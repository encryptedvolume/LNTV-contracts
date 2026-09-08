// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC721C, ERC721OpenZeppelin } from "@limitbreak/creator-token-standards/src/erc721c/ERC721C.sol";
import { ERC721 } from "../lib/openzeppelin-contracts-v4/contracts/token/ERC721/ERC721.sol";
import { TokenRescue } from "./TokenRescue.sol";
import { IERC4906 } from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RoyaltyMarketplace } from "./RoyaltyMarketplace.sol";

/// @notice Minimal interface to OpenSea's existing StrictAuthorizedTransferSecurityRegistry.
interface IStrictRoyaltyRegistry {
    function createListCopy(string calldata name, uint120 sourceListId) external returns (uint120);
    function addAccountToAuthorizers(uint120 listId, address account) external;
    function addAccountToWhitelist(uint120 listId, address account) external;
    function applyListToCollection(address collection, uint120 listId) external;
    function setTransferSecurityLevelOfCollection(address collection, uint8 level) external;
}

interface IAuctionPayout {
    function payoutWallet() external view returns (address);
}

/// @title AuctionEdition
/// @notice 100 ERC-721 NFTs with admin-updatable per-token off-chain metadata endpoints.
/// @dev Uses unmodified Limit Break ERC721-C. Secondary transfers require the configured enforcement registry.
contract AuctionEdition is ERC721C, IERC2981, TokenRescue {
    address public constant OPENSEA_TRANSFER_VALIDATOR = 0xA000027A9B2802E1ddf7000061001e5c005A0000;
    address public constant OPENSEA_SIGNED_ZONE = 0x000056F7000000EcE9003ca63978907a00FFD100;
    bool public tradingConfigured;
    uint120 public tradingListId;
    uint256 public constant MAX_SUPPLY = 100;
    address public immutable auction;
    uint96 public immutable royaltyBps;
    RoyaltyMarketplace public immutable marketplace;
    /// @notice Admin-updatable base endpoint, ending with a slash. Reveal state and metadata content live off-chain.
    string public metadataURI;
    uint256 public totalSupply;
    /// @notice Advances on every secondary transfer, invalidating prior listings.
    mapping(uint256 => uint256) public transferNonce;

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidMint();
    error RoyaltyTransferRequired();

    event MetadataURIUpdated(string previousURI, string newURI);
    event TradingConfigured(address indexed validator, uint120 indexed listId);
    event ContractURIUpdated();

    constructor(string memory name_, string memory symbol_, string memory metadataURI_, uint96 bps)
        ERC721OpenZeppelin(name_, symbol_)
    {
        if (
            bytes(name_).length == 0 || bytes(symbol_).length == 0 || bytes(metadataURI_).length == 0 || bps == 0
                || bps > 10_000
        ) {
            revert InvalidConfiguration();
        }
        if (bytes(metadataURI_)[bytes(metadataURI_).length - 1] != bytes1("/")) revert InvalidConfiguration();
        auction = msg.sender;
        metadataURI = metadataURI_;
        royaltyBps = bps;
        marketplace = new RoyaltyMarketplace();
    }

    /// @notice Mint the auction-assigned IDs atomically. Each NFT performs an ERC-721 receiver check.
    function mint(address recipient, uint256[] calldata tokenIds) external {
        if (msg.sender != auction) revert Unauthorized();
        if (tokenIds.length == 0 || tokenIds.length > MAX_SUPPLY - totalSupply) revert InvalidMint();
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds[i];
            if (id == 0 || id > MAX_SUPPLY || _ownerOf(id) != address(0)) revert InvalidMint();
            ++totalSupply;
            _safeMint(recipient, id);
        }
    }

    /// @notice The current shared payout wallet can replace the metadata base or refresh off-chain content.
    /// @dev Affects all minted and future IDs. Does not reveal tokens or invalidate marketplace listings.
    function setMetadataURI(string calldata newURI) external nonReentrant {
        if (msg.sender != royaltyRecipient()) revert Unauthorized();
        bytes memory uri = bytes(newURI);
        if (uri.length == 0 || uri[uri.length - 1] != bytes1("/")) revert InvalidConfiguration();
        string memory previousURI = metadataURI;
        metadataURI = newURI;
        emit MetadataURIUpdated(previousURI, newURI);
        emit IERC4906.BatchMetadataUpdate(1, MAX_SUPPLY);
        emit ContractURIUpdated();
    }

    function _tokenRescueAdmin() internal view override returns (address) {
        return royaltyRecipient();
    }

    function _protectedToken() internal view override returns (address) {
        return address(this);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        return string.concat(metadataURI, Strings.toString(tokenId), ".json");
    }

    function royaltyRecipient() public view returns (address) {
        return IAuctionPayout(auction).payoutWallet();
    }

    /// @notice Trading royalties round up. IDs outside the collection return zero royalty.
    function royaltyInfo(uint256 tokenId, uint256 salePrice) public view returns (address receiver, uint256 amount) {
        receiver = royaltyRecipient();
        if (tokenId > 0 && tokenId <= MAX_SUPPLY) {
            amount = Math.mulDiv(salePrice, royaltyBps, 10_000, Math.Rounding.Ceil);
        }
    }

    /// @notice Only the holder can grant operator approval; the validator has no implicit approval.
    /// @dev Read the exact OpenZeppelin base used by ERC721-C, bypassing its optional creator-controlled
    ///      auto-approval. The inherited flag/setter remain ABI-compatible but cannot authorize transfers.
    function isApprovedForAll(address holder, address operator) public view override returns (bool) {
        return ERC721.isApprovedForAll(holder, operator);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721C, IERC165) returns (bool) {
        return
            interfaceId == 0x49064906 || interfaceId == type(IERC2981).interfaceId
                || super.supportsInterface(interfaceId);
    }

    /// @notice OpenSea/registry ownership follows the auction's two-step payout-wallet rotation.
    /// @dev Ownership is changed through RankedAuction, never through a separate NFT owner role.
    function owner() public view returns (address) {
        return royaltyRecipient();
    }

    /// @notice Collection metadata endpoint; publish contract.json alongside the token metadata.
    function contractURI() external view returns (string memory) {
        return string.concat(metadataURI, "contract.json");
    }

    function _requireCallerIsContractOwner() internal view override {
        if (msg.sender != owner()) revert Unauthorized();
    }

    /// @notice Atomically enable strict marketplace enforcement using OpenSea's supported registry.
    /// @dev Copies the registry's curated list, adds SignedZone and the optional local royalty marketplace,
    ///      and disables direct wallet transfers. The edition owns this list; payout rotation cannot leave
    ///      its management with the previous wallet. Other supported marketplaces use registry policies.
    ///      OpenSea Studio must separately enforce the collection's royalty rate and payout recipient.
    function configureEnforcedTrading() external nonReentrant {
        _requireCallerIsContractOwner();
        IStrictRoyaltyRegistry registry = IStrictRoyaltyRegistry(OPENSEA_TRANSFER_VALIDATOR);
        if (OPENSEA_TRANSFER_VALIDATOR.code.length == 0) revert InvalidConfiguration();
        uint120 listId = registry.createListCopy("LNTV royalty enforcement", 0);
        registry.addAccountToAuthorizers(listId, OPENSEA_SIGNED_ZONE);
        registry.addAccountToWhitelist(listId, address(marketplace));
        registry.applyListToCollection(address(this), listId);
        registry.setTransferSecurityLevelOfCollection(address(this), 4);
        setTransferValidator(OPENSEA_TRANSFER_VALIDATOR);
        tradingListId = listId;
        tradingConfigured = true;
        emit TradingConfigured(OPENSEA_TRANSFER_VALIDATOR, listId);
    }

    function _preValidateTransfer(address caller, address from, address to, uint256 tokenId, uint256 value)
        internal
        override
    {
        // Never turn a missing/unset validator into unrestricted transfers. Minting is unaffected.
        if (!tradingConfigured || getTransferValidator().code.length == 0) revert RoyaltyTransferRequired();
        super._preValidateTransfer(caller, from, to, tokenId, value);
    }

    function _postValidateTransfer(address caller, address from, address to, uint256 tokenId, uint256 value)
        internal
        override
    {
        super._postValidateTransfer(caller, from, to, tokenId, value);
        ++transferNonce[tokenId];
    }
}
