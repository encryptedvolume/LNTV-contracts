// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, ReentrantReceiver } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract TieredAllocationTest is TestBase {
    function testFixedSupplyAnd48HourDuration() public view {
        assertEq(auction.SUPPLY(), 90);
        assertEq(auction.RESERVED_SUPPLY(), 10);
        assertEq(edition.MAX_SUPPLY(), 100);
        assertEq(auction.AUCTION_DURATION(), 48 hours);
        assertEq(auction.initialEndTime(), uint256(auction.startTime()) + 48 hours);
        assertEq(auction.endTime(), auction.initialEndTime());
        assertEq(auction.reservedRemaining(), 10);
    }

    function testWinningCostOnlyExistsForSettledWinners() public {
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.winningBidCost(0);
        live();
        fill(alice, RESERVE);
        place(bob, 1 ether);
        finish();
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.winningBidCost(90);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.winningBidCost(0);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.winningBidCost(92);
        assertEq(auction.winningBidCost(91), 1 ether);
        assertEq(auction.winningBidCost(1), RESERVE);
    }

    function testTopPaysFullAndOthersPay90thWithIndependentRefunds() public {
        live();
        for (uint256 i; i < 88; ++i) {
            place(alice, 1 ether);
        }
        place(bob, 4 ether);
        place(bob, 10 ether);
        finish();
        assertEq(auction.clearingPrice(), 1 ether);
        assertEq(auction.pendingProceeds(), 99 ether);
        assertEq(auction.escrow(), 3 ether);
        assertEq(bid(90).tokenId, 1);
        assertEq(bid(89).tokenId, 2);
        auction.creditRefunds(one(90));
        assertEq(auction.refunds(bob), 0);
        auction.creditRefunds(one(89));
        assertEq(auction.refunds(bob), 3 ether);
        auction.creditRefunds(range(90));
        assertEq(auction.refunds(bob), 3 ether);
        assertEq(auction.escrow(), 0);
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        assertEq(address(auction).balance, 0);
    }

    function testTiedTopBidsUseOriginalBidPriorityAndDifferentCosts() public {
        live();
        place(alice, 3 ether);
        place(bob, 3 ether);
        finish();
        assertEq(bid(1).tokenId, 1);
        assertEq(bid(2).tokenId, 2);
        assertEq(auction.winningBidCost(1), 3 ether);
        assertEq(auction.winningBidCost(2), RESERVE);
        auction.creditRefunds(range(2));
        assertEq(auction.refunds(alice), 0);
        assertEq(auction.refunds(bob), 3 ether - RESERVE);
    }

    function testSingleWinnerPaysFullAndEmptyAuctionHasNoProceeds() public {
        live();
        place(alice, 7 ether);
        finish();
        assertEq(auction.pendingProceeds(), 7 ether);
        assertEq(auction.winningBidCost(1), 7 ether);
        auction.creditRefunds(one(1));
        assertEq(auction.escrow(), 0);
        assertEq(auction.refunds(alice), 0);
        RankedAuction empty = new RankedAuction(config());
        vm.warp(empty.endTime());
        empty.settle();
        assertEq(empty.pendingProceeds(), 0);
        assertEq(empty.unsoldRemaining(), 90);
    }

    function testReservedAllocationIndependentOfAuctionAndClaimOrder() public {
        vm.prank(payoutWallet);
        auction.claimReserved(3, payoutWallet);
        assertEq(edition.ownerOf(91), payoutWallet);
        assertEq(edition.ownerOf(93), payoutWallet);
        assertEq(auction.activeCount(), 0);
        assertEq(auction.minimumBid(), RESERVE);
        live();
        fill(alice, RESERVE);
        vm.prank(payoutWallet);
        auction.claimReserved(6, bob);
        assertEq(edition.ownerOf(94), bob);
        assertEq(edition.ownerOf(99), bob);
        assertEq(auction.reservedRemaining(), 1);
        finish();
        vm.prank(alice);
        auction.claimTokens(range(90), alice);
        vm.prank(payoutWallet);
        auction.claimReserved(1, carol);
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.ownerOf(90), alice);
        assertEq(edition.ownerOf(100), carol);
        assertEq(edition.totalSupply(), 100);
        assertEq(auction.tokensClaimed(), 90);
        assertEq(auction.reservedRemaining(), 0);
        assertEq(auction.unsoldRemaining(), 0);
        assertEq(auction.pendingProceeds(), 90 * RESERVE);
        assertEq(market.pendingRoyalties(), 0);
    }

    function testReservedValidationAndLifetimeLimit() public {
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimReserved(1, alice);
        vm.startPrank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.claimReserved(1, address(0));
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimReserved(0, alice);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimReserved(11, alice);
        auction.claimReserved(10, alice);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimReserved(1, alice);
        vm.stopPrank();
        assertEq(edition.totalSupply(), 10);
        assertEq(auction.liabilities(), 0);
    }

    function testRotationTransfersOnlyUnclaimedReservedEntitlements() public {
        vm.startPrank(payoutWallet);
        auction.claimReserved(4, payoutWallet);
        auction.proposePayoutWallet(bob);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimReserved(1, bob);
        vm.prank(bob);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimReserved(1, payoutWallet);
        vm.prank(bob);
        auction.claimReserved(6, bob);
        assertEq(edition.ownerOf(94), payoutWallet);
        assertEq(edition.ownerOf(95), bob);
        assertEq(edition.ownerOf(100), bob);
        assertEq(auction.reservedRemaining(), 0);
    }

    function testRejectedReservedBatchRollsBackAndCanBeRedirected() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.setRejectOnCall(2);
        vm.prank(payoutWallet);
        vm.expectRevert(bytes("rejected"));
        auction.claimReserved(3, address(receiver));
        assertEq(edition.totalSupply(), 0);
        assertEq(auction.reservedRemaining(), 10);
        vm.prank(payoutWallet);
        auction.claimReserved(10, bob);
        assertEq(edition.ownerOf(91), bob);
        assertEq(edition.ownerOf(100), bob);
    }

    function testReservedReceiverCannotReenterClaimsOrRotateWallet() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        receiver.execute(address(auction), abi.encodeCall(auction.acceptPayoutWallet, ()));
        receiver.arm(address(auction), abi.encodeCall(auction.claimReserved, (1, alice)), false);
        receiver.execute(address(auction), abi.encodeCall(auction.claimReserved, (1, address(receiver))));
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(auction.reservedRemaining(), 9);
        receiver.arm(address(auction), abi.encodeCall(auction.proposePayoutWallet, (bob)), false);
        receiver.execute(address(auction), abi.encodeCall(auction.claimReserved, (9, address(receiver))));
        assertFalse(receiver.succeeded());
        assertEq(auction.pendingPayoutWallet(), address(0));
        assertEq(edition.totalSupply(), 10);
    }
}
