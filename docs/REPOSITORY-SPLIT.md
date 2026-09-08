# Repository extraction — 2026-09-08

The complete local work was committed and pushed to `fxckcomputer/LNTV` at
`f2baeba`, after integrating frontend commit `6d4f33b` and auction-page PR #2
(`bbda721`). The newer frontend variants and evolved bidding demo are retained.

This repository was extracted using `git subtree split --prefix=auction`.
Its initial commit is `c48494f4b2c965e0d5bd19a7727ac280bb72716f`; that tree is
byte-for-byte the `auction/` tree of the catch-up commit. The auction CI workflow
was then moved here and adjusted to run from the repository root.

Solidity source, tests and vendor dependencies were not changed by the split.
Historical audit reports retain their original source snapshots and wording.
Previously ignored audit evidence is now in Git history. Original references to
`auction/` or frontend paths in historical manifests describe the former layout;
consult the dated split verification for current paths and evidence.

The frontend receives only the versioned ABI/address interface, not Solidity
sources or the audit toolchain. Both repositories remain private.
