# Security review and verification report

> **Historical verification snapshot.** The results and PASS statements below describe the source before the 2.5% existing-bid increase and subsequent test-harness changes. See [ISSUES.md](ISSUES.md) for current statuses and follow-up evidence. The current complete run is [the 2026-09-08 split verification](REPOSITORY-SPLIT-2026-09-08.md). References below to `results.json` and `SHA256SUMS` describe the original copies now archived under `history/2026-09-07-*`.

**Review date:** 2026-09-07. **Result:** no unresolved implementation defects identified in the reviewed scope. All completed contract, fuzz, invariant, mutation, static-review, deployment and audit-gate checks pass. This is an implementation self-review and automated audit suite, not an independent third-party audit or a formal proof that no defects exist.

The [2026-09-07 re-audit](REAUDIT-2026-09-07.md) repeated manual review and completed the full suite with a new seed. No new production defect was identified and all three production sources remain unchanged. Five tests were added for callbacks across contracts and randomized claim/refund ordering; all invariant campaigns now advance time. The audit runner records its selected seed.

## Scope and build

The reviewed production system is `RankedAuction`, `AuctionEdition`, and `RoyaltyMarketplace`, their reachable vendored OpenZeppelin code, deployment configuration and binding logic, and the audit runner. Reference commit and dependency versions are recorded in `NOTICE.md`. Source/test/tool/reference/dependency/documentation/audit-metadata and CI hashes are in `SHA256SUMS` (paths relative to the auction package); the static finding review independently pins hashes of all three production sources.

This revision has **100 ERC-721 NFTs total: 90 auctioned IDs #1–90 and ten reserved IDs #91–100**. Settlement assigns auction IDs by final rank, regardless of claim order. The highest-ranked bid pays its full amount for NFT #1. Other winners pay the 90th winning bid when full, or reserve when fewer than 90 bids win. A sole winner pays its full bid. Ties favor the earlier original bid ID. Empty auctions settle with zero proceeds. The current shared payout wallet claims reserved NFTs independently of auction state, and unsold claims can consume only unallocated auction IDs through #90. Lifetime mint accounting remains capped at 100.

The initial auction duration is exactly 24 hours. New bids at capacity require floor + 5%, rounded up; existing-bid increases require an additional 0.5%. Qualifying late bids reset the uint256 deadline to five minutes after the bid, with no total extension cap. Settlement and displacement have no receiver callbacks. Only the winning bidder may claim and redirect its NFTs; refunds remain separate.

The shared two-step payout wallet receives all primary auction revenue with no royalty deduction. Only secondary trades accrue royalties. Accepted rotation moves control of unwithdrawn business revenue and unclaimed reserved/unsold inventory; personal bidder and seller entitlements remain with their owners. Royalty rate, supply, auction settings and metadata base URL are fixed.

Each token resolves to a distinct off-chain URL (`base + ID + .json`). There are no on-chain reveal controls, reveal state or metadata refresh events. The metadata service must initially serve unrevealed content for all 100 IDs and later enforce creator-enabled, owner-requested reveals. That backend is **outside this contract implementation and audit scope**. The contract guarantees the rank-to-ID assignment, not the artwork's rarity, secrecy, immutability or release permissions. Off-chain content changes do not invalidate marketplace listings.

Frontend verification covers the local simulation. This re-audit reran all 20 model tests; the browser walkthrough evidence for top/regular bids, tiered settlement, unrevealed claim labels and refund withdrawal is retained from the 2026-09-06 review. No fresh browser walkthrough or live wallet/RPC integration is claimed for this re-audit.

Build: Solidity **0.8.28**, legacy pipeline (`via_ir = false`), **Cancun**, optimizer enabled with **200 runs**, `bytecode_hash = "none"`. Tools: Foundry **1.7.1**, forge-std **1.11.0**, Slither **0.11.5**, OpenZeppelin Contracts **5.5.0**. Tests ran locally on macOS ARM64 and an isolated Anvil chain. The included Linux CI workflow has been configured; a hosted CI run is not claimed here. No public-chain deployment was performed.

## Results

