# Holder-approval security fix — 2026-09-08

**Version 4.0.1 fixes F4-01 (High).** The current payout wallet can no longer give
its chosen validator permission to transfer NFTs without holder approval.
This patch is verified by the checks below; a complete new audit is not claimed.

## Cause and change

ERC721-C's optional automatic-validator-approval feature combined with the
creator's ability to choose a validator allowed a malicious or compromised
payout wallet to manufacture an operator approval for every holder. The chosen
validator could then transfer all minted NFTs without their owners' consent.
The reviewed 4.0.0 implementation at `1c7c1a9` / `60e7e42` is affected.
The earlier review documented the admin controls but did not test this combined
NFT-seizure capability explicitly. This was a review and regression-coverage gap.

`AuctionEdition.isApprovedForAll` now calls the exact OpenZeppelin 4.8.3 ERC721
base implementation used by the pinned ERC721-C library. It reads only actual
holder approvals and bypasses ERC721-C's optional creator auto-approval branch.
No vendored source is edited. Explicit single-token/operator approvals still
work, and revocations cannot be undone by toggling the creator's flag.

The inherited auto-approval setter and getter remain ABI-compatible. Their
flag may be true, but it cannot grant approval. Validator replacement and policy
configuration remain available. This fix does not make royalty administration
immutable or resolve the other fourth-pass operational findings.

## Verification

| Check | Result |
|---|---|
| New tests against unpatched 4.0.0 | All 7 failed as expected, reproducing missing holder consent |
| Focused holder/OpenSea tests | 25 passed: 7 holder-consent tests and 18 OpenSea tests |
| Complete default-profile Solidity suite | 229 passed, 0 failed, 0 skipped; 9 fuzz tests × 1,024 runs; 3 invariant campaigns × 256 runs × 128 calls |
| Static analysis | 29 individually reviewed findings; one re-keyed bounded mint-loop finding, no new detector class |
| Audit-gate and native-runner tests | 10 + 2 passed |
| Format, optimized build, interface 4.0.1 | Passed |
| Local deployment and ETH/NFT lifecycle | Passed; deployment 6,812,730 gas; ending auction and marketplace liabilities zero |
| Pinned dependency integrity | All 21 added upstream Solidity files unchanged and hash-verified |
| Full extended audit / coverage / mutations | Not rerun for 4.0.1; no new full-audit claim |

Seed: `0x2026090841`. The holder regressions cover all 100 minted NFTs, both
configuration orders, safe transfers, future minting, payout rotation, explicit
single-token approval, clearing approval after transfer, operator revocation and
randomized combinations. OpenSea conduit ETH sales and ERC20 offers also pass
with the inherited flag enabled; normal 10% royalty payments remain intact.
Seaport/conduit tests use the verified protocol fixtures and local signatures.

NFT runtime is 11,434 bytes and auction initcode is 32,475 bytes, below the
applicable deployment limits. Auction, marketplace and token-rescue source are
byte-for-byte unchanged. Current edition SHA-256: `a6b7321c5e79e8733897d113c7d70ee0139ee8578e8a47314b09830cefa6de34`.

Evidence is under `generated/holder-approval-401/`. Original fourth-pass reports
and PoCs remain at [Fable fourth pass](INDEPENDENT-AUDIT-2026-09-08-fable-4.md);
they refer to the vulnerable 4.0.0 snapshot. Earlier result metadata and static
review pins are preserved in `history/2026-09-08-pre-holder-approval-*`.

## Deployment and remaining work

Use the patched implementation for new deployments. Source changes and ABI
updates do not upgrade an existing immutable edition. No public transaction or
OpenSea Studio activation was performed. Public listing/buy/offer verification,
the exact inherited operator-policy review, custom-list rotation, owner-event
integration and payout-wallet payment compatibility remain in [ISSUES](ISSUES.md).
The creator's accepted 28-day post-settlement ETH recovery policy is unchanged.
