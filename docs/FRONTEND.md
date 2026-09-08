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
When integrating, synchronize the interface to the published 3.1.0 commit and
disclose the optional recovery policy before real bids. Keep refund actions
available until the live closure flag changes, and retain NFT claim actions.

`UnclaimedETHWithdrawn.amount` includes unwithdrawn primary proceeds, remaining refunds and surplus. For separate bookkeeping, reconcile `AuctionSettled.proceeds` with prior `ProceedsWithdrawn` events; do not classify the entire recovery as forfeited refunds.
