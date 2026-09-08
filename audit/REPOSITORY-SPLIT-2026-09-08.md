# Standalone repository verification — 2026-09-08

The complete audit passed in the extracted contracts repository using Node
22.23.1 and `AUDIT_FUZZ_SEED=0x20260908 npm run audit`. All three production
source hashes match the pre-split checkpoint exactly. No Solidity code, test
logic, auction policy or vendored dependency changed during extraction.

| Check | Result |
|---|---|
| Extended Solidity tests | 127 passed, 0 failed, 0 skipped |
| Stateless fuzzing | Four tests, 10,000 runs each |
| Stateful invariants | Three campaigns, 1,000 runs × 256 calls each; 768,000 calls and zero unexpected reverts |
| Instrumented production coverage | 100% lines, statements, branches and functions |
| Mutation campaign | 57/57 killed by at least two behavioral tests; clean 124-test baseline |
| Tool regression tests | 2 native-runner + 7 audit-gate + 12 mutation-runner tests passed |
| Slither | 14 reviewed findings, no unreviewed findings or source drift |
| Temporary Anvil lifecycle | 92 bids, 100 NFT mints, 30 late increases, 33 exact transaction timestamp checks, two secondary sales, payout rotation; zero final auction/market liabilities |
| Frontend interface | Generated ABIs and address exports match a fresh optimized build |

The log is [split-audit.log](generated/split-audit.log); detailed current values
are in [results.json](results.json). [SHA256SUMS](SHA256SUMS) pins the committed
source, tests, tooling, documentation, interface and evidence at this snapshot.
Run `sha256sum -c audit/SHA256SUMS` from the repository root to verify it. Future
local audit runs may change generated logs and require a new attestation.

This closes A-01 and confirms the package works outside the frontend tree.
P-03 is closed by the pushed catch-up commit and preserved extraction history.
Fable's second-pass N-01 test gap and optional N-04/N-05 findings remain open;
accepted extension economics remain unchanged. This run does not constitute a
new independent manual audit, public deployment, or end-to-end website integration.

The earlier 0.5% reports retain their original meaning. Their original result
snapshot and manifest are archived under `history/`; Git history retains the
pre-extraction paths. See [migration provenance](../docs/REPOSITORY-SPLIT.md).
