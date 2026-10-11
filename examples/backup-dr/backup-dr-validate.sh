#!/usr/bin/env bash
# Offline validator for examples/backup-dr/
# Run from the repository root: bash examples/backup-dr/backup-dr-validate.sh
# Requires: bash, python3. shellcheck is used when available.
# Kubernetes manifests are schema-checked by the kubeconform step in validate.yml.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT_DIR/examples/backup-dr"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== Backup/DR example structure ==="
for f in README.md iam-policy.json restore-drill.sh velero/helmrelease.yaml; do
  if [ -f "$DIR/$f" ]; then pass "$f exists"; else fail "$f missing"; fi
done

echo ""
echo "=== IAM policy is scoped ==="
# No wildcard action, every S3 statement names the backup bucket, and a
# Resource "*" statement (EBS snapshots) is narrowed by a Condition.
if python3 -I - "$DIR/iam-policy.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
bad = []
for st in doc["Statement"]:
    actions = st["Action"] if isinstance(st["Action"], list) else [st["Action"]]
    resources = st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]]
    if any(a == "*" or a.endswith(":*") for a in actions):
        bad.append(f"{st.get('Sid', '?')}: wildcard action")
    if any(a.startswith("s3:") for a in actions) and any(r == "*" for r in resources):
        bad.append(f"{st.get('Sid', '?')}: S3 on Resource *")
    if any(r == "*" for r in resources) and not st.get("Condition"):
        bad.append(f"{st.get('Sid', '?')}: Resource * without a Condition")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
then
  pass "iam-policy.json has no wildcard actions, no unscoped S3 statements, and every Resource * is conditioned"
else
  fail "iam-policy.json is broader than the example promises"
fi

echo ""
echo "=== No static credentials ==="
if grep -q 'useSecret: false' "$DIR/velero/helmrelease.yaml"; then
  pass "helmrelease.yaml sets credentials.useSecret: false (IRSA only)"
else
  fail "helmrelease.yaml must set credentials.useSecret: false"
fi
if grep -q 'eks.amazonaws.com/role-arn' "$DIR/velero/helmrelease.yaml"; then
  pass "helmrelease.yaml annotates the service account for IRSA"
else
  fail "helmrelease.yaml is missing the IRSA role annotation"
fi

echo ""
echo "=== Restore drill never takes production traffic ==="
if grep -q 'httproutes.gateway.networking.k8s.io' "$DIR/restore-drill.sh" \
   && grep -q 'ingresses.networking.k8s.io' "$DIR/restore-drill.sh"; then
  pass "restore-drill.sh excludes HTTPRoutes and Ingresses"
else
  fail "restore-drill.sh must exclude HTTPRoutes and Ingresses from the drill restore"
fi
if bash -n "$DIR/restore-drill.sh"; then
  pass "restore-drill.sh parses"
else
  fail "restore-drill.sh has a syntax error"
fi
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$DIR/restore-drill.sh" >/dev/null 2>&1; then
    pass "shellcheck restore-drill.sh"
  else
    fail "shellcheck restore-drill.sh reported findings"
  fi
else
  echo "  SKIP: shellcheck not installed"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS backup-dr validation error(s)"
  exit 1
fi
echo "PASS: backup-dr examples valid"
