"""Independent real-transaction rehearsal of refunds that stay open until successful payout-wallet recovery."""


def run_refund_recovery(w3, artifact):
    deployer, payout, first, second, third, fourth, replacement, recipient = w3.eth.accounts[:8]
    start = w3.eth.get_block("latest").timestamp + 600
    source = artifact("RankedAuction")
    factory = w3.eth.contract(abi=source["abi"], bytecode=source["bytecode"]["object"])
    config = (payout, 750, 10**16, start, "https://metadata.example/refund-recovery/", "Refund Test", "RFD")
    receipt = w3.eth.wait_for_transaction_receipt(factory.constructor(config).transact({"from": deployer, "gas": 8_000_000}))
    assert receipt.status == 1
    auction = w3.eth.contract(address=receipt.contractAddress, abi=source["abi"])
    edition = w3.eth.contract(address=auction.functions.edition().call(), abi=artifact("AuctionEdition")["abi"])
    timed = []

    def transact(function, sender, value=0, succeeds=True, timestamp=None):
        if timestamp is not None:
            response = w3.provider.make_request("evm_setNextBlockTimestamp", [timestamp])
            assert "error" not in response, response
        tx = function.transact({"from": sender, "value": value, "gas": 8_000_000})
        mined = w3.eth.wait_for_transaction_receipt(tx)
        assert bool(mined.status) == succeeds, function.fn_name
        if timestamp is not None:
            actual = w3.eth.get_block(mined.blockNumber).timestamp
            assert actual == timestamp
            timed.append({"function": function.fn_name, "timestamp": actual, "status": mined.status})
        return mined

    transact(auction.functions.createBid(), first, 3 * 10**18, timestamp=start)
    transact(auction.functions.createBid(), second, 2 * 10**18)
    transact(auction.functions.createBid(), third, 10**18)
    transact(auction.functions.createBid(), fourth, 5 * 10**17)
    initial_end = start + 172800
    transact(auction.functions.increaseBid(3), third, 15 * 10**17, timestamp=initial_end - 1)
    final_end = initial_end + 599
    available_at = final_end + 28 * 86400
    assert auction.functions.endTime().call() == final_end
    assert auction.functions.recoveryAvailableAt().call() == available_at
    assert auction.functions.RECOVERY_DELAY().call() == 28 * 86400
    transact(auction.functions.settle(), deployer, timestamp=final_end)
    transact(auction.functions.creditRefunds([2]), deployer)
    assert auction.functions.refunds(second).call() == 199 * 10**16
    assert auction.functions.refunds(third).call() == 0
    assert auction.functions.escrow().call() == 298 * 10**16
    assert auction.functions.pendingProceeds().call() == 303 * 10**16
    transact(auction.functions.withdrawUnclaimedETH(recipient), payout, succeeds=False, timestamp=initial_end + 28 * 86400)
    transact(auction.functions.withdrawUnclaimedETH(recipient), payout, succeeds=False, timestamp=available_at - 2)
    before = w3.eth.get_balance(recipient)
    transact(auction.functions.withdrawRefund(recipient), second, timestamp=available_at - 1)
    assert w3.eth.get_balance(recipient) - before == 199 * 10**16
    transact(auction.functions.creditRefunds([3]), deployer, timestamp=available_at)
    assert not auction.functions.refundsClosed().call()
    assert auction.functions.refunds(third).call() == 249 * 10**16
    transact(auction.functions.withdrawUnclaimedETH(auction.address), payout, succeeds=False, timestamp=available_at + 7 * 86400)
    assert not auction.functions.refundsClosed().call()
    before = w3.eth.get_balance(recipient)
    transact(auction.functions.withdrawRefund(recipient), third, timestamp=available_at + 14 * 86400)
    assert w3.eth.get_balance(recipient) - before == 249 * 10**16
    assert not auction.functions.refundsClosed().call()
    transact(auction.functions.withdrawUnclaimedETH(recipient), deployer, succeeds=False)
    transact(auction.functions.proposePayoutWallet(replacement), payout)
    transact(auction.functions.acceptPayoutWallet(), replacement)
    transact(auction.functions.withdrawUnclaimedETH(recipient), payout, succeeds=False)
    before = w3.eth.get_balance(recipient)
    recovery = transact(auction.functions.withdrawUnclaimedETH(recipient), replacement)
    recovered = w3.eth.get_balance(recipient) - before
    assert recovered == 352 * 10**16
    assert auction.functions.refundsClosed().call()
    assert w3.eth.get_balance(auction.address) == 0
    assert auction.functions.liabilities().call() == 0
    assert auction.functions.escrow().call() == 0
    assert auction.functions.totalRefunds().call() == 0
    assert auction.functions.pendingProceeds().call() == 0
    transact(auction.functions.creditRefunds([4]), deployer, succeeds=False)
    transact(auction.functions.withdrawRefund(recipient), third, succeeds=False)
    transact(auction.functions.withdrawUnclaimedETH(recipient), replacement, succeeds=False)
    transact(auction.functions.claimTokens([1], first), first)
    transact(auction.functions.claimTokens([4], fourth), fourth)
    assert edition.functions.ownerOf(1).call() == first
    assert edition.functions.ownerOf(4).call() == fourth
    return {"result": "PASS", "auction": auction.address, "recoveryDelaySeconds": 28 * 86400,
            "initialEnd": initial_end, "finalEnd": final_end, "recoveryAvailableAt": available_at,
            "timedTransactions": timed, "refundBeforeRecoveryEligibilityWei": 199 * 10**16,
            "refundAfterRecoveryEligibilityWei": 249 * 10**16, "recoveredWei": recovered, "recoveryGas": recovery.gasUsed,
            "auctionEndingLiabilities": 0, "auctionEndingBalance": 0,
            "originalDeployerDenied": True, "oldPayoutWalletDeniedAfterRotation": True,
            "refundsStayOpenUntilRecovery": True, "rejectedRecoveryLeavesRefundsOpen": True,
            "refundsClosedAfterRecovery": True, "nftClaimsAfterRecovery": True}
