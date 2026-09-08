// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Rejector, ReentrantReceiver } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";

contract PayoutWalletTest is TestBase {
    event PayoutWalletProposed(address indexed currentWallet, address indexed proposedWallet);
    event PayoutWalletChangeCancelled(address indexed cancelledWallet);
    event PayoutWalletChanged(address indexed previousWallet, address indexed newWallet);

    function rotateTo(address next) internal {
        vm.prank(auction.payoutWallet());
        auction.proposePayoutWallet(next);
        vm.prank(next);
        auction.acceptPayoutWallet();
    }

    function sell(address seller, address buyer, uint128 price) internal {
        vm.prank(seller);
        edition.setApprovalForAll(address(market), true);
        vm.prank(seller);
        uint256 id = market.list(1, price, uint64(block.timestamp + 1 days));
        vm.prank(buyer);
        market.buy{ value: price }(id, buyer);
    }

    function testNominationRequiresAcceptanceAndEmitsBothEvents() public {
        assertEq(auction.payoutWallet(), payoutWallet);
        assertEq(auction.pendingPayoutWallet(), address(0));
        vm.expectEmit(true, true, false, true, address(auction));
        emit PayoutWalletProposed(payoutWallet, bob);
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(bob);
        assertEq(auction.payoutWallet(), payoutWallet);
        assertEq(edition.royaltyRecipient(), payoutWallet);
        assertEq(auction.pendingPayoutWallet(), bob);
        vm.expectEmit(true, true, false, true, address(auction));
        emit PayoutWalletChanged(payoutWallet, bob);
        vm.prank(bob);
        auction.acceptPayoutWallet();
        assertEq(auction.payoutWallet(), bob);
        assertEq(edition.royaltyRecipient(), bob);
        assertEq(auction.pendingPayoutWallet(), address(0));
        (address receiver, uint256 royalty) = edition.royaltyInfo(1, 1 ether);
        assertEq(receiver, bob);
        assertEq(royalty, 0.075 ether);
        assertEq(edition.royaltyBps(), 750);
    }

    function testOutsidersCannotProposeAcceptOrCancel() public {
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.proposePayoutWallet(alice);
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(bob);
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.acceptPayoutWallet();
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.cancelPayoutWalletChange();
        vm.prank(alice);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.cancelPayoutWalletChange();
        assertEq(auction.pendingPayoutWallet(), bob);
        assertEq(auction.payoutWallet(), payoutWallet);
    }

    function testNominationCanBeReplacedOrCancelledAndStaleAcceptanceFails() public {
        vm.startPrank(payoutWallet);
        vm.expectRevert(RankedAuction.NoPendingPayoutWallet.selector);
        auction.cancelPayoutWalletChange();
        auction.proposePayoutWallet(bob);
        auction.proposePayoutWallet(carol);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.acceptPayoutWallet();
        vm.expectEmit(true, false, false, true, address(auction));
        emit PayoutWalletChangeCancelled(carol);
        vm.prank(payoutWallet);
        auction.cancelPayoutWalletChange();
        assertEq(auction.pendingPayoutWallet(), address(0));
        vm.prank(carol);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.NoPendingPayoutWallet.selector);
        auction.cancelPayoutWalletChange();
    }

    function testUnsafePayoutWalletsAreRejected() public {
        address[5] memory invalid = [address(0), address(auction), address(edition), address(market), payoutWallet];
        for (uint256 i; i < invalid.length; ++i) {
            vm.prank(payoutWallet);
            vm.expectRevert(RankedAuction.InvalidPayoutWallet.selector);
            auction.proposePayoutWallet(invalid[i]);
        }
        assertEq(auction.pendingPayoutWallet(), address(0));
    }

    function testConstructorRejectsSystemAddressesAsPayoutWallet() public {
        for (uint256 i; i < 3; ++i) {
            RankedAuction.Config memory c = config();
            address nextAuction = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
            address nextEdition = vm.computeCreateAddress(nextAuction, 1);
            c.payoutWallet = i == 0 ? nextAuction : i == 1 ? nextEdition : vm.computeCreateAddress(nextEdition, 1);
            vm.expectRevert(RankedAuction.InvalidPayoutWallet.selector);
            new RankedAuction(c);
        }
    }

    function testRepeatedRotationsRevokeFormerWallets() public {
        rotateTo(bob);
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.proposePayoutWallet(alice);
        vm.prank(bob);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.acceptPayoutWallet();
        rotateTo(carol);
        rotateTo(payoutWallet);
        assertEq(edition.royaltyRecipient(), payoutWallet);
        assertEq(auction.pendingPayoutWallet(), address(0));
    }

    function testPrimaryAuctionHasNoRoyaltiesEvenAt100PercentTradingRate() public {
        RankedAuction.Config memory c = config();
        c.royaltyBps = 10000;
        auction = new RankedAuction(c);
        edition = auction.edition();
        market = edition.marketplace();
        live();
        place(alice, 1 ether);
        place(bob, 2 ether);
        finish();
        assertEq(auction.pendingProceeds(), 2 ether + RESERVE);
        assertEq(market.pendingRoyalties(), 0);
        uint256 beforeBalance = payoutWallet.balance;
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));
        assertEq(payoutWallet.balance - beforeBalance, 2 ether + RESERVE);
        assertEq(address(auction).balance, 1 ether - RESERVE);
        auction.creditRefunds(range(2));
        assertEq(auction.totalRefunds(), 1 ether - RESERVE);
    }

    function testRotatingDuringLiveAuctionDoesNotAlterBidsOrAuctionTerms() public {
        live();
        place(alice, 1 ether);
        rotateTo(carol);
        assertEq(auction.activeCount(), 1);
        assertEq(auction.escrow(), 1 ether);
        assertEq(bid(1).bidder, alice);
        assertEq(auction.reservePrice(), RESERVE);
        assertEq(edition.royaltyBps(), 750);
        assertEq(edition.metadataURI(), "ipfs://edition-metadata/");
        finish();
        assertEq(auction.pendingProceeds(), 1 ether);
        vm.prank(carol);
        auction.withdrawProceeds(payable(carol));
    }

    function testAccruedAndFutureBusinessRevenueMovesWhileBidderAndSellerFundsStayOwned() public {
        live();
        place(alice, 1 ether);
        place(alice, 2 ether);
        finish();
        vm.prank(alice);
        auction.claimTokens(one(2), alice);
        sell(alice, bob, 1 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(auction.pendingProceeds(), 2 ether + RESERVE);
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(carol);
        vm.prank(carol);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawProceeds(payable(carol));
        vm.prank(carol);
        vm.expectRevert(RoyaltyMarketplace.NotPayoutWallet.selector);
        market.withdrawRoyalties(payable(carol));
        vm.prank(carol);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.withdrawProceeds(payable(payoutWallet));
        vm.prank(payoutWallet);
        vm.expectRevert(RankedAuction.Unauthorized.selector);
        auction.claimUnsold(1, payoutWallet);
        vm.prank(payoutWallet);
        vm.expectRevert(RoyaltyMarketplace.NotPayoutWallet.selector);
        market.withdrawRoyalties(payable(payoutWallet));
        uint256 beforeBalance = carol.balance;
        vm.startPrank(carol);
        auction.withdrawProceeds(payable(carol));
        market.withdrawRoyalties(payable(carol));
        auction.claimUnsold(88, carol);
        vm.stopPrank();
        assertEq(carol.balance - beforeBalance, 2 ether + RESERVE + 0.075 ether);
        auction.creditRefunds(one(1));
        assertEq(auction.refunds(alice), 1 ether - RESERVE);
        assertEq(market.credits(alice), 0.925 ether);
        vm.prank(carol);
        vm.expectRevert(RoyaltyMarketplace.NothingToWithdraw.selector);
        market.withdraw(payable(carol));
        vm.prank(carol);
        vm.expectRevert(RankedAuction.NothingToWithdraw.selector);
        auction.withdrawRefund(payable(carol));
        sell(bob, alice, 2 ether);
        assertEq(market.pendingRoyalties(), 0.15 ether);
        vm.prank(carol);
        market.withdrawRoyalties(payable(carol));
        vm.startPrank(alice);
        auction.withdrawRefund(payable(alice));
        market.withdraw(payable(alice));
        vm.stopPrank();
        vm.prank(bob);
        market.withdraw(payable(bob));
        assertEq(market.totalCredits(), 0);
        assertEq(auction.liabilities(), 0);
    }

    function testFormerWalletKeepsItsOwnSellerCreditsAndBidderRefunds() public {
        rotateTo(alice);
        live();
        place(alice, 1 ether);
        place(alice, 2 ether);
        finish();
        vm.prank(alice);
        auction.claimTokens(one(2), alice);
        sell(alice, bob, 1 ether);
        rotateTo(carol);
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        auction.creditRefunds(range(2));
        assertEq(auction.refunds(alice), 1 ether - RESERVE);
        vm.startPrank(alice);
        market.withdraw(payable(alice));
        auction.withdrawRefund(payable(alice));
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.NotPayoutWallet.selector);
        market.withdrawRoyalties(payable(alice));
        vm.prank(carol);
        market.withdrawRoyalties(payable(carol));
        vm.prank(carol);
        auction.withdrawProceeds(payable(carol));
        assertEq(market.totalCredits(), 0);
        assertEq(auction.liabilities(), 0);
    }

    function testRoyaltiesWithdrawalValidationAndDoubleWithdrawal() public {
        mintForMarket();
        vm.prank(payoutWallet);
        vm.expectRevert(RoyaltyMarketplace.NothingToWithdraw.selector);
        market.withdrawRoyalties(payable(payoutWallet));
        sell(alice, bob, 1 ether);
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.NotPayoutWallet.selector);
        market.withdrawRoyalties(payable(alice));
        address[2] memory invalid = [address(0), address(market)];
        for (uint256 i; i < invalid.length; ++i) {
            vm.prank(payoutWallet);
            vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
            market.withdrawRoyalties(payable(invalid[i]));
        }
        assertEq(market.pendingRoyalties(), 0.075 ether);
        assertEq(market.totalCredits(), 1 ether);
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(carol));
        assertEq(market.pendingRoyalties(), 0);
        assertEq(market.totalCredits(), 0.925 ether);
        vm.prank(payoutWallet);
        vm.expectRevert(RoyaltyMarketplace.NothingToWithdraw.selector);
        market.withdrawRoyalties(payable(carol));
    }

    function testRejectingContractWalletCanAcceptAndRedirectPayments() public {
        live();
        place(alice, RESERVE);
        finish();
        Rejector receiver = new Rejector();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        receiver.execute(address(auction), abi.encodeCall(auction.acceptPayoutWallet, ()));
        vm.expectRevert(RankedAuction.TransferFailed.selector);
        receiver.execute(address(auction), abi.encodeCall(auction.withdrawProceeds, (payable(address(receiver)))));
        assertEq(auction.pendingProceeds(), RESERVE);
        receiver.execute(address(auction), abi.encodeCall(auction.withdrawProceeds, (payable(bob))));
        assertEq(auction.pendingProceeds(), 0);
        assertEq(edition.royaltyRecipient(), address(receiver));
    }

    function testProceedsCallbackCannotRotateOrDoubleWithdraw() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        rotateTo(address(receiver));
        live();
        place(alice, RESERVE);
        finish();
        receiver.arm(address(auction), abi.encodeCall(auction.proposePayoutWallet, (bob)), false);
        receiver.execute(address(auction), abi.encodeCall(auction.withdrawProceeds, (payable(address(receiver)))));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(auction.pendingPayoutWallet(), address(0));
        assertEq(auction.pendingProceeds(), 0);
    }

    function testRoyaltyWithdrawalCannotReenterSellerWithdrawal() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        rotateTo(address(receiver));
        mintForMarket();
        sell(alice, bob, 1 ether);
        receiver.arm(address(market), abi.encodeCall(market.withdraw, (payable(address(receiver)))), false);
        receiver.execute(address(market), abi.encodeCall(market.withdrawRoyalties, (payable(address(receiver)))));
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.totalCredits(), 0.925 ether);
    }
}
