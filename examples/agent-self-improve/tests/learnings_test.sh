#!/usr/bin/env bash
# Behavioural tests for scripts/learnings.sh. Every case runs in a sandboxed
# HOME and project dir under a mktemp root with the date pinned, so no test
# touches the real ~/.claude and none depends on today's date.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
CASE=0
CURRENT=""
T_HOME=""
T_PROJ=""
W=""
TODAY="2026-09-26"

pass() { PASS=$((PASS+1)); }
fail() {
  FAIL=$((FAIL+1))
  echo "FAIL [$CURRENT]: $1"
  if [ $# -gt 1 ]; then printf '  %s\n' "${@:2}"; fi
}
assert_eq() { if [ "$2" = "$3" ]; then pass; else fail "$1" "expected: $2" "actual:   $3"; fi; }
assert_contains() { case "$3" in *"$2"*) pass ;; *) fail "$1" "missing: $2" "in: $3" ;; esac; }
assert_not_contains() { case "$3" in *"$2"*) fail "$1" "unexpected: $2" ;; *) pass ;; esac; }
assert_missing() { if [ ! -e "$2" ]; then pass; else fail "$1" "should not exist: $2"; fi; }
file_or_empty() { if [ -f "$1" ]; then cat "$1"; fi; }

# fresh <global|local> — new sandbox. W is the workspace root.
fresh() {
  CASE=$((CASE+1))
  T_HOME="$TMP/$CASE/home"
  T_PROJ="$TMP/$CASE/proj"
  mkdir -p "$T_HOME" "$T_PROJ"
  case "$1" in
    global) W="$T_HOME/.claude" ;;
    local)  W="$T_PROJ" ;;
  esac
  mkdir -p "$W/.learnings"
}

# entry <file> <id> <status> [Field=value ...] — append one entry. Context
# and Content get defaults unless overridden; other pairs become extra
# **Field**: value lines.
entry() {
  local file="$1" id="$2" status="$3" kv ctx body extra=""
  ctx="Working on $id"
  body="Content of $id"
  shift 3
  for kv in "$@"; do
    case "$kv" in
      Context=*) ctx="${kv#Context=}" ;;
      Content=*) body="${kv#Content=}" ;;
      *) extra="$extra**${kv%%=*}**: ${kv#*=}"$'\n' ;;
    esac
  done
  printf '\n### %s\n**Status**: %s\n**Context**: %s\n**Content**: %s\n**Action**: Recorded\n%s' \
    "$id" "$status" "$ctx" "$body" "$extra" >> "$W/.learnings/$file"
}

# L <args...> — run learnings.sh in the sandbox with the date pinned.
L() {
  (
    cd "$T_PROJ" || exit 99
    env -u USERPROFILE HOME="$T_HOME" CLAUDE_PROJECT_DIR="$T_PROJ" LEARNINGS_LOCK_TRIES=1 \
      bash "$DIR/scripts/learnings.sh" --today "$TODAY" "$@"
  )
}

# ── PR 1: whereami, entries, lint, set-status ─────────────────────────────────

t_no_workspace() {
  fresh global; rm -rf "$W/.learnings"
  local rc=0 out
  out="$(L lint 2>&1)" || rc=$?
  assert_eq "no workspace exits 2" "2" "$rc"
  assert_contains "says how to fix it" "run /platform-skills:self-improve init" "$out"
}

t_whereami() {
  fresh global
  assert_contains "global scope" "scope=global" "$(L whereami)"
  fresh local
  mkdir -p "$T_PROJ/sub"
  git -C "$T_PROJ" init -q
  local out
  out="$(cd "$T_PROJ/sub" && env -u USERPROFILE HOME="$T_HOME" CLAUDE_PROJECT_DIR="$T_PROJ/sub" \
    bash "$DIR/scripts/learnings.sh" --base "$T_PROJ" whereami)"
  assert_contains "project name is the git top-level" "project=proj" "$out"
}

