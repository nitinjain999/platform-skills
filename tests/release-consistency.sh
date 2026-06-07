#!/usr/bin/env bash
# Release consistency checks — run before tagging a release.
# Verifies: version sync, command count, SKILL.md sync, doc coverage for all commands.
# Run from the repository root: bash tests/release-consistency.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# ---------------------------------------------------------------------------
echo ""
echo "=== Version sync ==="

PLUGIN_VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
MARKETPLACE_VERSION="$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"
CHANGELOG_VERSION="$(awk '$1 == "##" && $2 ~ /^\[[0-9]+\.[0-9]+\.[0-9]+\]$/ {gsub(/[][]/, "", $2); print $2; exit}' CHANGELOG.md)"

pass "plugin.json version: $PLUGIN_VERSION"

if [ "$MARKETPLACE_VERSION" = "$PLUGIN_VERSION" ]; then
  pass "marketplace.json version matches plugin.json"
else
  fail "marketplace.json version $MARKETPLACE_VERSION ≠ plugin.json $PLUGIN_VERSION"
fi

if [ "$CHANGELOG_VERSION" = "$PLUGIN_VERSION" ]; then
  pass "CHANGELOG.md latest version matches plugin.json"
else
  fail "CHANGELOG.md latest [$CHANGELOG_VERSION] ≠ plugin.json $PLUGIN_VERSION"
fi

DUPLICATE_CHANGELOG_VERSIONS="$(awk '$1 == "##" && $2 ~ /^\[[0-9]+\.[0-9]+\.[0-9]+\]$/ {gsub(/[][]/, "", $2); print $2}' CHANGELOG.md | sort | uniq -d)"
if [ -z "$DUPLICATE_CHANGELOG_VERSIONS" ]; then
  pass "CHANGELOG.md has no duplicate version headings"
else
  fail "CHANGELOG.md has duplicate version heading(s): $DUPLICATE_CHANGELOG_VERSIONS"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== marketplace.json source.sha ==="

MARKETPLACE_SHA="$(jq -r '.plugins[0].source.sha' .claude-plugin/marketplace.json)"
if [ -z "$MARKETPLACE_SHA" ] || [ "$MARKETPLACE_SHA" = "null" ]; then
  fail "marketplace.json source.sha is empty — set to the release commit SHA before tagging"
else
  # Check it looks like a git SHA (40 hex chars)
  if echo "$MARKETPLACE_SHA" | grep -qE "^[0-9a-f]{40}$"; then
    pass "marketplace.json source.sha is a full 40-char SHA: ${MARKETPLACE_SHA:0:8}..."
    # Verify the SHA exists in this repo's history (warns if stale)
    if git cat-file -e "${MARKETPLACE_SHA}^{commit}" 2>/dev/null; then
      pass "marketplace.json source.sha exists in git history"
    else
      echo "  WARN: marketplace.json source.sha ${MARKETPLACE_SHA:0:8}... not found in local git history — verify before publishing"
    fi
  else
    fail "marketplace.json source.sha '$MARKETPLACE_SHA' does not look like a full git SHA"
  fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== SKILL.md sync ==="

if diff -q SKILL.md skills/platform-skills/SKILL.md >/dev/null; then
  pass "root SKILL.md matches skills/platform-skills/SKILL.md"
else
  fail "root SKILL.md and skills/platform-skills/SKILL.md are out of sync — run: cp SKILL.md skills/platform-skills/SKILL.md"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Codex skill metadata ==="

if [ -f agents/openai.yaml ]; then
  pass "agents/openai.yaml exists"
else
  fail "agents/openai.yaml missing"
fi

if grep -q 'default_prompt: "Use \$platform-skills' agents/openai.yaml 2>/dev/null; then
  pass 'agents/openai.yaml default_prompt references $platform-skills'
else
  fail 'agents/openai.yaml default_prompt must reference $platform-skills'
fi

if grep -q "allow_implicit_invocation: true" agents/openai.yaml 2>/dev/null; then
  pass "agents/openai.yaml allows implicit invocation"
else
  fail "agents/openai.yaml should allow implicit invocation"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Cursor rules ==="

