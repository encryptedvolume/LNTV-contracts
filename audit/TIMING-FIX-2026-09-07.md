# Local lifecycle timing fix — 2026-09-07

**Fable P-01: resolved and verified by Codex.** The lifecycle harness now sets the timestamp for the actual transaction's block, without mining an empty block first. It reads the transaction receipt's block and asserts that the timestamp is exactly the requested value. A timing mismatch fails the rehearsal explicitly.

The same helper checks the first bid exactly at auction start, all 30 rank-changing increases one second before their respective deadlines, a rejected settlement one second before the final deadline, and successful settlement exactly at that deadline. These 33 timestamp checks run as part of the existing `scripts/local_e2e.py` audit gate.

## Verification

| Case | Result |
|---|---|
| Original harness with a 1.2-second delay before a transaction following a timestamp request | Reproduced `Unexpected transaction status: increaseBid` at the first late increase |
| Fixed harness, three independent fresh Anvil deployments | All three complete lifecycle rehearsals passed |
| Fixed harness with the same 1.2-second submission delay | Complete lifecycle rehearsal passed, including all 33 exact timestamp assertions |
| Optimized build | Passed |
| Audit-gate regression tests | All seven passed |
| Production source comparison | All three contract source hashes unchanged |

Across the four successful rehearsals, all 120 late increases extended correctly and all 132 requested transaction timestamps matched their receipt blocks. Each rehearsal created 92 bids, extended the auction by exactly 8,970 seconds, minted all 100 NFTs, processed two secondary sales and payout-wallet rotation, and ended with zero auction and marketplace ETH liabilities. The deployment checker accepted the current 2.5% increase configuration.

The delay was injected at the HTTP provider immediately before `eth_sendTransaction` after a successful `evm_setNextBlockTimestamp` request. This places the delay after the original harness's empty block, while the fixed harness retains the requested timestamp for the transaction itself. The delay was confined to the verification driver.

Evidence is retained separately in [generated/timing-fix-20260907/summary.json](generated/timing-fix-20260907/summary.json) and the adjacent `old-delayed`, `fresh-1`, `fresh-2`, `fresh-3` and `delayed` directories. Earlier audit evidence was preserved. These repetitions verify the harness fix and current local lifecycle; the full extended audit, coverage and all 57 mutations still need a combined refresh for the current source.

Updated `scripts/local_e2e.py` SHA-256: `64677498a1c1a8722b5557d80a7f4906870535779645a8e8aaec8d82e918933b`.
