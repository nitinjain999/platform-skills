#!/usr/bin/env bash
# Offline validator for examples/compliance/
# Run from the repository root: bash examples/compliance/compliance-validate.sh
# Requires: bash. checkov used when available.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMP_DIR="$ROOT_DIR/examples/compliance"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== Compliance example structure ==="

EXPECTED_DIRS=(
  "iam"
  "logging"
  "network"
  "encryption-data-services"
  "vulnerability"
  "detection"
  "incident-response"
  "backup"
)

for d in "${EXPECTED_DIRS[@]}"; do
  if [ -d "$COMP_DIR/$d" ]; then
    pass "$d/ directory exists"
  else
    fail "$d/ directory missing — expected SOC 2 control domain"
  fi
done

if [ -f "$COMP_DIR/checkov-config.yaml" ]; then
  pass "checkov-config.yaml exists"
else
  fail "checkov-config.yaml missing"
fi

echo ""
echo "=== SOC 2 control patterns ==="

# CC6.7 — encryption at rest: KMS rotation must be enabled
if grep -rq "enable_key_rotation" "$COMP_DIR/"; then
  pass "enable_key_rotation found (CC6.7 — KMS key rotation)"
else
  fail "enable_key_rotation not found — KMS keys must have rotation enabled (CC6.7)"
fi

# CC7.2 — audit logging: CloudTrail must be multi-region with log validation
if grep -rq "is_multi_region_trail" "$COMP_DIR/"; then
  pass "is_multi_region_trail found (CC7.2 — multi-region CloudTrail)"
else
  fail "is_multi_region_trail not found in compliance examples (CC7.2)"
fi

if grep -rq "enable_log_file_validation" "$COMP_DIR/"; then
  pass "enable_log_file_validation found (CC7.2 — CloudTrail log integrity)"
else
  fail "enable_log_file_validation not found (CC7.2)"
fi

# CC7.1 — threat detection: GuardDuty must be enabled
if grep -rq "aws_guardduty_detector" "$COMP_DIR/"; then
  pass "aws_guardduty_detector found (CC7.1 — GuardDuty)"
else
  fail "aws_guardduty_detector not found — GuardDuty must be enabled (CC7.1)"
fi

# A1.2 — backup: RDS backup retention must be set
if grep -rq "backup_retention_period" "$COMP_DIR/"; then
  pass "backup_retention_period found (A1.2 — RDS backup)"
else
  fail "backup_retention_period not found (A1.2)"
fi

# A1.2 — deletion protection must be enabled
if grep -rq "deletion_protection.*=.*true" "$COMP_DIR/"; then
  pass "deletion_protection = true found (A1.2 — production database protection)"
else
  fail "deletion_protection = true not found (A1.2)"
fi

echo ""
echo "=== Anti-patterns (must not exist) ==="

# Must NOT have publicly_accessible = true
if grep -rq --include="*.tf" "publicly_accessible.*=.*true" "$COMP_DIR/"; then
  fail "publicly_accessible = true found in compliance examples — databases must not be publicly accessible"
else
  pass "No publicly_accessible = true"
fi

# Must NOT have encrypted = false
if grep -rq --include="*.tf" "encrypted.*=.*false" "$COMP_DIR/"; then
  fail "encrypted = false found — all storage resources must be encrypted"
else
  pass "No encrypted = false"
fi

# Must NOT skip final snapshots on databases
if grep -rq --include="*.tf" "skip_final_snapshot.*=.*true" "$COMP_DIR/"; then
  fail "skip_final_snapshot = true found — production databases must take a final snapshot"
else
  pass "No skip_final_snapshot = true"
fi

echo ""
echo "=== Terraform syntax (if terraform available) ==="

if command -v terraform >/dev/null 2>&1; then
  echo "  INFO: terraform found — running fmt check on compliance examples"
  find "$COMP_DIR" -name "*.tf" -exec dirname {} \; | sort -u | while read -r dir; do
    if terraform fmt -check "$dir" >/dev/null 2>&1; then
      pass "terraform fmt: $(basename "$dir")"
    else
      fail "terraform fmt failed: $dir — run 'terraform fmt $dir'"
    fi
  done
else
  echo "  INFO: terraform not found — skipping fmt check"
fi

echo ""
echo "=== checkov (if available) ==="

if command -v checkov >/dev/null 2>&1; then
  echo "  INFO: checkov found — running on compliance examples"
  if checkov -d "$COMP_DIR" --config-file "$COMP_DIR/checkov-config.yaml" --quiet >/dev/null 2>&1; then
    pass "checkov passed"
  else
    fail "checkov found issues — run 'checkov -d examples/compliance' for details"
  fi
else
  echo "  INFO: checkov not found — skipping (install: pip install checkov)"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all compliance example checks passed"
