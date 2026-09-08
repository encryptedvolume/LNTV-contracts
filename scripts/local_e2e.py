#!/usr/bin/env python3
"""Deploy with the real Foundry script to an isolated Anvil and exercise the complete ETH/NFT lifecycle."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

from web3 import Web3
from check_deployment import check
from refund_recovery_e2e import run_refund_recovery

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audit/generated"
OUT.mkdir(parents=True, exist_ok=True)


def native(tool):
    return subprocess.check_output(["node", "scripts/foundry.mjs", tool, "--print-path"], cwd=ROOT, text=True).strip()


def artifact(name):
    return json.loads((ROOT / f"out/{name}.sol/{name}.json").read_text())


def main():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="auction-e2e-") as temporary:
        process = subprocess.Popen([native("anvil"), "--host", "127.0.0.1", "--port", str(port),
                                    "--chain-id", "31337", "--silent"], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE, text=True)
        try:
            w3 = Web3(Web3.HTTPProvider(f"http://127.0.0.1:{port}", request_kwargs={"timeout": 10}))
            for _ in range(90):
                if w3.is_connected():
                    break
                if process.poll() is not None:
                    raise RuntimeError(f"Anvil exited: {process.stderr.read()}")
                time.sleep(0.05)
            else:
                raise RuntimeError("Anvil did not start")
            deployer, payout, next_payout, alice, bob, carol = w3.eth.accounts[:6]
            start = w3.eth.get_block("latest").timestamp + 3600
            env = dict(os.environ, CHAIN_ID="31337", PAYOUT_WALLET=payout,
                       ROYALTY_BPS="750", RESERVE_WEI=str(10**16), START_TIME=str(start),
                       METADATA_URI="https://metadata.example/local-e2e/",
                       COLLECTION_NAME="Local ERC721 NFTs", COLLECTION_SYMBOL="L721",
                       FOUNDRY_BROADCAST=str(Path(temporary) / "broadcast"))
            deployment = subprocess.run([native("forge"), "script", "script/Deploy.s.sol:Deploy", "--rpc-url",
                                         w3.provider.endpoint_uri, "--sender", deployer, "--unlocked", "--broadcast"],
                                        cwd=ROOT, env=env, capture_output=True, text=True)
            (OUT / "local-deployment.log").write_text(deployment.stdout + deployment.stderr)
            if deployment.returncode:
                raise RuntimeError("Local deployment failed; see audit/generated/local-deployment.log")
            broadcast = json.loads((Path(temporary) / "broadcast/Deploy.s.sol/31337/run-latest.json").read_text())
            creations = [tx for tx in broadcast["transactions"] if tx.get("contractName") == "RankedAuction"]
            assert len(creations) == 1, "Deployment must be one atomic contract-creation transaction"
            auction = w3.eth.contract(address=Web3.to_checksum_address(creations[0]["contractAddress"]),
                                     abi=artifact("RankedAuction")["abi"])
            edition = w3.eth.contract(address=auction.functions.edition().call(), abi=artifact("AuctionEdition")["abi"])
            market = w3.eth.contract(address=edition.functions.marketplace().call(), abi=artifact("RoyaltyMarketplace")["abi"])
            deployment_receipt = w3.eth.get_transaction_receipt(creations[0]["hash"])
            assert deployment_receipt.status == 1
            assert edition.functions.auction().call() == auction.address
            assert market.functions.edition().call() == edition.address
            assert auction.functions.startTime().call() == start
            assert edition.functions.totalSupply().call() == 0
            assert edition.functions.metadataURI().call() == "https://metadata.example/local-e2e/"
            assert check(w3, auction.address, env)["result"] == "PASS"
            wrong_config = dict(env, ROYALTY_BPS="751")
            try:
                check(w3, auction.address, wrong_config)
            except AssertionError:
                pass
            else:
                raise AssertionError("Deployment checker accepted incorrect expected configuration")
            try:
                check(w3, auction.address, dict(env, PAYOUT_WALLET=next_payout))
            except AssertionError:
                pass
            else:
                raise AssertionError("Deployment checker accepted an unexpected payout wallet")
            # A forged runtime must not bypass verification by changing one copy of an immutable.
            original_code = w3.eth.get_code(auction.address)
            refs = artifact("RankedAuction")["deployedBytecode"]["immutableReferences"]
            repeated = next(entries for entries in refs.values() if len(entries) > 1)
            corrupted = bytearray(original_code)
            corrupted[repeated[0]["start"] + 31] ^= 1
            w3.provider.make_request("anvil_setCode", [auction.address, "0x" + corrupted.hex()])
            w3.provider.make_request("evm_mine", [])
            try:
                check(w3, auction.address, env)
            except AssertionError:
                pass
            else:
                raise AssertionError("Deployment checker accepted inconsistent immutable bytecode")
            finally:
                w3.provider.make_request("anvil_setCode", [auction.address, "0x" + original_code.hex()])
                w3.provider.make_request("evm_mine", [])
            gas = {"atomic_deployment": deployment_receipt.gasUsed}
            timed_transactions = []

            def transact(function, sender, value=0, succeeds=True, *, timestamp=None):
                if timestamp is not None:
                    # Pin the transaction's block; an intervening evm_mine consumes this timestamp.
                    result = w3.provider.make_request("evm_setNextBlockTimestamp", [timestamp])
                    assert "error" not in result, result
                tx_hash = function.transact({"from": sender, "value": value, "gas": 8_000_000})
                receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
                if timestamp is not None:
                    mined_at = w3.eth.get_block(receipt.blockNumber).timestamp
                    assert mined_at == timestamp, f"{function.fn_name}: expected timestamp {timestamp}, got {mined_at}"
                    timed_transactions.append({"function": function.fn_name, "timestamp": mined_at,
                                               "blockNumber": receipt.blockNumber, "status": receipt.status})
                assert bool(receipt.status) == succeeds, f"Unexpected transaction status: {function.fn_name}"
                return receipt.gasUsed

            transact(auction.functions.claimReserved(1, alice), alice, succeeds=False)
            gas["reserve_4"] = transact(auction.functions.claimReserved(4, payout), payout)
            assert edition.functions.ownerOf(91).call() == payout
            assert edition.functions.ownerOf(94).call() == payout
            assert auction.functions.activeCount().call() == 0
            assert auction.functions.initialEndTime().call() == start + 172800
            gas["worst_bid"] = 0
            for index in range(90):
                gas["worst_bid"] = max(gas["worst_bid"], transact(auction.functions.createBid(), alice, 2*10**16,
                                                                timestamp=start if index == 0 else None))
            assert auction.functions.minimumBid().call() == 21*10**15
            transact(auction.functions.createBid(), bob, 205*10**14, succeeds=False)
            transact(auction.functions.createBid(), bob, 21*10**15 - 1, succeeds=False)
            for amount in (21*10**15, 4*10**16):
                transact(auction.functions.createBid(), bob, amount)
            assert auction.functions.refunds(alice).call() == 4*10**16
            transact(auction.functions.withdrawRefund(alice), alice)
            # Keep swapping the two top ranks with late increases, continuing beyond 24 hours of extensions.
            for index in range(146):
                bid_id = 91 + index % 2
                other_id = 92 if bid_id == 91 else 91
                old_amount = auction.functions.bids(bid_id).call()[1]
                new_amount = max(auction.functions.bids(other_id).call()[1] + 10**16,
                                 old_amount + (old_amount * 250 + 9999) // 10000)
                bid_timestamp = auction.functions.endTime().call() - 1
                transact(auction.functions.increaseBid(bid_id), bob, new_amount - old_amount, timestamp=bid_timestamp)
                assert auction.functions.endTime().call() == bid_timestamp + 600
            extension_seconds = auction.functions.endTime().call() - auction.functions.initialEndTime().call()
            assert extension_seconds > 86400
            transact(auction.functions.settle(), carol, succeeds=False, timestamp=auction.functions.endTime().call() - 1)
            top_price = auction.functions.bids(92).call()[1]
            bob_refund = auction.functions.bids(91).call()[1] - 2*10**16
            gross = top_price + 89 * 2*10**16
            gas["settle"] = transact(auction.functions.settle(), carol, timestamp=auction.functions.endTime().call())
            assert auction.functions.clearingPrice().call() == 2*10**16
            assert auction.functions.pendingProceeds().call() == gross
            assert market.functions.pendingRoyalties().call() == 0
            transact(auction.functions.creditRefunds([91, 92]), carol)
            assert auction.functions.refunds(bob).call() == bob_refund
            transact(auction.functions.withdrawRefund(bob), bob)
            transact(auction.functions.claimTokens([1], alice), carol, succeeds=False)
            gas["claim_88"] = transact(auction.functions.claimTokens(list(range(1, 89)), alice), alice)
            transact(auction.functions.claimTokens([91, 92], bob), bob)
            transact(auction.functions.creditRefunds(list(range(1, 89))), carol)
            assert edition.functions.totalSupply().call() == 94
            assert edition.functions.balanceOf(alice).call() == 88
            assert edition.functions.balanceOf(bob).call() == 2
            for token_id in range(1, 95):
                assert edition.functions.ownerOf(token_id).call() == (payout if token_id > 90 else bob if token_id <= 2 else alice)
                assert edition.functions.tokenURI(token_id).call() == f"https://metadata.example/local-e2e/{token_id}.json"
            assert auction.functions.bids(92).call()[7] == 1
            assert auction.functions.bids(91).call()[7] == 2
            assert auction.functions.liabilities().call() == gross
            assert w3.eth.get_balance(auction.address) == gross

            transact(edition.functions.safeTransferFrom(alice, bob, 3, b""), alice, succeeds=False)
            transact(edition.functions.setApprovalForAll(market.address, True), alice)
            transact(market.functions.list(3, 10**18, w3.eth.get_block("latest").timestamp + 3600), alice)
            transact(market.functions.list(4, 10**18, w3.eth.get_block("latest").timestamp + 3600), alice)
            gas["secondary_sale"] = transact(market.functions.buy(1, carol), bob, 10**18)
            assert market.functions.pendingRoyalties().call() == 75*10**15
            assert market.functions.credits(alice).call() == 925*10**15
            assert edition.functions.ownerOf(3).call() == carol
            assert edition.functions.transferNonce(3).call() == 1
            transact(market.functions.cancel(2), alice)
            transact(market.functions.withdraw(alice), alice)
            # Both accrued business pools must move; nomination alone grants no authority.
            transact(auction.functions.proposePayoutWallet(next_payout), payout)
            assert edition.functions.royaltyRecipient().call() == payout
            try:
                check(w3, auction.address, env)
            except AssertionError:
                pass
            else:
                raise AssertionError("Deployment checker accepted an unexpected pending wallet")
            assert check(w3, auction.address, dict(env, PENDING_PAYOUT_WALLET=next_payout))["result"] == "PASS"
            transact(auction.functions.acceptPayoutWallet(), carol, succeeds=False)
            transact(auction.functions.withdrawProceeds(next_payout), next_payout, succeeds=False)
            transact(market.functions.withdrawRoyalties(next_payout), next_payout, succeeds=False)
            gas["payout_rotation_accept"] = transact(auction.functions.acceptPayoutWallet(), next_payout)
            assert edition.functions.royaltyRecipient().call() == next_payout
            transact(auction.functions.claimReserved(1, payout), payout, succeeds=False)
            gas["reserve_6"] = transact(auction.functions.claimReserved(6, next_payout), next_payout)
            transact(auction.functions.claimReserved(1, next_payout), next_payout, succeeds=False)
            assert edition.functions.ownerOf(94).call() == payout
            for token_id in range(95, 101):
                assert edition.functions.ownerOf(token_id).call() == next_payout
                assert edition.functions.tokenURI(token_id).call() == f"https://metadata.example/local-e2e/{token_id}.json"
            assert edition.functions.totalSupply().call() == 100
            assert auction.functions.reservedRemaining().call() == 0
            assert auction.functions.pendingPayoutWallet().call() == "0x" + "00" * 20
            transact(auction.functions.withdrawProceeds(payout), payout, succeeds=False)
            transact(market.functions.withdrawRoyalties(payout), payout, succeeds=False)
            # Redirect for exact balance checks without subtracting the signer's gas.
            before = w3.eth.get_balance(carol)
            transact(auction.functions.withdrawProceeds(carol), next_payout)
            transact(market.functions.withdrawRoyalties(carol), next_payout)
            assert w3.eth.get_balance(carol) - before == gross + 75*10**15
            assert auction.functions.liabilities().call() == 0
            assert w3.eth.get_balance(auction.address) == 0
            # New trading royalties must also accrue to the replacement wallet.
            transact(market.functions.list(4, 10**18, w3.eth.get_block("latest").timestamp + 3600), alice)
            transact(market.functions.buy(3, bob), bob, 10**18)
            assert edition.functions.ownerOf(4).call() == bob
            assert edition.functions.royaltyInfo(1, 10**18).call()[0] == next_payout
            transact(market.functions.withdraw(alice), alice)
            transact(market.functions.withdrawRoyalties(next_payout), next_payout)
            env = dict(env, PAYOUT_WALLET=next_payout)
            assert w3.eth.get_balance(market.address) == 0
            assert market.functions.totalCredits().call() == 0
            assert check(w3, auction.address, env)["result"] == "PASS"
            # Metadata is served off-chain at stable per-token endpoints; no on-chain reveal controls exist.
            functions = {entry["name"] for entry in artifact("AuctionEdition")["abi"] if entry["type"] == "function"}
            assert not functions.intersection({"reveal", "enableReveals", "revealsEnabled", "revealed"})
            assert edition.functions.tokenURI(3).call() == "https://metadata.example/local-e2e/3.json"
            assert gas["atomic_deployment"] < 6_000_000
            assert gas["worst_bid"] < 1_500_000
            assert gas["settle"] < 2_000_000
            assert gas["claim_88"] < 5_000_000
            result = {"chainId": 31337, "result": "PASS", "auction": auction.address, "edition": edition.address,
                      "marketplace": market.address, "gasUsed": gas, "bids": 92, "minted": 100,
                      "auctionEndingLiabilities": 0, "marketEndingLiabilities": 0,
                      "auctionRoyalties": 0, "initialPayoutWallet": payout, "finalPayoutWallet": next_payout,
                      "walletRotation": "Two-step acceptance, old-wallet revocation, accrued and future revenue",
                      "secondarySales": 2,
                      "tokenStandard": "ERC-721", "tokenIds": "1-90 by final rank; 91-100 reserved",
                      "metadata": "Fixed per-token off-chain endpoints; reveal policy belongs to the metadata service",
                      "pricing": "Top bid pays full; ranks 2-90 pay 90th winning bid or reserve if undersubscribed",
                      "initialDurationSeconds": 172800, "auctionedSupply": 90, "reservedSupply": 10,
                      "outbidBps": 500, "increaseBps": 250, "extensionLimit": None,
                      "extensionWindowSeconds": 600, "lateRankChangingIncreases": 146, "extensionSecondsAfterOriginalClose": extension_seconds,
                      "timedTransactions": timed_transactions,
                      "deploymentCheckerNegativeCases": ["incorrect royalty configuration rejected", "unexpected current payout wallet rejected", "unexpected pending payout wallet rejected", "inconsistent immutable bytecode rejected"],
                      "claimAuthorization": "Third-party forced mint rejected; winning bidders claim successfully"}
            result["refundRecovery"] = run_refund_recovery(w3, artifact)
            (OUT / "local-e2e.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result, indent=2))
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
