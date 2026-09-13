#!/usr/bin/env bash
# tests/triage-script.sh — validates triage_helper.py without a live PR/session
set -euo pipefail

HELPER="examples/triage/scripts/triage_helper.py"

echo "--- Test 1: python3 syntax check ---"
python3 -m py_compile "$HELPER"
echo "PASS: no syntax errors"

echo "--- Test 2: --help exits 0 ---"
python3 "$HELPER" --help >/dev/null
echo "PASS: --help works"

echo "--- Test 3: unittest suite ---"
python3 -m unittest examples/triage/tests/test_triage_helper.py -v
echo "PASS: unittest suite green"
