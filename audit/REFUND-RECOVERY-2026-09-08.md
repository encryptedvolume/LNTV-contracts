# Refund expiry and unclaimed ETH recovery — 2026-09-08

The creator explicitly requested that unclaimed auction ETH become recoverable
28 days after bidding ends. This supersedes the earlier indefinite-refund policy.
The shared, changeable payout wallet holds this authority; the original deployment
signer has no separate role. Frontend changes were explicitly deferred.

## Behavior

- `REFUND_CLAIM_PERIOD` is fixed at 28 days (2,419,200 seconds).
- `refundDeadline()` is final extended `endTime + 28 days`; settlement cannot reset it.
- Both refund crediting and withdrawal must occur strictly before that deadline.
  Crediting alone does not preserve a claim. The public `refunds(wallet)` getter
  returns zero at expiry, even before recovery.
- After settlement and at/after the deadline, the current payout wallet calls
  `withdrawUnclaimedETH(recipient)` to receive the entire remaining auction balance:
  expired displaced-bid credits, credited and uncredited winner excess,
  unwithdrawn proceeds, and forced surplus. Normal proceeds remain withdrawable
  separately after settlement. A rejected transfer rolls back accounting.
- Recovery zeros the three accounting buckets before its external call under
  the reentrancy guard. Historical private credits cannot be revived or spent.
  An empty recovery reverts; later forced ETH can be recovered again.
- NFT allocations/claims and marketplace seller credits/royalties retain their
  independent lifecycle. No additional deployment parameter was added.

Refund forfeiture is an accepted policy, not an assertion that bidders received
their money. Clearing prices remain historical settlement prices; missed refunds
increase the amount retained by the payout wallet through recovery. Unclaimed NFT
entitlements do not expire. Deployment of this version requires disclosure of
the refund window before real bids; that frontend work remains deferred.

## Verification

Full `AUDIT_FUZZ_SEED=0x2026090828 npm run audit` passed with Node 22.23.1.

| Check | Result |
|---|---|
| Extended Solidity suite | 149 passed, 0 failed, 0 skipped; includes 22 recovery scenarios |
| Stateless fuzzing | Five tests, 10,000 runs each |
| Stateful invariants | Three campaigns; 1,000 runs × 256 calls; 768,000 calls with zero unexpected reverts |
| Production coverage | 100% lines, statements, branches and functions |
| Mutations | 73/73 caught by at least two behavioral tests; clean 146-test baseline |
| Tool regression tests | 2 native-runner, 7 audit-gate and 14 mutation-runner tests passed |
| Static analysis | 18 individually reviewed findings; no unreviewed findings or source drift |
| Existing local lifecycle | 92 bids, 100 NFTs, 146 late increases, 149 pinned transaction timestamps, two resales, wallet rotation and zero final liabilities |
| New local recovery rehearsal | Refund paid one second before expiry; late credits/withdrawals rejected; original deployer and replaced payout wallet denied; replacement wallet recovered 6.01 ETH; zero final balance/liabilities and successful later NFT claims |
| Contract interface | Fresh build matches generated 2.0.0 exports; frontend remains unchanged |

Thirteen new mutants cover authorization, settlement, premature recovery,
shortened/lengthened claim periods, anchoring to the wrong end time, expired
credit visibility and guards, accounting cleanup, surplus and reentrancy.
Critical regressions require named, independently exercised recovery scenarios.
Additional tests cover partial prior withdrawals, rejection/retry, empty/repeated
recovery, forced ETH, preserved NFTs and isolated marketplace balances.

Static review adds three explicit refund-timestamp findings and the balance-derived
zero-withdrawal equality warning. The equality is a nonempty-payment check, not a
target-balance condition. Arbitrary-send and low-level-call findings were re-reviewed
for the new authorized caller and deadline. Recovery has fixed recipient checks,
authorization, settlement/time guards, accounting-before-interaction, and rollback
on transfer failure; tests and mutations exercise those properties.

Evidence: [refund-recovery-audit.log](generated/refund-recovery-audit.log),
[results.json](results.json), and [SHA256SUMS](SHA256SUMS). The checksum manifest
pins source, tests, tooling, documentation, exports and evidence. Run
`sha256sum -c audit/SHA256SUMS` from the repository root to verify the snapshot.
Prior consolidated results and checksums are archived under
`history/2026-09-08-pre-refund-expiry-*`; Git history retains earlier generated
evidence. The previous independent reviews and timing-only audit describe their
earlier source, not this refund policy. This automated review does not close the
existing N-01 or optional N-04/N-05 findings, constitute a new independent manual
audit, or implement public deployment, frontend wallet integration or reveal.
See [ISSUES.md](ISSUES.md).
