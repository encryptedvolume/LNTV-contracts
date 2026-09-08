# Independent security audit, third pass — encryptedvolume/LNTV-contracts

**Date:** 2026-09-08 (evening, AEST). **Reviewer:** Claude (Fable 5.1), read-only against the repository; every build, test, Slither and mutation run happened on isolated copies under the session scratchpad. The local checkout and its `audit/generated/` were not written to, except to add this report and its evidence directory under a new name. A separate Codex agent was regenerating `audit/generated/` in the local checkout while this review ran (files changing after 18:22); nothing here depends on that run.

**Scope:** the GitHub repository `encryptedvolume/LNTV-contracts` (branch `main` and branch `codex/48-hour-auction`) and the local working tree at `~/Desktop/dev/LNTV-contracts`, which is ahead of both. Contracts `src/RankedAuction.sol`, `src/AuctionEdition.sol`, `src/RoyaltyMarketplace.sol`, `script/Deploy.s.sol`, every file under `test/`, `scripts/`, `interface/`, `.github/workflows/`, `foundry.toml`, the vendored `lib/`, and the requirements stated in `README.md`, `docs/ARCHITECTURE.md`, `docs/OPERATIONS.md`, `docs/FRONTEND.md`, `audit/ISSUES.md`, `audit/TIMING-UPDATE-2026-09-08.md`, `audit/REFUND-RECOVERY-2026-09-08.md`, `audit/REPOSITORY-SPLIT-2026-09-08.md`. This is a self-directed independent review, not a funded third-party audit.

## Three revisions exist; only one is current

| Where | Commit | `src/RankedAuction.sol` SHA-256 | Policy | Status |
|---|---|---|---|---|
| GitHub `main` | `b8a2497` | `45371987…325a7` | 24 h initial, 5-minute window, refunds never expire | Byte-identical (all three contracts, `Deploy.s.sol`, every test and script) to the source pinned by the second independent review of 2026-09-07. Verdict from that review stands unchanged. |
| Commit `6660294` (local `main`; was the tip of GitHub `codex/48-hour-auction` until 18:38) | `6660294` | `0edfe997…8a0b7` | 48 h, 10-minute window, **automatic** refund expiry at `endTime + 28 days`, getter `refundDeadline()` | Withdrawn. The package's own `audit/REFUND-RECOVERY-2026-09-08.md` banner says this was an incorrect interpretation of the creator's request. Remains in history only; **never deploy this commit.** |
| Local working tree at review start (18:19, uncommitted); committed by the Codex agent as `0d52419` at 18:38 and pushed to GitHub `codex/48-hour-auction` | `0d52419` | `741b6805…32705` | 48 h, 10-minute window, **optional** recovery: refunds stay open until `withdrawUnclaimedETH` succeeds | Current. Audited in depth below. Not yet on GitHub `main`. `AuctionEdition.sol` (`fe163f6d…`) and `RoyaltyMarketplace.sol` (`ba2d6c86…`) are unchanged across all three revisions. |

Hashes of every reviewed file in the current revision are in `generated/independent-audit-20260908-fable-3/reviewed-hashes.txt`.

## Verdict

No Critical, High or Medium **correctness** defect in any of the three revisions. The recovery feature is implemented correctly against its stated policy: authorization, settlement and time guards, accounting-before-interaction, rollback on failure, reentrancy, forced-ETH handling and the closure flag all hold, and the package's 25 recovery tests, 16 recovery mutants and my own proof-of-concept tests agree.

What the recovery feature changes is the **trust model**, and two consequences of how it is anchored deserve a decision before deployment.

