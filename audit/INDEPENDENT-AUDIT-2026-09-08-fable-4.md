# Independent audit — fourth pass (Fable) — 2026-09-08

**Target:** `encryptedvolume/LNTV-contracts` commit `1c7c1a9` ("Integrate upstream ERC721-C and OpenSea royalty enforcement"), package version 4.0.0. `main` at `60e7e42` carries the same four production sources byte for byte (only README, ISSUES, SHA256SUMS and `docs/VERSIONS.md` differ).

**Focus requested:** ERC721-C / OpenSea royalty enforcement and bypasses, admin permissions, payout rotation, auction accounting, refunds, reentrancy; full non-mutation suite; optional refund recovery 28 days after settlement treated as accepted design.

**Method:** source review of `src/*.sol`, the ten vendored Limit Break files, the vendored OpenSea registry/zone fixtures and the OpenSea integration tests; the package's non-mutation audit pipeline on an isolated copy; eight proof-of-concept tests kept outside the package test inventory; live read-only queries of Ethereum mainnet and Sepolia; fork tests executing `configureEnforcedTrading` against the real registry bytecode on both chains. Nothing was deployed or broadcast. Evidence: `audit/generated/independent-audit-20260908-fable-4/`.

**Environment:** macOS arm64, Node 22.23.1, Foundry 1.7.1 (npm-pinned binaries), solc 0.8.28, Slither 0.11.5, seed `0x2026090850`. Public RPCs `ethereum-rpc.publicnode.com` (block 25,933,207) and `ethereum-sepolia-rpc.publicnode.com` (block 11,661,609).

---

## 1. Verdict

| Area | Result |
|---|---|
| Auction accounting, refunds, settlement clock, batch bidding | No defect found. Source diff since my third pass (`0d52419`) is confined to the `_createBid` factoring, `settledAt`, and the `TokenRescue` base. Invariant campaigns (3 × 1,000 runs × 256 calls) conserve every wei. |
| Reentrancy | No exploitable path. All state-changing entry points on the three contracts are `nonReentrant`; ERC-721 receiver hooks run after state updates; `validateTransfer` on the registry is invoked via `staticcall` (declared `view`). |
| Payout rotation | Two-step flow unchanged and correct. Rotation now also moves ERC721-C administration and the registry's `owner()` check (verified on real registry bytecode). |
| ERC721-C enforcement on OpenSea/Seaport | Correct and fail-closed locally. **New High trusted-admin capability (F4-01)** and one **live divergence** from the local fixture (F4-02). |
| Non-mutation suite | Composite `npm run audit:nonmutation` **fails at the static-review pin** (expected, AUD-40). Every individual stage passes; the Slither delta is a single re-keyed finding. |
| Accepted design | Optional recovery at `settledAt + 28 days`, refunds open until a successful recovery: behaviour re-verified (unit, fuzz, invariant, Anvil rehearsal). Not re-litigated. |

Findings: 1 High (trusted-admin, fix verified), 3 Low, 2 Informational. No Critical. No fund-loss path for bidders or holders exists without the payout wallet acting maliciously.

---

## 2. Full non-mutation suite at 1c7c1a9

Run on an rsync copy (excluding `out/ cache/ node_modules/ .venv/ .tools/ .git`), `bash scripts/audit.sh --skip-mutations`, then the remaining stages individually after the gate stop.

| Stage | Result | Evidence |
|---|---|---|
| `forge fmt --check` | PASS | `suite/format.log` |
| Native-runner tests (`scripts/foundry.test.mjs`) | 2/2 PASS | `suite/native-runner-tests.log` |
| Audit-gate tests (`scripts/test_audit_gates.py`) | **9/10** — `test_reviewed_findings_pass` fails because `audit/slither-reviewed.json` pins the 3.3.0 `src/AuctionEdition.sol` hash. `audit.sh` stops here (`set -e`). | `suite/01-audit-sh-run.log` |
| Slither 0.11.5 (`--filter-paths lib/|test/|script/`) | Ran clean: 29 findings. `check_slither.py` fails on source drift only. Delta vs reviewed snapshot: **one re-keyed `costly-loop` on `AuctionEdition.mint` (bounded 100-token loop); zero new detector classes.** | `suite/slither.log`, `suite/slither.final.json.gz`, `slither-delta.txt` |
| Coverage (`forge coverage`, excluding invariants) | PASS gate: 100 % lines / branches / functions on all four production files. AuctionEdition statements 96/97 (not gated). | `suite/coverage.log` |
| Extended tests (`FOUNDRY_PROFILE=audit`, seed `0x2026090850`) | **220 passed, 0 failed, 0 skipped**; 8 fuzz tests × 10,000 runs; 3 invariant campaigns × 1,000 runs × 256 depth, 0 unexpected reverts; 700 s | `suite/extended-tests.log` |
| `forge build --sizes` | PASS. Runtime / initcode bytes: RankedAuction 11,973 / 32,525; AuctionEdition 11,484 / 19,095; RoyaltyMarketplace 5,944 / 6,105. All below EIP-170 and EIP-3860. | `suite/build.log` |
| `scripts/local_e2e.py` (Anvil 31337) | PASS, including trading configuration through `ConfigureTrading.s.sol` as the payout wallet, refund-recovery rehearsal (`lateSettlementPreservesFullRecoveryDelay: true`, `refundsStayOpenUntilRecovery: true`, `rejectedRecoveryLeavesRefundsOpen: true`), batch bidding and admin/rescue rehearsals; ending liabilities 0 | `suite/local-e2e.json`, `suite/local-trading-configuration.log` |
| Interface export (`--check`) | PASS, 4.0.0 | `suite/interface-check.log` |
| Mutation campaign | Not run (excluded by request; N-01 remains open) | — |

