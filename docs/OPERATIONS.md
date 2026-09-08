# Deployment and operation

## Prepare configuration

Prepare a stable metadata base URL ending in `/` and serve initially unrevealed JSON at every ID from `1.json` to `100.json`. Collection name/symbol and trading royalty rate cannot change after deployment. The current payout wallet can update the metadata base with `edition.setMetadataURI(newBase)`. Contents and later owner-requested reveals are managed off-chain; use a mutable host if those responses will change. Verify that hosting and reveal permissions are under the creator's control separately from contract deployment.

Set one `PAYOUT_WALLET` able to execute contract calls, such as a multisig. It receives all auction proceeds and trading royalties and owns the ten reserved NFT entitlements. To reserve them for the deployer, use the deployer's address here. The deployer has no independent role. Set a positive reserve acceptable for the regular tier if fewer than 90 bids win; the top winner always pays its full bid. The payout wallet can later be replaced through the two-step flow below.

Copy `.env.example` to `.env`, retain the confirmed `ROYALTY_BPS=1000` (10%), and replace the other example values for the target deployment. Foundry automatically reads the package's `.env`. Times are Unix **seconds**, amounts are **wei**, and 100 basis points is 1%. The deployment script rejects wrong RPC chain IDs, unsupported chains, less than ten minutes of lead time, a zero payout wallet, zero reserve, zero/over-100% royalty rates, empty metadata/name/symbol, metadata base missing its trailing slash, and numeric overflow before narrowing.

| Variable | Meaning |
|---|---|
| `CHAIN_ID` | Target chain, matching the RPC |
| `PAYOUT_WALLET` | Initial shared wallet for all auction proceeds and trading royalties |
| `COLLECTION_NAME` | Nonempty, fixed ERC-721 collection name |
| `COLLECTION_SYMBOL` | Nonempty, fixed ERC-721 symbol |
| `ROYALTY_BPS` | Fixed secondary-trading royalty only; **1000 = 10%, confirmed for future deployments** |
| `RESERVE_WEI` | Positive starting auction minimum in wei |
| `START_TIME` | Unix seconds, at least ten minutes after deployment |
| `METADATA_URI` | Initial admin-updatable off-chain base ending `/`; token URI is `<base><id>.json` |

There is no `END_TIME` input: the contract sets the initial close to `START_TIME + 172800` seconds. The 90 auction/10 reserved split is also fixed.

Supported deployment networks are Ethereum mainnet (`1`), Sepolia (`11155111`), and local Anvil (`31337`). The RPC must support the Cancun EVM. No live RPC or private key is embedded in the repository. Use a Foundry encrypted keystore or hardware wallet; keep RPC and explorer API credentials in environment variables through your normal credential mechanism. Do not put private keys into shell commands or source files.

## Simulate, then broadcast deliberately

```bash
npm ci
npm run audit

# RPC_URL is supplied securely in the shell environment.
# This simulates and prints the public configuration and resulting addresses.
node scripts/foundry.mjs forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" --account deployer
```

Review chain ID, the shared payout wallet, collection name/symbol, royalty rate, reserve, start/end, URI, and strict transfer policy in the simulation output. The shared wallet receives the full auction `gross`; no auction royalties are charged. Its payout address can be rotated. That wallet also controls claims of unminted reserved and unsold NFTs. Off-chain hosting access must be managed separately. Other mistaken deployment settings require a new deployment. Then use the same configuration and signer:

```bash
node scripts/foundry.mjs forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" --account deployer --broadcast --verify
```

Explorer verification uses the `ETHERSCAN_API_KEY` environment variable. Foundry persists public transaction/receipt records under `broadcast/`; inspect the successful receipt on the correct chain and retain those deployment records. If broadcasting is interrupted, inspect the recorded transaction hash and receipt before sending anything else. Do not blindly rerun a deployment that may already have succeeded. Use Foundry's `--resume` with the existing broadcast records if needed, after verifying the target configuration and chain.

Deployment is a single transaction that creates the auction and its two nested contracts. The returned auction has immutable `edition()`; that edition has immutable `marketplace()`. Retain all three addresses. Verify source for all three on the explorer, including child contracts if the initial automatic verification did not do so. Auction constructor arguments are the `Config` tuple; edition arguments are `(collectionName, collectionSymbol, metadataURI, royaltyBps)`; marketplace has no constructor arguments. Compile with this exact package, Solidity 0.8.28, Cancun, optimizer 200 runs and `bytecode_hash = "none"`.

Run the read-only deployment checker after exporting the same expected configuration plus `AUCTION_ADDRESS` and `RPC_URL`:

