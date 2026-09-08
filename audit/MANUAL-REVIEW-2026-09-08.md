# Manual adversarial review — 4.0.1

Reviewer: Codex. Base commit: `96b473b00922262ccd8209563f2fda0962550712`.
This is a first-party manual review of the implementation, followed by tests;
it is not an independent third-party certification. Final run results and exact
source hashes are recorded in `results.json` and `generated/full-nonmutation-401/`.
The four production Solidity sources are unchanged from the merged 4.0.1 release.

## Method and scope

I read all four production contracts and both deployment scripts, traced their
externally callable functions into the pinned OpenZeppelin ERC721 implementation,
ERC721-C permission/validation mixins, SafeERC20 and ReentrancyGuard, and reviewed
the relevant OpenSea registry/SignedZone and PaymentProcessor royalty paths.
I considered ordinary bidders, dishonest sellers/buyers, malicious token/ETH/NFT
receivers, an old or compromised payout wallet, an untrusted validator, stale
orders, and transaction ordering around phase/recovery boundaries. The following
conclusions come from that reasoning; passing coverage alone is not their basis.

| Surface | Adversarial question and reasoning | Supporting checks |
|---|---|---|
| Construction and binding | Can an attacker substitute the NFT, market or payout getter? The auction creates the edition, which creates its market, in one transaction; immutable links have no replacement entry point. Validator registration during construction is best-effort and cannot mint through absent constructor bytecode. | Constructor/binding tests, runtime/immutable comparison in local rehearsal. |
| Single/batch bids | Can old contract ETH finance a new bid, or can a later bad batch entry leave earlier bids? Exact `msg.value == sum` precedes insertion; each insertion accounts only its input amount, and any later revert rolls back the complete call. The 90-item bound and uint128 per-bid bound make accepted totals safe. | Batch under/overpayment, forced balance, self-displacement, rollback and overflow scenarios. |
| Ranking and top-ups | Can unlink/reinsert corrupt the floor, lose a bidder, or manipulate ties? Insertion orders by descending amount then ascending original ID. Both neighbors are repaired on unlink. A positive increase can only move up; a changed predecessor therefore represents a rank change. | New independently sorted bid-record oracle verifies every forward/backward link, head/tail, count and escrow across middle/tail/head moves and displacement; stateful independent ranking model. |
| Timing | Can a bid arrive after closing or extend through a refund callback? Bidding requires `start <= timestamp < end`, and calls no receivers. `_extend` is called only while live, so subtraction cannot underflow. Same-rank increases do not extend, by the creator's decision. | Exact boundaries, repeated extensions beyond one day, uint64 crossing, default and extended timing fuzz tests. |
| Settlement | Can a hostile receiver block settlement, or can settlement underfund refunds? Settlement has no external calls. At capacity, each regular winner pays at most its own bid; when undersubscribed, reserve is at most every admitted bid. Gross is bounded by escrow. Ranking freezes before token IDs are assigned. | Empty/partial/full books, tied head bids, maximum amounts, stateful settle-and-drain checks. |
| Refunds and proceeds | Can someone claim another wallet's ETH or credit a winner twice? Displaced bids are removed and credited once. Winning overpayments move from escrow to original-bidder credits once, independently of claims. Withdrawals debit before sending and share the auction reentrancy guard. | Duplicate/mixed batches, rejection/retry, callback attempts, forced ETH, separate seller-credit and royalty accounting. |
| Recovery | Can late settlement shorten the protected interval? `settledAt` is assigned only on first successful settlement. Recovery requires settlement and `settledAt + 28 days`; the pre-settlement estimate cannot authorize it. Recovery intentionally confiscates remaining bidder ETH only when its transfer succeeds; a revert restores everything. | Late/atomic settlement-recovery, exact deadline, rejected recipient, repeat forced-surplus recovery and surviving NFT claims. Accepted High design risk retained. |
| Mint claims | Can a callback steal an unclaimed ID, mint twice, or overrun supply? Only the immutable auction can mint. Its claim entry points are guarded and reserve entitlements before the callback. Winning, unsold and reserved ID ranges cannot overlap. A later receiver rejection rolls back earlier nested sales and the whole mint batch. | Mixed-owner claims, rejected multi-mint, cross-contract mint/sale callback and retry, total 100-token allocation. |
| ERC721 permissions | Can creator control become holder approval? The edition now directly reads the inherited OZ holder-approval mapping. Setting a malicious validator and enabling its optional auto-approval flag cannot change that mapping. Token-specific approvals clear on transfer; revocation remains effective. | Seven F4-01 regressions including all 100 IDs, future mints, both configuration orders and payout rotation; real registry fork checks. |
| Transfer hooks | Can zero validators, callbacks or a different transfer path bypass enforcement? All exposed ERC721 transfers use the OZ hooks. Secondary transfers reject unconfigured/no-code validators. The validator's view call cannot modify state. The validator caller shortcut still requires an explicit holder approval after 4.0.1. Minting is deliberately exempt. | Unconfigured/zero-validator tests, direct/conduit approval-only failures, explicit approval/revocation checks. |
| Local marketplace | Can old listings sell an NFT after it leaves and returns, or can failed payment/delivery keep credits? Transfer nonces invalidate prior listings on every secondary transfer, including transfers through another market. Exact payment and the immutable edition determine royalties. All credit writes precede safe transfer and roll back on rejection. | Stale/multiple listings, OpenSea-to-local invalidation, buyer callback/rejection, seller withdrawals, independent market conservation model. |
| Payout rotation | Can a nominee act early, or an old wallet retain contract authority? Nomination alone grants nothing; acceptance changes the storage getter used by all three contracts. Personal bidder/seller credits remain attached to their owners. Cross-contract acceptance during a purchase cannot reenter the market's withdrawals. | Unauthorized/cancel/replace/accept paths, accrued funds, rejected-sale rollback and fork owner lookup. External custom-list ownership is a separate risk below. |
| Rescue and metadata | Can token rescue move ETH, approve an attacker, or take LNTV NFTs? It exposes only fixed ERC20/ERC721/ERC1155 transfers from the receiving contract, rejects its own edition, and shares each contract's withdrawal guard. Metadata control is deliberately trusted and can change all endpoints, without revealing on chain. | Malicious ERC20 return values/callbacks, receiver rejection, non-admin/old-wallet calls, unchanged ETH liabilities and ownership. |

