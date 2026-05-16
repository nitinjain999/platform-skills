#!/usr/bin/env bash
# Offline validator for examples/opa/
# Run from the repository root: bash examples/opa/opa-validate.sh
# Requires: bash. conftest/regal used when available.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPA_DIR="$ROOT_DIR/examples/opa"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== OPA example structure ==="

if [ -f "$OPA_DIR/README.md" ]; then
  pass "README.md exists"
else
  fail "README.md missing"
fi

if [ -d "$OPA_DIR/conftest" ]; then
  pass "conftest/ directory exists"
else
  fail "conftest/ directory missing"
fi

echo ""
echo "=== Rego policy content checks ==="

while IFS= read -r policy; do
  name="$(basename "$policy")"

  # Must use rego.v1
  if grep -q "import rego.v1" "$policy"; then
    pass "$name imports rego.v1"
  else
    fail "$name missing 'import rego.v1' — required for Rego v1 compatibility"
  fi

  # Must have package declaration
  if grep -q "^package " "$policy"; then
    pass "$name has package declaration"
  else
    fail "$name missing package declaration"
  fi

  # Must have a METADATA block (best practice for conftest output)
  if grep -q "# METADATA" "$policy"; then
    pass "$name has METADATA block"
  else
    fail "$name missing # METADATA block (add title, description, entrypoint)"
  fi

  # Rule names must be deny, warn, or violation (not allow)
  if grep -qE "^(deny|warn|violation)\b" "$policy"; then
    pass "$name uses deny/warn/violation rule names"
  elif grep -qE "^allow\b" "$policy"; then
    fail "$name uses 'allow' rule — Conftest expects deny/warn/violation"
  fi

  # Must NOT use deprecated input.request pattern (OPA v0.x only)
  if grep -q "input.request" "$policy"; then
    fail "$name uses input.request — check if this should be input.review (Gatekeeper) or input.resource (Conftest)"
  fi
done < <(find "$OPA_DIR" -name "*.rego" | sort)

echo ""
echo "=== Test fixtures ==="

TEST_COUNT=$(find "$OPA_DIR" -name "*_test.rego" | wc -l | tr -d ' ')
if [ "$TEST_COUNT" -gt 0 ]; then
  pass "Found $TEST_COUNT test file(s) (*_test.rego)"
else
  fail "No _test.rego files found — each policy should have a corresponding test file"
fi

echo ""
echo "=== conftest (if available) ==="

if command -v conftest >/dev/null 2>&1; then
  echo "  INFO: conftest found — running verify"
  if (cd "$OPA_DIR/conftest" && conftest verify --policy policies . >/dev/null 2>&1); then
    pass "conftest verify passed"
  else
    fail "conftest verify failed — run 'cd examples/opa/conftest && conftest verify --policy policies .' for details"
  fi
else
  echo "  INFO: conftest not found — skipping live verify (install: https://www.conftest.dev)"
fi

if command -v regal >/dev/null 2>&1; then
  echo "  INFO: regal found — running lint"
  if regal lint "$OPA_DIR" >/dev/null 2>&1; then
    pass "regal lint passed"
  else
    echo "  WARN: regal lint found style issues — run 'regal lint examples/opa' to review"
  fi
else
  echo "  INFO: regal not found — skipping lint (install: https://docs.styra.com/regal)"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all OPA example checks passed"