```bash
.venv/bin/python scripts/check_deployment.py
```

For inspection, `PAYOUT_WALLET` must be the expected current wallet; optional `PENDING_PAYOUT_WALLET` defaults to the zero address. Update these expected values after an authorized nomination/rotation. The checker fails on an unexpected current or pending wallet.

It checks runtime bytecode against the pinned build while masking compiler-designated immutable slots, requires repeated copies of each immutable to agree, then checks every immutable binding and expected configuration value separately. After an authorized metadata update or wallet rotation, supply the expected current `METADATA_URI` / `PAYOUT_WALLET` for later inspections; retain the original deployment configuration separately. It checks liabilities against actual ETH balances at one pinned block and verifies that block's hash has not changed during inspection. Do this from optimized build artifacts (`npm run build`) rather than the unoptimized coverage artifacts.

For a complete rehearsal without external RPCs or real funds:

```bash
.venv/bin/python scripts/local_e2e.py
```

## Bidder and indexer integration

The collection contains 100 individual ERC-721 NFTs with IDs 1–90 auctioned and IDs 91–100 reserved, each with its own metadata endpoint. Token ID equals final winning rank: the highest-ranked bid receives #1. This is fixed at settlement, independent of claim order. Unallocated IDs after the last winning rank through #90 belong to the unsold entitlement. The ten reserved IDs are always excluded from auction ranking.

Use the compiled ABIs from `out/`. Read `phase`, `startTime`, `endTime`, and `minimumBid` immediately before constructing a bid. These views describe current chain state and can change before transaction inclusion. A stale or insufficient bid reverts and does not create a bid or retain its ETH (transaction gas is still spent).

At capacity, the minimum new bid is the current floor plus 5%, rounded up to a wei. Existing active bids can still be raised by adding at least 2.5%. Qualifying new bids and rank-changing increases inside the final ten minutes reset the deadline to ten minutes after the bid. There is no fixed extension limit. The auction closes only when the current deadline passes without another qualifying extension.

| Intent | Call |
|---|---|
| One bid / one possible win | `createBid()` with the full bid as `msg.value` |
| Multiple bids in one transaction | `createBids(amounts)` with 1–90 individual wei amounts and `msg.value` equal to their sum |
| More bids from the same wallet | Repeat `createBid()` or `createBids(amounts)`; the batch bound is not a lifetime wallet cap |
| Raise an active bid | `minimumIncrease(id)`, then `increaseBid(id)` with added ETH only |
| Inspect a bid and its awarded NFT | `bids(id)`; its `tokenId` field is zero before settlement or for a displaced bid |
| Inspect NFT ownership/metadata | `edition.ownerOf(tokenId)`, `edition.tokenURI(tokenId)`; both require a minted ID |
| Inspect ranking | `rankedBids(0, 90)`; for smaller pages pass the returned next ID |
| End the auction | `settle()` from any account after the current end time |
| Make winner refunds withdrawable | `creditRefunds(ids)` from any account, 1–90 winning IDs |
| Receive ETH refund | Original bidder calls `withdrawRefund(payableRecipient)` while `refundsClosed()` is false |
| Recover unclaimed auction ETH | Current payout wallet calls `withdrawUnclaimedETH(payableRecipient)` after settlement and at/after `recoveryAvailableAt()` |
| Receive winning NFTs | `claimTokens(ids, recipient)`; only the winning bidder may call |
| Inspect a winner’s final payment | `winningBidCost(id)` after settlement; head pays full, others pay cutoff |
| Receive reserved NFTs | Current payout wallet calls `claimReserved(quantity, recipient)`, up to 10 total, at any phase |
| Receive unallocated supply | Current payout wallet calls `claimUnsold(quantity, recipient)` after settlement |
| Withdraw all auction sale revenue | Current payout wallet calls `withdrawProceeds(payableRecipient)` |

Batch inputs are processed in their supplied order, with a fresh `minimumBid()` check after each insertion and displacement. Crossing 90 active bids changes the minimum even inside one batch. Later entries may displace the sender's existing bids or earlier entries in that batch; displaced amounts become ordinary pull refunds. Successful submission does not guarantee that all batch IDs remain active or eventually win. Equal amounts retain original ID priority. All bids belong to the calling wallet.

Payment must equal the sum; `IncorrectPayment` rejects both underpayment and overpayment. `InvalidBatch` rejects zero or more than 90 amounts. Every individual amount must fit `MAX_BID` and meet its current minimum. No refund balance or forced surplus can substitute for payment. Any failure rolls back all IDs, ranking, credits, escrow, events and extensions in that transaction; gas is still charged. A successful late batch sets the deadline to its transaction timestamp plus 600 seconds once, rather than adding ten minutes for every item.

