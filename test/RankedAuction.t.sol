// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Rejector, ReentrantReceiver, ForceEther } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";

contract RankedAuctionTest is TestBase {
    function testConfigurationAndBindings() public view {
        assertEq(auction.SUPPLY(), 90);
        assertEq(auction.OUTBID_BPS(), 500);
        assertEq(auction.INCREASE_BPS(), 250);
        assertEq(auction.endTime(), auction.initialEndTime());
        assertEq(address(edition.auction()), address(auction));
        assertEq(market.edition(), address(edition));
        assertEq(edition.royaltyRecipient(), payoutWallet);
        assertEq(edition.totalSupply(), 0);
        assertEq(auction.minimumBid(), RESERVE);
        assertEq(uint256(auction.phase()), 0);
    }

    function testRejectBadAuctionConfiguration() public {
        RankedAuction.Config memory c = config();
        c.payoutWallet = address(0);
        vm.expectRevert(RankedAuction.InvalidPayoutWallet.selector);
        new RankedAuction(c);
        c = config();
        c.reservePrice = 0;
        vm.expectRevert(RankedAuction.InvalidConfiguration.selector);
        new RankedAuction(c);
        c = config();
        c.startTime = uint64(block.timestamp);
        vm.expectRevert(RankedAuction.InvalidConfiguration.selector);
        new RankedAuction(c);
    }

    function testRejectBadEditionConfiguration() public {
        RankedAuction.Config memory c = config();
        c.royaltyBps = 0;
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
        c = config();
        c.royaltyBps = 10001;
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
        c = config();
        c.metadataURI = "";
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
        c = config();
        c.collectionName = "";
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
        c = config();
        c.collectionSymbol = "";
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
    }

    function testExactTimeBoundaries() public {
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        place(alice, RESERVE);
        live();
        assertEq(uint256(auction.phase()), 1);
        place(alice, RESERVE);
        vm.warp(auction.endTime());
        assertEq(uint256(auction.phase()), 2);
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        place(alice, RESERVE);
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        vm.prank(alice);
        auction.increaseBid{ value: RESERVE }(1);
        auction.settle();
        assertEq(uint256(auction.phase()), 3);
    }

    function testFinalRankFixesTokenIdsRegardlessOfClaimOrder() public {
        live();
        place(alice, 2 ether);
        place(bob, 3 ether);
        place(alice, 1 ether);
        assertEq(bid(1).tokenId, 0);
        finish();
        assertEq(bid(2).tokenId, 1);
        assertEq(bid(1).tokenId, 2);
        assertEq(bid(3).tokenId, 3);
        vm.prank(alice);
        auction.claimTokens(one(3), carol);
        vm.prank(bob);
        auction.claimTokens(one(2), bob);
        vm.prank(alice);
        auction.claimTokens(one(1), alice);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(2), alice);
        assertEq(edition.ownerOf(3), carol);
        assertEq(edition.totalSupply(), 3);
    }

    function testUnsoldIdsCannotConsumeUnclaimedWinningNfts() public {
        live();
        place(alice, 2 ether);
        place(bob, 3 ether);
        finish();
        vm.prank(payoutWallet);
        auction.claimUnsold(38, carol);
        vm.prank(payoutWallet);
        auction.claimUnsold(50, carol);
        for (uint256 tokenId = 3; tokenId <= 90; ++tokenId) {
            assertEq(edition.ownerOf(tokenId), carol);
        }
        vm.expectRevert();
        edition.ownerOf(1);
        vm.expectRevert();
        edition.ownerOf(2);
        vm.prank(alice);
        auction.claimTokens(one(1), alice);
        vm.prank(bob);
        auction.claimTokens(one(2), bob);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(2), alice);
        assertEq(edition.totalSupply(), 90);
        assertEq(auction.unsoldRemaining(), 0);
    }

    function testRejectedLaterNftRollsBackEntireBatchAndCanBeRedirected() public {
        live();
        for (uint256 i; i < 3; ++i) {
            place(alice, RESERVE);
        }
        finish();
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.setRejectOnCall(3);
        vm.prank(alice);
        vm.expectRevert("rejected");
        auction.claimTokens(range(3), address(receiver));
        assertEq(edition.totalSupply(), 0);
        assertEq(auction.tokensClaimed(), 0);
        assertEq(receiver.calls(), 0);
        for (uint256 id = 1; id <= 3; ++id) {
            assertFalse(bid(id).tokenClaimed);
        }
        vm.prank(alice);
        auction.claimTokens(range(3), carol);
        for (uint256 id = 1; id <= 3; ++id) {
            assertEq(edition.ownerOf(id), carol);
        }
    }

    function testUnderReserveAndZeroBidsRejected() public {
        live();
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        place(alice, 0);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        place(alice, RESERVE - 1);
    }

    function testLargeBidCannotTruncate() public {
        live();
        vm.deal(alice, type(uint128).max + uint256(1));
        vm.expectRevert(RankedAuction.BidTooLarge.selector);
        place(alice, type(uint128).max + uint256(1));
        assertEq(auction.liabilities(), 0);
    }

    function testRankHeadMiddleTailAndStableTies() public {
        live();
        place(alice, 2 ether);
        place(bob, 4 ether);
        place(carol, 3 ether);
        place(alice, 2 ether);
        (uint256[] memory ids, uint256 next) = auction.rankedBids(0, 90);
        assertEq(ids.length, 4);
        assertEq(ids[0], 2);
        assertEq(ids[1], 3);
        assertEq(ids[2], 1);
        assertEq(ids[3], 4);
        assertEq(next, 0);
        assertEq(bid(3).prev, 2);
        assertEq(bid(3).next, 1);
    }

    function testPagination() public {
        live();
        place(alice, 3 ether);
        place(alice, 2 ether);
        place(alice, 1 ether);
        (uint256[] memory ids, uint256 next) = auction.rankedBids(0, 2);
        assertEq(ids, range(2));
        assertEq(next, 3);
        (ids, next) = auction.rankedBids(next, 2);
        assertEq(ids, one(3));
        assertEq(next, 0);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.rankedBids(0, 0);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.rankedBids(0, 91);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.rankedBids(999, 1);
    }

    function testEmptyPagination() public view {
        (uint256[] memory ids, uint256 next) = auction.rankedBids(0, 90);
        assertEq(ids.length, 0);
        assertEq(next, 0);
    }

    function testFullyAllocatedOutbidAndFullLoserRefund() public {
        live();
        fill(alice, RESERVE);
        uint256 min = auction.minimumBid();
        assertEq(min, RESERVE * 105 / 100);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        place(bob, RESERVE * 1025 / 1000);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        place(bob, min - 1);
        place(bob, min);
        assertFalse(bid(90).active);
        assertTrue(bid(90).refundCredited);
        assertEq(bid(90).prev, 0);
        assertEq(bid(90).next, 0);
        assertEq(auction.refunds(alice), RESERVE);
        assertEq(auction.activeCount(), 90);
        assertEq(auction.head(), 91);
        assertEq(auction.tail(), 89);
        vm.prank(alice);
        auction.withdrawRefund(payable(carol));
        assertEq(auction.refunds(alice), 0);
        assertEq(auction.liabilities(), address(auction).balance);
    }

    function testOneWalletCanWinAll90() public {
        live();
        fill(alice, 1 ether);
        finish();
        assertEq(auction.clearingPrice(), 1 ether);
        assertEq(auction.pendingProceeds(), 90 ether);
        vm.prank(alice);
        auction.claimTokens(range(90), alice);
        assertEq(edition.balanceOf(alice), 90);
        assertEq(edition.totalSupply(), 90);
        auction.creditRefunds(range(90));
        assertEq(auction.escrow(), 0);
        assertEq(auction.unsoldRemaining(), 0);
        vm.expectRevert(RankedAuction.AlreadyClaimed.selector);
        auction.claimTokens(one(1), alice);
    }

    function testIncreaseMaintainsSizeAndOriginalTiePriority() public {
        live();
        place(alice, 1 ether);
        place(bob, 2 ether);
        place(carol, 3 ether);
        vm.prank(alice);
        auction.increaseBid{ value: 1 ether }(1);
        assertEq(auction.head(), 3);
        assertEq(bid(3).next, 1);
        assertEq(bid(1).next, 2);
        vm.prank(alice);
        auction.increaseBid{ value: 2 ether }(1);
        assertEq(auction.head(), 1);
        assertEq(auction.tail(), 2);
        assertEq(auction.activeCount(), 3);
        assertEq(auction.escrow(), 9 ether);
    }

    function testSingleBidIncrease() public {
        live();
        place(alice, RESERVE);
        uint256 delta = auction.minimumIncrease(1);
        vm.prank(alice);
        auction.increaseBid{ value: delta }(1);
        assertEq(auction.head(), 1);
        assertEq(auction.tail(), 1);
        assertEq(bid(1).prev, 0);
        assertEq(bid(1).next, 0);
    }

    function testExistingBidRequiresTwoPointFivePercentRoundedUpAndCompounds() public {
        live();
        uint256 original = 1 ether + 1;
        place(alice, original);
        uint256 firstIncrease = 0.025 ether + 1;
        assertEq(auction.minimumIncrease(1), firstIncrease);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        vm.prank(alice);
        auction.increaseBid{ value: 0.005 ether + 1 }(1);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        vm.prank(alice);
        auction.increaseBid{ value: firstIncrease - 1 }(1);
        assertEq(bid(1).amount, original);
        assertEq(auction.escrow(), original);

        vm.prank(alice);
        auction.increaseBid{ value: firstIncrease }(1);
        uint256 secondIncrease = 0.025625 ether + 1;
        assertEq(auction.minimumIncrease(1), secondIncrease);
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        vm.prank(alice);
        auction.increaseBid{ value: firstIncrease }(1);
        vm.prank(alice);
        auction.increaseBid{ value: secondIncrease }(1);
        uint256 total = original + firstIncrease + secondIncrease;
        assertEq(bid(1).amount, total);
        assertEq(auction.escrow(), total);
        assertEq(auction.liabilities(), total);
        assertEq(address(auction).balance, total);
    }

    function testInvalidAndUnauthorizedIncrease() public {
        live();
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.increaseBid(1);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.minimumIncrease(1);
        place(alice, RESERVE);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.increaseBid{ value: RESERVE }(1);
        uint256 delta = auction.minimumIncrease(1) - 1;
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        vm.prank(alice);
        auction.increaseBid{ value: delta }(1);
    }

    function testOverflowIncreaseRejected() public {
        live();
        place(alice, type(uint128).max);
        vm.prank(alice);
        vm.expectRevert(RankedAuction.BidTooLarge.selector);
        auction.increaseBid{ value: 1 }(1);
    }

    function testDisplacedBidCannotBeIncreasedOrClaimed() public {
        live();
        fill(alice, RESERVE);
        place(bob, 1 ether);
        vm.prank(alice);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.increaseBid{ value: 1 ether }(90);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.rankedBids(90, 1);
        finish();
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.creditRefunds(one(90));
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.claimTokens(one(90), alice);
    }

    function testExtensionWindowContinuesBeyondTwoHours() public {
        live();
        vm.warp(auction.endTime() - 300);
        place(alice, RESERVE);
        assertEq(auction.endTime(), auction.initialEndTime());
        vm.warp(auction.endTime() - 299);
        place(alice, RESERVE);
        assertEq(auction.endTime(), auction.initialEndTime() + 1);
        for (uint256 i; i < 50; ++i) {
            vm.warp(auction.endTime() - 1);
            place(alice, auction.minimumBid());
            assertEq(auction.endTime(), block.timestamp + 300);
        }
        assertGt(auction.endTime(), uint256(auction.initialEndTime()) + 4 hours);
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        vm.warp(auction.endTime() - 1);
        place(bob, auction.minimumBid());
        assertEq(auction.endTime(), block.timestamp + 300);
        finish();
        assertTrue(auction.settled());
    }

    function testExtensionDoesNotTruncateAtUint64Boundary() public {
        RankedAuction.Config memory c = config();
        c.startTime = type(uint64).max - 1 days;
        auction = new RankedAuction(c);
        uint256 initialEnd = auction.initialEndTime();
        vm.warp(initialEnd - 1);
        place(alice, RESERVE);
        assertEq(auction.endTime(), initialEnd + 299);
        vm.warp(auction.endTime() - 1);
        place(bob, RESERVE);
        assertEq(auction.endTime(), initialEnd + 598);
        finish();
        assertTrue(auction.settled());
    }

    function testOnlyRankChangingIncreaseExtends() public {
        live();
        place(alice, 1 ether);
        place(bob, 2 ether);
        vm.warp(auction.endTime() - 1);
        vm.prank(bob);
        auction.increaseBid{ value: 1 ether }(2);
        assertEq(auction.endTime(), auction.initialEndTime());
        vm.prank(alice);
        auction.increaseBid{ value: 3 ether }(1);
        assertEq(auction.endTime(), block.timestamp + 300);
    }

    function testSettlementTimingAndSingleUse() public {
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        finish();
        vm.expectRevert(RankedAuction.AlreadySettled.selector);
        auction.settle();
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        place(alice, RESERVE);
    }

    function testEmptyAuctionAndUnsoldClaim() public {
        finish();
        assertEq(auction.clearingPrice(), RESERVE);
        assertEq(auction.unsoldRemaining(), 90);
        assertEq(auction.liabilities(), 0);
        vm.prank(payoutWallet);
        auction.claimUnsold(30, alice);
        vm.prank(payoutWallet);
        auction.claimUnsold(60, bob);
        assertEq(edition.totalSupply(), 90);
        assertEq(edition.balanceOf(bob), 60);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimUnsold(1, bob);
    }

    function testUnderSubscribedTieredReserveAndIndependentRefunds() public {
        live();
        place(alice, 1 ether);
        place(bob, 3 ether);
        finish();
        assertEq(auction.clearingPrice(), RESERVE);
        assertEq(auction.pendingProceeds(), 3 ether + RESERVE);
        assertEq(market.pendingRoyalties(), 0);
        auction.creditRefunds(range(2));
        assertEq(auction.refunds(alice), 1 ether - RESERVE);
        assertEq(auction.refunds(bob), 0);
        assertEq(auction.escrow(), 0);
        assertEq(auction.totalRefunds(), 1 ether - RESERVE);
        auction.creditRefunds(range(2));
        assertEq(auction.escrow(), 0);
        assertEq(edition.totalSupply(), 0);
    }

    function testSoldOutClearingIsLowestWinnerNotHighestLoser() public {
        live();
        fill(alice, 2 ether);
        place(bob, 3 ether);
        finish();
        assertEq(auction.clearingPrice(), 2 ether);
        auction.creditRefunds(one(91));
        assertEq(auction.refunds(bob), 0);
        assertEq(auction.refunds(alice), 2 ether);
    }

    function testTreasuryCannotConsumeRefunds() public {
        live();
        place(alice, 90 ether);
        place(bob, 100 ether);
        finish();
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        assertEq(address(auction).balance, 90 ether - RESERVE);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawProceeds(payable(payoutWallet));
        auction.creditRefunds(one(1));
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        assertEq(address(auction).balance, 0);
        assertEq(auction.liabilities(), 0);
        vm.prank(alice);
        auction.claimTokens(one(1), alice);
        assertEq(edition.balanceOf(alice), 1);
    }

    function testUnauthorisedClaimRedirectionAndPayouts() public {
        live();
        place(alice, 1 ether);
        finish();
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimTokens(one(1), bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawProceeds(payable(bob));
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimUnsold(1, bob);
        vm.prank(alice);
        auction.claimTokens(one(1), bob);
        assertEq(edition.balanceOf(bob), 1);
    }

    function testThirdPartyCannotForceDeliveryBeforeWinnerRedirects() public {
        live();
        place(alice, RESERVE);
        finish();
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimTokens(one(1), alice);
        assertFalse(bid(1).tokenClaimed);
        assertEq(edition.balanceOf(alice), 0);
        vm.prank(alice);
        auction.claimTokens(one(1), carol);
        assertEq(edition.balanceOf(carol), 1);
    }

    function testClaimsRequireSettlementAndValidBatches() public {
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.claimTokens(one(1), alice);
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.creditRefunds(one(1));
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.claimUnsold(1, alice);
        finish();
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.creditRefunds(new uint256[](0));
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimTokens(new uint256[](91), alice);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.claimTokens(one(1), address(0));
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.claimTokens(one(1), alice);
        vm.expectRevert(RankedAuction.InvalidBid.selector);
        auction.creditRefunds(one(1));
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.claimUnsold(1, address(0));
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        auction.claimUnsold(0, alice);
    }

    function testDuplicateTokenClaimRevertsWholeBatch() public {
        live();
        place(alice, RESERVE);
        finish();
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 1;
        vm.prank(alice);
        vm.expectRevert(RankedAuction.AlreadyClaimed.selector);
        auction.claimTokens(ids, alice);
        assertFalse(bid(1).tokenClaimed);
        assertEq(edition.totalSupply(), 0);
        auction.creditRefunds(ids);
        assertTrue(bid(1).refundCredited);
    }

    function testMixedOwnerBatchCannotBeStolen() public {
        live();
        place(alice, RESERVE);
        place(bob, RESERVE);
        finish();
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimTokens(range(2), alice);
        assertFalse(bid(1).tokenClaimed);
        assertEq(auction.tokensClaimed(), 0);
    }

    function testRejectingBidderCannotBlockBiddingSettlementOrRefunds() public {
        Rejector rejector = new Rejector();
        vm.deal(address(this), 10 ether);
        live();
        rejector.execute{ value: 1 ether }(address(auction), abi.encodeCall(auction.createBid, ()));
        place(bob, 2 ether);
        finish();
        vm.expectRevert();
        rejector.execute(address(auction), abi.encodeCall(auction.claimTokens, (one(1), address(rejector))));
        assertFalse(bid(1).tokenClaimed);
        auction.creditRefunds(one(1));
        vm.expectRevert(RankedAuction.TransferFailed.selector);
        rejector.execute(address(auction), abi.encodeCall(auction.withdrawRefund, (payable(address(rejector)))));
        assertEq(auction.refunds(address(rejector)), 1 ether - RESERVE);
        rejector.execute(address(auction), abi.encodeCall(auction.withdrawRefund, (payable(alice))));
        rejector.execute(address(auction), abi.encodeCall(auction.claimTokens, (one(1), alice)));
        assertEq(edition.balanceOf(alice), 1);
        assertEq(auction.refunds(address(rejector)), 0);
    }

    function testDisplacementNeverCallsRejectingBidder() public {
        Rejector rejector = new Rejector();
        live();
        vm.deal(address(this), 10 ether);
        rejector.execute{ value: RESERVE }(address(auction), abi.encodeCall(auction.createBid, ()));
        for (uint256 i; i < 89; ++i) {
            place(alice, 1 ether);
        }
        place(bob, 2 ether);
        assertEq(auction.refunds(address(rejector)), RESERVE);
        assertEq(auction.activeCount(), 90);
        finish();
    }

    function testRefundRecipientAndFailedProceedsValidation() public {
        live();
        place(alice, 1 ether);
        finish();
        auction.creditRefunds(one(1));
        vm.prank(alice);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.withdrawRefund(payable(address(0)));
        vm.prank(alice);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.withdrawRefund(payable(address(auction)));
        vm.prank(bob);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawRefund(payable(bob));
        Rejector rejector = new Rejector();
        uint256 proceeds = auction.pendingProceeds();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.TransferFailed.selector);
        auction.withdrawProceeds(payable(address(rejector)));
        assertEq(auction.pendingProceeds(), proceeds);
    }

    function testTokenCallbackCannotReenterClaims() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        live();
        place(alice, RESERVE);
        finish();
        receiver.arm(address(auction), abi.encodeCall(auction.claimTokens, (one(1), address(receiver))), false);
        vm.prank(alice);
        auction.claimTokens(one(1), address(receiver));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(edition.totalSupply(), 1);
    }

    function testRefundCallbackCannotDoubleWithdraw() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        vm.deal(address(this), 1 ether);
        live();
        receiver.execute{ value: 1 ether }(address(auction), abi.encodeCall(auction.createBid, ()));
        place(bob, 2 ether);
        finish();
        auction.creditRefunds(one(1));
        receiver.arm(address(auction), abi.encodeCall(auction.withdrawRefund, (payable(address(receiver)))), false);
        receiver.execute(address(auction), abi.encodeCall(auction.withdrawRefund, (payable(address(receiver)))));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(address(receiver).balance, 1 ether - RESERVE);
        assertEq(auction.refunds(address(receiver)), 0);
    }

    function testForcedEtherCannotAlterPricingOrBeStolen() public {
        vm.deal(address(this), 10 ether);
        new ForceEther{ value: 10 ether }(payable(address(auction)));
        live();
        place(alice, RESERVE);
        finish();
        assertEq(auction.clearingPrice(), RESERVE);
        assertEq(auction.liabilities(), RESERVE);
        assertEq(address(auction).balance, 10 ether + RESERVE);
    }

    function testUnsolicitedEtherRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(auction).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    function testOneWeiReserveHasStrictPositiveIncrements() public {
        RankedAuction.Config memory c = config();
        c.reservePrice = 1;
        auction = new RankedAuction(c);
        live();
        fill(alice, 1);
        assertEq(auction.minimumBid(), 2);
        assertEq(auction.minimumIncrease(1), 1);
        place(bob, 2);
        finish();
        assertEq(auction.clearingPrice(), 1);
    }

    function testMaximumFloorDoesNotOverflowAndCanSettle() public {
        live();
        vm.deal(alice, uint256(type(uint128).max) * 91);
        fill(alice, type(uint128).max);
        assertGt(auction.minimumBid(), type(uint128).max);
        finish();
        assertEq(auction.clearingPrice(), type(uint128).max);
        assertEq(auction.liabilities(), uint256(type(uint128).max) * 90);
    }

    function testFuzzTieredSettlement(uint128 a, uint128 b, uint8 countSeed) public {
        uint256 count = bound(countSeed, 1, 89);
        uint256 first = bound(a, RESERVE, 1000 ether);
        uint256 second = bound(b, RESERVE, 1000 ether);
        live();
        place(alice, first);
        for (uint256 i = 1; i < count; ++i) {
            place(bob, second);
        }
        finish();
        assertEq(auction.clearingPrice(), RESERVE);
        auction.creditRefunds(range(count));
        assertEq(auction.escrow(), 0);
        uint256 top = count == 1 || first >= second ? first : second;
        uint256 expectedProceeds = top + RESERVE * (count - 1);
        assertEq(auction.totalRefunds(), first + second * (count - 1) - expectedProceeds);
        assertEq(auction.pendingProceeds(), expectedProceeds);
        assertEq(auction.refunds(alice), count == 1 || first >= second ? 0 : first - RESERVE);
        assertEq(auction.liabilities(), address(auction).balance);
    }
}
