# Third-party notices and provenance

`RankedAuction.sol` adapts the sorted doubly linked list and economic rules of **TLRankedAuction**, authored by mpeyfuss / Transient Labs and contributors, distributed under the MIT license identified in its source SPDX header.

- Repository: https://github.com/Transient-Labs/tl-ranked-auction
- Reviewed revision: `4dd148d9fcfa4c96454393d1e8272e6e997dbf7c`
- Unmodified reviewed source: `reference/TLRankedAuction.sol.txt`
- The reference supports ERC-721 prize escrow; this 100-token ERC-721 adaptation (90 tiered auction places and 10 reserved NFTs) and its market are separate work and are not represented as audited or endorsed by Transient Labs.
- The upstream revision does not contain a separate top-level LICENSE file; its contract explicitly declares `SPDX-License-Identifier: MIT`. The MIT permission text is included in this package's `LICENSE`.

Vendored dependencies retain their source notices and license files:

| Dependency | Version | Exact revision | License |
|---|---|---|---|
| OpenZeppelin Contracts | 5.5.0 | `fcbae5394ae8ad52d8e580a3477db99814b9d565` | MIT |
| forge-std | 1.11.0 | `8e40513d678f392f398620b3ef2b418648b33e89` | MIT / Apache-2.0 |
| Foundry npm binaries | 1.7.1 | Integrity-pinned in `package-lock.json` | MIT / Apache-2.0 |
| Slither | 0.11.5 | Locked with its dependencies in `requirements-audit.txt` | AGPL-3.0 |

The project's new Solidity code is MIT-licensed. Tooling dependencies keep their own licenses; this notice does not relicense those tools.