| Check | Observed result |
|---|---|
| Solidity tests, including deployment tests and invariant suites | **111 passed, 0 failed, 0 skipped** |
| Frontend model tests | **20 passed**, including both pricing tiers, 90+10 allocation, 24-hour duration, final-rank IDs, refunds and uncapped extensions |
| Stateless fuzzing | **10,000 cases per fuzz test**, four fuzz tests |
| Auction-at-capacity invariant campaign | **1,000 runs × 256 calls = 256,000 calls**, zero reverts |
| Growing-auction invariant campaign | **1,000 runs × 256 calls = 256,000 calls**, zero reverts |
| Marketplace invariant campaign | **1,000 runs × 256 calls = 256,000 calls**, zero reverts |
| Invariant lifecycle completion | Every run settles/drains auction or market entitlements |
| Invariant/fuzz seed | `0x20260907` for the extended run |
| Production instrumented line/statement/branch/function coverage | **100% for each of the three contracts** |
| Intentional security mutations | **56/56 detected by failing tests**; compilation failures do not count as detection |
| Native runner regression tests | **2 passed**, including nonzero-exit propagation |
| Audit gate regression tests | **7 passed**, including source drift, new findings and incomplete coverage |
| Slither | **101 detectors**, 14 reviewed warnings, **0 unreviewed findings** |
| Local deployment and lifecycle | Passed: atomic construction, 92 bids, 90 auction NFTs plus 10 reserved NFTs with verified ownership/per-token URLs, 5% cutoff, 30 late increases beyond two hours, settlement at the extended deadline, zero auction royalties, two resales, payout handover, reserved claims before and after rotation, exact tiered proceeds/refunds and all legitimate liabilities drained |
| Deployment inspection | Accepted expected bytecode/configuration; rejected wrong royalty rate, unexpected current/pending payout wallets and inconsistent immutable bytecode |

The 768,000 stateful calls are **handler calls**, including valid no-op cases when an operation has no eligible bid/listing/credit or pending nomination. They are not claimed to be 768,000 successful state-changing on-chain transactions. Auction handlers compare each state against an independently sorted array of model amounts, owners and refunds. Market handlers independently track every token owner, transfer nonce and token-specific approval, plus balances, listings, collection approvals, seller credits and the royalty pool. Auction campaigns additionally interleave reserved NFT claims with bidding and wallet rotation, independently model reserved owners/counts, then settle both price tiers and drain all 100 mint entitlements. All three campaigns independently model current and pending payout wallets while exercising nomination, replacement, acceptance and cancellation. Invariant campaigns run with `fail_on_revert = true`; unexpected reverts fail the campaign.

Coverage is compiler-instrumented coverage of production source, not a claim that all combinations of conditions or reachable EVM states have been exhaustively enumerated. Deployment script runtime paths are additionally exercised by a real local broadcast. Full logs and LCOV are generated under `audit/generated/` and `lcov.info`; the compact final evidence snapshot is `results.json`. That snapshot pins the generated evidence by SHA-256, including formatting, runner and audit-gate regression logs. The source manifest includes this report, the snapshot and the exact static-review decisions; generated evidence remains local build output.

Both auction campaigns independently model the minimum bid and rolling deadline as time advances, then settle at the modeled deadline. The marketplace campaign advances time through listing expiries. The additional ordering fuzz test interleaves claims, credits and withdrawals after proceeds have already been withdrawn. The four callback tests cover a resale during minting, complete rollback on a later rejected mint, payout acceptance during a sale, and complete rollback of that acceptance on a rejected sale.

## Threats exercised

