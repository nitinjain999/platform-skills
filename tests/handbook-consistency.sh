#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Checking skill and marketplace identity..."
SKILL_NAME="$(awk '/^name:/{print $2; exit}' SKILL.md)"
MARKETPLACE_NAME="$(jq -r '.name' .claude-plugin/marketplace.json)"
PLUGIN_NAME="$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)"
PLUGIN_VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
MARKETPLACE_VERSION="$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"
CHANGELOG_VERSION="$(awk '$1 == "##" && $2 ~ /^\[[0-9]+\.[0-9]+\.[0-9]+\]$/ {gsub(/[][]/, "", $2); print $2; exit}' CHANGELOG.md)"

if [[ "$SKILL_NAME" != "$MARKETPLACE_NAME" || "$SKILL_NAME" != "$PLUGIN_NAME" ]]; then
  echo "❌ Skill and marketplace names are out of sync"
  echo "SKILL.md: $SKILL_NAME"
  echo "marketplace root: $MARKETPLACE_NAME"
  echo "marketplace plugin: $PLUGIN_NAME"
  exit 1
fi

if [[ "$PLUGIN_VERSION" != "$MARKETPLACE_VERSION" || "$PLUGIN_VERSION" != "$CHANGELOG_VERSION" ]]; then
  echo "❌ Plugin, marketplace, and changelog versions are out of sync"
  echo "plugin.json: $PLUGIN_VERSION"
  echo "marketplace.json: $MARKETPLACE_VERSION"
  echo "CHANGELOG.md latest: $CHANGELOG_VERSION"
  exit 1
fi

if ! grep -q "platform-skills  v${PLUGIN_VERSION}  enabled" INSTALLATION.md; then
  echo "❌ INSTALLATION.md verify output does not match version $PLUGIN_VERSION"
  exit 1
fi

declare -a REQUIRED_PATHS=(
  "references/platform-operating-model.md"
  "references/terraform.md"
  "references/kubernetes.md"
  "references/openshift.md"
  "references/fluxcd.md"
  "references/argocd.md"
  "references/aws.md"
  "references/azure.md"
  "references/github-actions.md"
  "examples/fluxcd/basic-monorepo"
  "examples/argocd/app-of-apps/application.yaml"
  "examples/argocd/projects/platform-project.yaml"
  "examples/terraform/eks-cluster/main.tf"
  "examples/github-actions/terraform-cicd.yml"
  "examples/github-actions/container-build.yml"
  "examples/github-actions/flux-sync.yml"
  "examples/github-actions/reusable-workflows/terraform-plan.yml"
  "examples/github-actions/composite-actions/setup-terraform/action.yml"
  "examples/github-actions/composite-actions/configure-cloud/action.yml"
  "examples/triage/README.md"
  "commands/triage.md"
  "examples/agent-self-improve/README.md"
  "commands/self-improve.md"
  "references/agent-self-improve.md"
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

echo "Checking example maturity labels..."
while IFS= read -r path; do
  if ! grep -q "^Status:" "$path"; then
    echo "❌ Missing maturity label in $path"
    exit 1
  fi
done < <(find examples -mindepth 2 -maxdepth 2 -name README.md | sort)

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
