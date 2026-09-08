# Admin metadata and foreign-token recovery — 2026-09-08

Interface **3.3.0** adds the creator-requested admin functions. The creator explicitly requested these additions without running the full suite. The current shared payout wallet is the admin, and accepted wallet rotation immediately moves these permissions on all three contracts.

## Changes

- `AuctionEdition.setMetadataURI(string)` changes the base used by all minted and future token IDs. It rejects an empty base or one without a trailing `/`. The admin can change artwork and rarity metadata; this is no longer a fixed-base collection.
- `MetadataURIUpdated` records old/new bases, while ERC-4906 `BatchMetadataUpdate(1, 100)` announces refresh. The same base can be submitted to announce updated off-chain content. The setter does not implement holder reveals, change token ownership or invalidate marketplace listings.
- `rescueERC20`, `rescueERC721` and `rescueERC1155` are available on the auction, edition and marketplace through a shared `TokenRescue` base. They transfer only foreign tokens held by the called contract, are nonpayable and reentrancy guarded, and expose no approvals or arbitrary calls. ERC-20 uses OpenZeppelin SafeERC20; NFT transfers check recipient acceptance.
- Every rescue method rejects the LNTV edition token address, preserving royalty enforcement. Token recovery cannot touch unminted winning/reserved/unsold entitlements. No receiver hooks are added for new deposits.
- Auction bidding, settlement, ETH accounting and refund recovery behavior are unchanged. The **High — payout wallet can confiscate all bidder refunds** finding is explicitly **accepted by design**, with the protected interval measured from **first successful settlement plus 28 days**. See [the creator decision](REFUND-RECOVERY-DESIGN-2026-09-08.md).
- Deployment checks recognize ERC-4906. Configuration parameters stay the same; later inspections require the current expected metadata URI. Interface provenance now includes `src/TokenRescue.sol`. Frontend code and wording are unchanged.

## Focused verification

| Check | Result |
|---|---|
| `forge test --match-contract 'AdminFeaturesTest\|MetadataTest' -vv` | **14 passed**, 0 failed, 0 skipped (11 new admin tests, 3 metadata tests) |
| `npm run build` | Passed; optimized deployed/init bytecode within limits |
| Auction runtime / init bytes | 11,973 / 29,098 |
| Edition runtime / init bytes | 8,336 / 15,668 |
| Marketplace runtime / init bytes | 5,944 / 6,105 |
| `npm run interface:export` / `interface:check` | Passed, 3.3.0; all new functions/events present |
| `npm run format:check` / `git diff --check` | Passed |

Tests cover metadata updates before/after minting, invalid input, non-admin and pending/old-wallet rejection, accepted rotation, all three token types across all three contracts, partial balances, own-collection exclusion, no-return/false-return ERC-20s, insufficient balance, rejecting NFT receivers, third-party ownership, reentrancy by the admin recipient, ETH payment rejection and preserved auction ETH/refund accounting. A test name initially matched Forge's removed `testFail*` convention; it was renamed before the successful run. No production defect was found by these focused checks.

Logs: [focused tests](generated/admin-focused.log), [build](generated/admin-build.log), [interface](generated/admin-interface.log), [format](generated/admin-format.log). Existing compiler/lint warnings about timestamps, checked casts and the test-only forced-ETH helper remain; these logs are not a new static audit disposition.

## Audit scope and handoff

**Focused checks passed; no full-audit PASS is claimed.** Full tests, fuzzing, invariants, coverage, Slither, mutation testing and a public/local-chain lifecycle rehearsal were not rerun for this addition. The source-pinned Slither approval still refers to the previous revision and intentionally rejects changed source until the reviewer refreshes it. Audit gates were not weakened or rewritten to approve unreviewed changes. The intended push uses `[skip ci]` so the workflow does not launch a full audit for this creator-waived run.

The next independent review should cover the new shared external-token call surface, mutable metadata authority and inherited guard, then refresh static findings, coverage and evidence as appropriate. Prior 3.2.0 results and hash manifest are preserved in `history/2026-09-08-pre-admin-*`; its 187-test/coverage results and the older mutation evidence do not attest this revision. The current `results.json` records only these focused checks. `SHA256SUMS` is an integrity manifest, not an assertion of full test coverage.

No contract was deployed by this task. Existing non-upgradeable deployments need a new deployment to obtain these functions. The source, exports, documentation and focused evidence are prepared for the existing contracts PR; the creator will obtain Claude's independent review.