- Ranking insertion/removal at head, middle and tail; ascending/descending order; deterministic ties and increases; 0, 1, 89, 90 and oversubscribed allocations; one wallet winning all 90 auction places.
- Exact start/end/extension/expiry boundaries; rank-preserving versus rank-changing increases; five-minute anti-sniping continuing beyond four hours; uint256 deadline extensions beyond the uint64 initial timestamp range.
- Reserve and minimum increment rounding at one wei; bid narrowing and addition overflow; full-precision royalties at `uint256.max`; maximum representable fully allocated bids.
- Shared payout authorization, unauthorized mint/refund redirection, forced mint delivery, token-specific and collection-wide approvals, all ERC-721 transfer bypasses, lost-list membership and duplicate claims.
- Nomination, cancellation, replacement, repeated acceptance cycles, stale/former-wallet revocation, invalid system-wallet addresses, rotation during bidding, accrued/future payouts, and separation of personal seller/bidder entitlements from business revenue.
- ETH-rejecting and NFT-rejecting contracts, retry and recipient redirection, refunds independent from delivery, reentrant receiver callbacks and exact guard error verification.
- Solvency before and after eviction/settlement/credit/withdrawal, payouts before mint claims, forced ETH, empty auctions and unsold allocation.
- Zero auction royalty even at a 100% trading rate; exact secondary consideration, 100% trading royalty, payout wallet also seller/bidder, one-wei royalty, individual NFT sales, cancelled/expired/stale/overlapping listings, returned ownership and self-purchase, revoked approval, and receiver failure rollback.
- ERC-721 and metadata interface identification, name/symbol/per-token URI, ID bounds, duplicate/unauthorized minting, rank allocation independent of claim order, safe-mint receiver checks on every NFT and atomic rollback if a later NFT is rejected.
- Actual optimized deployment size, receipt success, nested contract bindings, code/configuration inspection and complete post-sale cleanup.

## Findings and fixes

| ID | Finding | Resolution / evidence |
|---|---|---|
| F-01 | Upstream Foundry 1.7.1 npm JavaScript wrapper can exit successfully despite a failing native test process, making CI unreliable. | Runner resolves and executes the native platform binary directly and propagates its exit status. Regression test asserts an invalid native command exits 2. The initially failing contract test was observed before the fix; failures now propagate. |
| F-02 | The initial test's expected revert was consumed by a getter used in its transaction arguments. | Evaluate the minimum increment first, then install caller/revert expectations. The authorization and minimum-increase tests now exercise the intended transaction. |
| F-03 | Deployment tests mutated process-global environment values, causing interference between test cases. | Separate environment loading from typed configuration validation. All invalid-configuration tests use isolated contract state; only one test owns the environment-loading path. Real script broadcast also verified. |
| F-04 | Batch refund/token claims repeatedly wrote aggregate storage counters. | Accumulate refund totals and apply aggregate writes once; increment aggregate claimed count once before mint. Production coverage, model invariants and gas measurement verify the result. |
| F-05 | A bytecode checker that masks immutable slots without checking their repeated copies could accept inconsistent immutable bytecode. | Verify all copies of each compiler-designated immutable agree, then check every immutable binding/value against expected configuration. Anvil bytecode corruption regression verifies rejection. |
| F-06 | Reading live liabilities and ETH balances at different blocks could produce a false solvency alarm during withdrawals. | Deployment inspection pins all state/code reads to one block and checks the block hash again before reporting success. |
| F-07 | The earlier local prototype had separate immutable payout addresses and deducted royalties from auction revenue, contrary to the revised business requirement. | Replaced them with one two-step payout role, credited full auction revenue to proceeds, and separated marketplace royalties from personal seller credits. Fourteen focused wallet tests, all three model campaigns, mutation tests and the real deployment rehearsal cover the new policy. This was a requested policy change, not an exploitable vulnerability. |
| F-08 | A third party could force delivery of a winner's NFTs before the winner redirected the mint; strict trading transfers made that choice irreversible without a resale (historical review L-01). | Only the original winning bidder may call `claimTokens`. A regression test checks that a third-party delivery fails and the winner can then redirect. A dedicated mutation restores the former permissionless delivery rule and must fail tests; the Anvil rehearsal also rejects forced delivery. |
| F-09 | The requested 5% new-bid cutoff and removal of the two-hour extension limit change bidding policy. Simply removing the limit while retaining narrowed extension timestamps could wrap a late deadline. | Uses 500 basis points, removes the hard-end state and getter, and stores/emits extended deadlines as uint256. Tests reject the former 2.5% threshold, enforce exact rounding, extend beyond four hours and the uint64 boundary, and settle at the current deadline. Mutations restore both former rules and timestamp narrowing. The local rehearsal continues 30 late rank-changing increases beyond two hours. |
| F-10 | Moving from fungible ERC-1155 edition balances to individually owned ERC-721 NFTs requires stable token allocation, per-token receiver checks and protection against stale listings after ownership returns. | Settlement fixes IDs by final rank; unsold mints cannot consume reserved winning IDs. Every NFT uses safe minting, with full-batch rollback on rejection. Marketplace listings include a transfer nonce advanced even on self-transfer. Added focused regressions, an independent per-token model, ten additional mutations and a 100-ID ownership/metadata deployment rehearsal. This is the requested token-standard migration; no public deployment was changed. |
| F-11 | The interim on-chain owner-reveal prototype was superseded by the latest off-chain metadata requirement. | Removed its reveal functions, state, events and authority. Each ID now has a fixed endpoint, initially serving unrevealed content via the metadata host. Tests reject legacy reveal calls and verify distinct URLs for auction and reserved IDs. Backend authentication, release policy, mutable content and listing/cache effects are explicitly outside the contract boundary. This is a design revision, not a claim that the former feature was exploitable. |
| F-12 | The final 90-auction/10-reserved allocation and full-top-bid pricing require separate inventory and accounting. Reusing the former uniform gross/refund formulas would mischarge the top winner or overstate liabilities. | Updated proceeds and individual winner costs together; empty and single-winner cases are explicit. Fixed the initial duration to 24 hours. Ten focused allocation/tier tests, three metadata tests, independent reserve inventory modeling, 56 mutations and the full deployment rehearsal cover rank pricing, tie priority, partial reserved claims, failed receiver rollback, payout rotation and the 100-token lifetime cap. Removed obsolete END_TIME and reveal inputs/calls from deployment checks and demo. |

