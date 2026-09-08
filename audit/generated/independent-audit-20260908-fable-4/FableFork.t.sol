// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Fable fourth-pass live-fork check: run configureEnforcedTrading against the REAL OpenSea registry bytecode.
// FORK_RPC selects the chain. Read-only against the chain; all writes happen in the local fork.
import { Test } from "forge-std/Test.sol";
import { RankedAuction } from "../../src/RankedAuction.sol";
import { AuctionEdition } from "../../src/AuctionEdition.sol";
import { RoyaltyMarketplace } from "../../src/RoyaltyMarketplace.sol";

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

contract FableForkTest is Test {
    address constant PP1 = 0x9A1D00bEd7CD04BCDA516d721A596eb22Aac6834;
    address constant PP2 = 0x9A1D001670C8b17F8B7900E8d7a41e785B3F0515;
    address payoutWallet = address(0x71EA5);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function testLiveRegistryConfiguration() public {
        vm.createSelectFork(vm.envString("FORK_RPC"));
        emit log_named_uint("chainId", block.chainid);
        emit log_named_uint("block", block.number);
        RankedAuction auction = new RankedAuction(
            RankedAuction.Config(payoutWallet, 1000, 0.01 ether, uint64(block.timestamp + 1 hours),
                "ipfs://x/", "The First Signal", "LNTV")
        );
        AuctionEdition edition = auction.edition();
        RoyaltyMarketplace market = edition.marketplace();
        IRegistryView reg = IRegistryView(edition.OPENSEA_TRANSFER_VALIDATOR());
        assertGt(address(reg).code.length, 0, "registry missing");
        assertGt(edition.OPENSEA_SIGNED_ZONE().code.length, 0, "zone missing");

        uint120 before = reg.lastListId();
        emit log_named_uint("lastListId before", before);
        emit log_named_address("list0 owner", reg.listOwners(0));
        address[] memory l0w = reg.getWhitelistedAccounts(0);
        address[] memory l0a = reg.getAuthorizerAccounts(0);
        emit log_named_uint("list0 whitelist size", l0w.length);
        emit log_named_uint("list0 authorizers size", l0a.length);

        // Real registry, real duplicate-add path (SignedZone already an authorizer of list 0).
        vm.prank(payoutWallet);
        edition.configureEnforcedTrading();
        assertTrue(edition.tradingConfigured());
        uint120 listId = edition.tradingListId();
        assertEq(listId, before + 1);
        assertEq(reg.listOwners(listId), address(edition));
        (uint8 level, uint120 appliedList,) = reg.getCollectionSecurityPolicy(address(edition));
        assertEq(level, 4);
        assertEq(appliedList, listId);

        address[] memory ops = reg.getWhitelistedAccountsByCollection(address(edition));
        address[] memory auths = reg.getAuthorizerAccountsByCollection(address(edition));
        for (uint256 i; i < ops.length; ++i) emit log_named_address("LNTV whitelisted operator", ops[i]);
        for (uint256 i; i < auths.length; ++i) emit log_named_address("LNTV authorizer", auths[i]);
        assertEq(ops.length, l0w.length + 1, "expected list0 operators + local market");
        assertEq(auths.length, 1, "expected exactly SignedZone");
        assertEq(auths[0], edition.OPENSEA_SIGNED_ZONE());

        // Mint via the auction path so we can exercise the real registry's validateTransfer.
        vm.warp(auction.endTime());
        auction.settle();
        uint256[] memory one = new uint256[](1);
        one[0] = 91;
        vm.prank(payoutWallet);
        auction.claimReserved(1, alice);
        assertEq(edition.ownerOf(91), alice);

        // Direct owner transfer blocked (level 4 OTC disabled) by the REAL registry.
        vm.prank(alice);
        vm.expectRevert();
        edition.transferFrom(alice, bob, 91);
        // Random approved operator blocked.
        FreeOperatorFork op = new FreeOperatorFork();
        vm.prank(alice);
        edition.setApprovalForAll(address(op), true);
        vm.expectRevert();
        op.move(edition, alice, bob, 91);
        // Local marketplace (whitelisted by the copy) can transfer: sale with royalty.
        vm.prank(alice);
        edition.setApprovalForAll(address(market), true);
        vm.prank(alice);
        uint256 lid = market.list(91, 1 ether, uint64(block.timestamp + 1 days));
        vm.deal(bob, 2 ether);
        vm.prank(bob);
        market.buy{ value: 1 ether }(lid, bob);
        assertEq(edition.ownerOf(91), bob);
        assertEq(market.pendingRoyalties(), 0.1 ether);
        // PaymentProcessor operators inherited from list 0 pass the registry's operator check for LNTV
        // (the registry check alone; PP itself only transfers inside a paid sale).
        vm.prank(address(edition));
        reg.validateTransfer(PP1, bob, alice, 91);
        vm.prank(address(edition));
        reg.validateTransfer(PP2, bob, alice, 91);
        vm.prank(address(edition));
        vm.expectRevert();
        reg.validateTransfer(address(op), bob, alice, 91);

        // Payout wallet is recognised as collection owner by the REAL registry (trusted-admin surface).
        vm.prank(payoutWallet);
        reg.setTransferSecurityLevelOfCollection(address(edition), 1);
        (level,,) = reg.getCollectionSecurityPolicy(address(edition));
        assertEq(level, 1);
        vm.prank(bob);
        edition.transferFrom(bob, alice, 91); // OTC now open, no royalty
        assertEq(edition.ownerOf(91), alice);
    }
}
