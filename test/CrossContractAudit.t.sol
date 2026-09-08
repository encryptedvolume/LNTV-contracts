// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Sells the first NFT inside its mint callback, optionally rejecting the next NFT in that batch.
contract MintSaleCallback is IERC721Receiver {
    AuctionEdition internal immutable edition;
    RoyaltyMarketplace internal immutable market;
    address internal immutable destination;
    bool internal immutable rejectSecond;
    uint256 public received;

    constructor(AuctionEdition edition_, address destination_, bool rejectSecond_) {
        edition = edition_;
        market = edition_.marketplace();
        destination = destination_;
        rejectSecond = rejectSecond_;
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(edition));
        ++received;
        if (received == 1) {
            edition.approve(address(market), tokenId);
            uint256 listing = market.list(tokenId, 1 ether, uint64(block.timestamp + 1 days));
            market.buy{ value: 1 ether }(listing, destination);
        } else {
            require(!rejectSecond, "Rejected second NFT");
        }
        return this.onERC721Received.selector;
    }
}

/// @dev Accepts an already authorized payout nomination during a purchase's receiver callback.
contract PayoutSaleCallback is IERC721Receiver {
    RankedAuction internal immutable auction;
    RoyaltyMarketplace internal immutable market;
    bool internal immutable rejectSale;
    bool public withdrewDuringSale;
    bytes4 public withdrawalError;

    constructor(RankedAuction auction_, bool rejectSale_) {
        auction = auction_;
        market = auction_.edition().marketplace();
        rejectSale = rejectSale_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(auction.edition()));
        auction.acceptPayoutWallet();
        bytes memory result;
        (withdrewDuringSale, result) =
            address(market).call(abi.encodeCall(RoyaltyMarketplace.withdrawRoyalties, (payable(address(this)))));
        withdrawalError = result.length >= 4 ? bytes4(result) : bytes4(0);
        require(!rejectSale, "Rejected sale");
        return this.onERC721Received.selector;
    }
}

