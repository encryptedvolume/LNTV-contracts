# Current evidence: complete 4.0.1 non-mutation audit

The authoritative current run is in `full-nonmutation-401/`: 232 passing tests,
90,000 fuzz cases, 768,000 invariant actions, coverage, 29 reviewed static findings,
actual-script local lifecycle, exact-policy rejection checks, and two pinned chain
forks. See [results](../results.json), [manual review](../MANUAL-REVIEW-2026-09-08.md)
and [reproduction/scope](full-nonmutation-401/README.md). Mutation campaigns and
mutation-runner tests were excluded. Live OpenSea activation remains release work.

`holder-approval-401/` retains the earlier 4.0.1 default-profile security-patch run.
`erc721c-400/` retains the targeted 4.0.0 review. Top-level generated logs and root
`lcov.info` retain their historical snapshots; they are not the current full run.
Old metadata and its manifest are archived under
`../history/2026-09-08-pre-full-nonmutation-401/`.

Earlier 3.3.0 and mutation evidence retain their original source-specific scope.
The cancelled audit remains cancelled; the new completion does not retroactively
change the status of earlier runs.
