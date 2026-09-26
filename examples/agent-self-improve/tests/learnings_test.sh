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

# ── PR 2: promote, unpromote ──────────────────────────────────────────────────

# eligible <id> [Field=value ...] — a resolved, verified, project-scoped entry.
eligible() {
  local id="$1"
  shift
  entry ERRORS.md "$id" resolved Source=observed Scope=project:proj Verified=2026-09-20 "$@"
}

t_promote_preview_writes_nothing() {
  fresh global
  eligible ERR-20260920-001 "Paths=infrastructure/**/*.tf"
  local rc=0 out
  out="$(L promote ERR-20260920-001 --domain terraform --rule 'Scan plans for "forces replacement" before apply')" || rc=$?
  assert_eq "preview exits 0" "0" "$rc"
  assert_contains "shows a proposal" "PROMOTION PROPOSAL ERR-20260920-001" "$out"
  assert_contains "shows the evidence" "source=observed scope=project:proj verified=2026-09-20" "$out"
  assert_contains "diff adds the rule with its marker" \
    '+- Scan plans for "forces replacement" before apply <!-- self-improve:ERR-20260920-001 -->' "$out"
  assert_contains "diff adds the paths frontmatter" '+  - "infrastructure/**/*.tf"' "$out"
  assert_missing "preview writes no rule file" "$T_PROJ/.claude/rules/terraform.md"
  assert_contains "status unchanged" "**Status**: resolved" "$(file_or_empty "$W/.learnings/ERRORS.md")"
}

t_promote_apply_new_rules_file() {
  fresh global
  eligible ERR-20260920-001 "Paths=modules/**/*.tf, infrastructure/**/*.tf"
  local rc=0
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans for forces replacement" --apply >/dev/null || rc=$?
  assert_eq "apply exits 0" "0" "$rc"
  assert_eq "rule file with sorted paths frontmatter" \
    "$(printf '%s\n' '---' 'paths:' '  - "infrastructure/**/*.tf"' '  - "modules/**/*.tf"' '---' '' '# Terraform rules' '' \
      '- Scan plans for forces replacement <!-- self-improve:ERR-20260920-001 -->')" \
    "$(file_or_empty "$T_PROJ/.claude/rules/terraform.md")"
  assert_contains "status promoted with the target" \
    "**Status-Note**: 2026-09-26 promoted to $T_PROJ/.claude/rules/terraform.md" "$(file_or_empty "$W/.learnings/ERRORS.md")"
  rc=0
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans for forces replacement" --apply >/dev/null || rc=$?
  assert_eq "re-running is a no-op" "1" "$(grep -c 'self-improve:ERR-20260920-001' "$T_PROJ/.claude/rules/terraform.md")"
}

t_promote_appends_to_matching_rules_file() {
  fresh global
  mkdir -p "$T_PROJ/.claude/rules"
  printf '%s\n' '---' 'paths: "infrastructure/**/*.tf"' '---' '' '# Terraform rules' '' '- Pin provider versions' \
    > "$T_PROJ/.claude/rules/terraform.md"
  eligible ERR-20260920-001 "Paths=infrastructure/**/*.tf"
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans first" --apply >/dev/null
  assert_contains "appended after the existing rules" \
    $'- Pin provider versions\n- Scan plans first <!-- self-improve:ERR-20260920-001 -->' \
    "$(file_or_empty "$T_PROJ/.claude/rules/terraform.md")"
}

t_promote_refuses_mismatched_paths() {
  fresh global
  mkdir -p "$T_PROJ/.claude/rules"
  printf '# Terraform rules\n\n- Pin provider versions\n' > "$T_PROJ/.claude/rules/terraform.md"
  eligible ERR-20260920-001 "Paths=infrastructure/**/*.tf"
  local rc=0 out
  out="$(L promote ERR-20260920-001 --domain terraform --rule "Scan plans first" --apply 2>&1)" || rc=$?
  assert_eq "different paths exit 4" "4" "$rc"
  assert_contains "explains the mismatch" "applies to paths [all files] but ERR-20260920-001 needs [infrastructure/**/*.tf]" "$out"
  assert_not_contains "file untouched" "Scan plans first" "$(file_or_empty "$T_PROJ/.claude/rules/terraform.md")"
}

t_promote_global_scope() {
  fresh global
  entry LEARNINGS.md LRN-20260920-001 resolved Source=user Scope=global Verified=2026-01-01
  L promote LRN-20260920-001 --domain workflow --rule "Open draft PRs by default" --apply >/dev/null
  assert_contains "global scope lands in ~/.claude/rules" \
    "- Open draft PRs by default <!-- self-improve:LRN-20260920-001 -->" \
    "$(file_or_empty "$T_HOME/.claude/rules/workflow.md")"
}

t_promote_claude_md_section() {
  fresh global
  printf '%s\n' '# Project' '' '## Agent Rules' '' '- Existing rule' '' '## Other' 'text' > "$T_PROJ/CLAUDE.md"
  eligible ERR-20260920-001
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans first" --target CLAUDE.md --apply >/dev/null
  assert_eq "inserted at the end of the Agent Rules section" \
    "$(printf '%s\n' '# Project' '' '## Agent Rules' '' '- Existing rule' \
      '- Scan plans first <!-- self-improve:ERR-20260920-001 -->' '' '## Other' 'text')" \
    "$(file_or_empty "$T_PROJ/CLAUDE.md")"
  fresh global
  printf '# Project\n\nSome text\n' > "$T_PROJ/AGENTS.md"
  eligible ERR-20260920-001
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans first" --target AGENTS.md --apply >/dev/null
  assert_contains "section created when missing" \
    $'Some text\n\n## Agent Rules\n\n- Scan plans first <!-- self-improve:ERR-20260920-001 -->' \
    "$(file_or_empty "$T_PROJ/AGENTS.md")"
}

