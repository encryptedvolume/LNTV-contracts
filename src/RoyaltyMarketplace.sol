// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { TokenRescue } from "./TokenRescue.sol";

interface ITransferNonce {
    function transferNonce(uint256 tokenId) external view returns (uint256);
}

/// @title RoyaltyMarketplace
/// @notice Noncustodial ETH sales of individual ERC-721 NFTs from its deploying collection.
contract RoyaltyMarketplace is TokenRescue {
    struct Listing {
        address seller;
        uint128 price;
        uint64 expiry;
        uint16 tokenId;
        bool active;
        uint256 transferNonce;
    }

    address public immutable edition;
    uint256 public nextListingId = 1;
    uint256 public totalCredits;
    uint256 public pendingRoyalties;
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256) public credits;

    error InvalidListing();
    error InvalidToken();
    error InvalidRecipient();
    error IncorrectPayment();
    error NotSeller();
    error NotApproved();
    error NothingToWithdraw();
    error TransferFailed();
    error NotPayoutWallet();

    event Listed(uint256 indexed id, address indexed seller, uint256 indexed tokenId, uint256 price, uint64 expiry);
    event Cancelled(uint256 indexed id);
    event Purchased(
        uint256 indexed id,
        address indexed buyer,
        address indexed recipient,
        uint256 tokenId,
        uint256 price,
        uint256 royalty
    );
    event Withdrawn(address indexed account, address indexed recipient, uint256 amount);
    event RoyaltiesWithdrawn(address indexed payoutWallet, address indexed recipient, uint256 amount);

    constructor() {
        edition = msg.sender;
    }

    function list(uint256 tokenId, uint128 price, uint64 expiry) external nonReentrant returns (uint256 id) {
        if (tokenId == 0 || tokenId > 100) revert InvalidToken();
        if (price == 0 || expiry <= block.timestamp) revert InvalidListing();
        if (IERC721(edition).ownerOf(tokenId) != msg.sender) revert NotSeller();
        if (!_isApproved(msg.sender, tokenId)) revert NotApproved();
        id = nextListingId++;
        listings[id] =
            Listing(msg.sender, price, expiry, uint16(tokenId), true, ITransferNonce(edition).transferNonce(tokenId));
        emit Listed(id, msg.sender, tokenId, price, expiry);
    }

    function cancel(uint256 id) external nonReentrant {
        Listing storage item = listings[id];
        if (item.seller != msg.sender) revert NotSeller();
        if (!item.active) revert InvalidListing();
        item.active = false;
        emit Cancelled(id);
    }

    /// @notice Buy exactly the listed NFT. A rejected receiver reverts the complete sale.
    function buy(uint256 id, address recipient) external payable nonReentrant {
        Listing storage item = listings[id];
        if (!item.active || block.timestamp >= item.expiry) revert InvalidListing();
        if (ITransferNonce(edition).transferNonce(item.tokenId) != item.transferNonce) revert InvalidListing();
        if (!_isApproved(item.seller, item.tokenId)) revert NotApproved();
        if (recipient == address(0) || recipient == address(this) || recipient == edition) revert InvalidRecipient();
        uint256 price = item.price;
        if (msg.value != price) revert IncorrectPayment();
        (, uint256 royalty) = IERC2981(edition).royaltyInfo(item.tokenId, price);

        item.active = false;
        pendingRoyalties += royalty;
        credits[item.seller] += price - royalty;
        totalCredits += price;

        IERC721(edition).safeTransferFrom(item.seller, recipient, item.tokenId);
        emit Purchased(id, msg.sender, recipient, item.tokenId, price, royalty);
    }

    function _tokenRescueAdmin() internal view override returns (address wallet) {
        (wallet,) = IERC2981(edition).royaltyInfo(1, 0);
    }

    function _protectedToken() internal view override returns (address) {
        return edition;
    }

    function _isApproved(address seller, uint256 tokenId) private view returns (bool) {
        return IERC721(edition).isApprovedForAll(seller, address(this))
            || IERC721(edition).getApproved(tokenId) == address(this);
    }

    /// @notice Withdraw your seller proceeds to any payable recipient; failure preserves the credit.
    function withdraw(address payable recipient) external nonReentrant {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        uint256 amount = credits[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        credits[msg.sender] = 0;
        totalCredits -= amount;
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit Withdrawn(msg.sender, recipient, amount);
    }

    /// @notice Only the current shared payout wallet can withdraw accrued trading royalties.
    function withdrawRoyalties(address payable recipient) external nonReentrant {
        (address wallet,) = IERC2981(edition).royaltyInfo(1, 0);
        if (msg.sender != wallet) revert NotPayoutWallet();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        uint256 amount = pendingRoyalties;
        if (amount == 0) revert NothingToWithdraw();
        pendingRoyalties = 0;
        totalCredits -= amount;
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert TransferFailed();
        emit RoyaltiesWithdrawn(msg.sender, recipient, amount);
    }
}
