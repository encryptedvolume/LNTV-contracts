# Auction timing update — 2026-09-08

The creator requested a 48-hour initial auction, a ten-minute rolling closing
window, and no 24-hour limit on extensions. The existing contract already had
no cumulative cap. The only production Solidity changes are
`AUCTION_DURATION = 48 hours` and `EXTENSION_WINDOW = 10 minutes`.

Accepted new bids and rank-changing increases inside the final ten minutes set
`endTime = block.timestamp + 600`. Exactly 600 seconds remaining causes no
extension; bidding closes exactly at the current deadline. Increases preserving
rank do not extend the deadline. Repeated qualifying bids may extend the auction
more than 24 hours beyond its original close.

Deployment checks, the independent invariant model, behavioral tests, operational
documentation and the frontend simulation use the new timing. Interface version
1.1.0 retains the same ABI signatures and pins the revised source. These compiled
constants require a new deployment for any previously deployed instance; no
public deployment is recorded.

## Validation

Full `AUDIT_FUZZ_SEED=0x2026090810 npm run audit` passed with Node 22.23.1.

| Check | Result |
|---|---|
| Extended Solidity suite | 127 passed, 0 failed, 0 skipped |
| Stateless fuzzing | Four tests, 10,000 runs each |
| Stateful invariants | Three campaigns; 1,000 runs × 256 calls each; 768,000 calls and zero unexpected reverts |
| Production coverage | 100% lines, statements, branches and functions |
| Mutations | 60/60 caught by at least two behavioral tests; clean 124-test baseline |
| Tool tests | 2 native-runner, 7 audit-gate and 12 mutation-runner tests passed |
| Slither | 14 previously reviewed findings; no new findings |
| Local Anvil lifecycle | 92 bids, 100 NFT mints, 146 late rank-changing increases, 149 exact transaction timestamp checks, two resales and payout rotation; zero ending liabilities |
| Uncapped extension rehearsal | 87,454 seconds past the initial close, exceeding 24 hours |
| Interface | Fresh build matches version 1.1.0 exports; no public deployments |


Evidence: [timing-update-audit.log](generated/timing-update-audit.log),
[results.json](results.json), and [SHA256SUMS](SHA256SUMS). The checksum manifest
covers current source, tests, tooling, documentation, interface and evidence.
Run `sha256sum -c audit/SHA256SUMS` from the repository root to verify the snapshot.

The new mutation cases deliberately restore the 24-hour initial duration, restore
the five-minute window, and introduce a 24-hour cumulative extension cap. Both
new-bid and bid-increase scenarios exercise more than 24 hours of extensions;
the lifecycle rehearsal pins every timed transaction to its exact mined block.
The two percentage increments and accepted rank-based trigger retain their prior
semantics. Slither's finding IDs and checks match the previously reviewed set
exactly; timestamp rationales and source hashes were reviewed for the new values.

The earlier split audit and independent Fable reviews describe the preceding
source. Their measurements are historical, including five-minute extension
economics. The previous consolidated results and hash manifest are retained in
`history/2026-09-08-pre-timing-*`, and Git history preserves the earlier generated
evidence. This automated run does not close Fable's N-01 list-pointer test gap or
optional N-04/N-05 findings, and does not constitute an independent manual audit,
public deployment, live wallet integration, or implementation of the reveal
service. See [ISSUES.md](ISSUES.md).
