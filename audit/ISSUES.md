# Current issue register

Last reconciled: 2026-09-08 after [ERC721-C/OpenSea migration](ERC721C-INTEGRATION-2026-09-08.md). The creator cancelled the running audit/mutation jobs to prioritize the integration. Historical reviews retain their original findings, measurements and source snapshots.

Open work is listed below. Integration and incomplete verification are distinguished from demonstrated contract vulnerabilities. Accepted design findings retain their original severity, including the High refund-recovery finding. There is no full-audit PASS for version 4.0.0.

## Open work

| ID | Item | Current evidence | Completion condition |
|---|---|---|---|
| APP-01 | Off-chain metadata and reveal service | The contract provides per-token URLs with an admin-updatable base. The creator-enabled, owner-requested reveal service is not implemented in this package. | Implement and verify unrevealed metadata for all 100 tokens, creator activation and authenticated owner reveal requests. |
| APP-02 | Wallet and contract integration | Frontend integration is maintained separately. This package exports interface 4.0.0; batch controls, gas-aware quantity handling and recovery integration need separate release verification and remain unchanged by this request. | Connect the page to the deployed auction and implement real single/batch bids, gas estimation, increases, ranking updates, settlement, refunds and NFT claims with transaction state handling. |
| DEP-01 | Public testnet deployment and connected rehearsal | Successful rehearsals use isolated Anvil chain 31337; no public-chain deployment is recorded for this package. | Deploy and verify the contracts on the chosen testnet, connect the frontend, and rehearse the auction, refunds, claims, payout rotation and secondary-sale flows. |
| OS-01 | Public OpenSea and compatible-market activation | ERC721-C code and local Seaport/conduit/offer tests pass. No public deployment, Studio activation or live API signature is recorded. | Follow `docs/OPENSEA.md`, verify 10% enforced earnings and correct payout, and complete live testnet listing/buy/offer checks. Other venues need their required enforcement setup. |
| AUD-40 | Complete audit of the ERC721-C release | Targeted checks pass. The creator cancelled the old long audit and all running jobs to prioritize this fix; 3.3.0 static/coverage approval does not attest the changed inheritance. | Run and record a complete non-mutation audit of the final 4.0.0 source and dependencies when requested. Mutations remain excluded unless separately authorized. |
| Fable second pass N-01 | Ranked-list back-pointer regression coverage | The invariants catch the proposed regression, but a mutant deleting the successor's `prev` update survives the unit-only mutation selection. This is a test coverage gap, not a demonstrated defect in the current contract. | Add explicit list-integrity unit checks and both pointer-update mutants to the mutation gate. |
| Fable second pass N-04 | Extra-mutant redundancy (optional) | Fifteen additional mutants outside the package campaign have only one behavioral test failure. | Strengthen independent behavioral coverage for these additional boundaries if adopted into the campaign. |
| F3-03 | Release the corrected contract on the default branch | Corrected source and matching evidence are committed/pushed through PR #1, but `main` still holds the earlier 24-hour version. | Merge the reviewed contracts PR before using the default branch for deployment. |
| F3-06 | CI dependency pinning (optional) | GitHub Actions are pinned to major tags, not immutable commit SHAs. | Pin reviewed action revisions by SHA and maintain updates. |
| F3-07 | Audit author identity hygiene (optional) | An earlier audit names the commissioning individual. | Redact to the repository identity if the creator wants that privacy change. |

The second review supplies a complete passing audit of the pre-timing-update production source on an isolated copy (N-03). A fresh complete standalone-repository run and consolidated attestation on 2026-09-08 now close A-01. Its N-02 refines the economics of the accepted uncapped extension policy. On 2026-09-08 the creator changed the initial duration to 48 hours and the rolling window to ten minutes while retaining no cumulative extension cap and the rank-based trigger; the earlier numerical examples describe the five-minute version. N-06 is addressed by `.nvmrc` pinning Node 22.23.1, `engine-strict=true`, and Node 22 in CI; the split verification used Node 22.23.1.