Estimate gas and simulate the complete batch before submission, including the exact sender, amounts and total ETH. A changing floor can still invalidate the transaction before inclusion. Reduce the batch size when the estimate exceeds the selected network or wallet's transaction budget. Read all `BidCreated` events from the receipt; the return array is in input order, while final NFT IDs are assigned only at settlement. `increaseBid` continues to update one active bid per call.

Index `BidCreated` for the wallet-to-ID history, `BidIncreased`, `BidDisplaced`, `AuctionExtended`, and `AuctionSettled` for auction state. Follow refund and claim events for entitlements. Query current state to reconcile events after reorganizations. `rankedBids` shows current/final winners, not all historical bidders; terminated pages return next ID 0, which also means the head when supplied as input. Stop pagination when next is zero.

The highest-ranked bid pays its full amount for NFT #1. All other winners pay the 90th winning bid when full, otherwise reserve. Example: bids of 1 ETH and 3 ETH with a 0.01 ETH reserve assign NFT #1 to the 3 ETH bid (no refund), NFT #2 to the 1 ETH bid (0.99 ETH refund), and 3.01 ETH to auction proceeds. With 90 occupied places, #2–90 pay the smallest active bid even if no 91st bid was submitted. Equal top amounts favor the earlier original bid ID: that bid pays full; the tied second-place bid pays the regular price. Reserved mints never affect pricing.

The frontend should make first-place full-bid liability explicit before submission. Read `winningBidCost(id)` after settlement instead of multiplying a wallet's number of wins by `clearingPrice`. Credit all its overpayments and retain independent NFT-claim status, displaced-bid refunds and withdrawal status.

## Secondary sale calls

1. Seller calls `edition.approve(marketplace, tokenId)` for one NFT, or `edition.setApprovalForAll(marketplace, true)` for the collection.
2. Seller calls `marketplace.list(tokenId, priceWei, expirySeconds)` and records the emitted listing ID.
3. Buyer calls `marketplace.buy(listingId, recipient)` with exactly the listed price in ETH. This transfers that one NFT.
4. Seller calls `marketplace.withdraw(payableRecipient)` for its seller credit.
5. The current payout wallet calls `marketplace.withdrawRoyalties(payableRecipient)` for the trading royalty pool. `totalCredits()` includes both seller credits and `pendingRoyalties()`.

Sellers permanently cancel a listing with `cancel(listingId)`. Revoking approval blocks fills only while approval is absent; restoring approval can make an otherwise valid old listing fillable again. A transfer invalidates earlier listings for the same token, including if it later returns to that seller. Check ownership, current off-chain metadata, approval, expiry, active status and the recorded transfer nonce, and simulate the purchase before sending. Re-listing creates a new listing ID. Prices cannot be edited and there are no partial fills. Direct gifts and external-market transfers revert.

## Reserved NFTs and off-chain reveal

The current payout wallet can call `claimReserved(quantity, recipient)` before, during or after the auction. Batches mint the next unused reserved IDs from #91 through #100. Choose the payout wallet itself as recipient to hold them there, or redirect to a compatible wallet. There is no mint price or royalty. A failed receiver reverts the whole batch and leaves the entitlement available. Observe `ReservedClaimed`, `reservedRemaining` and ERC-721 `Transfer` events. Already minted reserved NFTs are subject to the same trading royalty policy as auction NFTs.

All 100 metadata endpoints must initially return unrevealed placeholder content. Implement the later creator-enabled, holder-requested reveal in the metadata service. The contract supplies per-ID URLs under an admin-updatable base and current ownership; it has no activation or reveal transactions and no on-chain revealed state. The backend must independently authenticate the creator and verify the current owner for each request. A wallet rotation does not move hosting credentials. These service/API features are outside this contract implementation.

Metadata changes do not invalidate active sale listings. `edition.setMetadataURI(newBase)` emits `MetadataURIUpdated(previousURI, newURI)` and ERC-4906 `BatchMetadataUpdate(1, 100)`; passing the same base can announce an off-chain content refresh. Hosting-only edits do not automatically emit events. Cancel affected listings before changing metadata, and refresh external caches through the relevant marketplace/service. A fixed IPFS directory cannot change its content; use a stable mutable endpoint for this design. Inspect metadata availability and content separately from the code/configuration checker.

## Change the shared payout wallet

1. From the **current** wallet, call `auction.proposePayoutWallet(newWallet)`.
2. Verify `pendingPayoutWallet()` and the proposal event. Until acceptance, the current wallet keeps all payout authority.
3. From the **new** wallet, call `auction.acceptPayoutWallet()`.
4. Confirm `payoutWallet()` and `edition.royaltyRecipient()` both equal the new wallet, and `pendingPayoutWallet()` is zero. Rerun deployment inspection with the new expected wallet.

