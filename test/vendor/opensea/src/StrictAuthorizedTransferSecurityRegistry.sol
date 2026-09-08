// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ListTypes,
    TransferSecurityLevels,
    IStrictAuthorizedTransferSecurityRegistry
} from "./interfaces/IStrictAuthorizedTransferSecurityRegistry.sol";

import {
    ICreatorTokenTransferValidator
} from "./interfaces/ICreatorTokenTransferValidator.sol";

import { IOwnable } from "./interfaces/IOwnable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { Tstorish } from "tstorish/Tstorish.sol";

import { IEOARegistry } from "./interfaces/IEOARegistry.sol";

import {
    StrictAuthorizedTransferSecurityRegistryExtraViewFns
} from "./StrictAuthorizedTransferSecurityRegistryExtraViewFns.sol";

/// @title StrictAuthorizedTransferSecurityRegistry
/// @dev Implementation of a simplified version of the Transfer Security Registry that only
///      supports authorizers and whitelisted operators, and allows collections to disable
///      direct transfers (where caller == from) and contract recipients (requiring EOA
///      registration by providing a signature). Note that a number of view functions on
///      collections that add this validator will not work.
contract StrictAuthorizedTransferSecurityRegistry is Tstorish, IStrictAuthorizedTransferSecurityRegistry, ERC165 {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev This struct is used internally to represent an enumerable list of accounts.
     */
    struct AccountList {
        EnumerableSet.AddressSet enumerableAccounts;
        mapping (address => bool) nonEnumerableAccounts;
    }

    /**
     * @dev This struct is used internally for the storage of authorizer + operator lists.
     */
    struct List {
        address owner;
        AccountList authorizers;
        AccountList operators;
        AccountList blacklist;
    }

    struct CollectionConfiguration {
        uint120 listId;
        bool policyBypassed;
        bool blacklistBased;
        bool directTransfersDisabled;
        bool contractRecipientsDisabled;
        bool signatureRegistrationRequired;
    }
    
    /// @dev The default admin role value for contracts that implement access control.
    bytes32 private constant DEFAULT_ACCESS_CONTROL_ADMIN_ROLE = 0x00;

    /// @notice Keeps track of the most recently created list id.
    uint120 public lastListId;

    /// @dev Mapping of list ids to list settings
    mapping (uint120 => List) private lists;

    /// @dev Mapping of collection addresses to list ids & security policies.
    mapping (address => CollectionConfiguration) private collectionConfiguration;

    // TSTORE slot: scope ++ 8 empty bytes ++ collection
    bytes4 private constant _AUTHORIZED_OPERATOR_SCOPE = 0x596a397a;

    // TSTORE slot: keccak256(scope ++ identifier ++ collection)
    bytes4 private constant _AUTHORIZED_IDENTIFIER_SCOPE = 0x7e746c61;

    // TSTORE slot: keccak256(scope ++ identifier ++ collection)
    bytes4 private constant _AUTHORIZED_AMOUNT_SCOPE = 0x71836d45;

    address private immutable _EXTRA_VIEW_FUNCTIONS;

    IEOARegistry private immutable _EOA_REGISTRY;

    /**
     * @dev This modifier restricts a function call to the owner of the list `id`.
     * @dev Throws when the caller is not the list owner.
     */
    modifier onlyListOwner(uint120 id) {
        _requireCallerOwnsList(id);
        _;
    }

    /**
     * @dev This modifier reverts a transaction if the supplied array has a zero length.
     * @dev Throws when the array parameter has a zero length.
     */
    modifier notZero(uint256 value) {
        if (value == 0) {
            revert StrictAuthorizedTransferSecurityRegistry__ArrayLengthCannotBeZero();
        }
        _;
    }

    constructor(address defaultOwner, address eoaRegistry) {
        uint120 id = 0;

        lists[id].owner = defaultOwner;

        emit CreatedList(id, "DEFAULT LIST");
        emit ReassignedListOwnership(id, defaultOwner);

        // Deploy a contract containing legacy view functions.
        _EXTRA_VIEW_FUNCTIONS = address(new StrictAuthorizedTransferSecurityRegistryExtraViewFns());

        _EOA_REGISTRY = IEOARegistry(eoaRegistry);
    }

    // Delegatecall to contract with legacy view functions in the fallback.
    fallback() external {
        address target = _EXTRA_VIEW_FUNCTIONS;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let status := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch status
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// Manage lists of authorizers & operators that can be applied to collections
    function createList(string calldata name) external returns (uint120) {
        uint120 id = ++lastListId;

        lists[id].owner = msg.sender;

        emit CreatedList(id, name);
        emit ReassignedListOwnership(id, msg.sender);

        return id;
    }

    function createListCopy(string calldata name, uint120 sourceListId) external override returns (uint120) {
        uint120 id = ++lastListId;

        unchecked {
            if (sourceListId > id - 1) {
                revert StrictAuthorizedTransferSecurityRegistry__ListDoesNotExist();
            }
        }
        List storage sourceList = lists[sourceListId];
        List storage targetList = lists[id];

        targetList.owner = msg.sender;

        emit CreatedList(id, name);
        emit ReassignedListOwnership(id, msg.sender);

        _copyAddressSet(ListTypes.AuthorizerList, id, sourceList.authorizers, targetList.authorizers);
        _copyAddressSet(ListTypes.OperatorList, id, sourceList.operators, targetList.operators);
        _copyAddressSet(ListTypes.OperatorRequiringAuthorizationList, id, sourceList.blacklist, targetList.blacklist);

        return id;
    }

    function reassignOwnershipOfList(uint120 id, address newOwner) external onlyListOwner(id) {
        if (newOwner == address(0)) {
            revert StrictAuthorizedTransferSecurityRegistry__ListOwnershipCannotBeTransferredToZeroAddress();
        }

        lists[id].owner = newOwner;

        emit ReassignedListOwnership(id, newOwner);
    }

    function renounceOwnershipOfList(uint120 id) external onlyListOwner(id) {
        lists[id].owner = address(0);

        emit ReassignedListOwnership(id, address(0));
    }

    function applyListToCollection(address collection, uint120 id) external {
        _requireCallerIsNFTOrContractOwnerOrAdmin(collection);

        if (id > lastListId) {
            revert StrictAuthorizedTransferSecurityRegistry__ListDoesNotExist();
        }

        collectionConfiguration[collection].listId = id;

        emit AppliedListToCollection(collection, id);
    }

    function listOwners(uint120 id) external view returns (address) {
        return lists[id].owner;
    }

    /// Manage and query for authorizers on lists
    function addAccountToAuthorizers(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _addAccounts(id, accounts, lists[id].authorizers, ListTypes.AuthorizerList);
    }

    function addAccountsToAuthorizers(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _addAccounts(id, accounts, lists[id].authorizers, ListTypes.AuthorizerList);
    }

    function addAuthorizers(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _addAccounts(id, accounts, lists[id].authorizers, ListTypes.AuthorizerList);
    }

    function removeAccountFromAuthorizers(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _removeAccounts(id, accounts, lists[id].authorizers, ListTypes.AuthorizerList);
    }
    
    function removeAccountsFromAuthorizers(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _removeAccounts(id, accounts, lists[id].authorizers, ListTypes.AuthorizerList);
    }

    function getAuthorizerAccounts(uint120 id) external view returns (address[] memory) {
        return lists[id].authorizers.enumerableAccounts.values();
    }

    function isAccountAuthorizer(uint120 id, address account) external view returns (bool) {
        return lists[id].authorizers.nonEnumerableAccounts[account];
    }

    function getAuthorizerAccountsByCollection(address collection) external view returns (address[] memory) {
        return lists[collectionConfiguration[collection].listId].authorizers.enumerableAccounts.values();
    }

    function isAccountAuthorizerOfCollection(address collection, address account) external view returns (bool) {
        return lists[collectionConfiguration[collection].listId].authorizers.nonEnumerableAccounts[account];
    }

    function _ensureCallerIsCollectionAuthorizer(address collection) internal view {
        if (!lists[collectionConfiguration[collection].listId].authorizers.nonEnumerableAccounts[msg.sender]) {
            revert StrictAuthorizedTransferSecurityRegistry__CallerIsNotValidAuthorizer();
        }
    }

    /// Manage and query for operators on lists
    function addAccountToWhitelist(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _addAccounts(id, accounts, lists[id].operators, ListTypes.OperatorList);
    }

    function addAccountsToWhitelist(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _addAccounts(id, accounts, lists[id].operators, ListTypes.OperatorList);
    }

    function addOperators(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _addAccounts(id, accounts, lists[id].operators, ListTypes.OperatorList);
    }

    function removeAccountFromWhitelist(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _removeAccounts(id, accounts, lists[id].operators, ListTypes.OperatorList);
    }

    function removeAccountsFromWhitelist(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _removeAccounts(id, accounts, lists[id].operators, ListTypes.OperatorList);
    }
    
    function getWhitelistedAccounts(uint120 id) external view returns (address[] memory) {
        return lists[id].operators.enumerableAccounts.values();
    }

    function isAccountWhitelisted(uint120 id, address account) external view returns (bool) {
        return lists[id].operators.nonEnumerableAccounts[account];
    }
    function getWhitelistedAccountsByCollection(address collection) external view returns (address[] memory) {
        return lists[collectionConfiguration[collection].listId].operators.enumerableAccounts.values();
    }

    function isAccountWhitelistedByCollection(address collection, address account) external view returns (bool) {
        return lists[collectionConfiguration[collection].listId].operators.nonEnumerableAccounts[account];
    }

    /// Manage and query for blacklists on lists
    function addAccountToBlacklist(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _addAccounts(id, accounts, lists[id].blacklist, ListTypes.OperatorRequiringAuthorizationList);
    }

    function addAccountsToBlacklist(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _addAccounts(id, accounts, lists[id].blacklist, ListTypes.OperatorRequiringAuthorizationList);
    }

    function removeAccountFromBlacklist(uint120 id, address account) external onlyListOwner(id) {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _removeAccounts(id, accounts, lists[id].blacklist, ListTypes.OperatorRequiringAuthorizationList);
    }

    function removeAccountsFromBlacklist(uint120 id, address[] calldata accounts) external onlyListOwner(id) notZero(accounts.length) {
        _removeAccounts(id, accounts, lists[id].blacklist, ListTypes.OperatorRequiringAuthorizationList);
    } 

    function getBlacklistedAccounts(uint120 id) external view returns (address[] memory) {
        return lists[id].blacklist.enumerableAccounts.values();
    }

    function isAccountBlacklisted(uint120 id, address account) external view returns (bool) {
        return lists[id].blacklist.nonEnumerableAccounts[account];
    }
    function getBlacklistedAccountsByCollection(address collection) external view returns (address[] memory) {
        return lists[collectionConfiguration[collection].listId].blacklist.enumerableAccounts.values();
    }

    function isAccountBlacklistedByCollection(address collection, address account) external view returns (bool) {
        return lists[collectionConfiguration[collection].listId].blacklist.nonEnumerableAccounts[account];
    }

    /// Ensure that a specific operator has been authorized to transfer tokens
    function validateTransfer(address caller, address from, address to) external view {
        _validateTransfer(caller, from, to);
    }

    /// Ensure that a transfer has been authorized for a specific tokenId
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view {
        _validateTransferByIdentifer(caller, from, to, tokenId);
    }

    /// Ensure that a transfer has been authorized for a specific amount of a specific tokenId, and
    /// reduce the transferable amount remaining
    function validateTransfer(address caller, address from, address to, uint256 tokenId, uint256 amount) external {
        _validateTransferByAmount(caller, from, to, tokenId, amount);
    }

    /// Legacy alias for validateTransfer (address caller, address from, address to)
    function applyCollectionTransferPolicy(address caller, address from, address to) external view {
        _validateTransfer(caller, from, to);
    }

    /// Temporarily assign a specific allowed operator for a given collection
    function beforeAuthorizedTransfer(address operator, address token) external {
        _ensureCallerIsCollectionAuthorizer(token);

        _setTstorish(
            _getAuthorizedOperatorSlot(token),
            uint256(uint160(operator))
        );
    }

    /// Clear assignment of a specific allowed operator for a given collection
    function afterAuthorizedTransfer(address token) external {
        _ensureCallerIsCollectionAuthorizer(token);

        _clearTstorish(_getAuthorizedOperatorSlot(token));
    }

    /// Temporarily allow a specific tokenId from a given collection to be transferred
    function beforeAuthorizedTransfer(address token, uint256 tokenId) external {
        _ensureCallerIsCollectionAuthorizer(token);

        _setTstorish(
            _getAuthorizedIdentifierSlot(token, tokenId),
            1
        );
    }

    /// Clear assignment of an specific tokenId's transfer allowance
    function afterAuthorizedTransfer(address token, uint256 tokenId) external {
        _ensureCallerIsCollectionAuthorizer(token);

        _clearTstorish(_getAuthorizedIdentifierSlot(token, tokenId));
    }

    /// Temporarily allow a specific amount of a specific tokenId from a given collection to be transferred
    function beforeAuthorizedTransferWithAmount(address token, uint256 tokenId, uint256 amount) external {
        _ensureCallerIsCollectionAuthorizer(token);

        uint256 slot = _getAuthorizedAmountSlot(token, tokenId);

        uint256 currentAmount = _getTstorish(slot);

        uint256 newAmount = currentAmount + amount;

        _setTstorish(slot, newAmount);
    }

    /// Clear assignment of a tokenId's transfer allowance for a specific amount
    function afterAuthorizedTransferWithAmount(address token, uint256 tokenId) external {
        _ensureCallerIsCollectionAuthorizer(token);

        _clearTstorish(_getAuthorizedAmountSlot(token, tokenId));
    }

    function setTransferSecurityLevelOfCollection(
        address collection,
        uint8 level,
        bool enableAuthorizationMode,
        bool authorizersCanSetWildcardOperators,
        bool enableAccountFreezingMode
    ) external {
        if (!enableAuthorizationMode || !authorizersCanSetWildcardOperators || enableAccountFreezingMode) {
            revert StrictAuthorizedTransferSecurityRegistry__UnsupportedSecurityLevelDetail();
        }

        _setTransferSecurityLevelOfCollection(collection, TransferSecurityLevels(level));
    }

    function setTransferSecurityLevelOfCollection(
        address collection,
        TransferSecurityLevels level
    ) external {
        _setTransferSecurityLevelOfCollection(collection, level);
    }

    function isVerifiedEOA(address account) external view returns (bool) {
        return _EOA_REGISTRY.isVerifiedEOA(account);
    }

    /// @notice ERC-165 Interface Support
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(ICreatorTokenTransferValidator).interfaceId ||
            interfaceId == type(IStrictAuthorizedTransferSecurityRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _setTransferSecurityLevelOfCollection(
        address collection,
        TransferSecurityLevels level
    ) internal {
        _requireCallerIsNFTOrContractOwnerOrAdmin(collection);

        if (level == TransferSecurityLevels.Recommended) {
            level = TransferSecurityLevels.Three;
        }

        CollectionConfiguration storage config = collectionConfiguration[collection];
        
        if (level == TransferSecurityLevels.One) {
            config.policyBypassed = true;
            config.blacklistBased = false;
            config.directTransfersDisabled = false;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Two) {
            config.policyBypassed = false;
            config.blacklistBased = true;
            config.directTransfersDisabled = false;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Three) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = false;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Four) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = true;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Five) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = false;
            config.contractRecipientsDisabled = true;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Six) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = false;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = true;
        } else if (level == TransferSecurityLevels.Seven) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = true;
            config.contractRecipientsDisabled = true;
            config.signatureRegistrationRequired = false;
        } else if (level == TransferSecurityLevels.Eight) {
            config.policyBypassed = false;
            config.blacklistBased = false;
            config.directTransfersDisabled = true;
            config.contractRecipientsDisabled = false;
            config.signatureRegistrationRequired = true;
        } else {
            revert StrictAuthorizedTransferSecurityRegistry__UnsupportedSecurityLevel();
        }

        emit SetTransferSecurityLevel(collection, level);
    }

    /**
     * @notice Copies all addresses in `ptrFromList` to `ptrToList`.
     * 
     * @dev    This function will copy all addresses from one list to another list.
     * @dev    Note: If used to copy adddresses to an existing list the current list contents will not be
     * @dev    deleted before copying. New addresses will be appeneded to the end of the list and the
     * @dev    non-enumerable mapping key value will be set to true.
     * 
     * @dev <h4>Postconditions:</h4>
     *      1. Addresses in from list that are not already present in to list are added to the to list.
     *      2. Emits an `AddedAccountToList` event for each address copied to the list.
     * 
     * @param  listType          The type of list addresses are being copied from and to.
     * @param  destinationListId The id of the list being copied to.
     * @param  ptrFromList       The storage pointer for the list being copied from.
     * @param  ptrToList         The storage pointer for the list being copied to.
     */
    function _copyAddressSet(
        ListTypes listType,
        uint120 destinationListId,
        AccountList storage ptrFromList,
        AccountList storage ptrToList
    ) private {
        EnumerableSet.AddressSet storage ptrFromSet = ptrFromList.enumerableAccounts;
        EnumerableSet.AddressSet storage ptrToSet = ptrToList.enumerableAccounts;
        mapping (address => bool) storage ptrToNonEnumerableSet = ptrToList.nonEnumerableAccounts;
        uint256 sourceLength = ptrFromSet.length();
        address account;
        for (uint256 i = 0; i < sourceLength;) {
            account = ptrFromSet.at(i); 
            if (ptrToSet.add(account)) {
                emit AddedAccountToList(listType, destinationListId, account);
                ptrToNonEnumerableSet[account] = true;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Requires the caller to be the owner of list `id`.
     * 
     * @dev    Throws when the caller is not the owner of the list.
     */
    function _requireCallerOwnsList(uint120 id) private view {
        if (msg.sender != lists[id].owner) {
            revert StrictAuthorizedTransferSecurityRegistry__CallerDoesNotOwnList();
        }
    }

    /**
     * @notice Reverts the transaction if the caller is not the owner or assigned the default
     * @notice admin role of the contract at `tokenAddress`.
     *
     * @dev    Throws when the caller is neither owner nor assigned the default admin role.
     * 
     * @param tokenAddress The contract address of the token to check permissions for.
     */
    function _requireCallerIsNFTOrContractOwnerOrAdmin(address tokenAddress) internal view {
        if (msg.sender == tokenAddress) {
            return;
        }

        if (msg.sender == _safeOwner(tokenAddress)) {
            return;
        }

        if (!_safeHasRole(tokenAddress)) {
            revert StrictAuthorizedTransferSecurityRegistry__CallerMustHaveElevatedPermissionsForSpecifiedNFT();
        }
    }

    /**
     * @dev A gas efficient, and fallback-safe way to call the owner function on a token contract.
     *      This will get the owner if it exists - and when the function is unimplemented, the
     *      presence of a fallback function will not result in halted execution.
     */
    function _safeOwner(
        address tokenAddress
    ) internal view returns(address owner) {
        assembly {
            mstore(0x00, 0x8da5cb5b)
            let status := staticcall(gas(), tokenAddress, 0x1c, 0x04, 0x00, 0x20)
            if and(iszero(lt(returndatasize(), 0x20)), status) {
                owner := mload(0x00)
            }
        }
    }
    
    /**
     * @dev A gas efficient, and fallback-safe way to call the hasRole function on a token contract.
     *      This will check if the account `hasRole` if `hasRole` exists - and when the function is unimplemented, the
     *      presence of a fallback function will not result in halted execution.
     */
    function _safeHasRole(
        address tokenAddress
    ) internal view returns(bool hasRole) {
        assembly {
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, 0x60))
            mstore(ptr, 0x91d14854)
            mstore(add(0x20, ptr), DEFAULT_ACCESS_CONTROL_ADMIN_ROLE)
            mstore(add(0x40, ptr), caller())
            let status := staticcall(gas(), tokenAddress, add(ptr, 0x1c), 0x44, 0x00, 0x20)
            if and(iszero(lt(returndatasize(), 0x20)), status) {
                hasRole := mload(0x00)
            }
        }
    }


    /**
     * @dev Internal function used to efficiently retrieve the code length of `account`.
     * 
     * @param account The address to get the deployed code length for.
     * 
     * @return length The length of deployed code at the address.
     */
    function _getCodeLengthAsm(address account) internal view returns (uint256 length) {
        assembly { length := extcodesize(account) }
    }

    function _addAccounts(
        uint120 id,
        address[] memory accounts,
        AccountList storage accountList,
        ListTypes listType
    ) internal {
        address account;
        for (uint256 i = 0; i < accounts.length;) {
            account = accounts[i];

            if (account == address(0)) {
                revert StrictAuthorizedTransferSecurityRegistry__ZeroAddressNotAllowed();
            }

            if (accountList.enumerableAccounts.add(account)) {
                emit AddedAccountToList(listType, id, account);
                accountList.nonEnumerableAccounts[account] = true;
            }

            unchecked {
                ++i;
            }
        }
    }

    function _removeAccounts(
        uint120 id,
        address[] memory accounts,
        AccountList storage accountList,
        ListTypes listType
    ) internal {
        address account;
        for (uint256 i = 0; i < accounts.length;) {
            account = accounts[i];

            if (accountList.enumerableAccounts.remove(account)) {
                emit RemovedAccountFromList(listType, id, account);
                delete accountList.nonEnumerableAccounts[account];
            }

            unchecked {
                ++i;
            }
        }
    }

    function _validateTransfer(address operator, address from, address to) internal view {
        CollectionConfiguration memory config = collectionConfiguration[msg.sender];

        if (config.policyBypassed) {
            return;
        }

        if (config.contractRecipientsDisabled) {
            if (to.code.length != 0) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverMustNotHaveDeployedCode();
            }
        }
        
        if (config.signatureRegistrationRequired) {
            if (!_EOA_REGISTRY.isVerifiedEOA(to)) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverProofOfEOASignatureUnverified();
            }
        }

        if (operator == from) {
            if (config.directTransfersDisabled) {
                revert StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator();
            }

            return;
        }

        uint256 slot = _getAuthorizedOperatorSlot(msg.sender);

        if (operator == address(uint160(_getTstorish(slot)))) {
            return;
        }

        if (config.blacklistBased) {
            if (lists[config.listId].blacklist.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        } else {
            if (!lists[config.listId].operators.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        }
    }

    function _validateTransferByIdentifer(address operator, address from, address to, uint256 identifier) internal view {
        CollectionConfiguration memory config = collectionConfiguration[msg.sender];

        if (config.policyBypassed) {
            return;
        }

        if (config.contractRecipientsDisabled) {
            if (to.code.length != 0) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverMustNotHaveDeployedCode();
            }
        }
        
        if (config.signatureRegistrationRequired) {
            if (!_EOA_REGISTRY.isVerifiedEOA(to)) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverProofOfEOASignatureUnverified();
            }
        }

        if (operator == from) {
            if (config.directTransfersDisabled) {
                revert StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator();
            }

            return;
        }

        uint256 slot = _getAuthorizedIdentifierSlot(msg.sender, identifier);

        uint256 authorizedIdentifier = _getTstorish(slot);

        if (authorizedIdentifier != 0) {
            return;
        }

        if (config.blacklistBased) {
            if (lists[config.listId].blacklist.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        } else {
            if (!lists[config.listId].operators.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        }
    }

    function _validateTransferByAmount(address operator, address from, address to, uint256 identifier, uint256 amount) internal {
        CollectionConfiguration memory config = collectionConfiguration[msg.sender];

        if (config.policyBypassed) {
            return;
        }

        if (config.contractRecipientsDisabled) {
            if (to.code.length != 0) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverMustNotHaveDeployedCode();
            }
        }
        
        if (config.signatureRegistrationRequired) {
            if (!_EOA_REGISTRY.isVerifiedEOA(to)) {
                revert StrictAuthorizedTransferSecurityRegistry__ReceiverProofOfEOASignatureUnverified();
            }
        }

        if (operator == from) {
            if (config.directTransfersDisabled) {
                revert StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator();
            }

            return;
        }

        uint256 slot = _getAuthorizedAmountSlot(msg.sender, identifier);

        uint256 authorizedAmount = _getTstorish(slot);
        if (authorizedAmount >= amount) {
            unchecked {
                _setTstorish(slot, authorizedAmount - amount);
            }

            return;
        }

        if (config.blacklistBased) {
            if (lists[config.listId].blacklist.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        } else {
            if (!lists[config.listId].operators.nonEnumerableAccounts[operator]) {
                revert StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
            }
        }
    }

    function _getAuthorizedOperatorSlot(
        address collection
    ) internal pure returns (uint256 slot) {
        bytes4 authorizedOperatorScope = _AUTHORIZED_OPERATOR_SCOPE;
        assembly {
            slot := or(
                authorizedOperatorScope,
                and(collection, 0xffffffffffffffffffffffffffffffffffffffff)
            )
        }
    }

    function _getAuthorizedIdentifierSlot(
        address collection,
        uint256 identifier
    ) internal pure returns (uint256 slot) {
        bytes4 authorizedIdentifierScope = _AUTHORIZED_IDENTIFIER_SCOPE;
        assembly {
            mstore(0x0, authorizedIdentifierScope)
            mstore(0x18, collection)
            mstore(0x04, identifier)
            slot := keccak256(0x0, 0x38)
        }
    }

    function _getAuthorizedAmountSlot(
        address collection,
        uint256 identifier
    ) internal pure returns (uint256 slot) {
        bytes4 authorizedAmountScope = _AUTHORIZED_AMOUNT_SCOPE;
        assembly {
            mstore(0x0, authorizedAmountScope)
            mstore(0x18, collection)
            mstore(0x04, identifier)
            slot := keccak256(0x0, 0x38)
        }
    }
}
