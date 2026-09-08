// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

/// @notice Atomic deployment: auction constructs and irrevocably binds edition and marketplace.
/// @dev Uses Foundry's keystore/hardware-wallet signing. Never reads or prints a private key.
contract Deploy is Script {
    struct DeploymentConfig {
        uint256 chainId;
        uint256 start;
        uint256 reserve;
        uint256 bps;
        address payoutWallet;
        string uri;
        string collectionName;
        string collectionSymbol;
    }

    function loadConfig() public view returns (RankedAuction.Config memory) {
        DeploymentConfig memory input;
        input.chainId = vm.envUint("CHAIN_ID");
        input.start = vm.envUint("START_TIME");
        input.reserve = vm.envUint("RESERVE_WEI");
        input.bps = vm.envUint("ROYALTY_BPS");
        input.payoutWallet = vm.envAddress("PAYOUT_WALLET");
        input.uri = vm.envString("METADATA_URI");
        input.collectionName = vm.envString("COLLECTION_NAME");
        input.collectionSymbol = vm.envString("COLLECTION_SYMBOL");
        return validateConfig(input);
    }

    function validateConfig(DeploymentConfig memory input) public view returns (RankedAuction.Config memory c) {
        require(input.chainId == block.chainid, "CHAIN_ID does not match RPC");
        require(input.chainId == 1 || input.chainId == 11155111 || input.chainId == 31337, "Unsupported Ethereum chain");
        require(input.start >= block.timestamp + 10 minutes, "Allow at least 10 minutes before bidding");
        require(input.start <= type(uint64).max, "Time exceeds uint64 range");
        require(input.reserve > 0 && input.reserve <= type(uint128).max, "Invalid reserve");
        require(input.bps > 0 && input.bps <= 10000, "Invalid royalty basis points");
        require(input.bps == 1000, "LNTV deployment requires 10 percent royalties");
        c = RankedAuction.Config(
            input.payoutWallet,
            uint96(input.bps),
            uint128(input.reserve),
            uint64(input.start),
            input.uri,
            input.collectionName,
            input.collectionSymbol
        );
        require(c.payoutWallet != address(0), "Zero payout wallet");
        require(bytes(c.metadataURI).length > 0, "Empty metadata URI");
        require(
            bytes(c.metadataURI)[bytes(c.metadataURI).length - 1] == bytes1("/"), "Metadata base must end with slash"
        );
        require(
            bytes(c.collectionName).length > 0 && bytes(c.collectionSymbol).length > 0,
            "Empty collection name or symbol"
        );
    }

    function run() external returns (RankedAuction deployed) {
        RankedAuction.Config memory c = loadConfig();
        console2.log("Chain ID", block.chainid);
        console2.log("Shared payout wallet", c.payoutWallet);
        console2.log("Royalty BPS", c.royaltyBps);
        console2.log("Reserve (wei)", c.reservePrice);
        console2.log("Start (unix seconds)", c.startTime);
        console2.log("Initial end (unix seconds)", uint256(c.startTime) + 48 hours);
        console2.log("Initial off-chain metadata base URI", c.metadataURI);
        console2.log("ERC-721 collection name", c.collectionName);
        console2.log("ERC-721 symbol", c.collectionSymbol);
        vm.startBroadcast();
        deployed = new RankedAuction(c);
        vm.stopBroadcast();
        require(deployed.edition().auction() == address(deployed), "Auction binding mismatch");
        require(
            deployed.edition().marketplace().edition() == address(deployed.edition()), "Marketplace binding mismatch"
        );
        console2.log("Auction", address(deployed));
        console2.log("Edition", address(deployed.edition()));
        console2.log("Royalty marketplace", address(deployed.edition().marketplace()));
    }
}
