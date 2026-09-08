#!/usr/bin/env python3
"""Fail on tool errors, source drift, or any finding outside the explicitly reviewed snapshot."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
review = json.loads((ROOT / "audit/slither-reviewed.json").read_text())
report = json.loads(Path(sys.argv[1]).read_text())
assert report["success"] and not report.get("error"), "Slither did not complete successfully"
production = {str(path.relative_to(ROOT)) for path in (ROOT / "src").rglob("*.sol")}
assert production and set(review["sourceSha256"]) == production, "Static review must pin every production source"
for name, expected in review["sourceSha256"].items():
    actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
    assert actual == expected, f"{name} changed: repeat the static review"
findings = report["results"]["detectors"]
allowed = {item["id"]: item for item in review["findings"]}
assert len(allowed) == len(review["findings"]), "Duplicate review IDs"
for finding in findings:
    assert finding["id"] in allowed, f"Unreviewed {finding['check']}: {finding['description']}"
    entry = allowed[finding["id"]]
    assert entry["check"] == finding["check"] and entry["reason"], "Invalid review record"
assert {item["id"] for item in findings} == set(allowed), "Finding set changed: repeat the static review"
print(f"PASS: {len(findings)} individually reviewed Slither findings; no unreviewed findings or source drift.")
