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

## Refund policy in interface 2.0.0

The contract now exposes `refundDeadline()`, `REFUND_CLAIM_PERIOD()` and
`withdrawUnclaimedETH(recipient)`. `refunds(wallet)` keeps its selector but now
returns zero once the 28-day period expires. Both `creditRefunds` and
`withdrawRefund` reject at/after that deadline, even if recovery has not happened.
Crediting alone does not preserve the right to withdraw. The projected deadline
moves with `endTime` during extensions and does not move when settlement occurs.
NFT claims and marketplace credits remain independent.

Frontend wording, behavior and the copied interface have deliberately not been
updated in this request. The current frontend snapshot remains pinned to 1.1.0.
When integrating this release, synchronize the interface to the published 2.0.0
commit, display/disclose the deadline before real bids, and stop offering expired
refund actions while retaining NFT claims. Show `RefundClaimPeriodExpired` as an
expired refund window; the recovery action requires the current payout wallet,
settlement and the deadline. Recovery emits `UnclaimedETHWithdrawn`.
