// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, Rejector, ReentrantReceiver, ForceEther } from "./TestBase.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract RoyaltyMarketplaceTest is TestBase {
    function listing(uint256 tokenId, uint128 price) internal returns (uint256 id) {
        vm.prank(alice);
        id = market.list(tokenId, price, uint64(block.timestamp + 1 days));
    }

    function active(uint256 id) internal view returns (bool value) {
        (,,,, value,) = market.listings(id);
    }

    function testERC165AndERC2981AndMetadata() public {
        assertTrue(edition.supportsInterface(0x01ffc9a7));
        assertTrue(edition.supportsInterface(0x80ac58cd));
        assertTrue(edition.supportsInterface(0x5b5e139f));
        assertTrue(edition.supportsInterface(0x2a55205a));
        assertFalse(edition.supportsInterface(0xd9b67a26));
        assertFalse(edition.supportsInterface(0xffffffff));
        assertEq(edition.name(), "The First Signal");
        assertEq(edition.symbol(), "LNTV");
        assertEq(edition.metadataURI(), "ipfs://edition-metadata/");
        vm.expectRevert();
        edition.tokenURI(1);
        mintForMarket();
        assertEq(edition.tokenURI(1), "ipfs://edition-metadata/1.json");
        assertEq(edition.tokenURI(100), "ipfs://edition-metadata/100.json");
        (address receiver, uint256 royalty) = edition.royaltyInfo(100, 1 ether);
        assertEq(receiver, payoutWallet);
        assertEq(royalty, 0.075 ether);
        (, royalty) = edition.royaltyInfo(1, 0);
        assertEq(royalty, 0);
        (, royalty) = edition.royaltyInfo(0, 1 ether);
        assertEq(royalty, 0);
        (, royalty) = edition.royaltyInfo(101, 1 ether);
        assertEq(royalty, 0);
    }

    function testMintAuthorityUniqueIdsAndLifetimeCap() public {
        vm.expectRevert(AuctionEdition.Unauthorized.selector);
        edition.mint(alice, one(1));
        AuctionEdition token = new AuctionEdition("Test", "TST", "ipfs://test/", 100);
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, new uint256[](0));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, range(101));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, one(0));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, one(101));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, one(type(uint256).max));
        token.mint(alice, one(100));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(bob, one(100));
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = 1;
        duplicate[1] = 1;
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(bob, duplicate);
        assertEq(token.totalSupply(), 1);
        token.mint(alice, range(99));
        vm.expectRevert(AuctionEdition.InvalidMint.selector);
        token.mint(alice, one(1));
        assertEq(token.totalSupply(), 100);
        for (uint256 id = 1; id <= 100; ++id) {
            assertEq(token.ownerOf(id), alice);
        }
    }

    function testRejectedMintRollsBackSupply() public {
        AuctionEdition token = new AuctionEdition("Test", "TST", "ipfs://test/", 100);
        Rejector rejector = new Rejector();
        vm.expectRevert();
        token.mint(address(rejector), range(100));
        assertEq(token.totalSupply(), 0);
        vm.expectRevert();
        token.mint(address(0), range(100));
        assertEq(token.totalSupply(), 0);
        token.mint(alice, range(100));
    }

    function testTransfersCannotMintUnissuedIds() public {
        vm.startPrank(alice);
        vm.expectRevert();
        edition.transferFrom(address(0), alice, 1);
        vm.expectRevert();
        edition.safeTransferFrom(address(0), alice, 1);
        vm.expectRevert();
        edition.safeTransferFrom(address(0), alice, 1, "");
        vm.stopPrank();
        assertEq(edition.totalSupply(), 0);
        assertEq(edition.balanceOf(alice), 0);
    }

    function testAllERC721TransferEntrypointsRequireRegistryAuthorization() public {
        mintForMarket();
        vm.startPrank(alice);
        vm.expectRevert(
            bytes4(keccak256("StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator()"))
        );
        edition.transferFrom(alice, bob, 1);
        vm.expectRevert(
            bytes4(keccak256("StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator()"))
        );
        edition.safeTransferFrom(alice, bob, 1);
        vm.expectRevert(
            bytes4(keccak256("StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator()"))
        );
        edition.safeTransferFrom(alice, bob, 1, "payload");
        vm.expectRevert();
        edition.transferFrom(alice, address(0), 1);
        vm.stopPrank();
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.balanceOf(alice), 100);
        assertEq(edition.transferNonce(1), 0);
    }

    function testApprovedUntrustedOperatorStillCannotTransfer() public {
        mintForMarket();
        vm.prank(alice);
        edition.setApprovalForAll(bob, true);
        assertTrue(edition.isApprovedForAll(alice, bob));
        vm.prank(bob);
        vm.expectRevert();
        edition.safeTransferFrom(alice, bob, 1);
        vm.prank(alice);
        edition.setApprovalForAll(bob, false);
        assertFalse(edition.isApprovedForAll(alice, bob));
        vm.prank(alice);
        edition.setApprovalForAll(address(market), false);
        assertFalse(edition.isApprovedForAll(alice, address(market)));
    }

    function testListingRequirements() public {
        mintForMarket();
        vm.expectRevert(RoyaltyMarketplace.InvalidToken.selector);
        market.list(0, 1, uint64(block.timestamp + 1));
        vm.expectRevert(RoyaltyMarketplace.InvalidToken.selector);
        market.list(101, 1, uint64(block.timestamp + 1));
        vm.expectRevert(RoyaltyMarketplace.InvalidToken.selector);
        market.list(65537, 1, uint64(block.timestamp + 1));
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.list(1, 0, uint64(block.timestamp + 1));
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.list(1, 1, uint64(block.timestamp));
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.NotSeller.selector);
        market.list(1, 1, uint64(block.timestamp + 1));
        vm.prank(alice);
        edition.setApprovalForAll(address(market), false);
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.NotApproved.selector);
        market.list(1, 1, uint64(block.timestamp + 1));
    }

    function testIndividualSalesPayRoyaltyAndSellerExactly() public {
        mintForMarket();
        uint256 first = listing(10, 3 ether);
        uint256 second = listing(100, 7 ether);
        vm.prank(bob);
        market.buy{ value: 3 ether }(first, bob);
        assertEq(edition.ownerOf(10), bob);
        assertFalse(active(first));
        assertEq(market.pendingRoyalties(), 0.225 ether);
        assertEq(market.credits(alice), 2.775 ether);
        vm.prank(carol);
        market.buy{ value: 7 ether }(second, carol);
        assertFalse(active(second));
        assertEq(market.totalCredits(), 10 ether);
        assertEq(edition.balanceOf(alice), 98);
        assertEq(edition.ownerOf(100), carol);
        vm.prank(alice);
        market.withdraw(payable(alice));
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(payoutWallet));
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 0);
    }

    function testBuyerMayChooseDifferentReceiver() public {
        mintForMarket();
        uint256 id = listing(1, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, carol);
        assertEq(edition.balanceOf(carol), 1);
        assertEq(edition.balanceOf(bob), 0);
    }

    function testOnlySellerCanCancelAndListingIdNeverReused() public {
        mintForMarket();
        uint256 id = listing(2, 1 ether);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.NotSeller.selector);
        market.cancel(id);
        vm.prank(alice);
        market.cancel(id);
        assertFalse(active(id));
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.cancel(id);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 1 ether }(id, bob);
        assertEq(listing(2, 1 ether), id + 1);
    }

    function testCancellingAnotherListingPreservesCompletedSale() public {
        mintForMarket();
        uint256 first = listing(1, 1 ether);
        uint256 second = listing(2, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(first, bob);
        vm.prank(alice);
        market.cancel(second);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(2), alice);
        assertEq(market.totalCredits(), 1 ether);
    }

    function testBuyRejectsInvalidPaymentAndRecipient() public {
        mintForMarket();
        uint256 id = listing(2, 1 ether);
        vm.deal(address(this), 5 ether);
        vm.expectRevert(RoyaltyMarketplace.IncorrectPayment.selector);
        market.buy{ value: 1 ether - 1 }(id, bob);
        vm.expectRevert(RoyaltyMarketplace.IncorrectPayment.selector);
        market.buy{ value: 1 ether + 1 }(id, bob);
        vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
        market.buy{ value: 1 ether }(id, address(0));
        vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
        market.buy{ value: 1 ether }(id, address(market));
        vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
        market.buy{ value: 1 ether }(id, address(edition));
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 1 ether }(999, bob);
        assertTrue(active(id));
        assertEq(market.totalCredits(), 0);
    }

    function testExpiryExclusive() public {
        mintForMarket();
        uint256 first = listing(1, 1 ether);
        uint256 second = listing(2, 1 ether);
        (,, uint64 expiry,,,) = market.listings(first);
        vm.warp(expiry - 1);
        vm.prank(bob);
        market.buy{ value: 1 ether }(first, bob);
        vm.warp(expiry);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 1 ether }(second, bob);
        assertTrue(active(second));
    }

    function testRevokedApprovalRollsBackFillAndCredit() public {
        mintForMarket();
        uint256 id = listing(1, 1 ether);
        vm.prank(alice);
        edition.setApprovalForAll(address(market), false);
        vm.prank(bob);
        vm.expectRevert();
        market.buy{ value: 1 ether }(id, bob);
        assertTrue(active(id));
        assertEq(market.totalCredits(), 0);
        vm.prank(alice);
        edition.setApprovalForAll(address(market), true);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
    }

    function testOverlappingListingsCannotSellAnNftTwiceOrReviveOnReturn() public {
        mintForMarket();
        uint256 first = listing(1, 1 ether);
        uint256 stale = listing(1, 2 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(first, bob);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 2 ether }(stale, bob);
        vm.startPrank(bob);
        edition.setApprovalForAll(address(market), true);
        uint256 resale = market.list(1, 3 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();
        vm.prank(alice);
        market.buy{ value: 3 ether }(resale, alice);
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.transferNonce(1), 2);
        vm.prank(carol);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 2 ether }(stale, carol);
        assertTrue(active(stale));
        assertEq(market.totalCredits(), 4 ether);
        uint256 current = listing(1, 4 ether);
        vm.prank(carol);
        market.buy{ value: 4 ether }(current, carol);
        assertEq(edition.ownerOf(1), carol);
    }

    function testRejectingNFTReceiverCannotConsumeBuyerFunds() public {
        mintForMarket();
        uint256 id = listing(1, 1 ether);
        Rejector rejector = new Rejector();
        uint256 beforeBalance = bob.balance;
        vm.prank(bob);
        vm.expectRevert();
        market.buy{ value: 1 ether }(id, address(rejector));
        assertEq(bob.balance, beforeBalance);
        assertTrue(active(id));
        assertEq(market.totalCredits(), 0);
        assertEq(market.pendingRoyalties(), 0);
        assertEq(edition.balanceOf(alice), 100);
    }

    function testRejectingSellerAndRoyaltyReceiversCannotBlockSale() public {
        Rejector rejector = new Rejector();
        RankedAuction.Config memory c = config();
        c.payoutWallet = address(rejector);
        auction = new RankedAuction(c);
        edition = auction.edition();
        market = edition.marketplace();
        configureTrading(edition, auction.payoutWallet());
        finish();
        rejector.execute(address(auction), abi.encodeCall(auction.claimUnsold, (90, alice)));
        vm.prank(alice);
        edition.setApprovalForAll(address(market), true);
        uint256 id = listing(1, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        vm.expectRevert(RoyaltyMarketplace.TransferFailed.selector);
        rejector.execute(address(market), abi.encodeCall(market.withdrawRoyalties, (payable(address(rejector)))));
        assertEq(market.pendingRoyalties(), 0.075 ether);
        rejector.execute(address(market), abi.encodeCall(market.withdrawRoyalties, (payable(carol))));
        assertEq(market.pendingRoyalties(), 0);
    }

    function testWithdrawAccessValidationAndRevertsPreserveFunds() public {
        mintForMarket();
        uint256 id = listing(1, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.NothingToWithdraw.selector);
        market.withdraw(payable(bob));
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
        market.withdraw(payable(address(0)));
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.InvalidRecipient.selector);
        market.withdraw(payable(address(market)));
        Rejector rejector = new Rejector();
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.TransferFailed.selector);
        market.withdraw(payable(address(rejector)));
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.totalCredits(), 1 ether);
        vm.prank(alice);
        market.withdraw(payable(carol));
        assertEq(market.credits(alice), 0);
    }

    function testERC721CallbackCannotReenterBuyOrCancel() public {
        mintForMarket();
        uint256 first = listing(1, 1);
        uint256 second = listing(2, 1);
        ReentrantReceiver receiver = new ReentrantReceiver();
        receiver.arm(address(market), abi.encodeCall(market.cancel, (first)), false);
        vm.prank(bob);
        market.buy{ value: 1 }(first, address(receiver));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertFalse(active(first));
        receiver.arm(address(market), abi.encodeCall(market.buy, (second, address(receiver))), false);
        vm.prank(bob);
        market.buy{ value: 1 }(second, address(receiver));
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertFalse(active(second));
        assertEq(edition.balanceOf(address(receiver)), 2);
    }

    function testWithdrawalCallbackCannotReenter() public {
        ReentrantReceiver receiver = new ReentrantReceiver();
        RankedAuction.Config memory c = config();
        c.payoutWallet = address(receiver);
        auction = new RankedAuction(c);
        edition = auction.edition();
        market = edition.marketplace();
        configureTrading(edition, auction.payoutWallet());
        mintForMarket();
        uint256 id = listing(1, 1 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
        receiver.arm(address(market), abi.encodeCall(market.withdrawRoyalties, (payable(address(receiver)))), false);
        receiver.execute(address(market), abi.encodeCall(market.withdrawRoyalties, (payable(address(receiver)))));
        assertTrue(receiver.attempted());
        assertFalse(receiver.succeeded());
        assertEq(receiver.lastError(), bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        assertEq(address(receiver).balance, 0.075 ether);
        assertEq(market.pendingRoyalties(), 0);
    }

    function testOneWeiSaleCannotRoundRoyaltyToZero() public {
        mintForMarket();
        uint256 id = listing(1, 1);
        vm.prank(bob);
        market.buy{ value: 1 }(id, bob);
        assertEq(market.pendingRoyalties(), 1);
        assertEq(market.credits(alice), 0);
    }

    function testFullRoyaltyAndSameSellerReceiverDoNotLoseFunds() public {
        RankedAuction.Config memory c = config();
        c.royaltyBps = 10000;
        c.payoutWallet = alice;
        auction = new RankedAuction(c);
        edition = auction.edition();
        market = edition.marketplace();
        configureTrading(edition, auction.payoutWallet());
        mintForMarket();
        uint256 id = listing(10, 10 ether);
        vm.prank(bob);
        market.buy{ value: 10 ether }(id, bob);
        assertEq(market.credits(alice), 0);
        assertEq(market.pendingRoyalties(), 10 ether);
        assertEq(market.totalCredits(), 10 ether);
        vm.prank(alice);
        market.withdrawRoyalties(payable(alice));
        assertEq(address(market).balance, 0);
    }

    function testForcedEtherDoesNotCreateCredits() public {
        mintForMarket();
        vm.deal(address(this), 1 ether);
        new ForceEther{ value: 1 ether }(payable(address(market)));
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 1 ether);
    }

    function testUnsolicitedMarketEtherRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(market).call{ value: 1 ether }("");
        assertFalse(ok);
    }

    function testFuzzRoyaltyMathNoOverflow(uint256 price, uint96 bps) public {
        bps = uint96(bound(bps, 1, 10000));
        AuctionEdition token = new AuctionEdition("Test NFTs", "TST", "ipfs://test/", bps);
        (, uint256 royalty) = token.royaltyInfo(1, price);
        // Independent quotient/remainder oracle avoids multiplication overflow even at uint256.max.
        uint256 expected = (price / 10000) * bps + ((price % 10000) * bps + 9999) / 10000;
        assertEq(royalty, expected);
        assertLe(royalty, price);
        if (price > 0) assertGt(royalty, 0);
    }

    function testFuzzTokenSaleConservesValue(uint128 price, uint16 tokenId) public {
        price = uint128(bound(price, 1, 1e30));
        tokenId = uint16(bound(tokenId, 1, 100));
        mintForMarket();
        uint256 id = listing(tokenId, price);
        vm.prank(bob);
        market.buy{ value: price }(id, bob);
        assertEq(market.credits(alice) + market.pendingRoyalties(), price);
        assertEq(market.totalCredits(), address(market).balance);
        assertEq(edition.balanceOf(alice) + edition.balanceOf(bob), 100);
        assertEq(edition.ownerOf(tokenId), bob);
        assertEq(edition.transferNonce(tokenId), 1);
    }

    function testTokenApprovalAllowsMarketAndClearsOnTransfer() public {
        mintForMarket();
        vm.startPrank(alice);
        edition.setApprovalForAll(address(market), false);
        edition.approve(bob, 1);
        assertEq(edition.getApproved(1), bob);
        edition.approve(address(market), 1);
        vm.stopPrank();
        assertEq(edition.getApproved(1), address(market));
        uint256 id = listing(1, 1 ether);
        vm.prank(alice);
        edition.approve(address(0), 1);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.NotApproved.selector);
        market.buy{ value: 1 ether }(id, bob);
        vm.prank(alice);
        edition.approve(address(market), 1);
        vm.prank(bob);
        market.buy{ value: 1 ether }(id, bob);
        assertEq(edition.getApproved(1), address(0));
        assertEq(edition.ownerOf(1), bob);
        vm.prank(alice);
        vm.expectRevert();
        edition.approve(address(market), 1);
        vm.prank(alice);
        vm.expectRevert(RoyaltyMarketplace.NotSeller.selector);
        market.list(1, 1 ether, uint64(block.timestamp + 1 days));
    }

    function testSelfPurchasePaysRoyaltyAndInvalidatesOtherListings() public {
        mintForMarket();
        uint256 first = listing(1, 1 ether);
        uint256 stale = listing(1, 1 ether);
        vm.prank(alice);
        market.buy{ value: 1 ether }(first, alice);
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.transferNonce(1), 1);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        vm.prank(bob);
        vm.expectRevert(RoyaltyMarketplace.InvalidListing.selector);
        market.buy{ value: 1 ether }(stale, bob);
    }
}