To make the composite command pass, refresh `audit/slither-reviewed.json`: replace the `src/AuctionEdition.sol` hash and swap the `costly-loop` id `dced4cdf…` for `062a2500…` with the same reason. No other static review work is outstanding for 4.0.0.

---

## 3. What was verified live versus locally

| Item | Local tests | This pass, live (read-only / fork) | Still required on a public chain |
|---|---|---|---|
| Registry `0xA000027A…5A0000`, SignedZone `0x000056F7…FD100`, Seaport 1.6, OpenSea conduit exist at the hardcoded addresses | Etched from source / runtime JSON | Code present on mainnet **and** Sepolia; registry runtime keccak identical on both chains (`0xc7dfe8ae…`); zone bytecode differs per chain only by chain-bound immutables | — |
| `configureEnforcedTrading()` succeeds against the real registry (including the duplicate add of SignedZone, which list 0 already holds) | Fixture list 0 is empty, so never exercised | **Executed on mainnet and Sepolia forks**: list created and owned by the edition, level 4 applied, SignedZone sole authorizer, OTC blocked, random operator blocked, local-market sale pays 10 % | Real transaction from the payout wallet |
| Contents of list 0 copied into the LNTV policy | Nothing copied | Owner `0x939C8d89…bA18A`; authorizer = SignedZone; **operators = `0x9A1D00bE…6834` and `0x9A1D0016…0515`, both Sourcify exact-match Limit Break `PaymentProcessor` 2.0.0** (deployer `deployer.limitbreak.eth`); blacklist empty. Identical on both chains. | Re-read at configuration time; OpenSea can change list 0 before you copy it |
| Seaport fill with SignedZone authorization pays 10 % | Real Seaport 1.6 + conduit runtimes, zone from source, **local signer** | Zone's live active signer is `0x2F16C6D6…8Fd2`; its signature cannot be produced locally | Testnet listing, buy and offer acceptance with OpenSea-generated fulfillment data |
| OpenSea Studio enforced earnings, ERC721-C indexing, owner detection after rotation | Not testable | Not testable | Studio configuration and a post-rotation check |
| Vendored Limit Break / OZ 4.8.3 / PermitC sources match the pinned upstream commits | In-repo manifest only | **All 21 files match `raw.githubusercontent.com` at the pinned commits** | — |
| Payout wallet recognised as collection owner by the registry (`owner()` → `payoutWallet()`) | Yes | Confirmed on real bytecode (level change to 1 accepted from the payout wallet) | — |

Evidence: `live-registry-queries.txt`, `poc-fork-mainnet.log`, `poc-fork-sepolia.log`, `upstream-provenance.txt`, `FableFork.t.sol`.

---

## 4. Findings

Severity follows the package's convention (impact × likelihood, trusted-admin findings keep their impact rating as with the accepted R-01 High).

### F4-01 — High (trusted admin) — Payout wallet can seize every holder's NFT through validator auto-approval

**Location.** `src/AuctionEdition.sol:136-138` (`_requireCallerIsContractOwner` → `owner()` → current payout wallet) gates both `setTransferValidator` (`lib/creator-token-standards/src/utils/CreatorTokenBase.sol:68`) and `setAutomaticApprovalOfTransfersFromValidator` (`lib/creator-token-standards/src/utils/AutomaticValidatorTransferApproval.sol:28`). `ERC721C.isApprovedForAll` (`lib/creator-token-standards/src/erc721c/ERC721C.sol:23-30`) then reports the validator as an approved operator for **every** holder, and `CreatorTokenBase._preValidateTransfer` (`CreatorTokenBase.sol:123`) skips validation entirely when `msg.sender == validator`. `AuctionEdition._preValidateTransfer` (`src/AuctionEdition.sol:160-167`) accepts any validator that has code.

