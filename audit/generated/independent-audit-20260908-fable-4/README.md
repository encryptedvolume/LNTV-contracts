# Fable fourth-pass evidence — commit 1c7c1a9 (2026-09-08)

Report: `audit/INDEPENDENT-AUDIT-2026-09-08-fable-4.md`. Produced on an rsync copy; nothing under `src/`, `test/`, `script/` or `scripts/` was modified. PoC sources here are NOT part of the package test inventory; copy them into `test/poc/` of a scratch checkout to run.

| File | Content |
|---|---|
| `FableFourthPass.t.sol`, `poc-unit.log` | F4-01 seizure PoC + two controls, F4-02 fixture PoC, F4-03 rotation PoC, F4-04 event check (7 passed) |
| `FableFixCheck.t.sol`, `poc-fix-check.log` | Recommended F4-01 fix as a subclass: hardened edition resists, unpatched edition seizable (2 passed) |
| `FableFork.t.sol`, `poc-fork-mainnet.log`, `poc-fork-sepolia.log` | `configureEnforcedTrading` executed against the real registry bytecode on mainnet (block 25,933,207) and Sepolia (block 11,661,609) forks |
| `live-registry-queries.txt` | Read-only `cast` queries: code hashes, list 0 owner/whitelist/authorizers/blacklist, zone active signer, Sourcify identification of the two list-0 operators |
| `upstream-provenance.txt` | 21 vendored Limit Break / OZ 4.8.3 / PermitC files vs GitHub raw at the pinned commits (all MATCH) |
| `slither-delta.txt` | Fresh Slither 0.11.5 run vs `audit/slither-reviewed.json` (one re-keyed `costly-loop`) |
| `suite/` | Non-mutation suite logs: `01-audit-sh-run.log` (stops at static pin), `02-remaining-stages.log`, format, native-runner, audit-gate, slither (`.log` + gzipped JSON), coverage, extended tests (220 passed, seed 0x2026090850), build sizes, local deployment / e2e / trading configuration, interface check |
