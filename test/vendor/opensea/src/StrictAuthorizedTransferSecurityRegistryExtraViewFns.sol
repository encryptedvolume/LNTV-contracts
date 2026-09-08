
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Tstorish } from "tstorish/Tstorish.sol";

import { TransferSecurityLevels } from "./interfaces/IStrictAuthorizedTransferSecurityRegistry.sol";

/// @title StrictAuthorizedTransferSecurityRegistryExtraViewFns
/// @dev Additional view functions, called by StrictAuthorizedTransferSecurityRegistry
///      via delegatecall in the fallback.
contract StrictAuthorizedTransferSecurityRegistryExtraViewFns is Tstorish {
    using EnumerableSet for EnumerableSet.AddressSet;

    error StrictAuthorizedTransferSecurityRegistry__NotImplemented();

    struct CollectionSecurityPolicy {
        TransferSecurityLevels transferSecurityLevel;
        uint120 operatorWhitelistId;
        uint120 permittedContractReceiversId;
    }

    struct AccountList {
        EnumerableSet.AddressSet enumerableAccounts;
        mapping (address => bool) nonEnumerableAccounts;
    }

    struct List {
        address owner;
        AccountList authorizers;
        AccountList operators;
    }

    struct CollectionConfiguration {
        uint120 listId;
        bool policyBypassed;
        bool blacklistBased;
        bool directTransfersDisabled;
        bool contractRecipientsDisabled;
        bool signatureRegistrationRequired;
    }

    uint120 private UNUSED_lastListId;

    mapping (uint120 => List) private lists;

    /// @dev Mapping of collection addresses to list ids & security policies.
    mapping (address => CollectionConfiguration) private collectionConfiguration;

    // view functions from other transfer security registries, included for completeness
    function getBlacklistedAccounts(uint120) external pure returns (address[] memory) {}
    function getWhitelistedAccounts(uint120 id) external view returns (address[] memory) {
        return lists[id].operators.enumerableAccounts.values();
    }
    function getBlacklistedCodeHashes(uint120) external pure returns (bytes32[] memory) {}
    function getWhitelistedCodeHashes(uint120) external pure returns (bytes32[] memory) {}
    function isAccountBlacklisted(uint120, address) external pure returns (bool) {
        return false;
    }
    function isAccountWhitelisted(uint120 id, address account) external view returns (bool) {
        return lists[id].operators.nonEnumerableAccounts[account];
    }
    function isCodeHashBlacklisted(uint120, bytes32) external pure returns (bool) {
        return false;
    }
    function isCodeHashWhitelisted(uint120, bytes32) external pure returns (bool) {
        return false;
    }
    function getBlacklistedAccountsByCollection(address) external pure returns (address[] memory) {}
    function getWhitelistedAccountsByCollection(address collection) external view returns (address[] memory) {
        return lists[collectionConfiguration[collection].listId].operators.enumerableAccounts.values();
    }
    function getBlacklistedCodeHashesByCollection(address) external pure returns (bytes32[] memory) {}
    function getWhitelistedCodeHashesByCollection(address) external pure returns (bytes32[] memory) {}
    function isAccountBlacklistedByCollection(address, address) external pure returns (bool) {
        return false;
    }
    function isAccountWhitelistedByCollection(
        address collection, address account
    ) external view returns (bool) {
        return lists[collectionConfiguration[collection].listId].operators.nonEnumerableAccounts[account];
    }
    function isCodeHashBlacklistedByCollection(address, bytes32) external pure returns (bool) {
        return false;
    }
    function isCodeHashWhitelistedByCollection(address, bytes32) external pure returns (bool) {
        return false;
    }
    function getCollectionSecurityPolicy(
        address collection
    ) external view returns (CollectionSecurityPolicy memory) {
        CollectionConfiguration memory config = collectionConfiguration[collection];

        return CollectionSecurityPolicy({
            transferSecurityLevel: _getSecurityLevel(config),
            operatorWhitelistId: config.listId,
            permittedContractReceiversId: 0
        });
    }
    function getWhitelistedOperators(uint120 id) external view returns (address[] memory) {
        return lists[id].operators.enumerableAccounts.values();
    }
    function getPermittedContractReceivers(uint120) external pure returns (address[] memory) {}
    function isOperatorWhitelisted(uint120 id, address operator) external view returns (bool) {
        return lists[id].operators.nonEnumerableAccounts[operator];
    }
    function isContractReceiverPermitted(uint120, address) external pure returns (bool) {
        return true;
    }

    function _getSecurityLevel(
        CollectionConfiguration memory config
    ) internal pure returns (TransferSecurityLevels level) {
        bool policyBypassed = config.policyBypassed;
        bool blacklistBased = config.blacklistBased;
        bool directTransfersDisabled = config.directTransfersDisabled;
        bool contractRecipientsDisabled = config.contractRecipientsDisabled;
        bool signatureRegistrationRequired = config.signatureRegistrationRequired;

        if (policyBypassed) {
            return TransferSecurityLevels.One;
        }

        if (blacklistBased) {
            return TransferSecurityLevels.Two;
        }

        if (directTransfersDisabled) {
            if (signatureRegistrationRequired) {
                return TransferSecurityLevels.Eight;
            } else if (contractRecipientsDisabled) {
                return TransferSecurityLevels.Seven;
            }

            return TransferSecurityLevels.Four;
        }

        if (signatureRegistrationRequired) {
            return TransferSecurityLevels.Six;
        } else if (contractRecipientsDisabled) {
            return TransferSecurityLevels.Five;
        }

        return TransferSecurityLevels.Three;
    }

    fallback() external {
        revert StrictAuthorizedTransferSecurityRegistry__NotImplemented();
    }
}