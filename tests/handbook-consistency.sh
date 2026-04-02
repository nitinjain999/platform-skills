#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Checking skill and marketplace identity..."
SKILL_NAME="$(awk '/^name:/{print $2; exit}' SKILL.md)"
MARKETPLACE_NAME="$(jq -r '.name' .claude-plugin/marketplace.json)"
PLUGIN_NAME="$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)"

if [[ "$SKILL_NAME" != "$MARKETPLACE_NAME" || "$SKILL_NAME" != "$PLUGIN_NAME" ]]; then
  echo "❌ Skill and marketplace names are out of sync"
  echo "SKILL.md: $SKILL_NAME"
  echo "marketplace root: $MARKETPLACE_NAME"
  echo "marketplace plugin: $PLUGIN_NAME"
  exit 1
fi

declare -a REQUIRED_PATHS=(
  "references/platform-operating-model.md"
  "references/terraform.md"
  "references/kubernetes.md"
  "references/openshift.md"
  "references/flux.md"
  "references/argocd.md"
  "references/aws.md"
  "references/azure.md"
  "references/github-actions.md"
  "examples/flux/basic-monorepo"
  "examples/argocd/app-of-apps/application.yaml"
  "examples/argocd/projects/platform-project.yaml"
  "examples/terraform/eks-cluster/main.tf"
  "examples/github-actions/terraform-cicd.yml"
  "examples/github-actions/container-build.yml"
  "examples/github-actions/flux-sync.yml"
  "examples/github-actions/reusable-workflows/terraform-plan.yml"
  "examples/github-actions/composite-actions/setup-terraform/action.yml"
  "examples/github-actions/composite-actions/configure-cloud/action.yml"
  "examples/aws/README.md"
  "examples/azure/README.md"
  "examples/kubernetes/README.md"
  "examples/openshift/README.md"
)

echo "Checking required handbook paths..."
for path in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "❌ Missing handbook path: $path"
    exit 1
  fi
done

declare -a STATUS_DOCS=(
  "examples/argocd/README.md"
  "examples/aws/README.md"
  "examples/azure/README.md"
  "examples/flux/README.md"
  "examples/github-actions/README.md"
  "examples/kubernetes/README.md"
  "examples/openshift/README.md"
  "examples/terraform/README.md"
)

echo "Checking example maturity labels..."
for path in "${STATUS_DOCS[@]}"; do
  if ! grep -q "^Status:" "$path"; then
    echo "❌ Missing maturity label in $path"
    exit 1
  fi
done

declare -a STALE_LINK_PATTERNS=(
  "\\[multi-tenant/\\]\\(multi-tenant/\\)"
  "\\[helm-releases/\\]\\(helm-releases/\\)"
  "\\[image-automation/\\]\\(image-automation/\\)"
  "\\[module-testing/\\]\\(module-testing/\\)"
  "\\[cicd-pipeline/\\]\\(cicd-pipeline/\\)"
)

echo "Checking for stale example links..."
for pattern in "${STALE_LINK_PATTERNS[@]}"; do
  if rg -n "$pattern" README.md examples >/dev/null; then
    echo "❌ Found stale example link matching: $pattern"
    exit 1
  fi
done

echo "✅ Handbook consistency checks passed"
