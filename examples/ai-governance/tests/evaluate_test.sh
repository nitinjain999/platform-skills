#!/usr/bin/env bash
# Several tests set policy globals (PROTECTED_PATHS, DENIED_COMMANDS,
# MAX_DIFF_FILES, REQUIRE_DISCLOSURE, POLICY_FILE) that are read by the
# functions sourced from evaluate.sh. shellcheck cannot see through the
# dynamic `source` below, so it reports them as unused.
# shellcheck disable=SC2034
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

# shellcheck source=../evaluate.sh
source "$EVAL" --source-only

# Fail loudly here, once, with a clear message — rather than letting the
# suite die silently and unexplained inside test_load_policy_valid, whose
# unsubshelled `load_policy` call needs yq's exit-2 path to stay reserved
# for the dedicated missing-yq test, not for an environment that's simply
# missing the dependency every other test in this file already assumes.
if ! command -v yq >/dev/null 2>&1; then
  echo "FATAL: yq is required to run this test suite (see references/ai-governance.md)." >&2
  exit 1
fi

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

test_neutral_platform_envelope() {
  # --platform=none is the dry-run renderer behind `check` mode: no vendor
  # envelope, and the short rule code is carried in its own field.
  local saved_platform="$PLATFORM"
  PLATFORM="none"
  local out rc
  out="$(emit_decision "deny" "protected_paths: secrets/** (secrets/x.yaml)" "protected_paths" 2>/dev/null)"
  rc=$?
  assert_eq "neutral deny shape" \
    '{"decision":"deny","rule":"protected_paths","reason":"protected_paths: secrets/** (secrets/x.yaml)"}' \
    "$out"
  assert_eq "neutral deny exit code" "2" "$rc"

  out="$(emit_decision "allow" 2>/dev/null)"
  rc=$?
  assert_eq "neutral allow shape" '{"decision":"allow"}' "$out"
  assert_eq "neutral allow exit code" "0" "$rc"
  PLATFORM="$saved_platform"
}

test_neutral_platform_envelope

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
  out="$(PATH="" load_policy 2>/dev/null)"
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

test_match_governance_asset_hits() {
  # GOVERNANCE_ASSETS is hardcoded, not policy-driven, so it cannot be weakened
  # by editing the policy file it protects.
  assert_eq "governance asset: policy file" ".ai-governance.yaml" \
    "$(match_governance_asset ".ai-governance.yaml")"
  assert_eq "governance asset: evaluator" ".ai-governance/**" \
    "$(match_governance_asset ".ai-governance/evaluate.sh")"
  assert_eq "governance asset: copilot hook" ".github/hooks/**" \
    "$(match_governance_asset ".github/hooks/preToolUse.json")"
  assert_eq "governance asset: merge-time check" ".github/workflows/ai-governance-check.yml" \
    "$(match_governance_asset ".github/workflows/ai-governance-check.yml")"
  assert_eq "governance asset: claude settings" ".claude/settings.json" \
    "$(match_governance_asset ".claude/settings.json")"
}

test_match_governance_asset_miss() {
  if match_governance_asset ".github/workflows/release.yml" >/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL: an ordinary workflow is not a governance asset"
  else
    PASS=$((PASS+1))
  fi
}

test_match_governance_asset_hits
test_match_governance_asset_miss

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

test_reason_string() {
  assert_eq "reason_string joins code and detail" "protected_paths: secrets/**" \
    "$(reason_string "protected_paths" "secrets/**")"
  assert_eq "reason_string omits an empty detail" "policy_load_failed" \
    "$(reason_string "policy_load_failed" "")"
}

test_tier_outcome_mapping() {
  local saved="$ENFORCEMENT"
  ENFORCEMENT="block"
  assert_eq "tier block -> deny" "deny" "$(tier_outcome)"
  ENFORCEMENT="warn"
  assert_eq "tier warn -> would_deny_warn (distinct from audit)" "would_deny_warn" "$(tier_outcome)"
  ENFORCEMENT="audit"
  assert_eq "tier audit -> would_deny" "would_deny" "$(tier_outcome)"
  ENFORCEMENT="not-a-tier"
  assert_eq "unrecognized tier falls back to audit behavior" "would_deny" "$(tier_outcome)"
  ENFORCEMENT="audit"
  assert_eq "force_deny overrides the audit tier" "deny" "$(tier_outcome "self_disable")"
  ENFORCEMENT="$saved"
}

test_is_write_intent() {
  # Read-only tool names never carry write intent.
  if is_write_intent "Read" "false"; then
    FAIL=$((FAIL+1)); echo "FAIL: Read must not be write intent"
  else PASS=$((PASS+1)); fi
  if is_write_intent "grep" "false"; then
    FAIL=$((FAIL+1)); echo "FAIL: grep must not be write intent"
  else PASS=$((PASS+1)); fi
  # Known write tools do.
  if is_write_intent "Edit" "false"; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: Edit must be write intent"; fi
  if is_write_intent "Write" "false"; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: Write must be write intent"; fi
  # An edit payload wins over the tool name (fail-closed).
  if is_write_intent "Read" "true"; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: an edit payload is write intent whatever the tool is called"; fi
  # An unknown tool name fails closed.
  if is_write_intent "SomeFutureTool" "false"; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: unknown tool names must fail closed to write intent"; fi
}

test_is_post_event_casing() {
  local saved="$EVENT"
  EVENT="postToolUse"
  if is_post_event; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: postToolUse (Copilot casing) must be a post event"; fi
  EVENT="PostToolUse"
  if is_post_event; then PASS=$((PASS+1));
  else FAIL=$((FAIL+1)); echo "FAIL: PostToolUse (Claude casing) must be a post event"; fi
  EVENT="preToolUse"
  if is_post_event; then FAIL=$((FAIL+1)); echo "FAIL: preToolUse must not be a post event";
  else PASS=$((PASS+1)); fi
  EVENT=""
  if is_post_event; then FAIL=$((FAIL+1)); echo "FAIL: an unset event must not be a post event";
  else PASS=$((PASS+1)); fi
  EVENT="$saved"
}

test_reason_string
test_tier_outcome_mapping
test_is_write_intent
test_is_post_event_casing

test_decide_block_tier_denies() {
  ENFORCEMENT="block"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"
  cd "$tmp" || return 1
  local out rc
  out="$(decide "true" "protected_paths" "secrets/** (secrets/config.yaml)" "secrets/config.yaml" 2>/dev/null)"
  rc=$?
  cd - >/dev/null || return 1
  assert_eq "block tier: exit 2" "2" "$rc"
  assert_eq "block tier: deny envelope" \
    '{"permissionDecision":"deny","permissionDecisionReason":"protected_paths: secrets/** (secrets/config.yaml)"}' \
    "$out"
  rm -rf "$tmp"
}

test_decide_audit_tier_allows_and_logs() {
  ENFORCEMENT="audit"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"
  cd "$tmp" || return 1
  local out
  out="$(decide "true" "protected_paths" "secrets/** (secrets/config.yaml)" "secrets/config.yaml" 2>/dev/null)"
  local logged outcome_field rule_field
  logged="$(grep -c "would_deny" .ai-governance/audit.log 2>/dev/null || true)"
  outcome_field="$(awk -F'\t' 'NR==1{print $3}' .ai-governance/audit.log 2>/dev/null)"
  rule_field="$(awk -F'\t' 'NR==1{print $4}' .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1
  assert_eq "audit tier: allow envelope" '{"permissionDecision":"allow"}' "$out"
  assert_eq "audit tier: would_deny logged" "1" "$logged"
  assert_eq "audit tier: outcome field is exactly would_deny" "would_deny" "$outcome_field"
  assert_eq "audit tier: rule field is a short stable code" "protected_paths" "$rule_field"
  rm -rf "$tmp"
}

test_decide_force_deny_overrides_tier() {
  # The self-disable guarantee: deny regardless of tier, even under audit.
  ENFORCEMENT="audit"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"
  cd "$tmp" || return 1
  local out rc outcome_field
  out="$(decide "true" "self_disable" ".ai-governance.yaml changed alongside iam/policy.json" \
    ".ai-governance.yaml" "self_disable" 2>/dev/null)"
  rc=$?
  outcome_field="$(awk -F'\t' 'NR==1{print $3}' .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1
  assert_eq "force_deny under audit tier: exit 2" "2" "$rc"
  assert_eq "force_deny under audit tier: real deny logged" "deny" "$outcome_field"
  assert_eq "force_deny under audit tier: deny envelope" "true" \
    "$(echo "$out" | grep -q '"permissionDecision":"deny"' && echo true || echo false)"
  rm -rf "$tmp"
}

test_decide_block_tier_denies
test_decide_audit_tier_allows_and_logs
test_decide_force_deny_overrides_tier

test_hook_mode_copilot_camelcase_edit_deny() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/release.yml"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "copilot camelCase edit denied" \
    '{"permissionDecision":"deny","permissionDecisionReason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}' \
    "$out"
}

test_hook_mode_claude_bash_deny() {
  ENFORCEMENT="block"
  DENIED_COMMANDS=("rm -rf")
  PLATFORM="claude"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "claude bash denied" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"denied_commands: rm -rf"}}' \
    "$out"
}

test_hook_mode_allow_when_no_match() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"toolName":"edit","toolArgs":{"path":"src/app.py"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
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

test_hook_mode_read_of_protected_path_allows() {
  # protected_paths gates writes, not reads. Denying a Read makes `block` tier
  # unusable in practice, and the predictable response is to remove the hook.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out log_written
  out="$(echo '{"toolName":"read","toolArgs":{"path":".github/workflows/release.yml"}}' | run_hook_mode 2>/dev/null)"
  log_written="$([[ -e .ai-governance/audit.log ]] && echo true || echo false)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "copilot read of a protected path is allowed under block tier" \
    '{"permissionDecision":"allow"}' "$out"
  assert_eq "an allowed read writes no audit line" "false" "$log_written"
}

test_hook_mode_claude_read_tool_allows() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="claude"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"tool_name":"Read","tool_input":{"file_path":".github/workflows/release.yml"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "claude Read of a protected path is allowed under block tier" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}' "$out"
}

test_hook_mode_write_of_protected_path_denies() {
  # Same path, same tier, write intent -> still denied.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="claude"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"tool_name":"Write","tool_input":{"file_path":".github/workflows/release.yml","content":"x"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "claude Write of the same protected path is denied" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}}' \
    "$out"
}

test_hook_mode_edit_payload_beats_unknown_tool_name() {
  # new_string/old_string present -> write intent even for an unrecognized tool.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"tool_name":"SomeFuturePatcher","tool_input":{"file_path":".github/workflows/release.yml","old_string":"a","new_string":"b"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "an edit payload is denied regardless of tool name" \
    '{"permissionDecision":"deny","permissionDecisionReason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}' \
    "$out"
}

test_hook_mode_denied_command_unaffected_by_write_intent_gate() {
  # denied_commands is gated on `command`, not on the write-intent check, so a
  # tool named "read" that is actually running a shell command is still caught.
  ENFORCEMENT="block"
  PROTECTED_PATHS=()
  DENIED_COMMANDS=("rm -rf")
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(echo '{"toolName":"read","toolArgs":{"command":"rm -rf /tmp/x"}}' | run_hook_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "denied_commands still fires for a read-named command tool" \
    '{"permissionDecision":"deny","permissionDecisionReason":"denied_commands: rm -rf"}' \
    "$out"
}

test_post_event_logs_completion_only() {
  # postToolUse must not re-run the decision logic — that would duplicate the
  # audit line preToolUse already wrote for the same call.
  ENFORCEMENT="audit"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=("rm -rf")
  PLATFORM="claude"
  local saved_event="$EVENT" saved_mode="$MODE"
  EVENT="PostToolUse"; MODE="hook"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc log
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | run_post_hook_mode 2>/dev/null)"
  rc=$?
  log="$(cat .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  EVENT="$saved_event"; MODE="$saved_mode"
  assert_eq "post event emits no decision body" "" "$out"
  assert_eq "post event exits 0" "0" "$rc"
  assert_eq "post event logs exactly one line" "1" "$(printf '%s\n' "$log" | grep -c . || true)"
  assert_eq "post event outcome field is completed" "completed" \
    "$(printf '%s\n' "$log" | awk -F'\t' 'NR==1{print $3}')"
  assert_eq "post event rule field is post_tool_use" "post_tool_use" \
    "$(printf '%s\n' "$log" | awk -F'\t' 'NR==1{print $4}')"
  assert_eq "post event does not re-evaluate rules" "false" \
    "$(printf '%s\n' "$log" | grep -q "would_deny" && echo true || echo false)"
}

test_check_mode_hook_writes_no_audit_log() {
  # `check` mode (--platform=none) renders a neutral decision and must leave
  # the real audit trail untouched.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  DENIED_COMMANDS=()
  local saved_mode="$MODE"
  PLATFORM="none"; MODE="hook"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc log_written
  out="$(echo '{"toolName":"edit","toolArgs":{"path":".github/workflows/release.yml"}}' | run_hook_mode 2>/dev/null)"
  rc=$?
  log_written="$([[ -e .ai-governance/audit.log ]] && echo true || echo false)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  PLATFORM="copilot"; MODE="$saved_mode"
  assert_eq "check mode renders a neutral decision" \
    '{"decision":"deny","rule":"protected_paths","reason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}' \
    "$out"
  assert_eq "check mode deny exits 2" "2" "$rc"
  assert_eq "check mode writes no audit log" "false" "$log_written"
}

test_hook_mode_copilot_camelcase_edit_deny
test_hook_mode_claude_bash_deny
test_hook_mode_allow_when_no_match
test_hook_mode_no_path_no_command
test_hook_mode_read_of_protected_path_allows
test_hook_mode_claude_read_tool_allows
test_hook_mode_write_of_protected_path_denies
test_hook_mode_edit_payload_beats_unknown_tool_name
test_hook_mode_denied_command_unaffected_by_write_intent_gate
test_post_event_logs_completion_only
test_check_mode_hook_writes_no_audit_log
test_source_only_suppresses_main_with_other_flags

# Every ci-mode test runs from a scratch cwd: AUDIT_LOG is a relative path, so
# running these in the repo root would leave a real .ai-governance/audit.log
# behind — and this suite is a CI gate (tests/handbook-consistency.sh).
test_ci_mode_protected_path_denies() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc
  out="$(printf '%s\0' ".github/workflows/release.yml" "src/app.py" | run_ci_mode 2>/dev/null)"
  rc=$?
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "ci mode protected path: exit 2" "2" "$rc"
  assert_eq "ci mode protected path: deny reason" "true" \
    "$(echo "$out" | grep -q "protected_paths" && echo true || echo false)"
}

test_ci_mode_max_diff_files() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=()
  MAX_DIFF_FILES=2
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc
  out="$(printf '%s\0' "a.txt" "b.txt" "c.txt" | run_ci_mode 2>/dev/null)"
  rc=$?
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "ci mode max_diff_files: exit 2" "2" "$rc"
  assert_eq "ci mode max_diff_files: reason" "true" \
    "$(echo "$out" | grep -q "max_diff_files" && echo true || echo false)"
}

test_ci_mode_allow_when_clean() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=25
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(printf '%s\0' "src/app.py" | run_ci_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
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
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(printf '%s\0%s\0%s\0' "a.txt" "b.txt" "c.txt" | run_ci_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "aggregate max_diff_files fires from one invocation" "true" \
    "$(echo "$out" | grep -q "max_diff_files: 3 > 2" && echo true || echo false)"
}

test_ci_mode_aggregate_not_per_file

test_ci_mode_reports_every_violation() {
  # The regression this pins: decide() always exits, so calling it inside the
  # per-file loop stopped at the first protected-path hit and never evaluated
  # max_diff_files or require_disclosure at all.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=2
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc log
  out="$(printf '%s\0' ".github/workflows/a.yml" ".github/workflows/b.yml" "src/app.py" \
    | run_ci_mode 2>/dev/null)"
  rc=$?
  log="$(cat .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "multi-violation: exit 2" "2" "$rc"
  assert_eq "multi-violation: first protected path reported" "true" \
    "$(echo "$out" | grep -q "a.yml" && echo true || echo false)"
  assert_eq "multi-violation: second protected path also reported" "true" \
    "$(echo "$out" | grep -q "b.yml" && echo true || echo false)"
  assert_eq "multi-violation: max_diff_files evaluated despite earlier hits" "true" \
    "$(echo "$out" | grep -q "max_diff_files: 3 > 2" && echo true || echo false)"
  assert_eq "multi-violation: one audit line per violation" "3" \
    "$(printf '%s\n' "$log" | grep -c . || true)"
}

test_ci_mode_reports_every_violation

test_ci_mode_self_disable_denies_under_audit() {
  # Spec guarantee: a governance asset changed alongside another protected path
  # denies regardless of tier, so a team onboarding under `audit` cannot have
  # its own governance config quietly switched off.
  ENFORCEMENT="audit"
  PROTECTED_PATHS=(".github/workflows/**" ".ai-governance.yaml")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc log
  out="$(printf '%s\0' ".ai-governance.yaml" ".github/workflows/release.yml" | run_ci_mode 2>/dev/null)"
  rc=$?
  log="$(cat .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "self-disable under audit tier: exit 2" "2" "$rc"
  assert_eq "self-disable under audit tier: self_disable in reason" "true" \
    "$(echo "$out" | grep -q "self_disable" && echo true || echo false)"
  assert_eq "self-disable under audit tier: logs a real deny, never would_deny" "false" \
    "$(printf '%s\n' "$log" | grep -q "would_deny" && echo true || echo false)"
}

test_ci_mode_governance_asset_alone_follows_tier() {
  # A governance asset on its own is an ordinary protected_paths hit and still
  # obeys the tier — only the combination triggers the override.
  ENFORCEMENT="audit"
  PROTECTED_PATHS=(".ai-governance.yaml")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out log
  out="$(printf '%s\0' ".ai-governance.yaml" | run_ci_mode 2>/dev/null)"
  log="$(cat .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "governance asset alone under audit is allowed" \
    '{"permissionDecision":"allow"}' "$out"
  assert_eq "governance asset alone logs would_deny" "would_deny" \
    "$(printf '%s\n' "$log" | awk -F'\t' 'NR==1{print $3}')"
  assert_eq "governance asset alone does not fire self_disable" "false" \
    "$(printf '%s\n' "$log" | grep -q "self_disable" && echo true || echo false)"
}

test_ci_mode_self_disable_denies_under_audit
test_ci_mode_governance_asset_alone_follows_tier

test_ci_mode_warn_tier_is_distinct_from_audit() {
  # warn must be distinguishable in the log so the CI workflow knows to post a
  # PR comment; audit stays silent.
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local warn_out warn_rc warn_field audit_field
  ENFORCEMENT="warn"
  warn_out="$(printf '%s\0' ".github/workflows/release.yml" | run_ci_mode 2>/dev/null)"
  warn_rc=$?
  warn_field="$(awk -F'\t' 'NR==1{print $3}' .ai-governance/audit.log 2>/dev/null)"
  rm -rf .ai-governance
  ENFORCEMENT="audit"
  printf '%s\0' ".github/workflows/release.yml" | run_ci_mode >/dev/null 2>&1
  audit_field="$(awk -F'\t' 'NR==1{print $3}' .ai-governance/audit.log 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "warn tier allows the PR through" '{"permissionDecision":"allow"}' "$warn_out"
  assert_eq "warn tier exits 0" "0" "$warn_rc"
  assert_eq "warn tier outcome is would_deny_warn" "would_deny_warn" "$warn_field"
  assert_eq "audit tier outcome is would_deny" "would_deny" "$audit_field"
}

test_ci_mode_warn_tier_is_distinct_from_audit

test_ci_mode_dry_run_writes_no_audit_log() {
  # `check --diff` uses --mode=ci --platform=none: neutral output, no audit line.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=0
  REQUIRE_DISCLOSURE="false"
  local saved_mode="$MODE"
  PLATFORM="none"; MODE="ci"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rc log_written
  out="$(printf '%s\0' ".github/workflows/release.yml" | run_ci_mode 2>/dev/null)"
  rc=$?
  log_written="$([[ -e .ai-governance/audit.log ]] && echo true || echo false)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  PLATFORM="copilot"; MODE="$saved_mode"
  assert_eq "ci dry run renders a neutral decision" \
    '{"decision":"deny","rule":"protected_paths","reason":"protected_paths: .github/workflows/** (.github/workflows/release.yml)"}' \
    "$out"
  assert_eq "ci dry run deny exits 2" "2" "$rc"
  assert_eq "ci dry run writes no audit log" "false" "$log_written"
}

test_ci_mode_dry_run_multiple_rule_codes() {
  # The neutral `rule` field carries every distinct code that fired, deduped.
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=2
  REQUIRE_DISCLOSURE="false"
  local saved_mode="$MODE"
  PLATFORM="none"; MODE="ci"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out rule
  out="$(printf '%s\0' ".github/workflows/a.yml" ".github/workflows/b.yml" "src/app.py" \
    | run_ci_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  PLATFORM="copilot"; MODE="$saved_mode"
  rule="$(printf '%s' "$out" | sed -n 's/.*"rule":"\([^"]*\)".*/\1/p')"
  assert_eq "neutral rule field dedupes and joins codes" "protected_paths,max_diff_files" "$rule"
}

test_ci_mode_dry_run_writes_no_audit_log
test_ci_mode_dry_run_multiple_rule_codes

test_ci_mode_empty_stdin() {
  ENFORCEMENT="block"
  PROTECTED_PATHS=(".github/workflows/**")
  MAX_DIFF_FILES=25
  REQUIRE_DISCLOSURE="false"
  PLATFORM="copilot"
  local tmp; tmp="$(mktemp -d)"; cd "$tmp" || return 1
  local out
  out="$(printf "" | run_ci_mode 2>/dev/null)"
  cd - >/dev/null || return 1; rm -rf "$tmp"
  assert_eq "ci mode allows on empty stdin (no changed files)" '{"permissionDecision":"allow"}' "$out"
}

test_ci_mode_empty_stdin

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
