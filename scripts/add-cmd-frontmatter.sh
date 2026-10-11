#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
cd "$(dirname "$0")/.."

add_cmd_frontmatter() {
  local file="$1"
  local title="$2"
  local label="$3"
  # Insert title/sidebar_label/custom_edit_url before the closing --- of the front matter block
  # The closing --- is the second occurrence of ^---
  python3 - "$file" "$title" "$label" <<'PYEOF'
import sys, re
path, title, label = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path).read()
# Find the second --- (closing front matter)
parts = content.split('---', 2)  # ['', 'existing fields\n', 'rest of file']
if len(parts) < 3:
    print(f"SKIP (no front matter block): {path}")
    sys.exit(0)
fm = parts[1]
if 'title:' in fm:
    print(f"SKIP (already has title): {path}")
    sys.exit(0)
new_fm = fm.rstrip('\n') + f'\ntitle: "{title}"\nsidebar_label: "{label}"\ncustom_edit_url: null\n'
new_content = '---' + new_fm + '---' + parts[2]
open(path, 'w').write(new_content)
print(f"DONE: {path}")
PYEOF
}

add_cmd_frontmatter skills/awesome-docs/SKILL.md "Awesome Docs Command" "awesome-docs"
add_cmd_frontmatter skills/aws-profile/SKILL.md "AWS Profile Command" "aws-profile"
add_cmd_frontmatter skills/aws/SKILL.md "AWS Command" "aws"
add_cmd_frontmatter skills/chaos/SKILL.md "Chaos Engineering Command" "chaos"
add_cmd_frontmatter skills/checkov/SKILL.md "Checkov Command" "checkov"
add_cmd_frontmatter skills/commit/SKILL.md "Commit Command" "commit"
add_cmd_frontmatter skills/compliance/SKILL.md "Compliance Command" "compliance"
add_cmd_frontmatter skills/composite-actions/SKILL.md "Composite Actions Command" "composite-actions"
add_cmd_frontmatter skills/datadog/SKILL.md "Datadog Command" "datadog"
add_cmd_frontmatter skills/debug/SKILL.md "Debug Command" "debug"
add_cmd_frontmatter skills/document/SKILL.md "Document Command" "document"
add_cmd_frontmatter skills/dora/SKILL.md "DORA Metrics Command" "dora"
add_cmd_frontmatter skills/dynatrace/SKILL.md "Dynatrace Command" "dynatrace"
add_cmd_frontmatter skills/fluxcd/SKILL.md "Flux CD Command" "fluxcd"
add_cmd_frontmatter skills/gitops/SKILL.md "GitOps Command" "gitops"
add_cmd_frontmatter skills/helmchart/SKILL.md "Helm Chart Command" "helmchart"
add_cmd_frontmatter skills/karpenter/SKILL.md "Karpenter Command" "karpenter"
add_cmd_frontmatter skills/keda/SKILL.md "KEDA Command" "keda"
add_cmd_frontmatter skills/kyverno/SKILL.md "Kyverno Command" "kyverno"
add_cmd_frontmatter skills/linkerd/SKILL.md "Linkerd Command" "linkerd"
add_cmd_frontmatter skills/linux/SKILL.md "Linux Command" "linux"
add_cmd_frontmatter skills/mcp/SKILL.md "MCP Command" "mcp"
add_cmd_frontmatter skills/observability/SKILL.md "Observability Command" "observability"
add_cmd_frontmatter skills/opa/SKILL.md "OPA Command" "opa"
add_cmd_frontmatter skills/pr-review/SKILL.md "PR Review Command" "pr-review"
add_cmd_frontmatter skills/product/SKILL.md "Product Command" "product"
add_cmd_frontmatter skills/renovate/SKILL.md "Renovate Command" "renovate"
add_cmd_frontmatter skills/preflight/SKILL.md "Preflight Command" "preflight"
add_cmd_frontmatter skills/runtime-security/SKILL.md "Runtime Security Command" "runtime-security"
add_cmd_frontmatter skills/self-improve/SKILL.md "Self-Improve Command" "self-improve"
add_cmd_frontmatter skills/setup-agents/SKILL.md "Setup Agents Command" "setup-agents"
add_cmd_frontmatter skills/supply-chain/SKILL.md "Supply Chain Command" "supply-chain"
add_cmd_frontmatter skills/terraform/SKILL.md "Terraform Command" "terraform"
add_cmd_frontmatter skills/triage/SKILL.md "Triage Command" "triage"
add_cmd_frontmatter skills/trivy/SKILL.md "Trivy Command" "trivy"
