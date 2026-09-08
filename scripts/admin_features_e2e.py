"""Real transactions for mutable metadata, foreign-token rescue and unchanged ETH entitlements."""
from web3.logs import DISCARD
from local_trading_setup import configure_local_trading


def run_admin_features(w3, artifact):
    deployer, payout, replacement, alice, bob, recipient = w3.eth.accounts[:6]
    gas = {}
    rejected = 0

    def deploy(name, args=()):
        source = artifact(name)
        factory = w3.eth.contract(abi=source['abi'], bytecode=source['bytecode']['object'])
        receipt = w3.eth.wait_for_transaction_receipt(factory.constructor(*args).transact({'from': deployer, 'gas': 8_000_000}))
        assert receipt.status == 1, name
        return w3.eth.contract(address=receipt.contractAddress, abi=source['abi'])

    def tx(fn, sender, value=0, succeeds=True, timestamp=None):
        nonlocal rejected
        if timestamp is not None:
            response = w3.provider.make_request('evm_setNextBlockTimestamp', [timestamp])
            assert 'error' not in response, response
        receipt = w3.eth.wait_for_transaction_receipt(fn.transact({'from': sender, 'value': value, 'gas': 8_000_000}))
        assert bool(receipt.status) == succeeds, (fn.fn_name, receipt.status)
        if timestamp is not None:
            assert w3.eth.get_block(receipt.blockNumber).timestamp == timestamp
        if not succeeds:
            rejected += 1
            assert not receipt.logs
        return receipt

    reserve = 10**16
    start = w3.eth.get_block('latest').timestamp + 600
    auction = deploy('RankedAuction', ((payout, 1000, reserve, start, 'https://metadata.example/before/', 'Admin rehearsal', 'ADM'),))
    edition = w3.eth.contract(address=auction.functions.edition().call(), abi=artifact('AuctionEdition')['abi'])
    market = w3.eth.contract(address=edition.functions.marketplace().call(), abi=artifact('RoyaltyMarketplace')['abi'])
    configure_local_trading(w3, edition, payout, artifact, use_script=True)
    base = 'https://metadata.example/after/'
    tx(edition.functions.setMetadataURI(base), deployer, succeeds=False)
    tx(edition.functions.setMetadataURI(''), payout, succeeds=False)
    tx(edition.functions.setMetadataURI('https://missing-slash'), payout, succeeds=False)
    changed = tx(edition.functions.setMetadataURI(base), payout)
    gas['metadata_update'] = changed.gasUsed
    event = edition.events.MetadataURIUpdated().process_receipt(changed, errors=DISCARD)[0]['args']
    assert event['previousURI'] == 'https://metadata.example/before/' and event['newURI'] == base
    refresh = edition.events.BatchMetadataUpdate().process_receipt(changed, errors=DISCARD)[0]['args']
    assert refresh['_fromTokenId'] == 1 and refresh['_toTokenId'] == 100
    assert edition.functions.supportsInterface(bytes.fromhex('49064906')).call()
    tx(auction.functions.claimReserved(10, alice), payout)
    assert edition.functions.tokenURI(100).call() == base + '100.json'
    tx(auction.functions.createBid(), alice, 2 * reserve, timestamp=start)
    tx(auction.functions.createBid(), bob, 3 * reserve)
    tx(auction.functions.settle(), deployer, timestamp=auction.functions.endTime().call())
    tx(auction.functions.creditRefunds([1]), deployer)
    tx(auction.functions.claimTokens([1], alice), alice)
    tx(auction.functions.claimTokens([2], bob), bob)
    tx(edition.functions.setApprovalForAll(market.address, True), alice)
    tx(market.functions.list(2, 10**18, w3.eth.get_block('latest').timestamp + 86400), alice)
    tx(market.functions.buy(1, bob), bob, 10**18)
    assert market.functions.pendingRoyalties().call() == 10**17
    assert market.functions.credits(alice).call() == 9 * 10**17
    assert auction.functions.refunds(alice).call() == reserve

    coin = deploy('RescueCoin')
    nft = deploy('RescueNFT')
    multi = deploy('RescueMultiToken')
    contracts = (auction, edition, market)
    eth_before = [w3.eth.get_balance(contract.address) for contract in contracts]
    liabilities_before = auction.functions.liabilities().call()
    for i, contract in enumerate(contracts):
        tx(coin.functions.mint(alice, 10), deployer)
        tx(coin.functions.transfer(contract.address, 10), alice)
        tx(nft.functions.mint(alice, i), deployer)
        tx(nft.functions.transferFrom(alice, contract.address, i), alice)
        tx(multi.functions.forceMint(contract.address, i, 20), deployer)
        tx(contract.functions.rescueERC20(coin.address, recipient, 1), alice, succeeds=False)
        tx(contract.functions.rescueERC721(edition.address, recipient, 2), payout, succeeds=False)
        tx(contract.functions.rescueERC20(coin.address, recipient, 11), payout, succeeds=False)
        tx(contract.functions.rescueERC721(nft.address, edition.address, i), payout, succeeds=False)
        gas[f'contract_{i}_rescue_erc20'] = tx(contract.functions.rescueERC20(coin.address, recipient, 6), payout).gasUsed
        gas[f'contract_{i}_rescue_erc721'] = tx(contract.functions.rescueERC721(nft.address, recipient, i), payout).gasUsed
        gas[f'contract_{i}_rescue_erc1155'] = tx(contract.functions.rescueERC1155(multi.address, recipient, i, 7), payout).gasUsed
        assert coin.functions.balanceOf(contract.address).call() == 4
        assert nft.functions.ownerOf(i).call() == recipient
        assert multi.functions.balanceOf(contract.address, i).call() == 13
        assert multi.functions.balanceOf(recipient, i).call() == 7
    assert [w3.eth.get_balance(contract.address) for contract in contracts] == eth_before
    assert auction.functions.liabilities().call() == liabilities_before
    assert market.functions.totalCredits().call() == 10**18

    tx(auction.functions.proposePayoutWallet(replacement), payout)
    tx(edition.functions.setMetadataURI(base), replacement, succeeds=False)
    tx(auction.functions.acceptPayoutWallet(), replacement)
    tx(edition.functions.setMetadataURI(base), payout, succeeds=False)
    tx(edition.functions.setMetadataURI('https://metadata.example/final/'), replacement)
    for contract in contracts:
        tx(contract.functions.rescueERC20(coin.address, recipient, 4), payout, succeeds=False)
        tx(contract.functions.rescueERC20(coin.address, recipient, 4), replacement)
        assert coin.functions.balanceOf(contract.address).call() == 0
    assert edition.functions.tokenURI(2).call() == 'https://metadata.example/final/2.json'
    assert edition.functions.ownerOf(2).call() == bob
    assert edition.functions.transferNonce(2).call() == 1
    assert auction.functions.refunds(alice).call() == reserve
    tx(auction.functions.withdrawUnclaimedETH(recipient), replacement, succeeds=False)
    assert not auction.functions.refundsClosed().call()
    tx(auction.functions.withdrawRefund(alice), alice)
    tx(auction.functions.withdrawProceeds(replacement), replacement)
    tx(auction.functions.claimUnsold(88, alice), replacement)
    tx(market.functions.withdraw(alice), alice)
    tx(market.functions.withdrawRoyalties(replacement), replacement)
    assert edition.functions.totalSupply().call() == 100
    assert auction.functions.liabilities().call() == 0
    assert market.functions.totalCredits().call() == 0
    assert [w3.eth.get_balance(contract.address) for contract in contracts] == [0, 0, 0]
    return {'result': 'PASS', 'auction': auction.address, 'royaltyBps': 1000,
            'allThreeTokenTypesOnAllThreeContracts': True, 'metadataBeforeAndAfterMint': True,
            'metadataEventsVerified': True, 'walletRotationRevokesOldAdmin': True,
            'ethEntitlementsPreservedAndWithdrawn': True, 'noEarlyEthRecovery': True,
            'rejectedTransactions': rejected, 'minted': 100, 'gasUsed': gas,
            'auctionEndingLiabilities': 0, 'marketEndingLiabilities': 0,
            'endingEthBalances': [0, 0, 0]}