**Impact.** The current payout wallet (or a wallet it rotates to, or anyone holding its key) can, in two transactions plus one call per token, transfer all 100 NFTs out of holders' wallets with no approval, no royalty and no marketplace. Before 1c7c1a9 (commit `737cbd7`) the payout wallet had no power over minted tokens; this is a new capability introduced by the migration. The runbook mentions that auto-approval "can grant the selected validator transfer authority over holders' NFTs", but ISSUES.md does not carry it as a finding and it is materially stronger than "could weaken enforcement".

**Reproduction.** `FableFourthPass.t.sol::testF4_01_PayoutWalletSeizesHolderTokenViaValidatorAutoApproval` (all 100 tokens moved from alice to the payout wallet, royalty 0). Controls: without auto-approval the malicious validator cannot move tokens (`…Control_MaliciousValidatorWithoutAutoApprovalCannotSeize`); auto-approval with the real registry is inert until a later validator swap (`…Control_AutoApprovalAloneWithRealRegistry`). Log: `poc-unit.log`.

**Fix (verified).** Neutralise the flag in the edition without touching the vendored library. `setAutomaticApprovalOfTransfersFromValidator` is not virtual, but `isApprovedForAll` is:

```solidity
// src/AuctionEdition.sol — add import (direct path: the @openzeppelin remapping in src/ resolves to 5.5.0)
import { ERC721 } from "../lib/openzeppelin-contracts-v4/contracts/token/ERC721/ERC721.sol";

/// @dev The validator is never an implicit operator; only explicit holder approvals count.
function isApprovedForAll(address owner_, address operator) public view override returns (bool) {
    return ERC721.isApprovedForAll(owner_, operator);
}
```

`FableFixCheck.t.sol` applies this as a subclass: the seizure reverts with `ERC721: caller is not token owner or approved`, explicit approvals still work, and the unpatched edition remains seizable in the same run (`poc-fix-check.log`). Optional additional hardening: pin the validator in `_preValidateTransfer` (`if (getTransferValidator() != OPENSEA_TRANSFER_VALIDATOR) revert RoyaltyTransferRequired();`), which also closes the royalty-weakening path of an arbitrary validator at the cost of needing a redeploy if OpenSea ever moves the registry. If the creator prefers to accept F4-01 by design, record it in ISSUES.md with this High rating next to R-01, and disclose to holders that the payout wallet can move their NFTs.

### F4-02 — Low (verification / documentation) — Live list 0 whitelists two operators the local fixture never sees

**Location.** `src/AuctionEdition.sol:149` (`createListCopy("LNTV royalty enforcement", 0)`); `test/TradingTestSetup.sol:12-16` (etched registry with empty storage, so list 0 has no owner and no entries); `scripts/check_deployment.py:70-74` (only asserts that Seaport/conduit are absent).

**Observation.** On both public chains list 0 currently contains the SignedZone authorizer plus two unconditional whitelisted operators, the Limit Break `PaymentProcessor` 2.0.0 deployments `0x9A1D00bEd7CD04BCDA516d721A596eb22Aac6834` and `0x9A1D001670C8b17F8B7900E8d7a41e785B3F0515`. After configuration these transfer LNTV tokens with a plain `setApprovalForAll` and no SignedZone authorization (fork test: `validateTransfer(PP, …)` passes, a random operator reverts). Payment Processor is a royalty-enforcing exchange (its trade modules pay ERC-2981 royalties; `royaltyBackfillNumerator` is only a fallback for collections without ERC-2981), so this is not a bypass, but: (a) no package document names them; (b) no local test exercises inherited operators; (c) the copy is a snapshot taken at configuration time from a list owned by OpenSea (`0x939C8d89EBC11fA45e576215E2353673AD0bA18A`), whose contents can differ at that moment; (d) the deployment checker would accept any extra operator that is not Seaport or the conduit. The Payment Processor module code was not audited in this pass.

**Reproduction.** `live-registry-queries.txt`; `FableFork.t.sol::testLiveRegistryConfiguration` on both chains; `FableFourthPass.t.sol::testF4_05_ListZeroContentsAreInheritedByConfiguration` (fixture seeded with an arbitrary operator becomes royalty-free after the copy).

