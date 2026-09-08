#!/usr/bin/env python3
"""Independent extra-mutant challenge of the package test suite (non-invariant tests, fuzz 16, fixed seed).
Mutants below are NOT in scripts/mutation_audit.py. A mutant 'survives' if zero behavioral tests fail."""
import json, shutil, subprocess, sys, tempfile
from pathlib import Path

POC = Path(sys.argv[1])
FORGE = sys.argv[2]
OUT = Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)
CONFIG_TESTS = {
    "test/RankedAuction.t.sol:RankedAuctionTest::testConfigurationAndBindings()",
    "test/TieredAllocation.t.sol:TieredAllocationTest::testFixedSupplyAnd24HourDuration()",
    "test/Deployment.t.sol:DeploymentTest::testLeadTimeAndFixed24HourDuration()",
}
RA, AE, RM = "RankedAuction", "AuctionEdition", "RoyaltyMarketplace"
MUTANTS = [
    ("RA extend boundary (>= -> >)", RA, "if (endTime - block.timestamp >= EXTENSION_WINDOW) return;", "if (endTime - block.timestamp > EXTENSION_WINDOW) return;"),
    ("RA always extend on increase", RA, "if (oldPrev != bid.prev) _extend();", "_extend();"),
    ("RA minimum bid boundary (< -> <=)", RA, "if (msg.value < minimumBid()) revert BidTooLow();", "if (msg.value <= minimumBid()) revert BidTooLow();"),
    ("RA settle boundary (< -> <=)", RA, "if (block.timestamp < endTime) revert AuctionNotEnded();", "if (block.timestamp <= endTime) revert AuctionNotEnded();"),
    ("RA phase boundary (< -> <=)", RA, "if (block.timestamp < endTime) return Phase.Live;", "if (block.timestamp <= endTime) return Phase.Live;"),
    ("RA unsold quantity boundary", RA, "if (quantity == 0 || quantity > unsoldRemaining) revert InvalidBatch();", "if (quantity == 0 || quantity >= unsoldRemaining) revert InvalidBatch();"),
    ("RA reserved quantity boundary", RA, "if (quantity == 0 || quantity > reservedRemaining) revert InvalidBatch();", "if (quantity == 0 || quantity >= reservedRemaining) revert InvalidBatch();"),
    ("RA creditRefunds not idempotent", RA, "if (bid.refundCredited) continue;", "if (bid.refundCredited) revert AlreadyClaimed();"),
    ("RA withdrawRefund keeps totalRefunds", RA, "refunds[msg.sender] = 0;\n        totalRefunds -= amount;", "refunds[msg.sender] = 0;"),
    ("RA auction address allowed as payout wallet", RA, "wallet == address(0) || wallet == address(this) || wallet == address(edition)", "wallet == address(0) || wallet == address(edition)"),
    ("RA anyone accepts pending wallet", RA, "if (proposed == address(0) || msg.sender != proposed) revert Unauthorized();", "if (proposed == address(0)) revert Unauthorized();"),
    ("RA capacity off by one in minimumBid", RA, "if (activeCount < SUPPLY) return reservePrice;", "if (activeCount <= SUPPLY) return reservePrice;"),
    ("RA anyone can increase another bid", RA, "if (bid.bidder != msg.sender) revert Unauthorized();", ""),
    ("RA tokensClaimed counter dropped", RA, "tokensClaimed += ids.length;", ""),
    ("RA _send to auction itself allowed", RA, "if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();", "if (recipient == address(0)) revert InvalidRecipient();"),
    ("RA pendingProceeds not zeroed", RA, "pendingProceeds = 0;", ""),
    ("RA _unlink drops successor prev", RA, "else bids[bid.next].prev = bid.prev;", "else { }"),
    ("RA _insert drops successor prev", RA, "else bids[current].prev = id;", "else { }"),
    ("RA displacement escrow not debited", RA, "escrow -= amount;\n            refunds[displaced.bidder] += amount;", "refunds[displaced.bidder] += amount;"),
    ("RA gross overcharges one clearing", RA, "uint256(bids[head].amount) + clearingPrice * (activeCount - 1)", "uint256(bids[head].amount) + clearingPrice * activeCount"),
    ("RA extension window 4 minutes", RA, "EXTENSION_WINDOW = 5 minutes", "EXTENSION_WINDOW = 4 minutes"),
    ("RA last rank left unassigned", RA, "for (uint256 rank = 1; id != 0; ++rank) {", "for (uint256 rank = 1; bids[id].next != 0; ++rank) {"),
    ("RA head/tail swap on unlink of head", RA, "if (bid.prev == 0) head = bid.next;", "if (bid.prev == 0) head = bid.next; else head = head;"),
    ("AE mint upper bound 101", AE, "if (id == 0 || id > MAX_SUPPLY || _ownerOf(id) != address(0)) revert InvalidMint();", "if (id == 0 || id > MAX_SUPPLY + 1 || _ownerOf(id) != address(0)) revert InvalidMint();"),
    ("AE royalty for any token id", AE, "if (tokenId > 0 && tokenId <= MAX_SUPPLY) {", "if (tokenId >= 0) {"),
    ("AE revocation of foreign operator blocked", AE, "if (approved && operator != address(marketplace)) revert RoyaltyTransferRequired();", "if (operator != address(marketplace)) revert RoyaltyTransferRequired();"),
    ("AE tokenURI for unminted id", AE, "_requireOwned(tokenId);", ""),
    ("AE nonce advances on mint", AE, "if (from != address(0)) ++transferNonce[tokenId];", "++transferNonce[tokenId];"),
    ("AE royalty rounds down", AE, "Math.Rounding.Ceil", "Math.Rounding.Floor"),
    ("RM buy expiry inclusive", RM, "if (!item.active || block.timestamp >= item.expiry) revert InvalidListing();", "if (!item.active || block.timestamp > item.expiry) revert InvalidListing();"),
    ("RM list expiry inclusive", RM, "if (price == 0 || expiry <= block.timestamp) revert InvalidListing();", "if (price == 0 || expiry < block.timestamp) revert InvalidListing();"),
    ("RM buy skips approval precheck", RM, "if (!_isApproved(item.seller, item.tokenId)) revert NotApproved();", ""),
    ("RM credits buyer instead of seller", RM, "credits[item.seller] += price - royalty;", "credits[msg.sender] += price - royalty;"),
    ("RM withdraw keeps totalCredits", RM, "credits[msg.sender] = 0;\n        totalCredits -= amount;", "credits[msg.sender] = 0;"),
    ("RM unsafe transferFrom", RM, "IERC721(edition).safeTransferFrom(item.seller, recipient, item.tokenId);", "IERC721(edition).transferFrom(item.seller, recipient, item.tokenId);"),
    ("RM anyone can list", RM, "if (IERC721(edition).ownerOf(tokenId) != msg.sender) revert NotSeller();", ""),
    ("RM cancel twice allowed", RM, "if (!item.active) revert InvalidListing();\n        item.active = false;", "item.active = false;"),
    ("RM edition allowed as recipient", RM, "if (recipient == address(0) || recipient == address(this) || recipient == edition) revert InvalidRecipient();", "if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();"),
    ("RM overpayment accepted", RM, "if (msg.value != price) revert IncorrectPayment();", "if (msg.value < price) revert IncorrectPayment();"),
    ("RM token id 101 listable", RM, "if (tokenId == 0 || tokenId > 100) revert InvalidToken();", "if (tokenId == 0 || tokenId > 101) revert InvalidToken();"),
    ("RM listing nonce recorded stale (+1)", RM, "ITransferNonce(edition).transferNonce(tokenId));", "ITransferNonce(edition).transferNonce(tokenId) + 1);"),
]


