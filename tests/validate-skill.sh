#!/usr/bin/env bash
# Validates that the skill structure is internally consistent.
# Run from the repository root: bash tests/validate-skill.sh

set -euo pipefail

ERRORS=0

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo ""
echo "=== SKILL.md ==="

if diff -q SKILL.md skills/platform-skills/SKILL.md >/dev/null; then
  pass "root SKILL.md matches packaged skill"
else
  fail "root SKILL.md and skills/platform-skills/SKILL.md are out of sync"
fi

# Must have YAML frontmatter
if head -1 skills/platform-skills/SKILL.md | grep -q "^---"; then
  pass "SKILL.md has frontmatter"
else
  fail "SKILL.md missing frontmatter"
fi

# Must have name and description fields
for field in "^name:" "^description:"; do
  if sed -n '/^---$/,/^---$/p' skills/platform-skills/SKILL.md | grep -qE "$field"; then
    pass "SKILL.md frontmatter has '${field}' field"
  else
    fail "SKILL.md frontmatter missing '${field}' field"
  fi
done

echo ""
echo "=== Reference files ==="

REQUIRED_REFERENCES=(
  references/platform-operating-model.md
  references/terraform.md
  references/kubernetes.md
  references/openshift.md
  references/flux.md
  references/argocd.md
  references/aws.md
  references/azure.md
  references/github-actions.md
  references/secrets.md
  references/linkerd.md
  references/linux-networking.md
  references/platform-mindset.md
  references/compliance.md
  references/helm.md
  references/mcp.md
  references/observability.md
  references/documentation.md
  references/datadog.md
  references/dynatrace.md
  references/conventional-commits.md
  references/opa.md
  references/kyverno.md
  references/pr-review.md
  references/keda.md
  references/agent-self-improve.md
  references/supply-chain.md
  references/runtime-security.md
  references/chaos.md
  references/dora.md
  references/llm-observability.md
  references/awesome-docs.md
)

for ref in "${REQUIRED_REFERENCES[@]}"; do
  if [ -f "$ref" ]; then
    pass "$ref exists"
  else
    fail "$ref missing"
  fi
done

echo ""
echo "=== Example domains have assets beyond README.md ==="

EXAMPLE_DOMAINS=(
  examples/aws
  examples/azure
  examples/kubernetes
  examples/openshift
  examples/argocd
  examples/flux
  examples/terraform
  examples/github-actions
  examples/compliance
  examples/helm
  examples/mcp
  examples/observability
  examples/documentation
  examples/datadog
  examples/dynatrace
  examples/conventional-commits
  examples/opa
  examples/kyverno
  examples/pr-review
  examples/triage
  examples/keda
  examples/agent-self-improve
  examples/supply-chain
  examples/runtime-security
  examples/chaos
  examples/dora
  examples/datadog/llm-observability
  examples/awesome-docs
)

for domain in "${EXAMPLE_DOMAINS[@]}"; do
  ASSET_COUNT=$(find "$domain" -type f ! -name "README.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ASSET_COUNT" -gt 0 ]; then
    pass "$domain has $ASSET_COUNT asset(s)"
  else
    fail "$domain has no example assets (only README.md)"
  fi
done

echo ""
echo "=== SKILL.md references all required reference files ==="

for ref in "${REQUIRED_REFERENCES[@]}"; do
  if grep -q "$ref" skills/platform-skills/SKILL.md; then
    pass "SKILL.md references $ref"
  else
    fail "SKILL.md does not reference $ref"
  fi
done

echo ""
echo "=== Command files declared in plugin.json exist ==="

