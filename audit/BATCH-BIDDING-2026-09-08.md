# Batch bidding — 2026-09-08

Interface 3.2.0 adds `createBids(uint256[] amounts)` and `IncorrectPayment`.
The creator requested this feature and then instructed: “No need to do mutation
testing” and “Finish up the current run here; Claude will audit.”

## Contract behavior

- Accept 1–90 independent bids in input order, with ETH equal to their exact sum.
- Share private `_createBid(bidder, bidAmount)` with the existing single-bid entry point.
- Check the updated reserve/floor and individual uint128 amount limit for every entry.
- Keep each bid's owner, original ID, amount, rank, refund and NFT entitlement separate.
- Later entries can displace earlier batch entries and credit their full pull refunds.
- Any failed entry reverts all batch effects, including IDs, escrow, ranks, credits,
  ETH transfer, events and extensions. Reverted transactions still consume gas.
- A successful late batch leaves ten minutes once; it does not add ten minutes per bid.
- Retain the 48-hour initial auction, 5% floor outbid, 2.5% top-up, uncapped extensions,
  90/10 allocation, rank-one full price, cutoff pricing and trading-only royalties.
- Recovery remains 28 days after first successful settlement; refunds close only on
  successful recovery. No new deployment parameter or external platform dependency.
- The ABI is exported; frontend code and its copied interface are unchanged.

## Completed validation

`AUDIT_FUZZ_SEED=0x2026090832 npm run audit` completed its formatting, tool-regression,
static, coverage and extended-test stages. The wrapper was stopped at the creator's
request during mutation testing. **This is not a complete audit PASS.**

| Check | Result |
|---|---|
| Solidity tests | 187 passed, zero failed or skipped; 30 new batch tests |
| Stateless fuzzing | Seven tests × 10,000 runs |
| Stateful invariants | Three campaigns × 1,000 runs × 256 calls; 768,000 actions, zero unexpected reverts |
| Batch model actions | 72,810 mixed batch calls across both auction models |
| Production coverage | 100% lines, statements, branches and functions |
| Tool regressions | 2 native-runner, 7 audit-gate and 14 mutation-runner tests passed |
| Static review | 28 individually reviewed findings, none unreviewed |
| Dedicated batch rehearsal | Passed on isolated local Anvil; 100 NFTs minted, final auction balance and liabilities zero |
| Interface | Fresh build matches 3.2.0 exports |
| Mutation testing | Stopped by request; 4/90 cases completed, no new batch mutations reached |
| Independent audit | Deferred to Claude by creator instruction |

Tests cover exact totals, escrow/surplus misuse, numeric limits, empty/oversized inputs,
phases, ties, event ownership and IDs, dynamic floor changes, capacity crossing,
rounding, self-displacement, failed-later-entry rollback, contract wallets,
cross-function reentry, top-ups, refunds, tiered settlement and NFT claims. Fuzz tests
compare batches to sequential bids and test rollback; both auction models independently
check ranking, pointers and every wei while mixing singles, batches and other actions.
The coverage build exposed a stack-depth limit in the new test's state encoder;
splitting that encoder fixed it without changing production code or coverage settings.

## Measured gas and batch-size limits

These are local scenario measurements, not universal gas or fee guarantees.

| Scenario | Gas used |
|---|---:|
| Three different bids in one batch | 430,421 |
| Same bids as three transactions, total | 530,430 |
| 90 equal reserve bids on an empty book | 13,667,532 |
| Two late bids on a full book | 366,336 |
| First 45 bids on a dense full book | 7,371,850 |
| Remaining 45 bids on that book | 7,360,192 |

The 90-item cap bounds execution but does not guarantee gas fit in every state.
A dense 90-bid call estimated 17,861,124 gas and exhausted
the rehearsal's 16,000,000-gas limit. Every effect rolled back; retrying as two
45-bid transactions succeeded and matched the independent model. Simulate the
complete call, estimate gas, and reduce quantity for the network/wallet budget.
The dedicated rehearsal also checked per-bid events, live displaced refunds,
one late extension, settlement, winner excess, all 100 NFT claims and payout.

## Evidence and handoff

Current evidence: [results.json](results.json), [run log](generated/batch-bidding-audit.log),
[extended tests](generated/extended-tests.log), [batch rehearsal](generated/batch-bidding-e2e.json),
and [SHA256SUMS](SHA256SUMS). The interrupted mutation attempt is retained under
`history/2026-09-08-batch-mutations-interrupted/`. Top-level mutation reports retain
the previous 3.1.0 campaign and do not attest this source; see
[mutation status](generated/MUTATION-STATUS.md). The previous full lifecycle/recovery
rehearsal was not rerun after the creator ended this run. Prior results and manifest
are archived as `history/2026-09-08-pre-batch-bidding-*` and remain in Git history.

The new mutation definitions remain available for a future audit; the permanent
audit gates were not weakened. [ISSUES.md](ISSUES.md) retains existing unrelated
findings and integration/release work. No public deployment or frontend change was
performed, and no absence-of-all-defects claim or independent audit is asserted.
