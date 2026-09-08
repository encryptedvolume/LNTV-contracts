# F3-02 fix: recovery delay starts at settlement — 2026-09-08

> Historical 3.1.0 evidence. Current batch changes and the creator-limited validation run are documented in [batch bidding](BATCH-BIDDING-2026-09-08.md). Settlement-based recovery remains in effect.

The creator explicitly approved: “Yep okay move recovery timer to settlement
date.” This supersedes the earlier auction-end anchor in interface 3.0.0.
The existing optional closure rule remains: refunds stay available until the
current payout wallet successfully recovers the remaining auction ETH.

## Behavior and finding disposition

- The first successful `settle()` records `block.timestamp` in `uint256 settledAt`.
- After settlement, `recoveryAvailableAt()` is exactly `settledAt + 28 days`.
  Late settlement grants the same full protected interval as prompt settlement.
- Before settlement, `settledAt` is zero and the recovery getter returns only an
  earliest estimate, `endTime + 28 days`. This estimate moves with extensions;
  it does not authorize recovery or start the actual timer.
- Repeated settlement reverts and cannot reset the date. Payout-wallet rotation,
  normal proceeds withdrawals, refunds and NFT claims do not change it.
- A contract payout wallet cannot settle and sweep in one transaction. The
  recovery call reverts `RecoveryNotAvailable`, rolling back that transaction's
  settlement as well. Anyone can separately settle to open winner refunds.
- For example, settlement 27 days after bidding ends makes recovery available
  55 days after bidding ends, not day 28.
- At eligibility refunds still do not expire. Only successful recovery closes
  outstanding refunds; failed/empty attempts leave the previous state intact.
  NFT claims and marketplace credits/royalties remain independent.

F3-02 from [Claude/Fable's third review](INDEPENDENT-AUDIT-2026-09-08-fable-3.md)
is resolved. The original report and PoCs are preserved unchanged as evidence
of the prior `0d52419` source. The package regression suite now asserts that its
late-settlement and atomic-settlement/recovery scenarios cannot shorten the
protected window. Other third-review findings are reconciled in [ISSUES.md](ISSUES.md).

Interface 3.1.0 adds `settledAt()` and updates eligibility semantics. No deployment
parameter was added. The frontend code, wording and copied 1.1.0 interface remain
unchanged by request. Existing deployed bytecode cannot acquire this behavior;
no public deployment is recorded.

## Verification

Full `AUDIT_FUZZ_SEED=0x2026090830 npm run audit` passed with Node 22.23.1.

| Check | Result |
|---|---|
| Solidity suite | 157 passed, 0 failed, 0 skipped; 30 recovery scenarios |
| Stateless fuzzing | Five tests, 10,000 runs each; recovery fuzz independently varies settlement delay, recovery delay, claims and forced ETH |
| Stateful invariants | Three campaigns; 1,000 runs × 256 calls; 768,000 calls, zero unexpected reverts |
| Production coverage | 100% lines, statements, branches and functions |
| Mutations | 80/80 detected by at least two behavioral tests; clean 154-test baseline |
| Tool regressions | 2 native-runner, 7 audit-gate, 14 mutation-runner tests passed |
| Static analysis | 16 reviewed findings; no unreviewed findings or source drift |
| Original local lifecycle | Full 90-place lifecycle, 100 NFTs, uncapped extensions, settlement, refunds, resale, payout rotation; zero final liabilities |
| Recovery rehearsal | Settlement on day 27; recovery rejected on old day 28 and one second before the new eligibility; successful bidder withdrawals, wallet rotation and eventual recovery; NFT claims survive |
| Interface | Fresh build matches 3.1.0 exports |

New deterministic cases cover atomic late settlement/recovery, settlement on
day 27, attempts to reset settlement, a changing pre-settlement estimate and
timestamps beyond uint64. The previous late-settlement test now requires the
full delay. New mutants restore the auction-end anchor, omit timestamp recording
or make the recovery clock move forever. Named scenario requirements protect
these checks from accidental removal. The existing stateful handlers retain
their prior auction/marketplace scope; dedicated unit/fuzz tests and the local
transaction rehearsal cover recovery.

Recording settlement adds one storage write, paid once by the settlement caller.
An isolated two-winner call comparison measured about 22,100 extra gas in
settlement, with ordinary bidder actions effectively unchanged. This is a call
comparison, not a universal transaction-fee quote or contract-wallet gas bound.

Evidence: [settlement-clock-audit.log](generated/settlement-clock-audit.log),
[results.json](results.json), [mutations.json](generated/mutations.json), and
[SHA256SUMS](SHA256SUMS). The manifest covers source, tests, tools, documentation,
exports and evidence. Verify with `sha256sum -c audit/SHA256SUMS` from the root.
Prior results and manifest are archived under
`history/2026-09-08-pre-settlement-clock-*`; Git preserves the previous source.

This automated verification does not close the other listed findings, replace
an independent audit, deploy contracts, merge the PR, or implement the frontend
or reveal service.
