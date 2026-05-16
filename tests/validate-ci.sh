#!/usr/bin/env bash
# CI quality gates: JSON syntax, YAML syntax, shell script lint, stale versions.
# Run from the repository root: bash tests/validate-ci.sh
# Requires: bash, jq. shellcheck/yamllint used when available.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# ---------------------------------------------------------------------------
echo ""
echo "=== JSON syntax ==="

while IFS= read -r f; do
  if jq empty "$f" >/dev/null 2>&1; then
    pass "$f is valid JSON"
  else
    fail "$f is invalid JSON"
  fi
done < <(find . -name "*.json" \
  ! -path "./.git/*" \
  ! -path "./node_modules/*" \
  | sort)

# ---------------------------------------------------------------------------
echo ""
echo "=== YAML syntax ==="

if command -v yamllint >/dev/null 2>&1; then
  while IFS= read -r f; do
    # Skip template files that intentionally contain placeholder values
    if grep -q "YOUR_\|PLACEHOLDER\|<REPLACE" "$f" 2>/dev/null; then
      echo "  INFO: skipping template file $f"
      continue
    fi
    if yamllint -d "{extends: relaxed, rules: {line-length: {max: 200}}}" "$f" >/dev/null 2>&1; then
      pass "$f is valid YAML"
    else
      fail "$f has YAML issues — run: yamllint $f"
    fi
  done < <(find . \( -name "*.yaml" -o -name "*.yml" \) \
    ! -path "./.git/*" \
    ! -path "./node_modules/*" \
    ! -path "*/templates/*" \
    | sort)
else
  echo "  INFO: yamllint not found — skipping YAML lint (install: pip install yamllint)"
  # Fallback: check YAML files parse with python if available and PyYAML is installed
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    while IFS= read -r f; do
      if grep -q "YOUR_\|PLACEHOLDER\|<REPLACE" "$f" 2>/dev/null; then
        continue
      fi
      if python3 -c "import yaml; yaml.safe_load(open('$f'))" >/dev/null 2>&1; then
        pass "$f parses as valid YAML"
      else
        fail "$f is invalid YAML"
      fi
    done < <(find . \( -name "*.yaml" -o -name "*.yml" \) \
      ! -path "./.git/*" \
      ! -path "./node_modules/*" \
      ! -path "*/templates/*" \
      | sort)
  else
    echo "  INFO: python3/PyYAML not found — YAML validation skipped entirely"
  fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Shell script lint ==="

if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r script; do
    if shellcheck --severity=warning "$script" >/dev/null 2>&1; then
      pass "shellcheck: $script"
    else
      fail "shellcheck: $script has warnings — run: shellcheck $script"
    fi
  done < <(find . -name "*.sh" \
    ! -path "./.git/*" \
    ! -path "./node_modules/*" \
    | sort)
else
  echo "  INFO: shellcheck not found — skipping (install: https://www.shellcheck.net)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Stale version strings ==="

PLUGIN_VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"

# copilot-instructions.md must match plugin.json version
COPILOT_VERSION="$(grep '^# Version:' .github/copilot-instructions.md | awk '{print $3}' || true)"
if [ "$COPILOT_VERSION" = "$PLUGIN_VERSION" ]; then
  pass ".github/copilot-instructions.md version matches plugin.json ($PLUGIN_VERSION)"
else
  fail ".github/copilot-instructions.md says Version: $COPILOT_VERSION but plugin.json is $PLUGIN_VERSION"
fi

# INSTALLATION.md verify output must match plugin.json version
if grep -q "platform-skills  v${PLUGIN_VERSION}  enabled" INSTALLATION.md; then
  pass "INSTALLATION.md verify output matches v${PLUGIN_VERSION}"
else
  fail "INSTALLATION.md verify output does not match v${PLUGIN_VERSION} — update the expected claude plugin list output"
fi

# marketplace.json version must match plugin.json
MARKETPLACE_VERSION="$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"
if [ "$MARKETPLACE_VERSION" = "$PLUGIN_VERSION" ]; then
  pass "marketplace.json version matches plugin.json ($PLUGIN_VERSION)"
else
  fail "marketplace.json version $MARKETPLACE_VERSION does not match plugin.json $PLUGIN_VERSION"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Internal Markdown link targets ==="

BROKEN=0
while IFS= read -r md_file; do
  dir="$(dirname "$md_file")"
  # Strip fenced code blocks before extracting links (avoids matching example links inside ```)
  stripped="$(awk '/^```/{in_fence=!in_fence; next} !in_fence' "$md_file")"
  # Extract relative Markdown links: [text](path) — skip anchors, external URLs, and mailto
  while IFS= read -r link; do
    # Skip external links, anchors-only, and template placeholders
    if echo "$link" | grep -qE "^https?://|^mailto:|^#|YOUR_|PLACEHOLDER"; then
      continue
    fi
    # Strip anchor fragment
    target="${link%%#*}"
    [ -z "$target" ] && continue
    # Strip trailing slash for directory link resolution
    target_path="${target%/}"
    # Resolve relative to the markdown file's directory
    resolved="$dir/$target_path"
    if [ ! -e "$resolved" ]; then
      fail "Broken link in $md_file: [$target] → $resolved does not exist"
      BROKEN=$((BROKEN + 1))
    fi
  done < <(echo "$stripped" | grep -oE '\]\([^)]+\)' | sed 's/^](\(.*\))$/\1/')
done < <(find . -name "*.md" \
  ! -path "./.git/*" \
  ! -path "./node_modules/*" \
  ! -path "./skills/*" \
  | sort)

if [ "$BROKEN" -eq 0 ]; then
  pass "No broken internal Markdown links found"
fi

# ---------------------------------------------------------------------------
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS validation error(s)"
  exit 1
fi
echo "PASS: all CI quality gate checks passed"