CURSOR_RULES=(
  ".cursorrules"
  ".cursor/rules/platform-skills.mdc"
  ".cursor/rules/kubernetes.mdc"
  ".cursor/rules/terraform.mdc"
  ".cursor/rules/keda.mdc"
)

for cursor_rule in "${CURSOR_RULES[@]}"; do
  if [ -f "$cursor_rule" ]; then
    pass "$cursor_rule exists"
  else
    fail "$cursor_rule missing"
  fi
done

if grep -q "platform-skills v${PLUGIN_VERSION}" .cursorrules 2>/dev/null; then
  pass ".cursorrules version matches v${PLUGIN_VERSION}"
else
  fail ".cursorrules version does not match v${PLUGIN_VERSION}"
fi

if grep -q "Platform Skills — v${PLUGIN_VERSION}" .cursor/rules/platform-skills.mdc 2>/dev/null; then
  pass ".cursor/rules/platform-skills.mdc version matches v${PLUGIN_VERSION}"
else
  fail ".cursor/rules/platform-skills.mdc version does not match v${PLUGIN_VERSION}"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Copilot instructions ==="

if [ -f .github/copilot-instructions.md ]; then
  pass ".github/copilot-instructions.md exists"
else
  fail ".github/copilot-instructions.md missing"
fi

if grep -q "Version: ${PLUGIN_VERSION}" .github/copilot-instructions.md 2>/dev/null; then
  pass ".github/copilot-instructions.md version matches v${PLUGIN_VERSION}"
else
  fail ".github/copilot-instructions.md version does not match v${PLUGIN_VERSION}"
fi

if grep -q "install.sh --copilot" .github/copilot-instructions.md 2>/dev/null; then
  pass ".github/copilot-instructions.md documents installer path"
else
  fail ".github/copilot-instructions.md should document install.sh --copilot"
fi

while IFS= read -r copilot_ref; do
  if [ -f "$copilot_ref" ]; then
    pass ".github/copilot-instructions.md reference exists: $copilot_ref"
  else
    fail ".github/copilot-instructions.md references missing file: $copilot_ref"
  fi
done < <(grep -oE 'references/[a-z0-9-]+\.md' .github/copilot-instructions.md | sort -u)

# ---------------------------------------------------------------------------
echo ""
echo "=== Installer ==="

if [ -x install.sh ]; then
  pass "install.sh exists and is executable"
else
  fail "install.sh missing or not executable"
fi

if bash install.sh --help >/dev/null 2>&1; then
  pass "install.sh --help works"
else
  fail "install.sh --help failed"
fi

for flag in --claude --codex --cursor --copilot --all; do
  if grep -q -- "$flag" install.sh; then
    pass "install.sh supports $flag"
  else
    fail "install.sh missing $flag"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Adoption assets ==="

if [ -f PROMPTS.md ]; then
  pass "PROMPTS.md exists"
else
  fail "PROMPTS.md missing"
fi

if grep -q "PROMPTS.md" README.md && grep -q "PROMPTS.md" QUICKSTART.md; then
  pass "README.md and QUICKSTART.md link to PROMPTS.md"
else
  fail "README.md and QUICKSTART.md should link to PROMPTS.md"
fi

ADOPTION_TEMPLATES=(
  ".github/ISSUE_TEMPLATE/agent_editor_support.md"
  ".github/ISSUE_TEMPLATE/domain_guide_request.md"
  ".github/ISSUE_TEMPLATE/example_contribution.md"
)

for template in "${ADOPTION_TEMPLATES[@]}"; do
  if [ -f "$template" ]; then
    pass "$template exists"
  else
    fail "$template missing"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Command count consistency ==="

ACTUAL_CMD_COUNT=$(find commands/ -name "*.md" | wc -l | tr -d ' ')
PLUGIN_CMD_COUNT=$(jq '.commands | length' .claude-plugin/plugin.json)

if [ "$ACTUAL_CMD_COUNT" -eq "$PLUGIN_CMD_COUNT" ]; then
  pass "commands/ ($ACTUAL_CMD_COUNT files) matches plugin.json commands array ($PLUGIN_CMD_COUNT entries)"
else
  fail "commands/ has $ACTUAL_CMD_COUNT files but plugin.json has $PLUGIN_CMD_COUNT entries"
fi

