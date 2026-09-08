#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/scripts/bin:$PATH"
export VIRTUAL_ENV="$PWD/.venv"
mkdir -p audit/generated
if [[ ! -x .venv/bin/slither ]]; then
  echo 'Install audit tools: python3 -m venv .venv && .venv/bin/pip install -r requirements-audit.txt' >&2
  exit 1
fi
npm run format:check 2>&1 | tee audit/generated/format.log
node --test scripts/foundry.test.mjs 2>&1 | tee audit/generated/native-runner-tests.log
.venv/bin/python scripts/test_audit_gates.py 2>&1 | tee audit/generated/audit-gate-tests.log
.venv/bin/python scripts/test_mutation_audit.py 2>&1 | tee audit/generated/mutation-runner-tests.log
# Slither reports reviewed design warnings. The following exact-match gate decides whether they are acceptable.
rm -f audit/generated/slither.final.json
.venv/bin/slither . --filter-paths 'lib/|test/|script/' --json audit/generated/slither.final.json --fail-none \
  > audit/generated/slither.log 2>&1
.venv/bin/python scripts/check_slither.py audit/generated/slither.final.json
node scripts/foundry.mjs forge coverage --no-match-contract '.*Invariant.*' --report summary --report lcov --exclude-tests \
  > audit/generated/coverage.log 2>&1
.venv/bin/python scripts/check_coverage.py
audit_seed="${AUDIT_FUZZ_SEED:-0x20260906}"
printf 'Extended audit fuzz seed: %s\n' "$audit_seed"
FOUNDRY_PROFILE=audit node scripts/foundry.mjs forge test --fuzz-seed "$audit_seed" \
  > audit/generated/extended-tests.log 2>&1
tail -3 audit/generated/extended-tests.log
.venv/bin/python scripts/mutation_audit.py | tee audit/generated/mutations.log
node scripts/foundry.mjs forge build --sizes > audit/generated/build.log 2>&1
.venv/bin/python scripts/local_e2e.py
echo 'PASS: all audit gates completed. Reports: audit/generated/'
