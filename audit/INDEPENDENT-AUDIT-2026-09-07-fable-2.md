# Independent security audit, second pass — RankedAuction / AuctionEdition / RoyaltyMarketplace

**Date:** 2026-09-07 (second independent review, after the 2.5% increase, timing fix and mutation strengthening).
**Reviewer:** Claude (Fable 5.1), read-only against the package; all execution happened on isolated copies under the session scratchpad so `audit/generated/` and `lcov.info` in the package were not touched.
**Scope:** `src/RankedAuction.sol`, `src/AuctionEdition.sol`, `src/RoyaltyMarketplace.sol`, `script/Deploy.s.sol`, every file under `test/` and `scripts/`, `foundry.toml`, the CI workflow `.github/workflows/auction.yml`, the documented requirements in `README.md`, `docs/ARCHITECTURE.md`, `docs/OPERATIONS.md`, `.env.example`, and every claim in `audit/REPORT.md`, `audit/REAUDIT-2026-09-07.md`, `audit/INDEPENDENT-AUDIT-2026-09-07-fable.md`, `audit/INCREASE-UPDATE-2026-09-07.md`, `audit/TIMING-FIX-2026-09-07.md`, `audit/MUTATION-STRENGTHENING-2026-09-07.md` and `audit/ISSUES.md`. This is a self-directed independent review, not a funded third-party audit.

**Pinned source reviewed** (working tree at the time of review; matches `audit/slither-reviewed.json`, the mutation-strengthening and timing-fix evidence, and differs from the historical `results.json`/`SHA256SUMS` snapshot only in `RankedAuction.sol`):

```
src/AuctionEdition.sol      fe163f6db23b7f0f5ab61a7382dd09de0607f3c7264953dafe13977c1712cab9
src/RankedAuction.sol       45371987e5fd027bfbae2cc0f79c0f0df4c4934a938e8205f65dfc31d9a325a7
src/RoyaltyMarketplace.sol  ba2d6c869ddaf9f589f88d673f00f9bbecb75dbc73fea10f26de64bb22b6eb85
script/Deploy.s.sol         5e9a984bbbe826511764beefa4eb90dfa22280227c0c04aecd01e8afc27d60f6
```

Hashes of every test and script file reviewed are in `generated/independent-audit-20260907-fable-2/reviewed-hashes.txt`. Note that other audit documents in `audit/` were being edited by another process during this review; the contract, test and script hashes above were stable throughout.

## Verdict

The three contracts, as pinned above, contain **no Critical, High or Medium correctness defect** that I could find by manual review, by re-deriving the accounting invariants, by a fresh-seed run of the complete audit suite, by five new proof-of-concept tests, or by 41 additional mutants that are not in the package's own list. Access control, ETH conservation, mint/supply accounting, ranked-list ordering, tiered settlement and transfer/royalty enforcement all hold. Every documented requirement I could map to code is implemented as documented. The earlier L-02 fix (bidder-only claims) is still in place and still killed by mutation.

What is new in this pass:

| ID | Severity | Title | Status |
|---|---|---|---|
| N-01 | Low (test robustness) | Ranked-list back-pointer integrity is protected only by the invariant campaign, which the mutation gate excludes; a `_unlink` regression survives all 124 unit tests and the 57-mutant gate | Open — recommended test additions below |
| N-02 | Informational (economics; refines accepted M-01) | With the 2.5% increase, a rotating set of *k* tail bids still holds the auction open for a day for roughly 0.2 ETH of commitment plus ~35M gas; `INCREASE-UPDATE.md`'s "raises the capital required" is true but small | Accepted design (creator decision 2026-09-07); numbers corrected here |
| N-03 | Process (should close before launch) | The top-level attestation is stale for the current source: `SHA256SUMS` fails on 15 files, `results.json` pins the pre-2.5% hash, and no complete `npm run audit` had run on the current tree (A-01). A complete run performed for this review on an isolated copy is recorded below | Evidence provided; A-01 and P-03 remain for the owner to close |
| N-04 | Informational (test robustness) | 15 of the 38 extra mutants killed are caught by exactly one behavioral test | Open — optional |
| N-05 | Informational (deployment) | `Deploy.run()` asserts contract bindings after `vm.stopBroadcast()`, and the 10-minute lead-time floor is tight for a hardware-wallet mainnet broadcast | Open — optional |
| N-06 | Informational (environment) | The machine's default Node is 18.18.0 while the package declares Node ≥ 22 and nothing enforces it | Note only |

