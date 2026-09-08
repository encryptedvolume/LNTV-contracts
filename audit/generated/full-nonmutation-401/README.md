# Complete 4.0.1 non-mutation evidence

Base: `96b473b00922262ccd8209563f2fda0962550712`, reviewed 2026-09-08.
The four production sources and exported interface are unchanged from that base.
The committed audit changes include stricter deployment/policy checks and three
regression tests. Exact source hashes and all measurements are in
[results](../../results.json); reasoning is in the
[manual report](../../MANUAL-REVIEW-2026-09-08.md).

## Authoritative runs

| Evidence | Scope/result |
|---|---|
| `pipeline.log` | `AUDIT_FUZZ_SEED=0x2026090842 npm run audit:nonmutation`, exit 0, 895 seconds |
| `extended-tests.log` | 232 tests pass; 9 × 10,000 fuzz cases and 3 × 1,000 × 256 invariant actions; no failures/skips |
| `coverage.log`, `lcov.info` | All four production files: 100% instrumented lines, branches and functions; edition statements 98/99 |
| `coverage-debug.log` | Separate 32-run debug pass identifies only the interface cast at edition line 155 as an unhit statement; enclosing assignment and following calls execute |
| `slither.final.json`, `slither.log` | Exact 29 reviewed findings, no new IDs or source drift |
| `audit-gate-tests.log`, `trading-policy-tests.log`, `native-runner-tests.log` | 10 + 10 Python checks and 2 Node checks pass |
| `focused.log`, `pre-fix-deployment.log` | Three new regressions plus six deployment tests pass; wrong-royalty regression fails on the old script |
| `local-e2e.json`, deployment/configuration logs | Actual deployment scripts, batch/auction/claim/royalty/admin/rotation lifecycle; zero ending liabilities |
| `policy-check-rehearsal.json`, `.py` | Reject six deliberately poisoned local policies; accept correct default after rotation |
| `fork-ethereum.log`, `fork-sepolia.log`, `fork-results.json` | Named registry-policy tests pass at Ethereum 25933485 and Sepolia 11661874 |
| `LivePolicyAudit.t.sol` | Executed fork test, adapted from Fable's fourth-pass check; header attribution retained |
| `payment-processor-review.json` | Two processors and four trade-module verified-source manifests; runtime matches at pinned Ethereum block |
| `dependency-integrity.json` | 21 ERC721-C/OZ4/PermitC source files match their pinned manifests |
| `build.log`, `interface-check.log`, `final-interface-check.log` | Optimized build/size and unchanged interface 4.0.1; final check follows debug instrumentation |

The full pipeline generated top-level logs; a wrapper copied the fresh logs here
and restored historical top-level files and root `lcov.info`. Do not use those
restored historical files as current evidence. Prior metadata and its original
manifest are in `../../history/2026-09-08-pre-full-nonmutation-401/`.

Initial fork attempts with `no-tests-initial`, `symlink-compile-failure` and
`stack-compile-failure` filenames are retained for transparency, not counted as
successful checks. Final results require `[PASS] testLiveRegistryConfiguration`
in addition to exit zero. Test sources/dependencies were copied into a temporary
fork project so Solidity type identities resolve consistently. The native binary
was invoked with explicit `--root`; the npm wrapper's own root must not silently
select the original test inventory.

## Reproduction

Install the pinned Node/Python dependencies as described in the repository README.
From the repository root, the complete requested gate is:

```bash
AUDIT_FUZZ_SEED=0x2026090842 npm run audit:nonmutation
```

This writes fresh logs to top-level `audit/generated/` and root `lcov.info`.
Archive those files first if retaining this checkout's historical evidence.
The command excludes both source mutation campaigns and mutation-runner tests.
Additional real-policy checker rehearsal:

```bash
.venv/bin/python audit/generated/full-nonmutation-401/policy-check-rehearsal.py
```

For the pinned fork test, create a temporary project and copy `src`, `lib`,
`script` and `foundry.toml` into it (real copies, not symlinked Solidity sources).
Create its `test` directory and copy `LivePolicyAudit.t.sol` there. Obtain the
native Forge binary with `node scripts/foundry.mjs forge --print-path`, then run:

```bash
# Set FORGE_NATIVE and FORK_PROJECT to those local paths.
FORK_RPC=https://ethereum-rpc.publicnode.com FORK_BLOCK=25933485 \
  "$FORGE_NATIVE" test --root "$FORK_PROJECT" --match-contract LivePolicyAuditTest -vv
FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com FORK_BLOCK=11661874 \
  "$FORGE_NATIVE" test --root "$FORK_PROJECT" --match-contract LivePolicyAuditTest -vv
```

Both commands must print the named passing test. Public RPC availability and
historical-state retention can affect reproducibility; stored block and code
hashes identify the states reviewed. The fork test and policy rehearsal use only
local transactions. Impersonation in the latter deliberately corrupts a local
fixture to test the checker and does not demonstrate a public attack path.

## Limits

No live OpenSea API signature, Studio activation or public-chain deployment was
performed. The PaymentProcessor review is focused on royalty/payment paths, not
a complete audit of that external protocol. Its creator royalty bounty must be
zero for the full quoted amount to reach the payout wallet; an exact 1000-bps
signed cap may reject the one-unit difference caused by upward rounding.

Large aggregate Forge gas in the list-integrity regression includes repeated
assertions over a whole book; it is not transaction gas. `local-e2e.json` records
actual transaction gas separately. No mutation campaign was run, and historical
mutation files do not attest this release. See the issue register for remaining
release checks and accepted design risks.
