// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice The current payout wallet can return foreign tokens held by this contract.
/// @dev No ETH transfer, approval, arbitrary execution or recovery of this system's own NFT collection.
abstract contract TokenRescue is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error RescueUnauthorized();
    error InvalidRescueToken();
    error InvalidRescueRecipient();
    error InvalidRescueAmount();

    event ERC20Rescued(address indexed token, address indexed recipient, uint256 amount);
    event ERC721Rescued(address indexed token, address indexed recipient, uint256 tokenId);
    event ERC1155Rescued(address indexed token, address indexed recipient, uint256 tokenId, uint256 amount);

    function rescueERC20(address token, address recipient, uint256 amount) external nonReentrant {
        _validateRescue(token, recipient);
        if (amount == 0) revert InvalidRescueAmount();
        IERC20(token).safeTransfer(recipient, amount);
        emit ERC20Rescued(token, recipient, amount);
    }

    function rescueERC721(address token, address recipient, uint256 tokenId) external nonReentrant {
        _validateRescue(token, recipient);
        IERC721(token).safeTransferFrom(address(this), recipient, tokenId);
        emit ERC721Rescued(token, recipient, tokenId);
    }

    function rescueERC1155(address token, address recipient, uint256 tokenId, uint256 amount) external nonReentrant {
        _validateRescue(token, recipient);
        if (amount == 0) revert InvalidRescueAmount();
        IERC1155(token).safeTransferFrom(address(this), recipient, tokenId, amount, "");
        emit ERC1155Rescued(token, recipient, tokenId, amount);
    }

    function _validateRescue(address token, address recipient) private view {
        if (msg.sender != _tokenRescueAdmin()) revert RescueUnauthorized();
        if (token == _protectedToken() || token.code.length == 0) revert InvalidRescueToken();
        if (recipient == address(0) || recipient == address(this)) revert InvalidRescueRecipient();
    }

    function _tokenRescueAdmin() internal view virtual returns (address);
    function _protectedToken() internal view virtual returns (address);
}
