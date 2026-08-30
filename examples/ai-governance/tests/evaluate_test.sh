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
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
