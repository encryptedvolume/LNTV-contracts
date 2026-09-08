# Independent security audit — RankedAuction / AuctionEdition / RoyaltyMarketplace

**Current status:** [ISSUES.md](ISSUES.md) consolidates the creator's accepted decisions, verified fixes and all five remaining audit/integration tasks. Dated Codex follow-ups below distinguish later changes from Fable's original review.

**Date:** 2026-09-07 · **Reviewer:** Claude (Fable 5.1), independent read-only review commissioned by Joel.
**Scope:** `src/RankedAuction.sol`, `src/AuctionEdition.sol`, `src/RoyaltyMarketplace.sol`, `script/Deploy.s.sol`,
the audit runner and gates (`scripts/`), the test suite (`test/`), and every quantitative claim in
`audit/REPORT.md` and `audit/REAUDIT-2026-09-07.md`. This is a self-directed independent review, not a
substitute for a funded third-party audit.

**Pinned source reviewed** (matches `results.json`):
```
src/AuctionEdition.sol      fe163f6db23b7f0f5ab61a7382dd09de0607f3c7264953dafe13977c1712cab9
src/RankedAuction.sol       de04bd090c4268b587ce0a37ca180c3d181aa23b0b9b9d89bc750be56554a720
src/RoyaltyMarketplace.sol  ba2d6c869ddaf9f589f88d673f00f9bbecb75dbc73fea10f26de64bb22b6eb85
```

**Creator disposition added by Codex on 2026-09-07:** M-01 and L-01 are **accepted by design** following the creator's explicit confirmation. Retain uncapped extensions and no extension for a floor increase that preserves rank; no corrective contract change is requested for either finding. The original severity ratings, analysis and recommendations below are retained as review history. The reviewed source and measurements predate the subsequent 2.5% existing-bid increase. See [the accepted design decisions](DESIGN-DECISIONS-2026-09-07.md) and [verification of the 2.5% update](INCREASE-UPDATE-2026-09-07.md).

## Verdict

The three contracts are **well constructed and, in the reviewed scope, free of any Critical, High, or Medium
correctness defect.** ETH accounting, mint/supply accounting, access control, ranked-list integrity, and
transfer-royalty enforcement are all sound and unusually thoroughly tested. Every measurable claim in the two
in-repo reports reproduced. `REVIEW.md`'s single Low (forced third-party mint) is **fixed** in this revision.

The residual items below are **economic / liveness design properties** (all disclosed in the docs, but with
consequences I judge understated) and **process / robustness gaps** in the attestation itself. None is a fund-loss
bug in the contract logic.

| ID | Severity | Title | Status |
|---|---|---|---|
| M-01 | Medium (liveness, by-design) | Uncapped rolling extension → cheap indefinite settlement stall + fund lock-up | **Accepted by design — creator confirmed 2026-09-07; no corrective change requested** |
| L-01 | Low (economic) | Last-second rank-preserving tail increase reprices all winners with no counter-play; creator can weaponise via a planted tail bid | **Accepted by design — creator confirmed 2026-09-07; no corrective change requested** |
| L-02 | Low | Forced third-party mint before winner redirects (was `REVIEW.md` L-01) | **Resolved** (verified) |
| I-01 | Info (economic) | Increasing to an *exact* tie seizes rank #1 and pays full, demoting the former leader to the cutoff | Disclosed |
| P-01 | Low (process) | `local_e2e.py` lifecycle gate is timing-flaky (failed 1 of 3 fresh runs) | **Resolved — Codex verified 2026-09-07; four fresh lifecycle runs passed, including delayed submission** |
| P-02 | Info (process) | 10 mutants are killed by a single test each; the 24h-duration mutant only by a constant-getter assertion | **Resolved — Codex verified 2026-09-07; 57/57 mutations caught by at least two behavioral tests, with required independent scenarios** |
| P-03 | Info (process) | `auction/` + `.github/` still untracked in git; hashed evidence is git-ignored | Open (carried from `REVIEW.md`) |

---

## What I reproduced (all pass)

