// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";

/// @dev Deliberately permissive validator/operator used only to reproduce F4-01.
contract UntrustedValidatorFixture {
    function validateTransfer(address, address, address, uint256) external pure { }
    function setTokenTypeOfCollection(address, uint16) external pure { }

    function take(AuctionEdition token, address from, address to, uint256 id) external {
        token.transferFrom(from, to, id);
    }

    function takeSafely(AuctionEdition token, address from, address to, uint256 id) external {
        token.safeTransferFrom(from, to, id, "unapproved validator");
    }
}

contract HolderApprovalTest is TestBase {
    function install(address admin, bool enableFirst) internal returns (UntrustedValidatorFixture validator) {
        validator = new UntrustedValidatorFixture();
        vm.startPrank(admin);
        if (enableFirst) edition.setAutomaticApprovalOfTransfersFromValidator(true);
        edition.setTransferValidator(address(validator));
        if (!enableFirst) edition.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.stopPrank();
    }

    function testPayoutWalletCannotSeizeAnyOfThe100MintedNFTs() public {
        mintForMarket();
        UntrustedValidatorFixture validator = install(payoutWallet, false);
        assertTrue(edition.autoApproveTransfersFromValidator());
        for (uint256 id = 1; id <= 100; ++id) {
            vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
            validator.take(edition, alice, payoutWallet, id);
            assertEq(edition.ownerOf(id), alice);
            assertEq(edition.transferNonce(id), 0);
        }
        assertEq(edition.balanceOf(alice), 100);
        assertEq(edition.balanceOf(payoutWallet), 0);
        assertFalse(edition.isApprovedForAll(alice, address(validator)));
    }

    function testEnablingAutoApprovalBeforeValidatorReplacementCannotSeize() public {
        mintForMarket();
        UntrustedValidatorFixture validator = install(payoutWallet, true);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.takeSafely(edition, alice, bob, 42);
        assertEq(edition.ownerOf(42), alice);
    }

    function testEnablingAutoApprovalBeforeMintingCannotSeizeFutureNFTs() public {
        UntrustedValidatorFixture validator = install(payoutWallet, true);
        vm.prank(payoutWallet);
        auction.claimReserved(1, alice);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, alice, payoutWallet, 91);
        assertEq(edition.ownerOf(91), alice);
    }

    function testPayoutRotationCannotGrantHolderApprovals() public {
        mintForMarket();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(carol);
        vm.prank(carol);
        auction.acceptPayoutWallet();
        UntrustedValidatorFixture validator = install(carol, true);
        vm.prank(payoutWallet);
        vm.expectRevert(AuctionEdition.Unauthorized.selector);
        edition.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, alice, carol, 1);
        assertEq(edition.ownerOf(1), alice);
    }

    function testExplicitTokenApprovalStillWorksAndClearsOnTransfer() public {
        mintForMarket();
        UntrustedValidatorFixture validator = install(payoutWallet, false);
        vm.prank(alice);
        edition.approve(address(validator), 1);
        assertFalse(edition.isApprovedForAll(alice, address(validator)));
        validator.take(edition, alice, bob, 1);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.getApproved(1), address(0));
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, bob, carol, 1);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, alice, carol, 2);
    }

    function testRevokingExplicitOperatorApprovalCannotBeUndoneByTheCreator() public {
        mintForMarket();
        UntrustedValidatorFixture validator = install(payoutWallet, false);
        vm.prank(alice);
        edition.setApprovalForAll(address(validator), true);
        validator.takeSafely(edition, alice, bob, 1);
        assertEq(edition.ownerOf(1), bob);
        vm.prank(alice);
        edition.setApprovalForAll(address(validator), false);
        vm.startPrank(payoutWallet);
        edition.setAutomaticApprovalOfTransfersFromValidator(false);
        edition.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.stopPrank();
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, alice, carol, 2);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        validator.take(edition, bob, carol, 1);
        assertFalse(edition.isApprovedForAll(alice, address(validator)));
    }

    function testFuzzValidatorNeedsHolderConsent(uint8 candidate, bool enableFirst, bool safe) public {
        mintForMarket();
        uint256 id = bound(uint256(candidate), 1, 100);
        UntrustedValidatorFixture validator = install(payoutWallet, enableFirst);
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        if (safe) validator.takeSafely(edition, alice, bob, id);
        else validator.take(edition, alice, bob, id);
        assertEq(edition.ownerOf(id), alice);
    }
}
