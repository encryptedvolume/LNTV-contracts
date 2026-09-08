// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract MetadataTest is TestBase {
    function testDistinctOffchainEndpointsForAuctionAndReservedNfts() public {
        mintForMarket();
        assertEq(edition.tokenURI(1), "ipfs://edition-metadata/1.json");
        assertEq(edition.tokenURI(90), "ipfs://edition-metadata/90.json");
        assertEq(edition.tokenURI(91), "ipfs://edition-metadata/91.json");
        assertEq(edition.tokenURI(100), "ipfs://edition-metadata/100.json");
        assertTrue(edition.supportsInterface(0x49064906));
    }

    function testBaseEndpointMustEndWithSlash() public {
        RankedAuction.Config memory c = config();
        c.metadataURI = "https://metadata.example/nfts";
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        new RankedAuction(c);
        c.metadataURI = "https://metadata.example/nfts/";
        RankedAuction replacement = new RankedAuction(c);
        assertEq(replacement.edition().metadataURI(), c.metadataURI);
    }

    function testNoOnchainRevealAuthority() public {
        mintForMarket();
        vm.prank(payoutWallet);
        (bool enabled,) = address(edition).call(abi.encodeWithSignature("enableReveals(string)", "https://changed/"));
        assertFalse(enabled);
        vm.prank(alice);
        (bool revealed,) = address(edition).call(abi.encodeWithSignature("reveal(uint256)", 1));
        assertFalse(revealed);
        assertEq(edition.tokenURI(1), "ipfs://edition-metadata/1.json");
        assertEq(edition.transferNonce(1), 0);
    }
}