| ID | Severity | Title | Status |
|---|---|---|---|
| F3-01 | Medium (trust/design; creator-accepted as R-01) | Optional recovery turns bidder refunds from a trustless entitlement into a 28-day obligation on the bidder, and gives the payout wallet a financial interest in refunds going unclaimed | Accepted by design 2026-09-08. Recorded here so the acceptance is explicit about consequences and disclosure |
| F3-02 | Low (design, one-line fix) | Recovery eligibility is anchored to `endTime`, not settlement. A contract payout wallet can settle and sweep every winner overpayment in one transaction at day 28 if nobody settled earlier; any late settlement shrinks the crediting window | Open. PoC-A and PoC-A2. The package's own `testLateSettlementDoesNotRestartTheRecoveryDelay` enforces the current behaviour, so it is a deliberate choice, but one with no benefit to the creator |
| F3-03 | Process (must close before deployment) | GitHub `main` still holds the old 24-hour contract; the corrected revision reached GitHub only on `codex/48-hour-auction` at 18:38, and that branch's history contains the withdrawn automatic-expiry commit | Mostly closed during the review: at 18:30 the corrected source was uncommitted with a stale attestation and a missing `RECOVERY-CHOICE-2026-09-08.md`; by 18:55 the Codex agent had regenerated `results.json` and `SHA256SUMS` (0 failures), written the document, committed `0d52419` and pushed the branch. Remaining: fast-forward `main` to `0d52419`, push, delete the branch |
| F3-04 | Informational (economics; refreshes accepted M-01 / N-02) | Halving the extension window to 10 minutes roughly halves the gas and cuts the capital needed to stall the auction: one day now costs about 0.14 ETH of commitment and 17.5M gas with ten rotating tail bids, or 0.12 ETH and 18.4M gas with two | Accepted design; numbers refreshed for the decision record |
| F3-05 | Informational | `withdrawUnclaimedETH` also sweeps unwithdrawn primary proceeds and emits a single `UnclaimedETHWithdrawn` for the whole amount; off-chain accounting must not treat that event as "refunds only" | Documented in OPERATIONS; note for the indexer |
| F3-06 | Informational (supply chain) | CI actions are pinned by major tag, not commit SHA (`actions/checkout@v4`, `setup-node@v4`, `setup-python@v5`, `upload-artifact@v4`) | Optional hardening |
| F3-07 | Informational (hygiene) | Line 5 of `audit/INDEPENDENT-AUDIT-2026-09-07-fable.md` names the commissioning individual; the repository otherwise uses only the `encryptedvolume` noreply identity | Consider redacting to the repository identity |

Carried forward, re-verified on the current source: **N-01** still open (the `_unlink` back-pointer mutant passes all 149 unit tests; both auction invariant campaigns fail on it within 3 seconds), **N-04** and **N-05** open (`Deploy.s.sol:38` still enforces a 10-minute lead), **M-01**, **L-01** accepted, **I-01** disclosed, **APP-01**, **APP-02**, **DEP-01** open. The A-01/N-03 attestation gap is closed for `main`; for the working tree a matching attestation now exists but is uncommitted (F3-03).

---

## What I reproduced

All runs used Foundry 1.7.1 (native binary from `node_modules/@foundry-rs/forge-darwin-arm64`), Node 22.23.1, Solidity 0.8.28 (Cancun, optimizer 200), Slither 0.11.5 from the package's `.venv`, on the working-tree source `741b6805…`.

| Check | How | Result |
|---|---|---|
| Build | `forge build --sizes` | RankedAuction 10,237 / 23,638 bytes (runtime / initcode), AuctionEdition 6,129 / 11,952, RoyaltyMarketplace 4,507 / 4,654; all under EIP-170/3860. Only compiler note: the `uint16(rank)` cast lint at `settle()`, bounded by `SUPPLY = 90` |
| Unit and fuzz suite (default profile, 1,024 fuzz runs) | `forge test --no-match-contract Invariant` | **149 passed, 0 failed** (`generated/…/unit-tests.log`) |
| Stateful invariants (default profile) | `forge test --match-contract Invariant` | 3 campaigns × 256 runs × 128 depth = 32,768 calls each, **0 reverts, all pass** (`invariants-default-profile.log`) |
| Slither gate | `slither . --filter-paths 'lib/|test/|script/'` then `scripts/check_slither.py` | 16 findings, every one in `audit/slither-reviewed.json` (which pins `741b6805…`); **no unreviewed finding, no source drift** (`slither.json`, `slither.log`) |
| Frontend interface | `node scripts/export-interface.mjs --check` | "Verified contract interface 3.0.0; 0 deployed networks". Exported ABIs contain `RECOVERY_DELAY`, `recoveryAvailableAt`, `refundsClosed`, `refunds(address)`, `withdrawUnclaimedETH` and the `UnclaimedETHWithdrawn` event; no deployment addresses yet |
| Package mutation campaign (77 mutants, two-behavioral-test gate) | `scripts/mutation_audit.py --output-dir …` on the isolated copy | **77/77 killed**, each by at least two behavioral tests, on a clean 149-test baseline (`mutations.log`, `mutations/mutations.json`); this independently reproduces the RECOVERY-CHOICE attestation |
| N-01 re-check | `_unlink`: `else bids[bid.next].prev = bid.prev;` → `else { }` on a separate copy | Unit suite: 149/149 still pass. Invariants (8 × 64): both auction campaigns **fail** (`51 != 52`, `2 != 1`) |
| New proof-of-concept tests | `AuditFable3.t.sol`, 8 tests | 8 pass on the current source (`poc-run.log`); numbers below |
| Vendored dependencies | `audit/SHA256SUMS` `lib/` entries | Every `lib/` entry verifies: OpenZeppelin 5.5.0 and forge-std unchanged since the byte-identical upstream comparison of 2026-09-06 |
| Repository state | GitHub API unauthenticated, `git log` | `404` unauthenticated, so the repository is private as documented. All three commits authored and committed by `encryptedvolume <87842543+encryptedvolume@users.noreply.github.com>` |
| Local vs GitHub | `git status`, `git diff`, hash comparison | Local `main` = GitHub `main` + `c60b07d` + `6660294` (= `codex/48-hour-auction`), plus 28 uncommitted modified files and 2 untracked history files |

