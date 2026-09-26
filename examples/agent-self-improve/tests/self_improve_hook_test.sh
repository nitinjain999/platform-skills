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

# ── session-end ───────────────────────────────────────────────────────────────

END_JSON='{"session_id":"sess-9","hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'

t_session_end_drains_pending() {
  fresh global
  # Header-only ERRORS.md is the case where the legacy `grep -c || echo 0`
  # produced "0\n0" and crashed the id arithmetic. An older day's id must
  # not affect today's numbering.
  printf '# Errors\n\n### ERR-20200101-007\n**Status**: resolved\n' > "$BASE/.learnings/ERRORS.md"
  printf '%s\n%s\n' \
    "2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s1 tool_use_id=t1" \
    "2026-09-26T10:01:00Z TOOL_FAILURE: Edit session=s1 tool_use_id=t2" \
    > "$BASE/.learnings/.pending-errors.log"
  local rc=0 errors
  run_hook session-end "$END_JSON" >/dev/null || rc=$?
  assert_eq "session-end exits 0" "0" "$rc"
  errors="$(file_or_empty "$BASE/.learnings/ERRORS.md")"
  assert_contains "first drained failure is -001" "### ERR-$STAMP-001" "$errors"
  assert_contains "second drained failure is -002" "### ERR-$STAMP-002" "$errors"
  assert_contains "content names the tool and ids" '`Edit` failed (session s1, tool_use_id t2)' "$errors"
  assert_contains "entry is pending" "**Status**: pending" "$errors"
  assert_missing "pending log removed" "$BASE/.learnings/.pending-errors.log"
  assert_missing "draining file removed" "$BASE/.learnings/.pending-errors.draining"
}

t_session_end_continues_after_highest_id() {
  fresh global
  printf '### ERR-%s-001\n**Status**: resolved\n\n### ERR-%s-003\n**Status**: pending\n' \
    "$STAMP" "$STAMP" > "$BASE/.learnings/ERRORS.md"
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s tool_use_id=t\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "next id follows the highest, not the count" "### ERR-$STAMP-004" \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
  assert_eq "no id reused" "1" "$(grep -c "^### ERR-$STAMP-003" "$BASE/.learnings/ERRORS.md")"
}

t_session_end_leading_zero_ids() {
  fresh global
  printf '### ERR-%s-008\n\n### ERR-%s-009\n' "$STAMP" "$STAMP" > "$BASE/.learnings/ERRORS.md"
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s tool_use_id=t\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "008/009 are decimal, not octal" "### ERR-$STAMP-010" \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
}

t_session_end_legacy_line_format() {
  fresh global
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "a line without ids still drains" '`Bash` failed (session unknown, tool_use_id unknown)' \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
}

t_session_end_drains_leftover_draining() {
  fresh global
  printf '2026-09-26T09:00:00Z TOOL_FAILURE: Read session=old tool_use_id=t0\n' > "$BASE/.learnings/.pending-errors.draining"
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=new tool_use_id=t1\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  local errors
  errors="$(file_or_empty "$BASE/.learnings/ERRORS.md")"
  assert_contains "leftover from an interrupted drain is kept" '`Read` failed (session old' "$errors"
  assert_contains "fresh pending line is drained too" '`Bash` failed (session new' "$errors"
  assert_eq "each line drained exactly once" "2" "$(grep -c '^### ERR-' "$BASE/.learnings/ERRORS.md")"
  assert_missing "draining file removed" "$BASE/.learnings/.pending-errors.draining"
}

t_session_end_aggregates_repeats() {
  fresh global
  printf '%s\n%s\n%s\n%s\n' \
    "2026-09-26T10:00:00Z TOOL_FAILURE: Edit session=s1 tool_use_id=t1" \
    "2026-09-26T10:01:00Z TOOL_FAILURE: Edit session=s1 tool_use_id=t2" \
    "2026-09-26T10:02:00Z TOOL_FAILURE: Edit session=s1 tool_use_id=t3" \
    "2026-09-26T10:03:00Z TOOL_FAILURE: Edit session=s2 tool_use_id=t4" \
    > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  local errors
  errors="$(file_or_empty "$BASE/.learnings/ERRORS.md")"
  assert_eq "repeats of one tool in one session become one entry" "2" "$(grep -c '^### ERR-' "$BASE/.learnings/ERRORS.md")"
  assert_contains "the entry carries the count and first id" \
    '`Edit` failed 3 times (session s1, first tool_use_id t1)' "$errors"
  assert_contains "the same tool in another session stays separate" \
    '`Edit` failed (session s2, tool_use_id t4)' "$errors"
  assert_contains "context keeps the first timestamp" "hook at 2026-09-26T10:00:00Z" "$errors"
}

t_session_end_respects_drain_lock() {
  fresh global
  : > "$BASE/.learnings/.drain.lock"
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s tool_use_id=t\n' > "$BASE/.learnings/.pending-errors.log"
  local rc=0
  run_hook session-end "$END_JSON" >/dev/null || rc=$?
  assert_eq "a held lock still exits 0" "0" "$rc"
  assert_missing "a parallel session holding the lock owns the drain" "$BASE/.learnings/ERRORS.md"
  assert_eq "pending line left for the next drain" "1" "$(line_count "$BASE/.learnings/.pending-errors.log")"
  assert_contains "the daily note is still written" "## Session closed: " "$(file_or_empty "$BASE/memory/$TODAY.md")"
  assert_eq "someone else's lock is not removed" "0" "$(line_count "$BASE/.learnings/.drain.lock")"
  [ -e "$BASE/.learnings/.drain.lock" ] && pass || fail "fresh lock left in place"
}

