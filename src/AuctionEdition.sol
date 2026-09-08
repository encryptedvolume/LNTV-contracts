// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RoyaltyMarketplace } from "./RoyaltyMarketplace.sol";

interface IAuctionPayout {
    function payoutWallet() external view returns (address);
}

/// @title AuctionEdition
/// @notice 100 ERC-721 NFTs with fixed per-token off-chain metadata endpoints.
/// @dev Only the deploying auction mints; all secondary transfers require the immutable royalty marketplace.
contract AuctionEdition is ERC721, IERC2981 {
    uint256 public constant MAX_SUPPLY = 100;
    address public immutable auction;
    uint96 public immutable royaltyBps;
    RoyaltyMarketplace public immutable marketplace;
    /// @notice Fixed base endpoint, ending with a slash. Reveal state and metadata content live off-chain.
    string public metadataURI;
    uint256 public totalSupply;
    /// @notice Advances on every secondary transfer, invalidating prior listings.
    mapping(uint256 => uint256) public transferNonce;

    error Unauthorized();
    error InvalidConfiguration();
    error InvalidMint();
    error RoyaltyTransferRequired();

    constructor(string memory name_, string memory symbol_, string memory metadataURI_, uint96 bps)
        ERC721(name_, symbol_)
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

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
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

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function approve(address to, uint256 tokenId) public override {
        if (to != address(0) && to != address(marketplace)) revert RoyaltyTransferRequired();
        super.approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        if (approved && operator != address(marketplace)) revert RoyaltyTransferRequired();
        super.setApprovalForAll(operator, approved);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0) && msg.sender != address(marketplace)) revert RoyaltyTransferRequired();
        address from = super._update(to, tokenId, auth);
        if (from != address(0)) ++transferNonce[tokenId];
        return from;
    }
}