## Findings and changes

**NM-01 — Low, deployment royalty mismatch; fixed.** `Deploy.validateConfig`
accepted 750 bps, while `ConfigureTrading.run` requires 1000. An operator following
both scripts could irreversibly deploy the wrong rate and then fail the documented
activation path. The new regression fails on the old script. Deployment now
requires exactly 1000 bps; the actual-script lifecycle rehearsal also uses 1000.
The reusable contract's constructor remains parameterized; production source and
existing deployments are unchanged.

**F4-02 — Low, incomplete policy verification; fixed in deployment tooling.**
The previous checker only required SignedZone/local market and excluded three
known bad unconditional operators. It could approve an arbitrary extra operator
or authorizer. The checker now requires the complete reviewed set, security level
4, the recorded list ID, edition ownership of that list, and an empty blacklist.
The two reviewed public-chain PaymentProcessors are named in `trading_policy.py`.
An upstream list change fails closed until it is reviewed. This does not remove
the creator's ability to subsequently change registry policy.

**N-01 — Direct bid-list coverage gap addressed.** New ordinary regression tests
independently sort bid records and inspect both links. No source mutations or
mutation campaign were run; the separate mutation-gate request remains excluded.

**NM-02 — Informational, stale audit/deployment documentation; corrected.** Some
current documents still identified 4.0.0/3.3.0, and the runbook called for live
OpenSea testnet trades after OpenSea had discontinued testnet support. Historical
evidence is retained as history; current scope and release checks are corrected.

## Marketplace dependency reasoning

The strict registry grants transfer permission to the configured authorizers or
operators; it does not calculate the sale price itself. SignedZone requires
Seaport as caller, validates its signature against a domain, order hash, fulfiller,
expiry and context, then sets and clears the transfer authorization around the
fill. Changing consideration changes the order hash. The package's real
Seaport/conduit runtime tests attack missing, altered, expired, replayed and
wrong-token authorizations. Their signatures are local fixtures, not OpenSea API
signatures. OpenSea's off-chain signer and Studio settings remain dependencies.

Both inherited PaymentProcessors use immutable trade-module addresses. I retrieved
the verified processor and four trade-module source bundles and reviewed the
shared `_computePaymentSplits`, basic order validation, token dispensing and
native/ERC20 payout paths. Those paths read ERC2981 royalties and reject a maker's
insufficient royalty cap; they do not silently reduce a successful royalty quote
to that cap. Native payout rejection reverts the fill; ERC20 transfers use
SafeERC20. Basic and advanced trades share this calculation. The two processor
revisions differ in partial-fill nonce restoration, not this royalty calculation.
This is a focused dependency review, not a complete audit of the entire external
PaymentProcessor protocol, its forwarders or every supported payment token.

