// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

enum ListTypes {
    AuthorizerList,
    OperatorList,
    OperatorRequiringAuthorizationList
}

enum TransferSecurityLevels {
    Recommended,
    One,
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight
}

/// @title IStrictAuthorizedTransferSecurityRegistry
/// @dev Interface for the Authorized Transfer Security Registry, a simplified version of the Transfer
///      Security Registry that only supports authorizers and whitelisted operators, and assumes a
///      security level of OperatorWhitelistEnableOTC + authorizers for all collections that use it.
///      Note that a number of view functions on collections that add this validator will not work.
interface IStrictAuthorizedTransferSecurityRegistry {
    event CreatedList(uint256 indexed id, string name);
    event AppliedListToCollection(address indexed collection, uint120 indexed id);
    event ReassignedListOwnership(uint256 indexed id, address indexed newOwner);
    event AddedAccountToList(ListTypes indexed kind, uint256 indexed id, address indexed account);
    event RemovedAccountFromList(ListTypes indexed kind, uint256 indexed id, address indexed account);
    event SetTransferSecurityLevel(address collection, TransferSecurityLevels level);

    error StrictAuthorizedTransferSecurityRegistry__ListDoesNotExist();
    error StrictAuthorizedTransferSecurityRegistry__CallerDoesNotOwnList();
    error StrictAuthorizedTransferSecurityRegistry__ArrayLengthCannotBeZero();
    error StrictAuthorizedTransferSecurityRegistry__CallerMustHaveElevatedPermissionsForSpecifiedNFT();
    error StrictAuthorizedTransferSecurityRegistry__ListOwnershipCannotBeTransferredToZeroAddress();
    error StrictAuthorizedTransferSecurityRegistry__ZeroAddressNotAllowed();
    error StrictAuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
    error StrictAuthorizedTransferSecurityRegistry__CallerIsNotValidAuthorizer();
    error StrictAuthorizedTransferSecurityRegistry__UnsupportedSecurityLevel();
    error StrictAuthorizedTransferSecurityRegistry__UnsupportedSecurityLevelDetail();
    error StrictAuthorizedTransferSecurityRegistry__CallerMustBeWhitelistedOperator();
    error StrictAuthorizedTransferSecurityRegistry__ReceiverMustNotHaveDeployedCode();
    error StrictAuthorizedTransferSecurityRegistry__ReceiverProofOfEOASignatureUnverified();

    /// Manage lists of authorizers & operators that can be applied to collections
    function createList(string calldata name) external returns (uint120);
    function createListCopy(string calldata name, uint120 sourceListId) external returns (uint120);
    function reassignOwnershipOfList(uint120 id, address newOwner) external;
    function renounceOwnershipOfList(uint120 id) external;
    function applyListToCollection(address collection, uint120 id) external;
    function listOwners(uint120 id) external view returns (address);

    /// Manage and query for authorizers on lists
    function addAccountToAuthorizers(uint120 id, address account) external;

    function addAccountsToAuthorizers(uint120 id, address[] calldata accounts) external;

    function addAuthorizers(uint120 id, address[] calldata accounts) external;

    function removeAccountFromAuthorizers(uint120 id, address account) external;
    
    function removeAccountsFromAuthorizers(uint120 id, address[] calldata accounts) external;

    function getAuthorizerAccounts(uint120 id) external view returns (address[] memory);

    function isAccountAuthorizer(uint120 id, address account) external view returns (bool);

    function getAuthorizerAccountsByCollection(address collection) external view returns (address[] memory);

    function isAccountAuthorizerOfCollection(address collection, address account) external view returns (bool);

    /// Manage and query for operators on lists
    function addAccountToWhitelist(uint120 id, address account) external;

    function addAccountsToWhitelist(uint120 id, address[] calldata accounts) external;

    function addOperators(uint120 id, address[] calldata accounts) external;

    function removeAccountFromWhitelist(uint120 id, address account) external;

    function removeAccountsFromWhitelist(uint120 id, address[] calldata accounts) external;
    
    function getWhitelistedAccounts(uint120 id) external view returns (address[] memory);

    function isAccountWhitelisted(uint120 id, address account) external view returns (bool);
    function getWhitelistedAccountsByCollection(address collection) external view returns (address[] memory);

    function isAccountWhitelistedByCollection(address collection, address account) external view returns (bool);

    /// Manage and query for blacklists on lists
    function addAccountToBlacklist(uint120 id, address account) external;

    function addAccountsToBlacklist(uint120 id, address[] calldata accounts) external;

    function removeAccountFromBlacklist(uint120 id, address account) external;

    function removeAccountsFromBlacklist(uint120 id, address[] calldata accounts) external;

    function getBlacklistedAccounts(uint120 id) external view returns (address[] memory);

    function isAccountBlacklisted(uint120 id, address account) external view returns (bool);
    function getBlacklistedAccountsByCollection(address collection) external view returns (address[] memory);

    function isAccountBlacklistedByCollection(address collection, address account) external view returns (bool);

    function setTransferSecurityLevelOfCollection(
        address collection,
        uint8 level,
        bool enableAuthorizationMode,
        bool authorizersCanSetWildcardOperators,
        bool enableAccountFreezingMode
    ) external;

    function setTransferSecurityLevelOfCollection(
        address collection,
        TransferSecurityLevels level
    ) external;

    function isVerifiedEOA(address account) external view returns (bool);

    /// Ensure that a specific operator has been authorized to transfer tokens
    function validateTransfer(address caller, address from, address to) external view;

    /// Ensure that a transfer has been authorized for a specific tokenId
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;

    /// Ensure that a transfer has been authorized for a specific amount of a specific tokenId, and
    /// reduce the transferable amount remaining
    function validateTransfer(address caller, address from, address to, uint256 tokenId, uint256 amount) external;

    /// Legacy alias for validateTransfer (address caller, address from, address to)
    function applyCollectionTransferPolicy(address caller, address from, address to) external view;

    /// Temporarily assign a specific allowed operator for a given collection
    function beforeAuthorizedTransfer(address operator, address token) external;

    /// Clear assignment of a specific allowed operator for a given collection
    function afterAuthorizedTransfer(address token) external;

    /// Temporarily allow a specific tokenId from a given collection to be transferred
    function beforeAuthorizedTransfer(address token, uint256 tokenId) external;

    /// Clear assignment of an specific tokenId's transfer allowance
    function afterAuthorizedTransfer(address token, uint256 tokenId) external;

    /// Temporarily allow a specific amount of a specific tokenId from a given collection to be transferred
    function beforeAuthorizedTransferWithAmount(address token, uint256 tokenId, uint256 amount) external;

    /// Clear assignment of a tokenId's transfer allowance for a specific amount
    function afterAuthorizedTransferWithAmount(address token, uint256 tokenId) external;
}