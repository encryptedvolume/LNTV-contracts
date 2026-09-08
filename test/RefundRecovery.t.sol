// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Rejector, ReentrantReceiver, ForceEther } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract RefundRecoveryTest is TestBase {
    event UnclaimedETHWithdrawn(address indexed recipient, uint256 amount);

    function _book() internal {
        live();
        fill(alice, 1 ether);
        place(bob, 5 ether);
        place(carol, 3 ether);
        place(bob, 2 ether);
    }

    function _fund() internal {
        _book();
        finish();
        auction.creditRefunds(one(92));
        assertEq(auction.pendingProceeds(), 94 ether);
        assertEq(auction.totalRefunds(), 5 ether);
        assertEq(auction.escrow(), 1 ether);
    }

    function _availableAt() internal view returns (uint256) {
        return auction.endTime() + 28 days;
    }

    function _recover(address recipient) internal {
        vm.prank(auction.payoutWallet());
        auction.withdrawUnclaimedETH(payable(recipient));
    }

    function _assertDrained() internal view {
        assertEq(address(auction).balance, 0);
        assertEq(auction.escrow(), 0);
        assertEq(auction.totalRefunds(), 0);
        assertEq(auction.pendingProceeds(), 0);
        assertEq(auction.liabilities(), 0);
        assertEq(auction.refunds(alice), 0);
        assertEq(auction.refunds(bob), 0);
        assertEq(auction.refunds(carol), 0);
    }

    function testRecoveryTransfersCreditedUncreditedRefundsAndProceeds() public {
        _fund();
        vm.warp(_availableAt());
        assertEq(auction.recoveryAvailableAt(), block.timestamp);
        assertEq(auction.RECOVERY_DELAY(), 28 days);
        uint256 before = alice.balance;
        vm.expectEmit(true, false, false, true, address(auction));
        emit UnclaimedETHWithdrawn(alice, 100 ether);
        _recover(alice);
        assertEq(alice.balance - before, 100 ether);
        _assertDrained();
    }

    function testRecoveryAfterProceedsAndPartialRefundsIncludesForcedSurplus() public {
        _fund();
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        vm.deal(address(this), 12);
        new ForceEther{ value: 5 }(payable(address(auction)));
        vm.warp(_availableAt());
        uint256 before = bob.balance;
        _recover(bob);
        assertEq(bob.balance - before, 4 ether + 5);
        _assertDrained();
        new ForceEther{ value: 7 }(payable(address(auction)));
        _recover(bob);
        assertEq(bob.balance - before, 4 ether + 12);
        _assertDrained();
    }

    function testRefundsCanBeCreditedAndWithdrawnBeforeRecoveryEligibility() public {
        _fund();
        vm.warp(_availableAt() - 1);
        assertEq(auction.refunds(alice), 3 ether);
        assertEq(auction.refunds(carol), 2 ether);
        auction.creditRefunds(one(93));
        assertEq(auction.refunds(bob), 1 ether);
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        assertEq(address(auction).balance, 94 ether);
        vm.warp(_availableAt());
        _recover(payoutWallet);
        _assertDrained();
    }

    function testCreditingRemainsAvailableAtRecoveryEligibility() public {
        _fund();
        vm.warp(_availableAt());
        assertFalse(auction.refundsClosed());
        auction.creditRefunds(one(93));
        assertEq(auction.refunds(bob), 1 ether);
        assertEq(auction.escrow(), 0);
        assertEq(auction.totalRefunds(), 6 ether);
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        _recover(payoutWallet);
        assertTrue(auction.refundsClosed());
        _assertDrained();
    }

    function testWithdrawingRemainsAvailableAtRecoveryEligibility() public {
        _fund();
        vm.warp(_availableAt());
        assertFalse(auction.refundsClosed());
        assertEq(auction.refunds(alice), 3 ether);
        assertEq(auction.refunds(carol), 2 ether);
        uint256 before = alice.balance;
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        assertEq(alice.balance - before, 3 ether);
        assertEq(auction.totalRefunds(), 2 ether);
        uint256 payoutBefore = payoutWallet.balance;
        _recover(payoutWallet);
        assertEq(payoutWallet.balance - payoutBefore, 97 ether);
        assertTrue(auction.refundsClosed());
        _assertDrained();
    }

    function testYearsOfInactionDoNotCloseRefunds() public {
        _fund();
        vm.warp(_availableAt() + 10 * 365 days);
        assertFalse(auction.refundsClosed());
        auction.creditRefunds(one(93));
        assertEq(auction.refunds(bob), 1 ether);
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        assertEq(auction.refunds(carol), 2 ether);
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        assertEq(address(auction).balance, 97 ether);
        assertEq(auction.totalRefunds(), 3 ether);
        assertFalse(auction.refundsClosed());
    }

    function testNormalProceedsWithdrawalDoesNotCloseRefunds() public {
        _fund();
        vm.warp(_availableAt() + 365 days);
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        assertFalse(auction.refundsClosed());
        auction.creditRefunds(one(93));
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        assertEq(auction.refunds(alice), 3 ether);
        assertEq(address(auction).balance, 3 ether);
        _recover(payoutWallet);
        assertTrue(auction.refundsClosed());
        _assertDrained();
    }

    function testRecoveryClosesRefundsBeforeRecipientCallback() public {
        _fund();
        vm.warp(_availableAt());
        RefundStateObserver observer = new RefundStateObserver(auction, carol);
        _recover(address(observer));
        assertTrue(observer.sawClosed());
        assertEq(observer.seenCredit(), 0);
        assertEq(observer.seenLiabilities(), 0);
        assertTrue(auction.refundsClosed());
        _assertDrained();
    }

    function testCreditedRefundsCannotBeWithdrawnAfterRecovery() public {
        _fund();
        vm.warp(_availableAt());
        _recover(payoutWallet);
        vm.prank(carol);
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.withdrawRefund(payable(carol));
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.creditRefunds(one(92));
        _assertDrained();
    }

    function testUncreditedRefundsCannotRecreateLiabilitiesAfterRecovery() public {
        _fund();
        vm.warp(_availableAt() + 365 days);
        _recover(payoutWallet);
        assertFalse(bid(93).refundCredited);
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.creditRefunds(one(93));
        _assertDrained();
    }

    function testRecoveryRejectsEarlyCallsWithoutFreezingRefunds() public {
        _fund();
        vm.warp(auction.endTime() + 27 days);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.RecoveryNotAvailable.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        vm.warp(_availableAt() - 1);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.RecoveryNotAvailable.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        assertEq(auction.totalRefunds(), 3 ether);
    }

    function testLateSettlementDoesNotRestartTheRecoveryDelay() public {
        _book();
        vm.warp(_availableAt());
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        auction.settle();
        auction.creditRefunds(one(92));
        assertEq(auction.refunds(carol), 2 ether);
        assertFalse(auction.refundsClosed());
        uint256 before = payoutWallet.balance;
        _recover(payoutWallet);
        assertEq(payoutWallet.balance - before, 100 ether);
        _assertDrained();
    }

    function testRecoveryEligibilityFollowsTheExtendedEnd() public {
        _book();
        uint256 originalEnd = auction.endTime();
        vm.warp(originalEnd - 1);
        vm.prank(alice);
        auction.increaseBid{ value: 0.05 ether }(87);
        assertEq(auction.endTime(), originalEnd + 599);
        finish();
        vm.warp(originalEnd + 28 days);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.RecoveryNotAvailable.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertEq(auction.refunds(alice), 3 ether);
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        vm.warp(originalEnd + 599 + 28 days);
        _recover(payoutWallet);
        _assertDrained();
    }

    function testExtendedRefundCanBeCreditedAtOriginalEligibilityTime() public {
        _book();
        uint256 originalEnd = auction.endTime();
        vm.warp(originalEnd - 1);
        place(bob, auction.minimumBid());
        finish();
        vm.warp(originalEnd + 28 days);
        auction.creditRefunds(one(92));
        assertEq(auction.refunds(carol), 2 ether);
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.RecoveryNotAvailable.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        vm.warp(originalEnd + 599 + 28 days);
        _recover(payoutWallet);
        _assertDrained();
    }

    function testUnsettledRecoveryCannotEraseWinnerAllocation() public {
        live();
        place(alice, 3 ether);
        vm.warp(_availableAt() + 1);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertEq(auction.escrow(), 3 ether);
        assertEq(bid(1).tokenId, 0);
        auction.settle();
        _recover(payoutWallet);
        vm.prank(alice);
        auction.claimTokens(one(1), alice);
        assertEq(edition.ownerOf(1), alice);
        _assertDrained();
    }

    function testOnlyCurrentPayoutWalletCanRecoverNotOriginalDeployer() public {
        _fund();
        vm.warp(_availableAt());
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawUnclaimedETH(payable(address(this)));
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawUnclaimedETH(payable(alice));
        _recover(payoutWallet);
        _assertDrained();
    }

    function testRecoveryAuthorityFollowsAcceptedWalletRotation() public {
        _fund();
        vm.warp(_availableAt());
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(bob);
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawUnclaimedETH(payable(bob));
        vm.prank(bob);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        uint256 before = carol.balance;
        _recover(carol);
        assertEq(carol.balance - before, 100 ether);
        _assertDrained();
    }

    function testRejectedRecoveryPreservesAllAccountingForRetry() public {
        _fund();
        vm.warp(_availableAt());
        Rejector rejector = new Rejector();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.TransferFailed.selector);
        auction.withdrawUnclaimedETH(payable(address(rejector)));
        assertEq(auction.escrow(), 1 ether);
        assertEq(auction.totalRefunds(), 5 ether);
        assertEq(auction.pendingProceeds(), 94 ether);
        assertEq(address(auction).balance, 100 ether);
        assertFalse(auction.refundsClosed());
        assertEq(auction.refunds(carol), 2 ether);
        auction.creditRefunds(one(93));
        vm.prank(carol);
        auction.withdrawRefund(payable(carol));
        vm.prank(bob);
        auction.withdrawRefund(payable(bob));
        assertEq(address(auction).balance, 97 ether);
        _recover(payoutWallet);
        _assertDrained();
    }

    function testRecoveryRejectsInvalidRecipientsAndEmptyRepeat() public {
        _fund();
        vm.warp(_availableAt());
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.withdrawUnclaimedETH(payable(address(0)));
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.InvalidRecipient.selector);
        auction.withdrawUnclaimedETH(payable(address(auction)));
        assertFalse(auction.refundsClosed());
        assertEq(auction.refunds(alice), 3 ether);
        _recover(payoutWallet);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        _assertDrained();
    }

    function _receiverPayout() internal returns (ReentrantReceiver receiver) {
        receiver = new ReentrantReceiver();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        vm.prank(address(receiver));
        auction.acceptPayoutWallet();
        vm.warp(_availableAt());
    }

    function testRecoveryCannotReenterRecovery() public {
        _fund();
        ReentrantReceiver receiver = _receiverPayout();
        bytes memory payload = abi.encodeCall(auction.withdrawUnclaimedETH, (payable(address(receiver))));
        receiver.arm(address(auction), payload, false);
        receiver.execute(address(auction), payload);
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(address(receiver).balance, 100 ether);
        _assertDrained();
    }

    function testRecoveryCannotNominateAnotherWalletDuringCallback() public {
        _fund();
        ReentrantReceiver receiver = _receiverPayout();
        receiver.arm(address(auction), abi.encodeCall(auction.proposePayoutWallet, (alice)), false);
        receiver.execute(address(auction), abi.encodeCall(auction.withdrawUnclaimedETH, (payable(address(receiver)))));
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(auction.pendingPayoutWallet(), address(0));
        _assertDrained();
    }

    function testRecoveryLeavesWinningNFTsAndTradingCreditsAvailable() public {
        _fund();
        vm.startPrank(carol);
        auction.claimTokens(one(92), carol);
        edition.setApprovalForAll(address(market), true);
        uint256 listing = market.list(2, 1 ether, uint64(_availableAt() + 1 days));
        vm.stopPrank();
        vm.prank(alice);
        market.buy{ value: 1 ether }(listing, alice);
        vm.warp(_availableAt());
        _recover(payoutWallet);
        assertEq(market.credits(carol), 0.925 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        vm.startPrank(bob);
        auction.claimTokens(one(91), bob);
        auction.claimTokens(one(93), bob);
        vm.stopPrank();
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(3), bob);
        vm.prank(carol);
        market.withdraw(payable(carol));
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(payoutWallet));
        assertEq(address(market).balance, 0);
        _assertDrained();
    }

    function testRecoveryPreservesUnsoldAndReservedMintEntitlements() public {
        live();
        place(alice, 1 ether);
        place(bob, 2 ether);
        finish();
        vm.warp(_availableAt());
        _recover(payoutWallet);
        vm.prank(alice);
        auction.claimTokens(one(1), alice);
        vm.prank(bob);
        auction.claimTokens(one(2), bob);
        vm.startPrank(payoutWallet);
        auction.claimUnsold(88, carol);
        auction.claimReserved(10, carol);
        vm.stopPrank();
        assertEq(edition.totalSupply(), 100);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(2), alice);
        _assertDrained();
    }

    function testEmptyAuctionRecoveryCollectsOnlyForcedETH() public {
        finish();
        vm.warp(_availableAt());
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertFalse(auction.refundsClosed());
        vm.deal(address(this), 123);
        new ForceEther{ value: 123 }(payable(address(auction)));
        uint256 before = carol.balance;
        _recover(carol);
        assertEq(carol.balance - before, 123);
        _assertDrained();
    }

    function testFuzzRecoveryConservesClaimedRefundsAndRemainingETH(uint96 forcedSeed, uint8 claims, uint32 delay)
        public
    {
        _fund();
        uint256 forced = bound(uint256(forcedSeed), 0, 1 ether);
        vm.deal(address(this), forced);
        new ForceEther{ value: forced }(payable(address(auction)));
        uint256 paid;
        vm.warp(_availableAt() + uint256(delay));
        assertFalse(auction.refundsClosed());
        if (claims & 1 != 0) auction.creditRefunds(one(93));
        if (claims & 2 != 0) {
            vm.prank(alice);
            auction.withdrawRefund(payable(alice));
            paid += 3 ether;
        }
        if (claims & 4 != 0) {
            vm.prank(carol);
            auction.withdrawRefund(payable(carol));
            paid += 2 ether;
        }
        if (claims & 9 == 9) {
            vm.prank(bob);
            auction.withdrawRefund(payable(bob));
            paid += 1 ether;
        }
        if (claims & 16 != 0) {
            vm.prank(payoutWallet);
            auction.withdrawProceeds(payable(payoutWallet));
            paid += 94 ether;
        }
        uint256 before = carol.balance;
        if (100 ether + forced == paid) {
            vm.prank(payoutWallet);
            vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
            auction.withdrawUnclaimedETH(payable(carol));
            assertFalse(auction.refundsClosed());
        } else {
            _recover(carol);
            assertTrue(auction.refundsClosed());
        }
        assertEq(carol.balance - before + paid, 100 ether + forced);
        _assertDrained();
    }
}

contract RefundStateObserver {
    RankedAuction private immutable auction;
    address private immutable bidder;
    bool public sawClosed;
    uint256 public seenCredit;
    uint256 public seenLiabilities;

    constructor(RankedAuction auction_, address bidder_) {
        auction = auction_;
        bidder = bidder_;
    }

    receive() external payable {
        sawClosed = auction.refundsClosed();
        seenCredit = auction.refunds(bidder);
        seenLiabilities = auction.liabilities();
    }
}
