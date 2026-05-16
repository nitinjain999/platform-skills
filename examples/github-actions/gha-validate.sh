#!/usr/bin/env bash
# Offline validator for examples/github-actions/
# Run from the repository root: bash examples/github-actions/gha-validate.sh
# Requires: bash. actionlint used when available.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GHA_DIR="$ROOT_DIR/examples/github-actions"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== GitHub Actions example structure ==="

EXPECTED_FILES=(
  "README.md"
  "terraform-cicd.yml"
  "container-build.yml"
  "flux-sync.yml"
  "reusable-workflows/terraform-plan.yml"
  "composite-actions/setup-terraform/action.yml"
  "composite-actions/configure-cloud/action.yml"
)

for f in "${EXPECTED_FILES[@]}"; do
  if [ -f "$GHA_DIR/$f" ]; then
    pass "$f exists"
  else
    fail "$f missing"
  fi
done

echo ""
echo "=== Security patterns ==="

find "$GHA_DIR" -name "*.yml" -o -name "*.yaml" | sort | while read -r workflow; do
  name="${workflow#$GHA_DIR/}"

  # Actions must NOT use mutable tags — must be pinned to SHA
  # Pattern: uses: owner/repo@v1.2.3 or @branch (not @sha256...)
  if grep -qE "uses: [a-zA-Z0-9_/-]+@v[0-9]" "$workflow" 2>/dev/null; then
    fail "$name: action(s) pinned to mutable version tag — pin to full SHA instead (uses: owner/repo@<sha>  # vX.Y.Z)"
  else
    pass "$name: no mutable version tag pins detected"
  fi

  # Must NOT use pull_request_target with code checkout from external sources
  if grep -q "pull_request_target" "$workflow" 2>/dev/null; then
    if grep -q "ref: \${{ github.event.pull_request.head" "$workflow" 2>/dev/null; then
      fail "$name: pull_request_target with PR head checkout — SECURITY RISK (arbitrary code execution)"
    else
      pass "$name: pull_request_target present but no dangerous head checkout"
    fi
  fi

  # Workflows must declare permissions
  if grep -q "^on:" "$workflow" 2>/dev/null && grep -q "permissions:" "$workflow" 2>/dev/null; then
    pass "$name: has permissions block"
  elif grep -q "^on:" "$workflow" 2>/dev/null; then
    fail "$name: missing top-level or job-level permissions block — default is write-all"
  fi

  # Must NOT use latest or mutable container tags
  if grep -qE "image: [a-zA-Z0-9._/-]+:latest" "$workflow" 2>/dev/null; then
    fail "$name: container image uses :latest tag — pin to a digest or version"
  else
    pass "$name: no :latest container tags"
  fi

  # OIDC: if id-token: write is present, should use OIDC not static keys
  if grep -q "id-token: write" "$workflow" 2>/dev/null; then
    if grep -qE "AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY" "$workflow" 2>/dev/null; then
      fail "$name: OIDC configured but static AWS credentials also present — remove static keys"
    else
      pass "$name: OIDC configured without static credentials"
    fi
  fi
done

echo ""
echo "=== Secrets handling ==="

# Check for hardcoded secrets patterns across all workflow files
if grep -rqE "(password|secret|token|key)[[:space:]]*[:=][[:space:]]*['\"][^'\"$\{]{8,}" "$GHA_DIR/" 2>/dev/null; then
  fail "Possible hardcoded secret detected in workflow files — use \${{ secrets.NAME }} instead"
else
  pass "No hardcoded secrets patterns detected"
fi

echo ""
echo "=== actionlint (if available) ==="

if command -v actionlint >/dev/null 2>&1; then
  echo "  INFO: actionlint found — running on all workflow files"
  if actionlint "$GHA_DIR"/*.yml "$GHA_DIR"/reusable-workflows/*.yml >/dev/null 2>&1; then
    pass "actionlint passed"
  else
    fail "actionlint found issues — run 'actionlint examples/github-actions/*.yml' for details"
  fi
else
  echo "  INFO: actionlint not found — skipping (install: https://github.com/rhysd/actionlint)"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all GitHub Actions example checks passed"
