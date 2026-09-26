#!/usr/bin/env bash
# learnings.sh — deterministic helpers for the self-improve .learnings/ store.
# /platform-skills:self-improve calls these instead of asking the model to
# parse entries, do date arithmetic, or edit instruction files by hand.
#
#   whereami                         workspace, scope and project name
#   entries                          one TSV record per entry
#   lint                             validate entries; report expired and stale
#   set-status ID STATUS [--note T]  rewrite one entry's Status line
#
# Global options, before the subcommand: --base DIR (skip resolution),
# --today YYYY-MM-DD (tests pin the date).
#
# Workspace resolution matches commands/self-improve.md and
# self-improve-hook.sh: ~/.claude/.learnings wins, then
# ${CLAUDE_PROJECT_DIR:-$PWD}/.learnings.
#
# Exit codes: 0 ok, 1 lint errors, 2 usage or no workspace, 3 workspace busy
# (lock held), 4 refused (entry missing or not eligible).
#
# Requires bash 3.2+ and a POSIX awk. No arrays: bash 3.2 treats an empty
# "${arr[@]}" as unbound under set -u.

set -u

TODAY="$(date +%Y-%m-%d)"
BASE=""
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

die() { echo "learnings.sh: $2" >&2; exit "$1"; }

resolve_base() {
  if [ -d "$HOME/.claude/.learnings" ]; then
    printf '%s\n' "$HOME/.claude"
  elif [ -d "$PROJECT/.learnings" ]; then
    printf '%s\n' "$PROJECT"
  fi
}

# project_name — the git top-level's basename, else the project dir's.
# `log` writes it into **Scope**: project:<name>, so both must agree.
project_name() {
  local top
  top="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)" || top=""
  basename "${top:-$PROJECT}"
}

learning_files() {
  local f
  for f in LEARNINGS.md ERRORS.md FEATURE_REQUESTS.md; do
    [ -f "$BASE/.learnings/$f" ] && printf '%s\n' "$BASE/.learnings/$f"
  done
}

# ── entries ───────────────────────────────────────────────────────────────────
# TSV columns: 1 id, 2 file, 3 line, 4 status, 5 source, 6 scope, 7 paths,
# 8 verified, 9 expires, 10 supersedes, 11 context, 12 content, 13 action.
# Empty columns are real empties, so consume this with awk -F'\t', never
# with `read`: IFS whitespace would collapse adjacent tabs.
cmd_entries() {
  local files
  files="$(learning_files)"
  [ -n "$files" ] || return 0
  # shellcheck disable=SC2086  # file paths never contain spaces here
  awk '
    function flush() {
      if (id != "")
        printf "%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, file, line,
          f["status"], f["source"], f["scope"], f["paths"], f["verified"],
          f["expires"], f["supersedes"], f["context"], f["content"], f["action"]
      id = ""; last = ""; split("", f)
    }
    FNR == 1 { flush(); file = FILENAME; sub(/.*\//, "", file) }
    /^### (LRN|ERR|FEAT)-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]*[[:space:]]*$/ {
      flush(); id = $2; line = FNR; next
    }
    /^#/ || /^---[[:space:]]*$/ { flush(); next }
    id != "" && /^\*\*[A-Za-z-]+\*\*:/ {
      name = $0; sub(/^\*\*/, "", name); sub(/\*\*:.*/, "", name); name = tolower(name)
      val = $0; sub(/^\*\*[A-Za-z-]+\*\*:[[:space:]]*/, "", val)
      gsub(/\t/, " ", val); sub(/[[:space:]]+$/, "", val)
      f[name] = val; last = name; next
    }
    id != "" && last != "" && NF > 0 {
      v = $0; gsub(/\t/, " ", v); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      f[last] = f[last] " " v; next
    }
    END { flush() }
  ' $files
}

# Shared awk: date helpers and the staleness policy. A verified date older
# than the window for its source needs re-verifying. User statements don't
# go stale; inferences go stale fastest.
AWK_LIB='
  function valid_date(s,   m, d) {
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    return m >= 1 && m <= 12 && d >= 1 && d <= 31
  }
  function days(s,   y, m, d) {
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m <= 2) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d
  }
  function window(source) {
    if (source == "user") return -1
    if (source == "inferred") return 30
    return 90
  }
  function is_expired(expires, today) {
    return valid_date(expires) && days(expires) < days(today)
  }
  function stale_age(verified, source, today,   w, age) {
    w = window(source)
    if (w < 0 || !valid_date(verified)) return -1
    age = days(today) - days(verified)
    return age > w ? age : -1
  }