**Fix.** Either construct the list explicitly (`createList` + `addAccountToAuthorizers(SignedZone)` + `addAccountToWhitelist(marketplace)` + any deliberately chosen processors) so the policy is fully known at compile time, or keep the copy and (1) document the expected operator set in `docs/OPENSEA.md`, (2) make `check_deployment.py` assert the whitelist equals exactly `{marketplace, PP-1, PP-2}` and the authorizer set equals `{SignedZone}`, and (3) read list 0 immediately before broadcasting the configuration.

### F4-03 — Low (operational, disclosed) — A payout-wallet-created list survives rotation under the old wallet

**Location.** `src/AuctionEdition.sol:145-158` (the edition owns only the list it creates; there is no edition-mediated add/remove, so a creator who needs another venue must own a list personally, as `test/OpenSeaIntegration.t.sol:380-395` demonstrates).

**Observation.** After rotation the previous wallet still owns and can edit the applied list, including adding a royalty-free operator; the new wallet cannot edit it and its only remedy is a full `configureEnforcedTrading()` re-run. `docs/OPENSEA.md` discloses this in one sentence; the PoC quantifies it (`testF4_03_OldPayoutWalletKeepsCustomListAfterRotation`).

**Fix.** Add owner-gated `addTrustedOperator(address)` / `removeTrustedOperator(address)` on the edition that operate on `tradingListId` (the edition is that list's owner), so no wallet ever needs to own a registry list. Until then, the rotation runbook should require the new wallet to re-run configuration.

### F4-04 — Low (integration) — No `OwnershipTransferred` event from the edition on rotation

**Location.** `src/AuctionEdition.sol:127-129` (`owner()` is derived); `src/RankedAuction.sol:144-151` (`acceptPayoutWallet` emits only `PayoutWalletChanged`).

**Observation.** ERC-173 consumers (OpenSea Studio ownership, Etherscan, indexers) commonly cache the owner from `OwnershipTransferred`. The edition emits nothing on rotation (`testF4_04_NoOwnershipTransferredEventOnEdition`), so Studio may keep showing the old wallet as the collection admin until it re-reads `owner()`.

**Fix.** Have `acceptPayoutWallet` call an auction-only `edition.syncOwner(previous, next)` that emits `OwnershipTransferred(previous, next)`. Verify on testnet that Studio reflects the new admin after rotation (cannot be checked locally).

### F4-05 — Informational (process) — The committed static-review pin blocks the composite non-mutation run

See section 2. AUD-40 already tracks this; the refresh is one hash and one finding id.

### F4-06 — Informational (operations) — Payout wallet must accept pushed ETH

Seaport pays native consideration by `call` and reverts the fill if the recipient rejects. The auction and local marketplace are pull-based, but on OpenSea a non-payable contract payout wallet makes every ETH sale fail until rotation. Add to `docs/OPERATIONS.md`: the payout wallet must accept plain ETH transfers and ERC-20 transfers (Payment Processor and Seaport ERC-20 offers pay royalties in the sale token).

### Other observations (no action required)

- The edition's constructor calls Limit Break's default validator `0x721C008fdff27BF06E7E123956E2Fe03B63342e3` (`setTokenTypeOfCollection`, inside try/catch; code present on both chains) and emits `TransferValidatorUpdated(0, 0x721C008f…)`. Until `configureEnforcedTrading` runs, indexers will show that validator, but `tradingConfigured` keeps transfers blocked.
- `0x963f00d3…c300` in `check_deployment.py`'s unsafe-operator list has no code on mainnet or Sepolia; harmless.
- `configureEnforcedTrading` can be re-run to reset the policy; each run orphans the previous edition-owned list.
- Per-token price understatement on any venue (including the local marketplace at 1 wei) remains the universal royalty limitation the runbook already discloses.

---

## 5. Focus-area notes

**Enforcement path.** OZ 4.8.3 `_transfer`/`_mint` → `ERC721C._beforeTokenTransfer` → `TransferValidation._validateBeforeTransfer` → `AuctionEdition._preValidateTransfer` (fail-closed on `!tradingConfigured` or a code-less validator) → `CreatorTokenBase._preValidateTransfer` → `registry.validateTransfer(caller, from, to, id)` (staticcall). Mint and burn skip the validator (no burn exists). Level 4 on the strict registry means: no policy bypass, whitelist-based, direct (`caller == from`) transfers disabled, no receiver constraints. Approved operators must be whitelisted or carry a transient per-token authorization set by SignedZone during a Seaport fill. `_postValidateTransfer` bumps `transferNonce`, which invalidates local listings after any external transfer (verified in the Seaport tests).

**Admin permission matrix (current payout wallet).** Auction: proceeds, unsold/reserved claims, recovery after `settledAt + 28d`, rescue. Edition: metadata base, `setTransferValidator`, auto-approval flag, `configureEnforcedTrading`, rescue, and (through `owner()`) the registry's `applyListToCollection` / `setTransferSecurityLevelOfCollection` for this collection. Marketplace: royalty pool, rescue. It cannot: take winners' unclaimed IDs, take seller credits, change the royalty rate, reopen the auction, or, without F4-01, move minted NFTs.

**Bypass review.** Direct transfer: blocked. Arbitrary approved operator: blocked. Seaport open order / conduit approval alone / missing, fake, expired, wrong-fulfiller signature / royalty stripped from an authorized order / authorization reused for another token / replay: all revert (package tests, real Seaport runtime). Rescue functions: reject the edition token on all three contracts and expose no arbitrary call. Whitelisted local marketplace: computes royalty from the immutable 10 % on the declared price. Remaining bypasses are the disclosed off-chain ones and the admin paths in F4-01/F4-02/F4-03.

**Auction accounting and refunds.** `escrow` is the sum of active bids before settlement and the sum of winner overpayments after; `gross = head + clearing × (active − 1)` is subtracted exactly once; displaced bids and credited overpayments move to `_refunds`/`totalRefunds`; `withdrawUnclaimedETH` sweeps the balance and zeroes the three accumulators only when eligible, and `refundsClosed` gates only credits and withdrawals. Batch bidding shares `_createBid`, checks the exact sum once, and self-displacement within a batch credits refunds correctly (tests, fuzz, invariants, rehearsal). `settledAt` is recorded once; settle-and-sweep in one transaction reverts (rehearsal `withdrawUnclaimedETH` at eligibility − 1 s rejected).

**Reentrancy.** Every external state-changing function on the three contracts is `nonReentrant`; ETH leaves only via `_send`/`withdraw*` after state updates; ERC-721 receiver callbacks in `claimTokens`, `claimUnsold`, `claimReserved`, `RoyaltyMarketplace.buy` and the rescue functions occur after all state changes and cannot re-enter guarded functions. The registry is called via staticcall. Adversarial receivers in the package tests (`ReentrantReceiver`) cover the auction, marketplace and rescue paths.

---

## 6. Open items carried forward

- N-01 (mutation gap on `_unlink` back-pointer) — unchanged, mutation campaign not run.
- AUD-40 — static-review refresh (section 2).
- OS-01 / DEP-01 — live OpenSea signature, Studio earnings, indexing, post-rotation ownership, Payment Processor trade: only on a public chain.

## 7. Reproduction

```bash
# suite (isolated copy, Node 22)
rsync -a --exclude out --exclude cache --exclude node_modules --exclude .venv --exclude .tools --exclude .git . /tmp/lntv/
ln -s "$PWD/node_modules" /tmp/lntv/node_modules; ln -s "$PWD/.venv" /tmp/lntv/.venv
cd /tmp/lntv && AUDIT_FUZZ_SEED=0x2026090850 bash scripts/audit.sh --skip-mutations   # stops at the static pin
FOUNDRY_PROFILE=audit node scripts/foundry.mjs forge test --fuzz-seed 0x2026090850   # 220 passed
# PoCs (copy test/poc from the evidence directory into a scratch checkout's test/poc/)
node scripts/foundry.mjs forge test --match-path 'test/poc/FableFourthPass.t.sol' -vv
node scripts/foundry.mjs forge test --match-path 'test/poc/FableFixCheck.t.sol' -vv
FORK_RPC=https://ethereum-rpc.publicnode.com          node scripts/foundry.mjs forge test --match-path 'test/poc/FableFork.t.sol' -vv
FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com  node scripts/foundry.mjs forge test --match-path 'test/poc/FableFork.t.sol' -vv
# live reads
cast call 0xA000027A9B2802E1ddf7000061001e5c005A0000 'getWhitelistedAccounts(uint120)(address[])' 0 --rpc-url https://ethereum-rpc.publicnode.com
```

## 8. Evidence index (`audit/generated/independent-audit-20260908-fable-4/`)

`FableFourthPass.t.sol`, `FableFixCheck.t.sol`, `FableFork.t.sol` (PoC sources); `poc-unit.log`, `poc-fix-check.log`, `poc-fork-mainnet.log`, `poc-fork-sepolia.log`; `live-registry-queries.txt`; `upstream-provenance.txt`; `slither-delta.txt`; `suite/` (all stage logs, `local-e2e.json`, gzipped Slither JSON). This audit did not modify any file under `src/`, `test/`, `script/` or `scripts/`.