t_session_end_breaks_stale_lock() {
  fresh global
  : > "$BASE/.learnings/.drain.lock"
  touch -t 202001010000 "$BASE/.learnings/.drain.lock"
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s tool_use_id=t\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "a lock left by a killed session is broken" "### ERR-$STAMP-001" \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
  assert_missing "the lock is released after the drain" "$BASE/.learnings/.drain.lock"
}

t_session_end_one_heading_per_session() {
  fresh global
  run_hook session-end "$END_JSON" >/dev/null
  run_hook session-end "$END_JSON" >/dev/null
  local daily="$BASE/memory/$TODAY.md"
  assert_eq "one Session closed heading per SessionEnd" "2" "$(grep -c '^## Session closed: ' "$daily" 2>/dev/null)"
  assert_contains "heading records the end reason" "(prompt_input_exit)" "$(file_or_empty "$daily")"
  assert_contains "daily note title keeps the em dash" "# Daily Notes — $TODAY" "$(file_or_empty "$daily")"
  assert_eq "daily note has no BOM" "#" "$(head -c1 "$daily" 2>/dev/null)"
  assert_eq "counter counts sessions" "2" "$(tr -cd '0-9' < "$BASE/memory/.session-count" 2>/dev/null)"
}

t_session_end_review_reminder() {
  fresh global
  printf '4\n' > "$BASE/memory/.session-count"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "reminder on every fifth session" "### Review reminder (session 5):" \
    "$(file_or_empty "$BASE/memory/$TODAY.md")"
}

t_session_end_pending_wal() {
  fresh global
  printf '## WAL Entry — 2026-09-26 10:00\n**Operation**: delete namespace payments-canary\n**Status**: PENDING\n' \
    > "$BASE/memory/working-buffer.md"
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "a PENDING WAL entry is logged" "Session closed with a PENDING WAL entry" \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
}

t_session_end_ignores_wal_template() {
  fresh global
  cp "$DIR/memory/working-buffer.md" "$BASE/memory/working-buffer.md"
  run_hook session-end "$END_JSON" >/dev/null
  assert_not_contains "the template's commented Status line is not a pending WAL" "PENDING WAL" \
    "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
}

t_session_end_incomplete_steps() {
  fresh global
  printf '## Progress\n\n- [x] snapshot etcd\n- [ ] roll back payments-canary\n' > "$BASE/memory/working-buffer.md"
  run_hook session-end "$END_JSON" >/dev/null
  local daily
  daily="$(file_or_empty "$BASE/memory/$TODAY.md")"
  assert_contains "incomplete step carried into the daily note" "- [ ] roll back payments-canary" "$daily"
  assert_not_contains "completed step not carried" "snapshot etcd" "$daily"
}

t_session_end_project_local() {
  fresh local
  run_hook session-end "$END_JSON" >/dev/null
  assert_contains "project workspace gets the daily note" "## Session closed: " \
    "$(file_or_empty "$T_PROJ/memory/$TODAY.md")"
  assert_missing "no global workspace created" "$T_HOME/.claude"
}

t_session_end_no_workspace() {
  fresh none
  local rc=0
  run_hook session-end "$END_JSON" >/dev/null || rc=$?
  assert_eq "no workspace still exits 0" "0" "$rc"
  assert_missing "creates no global workspace" "$T_HOME/.claude"
  assert_missing "creates no project memory" "$T_PROJ/memory"
}

t_session_end_empty_stdin() {
  fresh global
  run_hook session-end "" >/dev/null
  assert_contains "missing reason is recorded as unknown" "(unknown)" "$(file_or_empty "$BASE/memory/$TODAY.md")"
}

t_session_end_clears_legacy_marker() {
  fresh global
  : > "$BASE/memory/.session-active"
  run_hook session-end "$END_JSON" >/dev/null
  assert_missing "legacy banner marker removed" "$BASE/memory/.session-active"
}

t_session_end_without_jq() {
  [ "$IMPL" = "bash" ] || return 0
  fresh global
  printf '2026-09-26T10:00:00Z TOOL_FAILURE: Bash session=s tool_use_id=t\n' > "$BASE/.learnings/.pending-errors.log"
  run_hook_without_jq session-end "$END_JSON" >/dev/null
  assert_contains "reason parsed without jq" "(prompt_input_exit)" "$(file_or_empty "$BASE/memory/$TODAY.md")"
  assert_contains "drain works without jq" "### ERR-$STAMP-001" "$(file_or_empty "$BASE/.learnings/ERRORS.md")"
}

t_session_end_stale_lock_break_is_exclusive() {
  [ "$IMPL" = "bash" ] || return 0
  fresh global
  local lock="$BASE/.learnings/.drain.lock" out="$TMP/race-$$"
  : > "$lock"
  touch -t 202001010000 "$lock"
  mkdir -p "$out"
  # Race two real subshells against the same stale lock via the script's own
  # acquire_lock, by sourcing the function directly (not by starting a second
  # SessionEnd, which would also touch ERRORS.md and complicate the assertion).
  ( . "$DIR/scripts/self-improve-hook.sh" --source-only 2>/dev/null; acquire_lock "$lock" && echo win > "$out/a" ) &
  ( . "$DIR/scripts/self-improve-hook.sh" --source-only 2>/dev/null; acquire_lock "$lock" && echo win > "$out/b" ) &
  wait
  local wins
  wins=$(ls "$out" 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "at most one racer breaks the same stale lock" "1" "$wins"
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