F-02 and F-03 were test-harness defects; F-04 was a gas-efficiency improvement. F-05 was addressed while implementing the deployment checker and exercised with an explicit negative test. None is an unresolved production-contract finding.

Adaptation hardening includes checked amount narrowing, checked ID increments, ceiling bid increments, hint-independent tie priority, pull-only displacements, independent token/refund claims, bidder-only mint delivery, immutable deployment bindings and auction parameters, bounded payout authority, and royalty enforcement on all underlying NFT transfer paths. These are design differences from the reference, not claims that the reference was independently audited or exploitable in a deployed setting. `REVIEW.md` preserves an earlier review of the superseded prototype; it does not independently certify this revision.

## Static findings disposition

The raw Slither report is preserved; detectors have not been globally suppressed to produce a misleading zero-warning result. The gate checks exact finding IDs and production source hashes. Changed source or a changed finding set requires a new explicit review.

| Detector | Count | Disposition |
|---|---:|---|
| `arbitrary-send-eth` | 1 | False positive. `_send` is private; callers debit only caller-owned refunds or authenticate the current shared payout wallet. Redirection applies only to that entitlement, after its debit and under a reentrancy guard. |
| `uninitialized-local` | 1 | False positive. `credited` is a local uint256, zero-initialized by Solidity; it is not a storage reference. |
| `unused-return` | 2 | Intentional. Market fills use the royalty amount to fund the shared royalty pool; withdrawal resolves the current recipient with a zero-price query and uses the accounted pool amount. Neither path needs both return values. |
| `timestamp` | 6 | Intentional auction/listing deadlines, with explicit tested boundaries and uncapped rolling extensions. Timestamp is not randomness; extension arithmetic uses uint256. |
| `costly-loop` | 1 | Intentional per-NFT supply accounting in a batch bounded by the remaining 100-token lifetime cap. The count is updated before each receiver callback; auction-only minting and guarded claim entry points prevent reentrant supply consumption. Failure rolls back the batch; receipt gas and rejecting-receiver regressions cover this path. |
| `low-level-calls` | 3 | Intentional auction, seller and royalty pull-payment sends after effects, guarded against reentrancy, with failures reverting the entitlement debit. |

The arbitrary-send warning is labeled High by Slither; it is **not** omitted or presented as a remaining High-severity vulnerability. Its authorization paths were reviewed and covered by theft mutations/tests. Detailed per-finding reasons and IDs are in `slither-reviewed.json`.

## Compiler and dependency review

