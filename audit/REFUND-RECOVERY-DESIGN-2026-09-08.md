# Refund recovery — explicit accepted design, 2026-09-08

**Finding: High — payout wallet can confiscate all bidder refunds.**

**Disposition: ACCEPTED BY DESIGN (R-01).** The creator explicitly reaffirmed this behavior and the 28-day period on 2026-09-08. No corrective contract change is requested for this finding. The High severity quoted by the creator is retained; acceptance is not a severity downgrade or a claim that the financial consequence was removed. This is the same recovery authority previously reported as F3-01 (Medium trust/design) in the third Fable audit, not a second independent issue.

- Recovery is allowed only after settlement and at or after **`settledAt + 28 days`**, measured from the first successful settlement, not the bidding deadline or deployment.
- The current payout wallet can call `withdrawUnclaimedETH(recipient)` to take all remaining auction ETH, including displaced bidders' credited refunds and winners' uncredited or unwithdrawn excess.
- Refunds do not automatically expire after 28 days. They remain creditable and withdrawable until a recovery transaction succeeds. A failed recovery leaves them open.
- Successful recovery closes all outstanding bidder refunds irreversibly. After eligibility, transaction ordering decides whether a competing refund or recovery executes first; no extra notice or grace transaction is required.
- NFT claims, reserved/unsold entitlements and marketplace seller/royalty credits are unaffected.

The delayed-settlement bug (F3-02) remains **resolved**, not accepted: a late settlement starts a fresh full 28-day interval, so settlement and immediate recovery cannot occur together. The new foreign-token rescue methods do not change this ETH policy or bypass its timer.

This decision must remain visible in audit/release documentation. Frontend wording remains deferred at the creator's request. See [current issues](ISSUES.md) and [the settlement-clock fix](SETTLEMENT-CLOCK-2026-09-08.md).
