# Frontend interface

The website lives in [fxckcomputer/LNTV](https://github.com/fxckcomputer/LNTV).
It imports a checked-in snapshot of `interface/index.js`, so a frontend build
needs neither Solidity nor access to this private GitHub repository.

```js
import { RankedAuctionAbi, AuctionEditionAbi, RoyaltyMarketplaceAbi, deployments }
  from '/contracts/index.js';
```

From this repository, run `npm ci` and `npm run interface:export`. Commit the
result with its source changes. CI uses `npm run interface:check` to detect a
stale ABI, address file, or source hash. TypeScript consumers can use the
adjacent `index.d.ts`; a local package dependency can also import `@lntv/contracts`.

From the frontend's `site/` directory, run:

```bash
npm run contracts:sync -- /path/to/LNTV-contracts
npm run contracts:check
```

The sync requires a clean contracts checkout, verifies the export hashes and
source hashes, copies the interface, and records the exact contracts commit in
`contracts.lock.json`. Commit that frontend update and test it before releasing
the UI. Version changes are explicit; there is no automatic dependency on a
moving `main` branch and no GitHub token in browser code or build settings.

`deployments/networks.json` is currently empty because no public deployment has
been verified. After deployment, record the chain ID and verified `auction`,
`edition` and `marketplace` addresses, regenerate the interface, and sync the
frontend. An empty mapping must leave transaction controls unavailable. ABI
exports alone do not implement wallet integration or the reveal service.

## Refund policy in interface 3.1.0

`RECOVERY_DELAY()` is 28 days. Once `settled()` is true, `recoveryAvailableAt()`
is `settledAt() + 28 days`; `settledAt()` records the first successful settlement.
Before settlement, `settledAt()` is zero and the recovery getter returns only an
earliest estimate from `endTime + 28 days`. Do not show that estimate as a running
refund/recovery timer. Late settlement moves the actual eligibility date later.
This supersedes the auction-end anchor in 3.0.0. Neither crediting nor withdrawal has an automatic
expiry: enable them while `refundsClosed()` is false, even after day 28.
`refunds(wallet)` reports credited amounts until successful recovery and zero
afterwards. NFT claims and marketplace credits remain independent.

The current payout wallet may call `withdrawUnclaimedETH(recipient)` after
settlement and recovery eligibility. Success sets `refundsClosed()` true and
emits `UnclaimedETHWithdrawn`; failed and empty transactions leave refunds open.
Normal `withdrawProceeds` never closes refunds. Show `RefundsClosed` as recovery
already completed; `RecoveryNotAvailable` means the 28-day delay has not elapsed.
Use confirmed state to reconcile simultaneous refund/recovery transactions.

Frontend wording, behavior and the copied interface have deliberately not been
updated in this request. The frontend snapshot remains pinned to 1.1.0.
When integrating, synchronize the interface to the published 3.2.0 commit and
disclose the optional recovery policy before real bids. Keep refund actions
available until the live closure flag changes, and retain NFT claim actions.

`UnclaimedETHWithdrawn.amount` includes unwithdrawn primary proceeds, remaining refunds and surplus. For separate bookkeeping, reconcile `AuctionSettled.proceeds` with prior `ProceedsWithdrawn` events; do not classify the entire recovery as forfeited refunds.

## Batch bidding in interface 3.2.0

`createBids(uint256[] amounts)` is payable and returns the created bid IDs in input order. Pass 1–90 integer wei amounts and `value = amounts.reduce((sum, amount) => sum + amount, 0n)`. Simulate the complete call using the connected account and estimate gas, then use the same request for submission. The 90-item bound is not a guarantee that every batch fits a network or wallet gas limit; reduce quantity when needed. Ordinary wallets can send a batch as one transaction; wallet-specific batching support is unnecessary.

Decode every `BidCreated` event in the confirmed receipt, not only the first. Bids share the sender but keep separate IDs, amounts, rank, cost, refund and claim status. Array order breaks same-amount ties through original ID priority. A returned ID is a bid ID, not an NFT ID or a promise that it remains active. Later entries can displace earlier ones; include `BidDisplaced` when refreshing state. A failed batch has no partial success.

Handle `IncorrectPayment`, `InvalidBatch`, `BidTooLow`, `BidTooLarge`, and `BiddingClosed`. The floor can rise during a batch or before inclusion, so multiplying the current minimum by quantity does not reliably produce a valid batch quote. Existing credits cannot fund bids automatically. `increaseBid` remains a single-bid top-up. A late successful batch leaves ten minutes once, without accumulating ten-minute extensions per item. Pricing, the settlement-anchored recovery delay, and NFT claims retain their existing rules.

These are integration instructions only. The separate frontend's controls, wording and copied ABI are not modified by the batch contract update.

## Admin interface 3.3.0

The latest export adds `AuctionEdition.setMetadataURI(string)`, metadata refresh events and ERC-4906 support, plus `rescueERC20`, `rescueERC721` and `rescueERC1155` on all three contracts. These methods require the current shared payout wallet. See [operations](OPERATIONS.md#admin-metadata-and-token-recovery-interface-330) for parameters. The previous 3.2.0 batch methods remain unchanged. Frontend implementation and wording are deferred by the creator.


## ERC721-C interface 4.0.0

The exported NFT ABI now includes `owner`, `contractURI`, `getTransferValidator`, `getTransferValidationFunction`, `configureEnforcedTrading`, `tradingConfigured`, `tradingListId`, `setTransferValidator`, and `setAutomaticApprovalOfTransfersFromValidator`. These are creator administration/discovery functions; bidding remains on the ranked auction. Standard `approve`/`setApprovalForAll` are no longer restricted to the local marketplace. Never substitute unrestricted Seaport/conduit whitelisting for valid royalty-enforced order fulfillment. Read [OpenSea integration](OPENSEA.md). The separate frontend and its wording have not been changed.