The current [Solidity known-bugs list](https://docs.soliditylang.org/en/latest/bugs.html) was checked against the build. SOL-2026-1 and SOL-2026-2 require the IR pipeline, which is disabled; the production contracts also contain no transient-variable deletion or mutually recursive internal functions. SOL-2025-1 requires storage arrays crossing the end of storage; this system uses ordinary layouts with no custom near-boundary placement or storage-array resizing at that boundary. SOL-2026-3 starts with compiler 0.8.29, after the pinned version. No applicable compiler issue was identified for this build. Reassess this conclusion if compiler settings or source change.

The [OpenZeppelin advisory listing](https://github.com/OpenZeppelin/openzeppelin-contracts/security/advisories) was also consulted. The production dependency surface is ERC-721, royalty interface, persistent ReentrancyGuard and supporting math/storage utilities; the listed Bytes search, Base64, multicall, forwarding, governance, ERC721Consecutive and signature modules are not used by this system. Vendoring the entire library does not mean every unused module was audited here.

## Measured transaction costs and sizes

Optimized Anvil receipts, with separate transactions and normal cold storage costs:

| Operation | Gas used |
|---|---:|
| Atomic deployment of all three contracts | 4,826,220 |
| Worst observed new bid while filling the list | 590,731 |
| Settlement with 90 winners | 772,183 |
| Aggregate claim of 88 ERC-721 NFTs | 3,303,806 |
| Secondary purchase | 182,611 |

Wallet acceptance used **30,723 gas**. The local auction closed **8,970 seconds after its original deadline** following 30 qualifying late increases.

Runtime/initcode sizes in bytes: auction **9,706 / 23,107**, edition **6,129 / 11,952**, marketplace **4,507 / 4,654**. The local rehearsal fails if deployment exceeds 6M gas, observed bid cost exceeds 1.5M, settlement exceeds 2M, or the 88-NFT claim exceeds 5M. Settlement now includes up to 90 token-ID assignments, and ERC-721 batch claims perform a separate mint and receiver check per NFT. Costs are observations under this compiler/EVM, not fixed gas quotes for every recipient or network condition. A malicious receiver can consume gas in its own reverting claim without blocking another user's claim or settlement.

Reserved claims of four and six NFTs used **187,705** and **218,657 gas**, respectively.

## Residual assumptions and limits

Strict royalty transfers deliberately exclude direct free gifts and third-party marketplace transfers of the underlying NFT. Royalties apply to declared on-chain ETH consideration in the included marketplace; off-chain side payments, underreported prices, private key sales and secondary disposition of mint claims cannot be prevented. A compatible custody or wrapper contract can also receive a mint directly and transfer control or economic interests while retaining the underlying NFT, so that transfer of interests triggers no royalty here. Regular-tier uniform-price demand reduction, bid shading, transaction ordering, Sybil participation and self-outbidding remain possible economic behaviors. The starting reserve should be acceptable under underallocation.

There is no guaranteed latest closing time: qualifying late bids can continue extending the deadline. Active bids remain committed throughout those extensions; displaced bids remain immediately refundable. A rank-preserving increase does not extend the deadline. These are the requested auction rules, not settlement or refund failures.

The system cannot repair incorrect immutable configuration or lost bidder keys. Payout rotation requires a nomination by the current wallet and acceptance by its replacement; a nomination can be cancelled or replaced before acceptance. There is no separate recovery role if the current key is lost before a usable nomination. Accepted rotation changes control of unwithdrawn auction proceeds, trading royalties and unclaimed reserved/unsold NFTs; previously withdrawn funds and personal entitlements remain owned by their original wallets. Off-chain metadata has no on-chain content commitment or enforced reveal timing. The host can change or reveal contents independently of the NFT owner, and can become unavailable. The planned creator-enabled holder requests need a separately secured service; contract payout rotation does not migrate its credentials. Metadata changes do not invalidate market listings or emit refresh events. The creator must maintain the fixed endpoint and should coordinate listing cancellation/cache updates with reveals. A winning contract wallet must be able to call the refund and mint-redirection functions. Unclaimed winning units remain reserved indefinitely. Forced surplus has no withdrawal path. External wallet, node, explorer, signer, frontend, chain-consensus and MEV infrastructure were not independently audited.

There are no known unresolved defects in the reviewed implementation at this snapshot. Finite testing and self-review cannot guarantee an absence of all defects; before a public launch, review the immutable business parameters and obtain independent review appropriate to the funds at risk.