The current wallet can replace an unaccepted nomination or cancel it with `cancelPayoutWalletChange()`. No arbitrary caller or deployer can rotate it. Both EOAs and contract wallets must be able to make these calls. Zero, the current wallet, and the three system contract addresses are rejected as nominees.

Acceptance applies to unwithdrawn auction proceeds, accrued and future trading royalties, control of unclaimed reserved and unsold NFTs, metadata updates, and foreign-token rescue on all three contracts. Unrecovered bidder refunds, winning NFTs, seller credits, and already withdrawn funds keep their existing owners. Optional recovery 28 days after settlement follows the current payout wallet and closes outstanding auction refunds only when successful. If the old payout wallet also sold NFTs, its seller credits stay withdrawable by that old wallet. No separate royalty-recipient update is necessary.

## Recovery and operational limits

If a refund recipient rejects ETH, the entitlement survives and the bidder can retry to another address until a successful recovery closes refunds. If an NFT receiver rejects ERC-721, the mint entitlement survives and the bidder can redirect it; refund crediting and withdrawal are independent. Batch mint failure reverts that batch only; smaller batches help isolate a rejecting recipient. The current payout wallet can redirect auction proceeds and trading royalties in the same way.

No admin intervention can replace a lost bidder key, redirect somebody else's tokens, cancel an auction after a configuration mistake, change the royalty percentage, recover unclaimed bidder ETH before the authorized recovery eligibility time, or unlock direct transfers. Unclaimed winning units are reserved forever. The payout wallet can be rotated only while the current wallet can nominate a replacement (or a previously nominated wallet can still accept). There is no separate lost-key recovery authority. Keep wallets operational and communicate these constraints before opening the auction.

Monitor `liabilities() <= auction.balance`, `market.totalCredits() <= market.balance`, `activeCount <= 90`, the current closing time, and total supply. Normal donations cannot be sent directly; `selfdestruct` or protocol-level balance transfers can create surplus, recoverable with the remaining auction ETH after settlement and recovery eligibility. Regular-tier uniform-price demand reduction, bid shading, transaction ordering, Sybil bidding, and self-outbidding are economic properties, not solvency failures. The design supplies no per-person allocation guarantee.

## Migration from earlier local prototypes

This is a new deployment and requires regenerated ABIs. `Config.endTime` and the `END_TIME` environment input are removed. The remaining tuple is `(payoutWallet, royaltyBps, reservePrice, startTime, metadataURI, collectionName, collectionSymbol)`. Start is uint64; initial/current end times are uint256. `SUPPLY()` is now 90; `RESERVED_SUPPLY()` is 10; `AUCTION_DURATION()` is 172800. New calls include `claimReserved`, `reservedRemaining`, and `winningBidCost`.

`METADATA_URI` is now a base ending `/`, not a shared JSON file. `enableReveals`, `reveal`, `revealsEnabled`, `revealedMetadataURI`, `revealed`, their reveal-specific events are removed. Interface 3.3.0 restores ERC-4906 support for admin metadata updates, without restoring those reveal functions. Transfer nonces advance only on transfers. Frontends must obtain reveal state from the metadata service and stop sending the removed calls.

ERC-721 claims take bid IDs and return the NFTs assigned to those bids at settlement. Listings take `(tokenId, price, expiry)`; buys take `(listingId, recipient)`. The single two-step payout wallet and trading-only royalty policy remain in place. The old hard-end cap and its getters remain removed. No public deployment has been migrated or modified.

## Timing update — 2026-09-08

New auctions run for 48 hours initially (`AUCTION_DURATION() = 172800`). A qualifying new bid or rank-changing increase inside the final ten minutes resets `endTime` to the transaction timestamp plus 600 seconds. Extensions have no cumulative cap, including at 24 hours past the initial close. An increase that preserves rank still does not extend the deadline. The existing code already had no extension cap; this update changes only the two timing constants in production Solidity.

These constants are compiled into the contract. An already deployed auction would retain its original timing and require a new deployment to adopt this version. The timing-only release retained its external function signatures and exported interface version 1.1.0. The corrected refund-recovery release below exports version 3.1.0 with recovery eligibility and an explicit refund-closure state. No public deployment is recorded.

## Optional recovery of unclaimed auction ETH after 28 days