### Hand re-derivation of the new accounting (`src/RankedAuction.sol:307-348`)

- **Guards.** `withdrawUnclaimedETH` requires `msg.sender == payoutWallet` (`:338`), `settled` (`:339`) and `block.timestamp >= endTime + 28 days` (`:340`). `settled` implies `block.timestamp >= endTime` at settlement, and `endTime` can only change through `_extend()`, which is reachable only while `phase() == Live`, so after settlement `recoveryAvailableAt()` is fixed.
- **Closure before interaction.** `refundsClosed = true` and the three accounting buckets are zeroed (`:342-345`) before `_send` (`:346`). `_send` reverts on zero amount, on the zero address, on the auction itself, and on a failed call (`:435-440`); every revert rolls back the flag and the buckets, so a failed recovery leaves refunds open. Confirmed by `testRejectedRecoveryPreservesAllAccountingForRetry` and mutant "recovery leaves refunds open".
- **No liability can be recreated.** After closure, `creditRefunds` (`:241`) and `withdrawRefund` (`:319`) revert with `RefundsClosed`, which is what prevents `escrow -= credited` (`:254`) and `totalRefunds -= amount` (`:322`) from underflowing on the zeroed buckets. `createBid`/`increaseBid` require `Live`, which is impossible once `settled`. `withdrawProceeds` finds `pendingProceeds == 0` and reverts `NothingToWithdraw`. `liabilities()` is therefore permanently 0 after a successful recovery, and `balance >= liabilities()` still holds.
- **Forced ETH.** The sweep amount is `address(this).balance` (`:341`), so surplus is included; a second call after later forced ETH succeeds and refunds stay closed. `refunds(bidder)` reads through the flag (`:314-316`) while `_refunds` keeps the historical values, which is harmless because every spender checks the flag.
- **Reentrancy.** The recipient callback runs under the auction's guard; `withdrawRefund`, `creditRefunds`, `withdrawProceeds`, `proposePayoutWallet` and a nested recovery all revert (`nonReentrant` or `RefundsClosed`). The marketplace and edition are unaffected because they hold no auction ETH. Confirmed by `testRecoveryCannotReenterRecovery` and `testRecoveryCannotNominateAnotherWalletDuringCallback`.
- **Race at eligibility.** From `recoveryAvailableAt()` on, a bidder's `withdrawRefund` and the payout wallet's recovery are ordered by the block builder. Both orders are consistent: a refund first reduces the swept amount; a recovery first makes the refund revert with `RefundsClosed`. Documented in OPERATIONS.
- **Displaced-bid refunds** are credited during bidding (`:187`) and withdrawable during `Live` (no phase check on `withdrawRefund`), so a displaced bidder never needs to wait for settlement (PoC-D).
- **Timing constants.** `AUCTION_DURATION = 48 hours`, `EXTENSION_WINDOW = 10 minutes` (`:42-43`). `_extend()` at exactly 600 s remaining does not extend; at 599 s it sets `endTime = block.timestamp + 600` (PoC-C). `initialEndTime - startTime == 48 hours`.

## Requirements conformance (additions since the second review)