# All major docs must reflect the actual count
for doc in GETTING_STARTED.md QUICKSTART.md CHANGELOG.md; do
  if grep -q "$ACTUAL_CMD_COUNT command" "$doc" || grep -q "all $ACTUAL_CMD_COUNT" "$doc" || grep -q "$ACTUAL_CMD_COUNT workflow" "$doc"; then
    pass "$doc references $ACTUAL_CMD_COUNT commands"
  else
    fail "$doc does not reference $ACTUAL_CMD_COUNT commands — update the count"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== All commands registered in plugin.json ==="

for cmd_file in commands/*.md; do
  cmd_path="./$cmd_file"
  if jq -e --arg p "$cmd_path" '.commands[] | select(. == $p)' .claude-plugin/plugin.json >/dev/null 2>&1; then
    pass "$cmd_file registered"
  else
    fail "$cmd_file not registered in plugin.json"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== All commands present in canonical docs ==="

REQUIRED_SLASH_DOCS=(SKILL.md skills/platform-skills/SKILL.md COMMANDS.md HOW_IT_WORKS.md)

for cmd_file in commands/*.md; do
  cmd_name="$(awk '/^name:/{print $2; exit}' "$cmd_file")"
  [ -z "$cmd_name" ] && continue

  for doc in "${REQUIRED_SLASH_DOCS[@]}"; do
    if grep -q "/platform-skills:${cmd_name}" "$doc"; then
      pass "$doc ∋ /platform-skills:${cmd_name}"
    else
      fail "$doc missing /platform-skills:${cmd_name}"
    fi
  done
done

# ---------------------------------------------------------------------------
echo ""
echo "=== All required references exist and are in SKILL.md ==="

while IFS= read -r ref; do
  if [ -f "$ref" ]; then
    pass "$ref exists"
  else
    fail "$ref missing"
  fi
  if grep -q "$ref" skills/platform-skills/SKILL.md; then
    pass "SKILL.md references $ref"
  else
    fail "SKILL.md does not reference $ref"
  fi
done < <(grep -oE 'references/[a-z-]+\.md' SKILL.md | sort -u)

# ---------------------------------------------------------------------------
echo ""
echo "=== Domain coverage: README.md mentions, SKILL.md reference, examples/ directory ==="

# Cross-cutting docs with no per-domain example directory or command — skip coverage checks
SKIP_DOMAINS="platform-operating-model|platform-mindset|secrets|pr-review|setup-agents-generate|setup-agents-add|setup-agents-prompts|setup-agents-schemas|setup-agents-template|setup-agents-review"

for ref in references/*.md; do
  domain="$(basename "$ref" .md)"
  echo "$domain" | grep -qE "^($SKIP_DOMAINS)$" && continue

  if grep -qi "$domain" README.md; then
    pass "README.md mentions $domain"
  else
    fail "README.md missing any mention of $domain"
  fi

  if grep -qi "$domain" SKILL.md; then
    pass "SKILL.md references $domain"
  else
    fail "SKILL.md does not reference $domain"
  fi

  if [ -d "examples/$domain" ]; then
    pass "examples/$domain/ directory exists"
  else
    echo "  INFO: examples/$domain/ does not exist (may be in progress)"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== INSTALLATION.md verify output ==="

if grep -q "platform-skills  v${PLUGIN_VERSION}  enabled" INSTALLATION.md; then
  pass "INSTALLATION.md shows v${PLUGIN_VERSION}"
else
  fail "INSTALLATION.md verify output does not show v${PLUGIN_VERSION}"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Example maturity labels ==="

while IFS= read -r readme; do
  if grep -qE "^Status: (Stable|Beta|Draft|Experimental)" "$readme"; then
    pass "$readme has valid Status label"
  elif grep -q "^Status:" "$readme"; then
    fail "$readme has 'Status:' but value is not Stable/Beta/Draft/Experimental"
  else
    fail "$readme missing Status: label"
  fi
done < <(find examples -mindepth 2 -maxdepth 2 -name README.md | sort)

# ---------------------------------------------------------------------------
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS release consistency error(s) — fix before tagging"
  exit 1
fi
echo "PASS: all release consistency checks passed — safe to tag v${PLUGIN_VERSION}"
