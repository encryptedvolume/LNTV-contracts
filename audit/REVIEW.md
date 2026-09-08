# Independent review of `audit/REPORT.md` and the auction contracts

> **Historical review — superseded implementation.** This review describes the original ERC-1155 system with two immutable payout wallets. The 2026-09-06 payout revision replaces it with one wallet using two-step rotation and removes primary-auction royalties (resolving I-08). It also restricts NFT claims to the winning bidder to resolve L-01. The subsequent bidding revision raises the new-bid increment to 5% and removes the two-hour extension limit. The current system uses 100 ERC-721 NFTs: 90 auctioned IDs by final rank, ten reserved IDs, tiered full-top-bid/cutoff pricing, a fixed 24-hour initial duration and off-chain metadata/reveal state. The interim on-chain owner-reveal prototype was removed. These revisions have not received the independent review recorded below. Its test counts, source hashes, line numbers, payout descriptions and closing-limit conclusions do not apply to the revised contracts. See [ISSUES.md](ISSUES.md) for current statuses and verification scope; `REPORT.md` and `results.json` are also historical snapshots. The original review text is preserved below.

**Date:** 2026-09-06. **Reviewer:** Claude (Fable 5.1), read-only; no source or evidence files were modified.
**Scope:** `src/RankedAuction.sol`, `src/AuctionEdition.sol`, `src/RoyaltyMarketplace.sol` (509 lines), `script/Deploy.s.sol`, the six test files (1,607 lines), the audit scripts, the generated evidence under `audit/`, and every claim in `REPORT.md`.

## Verdict

`REPORT.md` is accurate. Every quantitative claim reproduces from the stored evidence or from re-execution, and the qualitative claims (compiler bugs, dependency provenance, Slither dispositions, the F-01 npm-shim defect) check out against upstream sources fetched today.