| Documented rule | Implementation | Verified by |
|---|---|---|
| 48-hour initial window, end exclusive (README:28, OPERATIONS:144) | `AUCTION_DURATION` `:42`, constructor `:115-116`, `phase()` `:151-156` | Deployment/RankedAuction tests, PoC-C |
| Ten-minute rolling window, no cumulative cap, rank-changing increases only (README:9, OPERATIONS:144) | `EXTENSION_WINDOW` `:43`, `_extend()` `:422-426`, trigger `:191`, `:208` | MutationBehavior, mutants "24-hour cap introduced" etc., PoC-B |
| Refunds have no automatic expiry; credit and withdraw until a successful recovery (README:32, ARCHITECTURE "Optional recovery", OPERATIONS:148-170) | `_requireRefundsOpen()` `:378-380`, `refunds()` `:314-316` | `testYearsOfInactionDoNotCloseRefunds`, mutants "automatic refund expiry restored", "refund getter automatically expires" |
| Recovery only by the current payout wallet, after settlement, at/after `endTime + 28 days`; rotation transfers the role; deployer has no role (README:9,33; OPERATIONS:148-163) | `:337-340`, `payoutWallet` rotation `:123-149` | RefundRecovery tests, mutants 68-73 |
| Success closes refunds, sweeps proceeds, refunds and forced surplus; failure and empty attempts revert without closing (OPERATIONS:156-165) | `:341-347`, `_send` `:435-440` | `testRejectedRecoveryPreservesAllAccountingForRetry`, `testRecoveryRejectsInvalidRecipientsAndEmptyRepeat`, PoC-E |
| Late settlement does not postpone eligibility (OPERATIONS:152-153, ARCHITECTURE) | `recoveryAvailableAt()` `:309-311` uses `endTime` only | `testLateSettlementDoesNotRestartTheRecoveryDelay`; see F3-02 |
| NFT claims, unsold/reserved inventory and marketplace balances unaffected by recovery (OPERATIONS:167-168) | recovery touches no bid flags, `unsoldRemaining`, `reservedRemaining` or the other contracts | `testRecoveryLeavesWinningNFTsAndTradingCreditsAvailable`, `testRecoveryPreservesUnsoldAndReservedMintEntitlements`, PoC-A |
| Interface 3.0.0 exports the new getters and event; no new deployment parameter (OPERATIONS:172-174, FRONTEND:38-50) | `interface/index.js`, `manifest.json` pinning `741b6805…` | `export-interface.mjs --check` |

Every rule from the second review's conformance table that is unaffected by the timing and recovery changes was re-checked against the unchanged code and still holds. One stale sentence: `docs/OPERATIONS.md:144` still says "including at 24 hours past the initial close" as an example, which is correct but reads as if 24 hours were a limit; harmless.

---

## F3-01 · Medium (trust/design, accepted) · What the recovery option changes

**Where:** `src/RankedAuction.sol:337-348`, `:378-380`, `:314-316`.

Before this revision the auction was trustless for bidders: a displaced bidder's or winner's overpayment was theirs indefinitely and no key could touch it. Now the current payout wallet may, at its option, take every unclaimed wei once 28 days have passed since the final `endTime`. That is the creator's explicit R-01 decision and the implementation is faithful to it. Three consequences should be stated wherever the decision is recorded and in bidder-facing disclosure:

1. **Bidders carry a deadline they cannot see on-chain as a deadline.** `recoveryAvailableAt()` is when the option opens, not when refunds close; refunds close whenever the payout wallet chooses to exercise it. A bidder who reads `refunds(me) > 0` on day 40 can still lose it in the next block. The frontend must display "recoverable by the creator since <date>" once eligibility passes, not a countdown.
2. **The payout wallet gains an interest in refunds going unclaimed.** Crediting is permissionless and the events are public, so the mitigation is that anyone (including the frontend, an indexer, or a bidder) can call `creditRefunds` for all winners at settlement. The frontend should do exactly that in the settlement flow so every winner's refund is credited and visible without depending on the creator.
3. **Recovery is irreversible and wholesale.** One successful call closes refunds for every bidder at once, including a bidder whose credit was 1 wei away from withdrawal in the same block. There is no per-bidder or partial recovery. Operationally, the creator should announce the intended recovery date in advance and credit all refunds first, so the sweep only ever takes what was truly abandoned.

No code change is requested. If the creator wants a softer form later, the smallest change is a fixed grace period after `recoveryAvailableAt()` during which recovery is announced on-chain (a `recoveryAnnouncedAt` timestamp) before it can execute.

## F3-02 · Low · Anchor recovery to settlement, not to `endTime`

**Where:** `src/RankedAuction.sol:309-311` (`recoveryAvailableAt() = endTime + RECOVERY_DELAY`), `:339-340`.

**Issue.** Winner overpayments cannot be credited until `settle()` has run (`creditRefunds` requires `settled`, `:240`), but the 28-day clock starts at `endTime` regardless of when settlement happens. Settlement is permissionless, so in the normal case somebody settles within minutes and the window is a full 28 days. In the abnormal case (frontend down, no bidder settles) the window is whatever is left after settlement, down to zero:

