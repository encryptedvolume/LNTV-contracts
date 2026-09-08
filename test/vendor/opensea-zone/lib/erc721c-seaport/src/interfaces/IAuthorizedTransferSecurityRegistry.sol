// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

enum ListTypes {
    AuthorizerList,
    OperatorList
}

/// @title IAuthorizedTransferSecurityRegistry
/// @dev Interface for the Authorized Transfer Security Registry, a simplified version of the Transfer
///      Security Registry that only supports authorizers and whitelisted operators, and assumes a
///      security level of OperatorWhitelistEnableOTC + authorizers for all collections that use it.
///      Note that a number of view functions on collections that add this validator will not work.
interface IAuthorizedTransferSecurityRegistry {
    event CreatedList(uint256 indexed id, string name);
    event AppliedListToCollection(address indexed collection, uint120 indexed id);
    event ReassignedListOwnership(uint256 indexed id, address indexed newOwner);
    event AddedAccountToList(ListTypes indexed kind, uint256 indexed id, address indexed account);
    event RemovedAccountFromList(ListTypes indexed kind, uint256 indexed id, address indexed account);

    error AuthorizedTransferSecurityRegistry__ListDoesNotExist();
    error AuthorizedTransferSecurityRegistry__CallerDoesNotOwnList();
    error AuthorizedTransferSecurityRegistry__ArrayLengthCannotBeZero();
    error AuthorizedTransferSecurityRegistry__CallerMustHaveElevatedPermissionsForSpecifiedNFT();
    error AuthorizedTransferSecurityRegistry__ListOwnershipCannotBeTransferredToZeroAddress();
    error AuthorizedTransferSecurityRegistry__ZeroAddressNotAllowed();
    error AuthorizedTransferSecurityRegistry__UnauthorizedTransfer();
    error AuthorizedTransferSecurityRegistry__CallerIsNotValidAuthorizer();

    /// Manage lists of authorizers & operators that can be applied to collections
    function createList(string calldata name) external returns (uint120);
    function createListCopy(string calldata name, uint120 sourceListId) external returns (uint120);
    function reassignOwnershipOfList(uint120 id, address newOwner) external;
    function renounceOwnershipOfList(uint120 id) external;
    function applyListToCollection(address collection, uint120 id) external;
    function listOwners(uint120 id) external view returns (address);

    /// Manage and query for authorizers on lists
    function addAuthorizers(uint120 id, address[] calldata accounts) external;
    function removeAuthorizers(uint120 id, address[] calldata accounts) external;
    function getAuthorizers(uint120 id) external view returns (address[] memory);
    function isAuthorizer(uint120 id, address account) external view returns (bool);
    function getAuthorizersByCollection(address collection) external view returns (address[] memory);
    function isAuthorizerByCollection(address collection, address account) external view returns (bool);

    /// Manage and query for operators on lists
    function addOperators(uint120 id, address[] calldata accounts) external;
    function removeOperators(uint120 id, address[] calldata accounts) external;
    function getOperators(uint120 id) external view returns (address[] memory);
    function isOperator(uint120 id, address account) external view returns (bool);
    function getOperatorsByCollection(address collection) external view returns (address[] memory);
    function isOperatorByCollection(address collection, address account) external view returns (bool);

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