# Contract version archive

Version **4.0.1** fixes the creator-controlled implicit approval vulnerability
(F4-01); see [the fix report](../audit/HOLDER-APPROVAL-FIX-2026-09-08.md). The
`v4.0.0` tag and the release history below preserve the affected implementation.
The following section records the prior 4.0.0 merge and archive, not a current
security attestation.

## Previous 4.0.0 release and archive

The previous contract implementation **4.0.0** was merged into `main` through
[PR #1](https://github.com/encryptedvolume/LNTV-contracts/pull/1) on 2026-09-08.
Production source is unchanged from commit `1c7c1a90ccc24a38d74b530fbdbc22954c2f83bb`;
the release tag is `v4.0.0`. This identifies a source version, not a deployment or
a completed audit: [the current evidence](../audit/results.json) remains partial.

All earlier committed snapshots in this contracts repository are preserved by
annotated archive tags. Superseded implementations and their original audit
evidence remain available at those tags; the historical source is not copied
into the active build. The previous `main` is the 1.0.0 snapshot at `b8a2497`.
The merged development branch is preserved as
`archive/2026-09-08/codex-48-hour-auction` at `1c7c1a9` and retired after merging.
The archive does not modify deployed contracts or the separate website repository.

| Package version | Commit | Archive tag | Revision |
|---|---|---|---|
| 1.0.0 | `c48494f` | `archive/2026-09-08/v1.0.0-c48494f` | Catch up auction contracts, audit evidence, and bidding demo |
| 1.0.0 | `59bc0f0` | `archive/2026-09-08/v1.0.0-59bc0f0` | Split contracts into standalone package with verified frontend interface and audit evidence |
| 1.0.0 | `b8a2497` | `archive/2026-09-08/v1.0.0-b8a2497` | Configure approved private repository and refresh interface provenance |
| 1.1.0 | `c60b07d` | `archive/2026-09-08/v1.1.0-c60b07d` | Use 48-hour auctions with uncapped ten-minute extensions |
| 2.0.0 | `6660294` | `archive/2026-09-08/v2.0.0-6660294` | Add 28-day refund expiry and unclaimed auction ETH recovery |
| 3.0.0 | `0d52419` | `archive/2026-09-08/v3.0.0-0d52419` | Keep refunds open until successful optional recovery |
| 3.1.0 | `ff5e952` | `archive/2026-09-08/v3.1.0-ff5e952` | Start the recovery delay at first successful settlement |
| 3.2.0 | `08718d4` | `archive/2026-09-08/v3.2.0-08718d4` | Add atomic batch bidding with shared auction rules |
| 3.3.0 | `737cbd7` | `archive/2026-09-08/v3.3.0-737cbd7` | Add payout-admin metadata updates and foreign-token rescue |

Merge commit: `f83f7c5ef7438e697cda8aa04ab939df498d496c`. Git history retains every archived revision.

To inspect an old version without changing the current checkout:

```bash
git fetch origin --tags
git show archive/2026-09-08/v3.3.0-737cbd7:src/AuctionEdition.sol
git worktree add --detach ../LNTV-contracts-v3.3.0 archive/2026-09-08/v3.3.0-737cbd7
```

Historical reports in `audit/history/` and version-specific review documents are
retained with their original scope. Their results do not attest the current
ERC721-C implementation. Superseded versions may include behavior later fixed
or replaced; use `main` for current development.