Carried forward unchanged: **M-01** and **L-01** (accepted by design), **I-01** (disclosed tie priority, re-proven in PoC-2), **P-03** (package and CI still untracked in git: `git ls-files auction .github` returns nothing).

---

## What I reproduced

All runs used the native Foundry 1.7.1 binary from `node_modules`, Node 22.23.1 on PATH, Slither 0.11.5 from `.venv`, and a fresh fuzz seed `0xFAB1E0907` that no prior run used.

| Check | How | Result |
|---|---|---|
| Complete audit runner on the current source | `AUDIT_FUZZ_SEED=0xFAB1E0907 bash scripts/audit.sh` on an isolated copy | **PASS, exit 0**, every gate; log in `generated/independent-audit-20260907-fable-2/audit-run.log`, runner output in `generated/independent-audit-20260907-fable-2/run/` |
| Format, native-runner (2), audit-gate (7), mutation-runner (12) regression tests | inside the runner | all pass |
| Slither gate | fresh `slither .` + `check_slither.py` | 14 reviewed findings, no new or missing finding, no source drift (the reviewed hash is the current 2.5% source) |
| Production coverage | fresh `forge coverage` | 100% lines / statements / branches / functions on all three contracts |
| Extended tests (audit profile) | 10,000 fuzz runs × 4 tests, three invariant campaigns 1,000 × 256 | **127 passed, 0 failed, 0 skipped**; 4 fuzz tests × 10,000 runs; 3 campaigns × (1,000 runs × 256 calls) = 768,000 handler calls, **0 reverts**; 114,239 time-advance handler calls |
| Package mutation campaign | `mutation_audit.py`, 57 mutants, two-behavioral-failure gate | **57/57 killed**, each by ≥ 2 behavioral tests with the required scenarios present; clean 124-test baseline |
| Build sizes | `forge build --sizes` | unchanged: auction 9,706 / 23,107, edition 6,129 / 11,952, marketplace 4,507 / 4,654 bytes (runtime / initcode) |
| Local Anvil lifecycle rehearsal | `local_e2e.py` (fixed timing harness) | **PASS**: 92 bids, 100 mints, 30 late rank-changing increases, 8,970 s extension, 33 exact-timestamp assertions, `increaseBps` 250, gas identical to `results.json` (deployment 4,826,220; worst bid 590,731; settle 772,183; 88-NFT claim 3,303,806; sale 182,611) |
| Stored follow-up evidence | `mutation-strengthening-20260907/`, `timing-fix-20260907/` | 57/57 mutants with ≥ 2 behavioral failures, 124-test baseline, input hashes match the current source; 4/4 lifecycle rehearsals with 33 exact timestamp checks each; harness hash matches `scripts/local_e2e.py` |
| Historical manifest | `shasum -a 256 -c audit/SHA256SUMS` | 415/430 OK; 15 FAILED (see N-03). All 381 `lib/` entries verify, so the vendored OpenZeppelin 5.5.0 and forge-std 1.11.0 trees are unchanged from the byte-identical upstream comparison recorded on 2026-09-06 |
| Extra mutants (not in the package list) | own runner, 41 mutants, same command line as the package gate | 38 killed; 1 survived (N-01); 1 equivalent; 1 malformed (mine) |
| New proof-of-concept tests | `AuditFable2.t.sol`, 7 tests | 7 pass on the current source; PoC-4 fails on the N-01 mutant |
| Solidity known-bugs list | upstream `bugs.json` fetched today | No applicable entry for 0.8.28 with the legacy pipeline: SOL-2026-1/-2 need `viaIR`, SOL-2025-1 needs arrays straddling the storage end, SOL-2026-3 is introduced in 0.8.29 |
| OpenZeppelin advisories | upstream advisory list fetched today | Nothing touches ERC721, ReentrancyGuard, Math, Strings or IERC2981 in 5.x; the only 5.x advisory is `Bytes.lastIndexOf`, which nothing here imports |

### Hand re-derivation of the accounting