t_entries_parses_fields() {
  fresh global
  printf '# Error Log\n\nFormat: `ERR-YYYYMMDD-NNN`\n\n---\n' > "$W/.learnings/ERRORS.md"
  printf '%s\n' '### ERR-20260901-001' '**Status**: resolved' '**Context**: Planning the RDS change' \
    '**Content**: Subnet group changes force replacement' '**Source**: observed' '**Scope**: project:proj' \
    '**Paths**: infrastructure/**/*.tf, modules/**/*.tf' '**Verified**: 2026-09-01' '**Expires**: never' \
    '**Action**: Recorded' 'continued on a second line' '' '---' >> "$W/.learnings/ERRORS.md"
  local rec
  rec="$(L entries)"
  assert_eq "one record, header ignored" "1" "$(printf '%s\n' "$rec" | grep -c .)"
  assert_eq "id" "ERR-20260901-001" "$(printf '%s' "$rec" | awk -F'\t' '{print $1}')"
  assert_eq "status" "resolved" "$(printf '%s' "$rec" | awk -F'\t' '{print $4}')"
  assert_eq "paths" "infrastructure/**/*.tf, modules/**/*.tf" "$(printf '%s' "$rec" | awk -F'\t' '{print $7}')"
  assert_eq "a continuation line joins the last field" "Recorded continued on a second line" \
    "$(printf '%s' "$rec" | awk -F'\t' '{print $13}')"
}
t_lint_clean() {
  fresh global
  entry LEARNINGS.md LRN-20260920-001 resolved Source=user Scope=global Verified=2026-09-20
  local rc=0 out
  out="$(L lint)" || rc=$?
  assert_eq "clean workspace exits 0" "0" "$rc"
  assert_contains "summary" "lint: 1 entries, 0 errors, 0 warnings, 0 expired, 0 stale, 0 without metadata" "$out"
}

t_lint_shipped_templates() {
  fresh global
  cp "$DIR/.learnings/"*.md "$W/.learnings/"
  local rc=0 out
  out="$(L lint)" || rc=$?
  assert_eq "the shipped templates lint clean" "0" "$rc"
  assert_contains "example entries are not counted" "lint: 0 entries" "$out"
}

