# Current issue register

Last reconciled: 2026-09-08, including [Fable's second independent review](INDEPENDENT-AUDIT-2026-09-07-fable-2.md). This is the current status list for the contract package and the related integration work discussed with the creator. Historical audits retain their original findings, measurements and source snapshots.

There are **eight open work items (two optional)**, **two accepted design findings**, **three resolved findings** and disclosed informational findings. Integration tasks are work still to build; they are not production-contract vulnerabilities. Accepted means the creator explicitly chose to retain the behavior. Resolved means a corrective change was verified.

## Open work

| ID | Item | Current evidence | Completion condition |
|---|---|---|---|
| A-01 | Combined audit and evidence refresh | The current default suite passes 127 tests; the strengthened 57-mutation campaign and four local lifecycle rehearsals passed separately. The last complete extended audit and coverage snapshot predates the 2.5% change. | Run the complete current `npm run audit`, review its results, and refresh the consolidated report, result snapshot and hash manifest for that exact source and test revision. |
| Fable 2026-09-07 P-03 | Version control and durable evidence | `auction/` and `.github/` remain untracked in this checkout; generated evidence is ignored by Git. No separate contract repository is configured. | Commit the contract package and CI configuration and retain matching audit evidence durably with an identifiable source revision. A separate repository is optional. |
| APP-01 | Off-chain metadata and reveal service | The contract provides fixed per-token URLs. The creator-enabled, owner-requested reveal service is not implemented in this package. | Implement and verify unrevealed metadata for all 100 tokens, creator activation and authenticated owner reveal requests. |
| APP-02 | Wallet and contract integration | The local bidding page is an in-memory simulation with no wallet or RPC access. | Connect the page to the deployed auction and implement real bids, increases, ranking updates, settlement, refunds and NFT claims with transaction state handling. |
| DEP-01 | Public testnet deployment and connected rehearsal | Successful rehearsals use isolated Anvil chain 31337; no public-chain deployment is recorded for this package. | Deploy and verify the contracts on the chosen testnet, connect the frontend, and rehearse the auction, refunds, claims, payout rotation and secondary-sale flows. |
| Fable second pass N-01 | Ranked-list back-pointer regression coverage | The invariants catch the proposed regression, but a mutant deleting the successor's `prev` update survives the unit-only mutation selection. This is a test coverage gap, not a demonstrated defect in the current contract. | Add explicit list-integrity unit checks and both pointer-update mutants to the mutation gate. |
| Fable second pass N-04 | Extra-mutant redundancy (optional) | Fifteen additional mutants outside the package campaign have only one behavioral test failure. | Strengthen independent behavioral coverage for these additional boundaries if adopted into the campaign. |
| Fable second pass N-05 | Deployment operator guidance (optional) | Post-broadcast binding checks cannot roll back a mined deployment; hardware-wallet approval can consume the ten-minute minimum lead time. | Document post-check recovery and recommend at least one hour of start-time lead for hardware-wallet deployment. |

The second review also supplies a complete passing audit of the current production source on an isolated copy (N-03), but the top-level attestation still needs consolidation under A-01. Its N-02 refines the economics of the already accepted extension policy; that policy is unchanged. N-06 notes the local default Node 18 versus the supported Node 22 runtime.

The last four items are supported by [the package README](../README.md), [the frontend README](../../site/README.md), [operations guidance](../docs/OPERATIONS.md), and the current local Git status. A-01 is tracked separately from P-03 so successful tests do not imply that the source or evidence has been committed.

## Finding dispositions

IDs below refer specifically to [Fable's 2026-09-07 audit](INDEPENDENT-AUDIT-2026-09-07-fable.md). IDs in the older ERC-1155 [review](REVIEW.md) describe a different snapshot and must not be confused with these.

| ID | Original classification | Current status | Basis |
|---|---|---|---|
| M-01 | Medium, liveness/design | **Accepted by design** | Creator explicitly retains uncapped qualifying extensions and the associated active-bid commitment. [Decision](DESIGN-DECISIONS-2026-09-07.md). |
| L-01 | Low, economic/design | **Accepted by design** | Creator explicitly retains no extension when a floor increase preserves rank, including at the last moment. [Decision](DESIGN-DECISIONS-2026-09-07.md). |
| L-02 | Low, forced mint delivery | **Resolved** | Only the original winning bidder may claim or redirect its NFTs; existing and additional behavioral tests reject forced delivery, and the corresponding mutations are caught. [Named mutation failures](generated/mutation-strengthening-20260907/updated/mutations.json). |
| I-01 | Informational, tie priority | **Disclosed behavior** | Earlier original bid ID wins an exact tie. A tie can change who receives #1 and pays the full winning bid. Documented in the auction rules. |
| P-01 | Low, test timing | **Resolved** | The harness pins and verifies the actual transaction's block timestamp. Four fresh lifecycle runs passed, including delayed submission. [Fix and evidence](TIMING-FIX-2026-09-07.md). |
| P-02 | Informational, mutation robustness | **Resolved** | Added 15 behavioral scenarios. All 57 mutations fail at least two behavioral tests; required scenarios and 12 runner regression tests enforce the gate. [Fix and evidence](MUTATION-STRENGTHENING-2026-09-07.md). |

P-03 remains open in the work table above. Accepted findings retain their original auditor ratings and their documented consequences; acceptance does not mean their behavior was removed by a code fix.

## Evidence status

- Current targeted evidence: [2.5% update](INCREASE-UPDATE-2026-09-07.md), [timing fix](TIMING-FIX-2026-09-07.md) and [mutation strengthening](MUTATION-STRENGTHENING-2026-09-07.md).
- Historical full-run evidence: [REPORT.md](REPORT.md), [REAUDIT-2026-09-07.md](REAUDIT-2026-09-07.md), [results.json](results.json) and [SHA256SUMS](SHA256SUMS) describe the earlier snapshot. The recorded RankedAuction hash differs from the current 2.5% source. They must not be presented as a complete audit of the current tree.
- This reconciliation verified all 377 recorded mutation inputs, the runner hash, the timing-harness hash and the current production hashes against the follow-up evidence. It did not run a new complete audit or close A-01.
- Fable's original M-01 cost table does not match its quoted 0.5% proof-of-concept arithmetic, and its refundable-capital description needs the winning-payment qualification. The audit now includes a dated numerical clarification. Those figures are not current 2.5% attack-cost estimates.

Other documented operating constraints remain in [architecture](../docs/ARCHITECTURE.md) and [operations](../docs/OPERATIONS.md): transfer restrictions and declared-price royalty limits, off-chain metadata trust, receiver compatibility, immutable settings and key-recovery limitations. They are not additional newly discovered defects or implied requests to change the design.
