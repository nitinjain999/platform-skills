#!/usr/bin/env bash
# Validates runtime-security example files: YAML syntax check.
# Run from repository root: bash examples/runtime-security/runtime-security-validate.sh

set -euo pipefail

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

EXAMPLE_DIR="examples/runtime-security"

echo ""
echo "=== Runtime Security Examples: YAML syntax ==="

if ! command -v yq &> /dev/null; then
  echo "  INFO: yq not found — skipping YAML lint (install: https://github.com/mikefarah/yq)"
else
  for f in "$EXAMPLE_DIR"/*.yaml; do
    if yq eval 'true' "$f" > /dev/null 2>&1; then
      pass "$f is valid YAML"
    else
      fail "$f has invalid YAML"
    fi
  done
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS error(s)"
  exit 1
fi
echo "PASS: all runtime-security example checks passed"
