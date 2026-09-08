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
