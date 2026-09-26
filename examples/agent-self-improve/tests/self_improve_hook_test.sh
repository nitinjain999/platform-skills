#!/usr/bin/env bash
# Behavioural tests for scripts/self-improve-hook.sh and its PowerShell port.
# Every t_* case runs once per implementation in IMPLS; s_* checks run once.
# Each case gets a sandboxed HOME and project dir under a mktemp root, so no
# test ever touches the real ~/.claude.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
CASE=0
IMPL=""
T_HOME=""
T_PROJ=""
BASE=""
TODAY="$(date +%Y-%m-%d)"
STAMP="$(date +%Y%m%d)"

FAIL_JSON='{"session_id":"sess-1","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"false"},"tool_use_id":"toolu_01","error":"Command failed with exit code 1","is_interrupt":false}'

pass() { PASS=$((PASS+1)); }
fail() {
  FAIL=$((FAIL+1))
  echo "FAIL [$IMPL]: $1"
  if [ $# -gt 1 ]; then printf '  %s\n' "${@:2}"; fi
}
assert_eq() { if [ "$2" = "$3" ]; then pass; else fail "$1" "expected: $2" "actual:   $3"; fi; }
assert_contains() { case "$3" in *"$2"*) pass ;; *) fail "$1" "missing: $2" "in: $3" ;; esac; }
assert_not_contains() { case "$3" in *"$2"*) fail "$1" "unexpected: $2" ;; *) pass ;; esac; }
assert_missing() { if [ ! -e "$2" ]; then pass; else fail "$1" "should not exist: $2"; fi; }
file_or_empty() { if [ -f "$1" ]; then cat "$1"; fi; }
line_count() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# fresh <global|local|both|none> — new sandboxed HOME and project dir.
# BASE is where the hook should write: global wins when both exist.
fresh() {
  CASE=$((CASE+1))
  T_HOME="$TMP/$IMPL-$CASE/home"
  T_PROJ="$TMP/$IMPL-$CASE/proj"
  mkdir -p "$T_HOME" "$T_PROJ"
  BASE=""
  case "$1" in
    global|both) mkdir -p "$T_HOME/.claude/.learnings" "$T_HOME/.claude/memory"; BASE="$T_HOME/.claude" ;;
  esac
  case "$1" in
    local|both) mkdir -p "$T_PROJ/.learnings" "$T_PROJ/memory"; [ -n "$BASE" ] || BASE="$T_PROJ" ;;
  esac
}

# run_hook <subcommand> [json] — run the implementation under test inside the
# sandbox. Prints the hook's stdout, drops stderr, returns the exit code.
run_hook() {
  local sub="$1" json="${2:-}"
  (
    cd "$T_PROJ" || exit 99
    case "$IMPL" in
      bash)
        printf '%s' "$json" | env -u USERPROFILE HOME="$T_HOME" CLAUDE_PROJECT_DIR="$T_PROJ" \
          bash "$DIR/scripts/self-improve-hook.sh" "$sub" ;;
      pwsh)
        printf '%s' "$json" | env -u USERPROFILE HOME="$T_HOME" CLAUDE_PROJECT_DIR="$T_PROJ" \
          POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off \
          pwsh -NoLogo -NoProfile -NonInteractive -File "$DIR/scripts/self-improve-hook.ps1" "$sub" ;;
    esac
  ) 2>/dev/null
}

# run_hook_without_jq <subcommand> <json> — bash only. PATH holds symlinks to
# exactly the tools the hook needs, so a jq preinstalled next to them in
# /usr/bin cannot leak in.
run_hook_without_jq() {
  local shim="$TMP/shim-nojq" t
  if [ ! -d "$shim" ]; then
    mkdir -p "$shim"
    for t in awk cat cut date find grep mkdir mktemp mv rm sed sort tail tr; do
      ln -s "$(command -v "$t")" "$shim/$t"
    done
  fi
  (
    cd "$T_PROJ" || exit 99
    printf '%s' "$2" | env -u USERPROFILE PATH="$shim" HOME="$T_HOME" CLAUDE_PROJECT_DIR="$T_PROJ" \
      "$BASH" "$DIR/scripts/self-improve-hook.sh" "$1"
  ) 2>/dev/null
}

# ── tool-failure ──────────────────────────────────────────────────────────────

t_tool_failure_records_line() {
  fresh global
  local rc=0 log
  run_hook tool-failure "$FAIL_JSON" >/dev/null || rc=$?
  assert_eq "tool-failure exits 0" "0" "$rc"
  log="$(file_or_empty "$BASE/.learnings/.pending-errors.log")"
  assert_contains "records tool, session and tool_use_id" \
    "TOOL_FAILURE: Bash session=sess-1 tool_use_id=toolu_01" "$log"
  assert_not_contains "never persists the error text" "exit code 1" "$log"
  assert_not_contains "never persists the tool input" "false" "$log"
  if printf '%s\n' "$log" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z TOOL_FAILURE: '; then
    pass
  else
    fail "line starts with a UTC timestamp" "$log"
  fi
}

