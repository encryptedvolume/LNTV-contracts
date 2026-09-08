// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Rejector, ReentrantReceiver, ForceEther } from "./TestBase.sol";
import { Vm } from "forge-std/Vm.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract BatchBiddingTest is TestBase {
    function _batch(address bidder, uint256[] memory amounts) private returns (uint256[] memory) {
        uint256 total;
        for (uint256 i; i < amounts.length; ++i) {
            total += amounts[i];
        }
        vm.prank(bidder);
        return auction.createBids{ value: total }(amounts);
    }

    function _same(uint256 count, uint256 amount) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            amounts[i] = amount;
        }
    }

    function _pair(uint256 first, uint256 second) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = first;
        amounts[1] = second;
    }

    function _empty() private view {
        assertEq(auction.nextBidId(), 1);
        assertEq(auction.activeCount(), 0);
        assertEq(auction.head(), 0);
        assertEq(auction.tail(), 0);
        assertEq(auction.liabilities(), 0);
        assertEq(auction.endTime(), auction.initialEndTime());
    }

    function _unevenBook() private {
        place(alice, 1 ether);
        for (uint256 i; i < 89; ++i) {
            place(carol, 3 ether);
        }
    }

    function testDistinctBidAmountsOwnersIdsAndEvents() public {
        live();
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.15 ether;
        amounts[2] = 0.12 ether;
        uint256 balance = alice.balance;
        vm.recordLogs();
        uint256[] memory ids = _batch(alice, amounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(ids, range(3));
        assertEq(logs.length, 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(bid(ids[i]).bidder, alice);
            assertEq(bid(ids[i]).amount, amounts[i]);
            assertTrue(bid(ids[i]).active);
            assertEq(logs[i].emitter, address(auction));
            assertEq(logs[i].topics[0], keccak256("BidCreated(uint256,address,uint256)"));
            assertEq(uint256(logs[i].topics[1]), ids[i]);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), alice);
            assertEq(abi.decode(logs[i].data, (uint256)), amounts[i]);
        }
        assertEq(auction.head(), 2);
        assertEq(bid(2).next, 3);
        assertEq(bid(3).prev, 2);
        assertEq(bid(3).next, 1);
        assertEq(bid(1).prev, 3);
        assertEq(auction.tail(), 1);
        assertEq(auction.escrow(), 0.37 ether);
        assertEq(auction.liabilities(), 0.37 ether);
        assertEq(address(auction).balance, 0.37 ether);
        assertEq(balance - alice.balance, 0.37 ether);
    }

    function testSingleAndBatchShareIdsAndStableTiePriority() public {
        live();
        assertEq(place(bob, 2 ether), 1);
        assertEq(_batch(alice, _pair(2 ether, 3 ether)), _pair(2, 3));
        assertEq(place(carol, 2 ether), 4);
        (uint256[] memory ranks,) = auction.rankedBids(0, 90);
        assertEq(ranks[0], 3);
        assertEq(ranks[1], 1);
        assertEq(ranks[2], 2);
        assertEq(ranks[3], 4);
        assertEq(auction.escrow(), 9 ether);
    }

    function testOneElementBatchRetainsSingleBidBehavior() public {
        live();
        assertEq(_batch(bob, one(2 ether)), one(1));
        assertEq(bid(1).bidder, bob);
        assertEq(bid(1).amount, 2 ether);
        assertEq(auction.escrow(), 2 ether);
        finish();
        assertEq(auction.winningBidCost(1), 2 ether);
        vm.prank(bob);
        auction.claimTokens(one(1), alice);
        assertEq(edition.ownerOf(1), alice);
    }

    function testEmptyBatchRejected() public {
        live();
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        _batch(alice, new uint256[](0));
        _empty();
    }

    function testBatchOver90RejectedBeforeFundingOrBidding() public {
        live();
        vm.expectRevert(RankedAuction.InvalidBatch.selector);
        _batch(alice, _same(91, RESERVE));
        _empty();
        assertEq(address(auction).balance, 0);
    }

    function testUnderpaymentRevertsWholeBatch() public {
        live();
        vm.prank(alice);
        vm.expectRevert(RankedAuction.IncorrectPayment.selector);
        auction.createBids{ value: 3 ether - 1 }(_pair(1 ether, 2 ether));
        _empty();
    }

    function testOverpaymentRevertsWholeBatch() public {
        live();
        vm.prank(alice);
        vm.expectRevert(RankedAuction.IncorrectPayment.selector);
        auction.createBids{ value: 3 ether + 1 }(_pair(1 ether, 2 ether));
        _empty();
        assertEq(address(auction).balance, 0);
    }

    function testExistingEscrowCannotFundAnotherWalletsBatch() public {
        live();
        place(bob, 3 ether);
        vm.prank(alice);
        vm.expectRevert(RankedAuction.IncorrectPayment.selector);
        auction.createBids(_pair(1 ether, 2 ether));
        assertEq(auction.nextBidId(), 2);
        assertEq(bid(1).bidder, bob);
        assertEq(auction.escrow(), 3 ether);
        assertEq(address(auction).balance, 3 ether);
    }

    function testForcedSurplusCannotSubstituteForBatchPayment() public {
        live();
        vm.deal(address(this), 3 ether);
        new ForceEther{ value: 3 ether }(payable(address(auction)));
        vm.prank(alice);
        vm.expectRevert(RankedAuction.IncorrectPayment.selector);
        auction.createBids(_pair(1 ether, 2 ether));
        _empty();
        assertEq(address(auction).balance, 3 ether);
    }

    function testBatchBeforeStartRejectedThenAcceptedAtStart() public {
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        _batch(alice, _pair(RESERVE, RESERVE));
        _empty();
        live();
        assertEq(_batch(alice, _pair(RESERVE, RESERVE)), range(2));
    }

    function testBatchRejectedAtEndAndAfterSettlement() public {
        vm.warp(auction.endTime());
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        _batch(alice, _pair(RESERVE, RESERVE));
        auction.settle();
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        _batch(alice, _pair(RESERVE, RESERVE));
        assertEq(auction.nextBidId(), 1);
        assertEq(auction.pendingProceeds(), 0);
    }

    function testLateBatchExtendsOnceToTenMinutesFromTransaction() public {
        uint256 end = auction.endTime();
        vm.warp(end - 1);
        vm.recordLogs();
        _batch(alice, _same(5, RESERVE));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 6);
        assertEq(logs[0].topics[0], keccak256("AuctionExtended(uint256)"));
        assertEq(abi.decode(logs[0].data, (uint256)), end + 599);
        assertEq(auction.endTime(), end + 599);
        assertEq(auction.activeCount(), 5);
    }

    function testBatchAtExactExtensionWindowDoesNotMoveEnd() public {
        uint256 end = auction.endTime();
        vm.warp(end - 600);
        vm.recordLogs();
        _batch(alice, _pair(RESERVE, RESERVE));
        assertEq(vm.getRecordedLogs().length, 2);
        assertEq(auction.endTime(), end);
        vm.warp(end - 599);
        _batch(bob, _pair(RESERVE, RESERVE));
        assertEq(auction.endTime(), end + 1);
    }

    function testInvalidLastBidRollsBackIdsEscrowAndExtension() public {
        vm.warp(auction.endTime() - 1);
        uint256 balance = alice.balance;
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        _batch(alice, _pair(1 ether, 0));
        _empty();
        assertEq(alice.balance, balance);
        assertEq(address(auction).balance, 0);
        assertEq(bid(1).bidder, address(0));
        assertEq(_batch(alice, _pair(1 ether, RESERVE)), range(2));
    }

    function testNewFloorRejectsLaterBidAndRestoresDisplacedBid() public {
        live();
        _unevenBook();
        vm.warp(auction.endTime() - 1);
        uint256 balance = bob.balance;
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        _batch(bob, _pair(2 ether, 2 ether));
        assertEq(auction.nextBidId(), 91);
        assertEq(auction.tail(), 1);
        assertTrue(bid(1).active);
        assertFalse(bid(1).refundCredited);
        assertEq(bid(1).prev, 90);
        assertEq(bid(90).next, 1);
        assertEq(auction.refunds(alice), 0);
        assertEq(auction.totalRefunds(), 0);
        assertEq(auction.escrow(), 268 ether);
        assertEq(address(auction).balance, 268 ether);
        assertEq(bob.balance, balance);
        assertEq(auction.endTime(), auction.initialEndTime());
    }

    function testFillingLastSlotChangesMinimumWithinBatch() public {
        live();
        for (uint256 i; i < 89; ++i) {
            place(alice, RESERVE);
        }
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        _batch(bob, _pair(RESERVE, RESERVE));
        assertEq(auction.activeCount(), 89);
        assertEq(auction.nextBidId(), 90);
        assertEq(auction.refunds(alice), 0);
        assertEq(_batch(bob, _pair(RESERVE, RESERVE * 105 / 100)), _pair(90, 91));
        assertTrue(bid(90).refundCredited);
        assertFalse(bid(90).active);
        assertEq(auction.refunds(bob), RESERVE);
    }

    function testLaterBidCanDisplaceEarlierBatchBidAndRefundOriginalWallet() public {
        live();
        _unevenBook();
        assertEq(_batch(bob, _pair(2 ether, 2.1 ether)), _pair(91, 92));
        assertFalse(bid(91).active);
        assertTrue(bid(92).active);
        assertTrue(bid(91).refundCredited);
        assertEq(auction.refunds(alice), 1 ether);
        assertEq(auction.refunds(bob), 2 ether);
        assertEq(auction.totalRefunds(), 3 ether);
        assertEq(auction.escrow(), 269.1 ether);
        uint256 before = bob.balance;
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        assertEq(bob.balance - before, 2 ether);
        assertEq(auction.refunds(bob), 0);
        assertEq(auction.liabilities(), address(auction).balance);
    }

    function testWeiFloorRoundsUpSeparatelyForEveryBatchBid() public {
        RankedAuction.Config memory c = config();
        c.reservePrice = 1;
        auction = new RankedAuction(c);
        live();
        place(alice, 1);
        for (uint256 i; i < 89; ++i) {
            place(carol, 3);
        }
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        _batch(bob, _pair(2, 2));
        assertEq(_batch(bob, _pair(2, 3)), _pair(91, 92));
        assertEq(auction.refunds(alice), 1);
        assertEq(auction.refunds(bob), 2);
        assertEq(auction.minimumBid(), 4);
        assertEq(auction.escrow(), 270);
    }

    function testMaximumBatchRetainsNinetyIndependentWinsAndTenReserves() public {
        live();
        uint256[] memory ids = _batch(alice, _same(90, RESERVE));
        assertEq(ids, range(90));
        assertEq(auction.activeCount(), 90);
        assertEq(auction.head(), 1);
        assertEq(auction.tail(), 90);
        finish();
        vm.prank(alice);
        auction.claimTokens(ids, alice);
        vm.prank(payoutWallet);
        auction.claimReserved(10, payoutWallet);
        assertEq(edition.balanceOf(alice), 90);
        assertEq(edition.balanceOf(payoutWallet), 10);
        assertEq(edition.totalSupply(), 100);
        assertEq(auction.pendingProceeds(), 90 * RESERVE);
    }

    function testMultipleMaximumBatchesHaveNoWalletBidCap() public {
        live();
        _batch(alice, _same(90, RESERVE));
        uint256[] memory ids = _batch(alice, _same(90, RESERVE * 105 / 100));
        assertEq(ids[0], 91);
        assertEq(ids[89], 180);
        assertEq(auction.nextBidId(), 181);
        assertEq(auction.activeCount(), 90);
        assertEq(auction.refunds(alice), 90 * RESERVE);
        assertEq(auction.escrow(), 90 * RESERVE * 105 / 100);
        assertEq(auction.totalRefunds(), 90 * RESERVE);
        assertEq(auction.liabilities(), address(auction).balance);
    }

    function testBatchWinnerTopUpsClaimsAndTieredRefundsRemainIndependent() public {
        live();
        uint256[] memory ids = _batch(alice, _pair(1 ether, 2 ether));
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.increaseBid{ value: 2 ether }(1);
        vm.prank(alice);
        auction.increaseBid{ value: 2 ether }(1);
        finish();
        assertEq(bid(1).tokenId, 1);
        assertEq(bid(2).tokenId, 2);
        assertEq(auction.winningBidCost(1), 3 ether);
        assertEq(auction.winningBidCost(2), RESERVE);
        auction.creditRefunds(ids);
        assertEq(auction.refunds(alice), 2 ether - RESERVE);
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimTokens(ids, bob);
        vm.prank(alice);
        auction.claimTokens(ids, carol);
        assertEq(edition.balanceOf(carol), 2);
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        assertEq(auction.liabilities(), 0);
        assertEq(address(auction).balance, 0);
        assertEq(market.pendingRoyalties(), 0);
    }

    function testBatchRefundsStayOpenUntilRecoveryAfterSettlementDelay() public {
        live();
        uint256[] memory ids = _batch(alice, _pair(1 ether, 2 ether));
        vm.warp(auction.endTime() + 60 days);
        auction.settle();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.RecoveryNotAvailable.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        auction.creditRefunds(ids);
        assertEq(auction.refunds(alice), 1 ether - RESERVE);
        vm.warp(auction.settledAt() + 28 days);
        assertEq(auction.refunds(alice), 1 ether - RESERVE);
        vm.prank(payoutWallet);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertEq(auction.refunds(alice), 0);
        assertEq(auction.liabilities(), 0);
        vm.prank(alice);
        auction.claimTokens(ids, alice);
        assertEq(edition.balanceOf(alice), 2);
    }

    function testOversizedIndividualBidCannotTruncateInBatch() public {
        live();
        vm.expectRevert(RankedAuction.BidTooLarge.selector);
        _batch(alice, _pair(RESERVE, uint256(type(uint128).max) + 1));
        _empty();
        assertEq(address(auction).balance, 0);
    }

    function testTotalCanExceedUint128WhileEveryBidFits() public {
        live();
        uint256 maximum = type(uint128).max;
        _batch(alice, _pair(maximum, maximum));
        assertEq(auction.escrow(), maximum * 2);
        assertEq(bid(1).amount, maximum);
        assertEq(bid(2).amount, maximum);
        finish();
        auction.creditRefunds(range(2));
        assertEq(auction.pendingProceeds(), maximum + RESERVE);
        assertEq(auction.refunds(alice), maximum - RESERVE);
    }

    function testOverflowingInputSumRevertsBeforeAnyBid() public {
        live();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        auction.createBids(_pair(type(uint256).max, 1));
        _empty();
    }

    function testContractWalletOwnsBatchWithoutReceiverCallbacks() public {
        live();
        Rejector wallet = new Rejector();
        vm.deal(address(this), 3 ether);
        bytes memory returned = wallet.execute{ value: 3 ether }(
            address(auction), abi.encodeCall(auction.createBids, (_pair(1 ether, 2 ether)))
        );
        assertEq(abi.decode(returned, (uint256[])), range(2));
        assertEq(bid(1).bidder, address(wallet));
        assertEq(bid(2).bidder, address(wallet));
        finish();
        wallet.execute(address(auction), abi.encodeCall(auction.claimTokens, (range(2), alice)));
        assertEq(edition.balanceOf(alice), 2);
    }

    function testRefundCallbackCannotReenterBatchBidding() public {
        live();
        _unevenBook();
        _batch(bob, one(2 ether));
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.arm(address(auction), abi.encodeCall(auction.createBids, (new uint256[](0))), false);
        vm.prank(alice);
        auction.withdrawRefund(payable(address(receiver)));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(auction.nextBidId(), 92);
        assertEq(auction.refunds(alice), 0);
    }

    function testMintCallbackCannotReenterBatchBiddingWhileLive() public {
        live();
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.arm(address(auction), abi.encodeCall(auction.createBids, (new uint256[](0))), false);
        vm.prank(payoutWallet);
        auction.claimReserved(1, address(receiver));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(edition.ownerOf(91), address(receiver));
        assertEq(auction.nextBidId(), 1);
    }

    function testFuzzBatchMatchesSequentialBidding(uint96 seed, uint8 countSeed, uint8 initialSeed) public {
        live();
        uint256 initial = bound(initialSeed, 80, 90);
        for (uint256 i; i < initial; ++i) {
            place(bob, RESERVE + (i % 7) * RESERVE / 10);
        }
        vm.warp(auction.endTime() - 1);
        uint256 count = bound(countSeed, 1, 8);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            amounts[i] = 1 ether + uint256(keccak256(abi.encode(seed, i))) % 10 ether;
        }
        uint256 snapshot = vm.snapshotState();
        _batch(alice, amounts);
        bytes32 expected = _stateHash(initial + count);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        for (uint256 i; i < count; ++i) {
            place(alice, amounts[i]);
        }
        assertEq(_stateHash(initial + count), expected);
    }

    function testFuzzInvalidLaterBidRollsBackEveryWei(uint96 amountSeed, uint8 indexSeed) public {
        live();
        vm.warp(auction.endTime() - 1);
        uint256 count = bound(indexSeed, 2, 10);
        uint256[] memory amounts = _same(count, bound(amountSeed, RESERVE, 100 ether));
        amounts[count - 1] = RESERVE - 1;
        uint256 balance = alice.balance;
        vm.expectRevert(RankedAuction.BidTooLow.selector);
        _batch(alice, amounts);
        _empty();
        assertEq(alice.balance, balance);
        assertEq(address(auction).balance, 0);
    }

    function _stateHash(uint256 count) private view returns (bytes32 digest) {
        digest = keccak256(
            abi.encode(
                auction.nextBidId(),
                auction.activeCount(),
                auction.head(),
                auction.tail(),
                auction.escrow(),
                auction.totalRefunds()
            )
        );
        digest = keccak256(
            abi.encode(
                digest,
                auction.endTime(),
                auction.minimumBid(),
                auction.refunds(alice),
                auction.refunds(bob),
                address(auction).balance,
                alice.balance,
                bob.balance
            )
        );
        for (uint256 id = 1; id <= count; ++id) {
            digest = keccak256(abi.encode(digest, bid(id)));
        }
    }
}
