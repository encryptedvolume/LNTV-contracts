# Mutation coverage strengthening — 2026-09-07

**Fable P-02: resolved and verified by Codex.** Added 15 separately reviewed behavioral scenarios and reran all 57 mutations. Every mutation now causes at least two distinct behavioral test failures, with configuration-only checks excluded from the count. Production contract sources are unchanged.

## Before and after

A fresh attribution run found 14 mutations below the new two-behavior threshold: 11 had one failing test in total, the restored bid percentages each relied on one behavioral test plus configuration assertions, and the one-hour duration regression was caught only by configuration assertions. The table counts behavioral failures only.

| Mutation | Before | After |
|---|---:|---:|
| old 2.5 percent outbid increment restored | 1 | 2 |
| old 0.5 percent increase increment restored | 1 | 2 |
| two-hour extension cap restored | 1 | 2 |
| extension timestamp narrowed | 1 | 2 |
| royalty transfer bypass | 1 | 2 |
| free purchase | 1 | 2 |
| unauthorized cancellation | 1 | 2 |
| repeatable marketplace withdrawal | 1 | 2 |
| unsafe payout wallet allowed | 1 | 2 |
| forced third-party mint delivery | 1 | 2 |
| unauthorized ERC721 mint | 1 | 2 |
| ERC721 token approval bypass | 1 | 2 |
| wrong initial duration | 0 | 5 |
| metadata slash validation bypassed | 1 | 2 |

The additional scenarios exercise late rank increases beyond the former cap, bidding across the uint64 timestamp boundary, minimum increments and wei rounding, paid resale restrictions, existing seller funds, cancellation by a former owner, payout replacement after a rejected nominee, refunds followed by protected mint claims, mint callbacks, token approvals after resale, and metadata constructor validation through the standalone edition. Two separate duration scenarios accept a bid at hour 23 and reject settlement at hour two; both complete settlement at hour 24 without deriving that deadline from the duration/end getters.

## Permanent audit gate

`scripts/mutation_audit.py` first verifies that the unmodified contracts pass the exact test selection and fixed fuzz seed. It reads native Forge JSON and requires an unchanged test inventory. Every mutation must exit with an actual test failure and fail at least two behavioral tests. The specific new scenarios for all 14 previously weak cases are mandatory, so other failures cannot replace their coverage.

The gate rejects compiler errors, setup failures, missing or skipped tests, malformed/empty reports, process crashes, successful exits mislabeled as failures, and configuration-only evidence. Twelve Python regression tests exercise these rules and now run in `scripts/audit.sh`. Test names, failure reasons, raw Forge results and hashes of the actual isolated inputs are retained. The classification excludes the three reviewed configuration-only tests; the independent scenarios were reviewed manually, and test counts do not prove exhaustive coverage of every possible defect.

## Validation

- `npm test`: 127 tests passed; four fuzz tests at 1,024 runs and three invariant campaigns totaling 98,304 handler calls with zero unexpected reverts.
- Mutation campaign: clean 124-test baseline, then 57/57 mutations passed the stronger gate; invariants are excluded from this isolated campaign and fuzz tests use 16 runs with seed `0x20260907`.
- Mutation-runner regression tests: 12 passed. Existing audit-gate regression tests: seven passed.
- Foundry formatting, Python syntax and audit-shell syntax checks passed.
- All recorded isolated input hashes match the current inputs; all three production source hashes match the pre-change snapshot.

Reproduce the strengthened campaign from `auction/`:

```bash
.venv/bin/python scripts/test_mutation_audit.py
.venv/bin/python scripts/mutation_audit.py --output-dir audit/generated/mutation-strengthening-repeat
```

Evidence: [summary](generated/mutation-strengthening-20260907/summary.json), [previous failure attribution](generated/mutation-strengthening-20260907/baseline.json), [current named failures](generated/mutation-strengthening-20260907/updated/mutations.json), [isolated input hashes](generated/mutation-strengthening-20260907/updated/mutation-inputs.json), and [complete contract test log](generated/mutation-strengthening-20260907/contract-tests.log).

This work completes the mutation-robustness item. The combined extended audit, coverage and consolidated evidence refresh remain separate outstanding work; the historical reports and top-level audit manifest have not been relabeled as a new complete audit.
