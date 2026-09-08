#!/usr/bin/env python3
"""Require a clean baseline and two behavioral test failures per compiled security mutation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
# Exact replacements intentionally fail closed if the implementation changes.
MUTANTS = [
    ("zero outbid increment", "RankedAuction", "OUTBID_BPS = 500", "OUTBID_BPS = 0"),
    ("old 2.5 percent outbid increment restored", "RankedAuction", "OUTBID_BPS = 500", "OUTBID_BPS = 250"),
    ("zero increase increment", "RankedAuction", "INCREASE_BPS = 250", "INCREASE_BPS = 0"),
    ("old 0.5 percent increase increment restored", "RankedAuction", "INCREASE_BPS = 250", "INCREASE_BPS = 50"),
    ("wrong supply", "RankedAuction", "SUPPLY = 90", "SUPPLY = 91"),
    ("two-hour extension cap restored", "RankedAuction", "endTime = block.timestamp + EXTENSION_WINDOW;", "if (block.timestamp + EXTENSION_WINDOW > uint256(initialEndTime) + 2 hours) return; endTime = block.timestamp + EXTENSION_WINDOW;"),
    ("extension timestamp narrowed", "RankedAuction", "endTime = block.timestamp + EXTENSION_WINDOW;", "endTime = uint64(block.timestamp + EXTENSION_WINDOW);"),
    ("reversed tie priority", "RankedAuction", "id < current", "id > current"),
    ("loser refund shortfall", "RankedAuction", "refunds[displaced.bidder] += amount;", "refunds[displaced.bidder] += amount - 1;"),
    ("wrong clearing price", "RankedAuction", "reservePrice : bids[tail].amount", "reservePrice : bids[head].amount"),
    ("settlement double liability", "RankedAuction", "escrow -= gross;", "escrow -= 0;"),
    ("stealable claims", "RankedAuction", "if (bid.tokenClaimed) revert AlreadyClaimed();\n            if (msg.sender != bid.bidder) revert Unauthorized();", "if (bid.tokenClaimed) revert AlreadyClaimed();"),
    ("repeatable refund credit", "RankedAuction", "bid.refundCredited = true;", "bid.refundCredited = false;"),
    ("repeatable token claim", "RankedAuction", "bid.tokenClaimed = true;", "bid.tokenClaimed = false;"),
    ("stolen payout funds", "RankedAuction", "if (msg.sender != payoutWallet) revert Unauthorized();", ""),
    ("auction reentrancy guard removed", "RankedAuction", "nonReentrant", ""),
    ("royalty transfer bypass", "AuctionEdition", "if (_ownerOf(tokenId) != address(0) && msg.sender != address(marketplace))", "if (false)"),
    ("missing supply accounting", "AuctionEdition", "++totalSupply;", "totalSupply += 0;"),
    ("zeroed royalties", "AuctionEdition", "royaltyBps, 10_000, Math.Rounding.Ceil", "0, 10_000, Math.Rounding.Ceil"),
    ("free purchase", "RoyaltyMarketplace", "if (msg.value != price) revert IncorrectPayment();", ""),
    ("royalty double credit", "RoyaltyMarketplace", "credits[item.seller] += price - royalty;", "credits[item.seller] += price;"),
    ("unauthorized cancellation", "RoyaltyMarketplace", "if (item.seller != msg.sender) revert NotSeller();", ""),
    ("repeatable marketplace withdrawal", "RoyaltyMarketplace", "credits[msg.sender] = 0;", ""),
    ("marketplace reentrancy guard removed", "RoyaltyMarketplace", "nonReentrant", ""),
    ("primary auction royalty deduction", "RankedAuction", "pendingProceeds = gross;", "pendingProceeds = gross - gross * edition.royaltyBps() / 10000;"),
    ("unauthorized wallet acceptance", "RankedAuction", "if (proposed == address(0) || msg.sender != proposed) revert Unauthorized();", ""),
    ("wallet nomination takes immediate control", "RankedAuction", "pendingPayoutWallet = proposed;", "pendingPayoutWallet = proposed; payoutWallet = proposed;"),
    ("accepted wallet not applied", "RankedAuction", "payoutWallet = proposed;", ""),
    ("stale pending wallet retained", "RankedAuction", "pendingPayoutWallet = address(0);", ""),
    ("unsafe payout wallet allowed", "RankedAuction", "_validatePayoutWallet(proposed);", ""),
    ("rotation erases accrued auction proceeds", "RankedAuction", "payoutWallet = proposed;", "payoutWallet = proposed; pendingProceeds = 0;"),
    ("royalty recipient ignores shared wallet", "AuctionEdition", "IAuctionPayout(auction).payoutWallet()", "auction"),
    ("stealable trading royalties", "RoyaltyMarketplace", "if (msg.sender != wallet) revert NotPayoutWallet();", ""),
    ("repeatable royalty withdrawal", "RoyaltyMarketplace", "pendingRoyalties = 0;", ""),
    ("forced third-party mint delivery", "RankedAuction", "if (bid.tokenClaimed) revert AlreadyClaimed();\n            if (msg.sender != bid.bidder) revert Unauthorized();", "if (bid.tokenClaimed) revert AlreadyClaimed();\n            if (msg.sender != bid.bidder && recipient != bid.bidder) revert Unauthorized();"),
    ("royalty pool double credit", "RoyaltyMarketplace", "pendingRoyalties += royalty;", "pendingRoyalties += royalty * 2;"),
    ("rank-to-token assignment reversed", "RankedAuction", "bids[id].tokenId = uint16(rank);", "bids[id].tokenId = uint16(SUPPLY - rank + 1);"),
    ("bid ID used instead of awarded token ID", "RankedAuction", "tokenIds[i] = bid.tokenId;", "tokenIds[i] = ids[i];"),
    ("unsold mint consumes winning token IDs", "RankedAuction", "uint256 firstTokenId = SUPPLY - unsoldRemaining + 1;", "uint256 firstTokenId = 1;"),
    ("unauthorized ERC721 mint", "AuctionEdition", "if (msg.sender != auction) revert Unauthorized();", ""),
    ("ERC721 token approval bypass", "AuctionEdition", "if (to != address(0) && to != address(marketplace))", "if (false)"),
    ("missing transfer nonce", "AuctionEdition", "++transferNonce[tokenId];", "transferNonce[tokenId] += 0;"),
    ("stale listing nonce ignored", "RoyaltyMarketplace", "if (ITransferNonce(edition).transferNonce(item.tokenId) != item.transferNonce) revert InvalidListing();", ""),
    ("ERC721 listing stays active after sale", "RoyaltyMarketplace", "item.active = false;", "item.active = true;"),
    ("ERC721 supply exceeds 100", "AuctionEdition", "MAX_SUPPLY = 100", "MAX_SUPPLY = 101"),
    ("ERC721 receiver check bypassed", "AuctionEdition", "_safeMint(recipient, id);", "_mint(recipient, id);"),
    ("top winner gets cutoff discount", "RankedAuction", "return id == head ? bids[id].amount : clearingPrice;", "return clearingPrice;"),
    ("regular winner pays full bid", "RankedAuction", "return id == head ? bids[id].amount : clearingPrice;", "return bids[id].amount;"),
    ("uniform primary proceeds restored", "RankedAuction", "uint256(bids[head].amount) + clearingPrice * (activeCount - 1)", "clearingPrice * activeCount"),
    ("empty auction settlement underflows", "RankedAuction", "activeCount == 0 ? 0 : uint256(bids[head].amount)", "uint256(bids[head].amount)"),
    ("wrong initial duration", "RankedAuction", "AUCTION_DURATION = 24 hours", "AUCTION_DURATION = 1 hours"),
    ("wrong reserved allocation", "RankedAuction", "RESERVED_SUPPLY = 10", "RESERVED_SUPPLY = 11"),
    ("reserved IDs overlap auction", "RankedAuction", "SUPPLY + RESERVED_SUPPLY - reservedRemaining + 1", "RESERVED_SUPPLY - reservedRemaining + 1"),
    ("reserved batch ignores quantity", "RankedAuction", "reservedRemaining -= quantity;", "reservedRemaining -= 1;"),
    ("reserved batch starts at wrong ID", "RankedAuction", "SUPPLY + RESERVED_SUPPLY - reservedRemaining + 1", "SUPPLY + RESERVED_SUPPLY - reservedRemaining + 2"),
    ("metadata ignores token ID", "AuctionEdition", 'return string.concat(metadataURI, Strings.toString(tokenId), ".json");', "return metadataURI;"),
    ("metadata slash validation bypassed", "AuctionEdition", 'if (bytes(metadataURI_)[bytes(metadataURI_).length - 1] != bytes1("/"))', 'if (false)'),
]

# These tests primarily assert configuration values; they cannot establish behavioral kill redundancy.
CONFIGURATION_TESTS = {
    "test/RankedAuction.t.sol:RankedAuctionTest::testConfigurationAndBindings()",
    "test/TieredAllocation.t.sol:TieredAllocationTest::testFixedSupplyAnd24HourDuration()",
    "test/Deployment.t.sol:DeploymentTest::testLeadTimeAndFixed24HourDuration()",
}
BEHAVIOR_SUITE = "test/MutationBehavior.t.sol:MutationBehaviorTest"
# Pin the separately reviewed scenarios so removing one cannot silently weaken a previously flagged case.
REQUIRED_BEHAVIORS = {
    "old 2.5 percent outbid increment restored": ["testNewBidRoundsFivePercentUpBeforeDisplacingWeiPricedTail"],
    "old 0.5 percent increase increment restored": ["testInsufficientTopUpCannotChangeRankOrDelayClosing"],
    "two-hour extension cap restored": ["testRankIncreasesKeepAuctionLiveBeyondFormerCap"],
    "extension timestamp narrowed": ["testRankIncreaseAcrossUint64BoundaryPreservesBiddingAndSettlement"],
    "royalty transfer bypass": ["testPurchasedNftRequiresAnotherRoyaltyPayingSaleToTransferAgain"],
    "free purchase": ["testFreePurchaseCannotSpendExistingSellerProceeds"],
    "unauthorized cancellation": ["testFormerSellerCannotCancelCurrentOwnersResale"],
    "repeatable marketplace withdrawal": ["testSellerCannotWithdrawTwiceUsingAnotherSellersBalance"],
    "unsafe payout wallet allowed": ["testInvalidNomineeCannotEraseUsablePayoutReplacement"],
    "forced third-party mint delivery": ["testRefundCreditDoesNotAuthorizeForcedBatchMint"],
    "unauthorized ERC721 mint": ["testMintReceiverCannotMintAnUnallocatedAuctionToken"],
    "ERC721 token approval bypass": ["testPurchasedNftRejectsTokenApprovalToFormerSeller"],
    "metadata slash validation bypassed": ["testStandaloneEditionRequiresSeparatorForMintedTokenEndpoints"],
    "wrong initial duration": ["testBiddingRemainsOpenAtHour23", "testSettlementCannotReleaseFundsAtHourTwo"],
}


def collect_tests(stdout):
    """Read native Forge JSON; setup failures, empty runs and non-test errors are not mutation kills."""
    report = json.loads(stdout)
    if not isinstance(report, dict) or not report:
        raise ValueError("Missing Forge test suites")
    tests = {}
    for suite, result in report.items():
        if not isinstance(result, dict) or not isinstance(result.get("test_results"), dict):
            raise ValueError(f"Invalid Forge suite: {suite}")
        if not result["test_results"]:
            raise ValueError(f"Empty Forge suite: {suite}")
        for name, detail in result["test_results"].items():
            if not name.startswith("test") or not isinstance(detail, dict):
                raise ValueError(f"Non-test failure or invalid test result: {suite}::{name}")
            if detail.get("status") not in {"Success", "Failure"}:
                raise ValueError(f"Skipped or unknown test result: {suite}::{name}")
            tests[f"{suite}::{name}"] = detail
    return tests


def evaluate_mutation(label, run, baseline_tests):
    result = {"mutation": label, "killed": False, "strengthPassed": False,
              "failedTests": [], "behavioralFailures": [], "missingRequiredBehaviors": []}
    if "Compiler run failed" in run.stderr:
        result["error"] = "Compilation failed"
        return result
    try:
        tests = collect_tests(run.stdout)
    except (ValueError, TypeError) as error:
        result["error"] = str(error)
        return result
    if set(tests) != set(baseline_tests):
        result["error"] = "Mutation test inventory differs from the clean baseline"
        return result
    failures = sorted(name for name, detail in tests.items() if detail["status"] == "Failure")
    behavioral = sorted(set(failures) - CONFIGURATION_TESTS)
    required = {f"{BEHAVIOR_SUITE}::{name}()" for name in REQUIRED_BEHAVIORS.get(label, [])}
    result.update(failedTests=failures, behavioralFailures=behavioral,
                  failureReasons={name: tests[name].get("reason") for name in failures},
                  missingRequiredBehaviors=sorted(required - set(behavioral)))
    result["killed"] = run.returncode == 1 and bool(failures)
    result["strengthPassed"] = result["killed"] and len(behavioral) >= 2 and not result["missingRequiredBehaviors"]
    return result


def validate_baseline(run):
    tests = collect_tests(run.stdout)
    if run.returncode != 0 or any(test["status"] != "Success" for test in tests.values()):
        raise RuntimeError("Unmodified contracts must pass the same tests before mutations are evaluated")
    return tests


def main(output_dir=None):
    output_dir = Path(output_dir) if output_dir is not None else ROOT / "audit/generated"
    output_dir.mkdir(parents=True, exist_ok=True)
    forge = subprocess.check_output(["node", "scripts/foundry.mjs", "forge", "--print-path"], cwd=ROOT, text=True).strip()
    results = []
    with tempfile.TemporaryDirectory(prefix="auction-mutants-") as temporary:
        target = Path(temporary)
        for name in ["src", "test", "script", "lib"]:
            shutil.copytree(ROOT / name, target / name)
        shutil.copy2(ROOT / "foundry.toml", target / "foundry.toml")
        inputs = {str(path.relative_to(target)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for directory in ["src", "test", "script", "lib"]
                  for path in sorted((target / directory).rglob("*.sol"))}
        inputs["foundry.toml"] = hashlib.sha256((target / "foundry.toml").read_bytes()).hexdigest()
        runner_digest = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        originals = {name: (target / f"src/{name}.sol").read_text() for name in ["RankedAuction", "AuctionEdition", "RoyaltyMarketplace"]}
        command = [forge, "test", "--root", str(target), "--offline", "--no-match-contract",
                   ".*Invariant.*", "--fuzz-runs", "16", "--fuzz-seed", "0x20260907", "--json"]
        baseline = subprocess.run(command, cwd=target, capture_output=True, text=True, timeout=120)
        (output_dir / "mutation-baseline.json").write_text(baseline.stdout)
        (output_dir / "mutation-baseline.stderr.log").write_text(baseline.stderr)
        baseline_tests = validate_baseline(baseline)
        required_tests = {f"{BEHAVIOR_SUITE}::{name}()" for names in REQUIRED_BEHAVIORS.values() for name in names}
        if not required_tests.issubset(baseline_tests):
            raise RuntimeError(f"Missing required behavioral tests: {sorted(required_tests - set(baseline_tests))}")
        print(f"Clean baseline: {len(baseline_tests)} tests passed; required behavioral scenarios present.", flush=True)
        for index, (label, name, before, after) in enumerate(MUTANTS, start=1):
            for source, text in originals.items():
                (target / f"src/{source}.sol").write_text(text)
            if before not in originals[name]:
                raise RuntimeError(f"Stale mutation: {label}")
            (target / f"src/{name}.sol").write_text(originals[name].replace(before, after))
            run = subprocess.run(command, cwd=target, capture_output=True, text=True, timeout=120)
            (output_dir / f"mutation-{index:02d}.json").write_text(run.stdout)
            (output_dir / f"mutation-{index:02d}.stderr.log").write_text(run.stderr)
            result = evaluate_mutation(label, run, baseline_tests)
            results.append(result)
            print(f"{'KILLED' if result['strengthPassed'] else 'FAILED GATE'}: {label} "
                  f"({len(result['behavioralFailures'])} behavioral tests)", flush=True)
            if not result["strengthPassed"]:
                print(json.dumps(result, indent=2))
    output = output_dir / "mutations.json"
    output.write_text(json.dumps(results, indent=2) + "\n")
    (output_dir / "mutation-inputs.json").write_text(json.dumps({
        "fuzzSeed": "0x20260907", "fuzzRuns": 16, "baselineTests": len(baseline_tests),
        "minimumBehavioralFailures": 2,
        "inputSha256": inputs, "runnerSha256": runner_digest,
    }, indent=2) + "\n")
    if not all(item["strengthPassed"] for item in results):
        raise SystemExit(1)
    print(f"All {len(results)} intentional regressions were detected by at least two behavioral tests.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, help="Evidence directory; defaults to audit/generated")
    main(parser.parse_args().output_dir)
