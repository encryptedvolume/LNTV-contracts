// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";

/// @dev Independent sorted-array model: it neither follows nor mutates production linked-list pointers.
contract AuctionHandler is Test {
    RankedAuction public auction;
    address[8] public actors;
    uint256[] public modelIds;
    mapping(uint256 => uint256) public amounts;
    mapping(uint256 => address) public owners;
    mapping(address => uint256) public modelRefunds;
    uint256 public paidIn;
    uint256 public paidOut;
    uint256 public created;
    uint256 public modelEndTime;
    address public modelPayoutWallet;
    address public modelPendingWallet;
    uint256 public modelReservedClaimed;
    mapping(uint256 => address) public reservedOwners;

    constructor(RankedAuction auction_) {
        auction = auction_;
        modelEndTime = uint256(auction_.startTime()) + 2 days;
        modelPayoutWallet = auction_.payoutWallet();
        for (uint256 i; i < 8; ++i) {
            actors[i] = address(uint160(1000 + i));
            vm.deal(actors[i], 1e60);
        }
    }

    function seed(uint256 count) external {
        require(created == 0);
        for (uint256 i; i < count; ++i) {
            create(i, uint128(i * 1e16));
        }
    }

    function create(uint256 actorSeed, uint128 extra) public {
        address actor = actors[actorSeed % 8];
        uint256 amount = _minimumBid() + bound(extra, 0, 10 ether);
        if (amount > auction.MAX_BID()) return;
        vm.prank(actor);
        uint256 id = auction.createBid{ value: amount }();
        assertEq(id, ++created);
        paidIn += amount;
        amounts[id] = amount;
        owners[id] = actor;
        modelIds.push(id);
        _sort();
        if (modelIds.length > 90) {
            uint256 removed = modelIds[90];
            modelRefunds[owners[removed]] += amounts[removed];
            modelIds.pop();
        }
        _extendModel();
    }

    /// @dev Build bids against the independent evolving model, then execute them in one transaction.
    function createBatch(uint256 actorSeed, uint8 countSeed, uint128 extra) external {
        address actor = actors[actorSeed % 8];
        uint256 count = bound(countSeed, 1, 5);
        uint256[] memory batchAmounts = new uint256[](count);
        uint256[] memory expectedIds = new uint256[](count);
        uint256 total;
        for (uint256 i; i < count; ++i) {
            uint256 amount = _minimumBid() + bound(uint256(keccak256(abi.encode(extra, i))), 0, 10 ether);
            // The bounded campaign starts below 1 ETH and has only 256 actions.
            // Keep this as an assertion: a model overflow must fail the campaign, not leave partial state.
            assertLe(amount, auction.MAX_BID());
            batchAmounts[i] = amount;
            total += amount;
            uint256 id = ++created;
            expectedIds[i] = id;
            amounts[id] = amount;
            owners[id] = actor;
            modelIds.push(id);
            _sort();
            if (modelIds.length > 90) {
                uint256 removed = modelIds[90];
                modelRefunds[owners[removed]] += amounts[removed];
                modelIds.pop();
            }
        }
        vm.prank(actor);
        assertEq(auction.createBids{ value: total }(batchAmounts), expectedIds);
        paidIn += total;
        _extendModel();
    }

    function increase(uint256 rankSeed, uint128 extra) external {
        if (modelIds.length == 0) return;
        uint256 oldRank = rankSeed % modelIds.length;
        uint256 id = modelIds[oldRank];
        uint256 delta = (amounts[id] * 250 + 9999) / 10000 + bound(extra, 0, 10 ether);
        if (amounts[id] + delta > auction.MAX_BID()) return;
        vm.prank(owners[id]);
        auction.increaseBid{ value: delta }(id);
        amounts[id] += delta;
        paidIn += delta;
        _sort();
        if (modelIds[oldRank] != id) _extendModel();
    }

    /// @dev Explore late bids while remaining live; afterInvariant tests the exact modeled closing instant.
    function advance(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 0, modelEndTime - block.timestamp - 1));
    }

    function _minimumBid() private view returns (uint256) {
        if (modelIds.length < 90) return auction.reservePrice();
        uint256 floor = amounts[modelIds[modelIds.length - 1]];
        return floor + (floor * 500 + 9999) / 10000;
    }

    function _extendModel() private {
        if (modelEndTime < block.timestamp + 600) modelEndTime = block.timestamp + 600;
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[actorSeed % 8];
        uint256 amount = modelRefunds[actor];
        if (amount == 0) return;
        modelRefunds[actor] = 0;
        paidOut += amount;
        vm.prank(actor);
        auction.withdrawRefund(payable(actor));
    }

    function rotate(uint256 walletSeed, uint8 actionSeed) external {
        address candidate = actors[walletSeed % 8];
        uint8 action = actionSeed % 3;
        if (action == 0) {
            if (candidate == modelPayoutWallet) return;
            vm.prank(modelPayoutWallet);
            auction.proposePayoutWallet(candidate);
            modelPendingWallet = candidate;
        } else if (action == 1) {
            if (modelPendingWallet == address(0)) return;
            vm.prank(modelPendingWallet);
            auction.acceptPayoutWallet();
            modelPayoutWallet = modelPendingWallet;
            modelPendingWallet = address(0);
        } else {
            if (modelPendingWallet == address(0)) return;
            vm.prank(modelPayoutWallet);
            auction.cancelPayoutWalletChange();
            modelPendingWallet = address(0);
        }
    }

    function reserve(uint256 quantitySeed, uint256 recipientSeed) external {
        if (modelReservedClaimed == 10) return;
        uint256 quantity = bound(quantitySeed, 1, 10 - modelReservedClaimed);
        address recipient = actors[recipientSeed % 8];
        vm.prank(modelPayoutWallet);
        auction.claimReserved(quantity, recipient);
        for (uint256 i; i < quantity; ++i) {
            reservedOwners[91 + modelReservedClaimed + i] = recipient;
        }
        modelReservedClaimed += quantity;
    }

    function model() external view returns (uint256[] memory) {
        return modelIds;
    }

    function assertState() external view {
        assertEq(auction.endTime(), modelEndTime);
        assertEq(uint256(auction.phase()), uint256(RankedAuction.Phase.Live));
        assertEq(auction.minimumBid(), _minimumBid());
        assertEq(auction.payoutWallet(), modelPayoutWallet);
        assertEq(auction.pendingPayoutWallet(), modelPendingWallet);
        assertEq(auction.edition().royaltyRecipient(), modelPayoutWallet);
        (uint256[] memory actual, uint256 next) = auction.rankedBids(0, 90);
        assertEq(actual, modelIds);
        assertEq(next, 0);
        assertEq(auction.activeCount(), modelIds.length);
        assertEq(auction.head(), modelIds.length == 0 ? 0 : modelIds[0]);
        assertEq(auction.tail(), modelIds.length == 0 ? 0 : modelIds[modelIds.length - 1]);
        uint256 expectedEscrow;
        for (uint256 i; i < modelIds.length; ++i) {
            uint256 id = modelIds[i];
            (address owner, uint128 amount, uint256 prev, uint256 following, bool active,,, uint16 tokenId) =
                auction.bids(id);
            assertEq(owner, owners[id]);
            assertEq(amount, amounts[id]);
            assertTrue(active);
            assertEq(tokenId, 0);
            assertEq(prev, i == 0 ? 0 : modelIds[i - 1]);
            assertEq(following, i + 1 == modelIds.length ? 0 : modelIds[i + 1]);
            expectedEscrow += amount;
        }
        uint256 refundSum;
        for (uint256 i; i < 8; ++i) {
            assertEq(auction.refunds(actors[i]), modelRefunds[actors[i]]);
            refundSum += modelRefunds[actors[i]];
        }
        assertEq(auction.escrow(), expectedEscrow);
        assertEq(auction.totalRefunds(), refundSum);
        assertEq(auction.liabilities(), paidIn - paidOut);
        assertEq(address(auction).balance, paidIn - paidOut);
        assertEq(auction.edition().totalSupply(), modelReservedClaimed);
        assertEq(auction.reservedRemaining(), 10 - modelReservedClaimed);
        for (uint256 i; i < modelReservedClaimed; ++i) {
            assertEq(auction.edition().ownerOf(91 + i), reservedOwners[91 + i]);
        }
    }

    /// @dev Every campaign also settles and drains all legitimate liabilities and all 100 mint entitlements.
    function settleAndDrain() external {
        vm.warp(modelEndTime);
        auction.settle();
        uint256 expectedPrice = modelIds.length < 90 ? auction.reservePrice() : amounts[modelIds[modelIds.length - 1]];
        assertEq(auction.clearingPrice(), expectedPrice);
        uint256 expectedProceeds =
            modelIds.length == 0 ? 0 : amounts[modelIds[0]] + expectedPrice * (modelIds.length - 1);
        assertEq(auction.pendingProceeds(), expectedProceeds);
        assertEq(auction.edition().marketplace().pendingRoyalties(), 0);
        if (modelIds.length != 0) auction.creditRefunds(modelIds);
        assertEq(auction.escrow(), 0);
        for (uint256 i; i < modelIds.length; ++i) {
            uint256 id = modelIds[i];
            (,,,,,,, uint16 tokenId) = auction.bids(id);
            assertEq(tokenId, i + 1);
            uint256[] memory ids = new uint256[](1);
            ids[0] = id;
            vm.prank(owners[id]);
            auction.claimTokens(ids, owners[id]);
            assertEq(auction.edition().ownerOf(i + 1), owners[id]);
            modelRefunds[owners[id]] += i == 0 ? 0 : amounts[id] - expectedPrice;
            assertEq(auction.winningBidCost(id), i == 0 ? amounts[id] : expectedPrice);
        }
        for (uint256 i; i < 8; ++i) {
            address actor = actors[i];
            assertEq(auction.refunds(actor), modelRefunds[actor]);
            if (modelRefunds[actor] > 0) {
                vm.prank(actor);
                auction.withdrawRefund(payable(actor));
            }
        }
        address payoutWallet = auction.payoutWallet();
        if (auction.pendingProceeds() > 0) {
            vm.prank(payoutWallet);
            auction.withdrawProceeds(payable(payoutWallet));
        }
        uint256 unsold = auction.unsoldRemaining();
        if (unsold > 0) {
            vm.prank(payoutWallet);
            auction.claimUnsold(unsold, payoutWallet);
        }
        uint256 reserved = 10 - modelReservedClaimed;
        if (reserved > 0) {
            vm.prank(payoutWallet);
            auction.claimReserved(reserved, payoutWallet);
        }
        assertEq(auction.liabilities(), 0);
        assertEq(address(auction).balance, 0);
        assertEq(auction.edition().totalSupply(), 100);
    }

    function _sort() private {
        for (uint256 i = 1; i < modelIds.length; ++i) {
            uint256 key = modelIds[i];
            uint256 j = i;
            while (
                j > 0
                    && (amounts[modelIds[j - 1]] < amounts[key]
                        || (amounts[modelIds[j - 1]] == amounts[key] && modelIds[j - 1] > key))
            ) {
                modelIds[j] = modelIds[j - 1];
                --j;
            }
            modelIds[j] = key;
        }
    }
}

abstract contract AuctionInvariantBase is StdInvariant, Test {
    AuctionHandler internal handler;

    function initialize(uint256 initialBids) internal {
        vm.warp(1_000_000);
        RankedAuction auction = new RankedAuction(
            RankedAuction.Config(
                address(2001), 750, 0.01 ether, 1_000_100, "ipfs://invariant/", "Invariant NFTs", "INV"
            )
        );
        handler = new AuctionHandler(auction);
        vm.warp(auction.startTime());
        handler.seed(initialBids);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.create.selector;
        selectors[1] = handler.increase.selector;
        selectors[2] = handler.withdraw.selector;
        selectors[3] = handler.rotate.selector;
        selectors[4] = handler.reserve.selector;
        selectors[5] = handler.advance.selector;
        selectors[6] = handler.createBatch.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_matchesIndependentRankingAndConservesEveryWei() public view {
        handler.assertState();
    }

    function afterInvariant() public {
        handler.settleAndDrain();
    }
}

contract FullAuctionInvariantTest is AuctionInvariantBase {
    function setUp() public {
        initialize(90);
    }
}

contract GrowingAuctionInvariantTest is AuctionInvariantBase {
    function setUp() public {
        initialize(0);
    }
}
