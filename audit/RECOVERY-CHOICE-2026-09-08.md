> **Historical 3.0.0 snapshot:** optional recovery still requires a successful transaction, but the creator subsequently moved its 28-day delay from auction end to settlement. See [the current settlement-clock fix](SETTLEMENT-CLOCK-2026-09-08.md).

# Refunds close only on successful recovery — 2026-09-08

The creator clarified: “Refunds should't expire though? It should just be an
option for us to claim. Refunds expire when we claim it.” The earlier automatic
28-day expiry implementation was an incorrect interpretation and is superseded.
Its source is retained in Git at `66602948`; its original consolidated results
and manifest are archived under `history/2026-09-08-pre-recovery-choice-*`.

## Corrected behavior

- `RECOVERY_DELAY` is fixed at 28 days (2,419,200 seconds).
- `recoveryAvailableAt()` is final extended `endTime + 28 days`. This only unlocks
  recovery; it does not close or zero any refunds. Settlement cannot reset it.
- `refundsClosed` starts false. Bidder withdrawal and winner refund crediting
  remain available while it is false, including years after bidding ends.
- After settlement and eligibility, the current payout wallet may call
  `withdrawUnclaimedETH(recipient)`. Success transfers all remaining auction ETH
  and permanently closes remaining refund credits and uncredited excess.
- Closure and zeroing of the three accounting buckets occur before the external
  transfer, under `nonReentrant`. A rejected, invalid-recipient or empty recovery
  reverts all effects, leaving refunds open if they were open before the call.
- Normal `withdrawProceeds` never closes refunds. Repeated recovery can collect
  later forced ETH without reopening refunds. Wallet rotation carries recovery
  authority to the accepted replacement, not the original deployment signer.
- NFT allocation and claims, reserved/unsold entitlements, and marketplace seller
  credits/royalties are unaffected. There is no new deployment parameter.

After day 28, transaction ordering determines which payment executes first: a
refund paid first reduces the recoverable balance; a successful recovery first
closes the remaining refunds. Broadcasting recovery alone has no effect.
The original settlement prices remain historical values; recovery separately
transfers money bidders have not withdrawn. Remaining refund forfeiture when
recovery succeeds is the creator's accepted policy, not payment to those bidders.

Interface 3.0.0 replaces the unreleased 2.0.0 deadline/claim-period getters and
errors with eligibility/closure names and adds `refundsClosed()`. The frontend
code, wording and copied 1.1.0 interface remain unchanged by explicit request.

## Verification

Full `AUDIT_FUZZ_SEED=0x2026090829 npm run audit` passed with Node 22.23.1.

| Check | Result |
|---|---|
| Solidity suite | 152 passed, 0 failed, 0 skipped; includes 25 recovery scenarios |
| Stateless fuzzing | Five tests, 10,000 runs each; recovery fuzz varies prior claims, forced ETH and delay beyond day 28 |
| Stateful invariants | Three campaigns; 1,000 runs × 256 calls; 768,000 calls with zero unexpected reverts |
| Production coverage | 100% lines, statements, branches and functions across all three contracts |
| Mutation regressions | 77/77 caught by at least two behavioral tests; clean 149-test baseline |
| Tool regression tests | 2 native-runner, 7 audit-gate and 14 mutation-runner tests passed |
| Static analysis | 16 individually reviewed findings; no unreviewed findings or source drift |
| Original local lifecycle | 92 bids, 100 NFTs, 146 late increases, 149 pinned timestamps, resales, wallet rotation and zero final liabilities |
| Corrected recovery rehearsal | Credit succeeds at day 28; rejected recovery at day 35 leaves refunds open; refund succeeds at day 42; accepted replacement then recovers 3.52 ETH and closes refunds; later NFT claims succeed |
| Interface | Fresh build matches generated 3.0.0 exports; no frontend synchronization |

The three added unit scenarios exercise years of inaction, ordinary proceeds
withdrawal and callback-visible closed state. Existing cases now verify exact
eligibility with continued credit/withdrawal, refunds after a rejected payment,
late settlement, extended-end eligibility, authorization, rollback and closure.
Four added mutants restore automatic time expiry in guards/getter, omit closure,
or close refunds during ordinary proceeds withdrawal. Named scenario gates
prevent accidental loss of those behavioral checks. The three existing stateful
handlers retain their prior auction/marketplace scope; recovery is tested in the
dedicated unit/fuzz suite and real-transaction rehearsal, not a new stateful handler.

Static review removes the two automatic-expiry timestamp findings. The remaining
auction timestamp checks govern start, end, settlement, extension and recovery
eligibility. The private payment helper, empty-balance guard and low-level call
were reviewed against the closure-before-interaction and rollback behavior.
No NFT or marketplace production source changed in this correction.

Evidence: [recovery-choice-audit.log](generated/recovery-choice-audit.log),
[results.json](results.json), [mutations.json](generated/mutations.json), and
[SHA256SUMS](SHA256SUMS). The manifest pins source, tests, tooling, docs, exports
and evidence; run `sha256sum -c audit/SHA256SUMS` from the repository root.

Earlier Fable reviews and timing/automatic-expiry reports describe their
historical snapshots. This complete automated run does not close N-01 or optional
N-04/N-05, constitute a new independent manual audit, or implement deployment,
frontend wallet integration or the reveal service. See [ISSUES.md](ISSUES.md).