The creator can choose to recover unclaimed ETH starting at
`recoveryAvailableAt()`: exactly 28 days (2,419,200 seconds) after the first
successful settlement transaction, recorded in `settledAt()`. Late settlement
starts the full delay; settling on day 27 after bidding ends makes recovery
available on day 55. Settlement and immediate recovery cannot succeed together.
Before settlement the getter is only an earliest estimate from the auction end;
check `settled()` before treating it as the actual recovery date. Bidders may
still credit and withdraw refunds at day 28 after settlement
or any later date **until recovery succeeds**. Displaced bidders may withdraw
during bidding. Normal `withdrawProceeds` never closes refunds.

To exercise this option, call `withdrawUnclaimedETH(recipient)` from the
**current `PAYOUT_WALLET`**. Success transfers all remaining auction ETH,
including unwithdrawn proceeds, remaining refunds and forced donations, and
permanently sets `refundsClosed()` to true. It disables both refund crediting
and withdrawals. The original deployment signer has no separate authority;
accepted wallet rotation transfers the recovery role. Rejected payments and
empty recovery attempts revert without closing refunds or consuming credits.
Retry a rejected payment with a suitable recipient. After successful recovery,
later forced ETH can be recovered again.

NFT claims never expire through this action. Marketplace seller credits and
royalties are separate and unaffected. After recovery becomes available,
transaction ordering determines whether a particular refund or recovery executes
first; a pending recovery transaction does not itself close refunds.

Interface 3.1.0 replaces the unreleased 2.0.0 time-expiry API with
`RECOVERY_DELAY()`, `recoveryAvailableAt()`, `settledAt()` and `refundsClosed()`. There is no new
deployment parameter. Existing deployed bytecode would keep its original rules;
no public deployment is recorded. Frontend wording, behavior and copied
interface remain deferred at the creator's request. When integrating, disclose
the optional recovery policy before real bids and use the live closure flag,
not elapsed time, to enable refund actions. Reconcile historical credit events
with `refunds(wallet)` and `refundsClosed()`. Index `UnclaimedETHWithdrawn` for
successful recovery transactions.

Version 3.1.0 supersedes the auction-end anchor in 3.0.0 and resolves F3-02. The settlement timestamp adds one storage write paid by the settlement caller; ordinary bidder actions gain no new state write. The creator can submit settlement after close.

## Batch bidding — interface 3.2.0

`createBids(uint256[] amounts)` is an additive payable entry point. Single-bid, top-up, settlement, recovery and claim signatures retain their behavior; no deployment parameter changes. Existing immutable deployments require a new deployment for batch support. Regenerate and synchronize the versioned interface before adding frontend controls. This contract update leaves frontend code and wording for the creator's separate integration work.

## Admin metadata and token recovery (interface 3.3.0)

The **current `payoutWallet`** is the admin. A nomination grants no authority until accepted; the previous wallet loses these permissions at acceptance. These functions are available before, during and after the auction, independently of the 28-day ETH recovery delay.

| Target | Function | Purpose |
|---|---|---|
| NFT edition | `setMetadataURI(string newBase)` | Set a nonempty base ending `/` for every minted and future token; announce an ERC-4906 refresh |
| Contract holding the foreign tokens | `rescueERC20(address token, address recipient, uint256 amount)` | Transfer the specified ERC-20 amount, including wrapped ETH as a token |
| Contract holding the foreign NFT | `rescueERC721(address token, address recipient, uint256 tokenId)` | Safely transfer that foreign NFT |
| Contract holding the foreign tokens | `rescueERC1155(address token, address recipient, uint256 tokenId, uint256 amount)` | Safely transfer the specified token ID and amount |

Each rescue function exists on the auction, edition and marketplace. Call the one that actually holds the tokens. The admin chooses the recipient, so it can return assets to the original sender; the contract does not infer depositor ownership. Positive amounts are required for ERC-20/ERC-1155. The token must have code, and the recipient must be nonzero and different from the called contract. Safe NFT recipients must support the relevant receiver interface. Rejected transfers leave assets available for retry. Normal safe NFT deposits remain blocked by the absence of receiver hooks; these functions recover assets already held.

Rescue functions never transfer ETH or alter ETH accounting. They reject the LNTV edition itself, preserving its royalty transfer policy and NFT claim entitlements. Use existing proceeds/refund/royalty functions for ETH. `ERC20Rescued`, `ERC721Rescued` and `ERC1155Rescued` record token transfers; unusual fee-on-transfer tokens may deliver less than the requested amount.

No deployment parameter is added. Existing immutable deployments require a new deployment for these functions. Interface 3.3.0 is exported for later integration; frontend code and wording are unchanged. Only focused tests and build/interface checks were requested for this release; the full audit and mutation suite were not rerun.
