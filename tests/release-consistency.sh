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
SKIP_DOMAINS="platform-operating-model|platform-mindset|secrets|pr-review"

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
