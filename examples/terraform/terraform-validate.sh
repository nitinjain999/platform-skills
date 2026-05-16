#!/usr/bin/env bash
# Offline validator for examples/terraform/
# Run from the repository root: bash examples/terraform/terraform-validate.sh
# Requires: bash. terraform/tflint/checkov used when available.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/examples/terraform"
EKS_DIR="$TF_DIR/eks-cluster"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== Terraform example structure ==="

for f in "README.md" "eks-cluster/main.tf" "eks-cluster/variables.tf" \
         "eks-cluster/outputs.tf" "eks-cluster/versions.tf"; do
  if [ -f "$TF_DIR/$f" ]; then
    pass "$f exists"
  else
    fail "$f missing"
  fi
done

echo ""
echo "=== Module structure best practices ==="

# versions.tf must pin provider versions
if grep -q "required_providers" "$EKS_DIR/versions.tf" 2>/dev/null; then
  pass "versions.tf has required_providers block"
else
  fail "versions.tf missing required_providers block"
fi

# variables.tf must have validation blocks
if grep -q "validation {" "$EKS_DIR/variables.tf" 2>/dev/null; then
  pass "variables.tf has validation blocks"
else
  fail "variables.tf missing validation blocks — add condition + error_message for key variables"
fi

# outputs.tf must exist and have description fields
if [ -f "$EKS_DIR/outputs.tf" ]; then
  if grep -q 'description' "$EKS_DIR/outputs.tf"; then
    pass "outputs.tf has description fields"
  else
    fail "outputs.tf missing description fields on outputs"
  fi
fi

echo ""
echo "=== Security patterns ==="

# Must NOT have hardcoded AWS credentials
if grep -rqE --include="*.tf" "aws_access_key_id|aws_secret_access_key|AKIA[A-Z0-9]{16}" "$EKS_DIR/" 2>/dev/null; then
  fail "Hardcoded AWS credentials detected in eks-cluster — remove immediately"
else
  pass "No hardcoded AWS credentials found"
fi

# Must NOT have publicly_accessible = true on databases
if grep -rq --include="*.tf" "publicly_accessible.*=.*true" "$TF_DIR/" 2>/dev/null; then
  fail "publicly_accessible = true found — databases must not be publicly accessible (SOC 2 CC6.6)"
else
  pass "No publicly_accessible = true found"
fi

# KMS encryption should be present in production modules
if grep -rq "aws_kms_key\|kms_key_id" "$EKS_DIR/" 2>/dev/null; then
  pass "KMS encryption reference found in eks-cluster"
else
  fail "No KMS key reference in eks-cluster — EKS secrets and EBS volumes should be encrypted"
fi

echo ""
echo "=== terraform fmt check (if available) ==="

if command -v terraform >/dev/null 2>&1; then
  echo "  INFO: terraform found — running fmt check"
  if terraform fmt -check -recursive "$EKS_DIR" >/dev/null 2>&1; then
    pass "terraform fmt check passed"
  else
    fail "terraform fmt check failed — run 'terraform fmt -recursive examples/terraform/eks-cluster'"
  fi

  echo "  INFO: running terraform validate"
  (cd "$EKS_DIR" && terraform init -backend=false >/dev/null 2>&1 && terraform validate >/dev/null 2>&1) && \
    pass "terraform validate passed" || \
    fail "terraform validate failed — run 'cd examples/terraform/eks-cluster && terraform init -backend=false && terraform validate'"
else
  echo "  INFO: terraform not found — skipping fmt/validate (install: https://developer.hashicorp.com/terraform/install)"
fi

echo ""
echo "=== tflint (if available) ==="

if command -v tflint >/dev/null 2>&1; then
  echo "  INFO: tflint found"
  if tflint --chdir="$EKS_DIR" >/dev/null 2>&1; then
    pass "tflint passed"
  else
    echo "  WARN: tflint found issues — run 'tflint --chdir examples/terraform/eks-cluster' to review"
  fi
else
  echo "  INFO: tflint not found — skipping (install: https://github.com/terraform-linters/tflint)"
fi

echo ""
echo "=== checkov (if available) ==="

if command -v checkov >/dev/null 2>&1; then
  echo "  INFO: checkov found"
  if checkov -d "$EKS_DIR" --quiet >/dev/null 2>&1; then
    pass "checkov passed"
  else
    echo "  WARN: checkov found issues — run 'checkov -d examples/terraform/eks-cluster' to review"
  fi
else
  echo "  INFO: checkov not found — skipping (install: pip install checkov)"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all Terraform example checks passed"
