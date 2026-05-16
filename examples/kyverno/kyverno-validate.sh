#!/usr/bin/env bash
# Offline validator for examples/kyverno/
# Run from the repository root: bash examples/kyverno/kyverno-validate.sh
# Requires: bash. kyverno CLI used when available (falls back to content checks).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KYVERNO_DIR="$ROOT_DIR/examples/kyverno"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== Kyverno example structure ==="

# Required files
for f in "README.md" "kyverno-test.yaml" "policies/require-team-labels.yaml" \
         "policies/disallow-privileged-containers.yaml" \
         "policies/generate-default-networkpolicy.yaml"; do
  if [ -f "$KYVERNO_DIR/$f" ]; then
    pass "$f exists"
  else
    fail "$f missing"
  fi
done

echo ""
echo "=== Policy API version and kind ==="

for policy in "$KYVERNO_DIR"/policies/*.yaml; do
  name="$(basename "$policy")"

  # Must use the new CEL-based API — never kyverno.io/v1 ClusterPolicy for new work
  if grep -q "apiVersion: policies.kyverno.io/v1" "$policy"; then
    pass "$name uses policies.kyverno.io/v1"
  else
    fail "$name must use apiVersion: policies.kyverno.io/v1 (not kyverno.io/v1)"
  fi

  # Must have a valid kind
  if grep -qE "^kind: (Validating|Mutating|Generating|ImageValidating)Policy$" "$policy"; then
    pass "$name has valid kind"
  else
    fail "$name missing valid kind (ValidatingPolicy, MutatingPolicy, GeneratingPolicy, or ImageValidatingPolicy)"
  fi

  # Must start in Audit mode — Deny requires explicit promotion from Audit
  if grep -q "validationActions" "$policy"; then
    if grep -q "Audit" "$policy"; then
      pass "$name uses Audit mode"
    else
      echo "  WARN: $name uses Deny without Audit — confirm Audit→Deny promotion was intentional"
    fi
  fi

  # Must NOT use deprecated validationFailureAction
  if grep -q "validationFailureAction:" "$policy"; then
    fail "$name uses deprecated validationFailureAction — replace with validationActions: [Audit] or [Deny]"
  else
    pass "$name does not use deprecated validationFailureAction"
  fi

  # Must NOT use deprecated spec.rules (kyverno.io/v1 pattern)
  if grep -q "spec:" "$policy" && grep -q "rules:" "$policy"; then
    if grep -q "matchConstraints:" "$policy" || grep -q "validations:" "$policy"; then
      pass "$name uses policies.kyverno.io/v1 spec fields"
    else
      fail "$name appears to use kyverno.io/v1 spec.rules pattern — migrate to matchConstraints + validations"
    fi
  fi

  # Must have policy metadata annotations
  if grep -q "policies.kyverno.io/title:" "$policy"; then
    pass "$name has policies.kyverno.io/title annotation"
  else
    fail "$name missing policies.kyverno.io/title annotation"
  fi
done

echo ""
echo "=== kyverno-test.yaml structure ==="

TEST_FILE="$KYVERNO_DIR/kyverno-test.yaml"
if [ -f "$TEST_FILE" ]; then
  # kyverno-test.yaml uses either apiVersion (newer CLI) or name-based format (older CLI)
  if grep -qE "^apiVersion: cli.kyverno.io|^name:" "$TEST_FILE"; then
    pass "kyverno-test.yaml has top-level identifier (apiVersion or name)"
  else
    fail "kyverno-test.yaml missing top-level identifier"
  fi

  if grep -q "policies:" "$TEST_FILE" && grep -q "resources:" "$TEST_FILE"; then
    pass "kyverno-test.yaml has policies and resources sections"
  else
    fail "kyverno-test.yaml missing policies or resources section"
  fi

  if grep -q "results:" "$TEST_FILE"; then
    pass "kyverno-test.yaml has results section"
  else
    fail "kyverno-test.yaml missing results section"
  fi
fi

echo ""
echo "=== kyverno CLI (if available) ==="

if command -v kyverno >/dev/null 2>&1; then
  echo "  INFO: kyverno CLI found — running kyverno test"
  if kyverno test "$KYVERNO_DIR" >/dev/null 2>&1; then
    pass "kyverno test passed"
  else
    fail "kyverno test failed — run 'kyverno test examples/kyverno' for details"
  fi
else
  echo "  INFO: kyverno CLI not found — skipping live test (install: https://kyverno.io/docs/kyverno-cli/)"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all kyverno example checks passed"
