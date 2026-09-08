# Existing-bid increase update — 2026-09-07

The minimum top-up for an existing active bid is now **2.5% of its current amount**, rounded up to the next wei (`INCREASE_BPS = 250`). Each successful increase establishes the amount used for the next minimum. For example, a 1 ETH bid requires 0.025 ETH extra; the resulting 1.025 ETH bid then requires at least 0.025625 ETH extra.

The production change is one constant in `src/RankedAuction.sol`. The deployment checker, independent invariant model, mutation definitions, sample-page calculations and copy, and current operating documentation use the new value. The new-bid threshold remains floor plus 5% at capacity. Extension triggers, the five-minute window, and the absence of an extension cap are unchanged.

## Verification performed

| Check | Result |
|---|---|
| `npm test` in `auction/` | 112 tests passed, zero failures; four fuzz tests at 1,024 runs each and three invariant campaigns totaling 98,304 handler calls with zero reverts |
| `npm run test:auction` in `site/` | 21 tests passed, zero failures |
| `npm run format:check` | Passed |
| JavaScript syntax checks | Both sample-page modules passed |
| Targeted mutation checks | Both zero minimum and restored 0.5% were rejected by the new behavioral contract test, independently of the configuration-getter test |
| Slither plus exact findings gate | Same 14 previously reviewed findings; no new or removed findings; reviewed source hash refreshed after reviewing the one-line production change |
| `scripts/test_audit_gates.py` | All seven tests passed |

The new contract regression exercises rejection of the former 0.5% threshold, rejection one wei below 2.5%, acceptance of the rounded minimum, compounding after a successful increase, and escrow/balance conservation. The sample model has corresponding acceptance, rejection and wallet-debit checks.

## Evidence scope

The existing audit reports, `results.json`, generated evidence and `SHA256SUMS` describe the earlier source snapshot. They have been retained rather than relabeled as evidence for this change. This update did not rerun the full extended audit profile, coverage, all 57 mutations, browser walkthrough or local Anvil deployment rehearsal. Fable's reported Anvil timing flake was addressed in a subsequent [timing fix](TIMING-FIX-2026-09-07.md), which passed four fresh local lifecycle rehearsals with this 2.5% source.

Raising the percentage increases the capital required for repeated extensions. The creator subsequently confirmed uncapped extensions and floor increases without a rank change or extension as accepted design on 2026-09-07. Fable M-01 and L-01 therefore require no corrective contract change; their behaviors remain in place. See [the recorded decisions](DESIGN-DECISIONS-2026-09-07.md).

Updated `src/RankedAuction.sol` SHA-256: `45371987e5fd027bfbae2cc0f79c0f0df4c4934a938e8205f65dfc31d9a325a7`.
