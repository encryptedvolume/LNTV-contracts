# Dependency and compiler review — 2026-09-08

> Historical 3.3.0 review. The subsequent ERC721-C migration adds upstream-pinned Limit Break/OpenZeppelin 4 dependencies; this document does not attest those additions. See ERC721C-INTEGRATION-2026-09-08.md.

Scope: production source 3.3.0, unchanged from `737cbd7`, Solidity 0.8.28, legacy code generation, optimizer 200 runs, Cancun. This is a dependency review alongside the non-mutation audit, not a compiler upgrade.

## Provenance

Fresh downloads of the exact revisions in [NOTICE](../NOTICE.md) matched all **330 OpenZeppelin Solidity files and 31 forge-std Solidity files**, byte for byte. No dependency or compiler version was changed. [Hashes and comparison result](generated/dependency-provenance-330.json).

## Compiler registry

The [Solidity bug registry](https://raw.githubusercontent.com/ethereum/solidity/develop/docs/bugs.json) entries potentially matching compiler version 0.8.28 were checked against this build. [Fetched snapshot](generated/solidity-bugs-20260908.json).

| Registry entry | Applicability |
|---|---|
| SOL-2026-4, SOL-2026-2 | Require IR compilation; this build uses the legacy pipeline. |
| SOL-2026-1 | Requires IR and transient-storage clearing; neither is used. ReentrancyGuard uses persistent storage. |
| SOL-2025-1 | Requires array data to cross the end of storage. No custom storage layout or reachable boundary-spanning array is present. Dynamic metadata strings use ordinary hashed storage. |

SOL-2026-3 starts at compiler 0.8.29, outside the pinned version. These conclusions concern the examined configuration; changing compiler settings requires a new review.

## OpenZeppelin advisories

The [maintainers' advisory registry](https://github.com/OpenZeppelin/openzeppelin-contracts/security/advisories) returned 20 published records. [Retained records](generated/openzeppelin-advisories-20260908.json). The latest Bytes `lastIndexOf` advisory identifies 5.4.0 as patched; the pinned dependency is 5.5.0 and production does not invoke that function. The Base64 advisory was patched in 5.0.2; production does not use Base64. The remaining records concern older versions or components absent from the deployed system. No applicable published advisory was identified in this review.

## Deployment operations

Fable's optional N-05 documentation item is addressed in [operations](../docs/OPERATIONS.md): use at least one hour of lead time for hardware-wallet/multisig deployment, and treat a post-broadcast check failure as requiring investigation of an already-mined transaction. No rollback of a mined deployment is implied. No public deployment occurred in this audit.