The integration items are supported by [the package README](../README.md), [the frontend README](https://github.com/fxckcomputer/LNTV/blob/main/site/README.md), and [operations guidance](../docs/OPERATIONS.md).

## Closed repository and audit work

| ID | Resolution |
|---|---|
| A-01 / Fable second pass N-03 | Complete standalone `npm run audit` passed on 2026-09-08 with seed `0x20260908`; current results and hash manifest were regenerated. See [split verification](REPOSITORY-SPLIT-2026-09-08.md). |
| Fable first pass P-03 | Contracts, CI and previously ignored audit evidence were committed and pushed in LNTV catch-up commit `f2baeba`, then extracted with their Git history. Evidence is versioned in the standalone package. |

| Fable second pass N-05 | Resolved in operations guidance: recommend at least one hour of hardware-wallet lead, explain that post-broadcast checks cannot roll back a mined deployment, and describe receipt inspection/replacement handling. |
| A33-01 | Resolved audit-harness inventory gap: coverage/static gates require all production sources, including TokenRescue. Ten audit-gate regression tests passed before cancellation. This does not constitute a 4.0.0 full audit. |

## Finding dispositions

IDs below refer specifically to [Fable's 2026-09-07 audit](INDEPENDENT-AUDIT-2026-09-07-fable.md). IDs in the older ERC-1155 [review](REVIEW.md) describe a different snapshot and must not be confused with these.

| ID | Original classification | Current status | Basis |
|---|---|---|---|
| M-01 | Medium, liveness/design | **Accepted by design** | Creator explicitly retains uncapped qualifying extensions and the associated active-bid commitment. [Decision](DESIGN-DECISIONS-2026-09-07.md). |
| L-01 | Low, economic/design | **Accepted by design** | Creator explicitly retains no extension when a floor increase preserves rank, including at the last moment. [Decision](DESIGN-DECISIONS-2026-09-07.md). |
| L-02 | Low, forced mint delivery | **Resolved** | Only the original winning bidder may claim or redirect its NFTs; existing and additional behavioral tests reject forced delivery, and the corresponding mutations are caught. [Named mutation failures](generated/mutation-strengthening-20260907/updated/mutations.json). |
| R-01 (2026-09-08) | Creator-requested optional refund recovery | **Accepted by design** | First successful `settledAt + 28 days` only unlocks recovery. The creator explicitly moved this timer from auction end to settlement to resolve F3-02. Refund credits and uncredited excess remain available until the current payout wallet successfully recovers the remaining auction ETH; failed recovery attempts do not close refunds. NFT claims and marketplace credits keep their prior lifecycle. [Decision and verification](SETTLEMENT-CLOCK-2026-09-08.md). |
| R-01, creator-quoted High finding | **High — payout wallet can confiscate all bidder refunds** | **Accepted by design; no corrective change requested** | Explicit creator reaffirmation of the optional recovery policy and its **28 days after first successful settlement**. Refunds remain available until recovery succeeds; success irreversibly closes all outstanding refunds. The severity is retained. This is the same authority as F3-01/R-01, not an additional accepted issue. [Decision](REFUND-RECOVERY-DESIGN-2026-09-08.md). |
| F3-02 | Low, late-settlement recovery window | **Resolved** | Recovery is now anchored to the first successful settlement. Delayed settlement preserves all 28 days, and atomic settlement/recovery fails. [Fix and evidence](SETTLEMENT-CLOCK-2026-09-08.md). |
| F3-01 | Medium, creator recovery trust | **Accepted by design (R-01)** | Only successful optional recovery closes remaining refunds; bidders need disclosure. The protected interval is now 28 days after settlement. |
| F3-04 | Informational, ten-minute extension economics | **Accepted by design (M-01)** | The third review measures roughly one extra day at 0.12–0.14 ETH committed plus gas in its rotating-tail model. This is committed capital, not a universal attack cost or guaranteed extra revenue. The window increased from five to ten minutes. |
| F3-05 | Informational, recovery event accounting | **Disclosed behavior** | Recovery includes outstanding auction proceeds, refunds and surplus under one event. The contract integration guide describes how to separate them. |
| I-01 | Informational, tie priority | **Disclosed behavior** | Earlier original bid ID wins an exact tie. A tie can change who receives #1 and pays the full winning bid. Documented in the auction rules. |
| P-01 | Low, test timing | **Resolved** | The harness pins and verifies the actual transaction's block timestamp. Four fresh lifecycle runs passed, including delayed submission. [Fix and evidence](TIMING-FIX-2026-09-07.md). |
| P-02 | Informational, mutation robustness | **Resolved** | Added 15 behavioral scenarios. All 57 mutations fail at least two behavioral tests; required scenarios and 12 runner regression tests enforce the gate. [Fix and evidence](MUTATION-STRENGTHENING-2026-09-07.md). |

P-03 is closed by the version-control checkpoint above. Accepted findings retain their original auditor ratings and their documented consequences; acceptance does not mean their behavior was removed by a code fix.

## Evidence status

- Current 4.0.0 evidence: [ERC721-C integration review](ERC721C-INTEGRATION-2026-09-08.md) and [machine-readable results](results.json). 217 bounded regression tests, a 3-campaign short invariant smoke, local deployment/trading-configuration rehearsal, formatting/build/interface checks passed. The full audit is incomplete.
- The cancelled 3.3.0 non-mutation run is preserved under `history/2026-09-08-nonmutation-cancelled/`; it must not be treated as a completed audit or as evidence for ERC721-C. Older static review and mutation files remain source-specific historical evidence.
- Prior admin, batch and settlement-clock reports retain their original verification scope. Earlier mutation campaigns are not rerun or claimed for the changed inheritance. The remaining N-01/N-04 mutation-related coverage items have not been closed by this task.
- The three accepted choices remain uncapped qualifying extensions, unchanged-rank floor increases without extension, and optional refund recovery 28 days after settlement. Their original severity and consequences are retained.

ERC721-C validator/policy and auto-approval controls are trusted creator administration, and live royalty enforcement depends on the configured registry, compatible processors and OpenSea's signer/settings. These constraints are disclosed in the [OpenSea runbook](../docs/OPENSEA.md); they are not labeled as an independently audited or newly accepted immutable-security guarantee.
