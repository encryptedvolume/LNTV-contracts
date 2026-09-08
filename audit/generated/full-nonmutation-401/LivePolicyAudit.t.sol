// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Fable fourth-pass live-fork check: run configureEnforcedTrading against the REAL OpenSea registry bytecode.
// FORK_RPC selects the chain. Read-only against the chain; all writes happen in the local fork.
import { Test } from "forge-std/Test.sol";
import { RankedAuction } from "../src/RankedAuction.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../src/RoyaltyMarketplace.sol";

interface IRegistryView {
    function lastListId() external view returns (uint120);
    function listOwners(uint120) external view returns (address);
    function getWhitelistedAccounts(uint120) external view returns (address[] memory);
    function getAuthorizerAccounts(uint120) external view returns (address[] memory);
    function getWhitelistedAccountsByCollection(address) external view returns (address[] memory);
    function getAuthorizerAccountsByCollection(address) external view returns (address[] memory);
    function getCollectionSecurityPolicy(address) external view returns (uint8, uint120, uint120);
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
    function setTransferSecurityLevelOfCollection(address collection, uint8 level) external;
}

contract FreeOperatorFork {
    function move(AuctionEdition token, address from, address to, uint256 id) external {
        token.transferFrom(from, to, id);
    }
}

contract LivePolicyAuditTest is Test {
    address constant PP1 = 0x9A1D00bEd7CD04BCDA516d721A596eb22Aac6834;
    address constant PP2 = 0x9A1D001670C8b17F8B7900E8d7a41e785B3F0515;
    address payout = address(0x71EA5);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    RankedAuction auction;
    AuctionEdition edition;
    RoyaltyMarketplace market;
    IRegistryView registry;

    function assertPolicy() internal view {
        (uint8 level, uint120 id,) = registry.getCollectionSecurityPolicy(address(edition));
        assertEq(level, 4);
        assertEq(id, edition.tradingListId());
        assertEq(registry.listOwners(id), address(edition));
        address[] memory ops = registry.getWhitelistedAccountsByCollection(address(edition));
        address[] memory auth = registry.getAuthorizerAccountsByCollection(address(edition));
        assertEq(auth.length, 1);
        assertEq(auth[0], edition.OPENSEA_SIGNED_ZONE());
        assertEq(ops.length, 3);
        bool pp1; bool pp2; bool localMarket;
        for (uint256 i; i < ops.length; ++i) {
            if (ops[i] == PP1) pp1 = true;
            else if (ops[i] == PP2) pp2 = true;
            else if (ops[i] == address(market)) localMarket = true;
            else revert("Unexpected operator");
        }
        assertTrue(pp1 && pp2 && localMarket);
    }

    function testLiveRegistryConfiguration() public {
        vm.createSelectFork(vm.envString("FORK_RPC"), vm.envUint("FORK_BLOCK"));
        emit log_named_uint("chainId", block.chainid);
        emit log_named_uint("block", block.number);
        auction = new RankedAuction(RankedAuction.Config(payout, 1000, 0.01 ether,
            uint64(block.timestamp + 1 hours), "ipfs://audit/", "Audit", "AUD"));
        edition = auction.edition();
        market = edition.marketplace();
        registry = IRegistryView(edition.OPENSEA_TRANSFER_VALIDATOR());
        assertGt(address(registry).code.length, 0);
        assertGt(edition.OPENSEA_SIGNED_ZONE().code.length, 0);
        vm.prank(payout);
        edition.configureEnforcedTrading();
        assertPolicy();
        vm.prank(payout);
        edition.setAutomaticApprovalOfTransfersFromValidator(true);
        assertFalse(edition.isApprovedForAll(alice, address(registry)));
        vm.prank(payout);
        auction.claimReserved(1, alice);
        vm.prank(alice);
        vm.expectRevert();
        edition.transferFrom(alice, bob, 91);
        FreeOperatorFork op = new FreeOperatorFork();
        vm.prank(alice);
        edition.setApprovalForAll(address(op), true);
        vm.expectRevert();
        op.move(edition, alice, bob, 91);
        vm.prank(alice);
        edition.setApprovalForAll(address(market), true);
        vm.prank(alice);
        uint256 listing = market.list(91, 1 ether, uint64(block.timestamp + 1 days));
        vm.deal(bob, 2 ether);
        vm.prank(bob);
        market.buy{value: 1 ether}(listing, bob);
        assertEq(edition.ownerOf(91), bob);
        assertEq(market.pendingRoyalties(), 0.1 ether);
        vm.prank(address(edition));
        registry.validateTransfer(PP1, bob, alice, 91);
        vm.prank(address(edition));
        registry.validateTransfer(PP2, bob, alice, 91);
        vm.prank(payout);
        auction.proposePayoutWallet(address(0x9999));
        vm.prank(address(0x9999));
        auction.acceptPayoutWallet();
        assertEq(edition.owner(), address(0x9999));
        assertPolicy();
        vm.prank(payout);
        vm.expectRevert();
        registry.setTransferSecurityLevelOfCollection(address(edition), 1);
        // Policy remains trusted administration, independently of holder consent.
        vm.prank(address(0x9999));
        registry.setTransferSecurityLevelOfCollection(address(edition), 1);
        vm.prank(bob);
        edition.transferFrom(bob, alice, 91);
        assertEq(edition.ownerOf(91), alice);
        vm.prank(address(0x9999));
        edition.configureEnforcedTrading();
        assertPolicy();
    }
}