t_tool_failure_skips_interrupt() {
  fresh global
  run_hook tool-failure '{"session_id":"s","tool_name":"Bash","tool_use_id":"t","is_interrupt":true}' >/dev/null
  assert_missing "a user interrupt is not logged" "$BASE/.learnings/.pending-errors.log"
}

t_tool_failure_project_local() {
  fresh local
  run_hook tool-failure "$FAIL_JSON" >/dev/null
  assert_contains "project workspace used when there is no global one" \
    "TOOL_FAILURE: Bash" "$(file_or_empty "$T_PROJ/.learnings/.pending-errors.log")"
}

t_tool_failure_global_wins() {
  fresh both
  run_hook tool-failure "$FAIL_JSON" >/dev/null
  assert_contains "global workspace wins, as in commands/self-improve.md" \
    "TOOL_FAILURE: Bash" "$(file_or_empty "$T_HOME/.claude/.learnings/.pending-errors.log")"
  assert_missing "project log untouched when global exists" "$T_PROJ/.learnings/.pending-errors.log"
}

t_tool_failure_no_workspace() {
  fresh none
  local rc=0
  run_hook tool-failure "$FAIL_JSON" >/dev/null || rc=$?
  assert_eq "no workspace still exits 0" "0" "$rc"
  assert_missing "creates no global workspace" "$T_HOME/.claude"
  assert_missing "creates no project workspace" "$T_PROJ/.learnings"
}

t_tool_failure_sanitizes_payload() {
  fresh global
  run_hook tool-failure '{"session_id":"s 1","tool_name":"Bash\nX TOOL_FAILURE: forged","tool_use_id":"t#1","is_interrupt":false}' >/dev/null
  assert_eq "a newline in tool_name cannot forge a second line" "1" \
    "$(line_count "$BASE/.learnings/.pending-errors.log")"
  assert_not_contains "spaces are stripped from ids" "session=s 1" \
    "$(file_or_empty "$BASE/.learnings/.pending-errors.log")"
}

t_tool_failure_malformed_json() {
  fresh global
  local rc=0
  run_hook tool-failure 'not json{' >/dev/null || rc=$?
  assert_eq "malformed payload still exits 0" "0" "$rc"
  assert_contains "malformed payload is recorded as unknown" \
    "TOOL_FAILURE: unknown session=unknown tool_use_id=unknown" \
    "$(file_or_empty "$BASE/.learnings/.pending-errors.log")"
}

t_tool_failure_without_jq() {
  [ "$IMPL" = "bash" ] || return 0
  fresh global
  run_hook_without_jq tool-failure "$FAIL_JSON" >/dev/null
  assert_contains "sed fallback reads the fields without jq" \
    "TOOL_FAILURE: Bash session=sess-1 tool_use_id=toolu_01" \
    "$(file_or_empty "$BASE/.learnings/.pending-errors.log")"
  run_hook_without_jq tool-failure '{"session_id":"s","tool_name":"Bash","tool_use_id":"t","is_interrupt":true}' >/dev/null
  assert_eq "sed fallback still skips interrupts" "1" "$(line_count "$BASE/.learnings/.pending-errors.log")"
}

# ── static checks ─────────────────────────────────────────────────────────────

s_hook_sh_syntax() {
  if bash -n "$DIR/scripts/self-improve-hook.sh" 2>/dev/null; then pass; else fail "self-improve-hook.sh parses"; fi
  if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3'; then
    if /bin/bash -n "$DIR/scripts/self-improve-hook.sh" 2>/dev/null; then pass; else fail "parses under bash 3.2"; fi
  else
    echo "SKIP: no bash 3.2 at /bin/bash"
  fi
}

s_hook_sh_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    local out
    out="$(shellcheck -S warning "$DIR/scripts/self-improve-hook.sh" 2>&1)" || true
    assert_eq "shellcheck clean at warning level" "" "$out"
  else
    echo "SKIP: shellcheck not installed"
  fi
}

# ── Runner ────────────────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required to run this suite." >&2
  exit 1
fi

IMPLS="bash"

for IMPL in $IMPLS; do
  echo "== implementation: $IMPL =="
  for t in $(declare -F | awk '{print $3}' | grep '^t_'); do "$t"; done
done
IMPL="static"
for t in $(declare -F | awk '{print $3}' | grep '^s_'); do "$t"; done

echo "self-improve hook tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
