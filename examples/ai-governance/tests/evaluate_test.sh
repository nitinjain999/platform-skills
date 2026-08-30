#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL="$SCRIPT_DIR/evaluate.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

source "$EVAL" --source-only

test_copilot_deny_envelope() {
  PLATFORM="copilot"
  local out
  out="$(emit_decision "deny" "test reason" 2>/dev/null)"
  assert_eq "copilot deny envelope" \
    '{"permissionDecision":"deny","permissionDecisionReason":"test reason"}' \
    "$out"
}

test_copilot_deny_envelope

test_claude_deny_envelope() {
  PLATFORM="claude"
  local out
  out="$(emit_decision "deny" "test reason" 2>/dev/null)"
  assert_eq "claude deny envelope" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"test reason"}}' \
    "$out"
}

test_claude_deny_envelope

test_copilot_allow_envelope() {
  PLATFORM="copilot"
  local out exit_code
  out="$(emit_decision "allow" 2>/dev/null)"
  exit_code=$?
  assert_eq "copilot allow envelope" \
    '{"permissionDecision":"allow"}' \
    "$out"
  assert_eq "copilot allow exit code" "0" "$exit_code"
}

test_copilot_allow_envelope

test_claude_allow_envelope() {
  PLATFORM="claude"
  local out exit_code
  out="$(emit_decision "allow" 2>/dev/null)"
  exit_code=$?
  assert_eq "claude allow envelope" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}' \
    "$out"
  assert_eq "claude allow exit code" "0" "$exit_code"
}

test_claude_allow_envelope

test_deny_exit_codes() {
  # Verify deny always exits with code 2
  PLATFORM="copilot"
  local out exit_code
  out="$(emit_decision "deny" "reason" 2>/dev/null)"
  exit_code=$?
  assert_eq "copilot deny exit code" "2" "$exit_code"

  PLATFORM="claude"
  out="$(emit_decision "deny" "reason" 2>/dev/null)"
  exit_code=$?
  assert_eq "claude deny exit code" "2" "$exit_code"
}

test_deny_exit_codes

test_unknown_platform_exit_code() {
  PLATFORM="unknown"
  local out exit_code
  out="$(emit_decision "allow" 2>/dev/null)"
  exit_code=$?
  assert_eq "unknown platform exit code" "1" "$exit_code"
}

test_unknown_platform_exit_code

test_json_string_escapes() {
  # Newline escape
  local out
  out="$(json_string $'hello\nworld')"
  assert_eq "json_string newline escape" \
    '"hello\nworld"' \
    "$out"

  # Tab escape
  out="$(json_string $'hello\tworld')"
  assert_eq "json_string tab escape" \
    '"hello\tworld"' \
    "$out"

  # Carriage return escape
  out="$(json_string $'hello\rworld')"
  assert_eq "json_string carriage return escape" \
    '"hello\rworld"' \
    "$out"

  # Combined with quote and backslash (literal backslash in input)
  out="$(json_string $'a\nb"c\\d')"
  assert_eq "json_string combined escapes" \
    '"a\nb\"c\\d"' \
    "$out"
}

test_json_string_escapes

test_load_policy_missing_yq() {
  PLATFORM="copilot"
  local tmp
  tmp="$(mktemp -d)"
  cat > "$tmp/policy.yaml" << 'YAML'
version: 1
source: local
enforcement: block
protected_paths:
  - "secrets/**"
denied_commands:
  - "rm -rf"
max_diff_files: 25
require_disclosure: true
YAML
  POLICY_FILE="$tmp/policy.yaml"
  local out rc
  out="$(PATH="/usr/bin:/bin" load_policy 2>/dev/null)"
  rc=$?
  assert_eq "missing yq denies, exit 2" "2" "$rc"
  assert_eq "missing yq reason specific" "true" \
    "$(echo "$out" | grep -q "yq not installed" && echo true || echo false)"
  rm -rf "$tmp"
}

test_load_policy_valid() {
  PLATFORM="copilot"
  local tmp
  tmp="$(mktemp -d)"
  cat > "$tmp/policy.yaml" << 'YAML'
version: 1
source: local
enforcement: block
protected_paths:
  - "secrets/**"
denied_commands:
  - "rm -rf"
max_diff_files: 25
require_disclosure: true
YAML
  POLICY_FILE="$tmp/policy.yaml"
  load_policy
  assert_eq "valid policy loads enforcement=block" "block" "$ENFORCEMENT"
  rm -rf "$tmp"
}

test_load_policy_missing_yq
test_load_policy_valid

test_match_protected_path_hit() {
  PROTECTED_PATHS=(".github/workflows/**" ".ai-governance.yaml" ".ai-governance/**")
  local matched
  matched="$(match_protected_path ".github/workflows/release.yml")"
  assert_eq "workflows glob matches" ".github/workflows/**" "$matched"
}

test_match_protected_path_governance_asset() {
  PROTECTED_PATHS=(".ai-governance.yaml" ".ai-governance/**")
  local matched
  matched="$(match_protected_path ".ai-governance/evaluate.sh")"
  assert_eq "governance asset glob matches" ".ai-governance/**" "$matched"
}

test_match_protected_path_miss() {
  PROTECTED_PATHS=(".github/workflows/**")
  if match_protected_path "src/app.py" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: unrelated path should not match"
  else
    PASS=$((PASS+1))
  fi
}

test_match_protected_path_nested() {
  PROTECTED_PATHS=(".ai-governance/**")
  local matched
  matched="$(match_protected_path ".ai-governance/policies/nested/deep/file.yaml")"
  assert_eq "recursive glob matches multiple path segments" ".ai-governance/**" "$matched"
}

test_match_protected_path_hit
test_match_protected_path_governance_asset
test_match_protected_path_miss
test_match_protected_path_nested

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
