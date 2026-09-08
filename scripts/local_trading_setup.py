"""Install the verified registry fixture on isolated Anvil; never installs code on a public chain."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
from web3 import Web3

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Web3.to_checksum_address('0xA000027A9B2802E1ddf7000061001e5c005A0000')


def configure_local_trading(w3, edition, payout, artifact, *, use_script=False):
    assert w3.eth.chain_id == 31337, 'Fixture installation is restricted to isolated Anvil'
    if not w3.eth.get_code(REGISTRY):
        source = artifact('StrictAuthorizedTransferSecurityRegistry')
        factory = w3.eth.contract(abi=source['abi'], bytecode=source['bytecode']['object'])
        receipt = w3.eth.wait_for_transaction_receipt(factory.constructor(w3.eth.accounts[0], '0x'+'00'*20).transact(
            {'from': w3.eth.accounts[0], 'gas': 8_000_000}))
        assert receipt.status == 1
        result = w3.provider.make_request('anvil_setCode', [REGISTRY, '0x'+w3.eth.get_code(receipt.contractAddress).hex()])
        assert 'error' not in result, result
    if use_script:
        with tempfile.TemporaryDirectory(prefix='lntv-trading-script-') as temporary:
            env = dict(os.environ, CHAIN_ID='31337', EDITION_ADDRESS=edition.address, PAYOUT_WALLET=payout,
                       FOUNDRY_BROADCAST=str(Path(temporary)/'broadcast'))
            done = subprocess.run(['node', 'scripts/foundry.mjs', 'forge', 'script',
                'script/ConfigureTrading.s.sol:ConfigureTrading', '--rpc-url', w3.provider.endpoint_uri,
                '--sender', payout, '--unlocked', '--broadcast'], cwd=ROOT, env=env, capture_output=True, text=True)
            (ROOT/'audit/generated/local-trading-configuration.log').write_text(done.stdout+done.stderr)
            assert done.returncode == 0, 'See audit/generated/local-trading-configuration.log'
    else:
        receipt = w3.eth.wait_for_transaction_receipt(edition.functions.configureEnforcedTrading().transact(
            {'from': payout, 'gas': 2_000_000}))
        assert receipt.status == 1
    assert edition.functions.tradingConfigured().call()
    assert edition.functions.getTransferValidator().call() == REGISTRY
