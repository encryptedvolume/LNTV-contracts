"""Exercise the release checker against deliberately poisoned local registry state."""
from pathlib import Path
import json, socket, subprocess, sys, time
from web3 import Web3

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from local_e2e import artifact, native
from local_trading_setup import configure_local_trading
from check_deployment import check


def main():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    process = subprocess.Popen([native('anvil'), '--host', '127.0.0.1', '--port', str(port),
                                '--chain-id', '31337', '--silent'], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL)
    try:
        w3 = Web3(Web3.HTTPProvider(f'http://127.0.0.1:{port}'))
        for _ in range(100):
            if w3.is_connected(): break
            time.sleep(0.05)
        assert w3.eth.chain_id == 31337
        deployer, payout, replacement, unexpected = w3.eth.accounts[:4]
        start = w3.eth.get_block('latest').timestamp + 3600
        config = dict(CHAIN_ID='31337', PAYOUT_WALLET=payout, ROYALTY_BPS='1000',
                      RESERVE_WEI=str(10**16), START_TIME=str(start), METADATA_URI='https://audit/',
                      COLLECTION_NAME='Policy audit', COLLECTION_SYMBOL='PA', REQUIRE_ENFORCED_TRADING='true')

        def send(fn, sender):
            receipt = w3.eth.wait_for_transaction_receipt(fn.transact({'from': sender, 'gas': 8_000_000}))
            assert receipt.status == 1
            return receipt

        factory = w3.eth.contract(abi=artifact('RankedAuction')['abi'], bytecode=artifact('RankedAuction')['bytecode']['object'])
        receipt = send(factory.constructor((payout, 1000, 10**16, start, 'https://audit/', 'Policy audit', 'PA')), deployer)
        auction = w3.eth.contract(address=receipt.contractAddress, abi=artifact('RankedAuction')['abi'])
        edition = w3.eth.contract(address=auction.functions.edition().call(), abi=artifact('AuctionEdition')['abi'])
        configure_local_trading(w3, edition, payout, artifact)
        registry = w3.eth.contract(address=edition.functions.OPENSEA_TRANSFER_VALIDATOR().call(),
                                   abi=artifact('StrictAuthorizedTransferSecurityRegistry')['abi'])
        assert check(w3, auction.address, config)['result'] == 'PASS'
        list_id = edition.functions.tradingListId().call()
        # The edition has no generic execution API. Impersonation here corrupts local fixture
        # state to challenge the checker; it is not an alleged public-chain attack path.
        w3.provider.make_request('anvil_impersonateAccount', [edition.address])
        w3.provider.make_request('anvil_setBalance', [edition.address, hex(10**18)])
        cases = [
            ('extra operator', registry.functions.addAccountToWhitelist(list_id, unexpected), edition.address, 'Unexpected operator set'),
            ('extra authorizer', registry.functions.addAccountToAuthorizers(list_id, unexpected), edition.address, 'Unexpected authorizer set'),
            ('nonempty blacklist', registry.functions.addAccountToBlacklist(list_id, unexpected), edition.address, 'Unexpected operator-requiring-authorization list'),
            ('old-wallet-owned list', registry.functions.reassignOwnershipOfList(list_id, payout), edition.address, 'Trading list must be owned by the edition'),
            ('policy downgrade', registry.functions.setTransferSecurityLevelOfCollection(edition.address, 1), payout, 'Expected strict security level 4'),
            ('unrecorded list', registry.functions.applyListToCollection(edition.address, 0), payout, 'Unexpected active trading list'),
        ]
        results = []
        for name, fn, sender, expected in cases:
            snapshot = w3.provider.make_request('evm_snapshot', [])['result']
            send(fn, sender)
            try:
                check(w3, auction.address, config)
            except AssertionError as exc:
                assert expected in str(exc), (name, str(exc))
                results.append({'case': name, 'result': 'REJECTED_AS_EXPECTED'})
            else:
                raise AssertionError(f'Checker accepted {name}')
            assert w3.provider.make_request('evm_revert', [snapshot])['result']
        send(auction.functions.proposePayoutWallet(replacement), payout)
        send(auction.functions.acceptPayoutWallet(), replacement)
        assert check(w3, auction.address, dict(config, PAYOUT_WALLET=replacement))['result'] == 'PASS'
        results.append({'case': 'default policy after payout rotation', 'result': 'PASS'})
        print(json.dumps({'result': 'PASS', 'chainId': 31337, 'cases': results}, indent=2))
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()


if __name__ == '__main__':
    main()