'

# ── lint ──────────────────────────────────────────────────────────────────────
ACTIVE_STATUSES="pending resolved promoted"
ALL_STATUSES="pending resolved promoted superseded revoked discarded example"

cmd_lint() {
  cmd_entries | TODAY="$TODAY" ACTIVE="$ACTIVE_STATUSES" ALL="$ALL_STATUSES" awk -F'\t' "$AWK_LIB"'
    function has(list, word) { return index(" " list " ", " " word " ") > 0 }
    function err(id, msg) { printf "ERROR %s %s\n", id, msg; errors++ }
    function warn(id, msg) { printf "WARN %s %s\n", id, msg; warnings++ }
    BEGIN { today = ENVIRON["TODAY"]; active = ENVIRON["ACTIVE"]; all = ENVIRON["ALL"] }
    {
      id = $1; status = $4; source = $5; scope = $6; paths = $7
      verified = $8; expires = $9; supersedes = $10
      if (status == "example") next
      total++
      if (seen[id]++) err(id, "duplicate id (also in an earlier entry)")
      state[id] = status
      if (status == "") err(id, "missing **Status**")
      else if (!has(all, status)) err(id, "unknown status \"" status "\"")
      if ($11 == "") err(id, "missing **Context**")
      if ($12 == "") err(id, "missing **Content**")
      if ($13 == "") err(id, "missing **Action**")
      if (source != "" && !has("user observed ci repo vendor-docs inferred", source))
        err(id, "unknown source \"" source "\" (user, observed, ci, repo, vendor-docs, inferred)")
      if (scope != "" && scope !~ /^global$/ && scope !~ /^project:[A-Za-z0-9._-]+$/)
        err(id, "bad scope \"" scope "\" (global or project:<name>)")
      if (paths != "") {
        if (scope !~ /^project:/) err(id, "**Paths** needs a project:<name> scope")
        if (paths ~ /"/ || paths ~ /(^|,)[[:space:]]*(,|$)/) err(id, "bad **Paths** (comma-separated globs, no quotes)")
      }
      if (verified != "" && !valid_date(verified)) err(id, "bad **Verified** date \"" verified "\"")
      if (expires != "" && expires != "never" && !valid_date(expires)) err(id, "bad **Expires** \"" expires "\" (YYYY-MM-DD or never)")
      if (supersedes != "") { sup_of[id] = supersedes }
      if (source == "" && verified == "") legacy++
      if (!has(active, status)) next
      if (is_expired(expires, today)) { printf "EXPIRED %s expired %s\n", id, expires; expired++ }
      age = stale_age(verified, source, today)
      if (age >= 0) {
        printf "STALE %s verified %d days ago (limit %d for source %s)%s\n", id, age, window(source),
          (source == "" ? "unknown" : source), (status == "promoted" ? "; its promoted rule is still loaded" : "")
        stale++
      }
    }
    END {
      for (id in sup_of) {
        old = sup_of[id]
        if (!(old in state)) err(id, "supersedes unknown id " old)
        else if (state[old] != "superseded") warn(id, "supersedes " old ", which is still " state[old])
      }
      printf "lint: %d entries, %d errors, %d warnings, %d expired, %d stale, %d without metadata\n",
        total, errors, warnings, expired, stale, legacy
      exit errors > 0 ? 1 : 0
    }'
}

# ── set-status ────────────────────────────────────────────────────────────────
LOCK_TRIES="${LEARNINGS_LOCK_TRIES:-5}"

in_list() {
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# acquire_lock <file> — same exclusive-create lock as self-improve-hook.sh,
# so a rewrite here never races the SessionEnd drain appending to ERRORS.md.
acquire_lock() {
  if ( set -C; : > "$1" ) 2>/dev/null; then return 0; fi
  if [ -n "$(find "$1" -mmin +10 2>/dev/null)" ]; then
    rm -f "$1"
    ( set -C; : > "$1" ) 2>/dev/null && return 0
  fi
  return 1
}

acquire_lock_wait() {
  local i=0
  while [ "$i" -lt "$LOCK_TRIES" ]; do
    acquire_lock "$1" && return 0
    i=$((i + 1))
    [ "$i" -lt "$LOCK_TRIES" ] && sleep 1
  done
  return 1
}

entry_file() {
  local files
  files="$(learning_files)"
  [ -n "$files" ] || return 0
  # shellcheck disable=SC2086
  grep -lx "### $1" $files 2>/dev/null | head -1
}

# rewrite_entry <file> <id> <status> <note> — replace the entry's Status line
# and its Status-Note (dropped when <note> is empty). Temp file + mv, so a
# reader never sees half a file.
rewrite_entry() {
  local tmp
  tmp="$(mktemp "$1.XXXXXX")" || return 1
  if ID="$2" STATUS="$3" NOTE="$4" TODAY="$TODAY" awk '
    BEGIN { id = ENVIRON["ID"]; status = ENVIRON["STATUS"]; note = ENVIRON["NOTE"]; today = ENVIRON["TODAY"] }
    $0 == "### " id { inside = 1; print; next }
    inside && (/^#/ || /^---[[:space:]]*$/) { inside = 0 }
    inside && /^\*\*Status-Note\*\*:/ { next }
    inside && /^\*\*Status\*\*:/ {
      print "**Status**: " status
      if (note != "") print "**Status-Note**: " today " " note
      next
    }
    { print }
  ' "$1" > "$tmp"; then
    mv -f "$tmp" "$1"
  else
    rm -f "$tmp"
    return 1
  fi
}

cmd_set_status() {
  local id="${1:-}" status="${2:-}" note="" file lock
  [ -n "$id" ] && [ -n "$status" ] || die 2 "usage: set-status ID STATUS [--note TEXT]"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --note) note="$(printf '%s' "${2:-}" | tr '\t\r\n' '   ')"; shift 2 ;;
      *) die 2 "set-status: unknown option $1" ;;
    esac
  done
  in_list "$status" "$ALL_STATUSES" && [ "$status" != "example" ] || die 2 "unknown status $status"
  file="$(entry_file "$id")"
  [ -n "$file" ] || die 4 "no entry $id"
  lock="$BASE/.learnings/.drain.lock"
  acquire_lock_wait "$lock" || die 3 "workspace busy: $lock is held"
  rewrite_entry "$file" "$id" "$status" "$note"
  local rc=$?
  rm -f "$lock"
  [ "$rc" -eq 0 ] || die 1 "could not rewrite $file"
  echo "$id: status $status"
}

# ── whereami ──────────────────────────────────────────────────────────────────
cmd_whereami() {
  local scope="project"
  [ "$BASE" = "$HOME/.claude" ] && scope="global"
  printf 'base=%s\nscope=%s\nproject=%s\ntoday=%s\n' "$BASE" "$scope" "$(project_name)" "$TODAY"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) BASE="${2:-}"; shift 2 ;;
      --today) TODAY="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  [ -n "$BASE" ] || BASE="$(resolve_base)"
  [ -n "$BASE" ] && [ -d "$BASE/.learnings" ] || die 2 "no .learnings workspace (run /platform-skills:self-improve init)"
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    whereami)   cmd_whereami ;;
    entries)    cmd_entries ;;
    lint)       cmd_lint ;;
    set-status) cmd_set_status "$@" ;;
    *) die 2 "usage: learnings.sh [--base DIR] [--today D] <subcommand> (see the header of this script)" ;;
  esac
}

main "$@"
