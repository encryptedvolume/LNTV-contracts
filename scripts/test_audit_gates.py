#!/usr/bin/env python3
"""Regression tests ensuring the report gates reject missing coverage, changed source, and new findings."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AuditGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="auction-gates-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ["src", "scripts"]:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns("__pycache__"))
        (self.root / "audit").mkdir()
        shutil.copy(ROOT / "audit/slither-reviewed.json", self.root / "audit/slither-reviewed.json")
        review = json.loads((self.root / "audit/slither-reviewed.json").read_text())
        self.report = {"success": True, "error": None, "results": {"detectors": [
            {"id": item["id"], "check": item["check"], "description": "test fixture"} for item in review["findings"]]}}

    def static_gate(self):
        path = self.root / "report.json"
        path.write_text(json.dumps(self.report))
        return subprocess.run([sys.executable, str(self.root / "scripts/check_slither.py"), str(path)], capture_output=True).returncode

    def test_reviewed_findings_pass(self):
        self.assertEqual(self.static_gate(), 0)

    def test_new_finding_fails(self):
        self.report["results"]["detectors"].append({"id": "unreviewed", "check": "arbitrary-send-eth", "description": "new"})
        self.assertNotEqual(self.static_gate(), 0)

    def test_changed_source_fails(self):
        with (self.root / "src/RankedAuction.sol").open("a") as source:
            source.write("\n// changed\n")
        self.assertNotEqual(self.static_gate(), 0)

    def test_missing_finding_requires_new_review(self):
        self.report["results"]["detectors"].pop()
        self.assertNotEqual(self.static_gate(), 0)

    def test_failed_analyzer_fails(self):
        self.report["success"] = False
        self.assertNotEqual(self.static_gate(), 0)

    def coverage_gate(self, hit=1, omit=False):
        contracts = ["AuctionEdition", "RankedAuction", "RoyaltyMarketplace"]
        if omit:
            contracts.pop()
        records = [f"SF:src/{name}.sol\nLF:1\nLH:{hit}\nBRF:1\nBRH:1\nFNF:1\nFNH:1\nend_of_record\n" for name in contracts]
        (self.root / "lcov.info").write_text("".join(records))
        return subprocess.run([sys.executable, str(self.root / "scripts/check_coverage.py")], capture_output=True).returncode

    def test_complete_coverage_passes(self):
        self.assertEqual(self.coverage_gate(), 0)

    def test_missing_coverage_fails(self):
        self.assertNotEqual(self.coverage_gate(hit=0), 0)
        self.assertNotEqual(self.coverage_gate(omit=True), 0)


if __name__ == "__main__":
    unittest.main()
