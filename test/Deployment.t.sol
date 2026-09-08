// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { RankedAuction } from "../src/RankedAuction.sol";

contract DeploymentTest is Test {
    Deploy internal deployment;
    Deploy.DeploymentConfig internal input;

    function setUp() public {
        vm.chainId(31337);
        vm.warp(1_000_000);
        deployment = new Deploy();
        input = Deploy.DeploymentConfig(
            31337, 1003600, 0.01 ether, 1000, address(0x123), "ipfs://deployment-test/", "Deployment NFTs", "DEP"
        );
    }

    function testValidatesDeploymentConfiguration() public view {
        RankedAuction.Config memory c = deployment.validateConfig(input);
        assertEq(c.payoutWallet, address(0x123));
        assertEq(c.reservePrice, 0.01 ether);
        assertEq(c.startTime, 1003600);
    }

    function testDeploymentRunLoadsEnvironmentAndBindsAllContracts() public {
        vm.setEnv("CHAIN_ID", "31337");
        vm.setEnv("START_TIME", "1003600");
        vm.setEnv("RESERVE_WEI", "10000000000000000");
        vm.setEnv("ROYALTY_BPS", "1000");
        vm.setEnv("PAYOUT_WALLET", vm.toString(input.payoutWallet));
        vm.setEnv("METADATA_URI", input.uri);
        vm.setEnv("COLLECTION_NAME", input.collectionName);
        vm.setEnv("COLLECTION_SYMBOL", input.collectionSymbol);
        RankedAuction deployed = deployment.run();
        assertEq(deployed.edition().auction(), address(deployed));
        assertEq(deployed.edition().marketplace().edition(), address(deployed.edition()));
        assertEq(deployed.payoutWallet(), input.payoutWallet);
        assertEq(deployed.reservePrice(), input.reserve);
        assertEq(deployed.edition().name(), input.collectionName);
        assertEq(deployed.edition().symbol(), input.collectionSymbol);
    }

    function testChainMismatchAndUnsupportedNetwork() public {
        vm.chainId(1);
        vm.expectRevert("CHAIN_ID does not match RPC");
        deployment.validateConfig(input);
        vm.chainId(42);
        input.chainId = 42;
        vm.expectRevert("Unsupported Ethereum chain");
        deployment.validateConfig(input);
    }

    function testNoSilentNumericTruncation() public {
        input.reserve = uint256(type(uint128).max) + 1;
        vm.expectRevert("Invalid reserve");
        deployment.validateConfig(input);
        input.reserve = 1;
        input.bps = type(uint256).max;
        vm.expectRevert("Invalid royalty basis points");
        deployment.validateConfig(input);
        input.bps = 1000;
        input.start = type(uint64).max;
        assertEq(deployment.validateConfig(input).startTime, type(uint64).max);
        input.start = type(uint256).max;
        vm.expectRevert("Time exceeds uint64 range");
        deployment.validateConfig(input);
    }

    function testLeadTimeAndFixed48HourDuration() public {
        input.start = 1000599;
        vm.expectRevert("Allow at least 10 minutes before bidding");
        deployment.validateConfig(input);
        input.start = 1000600;
        RankedAuction a = new RankedAuction(deployment.validateConfig(input));
        assertEq(a.initialEndTime(), uint256(a.startTime()) + 48 hours);
        assertEq(a.endTime(), a.initialEndTime());
    }

    function testRejectsZeroPayoutAndEmptyMetadata() public {
        input.payoutWallet = address(0);
        vm.expectRevert("Zero payout wallet");
        deployment.validateConfig(input);
        input.payoutWallet = address(0x123);
        input.uri = "";
        vm.expectRevert("Empty metadata URI");
        deployment.validateConfig(input);
        input.uri = "ipfs://test/";
        input.collectionName = "";
        vm.expectRevert("Empty collection name or symbol");
        deployment.validateConfig(input);
        input.collectionName = "NFTs";
        input.collectionSymbol = "";
        vm.expectRevert("Empty collection name or symbol");
        deployment.validateConfig(input);
    }
}
