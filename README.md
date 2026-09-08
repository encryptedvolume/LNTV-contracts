# Ranked edition auction

A self-contained Ethereum system for **100 ERC-721 NFTs: 90 auctioned and 10 reserved**. Final auction rank assigns IDs **1–90**. The top bid receives rarest NFT **#1 and pays its full bid**. Other winners pay the cutoff price and can withdraw their excess. A wallet may win multiple NFTs through separate bids. IDs **91–100** belong to the shared creator payout/royalty wallet's reserved allocation and never occupy auction places.

The [current issue register](audit/ISSUES.md) records open work, accepted design decisions, verified fixes and the scope of available audit evidence.

Ranked-list mechanics are adapted from [Transient Labs TLRankedAuction](https://github.com/Transient-Labs/tl-ranked-auction/tree/4dd148d9fcfa4c96454393d1e8272e6e997dbf7c). The reference source and MIT attribution are included. Tiered pricing, reserved inventory, minting and royalty enforcement are this adaptation's design.

The initial auction lasts exactly **24 hours**. Qualifying late bids leave five minutes on the clock, without a total extension cap. Contract code, supply, reserve, start, metadata base URL, collection name/symbol and trading royalty rate are fixed. The shared payout wallet can be changed through nomination and acceptance. There is no proxy, pause, cancellation, arbitrary execution or rescue role. The deployer has no separate authority; set `PAYOUT_WALLET` to the deployer if it should own that role.

## Auction rules

| Rule | Behavior |
|---|---|
| Total supply | 100 lifetime ERC-721 mints |
| Auction allocation | 90 places, IDs 1–90 by final rank, independent of claim order |
| Creator allocation | 10 NFTs, IDs 91–100; current payout wallet calls `claimReserved` before, during or after bidding |
| First-place price | Full amount of the highest-ranked bid; no overpayment refund for that bid |
| Other winners' price | 90th winning bid when full, otherwise reserve |
| Metadata/reveal | Fixed per-token off-chain URL; initially unrevealed content and later reveal policy managed by the metadata service |
| Payment | Native ETH, one fully escrowed bid per NFT |
| Multiple wins | Repeat `createBid()`; no wallet cap or allowlist |
| Ranking | Amount descending, original bid ID ascending for ties |
| Before 90 active bids | New bid must meet reserve |
| At capacity | New bid must meet floor + 5%, rounded up to a wei |
| Increase | Bidder adds at least 2.5% of its own active bid, rounded up |
| Displacement | Full payment immediately credited for withdrawal |
| Initial interval | `startTime` through `startTime + 24 hours`, end exclusive |
| Extensions | New bids and rank-changing increases inside the final five minutes reset remaining time to five minutes; uncapped |
| Settlement | Anyone after the current end; no recipient callbacks |
| Winners | Claim tokens separately from crediting/withdrawing refunds |
| Unsold auction NFTs | Current payout wallet may claim unallocated IDs up to #90 after settlement |
| Auction royalties | None; all tiered sale revenue becomes auction proceeds |
| Shared payout wallet | Two-step replacement controls unwithdrawn business revenue and unclaimed creator inventory |
| Claim expiry | None |

Tokens mint on successful claims. Reserved NFTs are an entitlement of the configured wallet; they are not automatically minted during deployment. Claiming all auction, unsold and reserved entitlements reaches exactly 100 lifetime mints.

The creator confirmed uncapped extensions and floor increases without an extension when rank stays unchanged as accepted design on 2026-09-07. Active bids remain committed during extensions, and a late floor increase can change regular winners' final price. See the [recorded decisions and audit finding dispositions](audit/DESIGN-DECISIONS-2026-09-07.md).

## Royalty policy

**Strict enforcement is enabled permanently.** Direct ERC-721 transfers, both safe-transfer variants, and approvals for other marketplaces are blocked. Owners must approve and use the included `RoyaltyMarketplace` for every secondary transfer. Each listing sells one specified token ID for a fixed ETH price; cancellation, expiry, buyer-selected recipients and separate seller/royalty withdrawals are supported. The seller must own and approve that NFT. Every transfer invalidates prior listings for that NFT, even if it later returns to the same seller. Both token-specific and collection-wide marketplace approvals are supported.

The initial auction charges **no royalty**. Its full tiered sale revenue goes to the shared payout wallet. Only secondary marketplace fills charge the configured royalty on their declared ETH price. Trading royalties round up to the nearest wei; a positive resale never rounds its royalty to zero. The royalty rate cannot change. `AuctionEdition.royaltyRecipient()` and ERC-2981 always report the current shared payout wallet. Marketplace royalties accumulate in a separate pool, so an accepted wallet replacement controls both accrued and future royalties; individual seller credits never move. Rates of 1–10,000 basis points are supported; **7.5% in the examples is an example, not a contract default**.

[ERC-2981](https://eips.ethereum.org/EIPS/eip-2981) only communicates royalty amounts. Enforcement here comes from restricting transfers of the underlying NFT to the included market. Ordinary direct gifts, external-market fills and direct deposits into wrappers/bridges are blocked. A bidder can nevertheless mint directly to a compatible custody or wrapper contract; that contract can transfer control or economic interests without moving the underlying NFT and without triggering this royalty logic. Off-chain payments, sale of wallet keys and deliberately understated prices also remain outside enforcement. Review these product constraints before using the deployment script.

## Off-chain metadata and reveal

Deploy with a base URL ending in `/`, for example `https://metadata.example/collection/`. NFT #1 resolves to `<base>1.json`, and #100 to `<base>100.json`. `tokenURI` requires a minted token; the public `metadataURI` getter exposes the base before minting. The base cannot change after deployment. The contract assigns rank to ID; the metadata service supplies rarity and artwork.

Serve unrevealed placeholder JSON for **all 100 endpoints**, including reserved IDs, initially. Later, the metadata service can enable owner-requested reveals at the creator's discretion and return revealed JSON for selected IDs. There is **no on-chain reveal function, reveal flag, activation transaction or metadata refresh event**. The metadata service and its authenticated reveal API are separate work; this package does not implement or certify that backend. For mutable off-chain reveals, use a stable HTTPS service or another mutable resolver; a fixed IPFS directory cannot later change its contents.

The host controls metadata contents and availability; on-chain ownership and payout-wallet rotation do not by themselves change hosting credentials or enforce reveal permissions. Metadata updates also do not invalidate marketplace listings. Cancel affected listings before changing the content offered for sale, and handle marketplace cache refresh through that service's APIs.

## Build and verify

Requires Node 22+, Python 3.10+, and a supported Foundry platform. Solidity 0.8.28, Cancun EVM, OpenZeppelin 5.5.0, forge-std 1.11.0, and Foundry 1.7.1 are pinned. Solidity dependencies are vendored; no Git submodules are needed.

```bash
cd auction
npm ci
npm run build
npm test
python3 -m venv .venv
.venv/bin/pip install -r requirements-audit.txt
npm run audit
```

`npm run audit` runs formatting, native-runner and mutation-runner regression tests, Slither with an exact reviewed-findings gate, production coverage, the extended fuzz/invariant suite, 57 intentional security mutations in an isolated copy, bytecode size checks, and a complete deployment/bidding/claims/resale/wallet-rotation rehearsal on a temporary local Anvil. It exits unsuccessfully on any failing gate. Local Anvil is shut down afterward. Reports are written to `audit/generated/`.

The mutation campaign first requires the unmodified contracts to pass the same test selection and fixed seed. Each mutation must then fail at least two behavioral tests; configuration-only checks, compiler errors, setup failures, skipped tests and changed test inventories cannot satisfy that requirement. Explicit scenarios are required for the previously weak cases, including bidding at hour 23 and rejecting settlement at hour two. The runner retains native Forge JSON, named test failures and input hashes. Use `python scripts/mutation_audit.py --output-dir <directory>` inside the audit virtual environment to retain a separate campaign without overwriting earlier evidence.

The runner prints its fuzz seed. Use `AUDIT_FUZZ_SEED=0x20260907 npm run audit` to run the current source with the 2026-09-07 re-audit seed; the default remains `0x20260906`. Stateful campaigns advance auction time and marketplace time, and independently check the auction deadline and minimum bid. Additional tests exercise callbacks across contracts and randomized claim/refund ordering.

`audit/REPORT.md`, `audit/REAUDIT-2026-09-07.md`, `audit/results.json` and `audit/SHA256SUMS` describe the earlier 0.5% increase snapshot. The subsequent 2.5% change, timing fix and mutation strengthening have separate verification records linked from [ISSUES.md](audit/ISSUES.md). A combined audit and consolidated evidence refresh for the current tree remains open.

The native tool runner is also available directly:

```bash
node scripts/foundry.mjs forge test --match-contract RankedAuctionTest
node scripts/foundry.mjs cast --help
```

The runner deliberately bypasses the upstream npm JavaScript shim to preserve failing native exit codes. See [ISSUES.md](audit/ISSUES.md) for current status and verification scope, and `audit/REPORT.md` for the historical full-run results; passing tests do not establish that every possible defect has been excluded.

## Contents

| Path | Purpose |
|---|---|
| `src/RankedAuction.sol` | Ranking, bidding, settlement, protected ETH accounting, and mint entitlements |
| `src/AuctionEdition.sol` | ERC-721, ERC-2981, fixed cap, per-token metadata URLs and transfer enforcement |
| `src/RoyaltyMarketplace.sol` | Noncustodial secondary sales with mandatory declared-price royalties |
| `script/Deploy.s.sol` | Validated atomic deployment of the three-contract system |
| `test/` | Unit, fuzz, independent-model invariant, wallet-rotation and adversarial receiver tests |
| `scripts/` | Audit gates, mutation testing, local deployment rehearsal and deployment inspection |
| `docs/ARCHITECTURE.md` | State transitions, accounting invariants, and reference differences |
| `docs/OPERATIONS.md` | Deployment, verification, bidder calls, payouts, and recovery |
| `audit/REPORT.md` | Measured audit results and reviewed findings |
| `audit/ISSUES.md` | Current open work, accepted design decisions, verified fixes and evidence status |
| `audit/REAUDIT-2026-09-07.md` | Repeat manual review, additional adversarial tests and verification scope |
| `audit/MUTATION-STRENGTHENING-2026-09-07.md` | Stronger behavioral mutation coverage, named failure attribution and verification scope |
| `NOTICE.md` | Reference revision, dependency provenance and license notices |

This package is independent of the LNTV sample bidding page, which remains an in-memory simulation. No public-chain deployment has been performed.
