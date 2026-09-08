// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase } from "./TestBase.sol";
import { RescueCoin, RescueNFT, RescueMultiToken } from "./AdminFeatures.t.sol";
import { TokenRescue } from "../src/TokenRescue.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CallbackRescueCoin is ERC20 {
    address public target;
    bytes public payload;
    bool public succeeded;
    bytes4 public errorSelector;
    bool public rejectTransfer;

    constructor() ERC20("Callback coin", "CALL") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target_, bytes calldata payload_, bool reject_) external {
        target = target_;
        payload = payload_;
        rejectTransfer = reject_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        (bool ok, bytes memory result) = target.call(payload);
        succeeded = ok;
        if (result.length >= 4) errorSelector = bytes4(result);
        super.transfer(to, amount);
        return !rejectTransfer;
    }
}

contract CallbackMultiReceiver is ERC1155Holder {
    address public target;
    bytes public payload;
    bool public attempted;
    bool public succeeded;
    bytes4 public errorSelector;

    function arm(address target_, bytes calldata payload_) external {
        target = target_;
        payload = payload_;
        attempted = false;
    }

    function execute(address target_, bytes calldata payload_) external {
        (bool ok, bytes memory result) = target_.call(payload_);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public override returns (bytes4) {
        attempted = true;
        (bool ok, bytes memory result) = target.call(payload);
        succeeded = ok;
        if (result.length >= 4) errorSelector = bytes4(result);
        return this.onERC1155Received.selector;
    }
}

contract AdminAuditTest is TestBase {
    function targets() internal view returns (TokenRescue[3] memory) {
        return [TokenRescue(address(auction)), TokenRescue(address(edition)), TokenRescue(address(market))];
    }

    function testERC20CallbackCannotReenterAuctionMetadataOrRoyaltyWithdrawal() public {
        CallbackRescueCoin coin = new CallbackRescueCoin();
        TokenRescue[3] memory contracts = targets();
        bytes[3] memory calls = [
            abi.encodeWithSignature("createBid()"),
            abi.encodeWithSignature("setMetadataURI(string)", "https://callback/"),
            abi.encodeWithSignature("withdrawRoyalties(address)", bob)
        ];
        live();
        for (uint256 i; i < 3; ++i) {
            coin.mint(address(contracts[i]), 10);
            coin.arm(address(contracts[i]), calls[i], false);
            vm.prank(payoutWallet);
            contracts[i].rescueERC20(address(coin), alice, 10);
            assertFalse(coin.succeeded());
            assertEq(coin.errorSelector(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            assertEq(coin.balanceOf(address(contracts[i])), 0);
        }
        assertEq(coin.balanceOf(alice), 30);
        assertEq(edition.metadataURI(), "ipfs://edition-metadata/");
        assertEq(auction.nextBidId(), 1);
        assertEq(market.totalCredits(), 0);
    }

    function testFalseReturningERC20RollsBackTransferAndCallbackState() public {
        CallbackRescueCoin coin = new CallbackRescueCoin();
        coin.mint(address(auction), 10);
        coin.arm(address(auction), abi.encodeWithSignature("withdrawUnclaimedETH(address)", bob), true);
        vm.prank(payoutWallet);
        vm.expectRevert();
        auction.rescueERC20(address(coin), alice, 10);
        assertEq(coin.balanceOf(address(auction)), 10);
        assertEq(coin.balanceOf(alice), 0);
        assertEq(coin.errorSelector(), bytes4(0));
        assertFalse(auction.refundsClosed());
    }

    function testERC1155AdminReceiverCannotReenterRescueOnAnyContract() public {
        RescueMultiToken token = new RescueMultiToken();
        CallbackMultiReceiver receiver = new CallbackMultiReceiver();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        receiver.execute(address(auction), abi.encodeWithSignature("acceptPayoutWallet()"));
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < 3; ++i) {
            token.forceMint(address(contracts[i]), i, 10);
            receiver.arm(address(contracts[i]), abi.encodeCall(TokenRescue.rescueERC1155, (address(token), bob, i, 5)));
            receiver.execute(
                address(contracts[i]),
                abi.encodeCall(TokenRescue.rescueERC1155, (address(token), address(receiver), i, 5))
            );
            assertTrue(receiver.attempted());
            assertFalse(receiver.succeeded());
            assertEq(receiver.errorSelector(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            assertEq(token.balanceOf(address(receiver), i), 5);
            assertEq(token.balanceOf(address(contracts[i]), i), 5);
            assertEq(token.balanceOf(bob, i), 0);
        }
    }

    function testMetadataAndRescuePreserveAccruedSellerAndRoyaltyCredits() public {
        mintForMarket();
        vm.prank(alice);
        uint256 listing = market.list(1, 1 ether, uint64(block.timestamp + 1 days));
        vm.prank(bob);
        market.buy{ value: 1 ether }(listing, bob);
        uint256 credits = market.credits(alice);
        uint256 royalties = market.pendingRoyalties();
        RescueCoin coin = new RescueCoin();
        coin.mint(address(market), 1);
        vm.startPrank(payoutWallet);
        edition.setMetadataURI("https://updated/");
        market.rescueERC20(address(coin), carol, 1);
        vm.stopPrank();
        assertEq(market.credits(alice), credits);
        assertEq(market.pendingRoyalties(), royalties);
        assertEq(market.totalCredits(), 1 ether);
        assertEq(address(market).balance, 1 ether);
        assertEq(edition.ownerOf(1), bob);
        assertEq(edition.transferNonce(1), 1);
        vm.prank(alice);
        market.withdraw(payable(alice));
        vm.prank(payoutWallet);
        market.withdrawRoyalties(payable(payoutWallet));
        assertEq(address(market).balance, 0);
    }

    function testRescueDoesNotBypassRecoveryDelayOrCloseRefundsAfterEligibility() public {
        live();
        place(alice, 2 * RESERVE);
        place(bob, 3 * RESERVE);
        finish();
        auction.creditRefunds(one(1));
        vm.warp(auction.recoveryAvailableAt());
        RescueCoin coin = new RescueCoin();
        coin.mint(address(auction), 1);
        vm.prank(payoutWallet);
        auction.rescueERC20(address(coin), carol, 1);
        assertFalse(auction.refundsClosed());
        assertEq(auction.refunds(alice), RESERVE);
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        auction.withdrawRefund(payable(alice));
        assertEq(alice.balance, balanceBefore + RESERVE);
    }

    function testFuzzRescueConservesForeignTokenBalances(uint96 supplied, uint96 requested, uint8 targetSeed) public {
        uint256 supply = bound(supplied, 1, type(uint96).max);
        uint256 amount = bound(requested, 1, supply);
        TokenRescue target = targets()[targetSeed % 3];
        RescueCoin coin = new RescueCoin();
        RescueMultiToken multi = new RescueMultiToken();
        coin.mint(address(target), supply);
        multi.forceMint(address(target), 0, supply);
        vm.startPrank(payoutWallet);
        target.rescueERC20(address(coin), bob, amount);
        target.rescueERC1155(address(multi), bob, 0, amount);
        vm.stopPrank();
        assertEq(coin.balanceOf(address(target)), supply - amount);
        assertEq(coin.balanceOf(bob), amount);
        assertEq(multi.balanceOf(address(target), 0), supply - amount);
        assertEq(multi.balanceOf(bob, 0), amount);
        assertEq(auction.liabilities(), 0);
        assertEq(market.totalCredits(), 0);
    }
}