- Before settlement `escrow = Σ active amounts`; every displacement moves exactly the displaced amount from `escrow` to `refunds[bidder]`/`totalRefunds` (`src/RankedAuction.sol:174-185`). A new bid at capacity must exceed the floor by at least one wei (`:155-159`, ceiling rounding), so it is never itself the displaced tail.
- At settlement every non-head winner's amount is ≥ `clearingPrice` (it is ≥ the tail when full and ≥ reserve otherwise), so `gross = head + clearing·(n−1) ≤ escrow` (`:212-215`) and each `amount − winningBidCost(id)` in `creditRefunds` (`:243`) is non-negative. `n = 0` and `n = 1` are explicit.
- `liabilities() = escrow + totalRefunds + pendingProceeds` is debited before every external call and every debit reverts on failure (`:301-315`, `:397-402`).
- Market: `royalty = ceil(price·bps/10000) ≤ price` for `bps ≤ 10000`, so `credits += price − royalty` cannot underflow (`src/RoyaltyMarketplace.sol:86-91`); `totalCredits = Σ credits + pendingRoyalties` is maintained by every path.
- Transfer enforcement: the only mint path is `AuctionEdition.mint` (auction-only, `src/AuctionEdition.sol:51-60`); every other `_update` with an existing owner requires `msg.sender == marketplace` (`:93-98`); `transferFrom` on a nonexistent ID reverts inside OpenZeppelin's authorization check before any state change (`lib/openzeppelin-contracts/token/ERC721/ERC721.sol:115-125`, `:179-186`). Approvals other than to the marketplace revert (`:83-91`); revocation stays possible.
- Reentrancy: every state-changing auction and market entry point is `nonReentrant`; a mint receiver can reach the *other* contract's guard only, which the cross-contract tests exercise, and no auction state is read after the external mint call.

## Requirements conformance

Each rule in the README table and the architecture/operations documents was mapped to code. All conform. Representative mapping:

| Documented rule | Implementation | Verified by |
|---|---|---|
| 100 lifetime mints, 90 auctioned (IDs 1–90 by final rank) + 10 reserved (91–100) | `SUPPLY`, `RESERVED_SUPPLY`, `MAX_SUPPLY`; `settle()` rank walk `:217-221`; `claimUnsold` `:276`; `claimReserved` `:291` | TieredAllocation, Metadata, e2e |
| Rank #1 pays full bid, others pay 90th winning bid when full else reserve; sole winner pays full | `clearingPrice` `:212`, `gross` `:213`, `winningBidCost` `:226-230` | TieredAllocation, fuzz, invariants |
| Reserve below capacity; floor + 5% rounded up at capacity; increase ≥ 2.5% rounded up | `minimumBid` `:155-159`, `increaseBid` `:197`, `minimumIncrement` `:349-351` | RankedAuction, MutationBehavior, invariants (independent model) |
| Ties favour the earlier bid ID, including after increases | `_insert` `:360` | RankedAuction, PoC-2 |
| 24 h initial window `[start, start+24h)`; new bids and rank-changing increases in the final 5 min reset to 5 min; uncapped; uint256 deadline | constructor `:110-111`, `phase` `:146-151`, `_extend` `:384-388`, `:186`, `:203` | RankedAuction, MutationBehavior, PoC-5 |
| Settlement by anyone at/after end; no callbacks; single use | `settle` `:208-223` | RankedAuction, e2e |
| Only the winning bidder claims and picks the recipient; refunds independent and permissionless to credit; withdrawals pull-only | `claimTokens` `:254-269`, `creditRefunds` `:234-250`, `withdrawRefund` `:301-307` | RankedAuction, CrossContractAudit |
| Payout wallet two-step rotation; system addresses and zero rejected; rotation moves only business revenue and unclaimed inventory | `:118-144`, `:390-395`; royalty recipient read-through `AuctionEdition.sol:67-69` | PayoutWallet, invariants |
| Strict royalty transfers: direct transfers and foreign approvals blocked; marketplace-only; every transfer bumps the nonce and invalidates prior listings | `AuctionEdition.sol:83-98`; `RoyaltyMarketplace.sol:58-95` | RoyaltyMarketplace, MarketInvariant |
| Royalties round up, never zero on a positive sale, 1–10,000 bps, no primary royalty | `AuctionEdition.sol:72-77`, `:37-42`; `settle` credits full `gross` | RoyaltyMarketplace, PayoutWallet |
| `tokenURI = base + id + ".json"`, base must end with `/`, requires a minted ID, no on-chain reveal | `AuctionEdition.sol:43`, `:62-65` | Metadata, e2e |
| Deployment validation list in OPERATIONS.md (chain match, supported chain, ≥10 min lead, bounds before narrowing, non-zero wallet, metadata slash, non-empty labels) | `script/Deploy.s.sol:35-60` | Deployment tests, e2e broadcast |
| No proxy, pause, cancel, rescue or deployer role | no such code path exists; deployer address is never stored | manual |

