#!/usr/bin/env bash
# tests/guardrails-plugin.sh — the platform-guardrails plugin stays correct.
#
# - Its scripts are byte-identical to the canonical copies in examples/, so a
#   fix to the example ships in the plugin (and the reverse is caught).
# - Every hook command points at a script that exists and quotes
#   ${CLAUDE_PLUGIN_ROOT}, so a path with spaces stays one word.
# - The governance hook is opt-in per project: with no .ai-governance.yaml it
#   allows silently; with one it enforces (a protected-path write is denied).
#
# Run from the repository root: bash tests/guardrails-plugin.sh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
G=plugins/platform-guardrails
ERRORS=0
pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

echo "=== Scripts match their canonical example copies ==="
while read -r plugin_copy source; do
  if cmp -s "$G/scripts/$plugin_copy" "$source"; then
    pass "$plugin_copy == $source"
  else
    fail "$G/scripts/$plugin_copy differs from $source (copy the fix across)"
  fi
done <<'MAP'
self-improve-hook.sh examples/agent-self-improve/scripts/self-improve-hook.sh
learnings.sh examples/agent-self-improve/scripts/learnings.sh
ai-governance-evaluate.sh examples/ai-governance/evaluate.sh
MAP
if cmp -s agents/platform-bulk-reader.md examples/token-optimizer/claude/platform-bulk-reader.md; then
  pass "agents/platform-bulk-reader.md == examples/token-optimizer/claude/platform-bulk-reader.md"
else
  fail "agents/platform-bulk-reader.md differs from the token-optimizer example"
fi

echo "=== Hook commands ==="
while IFS= read -r cmd; do
  script="$(printf '%s' "$cmd" | sed -n 's|.*"\${CLAUDE_PLUGIN_ROOT}/\(scripts/[A-Za-z0-9._-]*\)".*|\1|p')"
  if [ -z "$script" ]; then
    fail "hook command does not use a quoted \"\${CLAUDE_PLUGIN_ROOT}/scripts/...\" path: $cmd"
  elif [ -f "$G/$script" ]; then
    pass "hook runs $script"
  else
    fail "hook runs $script, which does not exist"
  fi
done < <(jq -r '.hooks[][].hooks[].command' "$G/hooks/hooks.json")
for ev in SessionStart SessionEnd PostToolUseFailure PreCompact PreToolUse PostToolUse; do
  if jq -e --arg e "$ev" '.hooks[$e]' "$G/hooks/hooks.json" >/dev/null; then pass "$ev wired"; else fail "$ev not wired"; fi
done

echo "=== Governance gate is opt-in per project ==="
if ! command -v jq >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1; then
  fail "jq and yq are required for the governance behaviour checks"
else
  proj="$(mktemp -d)"; trap 'rm -rf "$proj"' EXIT
  payload='{"tool_name":"Write","tool_input":{"file_path":".github/workflows/deploy.yml","content":"x"}}'
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$ROOT_DIR/$G" bash "$G/scripts/ai-governance-hook.sh" --event=PreToolUse)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    pass "no .ai-governance.yaml: tool call allowed, no output"
  else
    fail "no .ai-governance.yaml should allow silently (rc=$rc, out=$out)"
  fi
  # The example policy ships in audit mode (log, allow); enforce it for this check.
  cp examples/ai-governance/ai-governance.yaml "$proj/.ai-governance.yaml"
  yq -i '.enforcement = "block"' "$proj/.ai-governance.yaml"
  out="$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_ROOT="$ROOT_DIR/$G" bash "$G/scripts/ai-governance-hook.sh" --event=PreToolUse 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    pass "with .ai-governance.yaml: write to .github/workflows/ denied (exit 2)"
  else
    fail "with .ai-governance.yaml a protected-path write must be denied (rc=$rc, out=$out)"
  fi
fi

echo "=== Released together with platform-skills ==="
main_v="$(jq -r .version .claude-plugin/plugin.json)"
g_v="$(jq -r .version "$G/.claude-plugin/plugin.json")"
m_v="$(jq -r '.plugins[] | select(.name == "platform-guardrails") | .version' .claude-plugin/marketplace.json)"
if [ "$g_v" = "$main_v" ] && [ "$m_v" = "$main_v" ]; then
  pass "platform-guardrails version $g_v matches platform-skills"
else
  fail "versions differ: platform-skills $main_v, guardrails plugin.json $g_v, marketplace entry $m_v"
fi
if [ "$(jq -r '.plugins[] | select(.name == "platform-guardrails") | .source.path' .claude-plugin/marketplace.json)" = "$G" ]; then
  pass "marketplace entry points at $G"
else
  fail "marketplace.json has no platform-guardrails entry with source.path $G"
fi
g_sha="$(jq -r '.plugins[] | select(.name == "platform-guardrails") | .source.sha // ""' .claude-plugin/marketplace.json)"
if printf '%s' "$g_sha" | grep -qE '^[0-9a-f]{40}$'; then
  pass "marketplace entry is pinned to $g_sha"
else
  fail "platform-guardrails marketplace entry has no source.sha: an enforcing-hooks plugin would ship whatever main holds"
fi

echo "=== Marketplace pin gate rejects unpinned entries ==="
# The gate must fail closed on every way an entry can be unpinned; a skip here
# is how platform-guardrails shipped in 1.44.0 with no sha.
mp="$(mktemp -d)"
pin_case() {  # pin_case <label> <expected rc> <source json>
  printf '{"name":"t","owner":{"name":"t"},"plugins":[{"name":"a","source":%s}]}\n' "$3" > "$mp/m.json"
  local rc=0
  bash tests/marketplace-pins.sh --file "$mp/m.json" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$2" ]; then pass "pin gate: $1 → exit $rc"; else fail "pin gate: $1 → exit $rc, want $2"; fi
}
pin_case "git-subdir with ref and no sha" 1 '{"source":"git-subdir","url":"https://example.com/r.git","path":"p","ref":"main"}'
pin_case "relative path source" 1 '"./plugins/a"'
pin_case "short sha" 1 '{"source":"url","url":"https://example.com/r.git","sha":"7ff3050"}'
pin_case "uppercase sha" 1 '{"source":"url","url":"https://example.com/r.git","sha":"7FF3050303B66B38847A21E01A0844375F4483E6"}'
pin_case "full lowercase sha" 0 '{"source":"url","url":"https://example.com/r.git","sha":"7ff3050303b66b38847a21e01a0844375f4483e6"}'
rm -rf "$mp"

echo ""
if [ "$ERRORS" -gt 0 ]; then echo "FAIL: $ERRORS guardrails plugin error(s)"; exit 1; fi
echo "All guardrails plugin checks passed"
