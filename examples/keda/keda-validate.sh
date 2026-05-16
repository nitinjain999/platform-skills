#!/usr/bin/env bash
# Validates KEDA example manifests for structural correctness.
# Runs kubectl apply --dry-run=client when a cluster is available,
# falls back to field-level grep checks when it is not.
#
# Usage: bash examples/keda/keda-validate.sh
# Requires: kubectl (for cluster validation, with KEDA CRDs installed)

set -euo pipefail

ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

MANIFESTS=(
  scaledobject-sqs.yaml
  scaledobject-prometheus.yaml
  scaledobject-kafka.yaml
  scaledobject-cron.yaml
  scaledjob-sqs.yaml
)

# Offline field checks — run when no cluster is available
_check_yaml_fields() {
  local name="$1"
  local file="$2"

  if grep -q "keda.sh/v1alpha1" "$file"; then
    pass "$name — has keda.sh/v1alpha1 apiVersion"
  else
    fail "$name — missing keda.sh/v1alpha1 apiVersion"
  fi

  if grep -qE "^kind: (ScaledObject|ScaledJob|TriggerAuthentication|ClusterTriggerAuthentication)$" "$file"; then
    pass "$name — has valid KEDA kind"
  else
    fail "$name — missing valid KEDA kind"
  fi

  if grep -qE "^kind: (ScaledObject|ScaledJob)$" "$file"; then
    if grep -q "triggers:" "$file"; then
      pass "$name — has triggers block"
    else
      fail "$name — ScaledObject/ScaledJob missing triggers block"
    fi
  fi

  # Flag inline passwords longer than 20 chars (looks like a real credential)
  if grep -qE "^\s+password:\s+[A-Za-z0-9+/]{20,}" "$file"; then
    fail "$name — possible plaintext credential (use TriggerAuthentication)"
  else
    pass "$name — no plaintext credentials detected"
  fi
}

echo ""
echo "=== KEDA example manifest validation ==="

# Use kubectl dry-run if a cluster with KEDA CRDs is available
USE_KUBECTL=false
if kubectl cluster-info >/dev/null 2>&1; then
  if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "  Mode: kubectl apply --dry-run=client (cluster + KEDA CRDs available)"
    USE_KUBECTL=true
  else
    echo "  Mode: offline field checks (cluster available but KEDA CRDs not installed)"
    echo "        To enable full validation: helm install keda kedacore/keda -n keda --create-namespace"
  fi
else
  echo "  Mode: offline field checks (no cluster)"
fi

echo ""

for manifest in "${MANIFESTS[@]}"; do
  filepath="$SCRIPT_DIR/$manifest"

  if [ ! -f "$filepath" ]; then
    fail "$manifest — file not found"
    continue
  fi

  if [ "$USE_KUBECTL" = "true" ]; then
    if kubectl apply --dry-run=client -f "$filepath" >/dev/null 2>&1; then
      pass "$manifest — kubectl dry-run passed"
    else
      fail "$manifest — kubectl dry-run failed"
      kubectl apply --dry-run=client -f "$filepath" 2>&1 | sed 's/^/    /'
    fi
  else
    _check_yaml_fields "$manifest" "$filepath"
  fi
done

echo ""
echo "=== KEDA example content checks ==="
echo ""

# SQS: verify IRSA pattern (no static keys)
SQS_FILE="$SCRIPT_DIR/scaledobject-sqs.yaml"
if [ -f "$SQS_FILE" ]; then
  if grep -q "provider: aws" "$SQS_FILE"; then
    pass "scaledobject-sqs.yaml uses IRSA (podIdentity.provider: aws)"
  else
    fail "scaledobject-sqs.yaml should use IRSA not static credentials"
  fi

  if grep -q "activationQueueLength" "$SQS_FILE"; then
    pass "scaledobject-sqs.yaml has activationQueueLength (prevents flapping on empty queue)"
  else
    fail "scaledobject-sqs.yaml missing activationQueueLength"
  fi
fi

# Prometheus: verify activationThreshold and Cron floor
PROM_FILE="$SCRIPT_DIR/scaledobject-prometheus.yaml"
if [ -f "$PROM_FILE" ]; then
  if grep -q "activationThreshold" "$PROM_FILE"; then
    pass "scaledobject-prometheus.yaml has activationThreshold"
  else
    fail "scaledobject-prometheus.yaml missing activationThreshold"
  fi

  if grep -q "type: cron" "$PROM_FILE"; then
    pass "scaledobject-prometheus.yaml has Cron trigger for business-hours replica floor"
  else
    fail "scaledobject-prometheus.yaml missing Cron trigger"
  fi
fi

# Kafka: verify authenticationRef present
KAFKA_FILE="$SCRIPT_DIR/scaledobject-kafka.yaml"
if [ -f "$KAFKA_FILE" ]; then
  if grep -q "authenticationRef" "$KAFKA_FILE"; then
    pass "scaledobject-kafka.yaml uses authenticationRef for SASL/TLS credentials"
  else
    fail "scaledobject-kafka.yaml missing authenticationRef"
  fi
fi

# Cron: verify timezone, multiple windows, safety-net trigger, and restoreToOriginalReplicaCount
CRON_FILE="$SCRIPT_DIR/scaledobject-cron.yaml"
if [ -f "$CRON_FILE" ]; then
  if grep -q "timezone:" "$CRON_FILE"; then
    pass "scaledobject-cron.yaml has explicit timezone"
  else
    fail "scaledobject-cron.yaml missing explicit timezone (UTC assumption is a bug)"
  fi

  CRON_WINDOW_COUNT=$(grep -c "type: cron" "$CRON_FILE" || true)
  if [ "$CRON_WINDOW_COUNT" -ge 2 ]; then
    pass "scaledobject-cron.yaml has multiple cron windows ($CRON_WINDOW_COUNT)"
  else
    fail "scaledobject-cron.yaml should define multiple non-overlapping time windows"
  fi

  if grep -qE "type: prometheus|type: aws-sqs|type: kafka|type: redis" "$CRON_FILE"; then
    pass "scaledobject-cron.yaml has safety-net trigger alongside Cron"
  else
    fail "scaledobject-cron.yaml missing safety-net trigger — unexpected spikes will not scale up"
  fi

  if grep -q "restoreToOriginalReplicaCount" "$CRON_FILE"; then
    pass "scaledobject-cron.yaml has restoreToOriginalReplicaCount"
  else
    fail "scaledobject-cron.yaml missing restoreToOriginalReplicaCount"
  fi
fi

# ScaledJob: verify required Job fields
JOB_FILE="$SCRIPT_DIR/scaledjob-sqs.yaml"
if [ -f "$JOB_FILE" ]; then
  if grep -q "restartPolicy: Never" "$JOB_FILE"; then
    pass "scaledjob-sqs.yaml has restartPolicy: Never (required for Kubernetes Jobs)"
  else
    fail "scaledjob-sqs.yaml missing restartPolicy: Never"
  fi

  if grep -q "activeDeadlineSeconds" "$JOB_FILE"; then
    pass "scaledjob-sqs.yaml has activeDeadlineSeconds (prevents zombie jobs)"
  else
    fail "scaledjob-sqs.yaml missing activeDeadlineSeconds"
  fi
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all KEDA example checks passed"
