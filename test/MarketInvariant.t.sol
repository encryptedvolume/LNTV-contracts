// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { TradingTestSetup } from "./TradingTestSetup.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";

contract MarketHandler is Test {
    struct ModelListing {
        address seller;
        uint128 price;
        uint64 expiry;
        uint16 tokenId;
        bool active;
        uint256 nonce;
    }
    AuctionEdition public edition;
    RankedAuction public auction;
    RoyaltyMarketplace public market;
    address[8] public actors;
    address public modelPayoutWallet;
    address public modelPendingWallet;
    uint256 public royalties;
    mapping(address => uint256) public balances;
    mapping(uint256 => address) public owners;
    mapping(uint256 => uint256) public nonces;
    mapping(uint256 => bool) public tokenApproved;
    mapping(address => uint256) public credits;
    mapping(address => bool) public approved;
    mapping(uint256 => ModelListing) public listings;
    uint256 public listingCount;
    uint256 public totalIn;
    uint256 public totalOut;

    constructor(AuctionEdition edition_) {
        edition = edition_;
        market = edition.marketplace();
        auction = RankedAuction(edition.auction());
        modelPayoutWallet = edition.royaltyRecipient();
        for (uint256 i; i < 8; ++i) {
            address actor = address(uint160(3000 + i));
            actors[i] = actor;
            approved[actor] = true;
            vm.deal(actor, 1e50);
            vm.prank(actor);
            edition.setApprovalForAll(address(market), true);
        }
        balances[actors[0]] = 100;
        for (uint256 id = 1; id <= 100; ++id) {
            owners[id] = actors[0];
        }
    }

    function list(uint256 tokenSeed, uint128 priceSeed) external {
        uint16 tokenId = uint16(tokenSeed % 100 + 1);
        address actor = owners[tokenId];
        if (!approved[actor] && !tokenApproved[tokenId]) return;
        uint128 price = uint128(bound(priceSeed, 1, 10 ether));
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(actor);
        uint256 id = market.list(tokenId, price, expiry);
        assertEq(id, ++listingCount);
        listings[id] = ModelListing(actor, price, expiry, tokenId, true, nonces[tokenId]);
    }

    function buy(uint256 idSeed, uint256 buyerSeed, uint256 recipientSeed) external {
        if (listingCount == 0) return;
        uint256 id = idSeed % listingCount + 1;
        ModelListing storage item = listings[id];
        if (!item.active || block.timestamp >= item.expiry || item.nonce != nonces[item.tokenId]) return;
        if (!approved[item.seller] && !tokenApproved[item.tokenId]) return;
        address buyer = actors[buyerSeed % 8];
        address recipient = actors[recipientSeed % 8];
        uint256 payment = item.price;
        uint256 royalty = (payment * 750 + 9999) / 10000;
        vm.prank(buyer);
        market.buy{ value: payment }(id, recipient);
        item.active = false;
        balances[item.seller] -= 1;
        balances[recipient] += 1;
        owners[item.tokenId] = recipient;
        ++nonces[item.tokenId];
        tokenApproved[item.tokenId] = false;
        credits[item.seller] += payment - royalty;
        royalties += royalty;
        totalIn += payment;
    }

    function cancel(uint256 idSeed) external {
        if (listingCount == 0) return;
        uint256 id = idSeed % listingCount + 1;
        ModelListing storage item = listings[id];
        if (!item.active) return;
        vm.prank(item.seller);
        market.cancel(id);
        item.active = false;
    }

    function advance(uint32 secondsSeed) external {
        vm.warp(block.timestamp + uint256(secondsSeed) % 1 days);
    }

    function approveToken(uint256 tokenSeed, bool value) external {
        uint256 tokenId = tokenSeed % 100 + 1;
        vm.prank(owners[tokenId]);
        edition.approve(value ? address(market) : address(0), tokenId);
        tokenApproved[tokenId] = value;
    }

    function approval(uint256 actorSeed, bool value) external {
        address actor = actors[actorSeed % 8];
        vm.prank(actor);
        edition.setApprovalForAll(address(market), value);
        approved[actor] = value;
    }

    function withdraw(uint256 actorSeed) external {
        address actor = actors[actorSeed % 8];
        if (credits[actor] == 0) return;
        uint256 amount = credits[actor];
        credits[actor] = 0;
        totalOut += amount;
        vm.prank(actor);
        market.withdraw(payable(actor));
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

    function withdrawRoyalties() external {
        if (royalties == 0) return;
        totalOut += royalties;
        royalties = 0;
        vm.prank(modelPayoutWallet);
        market.withdrawRoyalties(payable(modelPayoutWallet));
    }

    function assertState() external view {
        assertEq(auction.payoutWallet(), modelPayoutWallet);
        assertEq(auction.pendingPayoutWallet(), modelPendingWallet);
        assertEq(edition.royaltyRecipient(), modelPayoutWallet);

        uint256 sum;
        uint256 currency = royalties;
        for (uint256 i; i < 8; ++i) {
            address actor = actors[i];
            sum += balances[actor];
            currency += credits[actor];
            assertEq(edition.balanceOf(actor), balances[actor]);
            assertEq(market.credits(actor), credits[actor]);
            assertEq(edition.isApprovedForAll(actor, address(market)), approved[actor]);
        }
        for (uint256 tokenId = 1; tokenId <= 100; ++tokenId) {
            assertEq(edition.ownerOf(tokenId), owners[tokenId]);
            assertEq(edition.transferNonce(tokenId), nonces[tokenId]);
            assertEq(edition.getApproved(tokenId), tokenApproved[tokenId] ? address(market) : address(0));
        }
        assertEq(market.pendingRoyalties(), royalties);
        assertEq(sum, 100);
        assertEq(edition.totalSupply(), 100);
        assertEq(currency, totalIn - totalOut);
        assertEq(market.totalCredits(), currency);
        assertEq(address(market).balance, currency);
        for (uint256 id = 1; id <= listingCount; ++id) {
            (address seller, uint128 price, uint64 expiry, uint16 tokenId, bool active, uint256 nonce) =
                market.listings(id);
            ModelListing storage expected = listings[id];
            assertEq(seller, expected.seller);
            assertEq(price, expected.price);
            assertEq(expiry, expected.expiry);
            assertEq(tokenId, expected.tokenId);
            assertEq(active, expected.active);
            assertEq(nonce, expected.nonce);
        }
    }

    function drain() external {
        for (uint256 i; i < 8; ++i) {
            this.withdraw(i);
        }
        this.withdrawRoyalties();
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 0);
    }
}

contract MarketInvariantTest is StdInvariant, TradingTestSetup {
    MarketHandler internal handler;

    function setUp() public {
        vm.warp(1_000_000);
        RankedAuction auction = new RankedAuction(
            RankedAuction.Config(
                address(4000), 750, 0.01 ether, 1_000_100, "ipfs://invariant/", "Invariant NFTs", "INV"
            )
        );
        configureTrading(auction.edition(), auction.payoutWallet());
        vm.warp(auction.endTime());
        auction.settle();
        vm.prank(address(4000));
        auction.claimUnsold(90, address(3000));
        vm.prank(address(4000));
        auction.claimReserved(10, address(3000));
        handler = new MarketHandler(auction.edition());
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.list.selector;
        selectors[1] = handler.buy.selector;
        selectors[2] = handler.cancel.selector;
        selectors[3] = handler.approval.selector;
        selectors[4] = handler.withdraw.selector;
        selectors[5] = handler.withdrawRoyalties.selector;
        selectors[6] = handler.rotate.selector;
        selectors[7] = handler.approveToken.selector;
        selectors[8] = handler.advance.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_marketConservesTokensAndEthAndPaysRoyalties() public view {
        handler.assertState();
    }

    function afterInvariant() public {
        handler.drain();
    }
}