Manual review of the three production contracts found **no Critical, High or Medium issue**. There is **one Low** (a third party can pre-empt a winner's mint redirect) and a set of Informational notes, most of which the package already documents as deliberate design. The remaining gaps are process-level: the package is not committed to git, and the stored evidence was assembled from more than one run rather than a single `npm run audit` pass. A full single-pass re-run performed for this review is recorded in P-02.

## How this was checked

- Read all production source, tests, scripts and docs in full.
- `shasum -a 256 -c audit/SHA256SUMS`: every entry OK. Source hashes in `results.json` and `slither-reviewed.json` match the working tree. Evidence hashes in `results.json` match `audit/generated/*`.
- Re-ran the default `forge test` profile locally: 72 passed, 0 failed (46 s).
- Re-ran `scripts/foundry.test.mjs` (2 pass), `scripts/test_audit_gates.py` (7 pass), `check_slither.py` and `check_coverage.py` against the stored outputs (both PASS).
- Diffed `lib/openzeppelin-contracts` against the upstream tarball at `fcbae5394ae8ad52d8e580a3477db99814b9d565` (5.5.0) and `lib/forge-std` against `8e40513d678f392f398620b3ef2b418648b33e89` (1.11.0): byte-identical apart from added LICENSE files.
- Fetched the current Solidity `bugs.json` and the OpenZeppelin GitHub security-advisory list and compared them with the report's disposition.
- Reproduced F-01: the upstream `@foundry-rs/forge` 1.7.1 `bin.mjs` exits 0 on an invalid option where the native binary exits 2.
- Re-ran the complete `scripts/audit.sh` on a copy of the package in a scratch directory so the stored evidence stayed untouched.

## Claim-by-claim verification

| Claim in REPORT.md | Evidence checked | Result |
|---|---|---|
| 72 Solidity tests, 0 failed, 0 skipped | `extended-tests.log`; local re-run | Verified (25 + 38 + 6 + 3 invariant) |
| 10,000 runs for each of three fuzz tests | `extended-tests.log` | Verified |
| Three invariant campaigns, 1,000 runs × 256 depth, 0 reverts | `extended-tests.log` handler tables | Verified (256,000 calls each) |
| Seed `0x20260906` | `scripts/audit.sh` line 22 | Verified by script; the log itself does not echo the seed |
| 100% line/statement/branch/function coverage on all three contracts | `coverage.log`, `lcov.info`, gate re-run | Verified. `Deploy.s.sol` is 97.5% lines and is not claimed |
| 21/21 mutations killed, compile failures excluded | `mutations.json`; `mutation_audit.py` line 53 | Verified |
| Native runner tests 2 passed; audit-gate tests 7 passed | No stored log; re-ran both | Verified |
| Slither 0.11.5, 101 detectors, 11 reviewed, 0 unreviewed | `slither.log`, `slither-reviewed.json`, gate re-run | Verified; all 11 dispositions agree with my reading |
| Local deployment: 102 bids, 100 mints, liabilities drained, resale | `local-e2e.json`, `local_e2e.py` | Verified; gas figures match exactly |
| Checker rejects wrong royalty config and inconsistent immutables | `local_e2e.py` lines 72–95 | Verified |
| Runtime/initcode sizes | `build.log` sizes table | Verified |
| Compiler 0.8.28 has no applicable known bug | upstream `bugs.json` fetched 2026-09-06 | Verified: SOL-2026-1/-2 need `viaIR`, SOL-2025-1 needs storage arrays at the slot boundary, SOL-2026-3 starts at 0.8.29 |
| OpenZeppelin 5.5.0 at `fcbae53`, forge-std 1.11.0 at `8e40513` | tarball diff | Verified, byte-identical |
| No OZ advisory affects the used modules | GitHub advisory list | Verified; the only 5.x advisory is `Bytes.lastIndexOf`, which nothing here imports |
| F-01: upstream npm shim drops native exit codes | Direct test of `node_modules/@foundry-rs/forge/bin.mjs` | Verified (shim 0, native 2) |
| F-05/F-06: immutable-copy check and single-block snapshot | `check_deployment.py` lines 12–28, 54 | Verified by reading |
| Single-pass `npm run audit` | Not claimed by the report; re-run for this review | See P-02 |

## Contract findings

### L-01 · Low · Anyone can force a winner's tokens onto the bidder's own address
`RankedAuction.claimTokens` (`src/RankedAuction.sol:220`) accepts any caller when `recipient == bid.bidder`. A third party can therefore front-run a winner's redirect (`claimTokens(ids, coldWallet)`) with `claimTokens(ids, bidder)`. Because `AuctionEdition` blocks every transfer that does not pass through `RoyaltyMarketplace`, the winner then cannot move the units to the intended address without a royalty-paying self-sale, and cannot move them at all if the bidding address is a contract that accepts ERC-1155 but cannot call `setApprovalForAll` and `list`. Cost to the griefer is gas only; no funds are at risk. `ARCHITECTURE.md` documents third-party delivery as intended, so this is a conscious trade-off rather than an oversight.
**Recommendation:** require `msg.sender == bid.bidder` (one-line change; `testThirdPartyCanDeliverOnlyToBidder` and the invariant handler's `settleAndDrain` need a `vm.prank`), or keep the behaviour and say so in the bidder guidance in `OPERATIONS.md`. Any bytecode change means re-running the audit suite and re-pinning hashes.

### I-01 · Informational · Older bid IDs win exact ties even after an increase
`src/RankedAuction.sol:305`. A bid placed first at 1 ETH can later be topped up to exactly 2 ETH and rank above a 2 ETH bid placed earlier in time. Documented. The frontend should make clear that increasing to an exact tie jumps ahead of the tied bid.

### I-02 · Informational · A tail increase raises the clearing price without extending the auction
`src/RankedAuction.sol:172` only extends on a rank change. The lowest winner can raise their bid in the final seconds, lifting everyone's clearing price with no extension. Documented as reference-compatible. Since bids cannot be withdrawn, extension never protected against price rises anyway; exposure equals ordinary shill bidding.

### I-03 · Informational · Under-subscription cliff and shill economics
With 99 or fewer active bids everyone pays the reserve; with 100 everyone pays the lowest winning bid. A treasury-controlled wallet can fill the last slot for the cost of the creator's royalty share on its own unit plus gas, lifting revenue from 99 × reserve to 100 × lowest bid. Inherent to the Transient Labs design and disclosed as "Sybil participation". Set the reserve as the real floor price and tell bidders there is no shill protection.

### I-04 · Informational · Insertion cost at capacity
Every near-floor bid at capacity walks all 100 nodes with two cold storage reads each, because `amount` and `next` sit in different slots of a five-slot `Bid` struct. Observed 636,625 gas, which at 30 gwei is about 0.019 ETH, roughly twice the example 0.01 ETH reserve. Packing `amount`, `prev` and `next` into one slot with `uint64` IDs would roughly halve it. Optional; the bound is safe and tested.

### I-05 · Informational · No `name()`, `symbol()` or `contractURI()`
`AuctionEdition` exposes only the ERC-1155 `uri`. Block explorers will show an unnamed ERC-1155. Constant view functions cost no storage if branding matters.

### I-06 · Informational · Edition and marketplace can be deployed standalone
Both constructors are public (the tests rely on this). Look-alike contracts are trivial to deploy. Publish only the auction address and have the frontend derive edition and marketplace from `auction.edition()` and `edition.marketplace()`.

### I-07 · Informational · EIP-7702 delegated wallets
A bidder or buyer whose EOA carries delegated code without `onERC1155Received` cannot receive mints or purchases directly and must redirect. The frontend should simulate `claimTokens` and `buy` before sending.

### I-08 · Informational · The royalty rate doubles as the creator's primary-sale share
`ROYALTY_BPS=750` sends 7.5% of primary revenue to `ROYALTY_RECIPIENT`, not to the treasury. Documented in `OPERATIONS.md`. Confirm this split is intended before writing `.env`.

### I-09 · Informational · Dependency freshness
OpenZeppelin 5.5.0 is pinned; 5.6.1 is current on npm. No advisory touches the modules used. Foundry 1.7.1 is current. No action.

## Report and process gaps

### P-01 · The package is not committed
`auction/` and `.github/` are untracked in the LNTV repository. The report has no commit hash of its own; the revision in `NOTICE.md` is the upstream Transient Labs commit. The hash gates pin files, not a tree. Commit before relying on the report, and keep `audit/` outputs in the same commit as the source they describe.

### P-02 · Stored evidence came from more than one run
File timestamps (`mutations.json` 15:41, `slither.final.json` 15:41, `extended-tests.log` 15:49, `coverage.log` 15:55, `build.log` 15:55, `local-e2e.json` 15:57) do not follow the single-pass order of `scripts/audit.sh` (Slither → coverage → extended tests → mutations → build → e2e). All evidence postdates the last source edit (`RankedAuction.sol` 15:38:39) and every hash verifies, so the evidence is consistent; it is just not a single-pass attestation.
**Re-run for this review:** `scripts/audit.sh` executed once, uninterrupted, on a copy of the package (2026-09-06 16:11–16:21 WITA, exit 0). Every gate passed: format check, 2 runner tests, 7 gate tests, Slither 11/0, coverage 100%/100%/100%, 72/72 tests with 10,000 fuzz runs and three 1,000 × 256 invariant campaigns at seed `0x20260906` with 0 reverts, 21/21 mutants killed, sizes, and the Anvil deployment rehearsal with gas figures identical to `results.json` (4,042,240 / 636,625 / 115,853 / 1,070,363 / 144,584). The single-pass result therefore matches the stored evidence.

### P-03 · Runner and gate tests leave no log
`foundry.test.mjs` and `test_audit_gates.py` run inside `audit.sh` but write nothing to `audit/generated/`. Re-ran both: pass. Tee their output alongside the other logs.

### P-04 · Mutation testing is 21 hand-picked mutants
Exact string replacements, run with `--fuzz-runs 16` and no invariants. It proves those specific regressions are caught; it is not a mutation score. Consider a systematic tool such as Gambit before mainnet if more assurance is wanted.

### P-05 · Invariant campaigns never move time
Neither handler warps the clock, so extension, the two-hour cap, listing expiry and mid-campaign settlement rest on unit tests only, and post-settlement claim/credit ordering only runs in the fixed order of `afterInvariant`. Unit coverage of those paths is thorough; this is a note on what the 768,000 handler calls do and do not exercise.

### P-06 · Generated evidence is gitignored
`audit/generated/` will not be in the repo, so the evidence hashed in `results.json` exists only locally and as a 30-day CI artifact. Archive a copy with the commit.

### P-07 · `SHA256SUMS` omissions
`audit/slither-reviewed.json`, `docs/`, `README.md` and `NOTICE.md` are not listed. Minor; the Slither gate pins source hashes independently.

## Before mainnet

1. Decide L-01 (bidder-only claims or document the current behaviour).
2. Commit `auction/` and `.github/`, run `npm run audit` once from clean, and commit `audit/` in the same commit.
3. Confirm `ROYALTY_BPS` as the primary split, the reserve as the real floor, and an immutable content-addressed `METADATA_URI`.
4. Sepolia rehearsal with `scripts/check_deployment.py` against the real config.
5. The report's own closing advice stands: this is a self-review; funds at risk are 100 × clearing price, so get an independent audit sized to that.