- **PoC-A** (`testPoCA_SettleAndRecoverAtomicallyLeavesNoPostSettlementWindow`): the payout wallet is rotated to a small contract (`PayoutBot`). Three winners bid 5, 3 and 1 ETH against a 0.01 ETH reserve; nobody settles. At `endTime + 28 days` the bot calls `settle()` and `withdrawUnclaimedETH()` in one transaction and receives 9 ETH, including 3.98 ETH of winner overpayments that were never creditable at any earlier block. `creditRefunds` and `withdrawRefund` then revert with `RefundsClosed`. NFT claims still work.
- **PoC-A2** (`testPoCA2_LateSettlementShrinksCreditWindow`): settlement on day 27 leaves exactly one day to credit and withdraw.

**Why it matters.** The bidder-facing promise is "28 days". For winners the promise is really "28 days minus however long the auction stays unsettled". Since settlement is permissionless the payout wallet gains nothing from the `endTime` anchor: it can always settle at `endTime` itself and then wait 28 days.

**Recommendation.** Record the settlement time and anchor the delay to it:

```solidity
uint256 public settledAt;                       // set in settle()
function recoveryAvailableAt() public view returns (uint256) {
    return (settled ? settledAt : endTime) + RECOVERY_DELAY;
}
```

This is a bytecode change, so it invalidates `slither-reviewed.json`'s pinned hash, `results.json`, `SHA256SUMS`, the interface manifest and the Codex evidence; the package's `testLateSettlementDoesNotRestartTheRecoveryDelay` and the "recovery eligibility ignores extensions" mutant would need updating (extensions still move `endTime`, and `settledAt >= endTime` always, so the extension test still holds). If the creator prefers to keep the `endTime` anchor, state in OPERATIONS and the frontend that the window is measured from the close, not from settlement, and have the frontend settle automatically at close.

## F3-03 · Process · GitHub does not hold the current contract

**Observed at 18:30 on 2026-09-08 (start of review):**

| Item | State |
|---|---|
| GitHub `main` (`b8a2497`) | Old policy (24 h / 5 min / no recovery). Fully attested by the split verification and both prior reviews. |
| GitHub `codex/48-hour-auction` (`6660294`) | Withdrawn automatic-expiry policy (`REFUND_CLAIM_PERIOD`, `refundDeadline()`, `RefundClaimPeriodExpired`). Its commit message and the later banner in `REFUND-RECOVERY-2026-09-08.md` disagree about what the creator asked for. Full diff against the current source: `generated/independent-audit-20260908-fable-3/codex-branch-vs-working-tree-RankedAuction.diff`. |
| Local working tree | Corrected policy, 28 modified files uncommitted, 2 untracked history files. |
| `audit/results.json` | Pinned `src/RankedAuction.sol = 0edfe997…` (the withdrawn source). |
| `audit/SHA256SUMS` | 40 of 899 entries failed on the working tree. |
| `audit/RECOVERY-CHOICE-2026-09-08.md` | Linked from `README.md:79`, `ISSUES.md` and the `REFUND-RECOVERY` banner; did not exist. |
| `audit/generated/` | Being rewritten by a Codex `npm run audit`. |

**Re-checked at 18:50 and 18:55 (after that Codex run finished):** `src/RankedAuction.sol` unchanged at `741b6805…`; `audit/RECOVERY-CHOICE-2026-09-08.md` written at 18:37 with a passing attestation (152 tests, 77/77 mutants, 16 reviewed Slither findings, seed `0x2026090829`) that matches what I reproduced independently; `results.json` pins `741b6805…`; `shasum -a 256 -c audit/SHA256SUMS` passes with 0 failures. The Codex agent then committed everything as `0d52419` ("Keep refunds open until successful optional recovery", 18:38) and pushed it to `origin/codex/48-hour-auction`. GitHub `main` is still `b8a2497`.

