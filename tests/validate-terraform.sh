#!/usr/bin/env bash
# Single source of truth for the Terraform sweep.
#
# This logic previously existed as two inline `run:` blocks — one in validate.yml
# (the PR gate) and one in release.yml (the release gate) — and they had already
# drifted: the PR gate ran `terraform fmt -check -recursive`, the release gate
# did not. Unified here, so the release gate cannot be weaker or stronger than
# the gate that let the change in.
#
# Callers: validate.yml, release.yml, terraform-drift.yml.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# examples/demo is excluded because demo dirs intentionally pair a bad file with
# its fixed version; as a single module they declare conflicting resources.
#
# evals/*/evidence is excluded for the same class of reason. Benchmark fixture
# evidence is an EXCERPT copied so a fixture is self-contained for an agent to
# read, not a module anyone applies. Some are deliberately partial: the IAM
# control ships only the one policy file its question is about, so it references
# a bucket and an assume-role document declared in the sibling files it does not
# carry, and `terraform validate` reports four undeclared-resource errors.
# Sweeping them would force every fixture to grow scaffolding unrelated to the
# discovery question it measures, and would run `terraform init` with a provider
# download once per fixture.
TF_DIRS=$(find . -type f -name "*.tf" \
  ! -path "./.git/*" \
  ! -path "./examples/demo/*" \
  ! -path "./evals/*/evidence/*" \
  ! -path "*/.terraform/*" \
  -exec dirname {} \; | sort -u)

if [ -z "$TF_DIRS" ]; then
  echo "ℹ️  No Terraform files found"
  exit 0
fi

ERRORS=0
CHECKED=0

while IFS= read -r dir; do
  echo ""
  echo "📁 Validating Terraform in: $dir"
  echo "─────────────────────────────────────"
  CHECKED=$((CHECKED + 1))

  (
    cd "$dir"

    if ! terraform fmt -check -recursive; then
      echo "❌ Terraform formatting issues in: $dir"
      exit 1
    fi
    echo "✅ Terraform formatting correct"

    # -backend=false avoids touching remote state; -input=false makes a missing
    # value a failure rather than a hang waiting on a prompt.
    if ! terraform init -backend=false -input=false; then
      echo "❌ Terraform init failed in: $dir"
      exit 1
    fi
    echo "✅ Terraform init successful"

    if ! terraform validate; then
      echo "❌ Terraform validation failed in: $dir"
      exit 1
    fi
    echo "✅ Terraform validation successful"
  ) || ERRORS=$((ERRORS + 1))
done <<< "$TF_DIRS"

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ Found $ERRORS Terraform validation errors across $CHECKED directories"
  exit 1
fi

echo "✅ All $CHECKED Terraform directories validated"
