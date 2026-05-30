#!/usr/bin/env bash
# Verifies editor and agent integration metadata stays aligned with the release.
# Run from the repository root: bash tests/editor-version-consistency.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

PLUGIN_VERSION="$(jq -r '.version' .claude-plugin/plugin.json)"
COMMAND_COUNT="$(find commands -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"

echo ""
echo "=== Editor and agent release metadata ==="
echo "  INFO: plugin version: $PLUGIN_VERSION"
echo "  INFO: command count: $COMMAND_COUNT"

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

if grep -q "agents/openai.yaml" README.md INSTALLATION.md 2>/dev/null; then
  pass "README/INSTALLATION document Codex agents/openai.yaml metadata"
else
  fail "README or INSTALLATION should document agents/openai.yaml for Codex"
fi

echo ""
echo "=== Cursor rules ==="

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

for cursor_rule in .cursorrules .cursor/rules/platform-skills.mdc .cursor/rules/kubernetes.mdc .cursor/rules/terraform.mdc .cursor/rules/keda.mdc; do
  if [ -f "$cursor_rule" ]; then
    pass "$cursor_rule exists"
  else
    fail "$cursor_rule missing"
  fi
done

echo ""
echo "=== Copilot instructions ==="

if [ -f .github/copilot-instructions.md ]; then
  pass ".github/copilot-instructions.md exists"
else
  fail ".github/copilot-instructions.md missing"
fi

if grep -q "^# Version: ${PLUGIN_VERSION}$" .github/copilot-instructions.md 2>/dev/null; then
  pass ".github/copilot-instructions.md version matches $PLUGIN_VERSION"
else
  fail ".github/copilot-instructions.md version does not match $PLUGIN_VERSION"
fi

if grep -q "install.sh --copilot" .github/copilot-instructions.md 2>/dev/null; then
  pass ".github/copilot-instructions.md documents install.sh --copilot"
else
  fail ".github/copilot-instructions.md should document install.sh --copilot"
fi

echo ""
echo "=== Public workflow counts ==="

if grep -q "Commands-${COMMAND_COUNT}" README.md 2>/dev/null; then
  pass "README command badge matches ${COMMAND_COUNT}"
else
  fail "README command badge should use Commands-${COMMAND_COUNT}"
fi

if grep -q " ${COMMAND_COUNT} command workflows" EDITOR_INTEGRATIONS.md 2>/dev/null; then
  pass "EDITOR_INTEGRATIONS.md command workflow count matches ${COMMAND_COUNT}"
else
  fail "EDITOR_INTEGRATIONS.md command workflow count should be ${COMMAND_COUNT}"
fi

if grep -q "All ${COMMAND_COUNT} command workflows" GETTING_STARTED.md 2>/dev/null; then
  pass "GETTING_STARTED.md command workflow count matches ${COMMAND_COUNT}"
else
  fail "GETTING_STARTED.md command workflow count should be ${COMMAND_COUNT}"
fi

if grep -q "${COMMAND_COUNT} slash-command workflows" .claude-plugin/marketplace.json 2>/dev/null; then
  pass "marketplace.json command workflow count matches ${COMMAND_COUNT}"
else
  fail "marketplace.json command workflow count should be ${COMMAND_COUNT}"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "FAIL: $ERRORS editor/version consistency error(s)"
  exit 1
fi

echo "PASS: editor and agent version consistency checks passed"