**Recommendation.** Fast-forward `main` to `0d52419` (plus this review's files), push, and delete `codex/48-hour-auction` so the default branch is the audited contract and the withdrawn commit `6660294` is reachable only through history. Until then, a default clone of the repository yields the 24-hour contract with no recovery, which is not what the current documentation describes.

## F3-04 · Informational · Extension economics at ten minutes

**Where:** `EXTENSION_WINDOW = 10 minutes` (`:43`), tie rule (`:398`), trigger (`:208`).

The second review measured the rotating-tail-bid stall with a five-minute window (N-02). Re-measured with the same PoC against the current constants (reserve 0.01 ETH, 90 − k honest 1 ETH bids, k griefer bids at reserve raised by the 2.5% minimum in rotation, each step landing one second before close):

| Rotating tail bids *k* | Windows | Held open | Griefer wei added | Final commitment | Clearing price at close | Griefer gas |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 12 (2 h) | 7,188 s | 0.0032 ETH | 0.0232 ETH | 0.0116 ETH | 1.53 M |
| 2 | 144 (1 day) | 86,256 s | 0.098 ETH | 0.118 ETH | 0.059 ETH | 18.4 M |
| 10 | 144 (1 day) | 86,256 s | 0.043 ETH | 0.143 ETH | 0.0141 ETH | 17.5 M |

Against the five-minute figures (k = 2: 0.70 ETH and 36.7 M gas per day; k = 10: 0.20 ETH and 35.0 M gas), the longer window halves the transactions per day and therefore the gas, and because commitment compounds per window it cuts the capital by roughly 6× for k = 2 and 1.4× for k = 10. The 48-hour initial period does not change these per-day numbers. The creator's M-01/L-01 acceptance stands; the decision record should carry these figures rather than the five-minute ones. The cheapest bytecode-level mitigation remains a total-extension cap, which the mutation gate deliberately treats as a regression.

## F3-05, F3-06, F3-07 · Informational

- **F3-05.** `withdrawUnclaimedETH` zeroes `pendingProceeds` (`:345`) and sends the whole balance, so a creator who never called `withdrawProceeds` receives proceeds and refunds together under one `UnclaimedETHWithdrawn` event (PoC-E). Any bookkeeping that separates revenue from forfeited refunds must compute the split from `AuctionSettled.proceeds` minus prior `ProceedsWithdrawn` amounts. OPERATIONS already says the sweep includes proceeds; the indexer note in FRONTEND could say so as well.
- **F3-06.** `.github/workflows/auction.yml:18-34` pins four actions by major tag. Pinning by commit SHA (with a comment naming the tag) removes the tag-move supply-chain vector. Optional.
- **F3-07.** The first-pass review header names the person who commissioned it. The repository otherwise carries only the `encryptedvolume` noreply identity in commits and docs. Redact to "commissioned by the repository owner" if identity separation matters for this repository as it does elsewhere.

---

## Proof-of-concept inventory (`generated/independent-audit-20260908-fable-3/AuditFable3.t.sol`)

| Test | Shows |
|---|---|
| `testPoCA_SettleAndRecoverAtomicallyLeavesNoPostSettlementWindow` | F3-02: contract payout wallet settles and sweeps 9 ETH (3.98 ETH overpayments) in one transaction at day 28 |
| `testPoCA2_LateSettlementShrinksCreditWindow` | F3-02: settlement on day 27 leaves one day |
| `testPoCB_StallOneDayTwoTailBids`, `…TenTailBids`, `…TwoHoursTwoTailBids` | F3-04 numbers |
| `testPoCC_ExtensionBoundaryTenMinutes` | 600 s remaining does not extend, 599 s does; 48-hour initial window |
| `testPoCD_DisplacedRefundWithdrawableDuringLiveAndSweptAfterRecovery` | Displaced refunds are withdrawable during bidding and are part of a later sweep |
| `testPoCE_RecoverySweepsProceedsWithoutProceedsEvent` | F3-05 |

The file is kept outside `test/` so it does not change the package's mutation baseline (which requires an exact test inventory). To run it: copy into `test/` on a scratch copy and `forge test --match-contract AuditFable3Test -vv`.

## Bottom line

The contracts are correct for the policy the creator chose. Before mainnet, in order:

1. **Close F3-03**: fast-forward `main` to the corrected revision `0d52419` (with this review committed), push, and delete the `codex/48-hour-auction` branch.
2. **Decide F3-02**: anchor recovery to settlement (two lines, then re-run every gate), or document the close-anchored window and auto-settle from the frontend.
3. **Disclose F3-01** before the first real bid, and credit all winner refunds in the settlement flow so the sweep only ever takes abandoned ETH.
4. **Add the N-01 list-integrity test and mutants** (unchanged recommendation, still reproducible).
5. **Refresh the M-01 decision record** with the F3-04 numbers.
6. **Fund a third-party audit** sized to funds at risk; a 90-slot auction with a 48-hour window and a sweep option is a different risk profile from the one the first review saw.
