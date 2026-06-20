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

add_cmd_frontmatter commands/awesome-docs.md "Awesome Docs Command" "awesome-docs"
add_cmd_frontmatter commands/aws-profile.md "AWS Profile Command" "aws-profile"
add_cmd_frontmatter commands/aws.md "AWS Command" "aws"
add_cmd_frontmatter commands/chaos.md "Chaos Engineering Command" "chaos"
add_cmd_frontmatter commands/checkov.md "Checkov Command" "checkov"
add_cmd_frontmatter commands/commit.md "Commit Command" "commit"
add_cmd_frontmatter commands/compliance.md "Compliance Command" "compliance"
add_cmd_frontmatter commands/composite-actions.md "Composite Actions Command" "composite-actions"
add_cmd_frontmatter commands/datadog.md "Datadog Command" "datadog"
add_cmd_frontmatter commands/debug.md "Debug Command" "debug"
add_cmd_frontmatter commands/document.md "Document Command" "document"
add_cmd_frontmatter commands/dora.md "DORA Metrics Command" "dora"
add_cmd_frontmatter commands/dynatrace.md "Dynatrace Command" "dynatrace"
add_cmd_frontmatter commands/fluxcd.md "Flux CD Command" "fluxcd"
add_cmd_frontmatter commands/gitops.md "GitOps Command" "gitops"
add_cmd_frontmatter commands/helmcheck.md "Helm Check Command" "helmcheck"
add_cmd_frontmatter commands/karpenter.md "Karpenter Command" "karpenter"
add_cmd_frontmatter commands/keda.md "KEDA Command" "keda"
add_cmd_frontmatter commands/kyverno.md "Kyverno Command" "kyverno"
add_cmd_frontmatter commands/linkerd.md "Linkerd Command" "linkerd"
add_cmd_frontmatter commands/linux.md "Linux Command" "linux"
add_cmd_frontmatter commands/mcp.md "MCP Command" "mcp"
add_cmd_frontmatter commands/observability.md "Observability Command" "observability"
add_cmd_frontmatter commands/opa.md "OPA Command" "opa"
add_cmd_frontmatter commands/pr-review.md "PR Review Command" "pr-review"
add_cmd_frontmatter commands/product.md "Product Command" "product"
add_cmd_frontmatter commands/renovate.md "Renovate Command" "renovate"
add_cmd_frontmatter commands/review.md "Review Command" "review"
add_cmd_frontmatter commands/runtime-security.md "Runtime Security Command" "runtime-security"
add_cmd_frontmatter commands/self-improve.md "Self-Improve Command" "self-improve"
add_cmd_frontmatter commands/setup-agents.md "Setup Agents Command" "setup-agents"
add_cmd_frontmatter commands/supply-chain.md "Supply Chain Command" "supply-chain"
add_cmd_frontmatter commands/terraform.md "Terraform Command" "terraform"
add_cmd_frontmatter commands/triage.md "Triage Command" "triage"
add_cmd_frontmatter commands/trivy.md "Trivy Command" "trivy"