t_lint_errors() {
  fresh global
  printf '\n### ERR-20260901-001\n**Status**: done\n**Context**: c\n**Action**: a\n' > "$W/.learnings/ERRORS.md"
  entry LEARNINGS.md LRN-20260901-001 resolved Source=guess
  entry LEARNINGS.md LRN-20260901-002 resolved Scope=team
  entry LEARNINGS.md LRN-20260901-003 resolved Scope=global Paths=src/**
  entry LEARNINGS.md LRN-20260901-004 resolved Verified=2026-13-01 Expires=soon
  entry LEARNINGS.md LRN-20260901-005 resolved Supersedes=LRN-20200101-001
  entry FEATURE_REQUESTS.md LRN-20260901-001 pending
  local rc=0 out
  out="$(L lint)" || rc=$?
  assert_eq "errors exit 1" "1" "$rc"
  assert_contains "unknown status" 'ERROR ERR-20260901-001 unknown status "done"' "$out"
  assert_contains "missing content" "ERROR ERR-20260901-001 missing **Content**" "$out"
  assert_contains "unknown source" 'ERROR LRN-20260901-001 unknown source "guess"' "$out"
  assert_contains "bad scope" 'ERROR LRN-20260901-002 bad scope "team"' "$out"
  assert_contains "paths need a project scope" "ERROR LRN-20260901-003 **Paths** needs a project:<name> scope" "$out"
  assert_contains "bad verified date" 'ERROR LRN-20260901-004 bad **Verified** date "2026-13-01"' "$out"
  assert_contains "bad expires" 'ERROR LRN-20260901-004 bad **Expires** "soon"' "$out"
  assert_contains "dangling supersedes" "ERROR LRN-20260901-005 supersedes unknown id LRN-20200101-001" "$out"
  assert_contains "duplicate id across files" "ERROR LRN-20260901-001 duplicate id" "$out"
}

t_lint_supersedes_warning() {
  fresh global
  entry LEARNINGS.md LRN-20260801-001 resolved Source=user Scope=global Verified=2026-08-01
  entry LEARNINGS.md LRN-20260901-001 resolved Source=user Scope=global Verified=2026-09-01 Supersedes=LRN-20260801-001
  local rc=0 out
  out="$(L lint)" || rc=$?
  assert_eq "a warning alone exits 0" "0" "$rc"
  assert_contains "the superseded entry is still active" \
    "WARN LRN-20260901-001 supersedes LRN-20260801-001, which is still resolved" "$out"
}

t_lint_expired_and_stale() {
  fresh global
  entry LEARNINGS.md LRN-20260101-001 resolved Source=user Scope=global Verified=2026-01-01
  entry LEARNINGS.md LRN-20260820-001 resolved Source=inferred Scope=global Verified=2026-08-20
  entry LEARNINGS.md LRN-20260601-001 promoted Source=observed Scope=global Verified=2026-06-01
  entry LEARNINGS.md LRN-20260701-001 resolved Source=ci Scope=global Verified=2026-07-01 Expires=2026-09-25
  entry LEARNINGS.md LRN-20260702-001 revoked Source=ci Scope=global Verified=2020-01-01 Expires=2020-01-02
  entry LEARNINGS.md LRN-20260703-001 resolved
  entry LEARNINGS.md LRN-20260704-001 resolved Source=user Scope=global Verified=2026-07-04 Expires=2026-09-26
  entry LEARNINGS.md LRN-20250926-001 resolved Source=repo Scope=global Verified=2025-09-26
  local out
  out="$(L lint)"
  assert_not_contains "an entry expiring today is still valid today" "EXPIRED LRN-20260704-001" "$out"
  assert_contains "ages are exact across a year boundary" "STALE LRN-20250926-001 verified 365 days ago" "$out"
  assert_not_contains "user statements never go stale" "STALE LRN-20260101-001" "$out"
  assert_contains "inferences go stale after 30 days" \
    "STALE LRN-20260820-001 verified 37 days ago (limit 30 for source inferred)" "$out"
  assert_contains "a stale promoted rule is called out" \
    "STALE LRN-20260601-001 verified 117 days ago (limit 90 for source observed); its promoted rule is still loaded" "$out"
  assert_contains "expired" "EXPIRED LRN-20260701-001 expired 2026-09-25" "$out"
  assert_not_contains "inactive entries are not reported" "LRN-20260702-001" "$out"
  assert_contains "legacy entries are counted" "1 without metadata" "$out"
}

t_set_status() {
  fresh global
  entry ERRORS.md ERR-20260901-001 resolved
  entry ERRORS.md ERR-20260901-002 resolved "Status-Note=2026-09-02 old note"
  local rc=0 file
  L set-status ERR-20260901-002 revoked --note "replaced by ERR-20260920-001" >/dev/null || rc=$?
  assert_eq "set-status exits 0" "0" "$rc"
  file="$(file_or_empty "$W/.learnings/ERRORS.md")"
  assert_contains "status rewritten" $'### ERR-20260901-002\n**Status**: revoked\n**Status-Note**: 2026-09-26 replaced by ERR-20260920-001' "$file"
  assert_not_contains "the old note is replaced" "old note" "$file"
  assert_contains "other entries untouched" $'### ERR-20260901-001\n**Status**: resolved' "$file"
  assert_missing "lock released" "$W/.learnings/.drain.lock"
}

t_set_status_refusals() {
  fresh global
  entry ERRORS.md ERR-20260901-001 resolved
  local rc=0
  L set-status ERR-20990101-001 resolved >/dev/null 2>&1 || rc=$?
  assert_eq "unknown id exits 4" "4" "$rc"
  rc=0; L set-status ERR-20260901-001 finished >/dev/null 2>&1 || rc=$?
  assert_eq "unknown status exits 2" "2" "$rc"
  : > "$W/.learnings/.drain.lock"
  rc=0; L set-status ERR-20260901-001 revoked >/dev/null 2>&1 || rc=$?
  assert_eq "a held lock exits 3" "3" "$rc"
  assert_contains "nothing changed while locked" "**Status**: resolved" "$(file_or_empty "$W/.learnings/ERRORS.md")"
  touch -t 202001010000 "$W/.learnings/.drain.lock"
  rc=0; L set-status ERR-20260901-001 revoked >/dev/null 2>&1 || rc=$?
  assert_eq "a stale lock is broken" "0" "$rc"
}


# ── Runner ────────────────────────────────────────────────────────────────────

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do CURRENT="$t"; "$t"; done

if command -v shellcheck >/dev/null 2>&1; then
  CURRENT="static"
  out="$(shellcheck -S warning "$DIR/scripts/learnings.sh" 2>&1)" || true
  assert_eq "shellcheck clean at warning level" "" "$out"
else
  echo "SKIP: shellcheck not installed"
fi
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3'; then
  CURRENT="static"
  if /bin/bash -n "$DIR/scripts/learnings.sh" 2>/dev/null; then pass; else fail "parses under bash 3.2"; fi
fi

echo "learnings tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
