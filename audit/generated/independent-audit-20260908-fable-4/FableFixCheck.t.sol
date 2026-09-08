// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Fable fourth pass: verifies the recommended F4-01 fix (ignore ERC721-C validator auto-approval) as a subclass.
import { Test } from "forge-std/Test.sol";
import { AuctionEdition } from "../../src/AuctionEdition.sol";
import { ERC721 } from "../../lib/openzeppelin-contracts-v4/contracts/token/ERC721/ERC721.sol";
import { TradingTestSetup } from "../TradingTestSetup.sol";
import { EvilValidator } from "./FableFourthPass.t.sol";

interface IPayoutStub {
    function payoutWallet() external view returns (address);
}

/// @dev Identical to AuctionEdition except the validator is never an implicit operator.
contract HardenedEdition is AuctionEdition {
    constructor(string memory n, string memory s, string memory u, uint96 bps) AuctionEdition(n, s, u, bps) { }

    function isApprovedForAll(address owner_, address operator) public view override returns (bool) {
        return ERC721.isApprovedForAll(owner_, operator); // OZ 4.8.3 base: explicit approvals only
    }
}

contract FableFixCheckTest is TradingTestSetup, IPayoutStub {
    address internal wallet = address(0x71EA5);
    address internal alice = address(0xA11CE);

    function payoutWallet() external view returns (address) {
        return wallet;
    }

    function _mintOne(AuctionEdition token) internal {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        token.mint(alice, ids); // this test contract is `auction` (msg.sender at construction)
    }

    function testHardenedEditionResistsValidatorAutoApprovalSeizure() public {
        HardenedEdition token = new HardenedEdition("H", "H", "ipfs://h/", 1000);
        configureTrading(token, wallet);
        _mintOne(token);
        EvilValidator evil = new EvilValidator();
        vm.startPrank(wallet);
        token.setTransferValidator(address(evil));
        token.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.stopPrank();
        assertTrue(token.autoApproveTransfersFromValidator());
        assertFalse(token.isApprovedForAll(alice, address(evil)));
        vm.expectRevert(bytes("ERC721: caller is not token owner or approved"));
        evil.take(token, alice, wallet, 1);
        assertEq(token.ownerOf(1), alice);
        // Normal approvals still work for a whitelisted operator path (local market whitelisted by configuration).
        address marketAddress = address(token.marketplace());
        vm.prank(alice);
        token.setApprovalForAll(marketAddress, true);
        assertTrue(token.isApprovedForAll(alice, marketAddress));
    }

    function testUnpatchedEditionIsSeizable() public {
        AuctionEdition token = new AuctionEdition("U", "U", "ipfs://u/", 1000);
        configureTrading(token, wallet);
        _mintOne(token);
        EvilValidator evil = new EvilValidator();
        vm.startPrank(wallet);
        token.setTransferValidator(address(evil));
        token.setAutomaticApprovalOfTransfersFromValidator(true);
        vm.stopPrank();
        evil.take(token, alice, wallet, 1);
        assertEq(token.ownerOf(1), wallet);
    }
}
