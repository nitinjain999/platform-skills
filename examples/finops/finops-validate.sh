#!/usr/bin/env bash
# Offline validator for examples/finops/
# Run from the repository root: bash examples/finops/finops-validate.sh
# Requires: bash, python3. opa and terraform are used when available.
# Kubernetes manifests are schema-checked by the kubeconform step in validate.yml.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT_DIR/examples/finops"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== FinOps example structure ==="
for f in README.md policy/required_tags.rego policy/required_tags_test.rego \
         terraform/main.tf kubernetes/require-cost-labels.yaml \
         opencost/opencost.yaml workflows/infracost.yml; do
  if [ -f "$DIR/$f" ]; then pass "$f exists"; else fail "$f missing"; fi
done

echo ""
echo "=== Tag keys agree across the four layers ==="
# The same default keys must appear in Terraform, the Rego policy and the
# Kyverno policy; a key added to one layer only is enforced inconsistently.
for key in owner cost-center environment; do
  for f in terraform/main.tf policy/required_tags.rego kubernetes/require-cost-labels.yaml; do
    if grep -q -- "$key" "$DIR/$f"; then
      pass "$f mentions $key"
    else
      fail "$f does not mention $key"
    fi
  done
done

echo ""
echo "=== Kyverno policy starts in Audit ==="
if python3 -I - "$DIR/kubernetes/require-cost-labels.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
actions = doc.get("spec", {}).get("validationActions", [])
sys.exit(0 if actions == ["Audit"] else 1)
PY
then
  pass "require-cost-labels.yaml validationActions is [Audit]"
else
  fail "require-cost-labels.yaml must ship with validationActions: [Audit]; promote to Deny per cluster"
fi

echo ""
echo "=== Workflow actions pinned by SHA ==="
unpinned="$(grep -nE '^\s*-?\s*uses:' "$DIR/workflows/infracost.yml" | grep -vE '@[0-9a-f]{40}' || true)"
if [ -z "$unpinned" ]; then
  pass "every uses: in infracost.yml is pinned to a full SHA"
else
  fail "unpinned uses: in infracost.yml: $unpinned"
fi

echo ""
echo "=== Rego tests ==="
if command -v opa >/dev/null 2>&1; then
  if opa test "$DIR/policy" >/dev/null 2>&1; then
    pass "opa test examples/finops/policy"
  else
    fail "opa test examples/finops/policy failed; run: opa test -v examples/finops/policy"
  fi
else
  echo "  SKIP: opa not installed"
fi

echo ""
echo "=== Terraform formatting ==="
if command -v terraform >/dev/null 2>&1; then
  if terraform fmt -check -recursive "$DIR/terraform" >/dev/null 2>&1; then
    pass "terraform fmt -check examples/finops/terraform"
  else
    fail "terraform fmt -check failed; run: terraform fmt -recursive examples/finops/terraform"
  fi
else
  echo "  SKIP: terraform not installed"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS finops validation error(s)"
  exit 1
fi
echo "PASS: finops examples valid"
