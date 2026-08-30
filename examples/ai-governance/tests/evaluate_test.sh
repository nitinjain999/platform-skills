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

test_match_protected_path_empty_array() {
  PROTECTED_PATHS=()
  if match_protected_path "src/app.py" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: empty PROTECTED_PATHS should not match"
  else
    PASS=$((PASS+1))
  fi
}

test_match_protected_path_empty_array

test_match_denied_command_hit() {
  DENIED_COMMANDS=("terraform apply" "rm -rf")
  local matched
  matched="$(match_denied_command "terraform apply -auto-approve")"
  assert_eq "terraform apply prefix matches" "terraform apply" "$matched"
}

test_match_denied_command_different_flag_position() {
  DENIED_COMMANDS=("terraform apply")
  if match_denied_command "terraform -chdir=x apply" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: terraform -chdir=x apply must NOT match (documented non-coverage)"
  else
    PASS=$((PASS+1))
  fi
}

test_match_denied_command_split_flags_bypass() {
  DENIED_COMMANDS=("rm -rf")
  if match_denied_command "rm -r -f" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: rm -r -f must NOT match rm -rf (documented non-coverage — different tokens)"
  else
    PASS=$((PASS+1))
  fi
}

test_match_denied_command_wrapper_name_bypass() {
  DENIED_COMMANDS=("terraform apply")
  if match_denied_command "terraform_apply_wrapper" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: terraform_apply_wrapper must NOT match (different token entirely)"
  else
    PASS=$((PASS+1))
  fi
}

test_match_denied_command_hit
test_match_denied_command_different_flag_position
test_match_denied_command_split_flags_bypass
test_match_denied_command_wrapper_name_bypass

test_match_denied_command_empty_array() {
  DENIED_COMMANDS=()
  if match_denied_command "rm -rf" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: empty DENIED_COMMANDS should not match"
  else
    PASS=$((PASS+1))
  fi
}

test_match_denied_command_empty_array

test_decide_block_tier_denies() {
  ENFORCEMENT="block"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"
  cd "$tmp"
  local out rc
  out="$(decide "true" "protected_paths: secrets/** test" "secrets/config.yaml" 2>/dev/null)"
  rc=$?
  cd - >/dev/null
  assert_eq "block tier: exit 2" "2" "$rc"
  assert_eq "block tier: deny envelope" \
    '{"permissionDecision":"deny","permissionDecisionReason":"protected_paths: secrets/** test"}' \
    "$out"
  rm -rf "$tmp"
}

test_decide_audit_tier_allows_and_logs() {
  ENFORCEMENT="audit"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"
  cd "$tmp"
  local out
  out="$(decide "true" "protected_paths: secrets/** test" "secrets/config.yaml" 2>/dev/null)"
  local logged
  logged="$(cat .ai-governance/audit.log 2>/dev/null | grep -c "would_deny" || true)"
  cd - >/dev/null
  assert_eq "audit tier: allow envelope" '{"permissionDecision":"allow"}' "$out"
  assert_eq "audit tier: would_deny logged" "1" "$logged"
  rm -rf "$tmp"
}

test_decide_block_tier_denies
test_decide_audit_tier_allows_and_logs

test_hook_mode_copilot_camelcase_edit_deny() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  local tmp; tmp="$(mktemp -d)"; cd "$tmp"
  local out
  out="$(echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/release.yml"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null; rm -rf "$tmp"
  assert_eq "copilot camelCase edit denied" \
    '{"permissionDecision":"deny","permissionDecisionReason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}' \
    "$out"
}

test_hook_mode_claude_bash_deny() {
  ENFORCEMENT="block"
  DENIED_COMMANDS=("rm -rf")
  PLATFORM="claude"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp"
  local out
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null; rm -rf "$tmp"
  assert_eq "claude bash denied" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"rm -rf"}}' \
    "$out"
}

test_hook_mode_allow_when_no_match() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp"
  local out
  out="$(echo '{"toolName":"edit","toolArgs":{"path":"src/app.py"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null; rm -rf "$tmp"
  assert_eq "unrelated edit allowed" '{"permissionDecision":"allow"}' "$out"
}

test_hook_mode_no_path_no_command() {
  PLATFORM="copilot"
  local out
  out="$(echo '{"toolName":"read"}' | run_hook_mode 2>/dev/null)"
  assert_eq "no path/command falls through to allow" '{"permissionDecision":"allow"}' "$out"
}

test_source_only_suppresses_main_with_other_flags() {
  local out
  out="$(echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/x.yml"}}' | \
    bash "$EVAL" --source-only --mode=hook --platform=copilot 2>/dev/null)"
  assert_eq "source-only suppresses main even with mode/platform present" "" "$out"
}

test_hook_mode_copilot_camelcase_edit_deny
test_hook_mode_claude_bash_deny
test_hook_mode_allow_when_no_match
test_hook_mode_no_path_no_command
test_source_only_suppresses_main_with_other_flags

test_ci_mode_protected_path_denies() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  local out rc
  out="$(printf '%s\0' ".github/workflows/release.yml" "src/app.py" | run_ci_mode 2>/dev/null)"
  rc=$?
  assert_eq "ci mode protected path: exit 2" "2" "$rc"
  assert_eq "ci mode protected path: deny reason" "true" \
    "$(echo "$out" | grep -q "protected_paths" && echo true || echo false)"
}

test_ci_mode_max_diff_files() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=()
  MAX_DIFF_FILES=2
  REQUIRE_DISCLOSURE="false"
  local out rc paths=""
  paths="a.txt\0b.txt\0c.txt\0"
  out="$(printf "$paths" | run_ci_mode 2>/dev/null)"
  rc=$?
  assert_eq "ci mode max_diff_files: exit 2" "2" "$rc"
  assert_eq "ci mode max_diff_files: reason" "true" \
    "$(echo "$out" | grep -q "max_diff_files" && echo true || echo false)"
}

test_ci_mode_allow_when_clean() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=25
  REQUIRE_DISCLOSURE="false"
  local out
  out="$(printf '%s\0' "src/app.py" | run_ci_mode 2>/dev/null)"
  assert_eq "ci mode allow when nothing matches" '{"permissionDecision":"allow"}' "$out"
}

test_ci_mode_protected_path_denies
test_ci_mode_max_diff_files
test_ci_mode_allow_when_clean

test_ci_mode_aggregate_not_per_file() {
  # A single invocation with 3 files and max_diff_files=2 must deny on the
  # aggregate count even though ci_mode is called exactly once, not 3 times.
  ENFORCEMENT="block"
  PROTECTED_PATHS=()
  MAX_DIFF_FILES=2
  REQUIRE_DISCLOSURE="false"
  local call_count=0
  # Sanity: confirm run_ci_mode reads the whole stdin stream in one call
  local out
  out="$(printf '%s\0%s\0%s\0' "a.txt" "b.txt" "c.txt" | run_ci_mode 2>/dev/null)"
  assert_eq "aggregate max_diff_files fires from one invocation" "true" \
    "$(echo "$out" | grep -q "max_diff_files: 3 > 2" && echo true || echo false)"
}

test_ci_mode_aggregate_not_per_file

test_ci_mode_empty_stdin() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=25
  REQUIRE_DISCLOSURE="false"
  local out
  out="$(printf "" | run_ci_mode 2>/dev/null)"
  assert_eq "ci mode allows on empty stdin (no changed files)" '{"permissionDecision":"allow"}' "$out"
}

test_ci_mode_empty_stdin

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
