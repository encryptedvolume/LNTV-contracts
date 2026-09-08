// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, ReentrantReceiver } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";

/// @dev Independent lifecycle scenarios for regressions previously caught by one test or only config getters.
contract MutationBehaviorTest is TestBase {
    function testBiddingRemainsOpenAtHour47() public {
        uint256 start = auction.startTime();
        vm.warp(start + 47 hours);
        uint256 id = place(alice, 1 ether);
        vm.warp(start + 48 hours);
        auction.settle();
        vm.prank(alice);
        auction.claimTokens(one(id), carol);
        assertEq(edition.ownerOf(1), carol);
        assertEq(auction.pendingProceeds(), 1 ether);
    }

    function testSettlementCannotReleaseFundsAtHour24() public {
        live();
        place(alice, 1 ether);
        uint256 start = auction.startTime();
        vm.warp(start + 24 hours);
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        assertEq(auction.pendingProceeds(), 0);
        assertEq(auction.escrow(), 1 ether);
        vm.warp(start + 48 hours);
        auction.settle();
        uint256 before = carol.balance;
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(carol));
        assertEq(carol.balance - before, 1 ether);
        assertEq(auction.liabilities(), 0);
    }

    function testRankIncreasesKeepAuctionLiveBeyond24HourExtension() public {
        live();
        place(alice, RESERVE);
        place(bob, 2 * RESERVE);
        uint256 deadline = uint256(auction.startTime()) + 48 hours;
        uint256[2] memory amounts = [RESERVE, 2 * RESERVE];
        for (uint256 i; i < 146; ++i) {
            uint256 id = i % 2 + 1;
            uint256 other = id == 1 ? 2 : 1;
            uint256 extra = amounts[other - 1] + RESERVE - amounts[id - 1];
            uint256 minimumExtra = (amounts[id - 1] * 250 + 9999) / 10000;
            if (extra < minimumExtra) extra = minimumExtra;
            amounts[id - 1] += extra;
            vm.warp(deadline - 1);
            vm.prank(id == 1 ? alice : bob);
            auction.increaseBid{ value: extra }(id);
            deadline += 599;
        }
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        vm.warp(deadline);
        auction.settle();
        vm.prank(bob);
        auction.claimTokens(one(2), carol);
        assertEq(edition.ownerOf(1), carol);
        assertEq(auction.pendingProceeds(), amounts[1] + RESERVE);
    }

    function testRankIncreaseAcrossUint64BoundaryPreservesBiddingAndSettlement() public {
        RankedAuction.Config memory c = config();
        c.startTime = type(uint64).max - 2 days - 120;
        auction = new RankedAuction(c);
        live();
        place(alice, RESERVE);
        place(bob, 2 * RESERVE);
        vm.warp(uint256(c.startTime) + 48 hours - 1);
        vm.prank(alice);
        auction.increaseBid{ value: 2 * RESERVE }(1);
        uint256 afterBoundary = uint256(type(uint64).max) + 1;
        vm.warp(afterBoundary);
        vm.prank(bob);
        auction.increaseBid{ value: 2 * RESERVE }(2);
        vm.warp(afterBoundary + 599);
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        vm.warp(afterBoundary + 600);
        auction.settle();
        assertEq(auction.pendingProceeds(), 5 * RESERVE);
    }

    function testNewBidRoundsFivePercentUpBeforeDisplacingWeiPricedTail() public {
        RankedAuction.Config memory c = config();
        c.reservePrice = 1;
        auction = new RankedAuction(c);
        live();
        fill(alice, 41);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        place(bob, 43);
        assertTrue(bid(90).active);
        assertEq(auction.refunds(alice), 0);
        place(bob, 44);
        assertFalse(bid(90).active);
        vm.prank(alice);
        auction.withdrawRefund(payable(carol));
        finish();
        assertEq(auction.pendingProceeds(), 44 + 89 * 41);
        assertEq(auction.liabilities(), address(auction).balance);
    }

    function testInsufficientTopUpCannotChangeRankOrDelayClosing() public {
        live();
        fill(alice, 1 ether);
        uint256 deadline = uint256(auction.startTime()) + 48 hours;
        vm.warp(deadline - 10);
        vm.prank(alice);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        auction.increaseBid{ value: 0.01 ether }(90);
        assertEq(auction.head(), 1);
        assertEq(auction.endTime(), deadline);
        assertEq(auction.escrow(), 90 ether);
        vm.prank(alice);
        auction.increaseBid{ value: 0.025 ether }(90);
        vm.warp(deadline + 590);
        auction.settle();
        assertEq(auction.winningBidCost(90), 1.025 ether);
        assertEq(auction.pendingProceeds(), 90.025 ether);
    }

    function testPurchasedNftRequiresAnotherRoyaltyPayingSaleToTransferAgain() public {
        _sellReservedToBob();
        vm.prank(bob);
        vm.expectRevert(
            bytes4(keccak256("StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator()"))
        );
        edition.safeTransferFrom(bob, carol, 91);
        assertEq(edition.ownerOf(91), bob);
        assertEq(edition.transferNonce(91), 1);
        uint256 resale = _list(bob, 91, 2 ether);
        vm.prank(carol);
        market.buy{ value: 2 ether }(resale, carol);
        assertEq(edition.ownerOf(91), carol);
        assertEq(edition.transferNonce(91), 2);
        assertEq(market.pendingRoyalties(), 0.225 ether);
        assertEq(market.credits(bob), 1.85 ether);
    }

    function testFreePurchaseCannotSpendExistingSellerProceeds() public {
        mintForMarket();
        uint256 first = _list(alice, 1, 1 ether);
        uint256 second = _list(alice, 2, 2 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(first, bob);
        vm.prank(carol);
        vm.expectRevert(RoyaltyMarketplace.IncorrectPayment.selector);
        market.buy(second, carol);
        assertEq(edition.ownerOf(2), alice);
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        assertEq(market.totalCredits(), address(market).balance);
        vm.prank(carol);
        market.buy{ value: 2 ether }(second, carol);
        assertEq(edition.ownerOf(2), carol);
        assertEq(market.totalCredits(), 3 ether);
        assertEq(address(market).balance, 3 ether);
    }

    function testSellerCannotWithdrawTwiceUsingAnotherSellersBalance() public {
        _sellReservedToBob();
        uint256 resale = _list(bob, 91, 2 ether);
        vm.prank(carol);
        market.buy{ value: 2 ether }(resale, carol);
        vm.startPrank(alice);
        market.withdraw(payable(alice));
        vm.expectRevert(RoyaltyMarketplace.NothingToWithdraw.selector);
        market.withdraw(payable(alice));
        vm.stopPrank();
        uint256 before = bob.balance;
        vm.prank(bob);
        market.withdraw(payable(bob));
        assertEq(bob.balance - before, 1.85 ether);
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(carol));
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 0);
    }

    function testFormerSellerCannotCancelCurrentOwnersResale() public {
        _sellReservedToBob();
        uint256 resale = _list(bob, 91, 2 ether);
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.NotSeller.selector);
        market.cancel(resale);
        vm.prank(carol);
        market.buy{ value: 2 ether }(resale, carol);
        assertEq(edition.ownerOf(91), carol);
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.credits(bob), 1.85 ether);
    }

    function testInvalidNomineeCannotEraseUsablePayoutReplacement() public {
        live();
        place(alice, 1 ether);
        finish();
        vm.startPrank(payoutWallet);
        auction.proposePayoutWallet(bob);
        vm.expectRevert(RankedAuction.InvalidPayoutWallet.selector);
        auction.proposePayoutWallet(address(market));
        vm.stopPrank();
        vm.prank(bob);
        auction.acceptPayoutWallet();
        uint256 before = carol.balance;
        vm.prank(bob);
        auction.withdrawProceeds(payable(carol));
        assertEq(carol.balance - before, 1 ether);
        assertEq(edition.royaltyRecipient(), bob);
        assertEq(auction.liabilities(), 0);
    }

    function testRefundCreditDoesNotAuthorizeForcedBatchMint() public {
        live();
        place(bob, 3 ether);
        place(alice, 2 ether);
        place(alice, 1 ether);
        finish();
        uint256[] memory wins = new uint256[](2);
        wins[0] = 2;
        wins[1] = 3;
        auction.creditRefunds(wins);
        vm.prank(carol);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimTokens(wins, alice);
        assertEq(edition.totalSupply(), 0);
        assertEq(auction.tokensClaimed(), 0);
        uint256 before = alice.balance;
        vm.startPrank(alice);
        auction.withdrawRefund(payable(alice));
        auction.claimTokens(wins, carol);
        vm.stopPrank();
        assertEq(alice.balance - before, 3 ether - 2 * RESERVE);
        assertEq(edition.ownerOf(2), carol);
        assertEq(edition.ownerOf(3), carol);
    }

    function testMintReceiverCannotMintAnUnallocatedAuctionToken() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.arm(address(edition), abi.encodeCall(edition.mint, (carol, one(1))), false);
        vm.prank(payoutWallet);
        auction.claimReserved(1, address(receiver));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), AuctionEdition.Unauthorized.selector);
        assertEq(edition.totalSupply(), 1);
        assertEq(edition.ownerOf(91), address(receiver));
        live();
        uint256 id = place(alice, RESERVE);
        finish();
        vm.prank(alice);
        auction.claimTokens(one(id), carol);
        assertEq(edition.ownerOf(1), carol);
        assertEq(edition.totalSupply(), 2);
    }

    function testPurchasedNftApprovalDoesNotBypassRegistryAndClearsAfterResale() public {
        _sellReservedToBob();
        vm.prank(bob);
        edition.approve(alice, 91);
        assertEq(edition.getApproved(91), alice);
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer()")));
        edition.transferFrom(bob, alice, 91);
        uint256 resale = _list(bob, 91, 2 ether);
        vm.prank(carol);
        market.buy{ value: 2 ether }(resale, carol);
        assertEq(edition.ownerOf(91), carol);
        assertEq(edition.getApproved(91), address(0));
    }

    function testStandaloneEditionRequiresSeparatorForMintedTokenEndpoints() public {
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new AuctionEdition("Direct Edition", "DIR", "ipfs://direct-edition", 750);
        AuctionEdition direct = new AuctionEdition("Direct Edition", "DIR", "ipfs://direct-edition/", 750);
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 100;
        direct.mint(alice, ids);
        assertEq(direct.tokenURI(1), "ipfs://direct-edition/1.json");
        assertEq(direct.tokenURI(100), "ipfs://direct-edition/100.json");
        assertEq(direct.ownerOf(100), alice);
    }

    function _list(address seller, uint256 tokenId, uint128 price) private returns (uint256 id) {
        vm.startPrank(seller);
        edition.approve(address(market), tokenId);
        id = market.list(tokenId, price, uint64(block.timestamp + 1 days));
        vm.stopPrank();
    }

    function _sellReservedToBob() private {
        vm.prank(payoutWallet);
        auction.claimReserved(1, alice);
        uint256 id = _list(alice, 91, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
    }
}
