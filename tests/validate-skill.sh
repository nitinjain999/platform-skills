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
  # Extract command paths from plugin.json (lines containing ./commands/)
  while IFS= read -r cmd_path; do
    # Strip leading ./ for file check
    cmd_file="${cmd_path#./}"
    if [ -f "$cmd_file" ]; then
      pass "$cmd_file exists"
    else
      fail "$cmd_file declared in plugin.json but not found"
    fi
  done < <(grep -o '"./commands/[^"]*"' "$PLUGIN_JSON" | tr -d '"')

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
echo "=== Triage command integration ==="

TRIAGE_CMD="commands/triage.md"
TRIAGE_EXAMPLES="examples/triage"

if [ -f "$TRIAGE_CMD" ]; then
  pass "$TRIAGE_CMD exists"
else
  fail "$TRIAGE_CMD missing"
fi

for field in "^name: triage$" "^description:" "^argument-hint:"; do
  if grep -qE "$field" "$TRIAGE_CMD"; then
    pass "$TRIAGE_CMD has '$field'"
  else
    fail "$TRIAGE_CMD missing '$field'"
  fi
done

if grep -q '"./commands/triage.md"' "$PLUGIN_JSON"; then
  pass "commands/triage.md registered in plugin.json"
else
  fail "commands/triage.md not registered in plugin.json"
fi

for doc in SKILL.md skills/platform-skills/SKILL.md COMMANDS.md HOW_IT_WORKS.md README.md GETTING_STARTED.md QUICKSTART.md; do
  if grep -q "/platform-skills:triage" "$doc"; then
    pass "$doc references /platform-skills:triage"
  else
    fail "$doc missing /platform-skills:triage"
  fi
done

if [ -d "$TRIAGE_EXAMPLES" ] && [ -f "$TRIAGE_EXAMPLES/README.md" ]; then
  pass "$TRIAGE_EXAMPLES has README.md"
else
  fail "$TRIAGE_EXAMPLES missing README.md"
fi

echo ""
echo "=== KEDA command integration ==="

KEDA_CMD="commands/keda.md"
KEDA_EXAMPLES="examples/keda"

if [ -f "$KEDA_CMD" ]; then
  pass "$KEDA_CMD exists"
else
  fail "$KEDA_CMD missing"
fi

for field in "^name: keda$" "^description:" "^argument-hint:"; do
  if grep -qE "$field" "$KEDA_CMD"; then
    pass "$KEDA_CMD has '$field'"
  else
    fail "$KEDA_CMD missing '$field'"
  fi
done

if grep -q '"./commands/keda.md"' "$PLUGIN_JSON"; then
  pass "commands/keda.md registered in plugin.json"
else
  fail "commands/keda.md not registered in plugin.json"
fi

for doc in SKILL.md skills/platform-skills/SKILL.md COMMANDS.md HOW_IT_WORKS.md README.md GETTING_STARTED.md QUICKSTART.md; do
  if grep -q "/platform-skills:keda" "$doc"; then
    pass "$doc references /platform-skills:keda"
  else
    fail "$doc missing /platform-skills:keda"
  fi
done

if [ -d "$KEDA_EXAMPLES" ] && [ -f "$KEDA_EXAMPLES/README.md" ]; then
  pass "$KEDA_EXAMPLES has README.md"
else
  fail "$KEDA_EXAMPLES missing README.md"
fi

if [ -f "$KEDA_EXAMPLES/keda-validate.sh" ]; then
  pass "$KEDA_EXAMPLES/keda-validate.sh exists"
  if bash "$KEDA_EXAMPLES/keda-validate.sh" >/dev/null 2>&1; then
    pass "$KEDA_EXAMPLES/keda-validate.sh passed"
  else
    fail "$KEDA_EXAMPLES/keda-validate.sh failed — run it directly for details"
  fi
else
  fail "$KEDA_EXAMPLES/keda-validate.sh missing"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi

echo "PASS: all skill structure checks passed"
