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
#
# Checking only that a `require` of the manifest exists is too weak: someone
# could keep the require and still write `pluginVersion: '1.41.0'`, passing the
# check while reintroducing the drift. So assert the ASSIGNMENTS reference the
# loaded values, and separately reject a quoted literal in either field.

if grep -qE "pluginVersion:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\.version" website/docusaurus.config.js; then
  pass "docusaurus.config.js assigns pluginVersion from the loaded manifest"
else
  fail "docusaurus.config.js must assign pluginVersion from the required plugin.json, not a literal"
fi

if grep -qE "pluginVersion:[[:space:]]*['\"]" website/docusaurus.config.js; then
  fail "docusaurus.config.js assigns pluginVersion a quoted literal — derive it from plugin.json"
else
  pass "pluginVersion is not a quoted literal"
fi

if grep -qE "commandCount:[[:space:]]*['\"]?[0-9]" website/docusaurus.config.js; then
  fail "docusaurus.config.js assigns commandCount a literal — derive it by reading commands/"
else
  pass "commandCount is not a literal"
fi

if grep -q "readdirSync" website/docusaurus.config.js; then
  pass "docusaurus.config.js derives the command count by reading commands/"
else
  fail "docusaurus.config.js must derive the command count by reading commands/"
fi

# Strongest available check: evaluate the config and compare against the real
# sources. Requires website/node_modules, since the config pulls in
# prism-react-renderer, so it is a bonus locally rather than the primary gate —
# the static assertions above are what run everywhere.
if command -v node >/dev/null 2>&1 && [ -d website/node_modules ]; then
  want_version="$(node -e "process.stdout.write(require('./.claude-plugin/plugin.json').version)")"
  want_count="$(find commands -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  got="$(cd website && node -e "
    const c = require('./docusaurus.config.js');
    process.stdout.write(c.customFields.pluginVersion + '|' + c.customFields.commandCount);
  " 2>/dev/null)" || got="EVAL_FAILED"
  if [ "$got" = "${want_version}|${want_count}" ]; then
    pass "evaluated config matches the sources exactly (version ${want_version}, count ${want_count})"
  else
    fail "evaluated config gave '${got}', expected '${want_version}|${want_count}'"
  fi
else
  echo "  SKIP: evaluated-config check needs node and website/node_modules (static checks above still ran)"
fi

# POSIX character classes throughout: \s is a GNU/PCRE extension, not POSIX ERE,
# so a grep without that extension would silently fail to match an indented
# literal and the guard would pass while the regression shipped.
if grep -qE '>v1\.[0-9]+\.[0-9]+|^[[:space:]]*v1\.[0-9]+\.[0-9]+' website/src/pages/index.tsx; then
  fail "website/src/pages/index.tsx hardcodes a version — read siteConfig.customFields.pluginVersion"
else
  pass "index.tsx does not hardcode a version"
fi

if grep -qE '[0-9]+[[:space:]]+commands\.' website/src/pages/index.tsx; then
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