contract CrossContractAuditTest is TestBase {
    function _prepareMintSale(bool rejectSecond) internal returns (MintSaleCallback receiver) {
        live();
        place(alice, 2 ether);
        place(alice, 1 ether);
        finish();
        receiver = new MintSaleCallback(edition, bob, rejectSecond);
        vm.deal(address(receiver), 1 ether);
    }

    function testMintCallbackSalePreservesSeparateAuctionAndMarketAccounting() public {
        MintSaleCallback receiver = _prepareMintSale(false);
        vm.prank(alice);
        auction.claimTokens(range(2), address(receiver));

        assertEq(receiver.received(), 2);
        assertEq(edition.totalSupply(), 2);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.ownerOf(2), address(receiver));
        assertEq(edition.transferNonce(1), 1);
        assertEq(auction.tokensClaimed(), 2);
        assertEq(auction.escrow(), 0.99 ether);
        assertEq(auction.pendingProceeds(), 2.01 ether);
        assertEq(auction.liabilities(), 3 ether);
        assertEq(address(auction).balance, 3 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        assertEq(market.credits(address(receiver)), 0.925 ether);
        assertEq(market.totalCredits(), 1 ether);
        assertEq(address(market).balance, 1 ether);
        auction.creditRefunds(range(2));
        vm.prank(alice);
        auction.withdrawRefund(payable(carol));
        assertEq(auction.liabilities(), 2.01 ether);
    }

    function testLaterMintRejectionRollsBackEarlierCallbackSaleAndPayment() public {
        MintSaleCallback receiver = _prepareMintSale(true);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Rejected second NFT"));
        vm.prank(alice);
        auction.claimTokens(range(2), address(receiver));

        assertEq(receiver.received(), 0);
        assertEq(address(receiver).balance, 1 ether);
        assertEq(edition.totalSupply(), 0);
        assertEq(edition.balanceOf(bob), 0);
        assertEq(edition.transferNonce(1), 0);
        assertEq(auction.tokensClaimed(), 0);
        assertFalse(bid(1).tokenClaimed);
        assertFalse(bid(2).tokenClaimed);
        assertEq(auction.escrow(), 0.99 ether);
        assertEq(auction.pendingProceeds(), 2.01 ether);
        assertEq(market.nextListingId(), 1);
        assertEq(market.pendingRoyalties(), 0);
        assertEq(market.credits(address(receiver)), 0);
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 0);

        // Refunds and a redirected retry remain usable after all nested transactions revert.
        auction.creditRefunds(range(2));
        vm.prank(alice);
        auction.withdrawRefund(payable(carol));
        vm.prank(alice);
        auction.claimTokens(range(2), alice);
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.ownerOf(2), alice);
    }

    function _preparePayoutSale(bool rejectSale) internal returns (PayoutSaleCallback receiver, uint256 listing) {
        mintForMarket();
        receiver = new PayoutSaleCallback(auction, rejectSale);
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        vm.prank(alice);
        listing = market.list(1, 1 ether, uint64(block.timestamp + 1 days));
    }

    function testPayoutAcceptanceDuringSaleKeepsRoyaltiesAndBlocksNestedWithdrawal() public {
        (PayoutSaleCallback receiver, uint256 listing) = _preparePayoutSale(false);
        vm.prank(bob);
        market.buy{ value: 1 ether }(listing, address(receiver));

        assertEq(auction.payoutWallet(), address(receiver));
        assertEq(auction.pendingPayoutWallet(), address(0));
        assertEq(edition.royaltyRecipient(), address(receiver));
        assertFalse(receiver.withdrewDuringSale());
        assertEq(receiver.withdrawalError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(edition.ownerOf(1), address(receiver));
        assertEq(market.credits(alice), 0.925 ether);
        assertEq(market.pendingRoyalties(), 0.075 ether);
        assertEq(market.totalCredits(), 1 ether);
        vm.expectRevert(RoyaltyMarketplace.NotPayoutWallet.selector);
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(carol));
        uint256 before = carol.balance;
        vm.prank(address(receiver));
        market.withdrawRoyalties(payable(carol));
        assertEq(carol.balance - before, 0.075 ether);
        assertEq(market.totalCredits(), 0.925 ether);
        assertEq(address(market).balance, 0.925 ether);
    }

    function testRejectedSaleRollsBackPayoutAcceptanceAndEveryCredit() public {
        (PayoutSaleCallback receiver, uint256 listing) = _preparePayoutSale(true);
        uint256 buyerBalance = bob.balance;
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Rejected sale"));
        vm.prank(bob);
        market.buy{ value: 1 ether }(listing, address(receiver));

        assertEq(auction.payoutWallet(), payoutWallet);
        assertEq(auction.pendingPayoutWallet(), address(receiver));
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.transferNonce(1), 0);
        assertEq(bob.balance, buyerBalance);
        (,,,, bool active,) = market.listings(listing);
        assertTrue(active);
        assertEq(market.credits(alice), 0);
        assertEq(market.pendingRoyalties(), 0);
        assertEq(market.totalCredits(), 0);
        assertEq(address(market).balance, 0);
    }

    function testFuzzClaimsCreditsAndWithdrawalsInDifferentOrders(uint256 seed, uint8 countSeed) public {
        uint256 count = uint256(countSeed) % 90 + 1;
        live();
        for (uint256 i; i < count; ++i) {
            place(alice, RESERVE * (i + 2));
        }
        finish();
        uint256 price = count == 90 ? 2 * RESERVE : RESERVE;
        uint256 gross = RESERVE * (count + 1) + price * (count - 1);
        uint256 paidIn = RESERVE * count * (count + 3) / 2;
        assertEq(auction.pendingProceeds(), gross);
        vm.prank(payoutWallet);
        auction.withdrawProceeds(payable(payoutWallet));

        uint256[] memory order = range(count);
        uint256 refundPending;
        uint256 refunded;
        for (uint256 i; i < count; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 j = i + seed % (count - i);
            (order[i], order[j]) = (order[j], order[i]);
            uint256 id = order[i];
            if (seed & 1 == 0) auction.creditRefunds(one(id));
            vm.prank(alice);
            auction.claimTokens(one(id), bob);
            if (seed & 1 != 0) auction.creditRefunds(one(id));
            assertEq(edition.ownerOf(count + 1 - id), bob);
            refundPending += id == count ? 0 : RESERVE * (id + 1) - price;
            assertEq(auction.refunds(alice), refundPending);
            if (seed & 2 != 0 && refundPending != 0) {
                vm.prank(alice);
                auction.withdrawRefund(payable(carol));
                refunded += refundPending;
                refundPending = 0;
            }
            assertEq(auction.liabilities(), paidIn - gross - refunded);
            assertEq(address(auction).balance, paidIn - gross - refunded);
        }
        auction.creditRefunds(range(count));
        assertEq(auction.escrow(), 0);
        assertEq(auction.refunds(alice), refundPending);
        if (refundPending != 0) {
            vm.prank(alice);
            auction.withdrawRefund(payable(carol));
        }
        vm.startPrank(payoutWallet);
        if (count < 90) auction.claimUnsold(90 - count, payoutWallet);
        auction.claimReserved(10, payoutWallet);
        vm.stopPrank();
        assertEq(edition.totalSupply(), 100);
        assertEq(auction.liabilities(), 0);
        assertEq(address(auction).balance, 0);
        assertEq(market.totalCredits(), 0);
    }
}