Documentation nits: `OPERATIONS.md` does not mention that an EIP-7702-delegated EOA without `onERC721Received` must redirect claims and purchases (the contracts handle it correctly; only the guidance is silent). Nothing else in the current documents contradicts the code; the historical banners added to `REPORT.md`, `REAUDIT-2026-09-07.md` and `REVIEW.md` on 2026-09-07 are accurate.

---

## N-01 · Low (test robustness) · Back-pointer corruption in `_unlink` is invisible to the unit suite and the mutation gate

**Where:** `src/RankedAuction.sol:373-382`, specifically line 377:

```solidity
if (bid.next == 0) tail = bid.prev;
else bids[bid.next].prev = bid.prev;
```

**Issue.** The unit tests assert `head`, `tail`, `activeCount`, `rankedBids` (which follows `next` only) and a few `next` pointers, but never walk the list checking that every node's `prev` matches its predecessor. The `prev` links are only checked by `AuctionHandler.assertState()` in the invariant campaign, and `scripts/mutation_audit.py` runs with `--no-match-contract '.*Invariant.*'`. A regression that drops the successor's back-pointer update therefore passes every one of the 124 non-invariant tests and would pass the 57-mutant gate. The corruption is real: after such a regression, the *next* `increaseBid` on the affected successor unlinks it using a stale `prev`, writes `next` on the wrong node, and the ranked list loses members (a subsequent traversal from `head` stops early), which would mis-price settlement and strand winners.

**Proof.** Extra mutant #17 (`else bids[bid.next].prev = bid.prev;` → `else { }`):

```
17 SURVIVED      RA _unlink drops successor prev (0 behavioral)   ← package suite, 124 tests, fuzz 16, seed 0xFAB1E0907
[PASS] testIncreaseMaintainsSizeAndOriginalTiePriority()         ← chained increases, pointers already stale
[FAIL: successor prev updated on unlink: 2 != 1] testPoC4_PointerIntegrityAfterMiddleUnlinkAndReinsert()
[FAIL: assertion failed: 3 != 2] invariant_matchesIndependentRankingAndConservesEveryWei() (runs: 0, calls: 0)
```

