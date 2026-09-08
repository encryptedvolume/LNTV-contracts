# Accepted auction design decisions — 2026-09-07

The creator explicitly confirmed both auction behaviors below after reviewing Fable's findings and the change to a 2.5% minimum increase for existing bids. Their current disposition is **accepted design; no corrective contract change requested**. The original audit retains the reviewer's findings and severity ratings as review history.

| Finding | Creator decision | Intended behavior |
|---|---|---|
| Fable M-01: repeated extensions | Accepted; retain uncapped extensions | A new accepted bid or rank-changing increase during the final five minutes leaves five minutes on the clock. Repeated qualifying bids can keep settlement pending, with active bids committed until settlement or displacement. |
| Fable L-01: floor increase without extension | Accepted; retain the rank-based trigger | Increasing the lowest winning bid without changing its rank does not extend the deadline, including at the last moment. At full capacity, the final lowest winning amount sets the price for ranks #2–90. |

The creator's stated objective is to allow continued competitive bidding and resulting revenue growth. Each increase requires additional ETH. Final auction proceeds depend on the highest-ranked bid and the clearing price; excess deposits above regular winners' final price are refundable. The 2.5% minimum compounds on each existing bid's current amount. New bids entering a full auction still require floor plus 5%, rounded up.

These two findings are removed from the outstanding corrective-work list. They remain documented auction behavior, including the possibility of prolonged fund commitment and last-moment repricing. This decision requires no code change.

The local-Anvil timing defect was subsequently [fixed and verified](TIMING-FIX-2026-09-07.md), and [behavioral mutation coverage was strengthened and verified](MUTATION-STRENGTHENING-2026-09-07.md). The remaining audit work is a complete audit/evidence refresh for the 2.5% source and committing the contract package and retaining matching evidence. [ISSUES.md](ISSUES.md) records those items alongside the remaining metadata, frontend and testnet work.

References: [Fable's original audit](INDEPENDENT-AUDIT-2026-09-07-fable.md), [2.5% change verification](INCREASE-UPDATE-2026-09-07.md).
