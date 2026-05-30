#!/usr/bin/env bash
# Validates Karpenter example manifests and checks live cluster health if available.
#
# Offline mode: field-level checks on all YAML files.
# Online mode: kubectl apply --dry-run=server + live NodePool/NodeClaim status.
#
# Usage: bash examples/karpenter/karpenter-validate.sh
# Requires: kubectl (for cluster validation, with Karpenter CRDs installed)

set -euo pipefail

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $1"; }

YAML_FILES=(
  nodepool-default-al2023.yaml
  nodepool-spot-flex.yaml
  nodepool-critical-ondemand.yaml
  nodepool-gpu.yaml
  ec2nodeclass-private-cluster.yaml
)

# ─── Offline field checks ─────────────────────────────────────────────────────

_check_yaml_fields() {
  local name="$1"
  local file="$2"

  # API version checks
  if grep -q "karpenter.sh/v1" "$file"; then
    pass "$name — uses karpenter.sh/v1 (v1.x API)"
  elif grep -q "karpenter.sh/v1beta1\|karpenter.sh/v1alpha5" "$file"; then
    fail "$name — uses deprecated v1beta1/v1alpha5 API — migrate to karpenter.sh/v1"
  fi

  if grep -q "karpenter.k8s.aws/v1" "$file"; then
    pass "$name — uses karpenter.k8s.aws/v1 EC2NodeClass (v1.x)"
  elif grep -q "karpenter.k8s.aws/v1beta1" "$file"; then
    fail "$name — uses deprecated EC2NodeClass v1beta1 — migrate to karpenter.k8s.aws/v1"
  fi

  # Old v0.x resources
  if grep -qE "^kind: Provisioner$" "$file"; then
    fail "$name — contains Provisioner (v0.x) — replace with NodePool"
  fi
  if grep -qE "^kind: AWSNodeTemplate$" "$file"; then
    fail "$name — contains AWSNodeTemplate (v0.x) — replace with EC2NodeClass"
  fi

  # NodePool checks
  if grep -qE "^kind: NodePool$" "$file"; then
    if grep -q "limits:" "$file"; then
      pass "$name — NodePool has limits (prevents runaway provisioning)"
    else
      fail "$name — NodePool missing limits — uncapped NodePool can provision unbounded nodes"
    fi

    if grep -q "disruption:" "$file"; then
      pass "$name — NodePool has disruption policy"
    else
      fail "$name — NodePool missing disruption block — defaults to no consolidation"
    fi

    if grep -q "expireAfter:" "$file"; then
      pass "$name — NodePool has expireAfter (node rotation configured)"
    else
      warn "$name — NodePool missing expireAfter — nodes will not be rotated for AMI updates"
    fi

    if grep -q "startupTaints:" "$file"; then
      pass "$name — NodePool has startupTaints (prevents premature pod scheduling)"
    else
      warn "$name — NodePool missing startupTaints — pods may schedule before DaemonSets are ready"
    fi

    if grep -q "minValues:" "$file"; then
      pass "$name — NodePool has minValues on instance requirements (Spot diversity enforced)"
    else
      warn "$name — NodePool missing minValues — Spot diversity not enforced"
    fi
  fi

  # EC2NodeClass checks
  if grep -qE "^kind: EC2NodeClass$" "$file"; then
    if grep -q "httpTokens: required" "$file"; then
      pass "$name — EC2NodeClass enforces IMDSv2 (httpTokens: required)"
    else
      fail "$name — EC2NodeClass missing httpTokens: required — IMDSv2 not enforced"
    fi

    if grep -q "httpPutResponseHopLimit: 1" "$file"; then
      pass "$name — EC2NodeClass sets httpPutResponseHopLimit: 1 (blocks pod IMDS access)"
    else
      fail "$name — EC2NodeClass missing httpPutResponseHopLimit: 1 — pods can access instance metadata"
    fi

    if grep -q "encrypted: true" "$file"; then
      pass "$name — EC2NodeClass has encrypted EBS volumes"
    else
      fail "$name — EC2NodeClass missing encrypted: true on EBS — unencrypted volumes in production"
    fi

    if grep -q "amiSelectorTerms:" "$file"; then
      pass "$name — EC2NodeClass has amiSelectorTerms"
    else
      fail "$name — EC2NodeClass missing amiSelectorTerms — no AMI selection configured"
    fi

    if grep -q "subnetSelectorTerms:" "$file"; then
      pass "$name — EC2NodeClass has subnetSelectorTerms"
    else
      fail "$name — EC2NodeClass missing subnetSelectorTerms"
    fi

    if grep -q "securityGroupSelectorTerms:" "$file"; then
      pass "$name — EC2NodeClass has securityGroupSelectorTerms"
    else
      fail "$name — EC2NodeClass missing securityGroupSelectorTerms"
    fi

    # Flag the placeholder AMI
    if grep -q "ami-PLACEHOLDER" "$file"; then
      warn "$name — contains ami-PLACEHOLDER — replace with a real tested AMI ID before deploying"
    fi
  fi

  # NodePool content checks
  if grep -qE "^kind: NodePool$" "$file"; then
    # minValues enforces Spot diversity — should be present on instance-family requirement
    if grep -q "minValues:" "$file"; then
      pass "$name — NodePool has minValues (Spot diversity enforced)"
    else
      warn "$name — NodePool missing minValues on instance requirements — Spot InsufficientCapacityError may stall provisioning"
    fi

    # consolidateAfter safety check — 1m with WhenEmptyOrUnderutilized causes churn
    if grep -q "WhenEmptyOrUnderutilized" "$file"; then
      # Extract consolidateAfter value and check it's >= 5m
      consolidate_val=$(grep "consolidateAfter:" "$file" | grep -oE "[0-9]+(m|h|s)" | head -1)
      consolidate_num=$(echo "$consolidate_val" | grep -oE "[0-9]+")
      consolidate_unit=$(echo "$consolidate_val" | grep -oE "[a-z]+")
      if [ -n "$consolidate_num" ] && [ "$consolidate_unit" = "m" ] && [ "$consolidate_num" -lt 5 ]; then
        fail "$name — consolidateAfter: ${consolidate_val} with WhenEmptyOrUnderutilized is too aggressive (resets on pod activity) — use 5m minimum"
      elif [ -n "$consolidate_val" ]; then
        pass "$name — consolidateAfter: ${consolidate_val} (safe for WhenEmptyOrUnderutilized)"
      fi
    fi

    # expireAfter should be set for AMI rotation
    if grep -q "expireAfter:" "$file"; then
      pass "$name — NodePool has expireAfter (periodic node rotation configured)"
    else
      warn "$name — NodePool missing expireAfter — nodes will not be rotated for AMI updates"
    fi
  fi
}

