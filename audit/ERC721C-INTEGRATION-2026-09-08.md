# ERC721-C / OpenSea integration review — 2026-09-08

**Version 4.0.0: targeted verification passed; a full audit is not claimed.** The creator cancelled the running non-mutation audit and other LNTV mutation/test jobs to prioritize this migration. The cancelled 3.3.0 evidence is preserved in `history/2026-09-08-nonmutation-cancelled/`.

## Implementation

`AuctionEdition` directly inherits the unmodified upstream Limit Break `ERC721C` implementation. Its transitive source closure is pinned and hash-verified: 10 Limit Break files, 10 files from its upstream-pinned OpenZeppelin 4.8.3 dependency, and PermitC's constants file. This package's OpenZeppelin 5.5.0 utilities remain separately namespaced. `NOTICE.md` records exact revisions and licenses.

The old custom-market-only transfer and approval overrides are removed. Standard approvals now work, while ERC721-C transfer hooks call the configured validator. The existing marketplace is an optional royalty-enforcing venue. Auction, marketplace and token-rescue production source are byte-for-byte unchanged from `737cbd7`; only `AuctionEdition.sol` changed in production.

The current payout wallet configures the documented OpenSea registry/SignedZone profile atomically using `configureEnforcedTrading`. It copies the registry's curated list, includes the optional local market, and selects level 4. Transfers before configuration or with a zero/no-code validator fail closed. Mint claims remain separate. `owner()` uses the existing payout role; `contractURI()` and `ContractURIUpdated` supply collection metadata discovery. External transfers update local listing nonces.

## Verification performed

| Check | Result |
|---|---|
| Bounded Solidity regression suite | **217 passed, 0 failed**, eight fuzz tests at 128 runs; seed `0x2026090840` |
| OpenSea-specific subset | **16 passed** using verified Seaport/conduit runtimes and unmodified verified SignedZone/registry source |
| Short stateful smoke | **3 passed**, 16 runs × 32 depth each; 1,536 generated actions |
| Local deployment/lifecycle | **PASS**, including actual payout-wallet trading-configuration script and strict-policy readiness checker |
| Metadata/rescue rehearsal | **PASS**, all three foreign token types on all three contracts; 21 rejected transactions; no residual ETH liabilities |
| Formatting, clean optimized build, interface 4.0.0 | **PASS** |
| Vendored implementation integrity | **PASS**, all 21 added upstream Solidity files match their pinned manifests |
| Extended audit / mutation campaign | **Not run for 4.0.0**; cancelled work is historical |

Seaport tests exercise both direct and OpenSea-conduit ETH listings and ERC20-priced offer acceptance. They verify creator/seller payments of 10%/90%, rejected missing/fake/expired/mismatched authorizations, royalty-removal and token-substitution attempts, replay, cleared authorization, and invalidation of a local listing even after the NFT returns to the original seller. An explicitly named fixture demonstrates another royalty-aware marketplace through the registry; it does not certify a particular live third-party venue.

The royalty attestation is produced by a **local test signer**. This proves contract/protocol interoperability, not a live OpenSea API signature or Studio configuration. The registry and SignedZone fixtures are source-level reproductions; Seaport and the tested conduit use the exact public verified runtimes. There is no public deployment in `deployments/networks.json`.

Deployment for the local rehearsal consumed **6,823,539 gas**. Runtime sizes: auction 11,973 bytes, edition 11,484, optional marketplace 5,944. All are below EIP-170; the auction initcode is 32,525 bytes, below EIP-3860. The deployment gas guard was updated to 7.5 million to cover the measured ERC721-C deployment while remaining below the local transaction limit of 8 million.

## Trust and remaining release work

This uses the upstream standard's trusted creator-token administration. The payout wallet can change validator/policy and enable automatic validator approval; a malicious nonzero validator or unsafe operator policy could weaken enforcement or transfer safety. Automatic approval starts disabled. A zero/missing validator blocks this edition rather than opening transfers. Curated processors and OpenSea's authorization signer are external trust dependencies. No administrator-proof immutable royalty claim is made.

Before live trading, deploy/verify the new contracts, configure the registry, enable **10% enforced earnings** for the correct wallet in **OpenSea Studio**, recheck the final on-chain policy and perform a public-testnet listing, purchase and offer acceptance with real API fulfillment data. Other venues need compatible enforcement and their own required settings. On payout rotation, update marketplace settings and invalidate affected signed orders; on-chain ERC-2981 cannot rewrite their fee recipient. The [runbook](../docs/OPENSEA.md) gives the sequence.

The High finding **“payout wallet can confiscate all bidder refunds”** remains **accepted by design**, unchanged: optional recovery only 28 days after first successful settlement, and refunds close only when recovery succeeds. The accepted extension rules are also unchanged. No frontend files, public deployment or default-branch merge were performed.

The audit harness's omitted-source coverage/static-review inventory gap (A33-01) was fixed before cancellation and its ten harness tests passed on that snapshot. The current complete static/coverage/extended audit must still be refreshed for ERC721-C. Mutation inventory and evidence remain historical and are not claimed to cover this source. `SHA256SUMS` records file integrity, not an audit verdict.

Evidence: [results](results.json), [regression tests](generated/erc721c-400/regression-tests.log), [protocol tests](generated/erc721c-400/opensea-tests.log), [invariant smoke](generated/erc721c-400/invariant-smoke.log), [local rehearsal](generated/erc721c-400/local-e2e.json).
