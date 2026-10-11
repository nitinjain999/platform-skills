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
for f in README.md iam-policy.json restore-drill.sh velero/helmrelease.yaml bucket/main.tf; do
  if [ -f "$DIR/$f" ]; then pass "$f exists"; else fail "$f missing"; fi
done

echo ""
echo "=== IAM policy is scoped ==="
# No wildcard action, every S3 statement names the backup bucket, only the
# Describe calls use Resource "*" (and only with a Condition), and snapshot
# deletion is limited to snapshots Velero tagged velero.io/backup.
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
    if any(r == "*" for r in resources) and any(not a.startswith("ec2:Describe") for a in actions):
        bad.append(f"{st.get('Sid', '?')}: only Describe calls may use Resource *")
    if "ec2:DeleteSnapshot" in actions:
        cond = json.dumps(st.get("Condition", {}))
        if "velero.io/backup" not in cond or any(r == "*" for r in resources):
            bad.append(f"{st.get('Sid', '?')}: DeleteSnapshot must be limited to snapshots tagged velero.io/backup")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
then
  pass "iam-policy.json: no wildcard actions, S3 scoped, Resource * only for conditioned Describe calls, deletes limited to Velero snapshots"
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
echo "=== Restore drill is not reachable from outside the cluster ==="
excl="$(grep -o -- '--exclude-resources [^ ]*' "$DIR/restore-drill.sh" || true)"
excl="${excl#--exclude-resources }"
missing=""
for r in httproutes.gateway.networking.k8s.io ingresses.networking.k8s.io services networkpolicies.networking.k8s.io; do
  printf '%s\n' "$excl" | tr ',' '\n' | grep -qx "$r" || missing="$missing $r"
done
if [ -z "$missing" ]; then
  pass "restore-drill.sh excludes HTTPRoutes, Ingresses, Services and NetworkPolicies from the Velero restore"
else
  fail "restore-drill.sh must exclude from the drill restore:$missing"
fi
if grep -q 'type: "ClusterIP"' "$DIR/restore-drill.sh"; then
  pass "restore-drill.sh recreates Services as ClusterIP only"
else
  fail "restore-drill.sh must recreate Services as ClusterIP (no LoadBalancer or NodePort)"
fi

echo ""
echo "=== Restore drill cannot reach production ==="
# The namespace and its default-deny policy must exist before velero restore
# runs, or restored pods start with production credentials and open egress.
np_line="$(grep -n 'kind: "NetworkPolicy"' "$DIR/restore-drill.sh" | head -1 | cut -d: -f1 || true)"
restore_line="$(grep -n '^velero restore create' "$DIR/restore-drill.sh" | head -1 | cut -d: -f1 || true)"
if [ -n "$np_line" ] && [ -n "$restore_line" ] && [ "$np_line" -lt "$restore_line" ] \
   && grep -q 'policyTypes: \["Ingress", "Egress"\]' "$DIR/restore-drill.sh"; then
  pass "restore-drill.sh applies a default-deny Ingress+Egress NetworkPolicy before the restore"
else
  fail "restore-drill.sh must apply a default-deny egress NetworkPolicy to the drill namespace before velero restore"
fi
# An empty namespaceSelector on the DNS rule would allow those ports to every
# pod in every namespace, not just the resolver. ($dns_ns is a literal jq variable.)
# shellcheck disable=SC2016
if ! grep -q 'namespaceSelector: {}' "$DIR/restore-drill.sh" \
   && grep -qF '"kubernetes.io/metadata.name": $dns_ns' "$DIR/restore-drill.sh"; then
  pass "restore-drill.sh limits DNS egress to the DNS namespace and pod label"
else
  fail "restore-drill.sh must scope the DNS egress rule to the DNS namespace and pods, never namespaceSelector: {}"
fi
# The drill namespace holds production Secrets: a failed restore or readiness
# timeout must not leave it running.
trap_line="$(grep -n '^trap cleanup EXIT' "$DIR/restore-drill.sh" | head -1 | cut -d: -f1 || true)"
ns_line="$(grep -n 'kind: "Namespace"' "$DIR/restore-drill.sh" | head -1 | cut -d: -f1 || true)"
if [ -n "$trap_line" ] && [ -n "$ns_line" ] && [ "$trap_line" -lt "$ns_line" ]; then
  pass "restore-drill.sh deletes the drill namespace on every exit path (EXIT trap set before it is created)"
else
  fail "restore-drill.sh must set an EXIT trap that deletes the drill namespace before creating it"
fi

echo ""
echo "=== Backup bucket is protected from deletion ==="
# Velero holds s3:DeleteObject; versioning turns that into a delete marker, and
# only the admin roles may delete versions or remove the protection.
if python3 -I - "$DIR/bucket/main.tf" "$DIR/iam-policy.json" "$DIR/velero/helmrelease.yaml" <<'PY'
import json, re, sys
tf, iam, hr = (open(p).read() for p in sys.argv[1:4])
bad = []
if not re.search(r'aws_s3_bucket_versioning"[^}]*status\s*=\s*"Enabled"', tf, re.S):
    bad.append("bucket/main.tf: versioning must be Enabled")
if "prevent_destroy = true" not in tf:
    bad.append("bucket/main.tf: the bucket must set prevent_destroy")
for action in ("s3:DeleteObjectVersion", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration",
               "s3:PutBucketPolicy", "s3:DeleteBucket"):
    if f'"{action}"' not in tf:
        bad.append(f"bucket/main.tf: bucket policy must deny {action} to non-admins")
granted = {a for st in json.loads(iam)["Statement"] if st["Effect"] == "Allow"
           for a in (st["Action"] if isinstance(st["Action"], list) else [st["Action"]])}
for action in granted & {"s3:DeleteObjectVersion", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration",
                         "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:DeleteBucket"}:
    bad.append(f"iam-policy.json: Velero must not hold {action}")
name = re.search(r'variable "bucket_name"[^}]*default\s*=\s*"([^"]+)"', tf, re.S)
name = name.group(1) if name else ""
if not name or f"bucket: {name}" not in hr or f"arn:aws:s3:::{name}" not in iam:
    bad.append(f"bucket name {name!r} must match velero/helmrelease.yaml and iam-policy.json")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
then
  pass "bucket/main.tf: versioned, prevent_destroy, version deletion and protection changes denied to non-admins; Velero holds none of them; bucket name consistent"
else
  fail "backup bucket is not protected as the example promises"
fi

echo ""
echo "=== Restore drill script ==="
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
