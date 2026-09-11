#!/usr/bin/env bash
# tests/website-coverage.sh — every command and reference must reach the docs site.
#
# The site's sidebars are hand-enumerated, and nothing compared them against the
# directories they document. Three consecutive releases shipped a command that
# never appeared on the site: kingfisher (1.39.0), ai-governance (1.40.0) and
# token-optimizer (1.41.0), plus azure, github-actions, kubernetes, openshift and
# secrets from earlier. The homepage separately advertised "41 commands" against
# a repo carrying 44, and the version in the hero sat at v1.38.0 across three
# releases. All of it was invisible because no gate looked at website/.
#
# Run from the repository root: bash tests/website-coverage.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# check_coverage <label> <content dir> <sidebar file>
check_coverage() {
  local label="$1" dir="$2" sidebar="$3"
  local listed files missing orphans

  if [ ! -f "$sidebar" ]; then
    fail "$label sidebar missing: $sidebar"
    return
  fi

  listed="$(grep -oE "id: '[a-z0-9-]+'" "$sidebar" | sed "s/id: '//;s/'//" | sort -u)"
  files="$(find "$dir" -maxdepth 1 -name '*.md' -exec basename {} .md \; | sort)"

  missing="$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$files"))"
  orphans="$(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$files"))"

  if [ -z "$missing" ]; then
    pass "$label: every file in $dir appears in $(basename "$sidebar") ($(printf '%s\n' "$files" | wc -l | tr -d ' ') entries)"
  else
    while IFS= read -r m; do
      [ -n "$m" ] && fail "$label: $dir/$m.md is not in $(basename "$sidebar") — it will not appear on the site"
    done <<< "$missing"
  fi

  if [ -z "$orphans" ]; then
    pass "$label: no sidebar entry points at a missing file"
  else
    while IFS= read -r o; do
      [ -n "$o" ] && fail "$label: $(basename "$sidebar") lists '$o' but $dir/$o.md does not exist — the build will break"
    done <<< "$orphans"
  fi
}

echo ""
echo "=== Docs site covers every command and reference ==="
check_coverage "commands" "commands" "website/sidebars-commands.js"
check_coverage "references" "references" "website/sidebars-references.js"

# ---------------------------------------------------------------------------
echo ""
echo "=== Docs site derives versions and counts rather than hardcoding ==="

# Asserting the derivation, not a literal. Asserting a literal here would just
# relocate the stale value into this file.
if grep -q "require('../.claude-plugin/plugin.json')" website/docusaurus.config.js; then
  pass "docusaurus.config.js derives the version from plugin.json"
else
  fail "docusaurus.config.js must derive the version from .claude-plugin/plugin.json"
fi

if grep -q "readdirSync" website/docusaurus.config.js; then
  pass "docusaurus.config.js derives the command count from commands/"
else
  fail "docusaurus.config.js must derive the command count by reading commands/"
fi

if grep -qE '>v1\.[0-9]+\.[0-9]+|^\s*v1\.[0-9]+\.[0-9]+' website/src/pages/index.tsx; then
  fail "website/src/pages/index.tsx hardcodes a version — read siteConfig.customFields.pluginVersion"
else
  pass "index.tsx does not hardcode a version"
fi

if grep -qE '[0-9]+ commands\.' website/src/pages/index.tsx; then
  fail "website/src/pages/index.tsx hardcodes a command count — read siteConfig.customFields.commandCount"
else
  pass "index.tsx does not hardcode a command count"
fi

# ---------------------------------------------------------------------------
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS website coverage error(s)"
  exit 1
fi
echo "PASS: all website coverage checks passed"