| Check | How | Result |
|---|---|---|
| Default test suite | `forge test` (1024-run fuzz, 256×128 invariants) | **111 passed, 0 failed** |
| Fresh-seed challenge | `FOUNDRY_PROFILE=audit forge test --fuzz-seed 0xA0D17` (10k fuzz, 3×(1000×256) invariants) | **111 passed, 0 failed, 0 reverts** — not seed-specific |
| Slither 0.11.5 | fresh `slither .` + `check_slither.py` | 14 findings, **byte-identical finding IDs** to stored `slither.final.json`; gate PASS |
| Production coverage | fresh `forge coverage` in a scratch copy | **100%** lines/branches/functions on all three contracts |
| Mutation suite | re-ran all 56 mutants + recorded which tests kill each | **56/56 killed** (see P-02 for kill quality) |
| Manifest | `shasum -a 256 -c audit/SHA256SUMS` | **430/430 OK** |
| Native runner + gate tests | `foundry.test.mjs`, `test_audit_gates.py` | 2 + 7 pass |
| Deployment checker negatives | `local_e2e.py` (2 of 3 runs) | wrong royalty / current / pending wallet / corrupted immutable all rejected |
| Compiler-bug review | Solidity `bugs.json` vs. 0.8.28 + legacy pipeline | no applicable bug (SOL-2026-1/-2 need IR; SOL-2025-1 needs boundary storage arrays; SOL-2026-3 ≥ 0.8.29) |

I re-derived the core invariants by hand and found no underflow/overflow path: at settlement
`escrow = Σ active bids ≥ gross` (each non-head winner pays ≤ its own bid), so `escrow -= gross`
(`RankedAuction.sol:215`) and each `bid.amount - winningBidCost` in `creditRefunds` (`:243`) are always
non-negative; the tiered `gross = head + clearing·(n-1)` handles `n=0` and `n=1` explicitly (`:213`).
Royalty ceil-division cannot exceed the sale price for `bps ≤ 10000`, so `price - royalty`
(`RoyaltyMarketplace.sol:90`) never underflows.

---

## M-01 · Medium (liveness / griefing) · Uncapped extension enables cheap indefinite settlement stall

**Numerical clarification added by Codex, 2026-09-07:** Integer recalculation of the quoted 288-step strategy at the original 0.5% threshold reproduces 0.021015016311213871 ETH added and 0.041015016311213871 ETH deposited across the pair. If both bids remain regular winners, their combined excess refund is only 15 wei; they still pay the final cutoff for their NFTs. Full refunds depend on displacement. The original cost table below does not match its own quoted proof-of-concept and must not be used as a verified cost estimate or as an estimate for the current 2.5% threshold. The accepted design disposition is unchanged; original analysis follows for review history.

**Where:** `RankedAuction._extend()` `src/RankedAuction.sol:384-388`; triggered by `createBid` (`:186`) and by
rank-changing `increaseBid` (`:203`). Contrast the reference `TLRankedAuction`, which bounds this with
`EXTENSION_HARD_CAP = 2 hours` (`reference/TLRankedAuction.sol.txt:49`, applied at `:248`). The cap was
deliberately removed here (report finding F-09) and its absence is asserted by a test and a mutant.

**Issue.** Bids can never be cancelled or withdrawn while active — only *displaced* bids refund
(`:174-185`). Every new bid or rank-changing increase in the final five minutes resets the deadline to
`now + 5 min`, with no ceiling. A single actor holding the two lowest (tail) bids can leapfrog them against each
other once per window forever. Each swap is a rank change, so it extends the auction, yet it only needs the
0.5% self-increase (`INCREASE_BPS`, `:46`) and never displaces anyone. Meanwhile all other bidders' escrow stays
locked and `settle()` reverts with `AuctionNotEnded`.

**Proof (run in a scratch copy; passes):**
```solidity
function testPoC_LeapfrogExtensionHoldsAuctionOpenForADay() public {
    live();
    for (uint256 i; i < 88; ++i) place(alice, 1 ether);   // 88 honest bids, 88 ETH escrowed
    uint256 a = place(bob, RESERVE);                        // griefer's two tail bids
    uint256 b = place(bob, RESERVE);
    uint256 initialEnd = auction.endTime();
    uint256 spent;
    for (uint256 i; i < 288; ++i) {                         // 288 five-minute windows = 24h
        uint256 lower = auction.tail();                     // always one of the griefer's pair
        uint256 upper = lower == a ? b : a;
        uint256 delta = auction.minimumIncrease(lower);
        if (bid(lower).amount + delta <= bid(upper).amount) delta = bid(upper).amount - bid(lower).amount + 1;
        vm.warp(auction.endTime() - 1);
        vm.prank(bob);
        auction.increaseBid{ value: delta }(lower);
        assertEq(auction.endTime(), block.timestamp + 300); // extended every time
        spent += delta;
    }
    // observed: 86,112 s (~23.9h) of extension for 0.021 ETH of (own, refundable) capital
    assertGe(auction.endTime() - initialEnd, 24 hours - 300);
    assertLt(spent, 0.1 ether);
    vm.expectRevert(RankedAuction.AuctionNotEnded.selector);
    auction.settle();                                       // settlement stays impossible
    assertEq(auction.escrow(), 88 ether + 2 * RESERVE + spent); // 88 ETH still locked
}
```
Observed logs: `seconds of extension 86112`, `griefer ETH added 21015016311213871` (0.021 ETH),
`total gas 36,680,752` over the 288 steps.

