// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";

contract DeploymentRoyaltyAuditTest is Test {
    function testDeploymentRejectsRateThatTradingSetupCannotAccept() public {
        vm.chainId(31337);
        Deploy deployment = new Deploy();
        Deploy.DeploymentConfig memory input = Deploy.DeploymentConfig(
            31337, block.timestamp + 1 hours, 0.01 ether, 750, address(0x123), "ipfs://audit/", "Audit", "AUD"
        );
        vm.expectRevert("LNTV deployment requires 10 percent royalties");
        deployment.validateConfig(input);
    }
}

/// @dev Independently sort bid records without following the contract's linked list.
contract RankedLinksAuditTest is TestBase {
    function assertIndependentOrder() internal view {
        uint256 allocated = auction.nextBidId() - 1;
        uint256[] memory expected = new uint256[](allocated);
        uint256 count;
        uint256 sum;
        for (uint256 id = 1; id <= allocated; ++id) {
            RankedAuction.Bid memory b = bid(id);
            if (b.active) {
                expected[count++] = id;
                sum += b.amount;
            } else {
                assertEq(b.prev, 0);
                assertEq(b.next, 0);
            }
        }
        // Selection sort is independent of the linked-list insertion algorithm.
        for (uint256 i; i < count; ++i) {
            uint256 best = i;
            for (uint256 j = i + 1; j < count; ++j) {
                uint256 a = bid(expected[j]).amount;
                uint256 b = bid(expected[best]).amount;
                if (a > b || (a == b && expected[j] < expected[best])) best = j;
            }
            (expected[i], expected[best]) = (expected[best], expected[i]);
        }
        assertEq(auction.activeCount(), count);
        assertEq(auction.escrow(), sum);
        assertEq(auction.head(), count == 0 ? 0 : expected[0]);
        assertEq(auction.tail(), count == 0 ? 0 : expected[count - 1]);
        uint256 reverse = auction.tail();
        for (uint256 i; i < count; ++i) {
            RankedAuction.Bid memory b = bid(expected[i]);
            assertEq(b.prev, i == 0 ? 0 : expected[i - 1]);
            assertEq(b.next, i + 1 == count ? 0 : expected[i + 1]);
            assertEq(reverse, expected[count - 1 - i]);
            reverse = bid(reverse).prev;
        }
        assertEq(reverse, 0);
        (uint256[] memory page, uint256 next) = auction.rankedBids(0, 90);
        assertEq(page.length, count);
        assertEq(next, 0);
        for (uint256 i; i < count; ++i) {
            assertEq(page[i], expected[i]);
        }
    }

    function testHeadMiddleTailAndStableTieInsertionMaintainBothLinks() public {
        live();
        place(alice, 2 ether);
        place(bob, 4 ether);
        place(carol, 1 ether);
        place(alice, 3 ether);
        place(bob, 3 ether);
        assertIndependentOrder();
        vm.prank(alice);
        auction.increaseBid{ value: 1 ether }(1); // Earlier ID overtakes equal totals.
        assertIndependentOrder();
        vm.prank(carol);
        auction.increaseBid{ value: 4 ether }(3); // Tail becomes head.
        assertIndependentOrder();
        vm.prank(alice);
        auction.increaseBid{ value: 0.1 ether }(4); // Middle unlink and insertion.
        assertIndependentOrder();
    }

    function testFullBookDisplacementAndTailIncreaseMaintainBothLinks() public {
        live();
        for (uint256 i; i < 90; ++i) {
            place(alice, RESERVE * (i + 1));
        }
        place(bob, auction.minimumBid());
        assertFalse(bid(1).active);
        assertIndependentOrder();
        uint256 oldTail = auction.tail();
        vm.prank(bid(oldTail).bidder);
        auction.increaseBid{ value: 1 ether }(oldTail);
        assertIndependentOrder();
        place(carol, 2 ether);
        assertIndependentOrder();
    }
}
