// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

/// @dev Payout wallet implemented as a contract: settles and recovers in ONE transaction.
contract PayoutBot {
    RankedAuction internal a;
    constructor(RankedAuction a_) { a = a_; }
    function accept() external { a.acceptPayoutWallet(); }
    function settleAndRecover() external { a.settle(); a.withdrawUnclaimedETH(payable(address(this))); }
    receive() external payable { }
}

/// @dev Independent audit proofs, 2026-09-08 (third Fable review, source 741b6805...). Not part of the package suite.
contract AuditFable3Test is TestBase {
    // PoC-A: recovery is anchored to endTime, not to settlement. If nobody settled during the 28 days,
    // a contract payout wallet can settle and sweep every winner overpayment in the same transaction,
    // so winners get zero blocks between settlement (when crediting first becomes possible) and closure.
    function testPoCA_SettleAndRecoverAtomicallyLeavesNoPostSettlementWindow() public {
        PayoutBot bot = new PayoutBot(auction);
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(bot));
        bot.accept();

        live();
        uint256 a1 = place(alice, 5 ether); // rank 1, pays full
        uint256 b1 = place(bob, 3 ether); // rank 2, pays reserve, 2.99 ETH overpayment
        uint256 c1 = place(carol, 1 ether); // rank 3, 0.99 ETH overpayment
        vm.warp(auction.endTime() + auction.RECOVERY_DELAY()); // nobody settled in 28 days

        // Winner overpayments cannot be credited before settlement.
        vm.expectRevert(RankedAuction.NotSettled.selector);
        auction.creditRefunds(one(b1));

        uint256 before = address(bot).balance;
        bot.settleAndRecover();
        assertTrue(auction.settled());
        assertTrue(auction.refundsClosed());
        assertEq(address(bot).balance - before, 9 ether, "all escrow incl. 3.98 ETH of winner overpayments swept");
        assertEq(auction.refunds(bob), 0);
        assertEq(auction.liabilities(), 0);
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.creditRefunds(one(b1));
        vm.prank(bob);
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.withdrawRefund(payable(bob));
        // NFT entitlements survive.
        vm.prank(bob);
        auction.claimTokens(one(b1), bob);
        assertEq(edition.ownerOf(2), bob);
        vm.prank(alice);
        auction.claimTokens(one(a1), alice);
        vm.prank(carol);
        auction.claimTokens(one(c1), carol);
        emit log_named_uint("overpayment swept from bob (wei)", 3 ether - auction.clearingPrice());
    }

    // PoC-A2: the same anchoring means a late settlement shrinks the crediting window to whatever is left.
    function testPoCA2_LateSettlementShrinksCreditWindow() public {
        live();
        place(alice, 5 ether);
        uint256 b1 = place(bob, 3 ether);
        uint256 end = auction.endTime();
        vm.warp(end + 27 days);
        auction.settle(); // first settlement, 27 days after close
        assertEq(auction.recoveryAvailableAt() - block.timestamp, 1 days, "one day left to credit and withdraw");
        vm.warp(end + 28 days);
        vm.prank(payoutWallet);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        vm.expectRevert(RankedAuction.RefundsClosed.selector);
        auction.creditRefunds(one(b1));
    }

    // PoC-B: N-02 economics refreshed for EXTENSION_WINDOW = 10 minutes (144 windows per day).
    function _stall(uint256 k, uint256 windows) internal returns (uint256 spent, uint256 gasTotal) {
        live();
        for (uint256 i; i < 90 - k; ++i) place(alice, 1 ether);
        for (uint256 i; i < k; ++i) place(bob, RESERVE);
        uint256 initialEnd = auction.endTime();
        for (uint256 w; w < windows; ++w) {
            uint256 lower = auction.tail();
            uint256 up = bid(lower).prev;
            uint256 delta = auction.minimumIncrease(lower);
            uint256 need = bid(up).amount > bid(lower).amount ? bid(up).amount - bid(lower).amount : 0;
            if (lower > up) need += 1;
            if (need > delta) delta = need;
            vm.warp(auction.endTime() - 1);
            vm.prank(bob);
            uint256 g = gasleft();
            auction.increaseBid{ value: delta }(lower);
            gasTotal += g - gasleft();
            assertEq(auction.endTime(), block.timestamp + 600, "every step extends by 10 min");
            spent += delta;
        }
        emit log_named_uint("k rotating tail bids", k);
        emit log_named_uint("windows (x10min)", windows);
        emit log_named_uint("seconds held open past initial end", auction.endTime() - initialEnd);
        emit log_named_uint("griefer wei added", spent);
        emit log_named_uint("griefer total commitment wei", spent + k * RESERVE);
        emit log_named_uint("final tail (= clearing price) wei", bid(auction.tail()).amount);
        emit log_named_uint("gas used by griefer", gasTotal);
    }

    function testPoCB_StallOneDayTwoTailBids() public { _stall(2, 144); }
    function testPoCB_StallOneDayTenTailBids() public { _stall(10, 144); }
    function testPoCB_StallTwoHoursTwoTailBids() public { _stall(2, 12); }

    // PoC-C: boundary at exactly ten minutes remaining does not extend; 599 s does.
    function testPoCC_ExtensionBoundaryTenMinutes() public {
        live();
        vm.warp(auction.endTime() - 600);
        place(alice, RESERVE);
        assertEq(auction.endTime(), auction.initialEndTime());
        vm.warp(auction.endTime() - 599);
        place(alice, RESERVE);
        assertEq(auction.endTime(), block.timestamp + 600);
        assertEq(auction.initialEndTime() - auction.startTime(), 48 hours);
    }

    // PoC-D: displaced-bid refunds are withdrawable during Live and are also subject to closure later.
    function testPoCD_DisplacedRefundWithdrawableDuringLiveAndSweptAfterRecovery() public {
        live();
        fill(alice, 1 ether);
        place(bob, 1.05 ether); // displaces alice's 90th bid
        assertEq(auction.refunds(alice), 1 ether);
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        assertEq(auction.refunds(alice), 0);
        place(carol, 1.1025 ether); // displaces another of alice's bids; alice never withdraws this one
        assertEq(auction.refunds(alice), 1 ether);
        finish();
        vm.warp(auction.recoveryAvailableAt());
        uint256 before = payoutWallet.balance;
        vm.prank(payoutWallet);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertEq(auction.refunds(alice), 0);
        assertGe(payoutWallet.balance - before, 1 ether, "alice's unwithdrawn displaced refund is part of the sweep");
    }

    // PoC-E: recovery sweeps proceeds too; only one event describes the whole amount.
    function testPoCE_RecoverySweepsProceedsWithoutProceedsEvent() public {
        live();
        place(alice, 2 ether);
        finish();
        vm.warp(auction.recoveryAvailableAt());
        assertEq(auction.pendingProceeds(), 2 ether);
        vm.prank(payoutWallet);
        auction.withdrawUnclaimedETH(payable(payoutWallet));
        assertEq(auction.pendingProceeds(), 0);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawProceeds(payable(payoutWallet));
    }
}