**Cost asymmetry** (reserve 0.01 ETH). The griefer's *added capital* grows as `1.005^steps` and stays trivial for
days; the dominant cost is gas. A new bid at capacity, by contrast, needs +5% each time (`1.05^steps`), which
explodes almost immediately — so the cheap path is the self-leapfrog, not honest bidding.

| Extra hours held open | Leapfrog capital (ETH, refundable) | Leapfrog gas @10 gwei (ETH) | Honest new-bid capital (ETH) |
|---:|---:|---:|---:|
| 24 | 0.08 | ~0.4 | 1.3e4 |
| 72 | 1.5 | ~1.3 | 2.0e16 |
| 168 | 465 | ~3.0 | 5.2e40 |

So for on the order of **0.4 ETH of gas per day** one actor keeps every committed bidder's ETH locked and blocks
closure indefinitely, repeatable at will.

**Assessment.** This is exactly what the docs promise ("There is no guaranteed latest closing time"), so it is a
*disclosed design decision*, not a coding error. I flag it Medium because the security-relevant consequence —
indefinite, cheap lock-up of all other bidders' funds by one self-funded participant — is stronger than the
neutral framing in the docs conveys, and it removes a protection the reference deliberately shipped.

**Recommended fixes (pick one):**
1. Reinstate a hard cap like the reference (e.g. `initialEndTime + MAX_TOTAL_EXTENSION`); simplest and matches the
   audited upstream behaviour.
2. Extend only when the *winning set* changes (a displacement, or an increase that crosses the clearing line),
   not for reshuffles wholly inside the current top 90.
3. If uncapped extension is a firm product requirement, state the fund-lock-up consequence explicitly to bidders
   in `OPERATIONS.md` and the frontend, since committed bids cannot be exited.

Any of these changes bytecode and re-triggers the full audit + hash re-pin.

---

## L-01 · Low (economic) · Last-second tail increase reprices every winner with no counter-play

**Where:** clearing price is the tail amount at capacity, `settle()` `src/RankedAuction.sol:212`; a
rank-*preserving* increase does **not** extend (`:203`, only extends when `oldPrev != bid.prev`).

**Issue.** In this uniform-price design ranks 2–90 pay the lowest winning bid. Any winner can raise the tail; the
lowest winner can raise *its own* bid at the last second and lift the price everyone else pays — and because a
rank-preserving increase never extends the clock, no one can react. A creator who plants a shill bid at the tail
turns this into a near-free revenue lever: the shill's payment loops back to the payout wallet as proceeds, so its
only real cost is transient capital + gas.

**Proof (passes):**
```solidity
function testPoC_CreatorTailIncreaseRepricesEveryWinnerAtTheLastSecond() public {
    live();
    for (uint256 i; i < 89; ++i) place(alice, 1 ether);
    vm.deal(payoutWallet, 10 ether);
    uint256 shill = place(payoutWallet, RESERVE);                 // rank 90, sets the clearing price
    vm.warp(auction.endTime() - 1);
    vm.prank(payoutWallet);
    auction.increaseBid{ value: 1 ether - RESERVE }(shill);       // ties alice's 1 ETH; later ID keeps it the tail
    assertEq(auction.endTime(), auction.initialEndTime());        // NO extension: nobody can respond
    vm.warp(auction.endTime());
    auction.settle();
    assertEq(auction.clearingPrice(), 1 ether);                   // was 0.01 ETH a second earlier
    assertEq(auction.pendingProceeds(), 90 ether);                // vs. ~1.89 ETH honest; +88 ETH extracted
}
```

**Assessment.** This is the disclosed "no shill protection" + "tail increase raises clearing price without
extending" property (`REVIEW.md` I-02/I-03), but the interaction — a creator-controlled tail plus a guaranteed
no-extension last look — is sharper than generic shilling: the creator sets the price honest winners pay, with the
shill's own outlay refunded to itself as proceeds. **Recommend** either extending on any increase that raises the
clearing price, or disclosing this last-look explicitly to bidders. Inherent to uniform-price clearing, hence Low.

## I-01 · Informational · Increasing to an exact tie seizes rank #1 at full price

`_insert` breaks ties by **earlier original bid ID** (`src/RankedAuction.sol:360`). A later bidder can increase to
*exactly* match the current head and, by virtue of its smaller ID… no — the *earlier* ID wins, so a bid that was
placed earlier and then increased to a tie jumps ahead of a higher-but-later bid. Confirmed by PoC: a rank-2 bid
increased to an exact tie with the head becomes the head and pays its **full** amount for #1, demoting the former
leader to the cutoff. Disclosed; the frontend should surface that a tie resolves by original bid ID and that #1
pays full.

