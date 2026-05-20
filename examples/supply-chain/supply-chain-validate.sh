#!/usr/bin/env bash
# Validates supply-chain example files: YAML syntax check.
# Run from repository root: bash examples/supply-chain/supply-chain-validate.sh

set -euo pipefail

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

EXAMPLE_DIR="examples/supply-chain"

echo ""
echo "=== Supply Chain Examples: YAML syntax ==="

for f in "$EXAMPLE_DIR"/*.yaml; do
  if yq eval 'true' "$f" > /dev/null 2>&1; then
    pass "$f is valid YAML"
  else
    fail "$f has invalid YAML"
  fi
done

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS error(s)"
  exit 1
fi
echo "PASS: all supply-chain example checks passed"
