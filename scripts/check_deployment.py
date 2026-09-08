#!/usr/bin/env python3
"""Read-only code/config/accounting verification. Supply expected config and RPC_URL through the environment."""
import json
import os
from pathlib import Path
from web3 import Web3

ROOT = Path(__file__).resolve().parents[1]


def check(w3, auction_address, config):
    snapshot = w3.eth.block_number
    snapshot_hash = w3.eth.get_block(snapshot).hash
    def contract(name, address):
        artifact = json.loads((ROOT / f"out/{name}.sol/{name}.json").read_text())
        address = Web3.to_checksum_address(address)
        code = bytearray(w3.eth.get_code(address, block_identifier=snapshot))
        compiled = artifact["deployedBytecode"]
        expected = bytearray.fromhex(compiled["object"].removeprefix("0x"))
        assert code and len(code) == len(expected), f"{name}: code size mismatch"
        for refs in compiled["immutableReferences"].values():
            values = {bytes(code[ref["start"]:ref["start"] + ref["length"]]) for ref in refs}
            assert len(values) == 1, f"{name}: inconsistent copies of an immutable value"
            for ref in refs:
                begin, length = ref["start"], ref["length"]
                code[begin:begin + length] = bytes(length)
                expected[begin:begin + length] = bytes(length)
        assert code == expected, f"{name}: runtime differs from this compiled source"
        return w3.eth.contract(address=address, abi=artifact["abi"])

    assert w3.eth.chain_id == int(config["CHAIN_ID"]), "Wrong RPC chain"
    auction = contract("RankedAuction", auction_address)
    edition = contract("AuctionEdition", auction.functions.edition().call(block_identifier=snapshot))
    market = contract("RoyaltyMarketplace", edition.functions.marketplace().call(block_identifier=snapshot))
    assert edition.functions.auction().call(block_identifier=snapshot) == auction.address, "Invalid auction binding"
    assert market.functions.edition().call(block_identifier=snapshot) == edition.address, "Invalid marketplace binding"
    payout = Web3.to_checksum_address(config["PAYOUT_WALLET"])
    pending = Web3.to_checksum_address(config.get("PENDING_PAYOUT_WALLET", "0x" + "00" * 20))
    assert auction.functions.payoutWallet().call(block_identifier=snapshot) == payout, "Unexpected payout wallet"
    assert auction.functions.pendingPayoutWallet().call(block_identifier=snapshot) == pending, "Unexpected pending wallet"
    assert edition.functions.royaltyRecipient().call(block_identifier=snapshot) == payout
    royalty_receiver, royalty_amount = edition.functions.royaltyInfo(1, 10**18).call(block_identifier=snapshot)
    assert royalty_receiver == payout
    assert royalty_amount == (10**18 * int(config["ROYALTY_BPS"]) + 9999) // 10000
    assert edition.functions.royaltyBps().call(block_identifier=snapshot) == int(config["ROYALTY_BPS"])
    assert auction.functions.reservePrice().call(block_identifier=snapshot) == int(config["RESERVE_WEI"])
    assert auction.functions.startTime().call(block_identifier=snapshot) == int(config["START_TIME"])
    assert auction.functions.initialEndTime().call(block_identifier=snapshot) == (int(config["START_TIME"]) + 172800)
    assert auction.functions.OUTBID_BPS().call(block_identifier=snapshot) == 500
    assert auction.functions.INCREASE_BPS().call(block_identifier=snapshot) == 250
    assert auction.functions.EXTENSION_WINDOW().call(block_identifier=snapshot) == 600
    assert auction.functions.RECOVERY_DELAY().call(block_identifier=snapshot) == 28 * 86400
    settled = auction.functions.settled().call(block_identifier=snapshot)
    settled_at = auction.functions.settledAt().call(block_identifier=snapshot)
    end_time = auction.functions.endTime().call(block_identifier=snapshot)
    if settled:
        assert end_time <= settled_at <= w3.eth.get_block(snapshot).timestamp, "Invalid settlement timestamp"
    else:
        assert settled_at == 0, "Unsettled auction has a settlement timestamp"
    assert auction.functions.recoveryAvailableAt().call(block_identifier=snapshot) == (settled_at if settled else end_time) + 28 * 86400
    assert edition.functions.metadataURI().call(block_identifier=snapshot) == config["METADATA_URI"]
    assert edition.functions.name().call(block_identifier=snapshot) == config["COLLECTION_NAME"]
    assert edition.functions.symbol().call(block_identifier=snapshot) == config["COLLECTION_SYMBOL"]
    assert auction.functions.AUCTION_DURATION().call(block_identifier=snapshot) == 172800
    assert auction.functions.SUPPLY().call(block_identifier=snapshot) == 90
    assert auction.functions.RESERVED_SUPPLY().call(block_identifier=snapshot) == 10
    assert auction.functions.reservedRemaining().call(block_identifier=snapshot) <= 10
    assert edition.functions.MAX_SUPPLY().call(block_identifier=snapshot) == 100
    assert edition.functions.supportsInterface(bytes.fromhex("80ac58cd")).call(block_identifier=snapshot)
    assert edition.functions.supportsInterface(bytes.fromhex("5b5e139f")).call(block_identifier=snapshot)
    assert edition.functions.supportsInterface(bytes.fromhex("49064906")).call(block_identifier=snapshot)
    assert not edition.functions.supportsInterface(bytes.fromhex("d9b67a26")).call(block_identifier=snapshot)
    assert (int(config["START_TIME"]) + 172800) <= auction.functions.endTime().call(block_identifier=snapshot)
    assert auction.functions.activeCount().call(block_identifier=snapshot) <= 90
    assert edition.functions.totalSupply().call(block_identifier=snapshot) <= 100
    assert auction.functions.liabilities().call(block_identifier=snapshot) <= w3.eth.get_balance(auction.address, block_identifier=snapshot)
    assert market.functions.pendingRoyalties().call(block_identifier=snapshot) <= market.functions.totalCredits().call(block_identifier=snapshot)
    assert market.functions.totalCredits().call(block_identifier=snapshot) <= w3.eth.get_balance(market.address, block_identifier=snapshot)
    assert w3.eth.get_block(snapshot).hash == snapshot_hash, "Chain reorganized during verification; retry"
    return {"result": "PASS", "chainId": w3.eth.chain_id, "blockNumber": snapshot, "blockHash": snapshot_hash.hex(), "auction": auction.address,
            "edition": edition.address, "marketplace": market.address,
            "payoutWallet": payout, "pendingPayoutWallet": pending,
            "checks": "Runtime code, immutable bindings, expected payout/configuration, supply and solvency"}


if __name__ == "__main__":
    # Never print RPC_URL: providers may embed credentials in it.
    provider = Web3(Web3.HTTPProvider(os.environ["RPC_URL"], request_kwargs={"timeout": 30}))
    try:
        print(json.dumps(check(provider, os.environ["AUCTION_ADDRESS"], os.environ), indent=2))
    except Exception as exc:
        # Transport exception messages may contain the authenticated RPC URL.
        raise SystemExit(f"Deployment check failed ({type(exc).__name__}); inspect configuration and RPC access locally.") from None