Creator-configured PaymentProcessor royalty bounties can divert some royalty to
the marketplace. Keep those bounties zero if the payout wallet must receive the
full quoted 10%. ERC2981 here rounds upward: for prices not divisible by ten
smallest payment units, a processor order with an exact 1000-bps maximum may
reject the one-unit rounding difference. Clients must simulate using the actual
royalty quote and sufficient cap, or use prices divisible by ten. These are
configuration/rounding constraints, not a demonstrated unpaid successful fill.

## Remaining release conditions and explicit limits

- **F4-03 (Low):** a personally owned custom registry list still belongs to its
  old wallet after payout rotation. The checked default policy is edition-owned
  and avoids this. Custom lists fail release verification; restore the default
  in the same new-wallet batch as acceptance when migrating from a custom list.
  A narrowly scoped list-management feature is not added by this audit.
- **F4-04 (Low):** `owner()` changes correctly, but the edition emits no
  `OwnershipTransferred` event. This is an indexer/Studio recognition question;
  the documented ERC721-C interface does not require that event. Actual Studio
  owner recognition after rotation remains a live check, not a claimed fix.
- **F4-06 (Informational):** the chosen payout wallet must accept native ETH and
  the relevant sale tokens. A successful local fixture is not proof for a future
  production multisig's modules or receive hook.
- Metadata/reveal service, frontend, public deployment, live OpenSea API/Studio
  activation, other marketplace activation and signer custody are separate
  release work. Mainnet spending was not authorized or performed by this audit.
- Creator-controlled metadata and validator/policy administration remain trusted.
  Holder consent is protected; immutable, administrator-proof royalties are not
  claimed. Side payments, wallet sales and understated declared prices cannot be
  priced by this NFT contract.
- The three accepted choices remain uncapped qualifying extensions, no extension
  for unchanged rank, and optional refund recovery 28 days after settlement.
- Mutation campaigns and mutation-runner tests remain excluded by request.

## Completed verification

The complete non-mutation pipeline passed with seed `0x2026090842` in **895 seconds**.
Its extended suite passed **232 tests**, with no failures or skips: nine fuzz tests
ran 10,000 cases each, and three invariant campaigns ran 1,000 sequences of 256
actions each (**768,000 actions**, zero handler reverts). These counts are test
executions, not a proof over all possible inputs. Formatting, optimized build,
interface 4.0.1, ten audit-gate tests, ten policy-checker tests, two native-runner
tests, and the exact 29-finding Slither gate passed.

All four production files have 100% instrumented line, branch and function
coverage. Edition statement coverage is **98/99**; the other files are 100%.
A separate debug run identifies the unhit item as the no-op interface address
cast on `AuctionEdition.sol:155`. Its enclosing assignment has 245 hits and the
subsequent registry configuration has 244; the absent-registry revert is also
covered. I classify this as coverage instrumentation, not a missed execution
branch. The debug run uses 32 fuzz cases per test only to locate the item; the
full extended run above independently uses 10,000.

The real-script local lifecycle minted all 100 NFTs and ended with zero auction
and marketplace liabilities. Six deliberately poisoned local registry policies
were rejected by the deployment checker; default-policy payout rotation passed.
The poisoning uses explicit local impersonation to test the checker and is not
presented as a public-chain exploit. The regression for NM-01 failed before its
fix and passed afterward.

Named registry-policy fork tests passed on Ethereum block **25933485** and
Sepolia block **11661874**. All writes occurred in local forks. Initial harness
attempts that ran no tests or failed compilation are preserved and are not
counted as passes; the final logs require the named test to execute successfully.
The two processors and four Ethereum trade-module bytecodes were matched to
verified source records at the pinned Ethereum block. The 21 added ERC721-C/OZ4/
PermitC dependency files match their pinned manifests; other vendored dependencies
remain unchanged from main.

No newly demonstrated High or Medium production-code defect remained from this
pass. The accepted High refund-recovery authority and the explicitly listed Low,
informational and live-integration release items remain. This is completion of
the requested **manual plus non-mutation audit**, not live marketplace certification.

## References

- [Current exact evidence](results.json)
- [Original fourth-pass findings](INDEPENDENT-AUDIT-2026-09-08-fable-4.md)
- [OpenSea enforcement specification](https://docs.opensea.io/docs/creator-fee-enforcement)
- [OpenSea discontinued testnets](https://support.opensea.io/en/articles/11833955-farewell-testnets)
- Verified dependency addresses, source hashes and provenance are in
  `generated/full-nonmutation-401/payment-processor-review.json` and `fork-results.json`.