---

## Process & robustness

### P-01 · Low · The local lifecycle gate is timing-flaky

**Codex follow-up, 2026-09-07: resolved.** The harness now pins and verifies the actual transaction block timestamp without an intervening empty block. The old failure was reproduced under delayed submission; the fixed harness passed three ordinary fresh deployments plus one deliberately delayed deployment. See [the fix and verification record](TIMING-FIX-2026-09-07.md). Original finding follows for review history.

`scripts/local_e2e.py` failed **1 of 3** fresh runs in this environment, at the first late-bid increase (line 140),
with the transaction reverting `BiddingClosed`. Root cause is a harness timing assumption, **not** a contract bug:
the loop warps to `endTime - 1` then sends `increaseBid`, and Anvil intermittently mines that transaction in the
*next* block at `endTime`, where `phase()` is already `Ended`. A minimal repro shows the tx normally lands at
`endTime - 1` (still `Live`, extends correctly), so the outcome depends on wall-clock alignment. Because
`local_e2e.py` is part of the `npm run audit` attestation, this makes the stored "local lifecycle PASS" evidence
not reliably reproducible and can spuriously fail CI. **Fix:** set the block timestamp immediately before the
transaction (no intervening `evm_mine`), warp to `endTime - 2`, or run Anvil with deterministic block times.

### P-02 · Info · Mutation-kill quality is uneven

**Codex follow-up, 2026-09-07: resolved.** Added 15 behavioral scenarios and a permanent gate requiring at least two behavioral failures per mutation, excluding configuration-only checks. All 57 current mutations passed; the required hour-23 bidding and hour-two settlement scenarios both catch the duration regression. The complete contract suite passed 127 tests, and 12 mutation-runner regression tests passed. See [the before/after attribution and verification record](MUTATION-STRENGTHENING-2026-09-07.md). Original finding follows for review history.

All 56 intentional mutants are killed, but I recorded *which* tests kill each and several kills are single points of
failure: `two-hour extension cap restored`, `extension timestamp narrowed`, `royalty transfer bypass`,
`free purchase`, `unauthorized cancellation`, `unsafe payout wallet allowed`, `forced third-party mint delivery`,
`unauthorized ERC721 mint`, `ERC721 token approval bypass`, and `metadata slash validation bypassed` are each caught
by exactly one test. The `wrong initial duration` mutant (24h→1h) is caught **only** by constant-getter assertions
(`testFixedSupplyAnd24HourDuration`, `testLeadTimeAndFixed24HourDuration`) — no behavioural test exercises the
24-hour length — so a duration change would survive if those literal getters were ever relaxed. These are
test-robustness observations, not live gaps. **Suggest** a second independent assertion for the single-test kills.

### P-03 · Info · Package still untracked; evidence git-ignored
`auction/` and `.github/` have **zero tracked files** in the LNTV repo, and `audit/generated/` + `lcov.info` are
git-ignored, so the SHA-256-pinned evidence lives only locally and as a 30-day CI artifact. The `SHA256SUMS`
manifest now covers docs/README/site (an improvement over `REVIEW.md` P-07). **Recommend** committing the package
and a single clean `npm run audit` evidence set together before any launch. (Also present in the repo root: a
stray `:memory:.ses` file and untracked `site/public/auction*.js|css|html` — unrelated to this package.)

---

## Deployment-script review (`script/Deploy.s.sol`)

Sound. `validateConfig` checks chain match, supported chain (1/11155111/31337), ≥10 min lead, `reserve ∈ (0,
uint128]`, `bps ∈ (0, 10000]`, `start ≤ uint64.max`, non-zero payout, non-empty metadata ending `/`, non-empty
name/symbol — all **before** narrowing casts, so no silent truncation (verified by `testNoSilentNumericTruncation`).
The constructor re-validates `start > block.timestamp` and rejects the system addresses as payout wallet
(`RankedAuction.sol:106,390-395`). `check_deployment.py` pins all reads to one block, verifies runtime bytecode with
immutable masking **and** cross-checks that repeated immutable copies agree, then checks every immutable/config value
and solvency, and re-verifies the block hash — a corrupted-immutable negative test confirms rejection. No issue found.

## Bottom line

Deploy-ready from a *code-correctness* standpoint in the reviewed scope. Before mainnet: (1) decide M-01 (a hard
extension cap is the safe default and restores reference behaviour); (2) decide whether to mitigate or merely
disclose L-01/I-01; (3) fix the flaky `local_e2e.py` timing and commit the package + one clean evidence run to git;
(4) obtain a funded third-party audit sized to funds at risk (≈ 90 × clearing price). Any bytecode change from
(1)/(2) invalidates the current hash gates and requires a fresh `npm run audit` and re-pin.
