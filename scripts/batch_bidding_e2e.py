"""Actual local transactions for batch value accounting, rollback, ranking, claims and gas."""
from web3.logs import DISCARD


def run_batch_bidding(w3, artifact):
    deployer, payout, alice, bob, recipient = w3.eth.accounts[:5]
    start = w3.eth.get_block("latest").timestamp + 600
    reserve = 10**16
    source = artifact("RankedAuction")
    factory = w3.eth.contract(abi=source["abi"], bytecode=source["bytecode"]["object"])
    config = (payout, 750, reserve, start, "https://metadata.example/batch/", "Batch Test", "BID")
    receipt = w3.eth.wait_for_transaction_receipt(factory.constructor(config).transact({"from": deployer, "gas": 8_000_000}))
    assert receipt.status == 1
    auction = w3.eth.contract(address=receipt.contractAddress, abi=source["abi"])
    edition = w3.eth.contract(address=auction.functions.edition().call(), abi=artifact("AuctionEdition")["abi"])
    gas = {}

    def rpc(method, params):
        result = w3.provider.make_request(method, params)
        assert "error" not in result, result
        return result["result"]

    def transact(function, sender, value=0, succeeds=True, timestamp=None):
        if timestamp is not None:
            rpc("evm_setNextBlockTimestamp", [timestamp])
        tx = function.transact({"from": sender, "value": value, "gas": 16_000_000})
        mined = w3.eth.wait_for_transaction_receipt(tx)
        assert bool(mined.status) == succeeds, (function.fn_name, mined.status, mined.gasUsed)
        if timestamp is not None:
            assert w3.eth.get_block(mined.blockNumber).timestamp == timestamp
        if not succeeds:
            assert len(mined.logs) == 0
        return mined

    transact(auction.functions.createBids([reserve]), alice, reserve, succeeds=False, timestamp=start - 1)
    rpc("evm_setNextBlockTimestamp", [start])
    rpc("evm_mine", [])

    # Compare identical empty-book inputs in isolated snapshots of the same deployment.
    snapshot = rpc("evm_snapshot", [])
    values = [10 * reserve, 12 * reserve, 15 * reserve]
    assert auction.functions.createBids(values).call({"from": alice, "value": sum(values)}) == [1, 2, 3]
    batch = transact(auction.functions.createBids(values), alice, sum(values))
    gas["three_bids_batch"] = batch.gasUsed
    assert [event["args"]["amount"] for event in auction.events.BidCreated().process_receipt(batch)] == values
    assert all(auction.functions.bids(i).call()[0] == alice for i in range(1, 4))
    assert rpc("evm_revert", [snapshot])
    snapshot = rpc("evm_snapshot", [])
    gas["three_bids_separate_total"] = sum(transact(auction.functions.createBid(), alice, value).gasUsed for value in values)
    assert gas["three_bids_batch"] < gas["three_bids_separate_total"]
    assert rpc("evm_revert", [snapshot])

    # A dense full book exercises near-tail insertions and repeated self-displacement.
    snapshot = rpc("evm_snapshot", [])
    existing = [i * reserve for i in range(90, 0, -1)]
    transact(auction.functions.createBids(existing), alice, sum(existing))
    model = [(amount, i + 1, alice) for i, amount in enumerate(existing)]
    values = []
    credits = {alice: 0, bob: 0}
    for bid_id in range(91, 181):
        floor = model[-1][0]
        value = floor + (floor * 500 + 9999) // 10000
        values.append(value)
        model.append((value, bid_id, bob))
        model.sort(key=lambda item: (-item[0], item[1]))
        amount, _, owner = model.pop()
        credits[owner] += amount
    dense_estimate = auction.functions.createBids(values).estimate_gas({"from": bob, "value": sum(values)})
    assert dense_estimate > 16_000_000
    # Quantity is a contract bound, not a promise that every 90-item shape fits a network gas budget.
    original_ranks = auction.functions.rankedBids(0, 90).call()[0]
    original_balance = w3.eth.get_balance(auction.address)
    too_large = transact(auction.functions.createBids(values), bob, sum(values), succeeds=False)
    assert too_large.gasUsed == 16_000_000
    assert auction.functions.rankedBids(0, 90).call()[0] == original_ranks
    assert auction.functions.nextBidId().call() == 91
    assert auction.functions.totalRefunds().call() == 0
    assert w3.eth.get_balance(auction.address) == original_balance
    gas["forty_five_bids_dense_first"] = transact(auction.functions.createBids(values[:45]), bob, sum(values[:45])).gasUsed
    gas["forty_five_bids_dense_second"] = transact(auction.functions.createBids(values[45:]), bob, sum(values[45:])).gasUsed
    assert auction.functions.rankedBids(0, 90).call()[0] == [bid_id for _, bid_id, _ in model]
    assert auction.functions.refunds(alice).call() == credits[alice]
    assert auction.functions.refunds(bob).call() == credits[bob]
    assert credits[bob] > 0
    assert auction.functions.escrow().call() == sum(amount for amount, _, _ in model)
    assert auction.functions.liabilities().call() == w3.eth.get_balance(auction.address)
    assert rpc("evm_revert", [snapshot])

    # Rehearse all 100 mint entitlements and drain every legitimate ETH liability.
    maximum = transact(auction.functions.createBids([reserve] * 90), alice, reserve * 90)
    gas["ninety_bids_empty_book_ties"] = maximum.gasUsed
    assert [event["args"]["id"] for event in auction.events.BidCreated().process_receipt(maximum)] == list(range(1, 91))
    end = auction.functions.endTime().call()
    before = (auction.functions.nextBidId().call(), auction.functions.escrow().call(), w3.eth.get_balance(auction.address))
    rejected = transact(auction.functions.createBids([2 * reserve, 0]), bob, 2 * reserve, succeeds=False, timestamp=end - 2)
    assert (auction.functions.nextBidId().call(), auction.functions.escrow().call(), w3.eth.get_balance(auction.address)) == before
    assert auction.functions.endTime().call() == end
    assert auction.functions.refunds(alice).call() == 0
    assert auction.functions.bids(90).call()[4]

    late = transact(auction.functions.createBids([2 * reserve, 3 * reserve]), bob, 5 * reserve, timestamp=end - 1)
    gas["two_bids_late_full_book"] = late.gasUsed
    assert auction.functions.endTime().call() == end + 599
    assert len(auction.events.AuctionExtended().process_receipt(late, errors=DISCARD)) == 1
    assert [event["args"]["id"] for event in auction.events.BidCreated().process_receipt(late, errors=DISCARD)] == [91, 92]
    assert auction.functions.refunds(alice).call() == 2 * reserve
    before = w3.eth.get_balance(recipient)
    transact(auction.functions.withdrawRefund(recipient), alice)
    assert w3.eth.get_balance(recipient) - before == 2 * reserve
    transact(auction.functions.createBids([reserve]), bob, reserve, succeeds=False, timestamp=end + 599)
    transact(auction.functions.settle(), deployer)
    assert auction.functions.winningBidCost(92).call() == 3 * reserve
    assert auction.functions.winningBidCost(91).call() == reserve
    transact(auction.functions.creditRefunds([91, 92]), deployer)
    before = w3.eth.get_balance(recipient)
    transact(auction.functions.withdrawRefund(recipient), bob)
    assert w3.eth.get_balance(recipient) - before == reserve
    transact(auction.functions.claimTokens([91, 92], bob), bob)
    transact(auction.functions.claimTokens(list(range(1, 89)), alice), alice)
    transact(auction.functions.creditRefunds(list(range(1, 89))), deployer)
    transact(auction.functions.claimReserved(10, payout), payout)
    assert edition.functions.totalSupply().call() == 100
    assert edition.functions.balanceOf(alice).call() == 88
    assert edition.functions.balanceOf(bob).call() == 2
    assert edition.functions.balanceOf(payout).call() == 10
    assert edition.functions.ownerOf(1).call() == bob
    assert auction.functions.pendingProceeds().call() == 92 * reserve
    transact(auction.functions.withdrawProceeds(recipient), payout)
    assert auction.functions.liabilities().call() == 0
    assert w3.eth.get_balance(auction.address) == 0
    assert max(gas.values()) < 16_000_000
    return {"result": "PASS", "auction": auction.address, "gasUsed": gas,
            "batchSizeLimit": 90, "maximumBatchMined": True,
            "denseNinetyBidGasEstimate": dense_estimate, "transactionGasBudget": 16_000_000,
            "overBudgetBatchRolledBackAndRetriedAsTwoBatches": True,
            "denseBookMatchesIndependentModel": True, "sameBatchDisplacementRefunded": True,
            "rejectedBatchRollsBackEventsEscrowRefundsIdsAndTimer": rejected.status == 0,
            "oneExtensionForLateBatch": True, "minted": 100,
            "auctionEndingLiabilities": 0, "auctionEndingBalance": 0}
