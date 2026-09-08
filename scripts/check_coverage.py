#!/usr/bin/env python3
"""Require complete instrumented line, branch and function coverage for all production contracts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
expected = {str(path.relative_to(ROOT)) for path in (ROOT / "src").rglob("*.sol")}
assert expected, "No production sources found"
seen = set()
for record in (ROOT / "lcov.info").read_text().split("end_of_record"):
    lines = record.strip().splitlines()
    fields = dict(line.split(":", 1) for line in lines if ":" in line and not line.startswith(("DA:", "BRDA:", "FN:", "FNDA:")))
    path = fields.get("SF", "")
    if path.startswith("src/"):
        seen.add(path)
        for found, hit in [("LF", "LH"), ("BRF", "BRH"), ("FNF", "FNH")]:
            assert fields[found] == fields[hit], f"Incomplete {found} coverage in {path}: {fields[hit]}/{fields[found]}"
assert seen == expected, f"Production coverage inventory mismatch: missing={expected - seen}, unexpected={seen - expected}"
print("PASS: all production contracts have 100% instrumented line, branch and function coverage.")