t_promote_refusals() {
  fresh global
  entry ERRORS.md ERR-20260901-001 pending Source=observed Scope=project:proj Verified=2026-09-20
  entry ERRORS.md ERR-20260901-002 revoked Source=observed Scope=project:proj Verified=2026-09-20
  entry ERRORS.md ERR-20260901-003 resolved
  entry ERRORS.md ERR-20260901-004 resolved Source=observed Scope=project:proj Verified=2026-09-20 Expires=2026-09-01
  entry ERRORS.md ERR-20260901-005 resolved Source=observed Scope=project:proj Verified=2026-05-01
  entry ERRORS.md ERR-20260901-006 resolved Source=inferred Scope=project:proj Verified=2026-09-20
  entry ERRORS.md ERR-20260901-007 resolved Source=observed Scope=project:other-repo Verified=2026-09-20
  entry ERRORS.md ERR-20260901-008 resolved Source=observed Scope=project:proj Verified=2026-09-20 Paths=src/**
  local id rc out
  for id in 001 002 003 004 005 006 007; do
    rc=0; out="$(L promote "ERR-20260901-$id" --domain terraform --rule "Rule" 2>&1)" || rc=$?
    assert_eq "ERR-20260901-$id is refused with exit 4" "4" "$rc"
  done
  out="$(L promote ERR-20260901-001 --domain terraform --rule "Rule" 2>&1)"
  assert_contains "pending explains itself" "is pending; resolve it before promoting" "$out"
  out="$(L promote ERR-20260901-003 --domain terraform --rule "Rule" 2>&1)"
  assert_contains "legacy entries need metadata" "has no **Source**, **Scope** or **Verified**" "$out"
  out="$(L promote ERR-20260901-005 --domain terraform --rule "Rule" 2>&1)"
  assert_contains "stale entries need re-verifying" "re-verify it and update **Verified** first" "$out"
  out="$(L promote ERR-20260901-007 --domain terraform --rule "Rule" 2>&1)"
  assert_contains "another project's lesson stays there" "is scoped to other-repo, but this project is proj" "$out"
  rc=0; L promote ERR-20260901-006 --domain terraform --rule "Rule" --allow-inferred >/dev/null 2>&1 || rc=$?
  assert_eq "--allow-inferred lets a confirmed inference through" "0" "$rc"
  rc=0; out="$(L promote ERR-20260901-008 --domain terraform --rule "Rule" --target CLAUDE.md 2>&1)" || rc=$?
  assert_eq "paths cannot go into CLAUDE.md" "4" "$rc"
  rc=0; L promote ERR-20260901-006 --domain "Terraform!" --rule "Rule" --allow-inferred >/dev/null 2>&1 || rc=$?
  assert_eq "bad domain exits 2" "2" "$rc"
  rc=0; L promote ERR-20260901-006 --domain terraform --rule "a <!-- b -->" --allow-inferred >/dev/null 2>&1 || rc=$?
  assert_eq "a rule cannot carry an HTML comment" "2" "$rc"
  rc=0; L promote ERR-20260901-006 --domain terraform --rule "$(printf 'x%.0s' $(seq 1 161))" --allow-inferred >/dev/null 2>&1 || rc=$?
  assert_eq "an overlong rule exits 2" "2" "$rc"
  rc=0; L promote ERR-20260901-006 --domain terraform --rule "Rule" --target README.md --allow-inferred >/dev/null 2>&1 || rc=$?
  assert_eq "an unknown target kind exits 2" "2" "$rc"
}

t_unpromote() {
  fresh global
  eligible ERR-20260920-001
  L promote ERR-20260920-001 --domain terraform --rule "Scan plans first" --apply >/dev/null
  printf '%s\n' '- Hand-written rule' >> "$T_PROJ/.claude/rules/terraform.md"
  local rc=0 out
  out="$(L unpromote ERR-20260920-001)" || rc=$?
  assert_eq "unpromote exits 0" "0" "$rc"
  assert_not_contains "the marked line is gone" "self-improve:ERR-20260920-001" "$(file_or_empty "$T_PROJ/.claude/rules/terraform.md")"
  assert_contains "other lines survive" "- Hand-written rule" "$(file_or_empty "$T_PROJ/.claude/rules/terraform.md")"
  assert_contains "status back to resolved" $'**Status**: resolved\n**Status-Note**: 2026-09-26 unpromoted (removed from' \
    "$(file_or_empty "$W/.learnings/ERRORS.md")"
  rc=0; L unpromote ERR-20260920-001 >/dev/null 2>&1 || rc=$?
  assert_eq "nothing left to remove exits 4" "4" "$rc"
  rc=0; L unpromote ERR-20260920-001 --revoke --note "wrong for EKS 1.35" >/dev/null || rc=$?
  assert_eq "--revoke works without a marker" "0" "$rc"
  assert_contains "revoked with the reason" $'**Status**: revoked\n**Status-Note**: 2026-09-26 wrong for EKS 1.35' \
    "$(file_or_empty "$W/.learnings/ERRORS.md")"
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
