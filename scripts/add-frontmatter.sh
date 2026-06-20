#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
cd "$(dirname "$0")/.."

add_frontmatter() {
  local file="$1"
  local title="$2"
  # Only add if file does NOT already start with ---
  if head -1 "$file" | grep -q "^---"; then
    echo "SKIP (has front matter): $file"
    return
  fi
  local tmp
  tmp=$(mktemp)
  # Quote titles that contain special YAML characters (colon, slash, etc.)
  if echo "$title" | grep -qE '[:/#]'; then
    printf -- "---\ntitle: \"%s\"\ncustom_edit_url: null\n---\n\n" "$title" > "$tmp"
  else
    printf -- "---\ntitle: %s\ncustom_edit_url: null\n---\n\n" "$title" > "$tmp"
  fi
  cat "$file" >> "$tmp"
  mv "$tmp" "$file"
  echo "DONE: $file"
}

# references/
add_frontmatter references/agent-self-improve.md "Agent Self-Improvement"
add_frontmatter references/argocd.md "Argo CD"
add_frontmatter references/awesome-docs.md "Awesome Docs"
add_frontmatter references/aws-cloudfront.md "AWS CloudFront"
add_frontmatter references/aws-mcp-profiles.md "AWS MCP Profiles"
add_frontmatter references/aws-waf.md "AWS WAF"
add_frontmatter references/aws.md "AWS"
add_frontmatter references/azure.md "Azure"
add_frontmatter references/chaos.md "Chaos Engineering"
add_frontmatter references/checkov.md "Checkov"
add_frontmatter references/compliance.md "Compliance"
add_frontmatter references/composite-actions.md "GitHub Actions: Composite Actions"
add_frontmatter references/conventional-commits.md "Conventional Commits"
add_frontmatter references/datadog.md "Datadog"
add_frontmatter references/documentation.md "Documentation"
add_frontmatter references/dora.md "DORA Metrics"
add_frontmatter references/dynatrace.md "Dynatrace"
add_frontmatter references/fluxcd-helmrelease.md "Flux CD: HelmRelease"
add_frontmatter references/fluxcd-kustomization.md "Flux CD: Kustomization"
add_frontmatter references/fluxcd-mcp.md "Flux CD: MCP"
add_frontmatter references/fluxcd-migration.md "Flux CD: Migration"
add_frontmatter references/fluxcd-notifications.md "Flux CD: Notifications"
add_frontmatter references/fluxcd-operator.md "Flux CD: Operator"
add_frontmatter references/fluxcd-resourcesets.md "Flux CD: ResourceSets"
add_frontmatter references/fluxcd-security.md "Flux CD: Security"
add_frontmatter references/fluxcd-sources.md "Flux CD: Sources"
add_frontmatter references/fluxcd-terraform.md "Flux CD: Terraform"
add_frontmatter references/fluxcd-troubleshooting.md "Flux CD: Troubleshooting"
add_frontmatter references/fluxcd.md "Flux CD"
add_frontmatter references/github-actions.md "GitHub Actions"
add_frontmatter references/helm.md "Helm"
add_frontmatter references/karpenter.md "Karpenter"
add_frontmatter references/keda.md "KEDA"
add_frontmatter references/kubernetes.md "Kubernetes"
add_frontmatter references/kyverno.md "Kyverno"
add_frontmatter references/linkerd.md "Linkerd"
add_frontmatter references/linux-networking.md "Linux Networking"
add_frontmatter references/llm-observability.md "LLM Observability"
add_frontmatter references/mcp.md "MCP"
add_frontmatter references/observability.md "Observability"
add_frontmatter references/opa.md "OPA / Rego"
add_frontmatter references/openshift.md "OpenShift"
add_frontmatter references/platform-mindset.md "Platform Mindset"
add_frontmatter references/platform-operating-model.md "Platform Operating Model"
add_frontmatter references/pr-review.md "PR Review"
add_frontmatter references/renovate.md "Renovate"
add_frontmatter references/runtime-security.md "Runtime Security"
add_frontmatter references/secrets.md "Secrets Management"
add_frontmatter references/setup-agents-add.md "Setup Agents: Add"
add_frontmatter references/setup-agents-build.md "Setup Agents: Build"
add_frontmatter references/setup-agents-generate.md "Setup Agents: Generate"
add_frontmatter references/setup-agents-prompts.md "Setup Agents: Prompts"
add_frontmatter references/setup-agents-review.md "Setup Agents: Review"
add_frontmatter references/setup-agents-schemas.md "Setup Agents: Schemas"
add_frontmatter references/setup-agents-template.md "Setup Agents: Template"
add_frontmatter references/setup-agents.md "Setup Agents"
add_frontmatter references/supply-chain.md "Supply Chain Security"
add_frontmatter references/terraform.md "Terraform"
add_frontmatter references/trivy.md "Trivy"