The same mutant applied to `_insert` (`else bids[current].prev = id;` → `else { }`, extra mutant #18) *is* caught, by four tests, because insertion pointer errors surface immediately through `bids(id).prev` assertions.

**Recommendation.**
1. Add a chain-integrity helper to `TestBase` (walk from `head`: each node's `prev` equals the previous node, amounts non-increasing with ID tie order, count equals `activeCount`, last node equals `tail`) and call it at the end of every ranking/increase/displacement unit test. `testPoC4_PointerIntegrityAfterMiddleUnlinkAndReinsert` in `generated/independent-audit-20260907-fable-2/AuditFable2.t.sol` is a minimal version.
2. Add the `_unlink` back-pointer mutant (and its `_insert` twin) to `MUTANTS` in `scripts/mutation_audit.py`, with the helper test in `REQUIRED_BEHAVIORS`.
3. Optionally run one short invariant campaign (for example 16 × 64) per mutant in the gate; the corruption shows within the first sequence.

None of this changes bytecode.

## N-02 · Informational (economics; refines accepted M-01) · What the 2.5% increase actually buys

**Where:** `INCREASE_BPS` `src/RankedAuction.sol:46`, tie rule `:360`, extension trigger `:203`, `_extend` `:384-388`.

**Issue.** `INCREASE-UPDATE-2026-09-07.md` states that raising the increase to 2.5% "increases the capital required for repeated extensions", and `ISSUES.md` notes that the earlier 0.5% figures are not current estimates. Measured against the current source, the increase in cost is modest, for two reasons:

- The stall does not need one bid to grow 2.5% per window. Because an exact tie resolves in favour of the earlier ID, the lowest of *k* co-owned tail bids can be raised by exactly its own 2.5% minimum, tie the next one, and change rank, which extends. Each window costs 2.5% of **one** bid, so total commitment grows by about `1.025^(windows / k)`.
- The griefer's bids are tail bids, so they win; the "capital" becomes payment for *k* NFTs at a clearing price the griefer itself sets, and it lifts every regular winner's price to that level.

**Proof** (`testPoC1_*`, all pass on the current source; reserve 0.01 ETH, honest bids 1 ETH):

| Rotating tail bids *k* | Windows | Extra time held open | Griefer wei added | Final commitment | Clearing price at close | Griefer gas |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 24 (2 h) | 7,176 s | 0.0069 ETH | 0.027 ETH | 0.0134 ETH | 3.06 M |
| 2 | 288 (24 h) | 86,112 s | 0.680 ETH | 0.700 ETH | 0.350 ETH | 36.7 M |
| 10 | 288 (24 h) | 86,112 s | 0.104 ETH | 0.204 ETH | 0.0200 ETH | 35.0 M |

With ten rotating bids, one day of stalling costs about 0.2 ETH of commitment (which then buys ten NFTs at twice the reserve) plus roughly 35M gas (≈ 0.35 ETH at 10 gwei), while 80 ETH of honest escrow stays locked. Under the previous 0.5% rule the same day cost about 0.02 ETH of commitment; the 2.5% rule therefore raised the capital component by roughly ten times, from negligible to small.

**Assessment.** The creator accepted uncapped extensions and last-moment repricing on 2026-09-07 with full knowledge of the mechanism, so this is not a request to change the design. It is a correction of the numbers the decision should be read against, and a note that the tie rule, not only the percentage, sets the floor cost. If the decision is ever revisited, the cheapest bytecode-level mitigation remains the reference contract's total-extension cap; a cheaper documentation-level mitigation is to state the ~0.2 ETH/day figure to bidders.

## N-03 · Process · Attestation is stale for the current source; a complete run on the current tree is recorded here

**Where:** `audit/SHA256SUMS`, `audit/results.json` (`sourceSha256["src/RankedAuction.sol"] = de04bd…`), `audit/REPORT.md` results table.

**Issue.** Fifteen manifest entries fail (`README.md`, both docs, `scripts/audit.sh`, `check_deployment.py`, `local_e2e.py`, `mutation_audit.py`, `slither-reviewed.json`, `src/RankedAuction.sol`, `test/AuctionInvariant.t.sol`, `test/RankedAuction.t.sol` and four `site/` files). `results.json` and the results table in `REPORT.md` describe the 0.5% source. The follow-up notes are honest about this, and `ISSUES.md` (added during this review) tracks it as A-01, but until it is closed anyone reading `REPORT.md` for numbers reads numbers for a different contract.

**What this review adds.** A complete `scripts/audit.sh` run on an isolated copy of the current tree with a never-used seed: **exit 0 with every gate passing** (format; 2 + 7 + 12 tool regression tests; Slither 14 reviewed / 0 unreviewed; 100% production coverage; 127/127 tests with 10,000-run fuzzing and 768,000 invariant calls at seed `0xFAB1E0907`; 57/57 mutants; bytecode sizes; the complete Anvil rehearsal). The full log, the runner's `audit/generated/` output, my extra-mutant results and the PoC test file are retained under `audit/generated/independent-audit-20260907-fable-2/`. That directory is git-ignored like the rest of `generated/`, so it has the same durability problem as P-03.

**Recommendation.** Close A-01 by running `npm run audit` in place (or adopting the evidence above), regenerating `results.json` and `SHA256SUMS` for the current hashes, and committing `auction/`, `.github/` and the evidence together (P-03). Until then, treat `REPORT.md` numbers as historical.

## N-04 · Informational · Single-test kills among the extra mutants

Of the 38 extra mutants killed, 15 are caught by exactly one behavioral test: `phase()` end boundary (`<` → `<=`), always-extend-on-increase, anyone-can-increase, `_send` to the auction itself, `mint` upper bound 101, royalty for out-of-range IDs, blocked revocation of foreign operators, `tokenURI` for unminted IDs, `buy`/`list` expiry inclusive, `buy` without the approval pre-check, double cancel, edition as purchase recipient, overpayment accepted, token 101 listable. The package's own P-02 work fixed this pattern for its 57 mutants; the same fragility exists for boundary conditions outside that list. Optional: add a second assertion for each, or add these mutants to the gate. Full table in `generated/independent-audit-20260907-fable-2/extra-mutants.json`.

## N-05 · Informational · Deployment script

`script/Deploy.s.sol` is sound: every numeric bound is checked before narrowing (`:38-41`), chain and lead time are checked (`:36-38`), the metadata slash and labels are checked (`:52-59`), and the constructor re-validates start time and rejects system addresses as payout wallet (`src/RankedAuction.sol:106`, `:390-395`). Two notes:

- The binding assertions at `:76-79` execute after `vm.stopBroadcast()`. If they ever failed the deployment would already be on chain and only the script's exit status would signal it. They cannot fail for this constructor, so this is cosmetic; moving them before broadcast is not possible, so either leave as is or document that a failed post-check still means a live deployment.
- The 10-minute lead-time floor (`:38`) is enforced at simulation time. A hardware-wallet mainnet broadcast that takes longer than the lead time reverts in the constructor (`startTime <= block.timestamp`), costing gas but deploying nothing. Recommend at least one hour of lead time in `.env` guidance.

`scripts/check_deployment.py` and `scripts/local_e2e.py` were re-read in full; the immutable-copy consistency check, single-block snapshot and the new receipt-timestamp assertion are correct. The CI workflow pins Node 22 and Python 3.12, grants `contents: read` only, and uploads evidence for 30 days; it has not been run on a hosted runner (the package is not committed).

## N-06 · Informational · Environment

`package.json` declares `"node": ">=22"`, but the machine's first `node` on PATH is 18.18.0 and nothing sets `engine-strict`. The scripts happen to work on 18; this review used 22.23.1 to match CI. Consider `.nvmrc` or `engine-strict=true` in `.npmrc` so the audit runner cannot silently run on an unsupported Node.

---

## Extra-mutant challenge (summary)

Same command line as the package gate (`--no-match-contract '.*Invariant.*' --fuzz-runs 16`, seed `0xFAB1E0907`), package tests only, baseline 124 passing.

| # | Mutant | Result |
|---|---|---|
| 1 | `_extend` boundary `>=` → `>` | Equivalent: at exactly 300 s remaining the "extension" writes the same `endTime` and only emits a spurious event |
| 2 | `increaseBid` always extends | Killed (1) |
| 3–7 | `createBid` minimum, `settle`, `phase`, unsold and reserved quantity boundaries | Killed (24 / 80 / 1 / 34 / 35) |
| 8–9 | `creditRefunds` non-idempotent; `withdrawRefund` keeps `totalRefunds` | Killed (4 / 7) |
| 10–11 | auction address allowed as payout wallet; anyone accepts a pending wallet | Killed (2 / 2) |
| 12 | capacity off-by-one in `minimumBid` | Killed (4) |
| 13–16 | anyone can increase another bid; `tokensClaimed` dropped; `_send` to self allowed; `pendingProceeds` not zeroed | Killed (1 / 2 / 1 / 8) |
| 17 | **`_unlink` drops successor `prev`** | **Survived (N-01)** |
| 18 | `_insert` drops successor `prev` | Killed (4) |
| 19–22 | displacement escrow not debited; gross overcharges one clearing; 4-minute window; last rank unassigned | Killed (2 / 45 / 5 / 17) |
| 23 | (malformed mutant, compile error; disregarded) | n/a |
| 24–29 | `AuctionEdition`: mint bound 101, royalty for any ID, blocked revocation, `tokenURI` unminted, nonce on mint, royalty rounds down | Killed (1 / 1 / 1 / 1 / 8 / 2) |
| 30–41 | `RoyaltyMarketplace`: inclusive expiries, skipped approval pre-check, credit to buyer, `totalCredits` kept, `transferFrom` instead of `safeTransferFrom`, anyone lists, double cancel, edition as recipient, overpayment, token 101, stale nonce recorded | Killed (1 / 1 / 1 / 11 / 4 / 4 / 2 / 1 / 1 / 1 / 1 / 29) |

## Bottom line

Code-correctness verdict unchanged from the first independent review: deploy-ready in the reviewed scope, with M-01/L-01 accepted by the creator. Before mainnet, in order: (1) close A-01 and P-03 so the attestation describes the code being deployed; (2) add the list-integrity test and mutant from N-01; (3) read the M-01 decision against the N-02 numbers and state the per-day stall cost to bidders if the decision stands; (4) obtain a funded third-party audit sized to funds at risk (≈ 90 × clearing price plus the ten reserved NFTs).
