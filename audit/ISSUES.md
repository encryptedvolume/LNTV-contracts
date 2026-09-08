# Current issue register

Last reconciled: 2026-09-08, including [Fable's second independent review](INDEPENDENT-AUDIT-2026-09-07-fable-2.md). This is the current status list for the contract package and the related integration work discussed with the creator. Historical audits retain their original findings, measurements and source snapshots.

There are **six open work items (two optional)**, **two accepted design findings**, **five resolved findings/work items** and disclosed informational findings. Integration tasks are work still to build; they are not production-contract vulnerabilities. Accepted means the creator explicitly chose to retain the behavior. Resolved means a corrective change was verified.

## Open work

| ID | Item | Current evidence | Completion condition |
|---|---|---|---|
| APP-01 | Off-chain metadata and reveal service | The contract provides fixed per-token URLs. The creator-enabled, owner-requested reveal service is not implemented in this package. | Implement and verify unrevealed metadata for all 100 tokens, creator activation and authenticated owner reveal requests. |
| APP-02 | Wallet and contract integration | The local bidding page is an in-memory simulation with no wallet or RPC access. | Connect the page to the deployed auction and implement real bids, increases, ranking updates, settlement, refunds and NFT claims with transaction state handling. |
| DEP-01 | Public testnet deployment and connected rehearsal | Successful rehearsals use isolated Anvil chain 31337; no public-chain deployment is recorded for this package. | Deploy and verify the contracts on the chosen testnet, connect the frontend, and rehearse the auction, refunds, claims, payout rotation and secondary-sale flows. |
| Fable second pass N-01 | Ranked-list back-pointer regression coverage | The invariants catch the proposed regression, but a mutant deleting the successor's `prev` update survives the unit-only mutation selection. This is a test coverage gap, not a demonstrated defect in the current contract. | Add explicit list-integrity unit checks and both pointer-update mutants to the mutation gate. |
| Fable second pass N-04 | Extra-mutant redundancy (optional) | Fifteen additional mutants outside the package campaign have only one behavioral test failure. | Strengthen independent behavioral coverage for these additional boundaries if adopted into the campaign. |
| Fable second pass N-05 | Deployment operator guidance (optional) | Post-broadcast binding checks cannot roll back a mined deployment; hardware-wallet approval can consume the ten-minute minimum lead time. | Document post-check recovery and recommend at least one hour of start-time lead for hardware-wallet deployment. |

The second review supplies a complete passing audit of the current production source on an isolated copy (N-03). A fresh complete standalone-repository run and consolidated attestation on 2026-09-08 now close A-01. Its N-02 refines the economics of the already accepted extension policy; that policy is unchanged. N-06 is addressed by `.nvmrc` pinning Node 22.23.1, `engine-strict=true`, and Node 22 in CI; the split verification used Node 22.23.1.

The integration items are supported by [the package README](../README.md), [the frontend README](https://github.com/fxckcomputer/LNTV/blob/main/site/README.md), and [operations guidance](../docs/OPERATIONS.md).

## Closed repository and audit work

| ID | Resolution |
|---|---|
| A-01 / Fable second pass N-03 | Complete standalone `npm run audit` passed on 2026-09-08 with seed `0x20260908`; current results and hash manifest were regenerated. See [split verification](REPOSITORY-SPLIT-2026-09-08.md). |
| Fable first pass P-03 | Contracts, CI and previously ignored audit evidence were committed and pushed in LNTV catch-up commit `f2baeba`, then extracted with their Git history. Evidence is versioned in the standalone package. |

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

P-03 is closed by the version-control checkpoint above. Accepted findings retain their original auditor ratings and their documented consequences; acceptance does not mean their behavior was removed by a code fix.

## Evidence status

- Current complete evidence: [split verification](REPOSITORY-SPLIT-2026-09-08.md), [results.json](results.json), and [SHA256SUMS](SHA256SUMS). The full run passed 127 tests, 57 two-behavioral-test mutation gates, full instrumented production coverage, and the deployment lifecycle.
- Both Fable reviews and their proof-of-concept/mutation evidence are retained. The new N-01, optional N-04 and optional N-05 remain open above; automated PASS does not close those findings.
- Historical 0.5% reports remain explicitly historical. Their original results and manifest are preserved in `history/`; source history and the catch-up commit retain the original file layout.
- The earlier M-01 numerical correction and the second review's N-02 describe the accepted extension economics. They do not change the creator's accepted design policy.

Other documented operating constraints remain in [architecture](../docs/ARCHITECTURE.md) and [operations](../docs/OPERATIONS.md): transfer restrictions and declared-price royalty limits, off-chain metadata trust, receiver compatibility, immutable settings and key-recovery limitations. They are not additional newly discovered defects or implied requests to change the design.
