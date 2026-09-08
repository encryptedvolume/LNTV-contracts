// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

abstract contract TestBase is Test {
    RankedAuction internal auction;
    AuctionEdition internal edition;
    RoyaltyMarketplace internal market;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);
    address public payoutWallet = address(0x71EA5);
    uint256 internal constant RESERVE = 0.01 ether;

    function setUp() public virtual {
        vm.warp(1_000_000);
        auction = new RankedAuction(config());
        edition = auction.edition();
        market = edition.marketplace();
        vm.deal(alice, 1e40);
        vm.deal(bob, 1e40);
        vm.deal(carol, 1e40);
    }

    function config() internal view returns (RankedAuction.Config memory) {
        return RankedAuction.Config(
            payoutWallet,
            750,
            uint128(RESERVE),
            uint64(block.timestamp + 1 hours),
            "ipfs://edition-metadata/",
            "The First Signal",
            "LNTV"
        );
    }

    function live() internal {
        vm.warp(auction.startTime());
    }

    function finish() internal {
        vm.warp(auction.endTime());
        auction.settle();
    }

    function place(address bidder, uint256 amount) internal returns (uint256) {
        vm.prank(bidder);
        return auction.createBid{ value: amount }();
    }

    function one(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }

    function range(uint256 count) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = i + 1;
        }
    }

    function bid(uint256 id) internal view returns (RankedAuction.Bid memory b) {
        (b.bidder, b.amount, b.prev, b.next, b.active, b.refundCredited, b.tokenClaimed, b.tokenId) = auction.bids(id);
    }

    function fill(address bidder, uint256 amount) internal {
        for (uint256 i; i < 90; ++i) {
            place(bidder, amount);
        }
    }

    function mintForMarket() internal {
        finish();
        vm.startPrank(auction.payoutWallet());
        auction.claimUnsold(90, alice);
        auction.claimReserved(10, alice);
        vm.stopPrank();
        vm.prank(alice);
        edition.setApprovalForAll(address(market), true);
    }
}

contract Rejector {
    function execute(address target, bytes calldata data) external payable returns (bytes memory) {
        (bool ok, bytes memory result) = target.call{ value: msg.value }(data);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
        return result;
    }
}

contract ReentrantReceiver is IERC721Receiver {
    address public target;
    bytes public payload;
    bool public attempted;
    bool public succeeded;
    bytes4 public lastError;
    bool public reject;
    uint256 public calls;
    uint256 public rejectOnCall;

    function arm(address target_, bytes memory payload_, bool reject_) external {
        target = target_;
        payload = payload_;
        reject = reject_;
        attempted = false;
        calls = 0;
        succeeded = false;
    }

    function execute(address target_, bytes calldata data) external payable {
        (bool ok, bytes memory result) = target_.call{ value: msg.value }(data);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }

    function setRejectOnCall(uint256 value) external {
        rejectOnCall = value;
    }

    function attack() internal {
        ++calls;
        attempted = true;
        bytes memory result;
        (succeeded, result) = target.call(payload);
        lastError = result.length >= 4 ? bytes4(result) : bytes4(0);
        require(!reject && (rejectOnCall == 0 || calls != rejectOnCall), "rejected");
    }

    receive() external payable {
        attack();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        attack();
        return this.onERC721Received.selector;
    }
}

contract ForceEther {
    constructor(address payable to) payable {
        selfdestruct(to);
    }
}
