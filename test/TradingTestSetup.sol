// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import {
    StrictAuthorizedTransferSecurityRegistry
} from "./vendor/opensea/src/StrictAuthorizedTransferSecurityRegistry.sol";

abstract contract TradingTestSetup is Test {
    function configureTrading(AuctionEdition token, address admin) internal {
        if (token.OPENSEA_TRANSFER_VALIDATOR().code.length == 0) {
            StrictAuthorizedTransferSecurityRegistry registry =
                new StrictAuthorizedTransferSecurityRegistry(address(this), address(0));
            vm.etch(token.OPENSEA_TRANSFER_VALIDATOR(), address(registry).code);
        }
        vm.prank(admin);
        token.configureEnforcedTrading();
    }
}
