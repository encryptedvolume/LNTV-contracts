# LNTV contracts

A self-contained Ethereum system for **100 ERC-721 NFTs: 90 auctioned and 10 reserved**. Final auction rank assigns IDs **1–90**. The top bid receives rarest NFT **#1 and pays its full bid**. Other winners pay the cutoff price and can withdraw their excess. A wallet may win multiple NFTs through separate bids. IDs **91–100** belong to the shared creator payout/royalty wallet's reserved allocation and never occupy auction places.

The [current issue register](audit/ISSUES.md) records open work, accepted design decisions, verified fixes and the scope of available audit evidence.

The current source release is **4.0.1**, which fixes validator auto-approval seizure (F4-01). [Earlier contract versions](docs/VERSIONS.md) are preserved under annotated archive tags.

Ranked-list mechanics are adapted from [Transient Labs TLRankedAuction](https://github.com/Transient-Labs/tl-ranked-auction/tree/4dd148d9fcfa4c96454393d1e8272e6e997dbf7c). The reference source and MIT attribution are included. Tiered pricing, reserved inventory and minting are this adaptation's design; creator-token transfer enforcement uses Limit Break's existing ERC721-C implementation.

The initial auction lasts exactly **48 hours**. Qualifying late bids leave ten minutes on the clock, without a total extension cap. Contract code, supply, reserve, start, collection name/symbol and trading royalty rate are fixed. The shared payout wallet can be changed through nomination and acceptance. That wallet can update the metadata base and rescue foreign tokens held by the contracts. There is no proxy, pause, cancellation, arbitrary execution or early ETH recovery role. Refunds remain available until the current payout wallet successfully recovers the remaining auction ETH. Recovery is optional and becomes available 28 days after settlement. The deployer has no separate authority; set `PAYOUT_WALLET` to the deployer if it should own that role.

## Auction rules

| Rule | Behavior |
|---|---|
| Total supply | 100 lifetime ERC-721 mints |
| Auction allocation | 90 places, IDs 1–90 by final rank, independent of claim order |
| Creator allocation | 10 NFTs, IDs 91–100; current payout wallet calls `claimReserved` before, during or after bidding |
| First-place price | Full amount of the highest-ranked bid; no overpayment refund for that bid |
| Other winners' price | 90th winning bid when full, otherwise reserve |
| Metadata/reveal | Admin-updatable base with per-token off-chain URLs; initially unrevealed content and later reveal policy managed by the metadata service |
| Payment | Native ETH, one fully escrowed bid per NFT |
| Multiple wins | `createBids(amounts)` for 1–90 bids in one transaction, or repeat `createBid()`; no wallet cap or allowlist |
| Batch funding | Exact sum of individual amounts; updated minimum checked after each bid; any failure reverts the whole batch |
| Ranking | Amount descending, original bid ID ascending for ties |
| Before 90 active bids | New bid must meet reserve |
| At capacity | New bid must meet floor + 5%, rounded up to a wei |
| Increase | Bidder adds at least 2.5% of its own active bid, rounded up |
| Displacement | Full payment immediately credited for withdrawal |
| Initial interval | `startTime` through `startTime + 48 hours`, end exclusive |
| Extensions | New bids and rank-changing increases inside the final ten minutes reset remaining time to ten minutes; uncapped |
| Settlement | Anyone after the current end; no recipient callbacks |
| Winners | Claim tokens separately from crediting/withdrawing refunds |
| Refund availability | Credit and withdraw until a successful creator recovery; no automatic time expiry |
| Unclaimed auction ETH | Current payout wallet may recover it at/after `settledAt + 28 days`; success closes refunds while NFT claims remain available |
| Unsold auction NFTs | Current payout wallet may claim unallocated IDs up to #90 after settlement |
| Auction royalties | None; all tiered sale revenue becomes auction proceeds |
| Shared payout wallet | Two-step replacement controls unwithdrawn business revenue and unclaimed creator inventory |
| NFT claim expiry | None |

Tokens mint on successful claims. Reserved NFTs are an entitlement of the configured wallet; they are not automatically minted during deployment. Claiming all auction, unsold and reserved entitlements reaches exactly 100 lifetime mints.

The creator confirmed uncapped extensions and floor increases without an extension when rank stays unchanged as accepted design on 2026-09-07. Active bids remain committed during extensions, and a late floor increase can change regular winners' final price. See the [recorded decisions and audit finding dispositions](audit/DESIGN-DECISIONS-2026-09-07.md).

## Royalty policy

The edition now inherits **Limit Break ERC721-C**, with ERC-2981 reporting the confirmed **10%** trading royalty and current shared payout wallet. Standard ERC-721 marketplace approvals are supported. The old exclusive-marketplace transfer restriction has been removed; the included `RoyaltyMarketplace` is optional. Version 4.0.1 requires explicit holder approvals for operators: the creator cannot manufacture approval by changing the validator or its auto-approval flag. See [the security fix and verification](audit/HOLDER-APPROVAL-FIX-2026-09-08.md).

Before secondary trading, the payout wallet calls `configureEnforcedTrading()` (or runs `script/ConfigureTrading.s.sol`) and enables **10% enforced earnings in OpenSea Studio**. The contract configures OpenSea's supported transfer validator and SignedZone, with strict level-4 transfer rules. Other marketplaces work when they support that enforcement system and their required royalty settings are configured. Ordinary transfers remain blocked under that profile. There are no royalties on the initial auction.

ERC721-C enforcement depends on the configured validator, trusted payment processors and OpenSea's signed fulfillment service. Creator-token administration remains trusted; the owner can change registry settings. A zero/missing validator cannot silently unlock this edition. The royalty rate is immutable, while `royaltyInfo()` and `owner()` follow the auction's two-step wallet rotation. OpenSea settings and already-signed external orders need separate handling when the payout wallet changes.

Read [OpenSea setup, compatibility, administration and verification limits](docs/OPENSEA.md) before deployment. This repository contains tested contract integration, not a live OpenSea collection. Existing immutable deployments require redeployment.

## Off-chain metadata and reveal

Deploy with a base URL ending in `/`, for example `https://metadata.example/collection/`. NFT #1 resolves to `<base>1.json`, and #100 to `<base>100.json`. `tokenURI` requires a minted token; the public `metadataURI` getter exposes the base before minting. The current payout wallet can call `edition.setMetadataURI(newBase)` at any time, before or after minting. The replacement must be nonempty and end in `/`; it applies to every token and emits `MetadataURIUpdated` plus ERC-4906 `BatchMetadataUpdate(1, 100)`. The admin can change artwork/rarity by changing this base; metadata is not immutable. The contract assigns rank to ID; the metadata service supplies rarity and artwork.

Serve unrevealed placeholder JSON for **all 100 endpoints**, including reserved IDs, initially. Later, the metadata service can enable owner-requested reveals at the creator's discretion and return revealed JSON for selected IDs. There is **no on-chain reveal function, reveal flag or activation transaction**. The metadata service and its authenticated reveal API are separate work; this package does not implement or certify that backend. For mutable off-chain reveals, use a stable HTTPS service or another mutable resolver; a fixed IPFS directory cannot later change its contents.

The host controls metadata contents and availability; on-chain ownership and payout-wallet rotation do not by themselves change hosting credentials or enforce reveal permissions. Metadata updates also do not invalidate marketplace listings. Cancel affected listings before changing the content offered for sale. Calling `setMetadataURI` with the same base also emits a refresh event for off-chain content changes; indexer cache refresh is not guaranteed. Hosting-only changes do not emit events automatically.

## Build and verify

Requires Node 22+, Python 3.10+, and a supported Foundry platform. Solidity 0.8.28, Cancun EVM, OpenZeppelin 5.5.0, forge-std 1.11.0, and Foundry 1.7.1 are pinned. ERC721-C uses the unmodified Limit Break implementation and its separately namespaced, upstream-pinned OpenZeppelin 4.8.3/PermitC dependencies; see `NOTICE.md`. Solidity dependencies are vendored; no Git submodules are needed.

```bash
cd LNTV-contracts
npm ci
npm run build
npm test
python3 -m venv .venv
.venv/bin/pip install -r requirements-audit.txt
npm run audit
```

`npm run audit` runs formatting, native-runner and mutation-runner regression tests, Slither with an exact reviewed-findings gate, production coverage, the extended fuzz/invariant suite, 90 intentional security mutations in an isolated copy, bytecode size checks, and a complete deployment/bidding/claims/resale/wallet-rotation rehearsal on a temporary local Anvil. It exits unsuccessfully on any failing gate. Local Anvil is shut down afterward. Reports are written to `audit/generated/`.

The mutation campaign first requires the unmodified contracts to pass the same test selection and fixed seed. Each mutation must then fail at least two behavioral tests; configuration-only checks, compiler errors, setup failures, skipped tests and changed test inventories cannot satisfy that requirement. Explicit scenarios are required for the previously weak cases, including bidding at hour 47 and rejecting settlement at hour 24. The runner retains native Forge JSON, named test failures and input hashes. Use `python scripts/mutation_audit.py --output-dir <directory>` inside the audit virtual environment to retain a separate campaign without overwriting earlier evidence.

The runner prints its fuzz seed. Use `AUDIT_FUZZ_SEED=0x20260907 npm run audit` to run the current source with the 2026-09-07 re-audit seed; the default remains `0x20260906`. Stateful campaigns advance auction time and marketplace time, and independently check the auction deadline and minimum bid. Additional tests exercise callbacks across contracts, randomized claim/refund ordering, and batch equivalence to sequential bids. Both auction invariant campaigns mix batch bidding into their independent ranking and ETH model.

Interface **4.0.1** retains ERC721-C/OpenSea support and fixes creator-controlled validator auto-approval. The [fix report](audit/HOLDER-APPROVAL-FIX-2026-09-08.md) records 229 passing default-profile tests, static review and local lifecycle checks. The full extended audit and coverage were not rerun for this patch, and mutations remain excluded. Earlier integration reviews and Fable's fourth pass attest their named snapshots, not an automatic full-audit PASS for the changed source. `npm run audit:nonmutation` excludes mutations. See [ISSUES.md](audit/ISSUES.md) for remaining work.

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
| `src/TokenRescue.sol` | Shared non-ETH foreign-token rescue controlled by the current payout wallet |
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

The frontend lives in [fxckcomputer/LNTV](https://github.com/fxckcomputer/LNTV). Its sample bidding page remains an in-memory simulation. No public-chain deployment has been performed.

## Frontend interface

Run `npm run interface:export` to compile and generate the versioned `interface/` files: browser-compatible ESM ABIs, TypeScript declarations, deployment addresses and a SHA-256 manifest. `npm run interface:check` checks that committed exports match a fresh build. No npm registry publication is required. See [interface integration](docs/FRONTEND.md) and [repository migration](docs/REPOSITORY-SPLIT.md).