def tests_from(stdout):
    report = json.loads(stdout)
    out = {}
    for suite, result in report.items():
        for name, detail in result["test_results"].items():
            out[f"{suite}::{name}"] = detail
    return out


def main():
    results = []
    with tempfile.TemporaryDirectory(prefix="extra-mutants-") as tmp:
        target = Path(tmp)
        for name in ["src", "script", "lib"]:
            shutil.copytree(POC / name, target / name)
        shutil.copytree(POC / "test", target / "test", ignore=shutil.ignore_patterns("AuditFable2*"))
        shutil.copy2(POC / "foundry.toml", target / "foundry.toml")
        originals = {n: (target / f"src/{n}.sol").read_text() for n in [RA, AE, RM]}
        cmd = [FORGE, "test", "--root", str(target), "--offline", "--no-match-contract", ".*Invariant.*",
               "--fuzz-runs", "16", "--fuzz-seed", "0xFAB1E0907", "--json"]
        base = subprocess.run(cmd, cwd=target, capture_output=True, text=True, timeout=600)
        baseline = tests_from(base.stdout)
        assert base.returncode == 0 and all(t["status"] == "Success" for t in baseline.values()), "baseline failed"
        print(f"baseline: {len(baseline)} tests pass", flush=True)
        for i, (label, name, before, after) in enumerate(MUTANTS, 1):
            for n, text in originals.items():
                (target / f"src/{n}.sol").write_text(text)
            assert before in originals[name], f"stale mutant: {label}"
            (target / f"src/{name}.sol").write_text(originals[name].replace(before, after))
            run = subprocess.run(cmd, cwd=target, capture_output=True, text=True, timeout=600)
            entry = {"mutant": label, "file": name}
            if "Compiler run failed" in run.stderr or not run.stdout.strip().startswith("{"):
                entry.update(status="COMPILE-ERROR", stderr=run.stderr[-800:])
            else:
                tests = tests_from(run.stdout)
                failures = sorted(k for k, v in tests.items() if v["status"] == "Failure")
                behavioral = sorted(set(failures) - CONFIG_TESTS)
                entry.update(status="KILLED" if behavioral else ("CONFIG-ONLY" if failures else "SURVIVED"),
                             behavioralFailures=len(behavioral), failures=failures[:12],
                             inventoryMatches=set(tests) == set(baseline))
            results.append(entry)
            print(f"{i:02d} {entry['status']:13s} {label} ({entry.get('behavioralFailures', 0)} behavioral)", flush=True)
    (OUT / "extra-mutants.json").write_text(json.dumps(results, indent=2))
    survivors = [r for r in results if r["status"] != "KILLED"]
    print(f"\n{len(results) - len(survivors)}/{len(results)} killed; non-killed: {[r['mutant'] for r in survivors]}")


if __name__ == "__main__":
    main()
