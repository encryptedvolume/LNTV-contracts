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
| Limit Break Creator Token Standards (ERC721-C source closure) | pinned upstream | `980a63b33591d568b6e04b45f37deba05a55f787` | MIT |
| OpenZeppelin for upstream ERC721-C only | 4.8.3 | `0a25c1940ca220686588c4af3ec526f725fe2582` | MIT |
| Limit Break PermitC (Constants.sol only) | pinned upstream | `65e3a4a493aa14d1a03c23512233d7546e8f1e96` | MIT |
| forge-std | 1.11.0 | `8e40513d678f392f398620b3ef2b418648b33e89` | MIT / Apache-2.0 |
| Foundry npm binaries | 1.7.1 | Integrity-pinned in `package-lock.json` | MIT / Apache-2.0 |
| Slither | 0.11.5 | Locked with its dependencies in `requirements-audit.txt` | AGPL-3.0 |

The project's new Solidity code is MIT-licensed. Tooling dependencies keep their own licenses; this notice does not relicense those tools.

The ERC721-C source closure is copied byte-for-byte from the selected Limit Break revision, with its exact submodule revisions for OpenZeppelin/PermitC. Scoped remappings keep its OpenZeppelin 4.8.3 implementation separate from this package's OpenZeppelin 5.5.0 utilities. Each added dependency has `UPSTREAM_COMMIT`, `SOURCE-MANIFEST.json` and its original license. Unused upstream contracts are not included.

`test/vendor/` contains verified OpenSea SignedZone/registry source and Seaport/conduit runtime fixtures for local interoperability tests. Provenance and original source licenses are retained. They are test dependencies; the public deployment uses the existing documented registry, zone and Seaport deployments. The test fixtures do not represent an OpenSea endorsement or a live OpenSea API integration.
