// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { TestBase, ReentrantReceiver, Rejector } from "./TestBase.sol";
import { TokenRescue } from "../src/TokenRescue.sol";
import { AuctionEdition } from "../src/AuctionEdition.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RescueCoin is ERC20 {
    constructor() ERC20("Accidental token", "ACC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RescueNFT is ERC721 {
    constructor() ERC721("Foreign NFT", "FNFT") { }

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

contract RescueMultiToken is ERC1155 {
    constructor() ERC1155("") { }

    // Simulate balances already credited without receiver acceptance by a foreign contract.
    function forceMint(address to, uint256 id, uint256 amount) external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = id;
        amounts[0] = amount;
        _update(address(0), to, ids, amounts);
    }
}

contract NoReturnRescueCoin {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract FalseReturnRescueCoin {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract AdminFeaturesTest is TestBase {
    event MetadataURIUpdated(string previousURI, string newURI);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    function targets() internal view returns (TokenRescue[3] memory) {
        return [TokenRescue(address(auction)), TokenRescue(address(edition)), TokenRescue(address(market))];
    }

    function testMetadataUpdateChangesAllMintedAndFutureEndpointsAndEmitsRefresh() public {
        vm.expectEmit(false, false, false, true, address(edition));
        emit MetadataURIUpdated("ipfs://edition-metadata/", "https://new.example/");
        vm.expectEmit(false, false, false, true, address(edition));
        emit BatchMetadataUpdate(1, 100);
        vm.prank(payoutWallet);
        edition.setMetadataURI("https://new.example/");
        assertEq(edition.metadataURI(), "https://new.example/");
        mintForMarket();
        assertEq(edition.tokenURI(1), "https://new.example/1.json");
        assertEq(edition.tokenURI(100), "https://new.example/100.json");
        vm.prank(payoutWallet);
        edition.setMetadataURI("ipfs://replacement/");
        assertEq(edition.tokenURI(1), "ipfs://replacement/1.json");
        assertEq(edition.tokenURI(100), "ipfs://replacement/100.json");
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.totalSupply(), 100);
        assertEq(edition.transferNonce(1), 0);
        assertTrue(edition.supportsInterface(0x49064906));
    }

    function testMetadataAuthorizationValidationAndWalletRotation() public {
        vm.expectRevert(AuctionEdition.Unauthorized.selector);
        edition.setMetadataURI("https://outsider/");
        vm.startPrank(payoutWallet);
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        edition.setMetadataURI("");
        vm.expectRevert(AuctionEdition.InvalidConfiguration.selector);
        edition.setMetadataURI("https://missing-slash");
        auction.proposePayoutWallet(bob);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(AuctionEdition.Unauthorized.selector);
        edition.setMetadataURI("https://pending/");
        vm.prank(bob);
        auction.acceptPayoutWallet();
        vm.prank(payoutWallet);
        vm.expectRevert(AuctionEdition.Unauthorized.selector);
        edition.setMetadataURI("https://old-wallet/");
        vm.prank(bob);
        edition.setMetadataURI("https://new-wallet/");
        assertEq(edition.metadataURI(), "https://new-wallet/");
    }

    function testRescueAllThreeTokenTypesFromAllThreeContracts() public {
        RescueCoin coin = new RescueCoin();
        RescueNFT nft = new RescueNFT();
        RescueMultiToken multi = new RescueMultiToken();
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < contracts.length; ++i) {
            address target = address(contracts[i]);
            coin.mint(alice, 10);
            nft.mint(alice, i);
            vm.startPrank(alice);
            coin.transfer(target, 10);
            nft.transferFrom(alice, target, i);
            vm.stopPrank();
            multi.forceMint(target, i, 20);
            vm.startPrank(payoutWallet);
            contracts[i].rescueERC20(address(coin), bob, 6);
            contracts[i].rescueERC721(address(nft), bob, i);
            contracts[i].rescueERC1155(address(multi), bob, i, 7);
            vm.stopPrank();
            assertEq(coin.balanceOf(target), 4);
            assertEq(nft.ownerOf(i), bob);
            assertEq(multi.balanceOf(target, i), 13);
            assertEq(multi.balanceOf(bob, i), 7);
        }
        assertEq(coin.balanceOf(bob), 18);
    }

    function testRescueAuthorityFollowsAcceptedWalletForEveryContractAndTokenType() public {
        RescueCoin coin = new RescueCoin();
        RescueNFT nft = new RescueNFT();
        RescueMultiToken multi = new RescueMultiToken();
        TokenRescue[3] memory contracts = targets();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(bob);
        for (uint256 i; i < 3; ++i) {
            coin.mint(address(contracts[i]), 5);
            nft.mint(address(contracts[i]), i);
            multi.forceMint(address(contracts[i]), i, 2);
            _expectUnauthorized(contracts[i], bob, address(coin), address(nft), address(multi), i);
            _expectUnauthorized(contracts[i], address(this), address(coin), address(nft), address(multi), i);
        }
        vm.prank(bob);
        auction.acceptPayoutWallet();
        for (uint256 i; i < 3; ++i) {
            _expectUnauthorized(contracts[i], payoutWallet, address(coin), address(nft), address(multi), i);
            vm.startPrank(bob);
            contracts[i].rescueERC20(address(coin), carol, 5);
            contracts[i].rescueERC721(address(nft), carol, i);
            contracts[i].rescueERC1155(address(multi), carol, i, 2);
            vm.stopPrank();
            assertEq(nft.ownerOf(i), carol);
        }
        assertEq(coin.balanceOf(carol), 15);
    }

    function _expectUnauthorized(
        TokenRescue target,
        address caller,
        address coin,
        address nft,
        address multi,
        uint256 id
    ) internal {
        vm.startPrank(caller);
        vm.expectRevert(TokenRescue.RescueUnauthorized.selector);
        target.rescueERC20(coin, carol, 1);
        vm.expectRevert(TokenRescue.RescueUnauthorized.selector);
        target.rescueERC721(nft, carol, id);
        vm.expectRevert(TokenRescue.RescueUnauthorized.selector);
        target.rescueERC1155(multi, carol, id, 1);
        vm.stopPrank();
    }

    function testRejectInvalidTokenRecipientAndAmount() public {
        RescueCoin coin = new RescueCoin();
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < 3; ++i) {
            vm.startPrank(payoutWallet);
            vm.expectRevert(TokenRescue.InvalidRescueToken.selector);
            contracts[i].rescueERC20(address(0), bob, 1);
            vm.expectRevert(TokenRescue.InvalidRescueToken.selector);
            contracts[i].rescueERC20(alice, bob, 1);
            vm.expectRevert(TokenRescue.InvalidRescueRecipient.selector);
            contracts[i].rescueERC20(address(coin), address(0), 1);
            vm.expectRevert(TokenRescue.InvalidRescueRecipient.selector);
            contracts[i].rescueERC20(address(coin), address(contracts[i]), 1);
            vm.expectRevert(TokenRescue.InvalidRescueAmount.selector);
            contracts[i].rescueERC20(address(coin), bob, 0);
            vm.expectRevert(TokenRescue.InvalidRescueAmount.selector);
            contracts[i].rescueERC1155(address(coin), bob, 1, 0);
            vm.stopPrank();
        }
    }

    function testOwnCollectionCannotBeRescuedOrBypassRoyalties() public {
        mintForMarket();
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < 3; ++i) {
            vm.startPrank(payoutWallet);
            vm.expectRevert(TokenRescue.InvalidRescueToken.selector);
            contracts[i].rescueERC20(address(edition), bob, 1);
            vm.expectRevert(TokenRescue.InvalidRescueToken.selector);
            contracts[i].rescueERC721(address(edition), bob, 1);
            vm.expectRevert(TokenRescue.InvalidRescueToken.selector);
            contracts[i].rescueERC1155(address(edition), bob, 1, 1);
            vm.stopPrank();
        }
        assertEq(edition.ownerOf(1), alice);
        assertEq(edition.transferNonce(1), 0);
    }

    function testSafeERC20SupportsNoReturnAndRejectsFalseReturn() public {
        NoReturnRescueCoin coin = new NoReturnRescueCoin();
        FalseReturnRescueCoin failed = new FalseReturnRescueCoin();
        coin.mint(address(auction), 10);
        vm.startPrank(payoutWallet);
        auction.rescueERC20(address(coin), bob, 7);
        vm.expectRevert();
        auction.rescueERC20(address(failed), bob, 1);
        vm.stopPrank();
        assertEq(coin.balanceOf(address(auction)), 3);
        assertEq(coin.balanceOf(bob), 7);
    }

    function testRejectedRescuePreservesForeignBalancesAndCannotTakeThirdPartyNFT() public {
        RescueCoin coin = new RescueCoin();
        RescueNFT nft = new RescueNFT();
        RescueMultiToken multi = new RescueMultiToken();
        coin.mint(address(auction), 1);
        nft.mint(address(auction), 1);
        nft.mint(alice, 2);
        vm.prank(alice);
        nft.approve(address(auction), 2);
        multi.forceMint(address(auction), 1, 1);
        address reject = address(new Rejector());
        vm.startPrank(payoutWallet);
        vm.expectRevert();
        auction.rescueERC20(address(coin), bob, 2);
        vm.expectRevert();
        auction.rescueERC721(address(nft), reject, 1);
        vm.expectRevert();
        auction.rescueERC721(address(nft), bob, 2);
        vm.expectRevert();
        auction.rescueERC1155(address(multi), reject, 1, 1);
        vm.stopPrank();
        assertEq(coin.balanceOf(address(auction)), 1);
        assertEq(nft.ownerOf(1), address(auction));
        assertEq(nft.ownerOf(2), alice);
        assertEq(multi.balanceOf(address(auction), 1), 1);
    }

    function testRescueCannotReenterAnyContractEvenWhenRecipientIsAdmin() public {
        RescueNFT nft = new RescueNFT();
        ReentrantReceiver receiver = new ReentrantReceiver();
        vm.prank(payoutWallet);
        auction.proposePayoutWallet(address(receiver));
        receiver.execute(address(auction), abi.encodeWithSignature("acceptPayoutWallet()"));
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < 3; ++i) {
            nft.mint(address(contracts[i]), i * 2);
            nft.mint(address(contracts[i]), i * 2 + 1);
            receiver.arm(
                address(contracts[i]), abi.encodeCall(TokenRescue.rescueERC721, (address(nft), bob, i * 2 + 1)), false
            );
            receiver.execute(
                address(contracts[i]),
                abi.encodeCall(TokenRescue.rescueERC721, (address(nft), address(receiver), i * 2))
            );
            assertTrue(receiver.attempted());
            assertFalse(receiver.succeeded());
            assertEq(receiver.lastError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            assertEq(nft.ownerOf(i * 2 + 1), address(contracts[i]));
        }
    }

    function testRescueLeavesEthAndAuctionRefundAccountingUntouched() public {
        live();
        place(alice, 2 * RESERVE);
        place(bob, 3 * RESERVE);
        finish();
        auction.creditRefunds(one(1));
        uint256 liabilityBefore = auction.liabilities();
        uint256 refundsBefore = auction.totalRefunds();
        RescueCoin coin = new RescueCoin();
        TokenRescue[3] memory contracts = targets();
        for (uint256 i; i < 3; ++i) {
            address target = address(contracts[i]);
            vm.deal(target, target.balance + 1 ether);
            uint256 ethBefore = target.balance;
            coin.mint(target, 2);
            vm.prank(payoutWallet);
            contracts[i].rescueERC20(address(coin), bob, 2);
            assertEq(target.balance, ethBefore);
        }
        assertEq(auction.liabilities(), liabilityBefore);
        assertEq(auction.totalRefunds(), refundsBefore);
        assertEq(auction.refunds(alice), RESERVE);
        assertFalse(auction.refundsClosed());
        assertEq(market.totalCredits(), 0);
    }

    function testRescueFunctionsRejectEthPayments() public {
        TokenRescue[3] memory contracts = targets();
        vm.deal(payoutWallet, 1 ether);
        for (uint256 i; i < 3; ++i) {
            vm.startPrank(payoutWallet);
            (bool ok20,) = address(contracts[i]).call{ value: 1 }(
                abi.encodeCall(TokenRescue.rescueERC20, (address(edition), bob, 1))
            );
            (bool ok721,) = address(contracts[i]).call{ value: 1 }(
                abi.encodeCall(TokenRescue.rescueERC721, (address(edition), bob, 1))
            );
            (bool ok1155,) = address(contracts[i]).call{ value: 1 }(
                abi.encodeCall(TokenRescue.rescueERC1155, (address(edition), bob, 1, 1))
            );
            vm.stopPrank();
            assertFalse(ok20);
            assertFalse(ok721);
            assertFalse(ok1155);
        }
    }
}
