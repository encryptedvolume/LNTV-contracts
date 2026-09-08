// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";

/// @notice Run as the current payout wallet after deployment and before opening secondary trading.
/// @dev Uses existing OpenSea infrastructure. OpenSea Studio earnings activation is a separate required step.
contract ConfigureTrading is Script {
    function run() external {
        require(vm.envUint("CHAIN_ID") == block.chainid, "CHAIN_ID does not match RPC");
        require(block.chainid == 1 || block.chainid == 11155111 || block.chainid == 31337, "Unsupported Ethereum chain");
        AuctionEdition edition = AuctionEdition(vm.envAddress("EDITION_ADDRESS"));
        require(edition.owner() == vm.envAddress("PAYOUT_WALLET"), "Unexpected payout wallet");
        require(edition.royaltyBps() == 1000, "LNTV deployment requires 10 percent royalties");
        require(
            edition.OPENSEA_TRANSFER_VALIDATOR().code.length > 0, "Supported registry is not deployed on this chain"
        );
        vm.startBroadcast();
        edition.configureEnforcedTrading();
        vm.stopBroadcast();
        require(edition.tradingConfigured(), "Trading configuration failed");
        require(edition.getTransferValidator() == edition.OPENSEA_TRANSFER_VALIDATOR(), "Unexpected validator");
        console2.log("Edition", address(edition));
        console2.log("Royalty recipient", edition.royaltyRecipient());
        console2.log("Royalty BPS", edition.royaltyBps());
        console2.log("Transfer validator", edition.getTransferValidator());
        console2.log("Trading list", edition.tradingListId());
        console2.log("Next: enable 10 percent enforced earnings for this collection in OpenSea Studio.");
    }
}