PLUGIN_JSON=".claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ]; then
  # Every command path in plugin.json must point to a real file
  while IFS= read -r cmd_path; do
    cmd_file="${cmd_path#./}"
    if [ -f "$cmd_file" ]; then
      pass "$cmd_file exists"
    else
      fail "$cmd_file declared in plugin.json but not found"
    fi
  done < <(grep -o '"./commands/[^"]*"' "$PLUGIN_JSON" | tr -d '"')

  # Every commands/*.md file must be registered in plugin.json
  for cmd_file in commands/*.md; do
    cmd_path="./$cmd_file"
    if grep -q "\"$cmd_path\"" "$PLUGIN_JSON"; then
      pass "$cmd_file registered in plugin.json"
    else
      fail "$cmd_file exists but is not registered in plugin.json"
    fi
  done
else
  fail "$PLUGIN_JSON not found"
fi

echo ""
echo "=== All commands: frontmatter fields and doc presence ==="

# Docs that must carry the full /platform-skills:<name> slash command form
SLASH_CMD_DOCS=(
  SKILL.md
  skills/platform-skills/SKILL.md
  COMMANDS.md
  HOW_IT_WORKS.md
)

# Docs where the command name alone is sufficient (short-name tables)
# README.md has a domain table (not commands) — not included here
# QUICKSTART.md is intentionally minimal — links to COMMANDS.md rather than listing all commands
NAME_ONLY_DOCS=(
  GETTING_STARTED.md
)

for cmd_file in commands/*.md; do
  cmd_name="$(awk '/^name:/{print $2; exit}' "$cmd_file")"

  if [ -z "$cmd_name" ]; then
    fail "$cmd_file: missing 'name:' in frontmatter"
    continue
  fi

  # Required frontmatter fields
  for field in "^name:" "^description:" "^argument-hint:"; do
    if grep -qE "$field" "$cmd_file"; then
      pass "$cmd_file has '$field'"
    else
      fail "$cmd_file missing '$field'"
    fi
  done

  # Full slash command form must appear in canonical reference docs
  for doc in "${SLASH_CMD_DOCS[@]}"; do
    if grep -q "/platform-skills:${cmd_name}" "$doc"; then
      pass "$doc references /platform-skills:${cmd_name}"
    else
      fail "$doc missing /platform-skills:${cmd_name}"
    fi
  done

  # Command name (short form) must appear in navigational docs
  for doc in "${NAME_ONLY_DOCS[@]}"; do
    if grep -qi "${cmd_name}" "$doc"; then
      pass "$doc mentions ${cmd_name}"
    else
      fail "$doc missing any mention of ${cmd_name}"
    fi
  done
done

echo ""
echo "=== Commands with example directories: README.md present ==="

for cmd_file in commands/*.md; do
  cmd_name="$(awk '/^name:/{print $2; exit}' "$cmd_file")"
  [ -z "$cmd_name" ] && continue

  dir_candidates=("examples/${cmd_name}")
  case "$cmd_name" in
    commit)
      dir_candidates=("examples/conventional-commits")
      ;;
    document)
      dir_candidates=("examples/documentation")
      ;;
    helmcheck)
      dir_candidates=("examples/helm")
      ;;
    linux)
      dir_candidates=("examples/linux-networking")
      ;;
    composite-actions)
      dir_candidates=("examples/github-actions/composite-actions")
      ;;
  esac

  for dir_candidate in "${dir_candidates[@]}"; do
    if [ -d "$dir_candidate" ]; then
      if [ -f "${dir_candidate}/README.md" ]; then
        pass "${dir_candidate}/README.md exists"
      else
        fail "${dir_candidate}/ exists but is missing README.md"
      fi
    fi
  done
done

echo ""
echo "=== Domain validator scripts: run if present ==="

# Commands that ship a validate script alongside their examples
VALIDATE_SCRIPTS=(
  "examples/keda/keda-validate.sh"
  "examples/kyverno/kyverno-validate.sh"
  "examples/opa/opa-validate.sh"
  "examples/terraform/terraform-validate.sh"
  "examples/github-actions/gha-validate.sh"
  "examples/compliance/compliance-validate.sh"
  "examples/supply-chain/supply-chain-validate.sh"
  "examples/runtime-security/runtime-security-validate.sh"
  "examples/chaos/chaos-validate.sh"
  "examples/dora/dora-validate.sh"
)

for script in "${VALIDATE_SCRIPTS[@]}"; do
  if [ -f "$script" ]; then
    pass "$script exists"
    if bash "$script" >/dev/null 2>&1; then
      pass "$script passed"
    else
      fail "$script failed — run it directly for details"
    fi
  else
    fail "$script missing"
  fi
done

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all skill structure checks passed"