# ─── Online cluster checks ────────────────────────────────────────────────────

_check_live_cluster() {
  echo ""
  echo "=== Live cluster checks ==="
  echo ""

  # NodePool health
  if kubectl get nodepool -A &>/dev/null 2>&1; then
    local not_ready
    not_ready=$(kubectl get nodepool -A -o json 2>/dev/null | \
      jq -r '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True")) | .metadata.name' || true)
    if [ -z "$not_ready" ]; then
      pass "All NodePools are Ready"
    else
      fail "NodePool(s) not Ready: $not_ready"
      kubectl get nodepool -A
    fi
  else
    warn "No NodePools found in cluster"
  fi

  # Stuck NodeClaims
  local pending_claims
  pending_claims=$(kubectl get nodeclaim -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.conditions[]? | select(.type=="Launched" and .status=="False")) | .metadata.name' || true)
  if [ -z "$pending_claims" ]; then
    pass "No NodeClaims stuck in Launched=False"
  else
    fail "NodeClaim(s) stuck (Launched=False): $pending_claims"
    kubectl get nodeclaim -A
  fi

  # Karpenter controller pod
  local karpenter_ready
  karpenter_ready=$(kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  if [ "$karpenter_ready" -gt 0 ]; then
    pass "Karpenter controller pod is Running ($karpenter_ready pod(s))"
  else
    fail "Karpenter controller pod is not Running"
    kubectl get pods -n karpenter
  fi

  # Recent errors in Karpenter logs
  local log_errors
  log_errors=$(kubectl logs -n karpenter \
    -l app.kubernetes.io/name=karpenter \
    --since=5m --tail=200 2>/dev/null | grep -ci '"level":"error"' || true)
  if [ "$log_errors" -eq 0 ]; then
    pass "No errors in Karpenter logs (last 5 minutes)"
  else
    warn "$log_errors error log line(s) in last 5 minutes — run: kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --since=5m | grep error"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Karpenter example manifest validation ==="
echo ""

USE_KUBECTL=false
HAS_CRDS=false

if kubectl cluster-info >/dev/null 2>&1; then
  USE_KUBECTL=true
  if kubectl get crd nodepools.karpenter.sh >/dev/null 2>&1; then
    HAS_CRDS=true
    echo "  Mode: kubectl apply --dry-run=server + live checks (Karpenter CRDs available)"
  else
    echo "  Mode: offline field checks + kubectl syntax (cluster available, Karpenter CRDs not installed)"
    echo "        To enable full validation: helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter ..."
  fi
else
  echo "  Mode: offline field checks (no cluster)"
fi

echo ""

for manifest in "${YAML_FILES[@]}"; do
  filepath="$SCRIPT_DIR/$manifest"

  if [ ! -f "$filepath" ]; then
    fail "$manifest — file not found"
    continue
  fi

  echo "--- $manifest ---"

  # Offline field checks always run
  _check_yaml_fields "$manifest" "$filepath"

  # Online dry-run if CRDs are available
  if [ "$HAS_CRDS" = "true" ]; then
    if kubectl apply --dry-run=server -f "$filepath" >/dev/null 2>&1; then
      pass "$manifest — kubectl dry-run=server passed"
    else
      fail "$manifest — kubectl dry-run=server failed"
      kubectl apply --dry-run=server -f "$filepath" 2>&1 | sed 's/^/    /'
    fi
  elif [ "$USE_KUBECTL" = "true" ]; then
    if kubectl apply --dry-run=client -f "$filepath" >/dev/null 2>&1; then
      pass "$manifest — kubectl dry-run=client passed (syntax only)"
    else
      fail "$manifest — kubectl dry-run=client failed"
      kubectl apply --dry-run=client -f "$filepath" 2>&1 | sed 's/^/    /'
    fi
  fi

  echo ""
done

# Live cluster checks (only when Karpenter CRDs are present)
if [ "$HAS_CRDS" = "true" ]; then
  _check_live_cluster
fi

echo ""
echo "=== IAM reachability check ==="
echo ""
echo "  To verify the Karpenter controller can call EC2 APIs, run from inside the cluster:"
echo "  kubectl run -it --rm iamtest --image=amazon/aws-cli \\"
echo "    --serviceaccount=karpenter --namespace=karpenter \\"
echo "    -- ec2 describe-instance-types --region eu-north-1 --max-items 1"
echo ""
echo "  To verify SQS interruption queue is reachable:"
echo "  kubectl run -it --rm sqstest --image=amazon/aws-cli \\"
echo "    --serviceaccount=karpenter --namespace=karpenter \\"
echo "    -- sqs get-queue-attributes \\"
echo "       --queue-url <queue-url> --attribute-names All --region eu-north-1"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all Karpenter example checks passed"
