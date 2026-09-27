#!/usr/bin/env bash
# learnings.sh — deterministic helpers for the self-improve .learnings/ store.
# /platform-skills:self-improve calls these instead of asking the model to
# parse entries, do date arithmetic, or edit instruction files by hand.
#
#   whereami                         workspace, scope and project name
#   entries                          one TSV record per entry
#   lint                             validate entries; report expired and stale
#   set-status ID STATUS [--note T]  rewrite one entry's Status line
#   promote ID --domain D --rule T [--target F] [--allow-inferred] [--apply]
#   unpromote ID [--revoke] [--note T]
#   recall [--all] [--limit N] TERM...
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
# Normalised to what lint accepts ([A-Za-z0-9._-]+), because a directory name
# may contain a space or anything else. self-improve-hook.sh normalises
# identically when it writes a scope, so promote's comparison still matches.
project_name() {
  local top name
  top="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null)" || top=""
  name="$(basename "${top:-$PROJECT}")"
  name="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-')"
  printf '%s\n' "${name:-project}"
}

learning_files() {
  local f
  for f in LEARNINGS.md ERRORS.md FEATURE_REQUESTS.md; do
    [ -f "$BASE/.learnings/$f" ] && printf '%s\n' "$BASE/.learnings/$f"
  done
}

# set_learning_files — put the store's files in "$@". `set --` is local to the
# function that runs it, so each consumer repeats these three lines rather than
# calling a helper. Passing the list unquoted would split it on spaces, and
# $BASE derives from $HOME or $CLAUDE_PROJECT_DIR, either of which can contain
# one: "/Users/Alex Smith/repo" then reaches awk as two missing files.
# Positional parameters, not an array: bash 3.2 treats an empty "${arr[@]}"
# as unbound under set -u.

# ── entries ───────────────────────────────────────────────────────────────────
# TSV columns: 1 id, 2 file, 3 line, 4 status, 5 source, 6 scope, 7 paths,
# 8 verified, 9 expires, 10 supersedes, 11 context, 12 content, 13 action.
# Empty columns are real empties, so consume this with awk -F'\t', never
# with `read`: IFS whitespace would collapse adjacent tabs.
cmd_entries() {
  local f
  set --
  while IFS= read -r f; do
    [ -z "$f" ] || set -- "$@" "$f"
  done < <(learning_files)
  [ $# -gt 0 ] || return 0
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
  ' "$@"
}

# Shared awk: date helpers and the staleness policy. A verified date older
# than the window for its source needs re-verifying. User statements don't
# go stale; inferences go stale fastest.
AWK_LIB='
  function valid_date(s,   y, m, d, limit) {
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m < 1 || m > 12 || d < 1) return 0
    # A day limit of 31 for every month accepted 2026-02-31, which then took
    # part in staleness and expiry arithmetic as though it were a real date.
    limit = 31
    if (m == 4 || m == 6 || m == 9 || m == 11) limit = 30
    else if (m == 2) limit = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
    return d <= limit
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
      # Promotion needs all three of Source, Scope and Verified, so an entry
      # missing any one of them is one that promote will refuse. Counting only
      # the entries missing both Source and Verified hid the rest.
      if (source == "" || scope == "" || verified == "") legacy++
      if (!has(active, status)) next
      if (is_expired(expires, today)) { printf "EXPIRED %s expired %s\n", id, expires; expired++ }
      age = stale_age(verified, source, today)
      if (age >= 0) {
        # Buffered rather than printed here, so a stale promoted entry is
        # reported before the others however the store happens to be ordered.
        # Its rule is loaded into every session, which makes it the one to
        # re-verify first.
        line = sprintf("STALE %s verified %d days ago (limit %d for source %s)%s\n", id, age, window(source),
          (source == "" ? "unknown" : source), (status == "promoted" ? "; its promoted rule is still loaded" : ""))
        if (status == "promoted") stale_promoted = stale_promoted line
        else stale_other = stale_other line
        stale++
      }
    }
    END {
      for (id in sup_of) {
        old = sup_of[id]
        if (!(old in state)) err(id, "supersedes unknown id " old)
        else if (state[old] != "superseded") warn(id, "supersedes " old ", which is still " state[old])
      }
      printf "%s%s", stale_promoted, stale_other
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

# need_arg <remaining-argc> <option> — an option that takes a value must have
# one. Without this check `shift 2` on a single remaining argument fails and,
# because the script does not use set -e, leaves the same option at $1: the
# parse loop then spins forever instead of reporting a usage error.
need_arg() {
  [ "$1" -ge 2 ] || die 2 "$2 needs a value"
}

# acquire_lock <file> — the same exclusive-create lock as
# self-improve-hook.sh, so a rewrite here never races the SessionEnd drain
# appending to ERRORS.md. Reclaiming a stale lock with `rm` then recreate is
# not safe: between this process's staleness check and its `rm`, another
# process can reclaim the same stale lock and start work, and the `rm` then
# deletes that live lock. Claim by rename instead — only one racer can move
# the lock aside — and re-check the claim's age, putting it back if what we
# moved turned out to be a live lock created inside that window.
acquire_lock() {
  if ( set -C; : > "$1" ) 2>/dev/null; then return 0; fi
  if [ -n "$(find "$1" -mmin +10 2>/dev/null)" ]; then
    local claim="$1.claim.$$"
    if mv "$1" "$claim" 2>/dev/null; then
      if [ -n "$(find "$claim" -mmin +10 2>/dev/null)" ]; then
        rm -f "$claim"
        ( set -C; : > "$1" ) 2>/dev/null && return 0
      else
        mv "$claim" "$1" 2>/dev/null
      fi
    fi
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

# Workspace lock ownership. A command that mutates a rule file and then the
# entry that owns it must hold one lock across both, so held state lives here
# rather than in the command that happens to take it first. The EXIT trap in
# main() releases it, so a `die` on any path cannot leak the lock.
LOCK=""

lock_workspace() {
  [ -z "$LOCK" ] || return 0
  local l="$BASE/.learnings/.drain.lock"
  acquire_lock_wait "$l" || die 3 "workspace busy: $l is held"
  LOCK="$l"
}

unlock_workspace() {
  [ -n "$LOCK" ] || return 0
  rm -f "$LOCK"
  LOCK=""
}

entry_file() {
  local id="$1" f
  set --
  while IFS= read -r f; do
    [ -z "$f" ] || set -- "$@" "$f"
  done < <(learning_files)
  [ $# -gt 0 ] || return 0
  grep -lx "### $id" "$@" 2>/dev/null | head -1
}

# rewrite_entry <file> <id> <status> <note> — replace the entry's Status line
# and its Status-Note (dropped when <note> is empty). Temp file + mv, so a
# reader never sees half a file. An entry with no **Status** line would
# otherwise be copied through unchanged and reported as rewritten, so the awk
# exits 3 when it never matched one and the file is left alone.
rewrite_entry() {
  local tmp rc
  tmp="$(mktemp "$1.XXXXXX")" || return 1
  ID="$2" STATUS="$3" NOTE="$4" TODAY="$TODAY" awk '
    BEGIN { id = ENVIRON["ID"]; status = ENVIRON["STATUS"]; note = ENVIRON["NOTE"]; today = ENVIRON["TODAY"] }
    $0 == "### " id { inside = 1; print; next }
    inside && (/^#/ || /^---[[:space:]]*$/) { inside = 0 }
    inside && /^\*\*Status-Note\*\*:/ { next }
    inside && /^\*\*Status\*\*:/ {
      print "**Status**: " status
      if (note != "") print "**Status-Note**: " today " " note
      done = 1
      next
    }
    { print }
    END { if (!done) exit 3 }
  ' "$1" > "$tmp"
  rc=$?
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return "$rc"; }
  mv -f "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

# set_status <id> <status> <note> — the lock-free core, so a command that
# already holds the workspace lock can rewrite an entry without deadlocking
# against itself and can act on the failure instead of exiting. Returns 4 for
# an unknown id, 3 for an entry with no Status line, 1 for a write failure.
set_status() {
  local file
  file="$(entry_file "$1")"
  [ -n "$file" ] || return 4
  rewrite_entry "$file" "$1" "$2" "$3"
}

cmd_set_status() {
  local id="${1:-}" status="${2:-}" note="" rc=0
  [ -n "$id" ] && [ -n "$status" ] || die 2 "usage: set-status ID STATUS [--note TEXT]"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --note) need_arg $# "$1"; note="$(printf '%s' "$2" | tr '\t\r\n' '   ')"; shift 2 ;;
      *) die 2 "set-status: unknown option $1" ;;
    esac
  done
  in_list "$status" "$ALL_STATUSES" && [ "$status" != "example" ] || die 2 "unknown status $status"
  lock_workspace
  set_status "$id" "$status" "$note" || rc=$?
  unlock_workspace
  case "$rc" in
    0) ;;
    4) die 4 "no entry $id" ;;
    3) die 1 "$id has no **Status** line to rewrite" ;;
    *) die 1 "could not rewrite the file holding $id" ;;
  esac
  echo "$id: status $status"
}

# ── promote / unpromote ───────────────────────────────────────────────────────
# A promoted rule is one line ending in a marker comment naming its entry:
#   - Never apply a plan that says "forces replacement" on RDS <!-- self-improve:ERR-20260901-001 -->
# The marker makes a promotion traceable and removable (unpromote) without
# guessing which line came from which lesson.
REC=""

# entry_record <id> — that entry's TSV record, or nothing.
entry_record() {
  cmd_entries | ID="$1" awk -F'\t' '$1 == ENVIRON["ID"] { print; exit }'
}

# col <n> — column n of the record in REC.
col() {
  printf '%s\n' "$REC" | awk -F'\t' -v n="$1" '{ print $n }'
}

# norm_paths — comma list on stdin to sorted, trimmed, comma-joined.
norm_paths() {
  tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort | paste -sd, -
}

# frontmatter_paths <file> — the rule file's `paths:` as norm_paths output.
# Reads the YAML list form and the comma-separated string form.
frontmatter_paths() {
  awk '
    NR == 1 { if ($0 != "---") exit; fm = 1; next }
    fm && /^---[[:space:]]*$/ { exit }
    fm && /^paths:[[:space:]]*$/ { inlist = 1; next }
    fm && /^paths:[[:space:]]*[^[:space:]]/ {
      v = $0; sub(/^paths:[[:space:]]*/, "", v); gsub(/"/, "", v); print v; inlist = 0; next
    }
    fm && inlist && /^[[:space:]]*-/ {
      v = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); gsub(/^"|"$/, "", v); print v; next
    }
    fm && /^[^[:space:]]/ { inlist = 0 }
  ' "$1" | norm_paths
}

rule_candidates() {
  find "$HOME/.claude/rules" "$PROJECT/.claude/rules" -type f -name '*.md' 2>/dev/null
  printf '%s\n' "$HOME/.claude/CLAUDE.md" "$PROJECT/CLAUDE.md" "$PROJECT/AGENTS.md" \
    "$PROJECT/.github/copilot-instructions.md"
}

cmd_promote() {
  local id="${1:-}" domain="" rule="" target="" allow_inferred=0 apply=0
  [ -n "$id" ] || die 2 "usage: promote ID --domain D --rule TEXT [--target FILE] [--allow-inferred] [--apply]"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --domain) need_arg $# "$1"; domain="$2"; shift 2 ;;
      --rule) need_arg $# "$1"; rule="$(printf '%s' "$2" | tr '\t\r\n' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"; shift 2 ;;
      --target) need_arg $# "$1"; target="$2"; shift 2 ;;
      --allow-inferred) allow_inferred=1; shift ;;
      --apply) apply=1; shift ;;
      *) die 2 "promote: unknown option $1" ;;
    esac
  done

  REC="$(entry_record "$id")"
  [ -n "$REC" ] || die 4 "no entry $id"
  local status source scope paths verified expires verdict project
  status="$(col 4)"; source="$(col 5)"; scope="$(col 6)"; paths="$(col 7)"
  verified="$(col 8)"; expires="$(col 9)"

  # ── Eligibility: promotion changes agent behaviour, so it needs evidence ──
  case "$status" in
    resolved|promoted) ;;
    pending) die 4 "$id is pending; resolve it before promoting" ;;
    *) die 4 "$id is $status; only resolved entries can be promoted" ;;
  esac
  if [ -z "$source" ] || [ -z "$scope" ] || [ -z "$verified" ]; then
    die 4 "$id has no **Source**, **Scope** or **Verified**; add them before promoting"
  fi
  # Non-empty is not enough. lint rejects an unknown source, a malformed scope,
  # an impossible **Verified** date and **Paths** on a global entry; promotion
  # has to apply the same rules or it becomes the way around them. One reason at
  # a time, because the first is what has to be fixed anyway.
  local bad
  bad="$(printf '%s\n' "$REC" | awk -F'\t' "$AWK_LIB"'
    function has(list, word) { return index(" " list " ", " " word " ") > 0 }
    {
      if (!has("user observed ci repo vendor-docs inferred", $5))
        print "**Source** is \"" $5 "\"; use user, observed, ci, repo, vendor-docs or inferred"
      else if ($6 != "global" && $6 !~ /^project:[A-Za-z0-9._-]+$/)
        print "**Scope** is \"" $6 "\"; use global or project:<name>"
      else if (!valid_date($8))
        print "**Verified** is \"" $8 "\"; use a real YYYY-MM-DD date"
      else if ($9 != "" && $9 != "never" && !valid_date($9))
        print "**Expires** is \"" $9 "\"; use a real YYYY-MM-DD date or never"
      else if ($7 != "" && $6 !~ /^project:/)
        print "**Paths** needs a project:<name> scope"
      else if ($7 != "" && ($7 ~ /"/ || $7 ~ /(^|,)[[:space:]]*(,|$)/))
        print "**Paths** is \"" $7 "\"; use comma-separated globs, no quotes"
    }')"
  [ -z "$bad" ] || die 4 "$id: $bad (learnings.sh lint reports it too)"
  if [ "$source" = "inferred" ] && [ "$allow_inferred" -eq 0 ]; then
    die 4 "$id comes from an inference; confirm it with the user and re-run with --allow-inferred"
  fi
  verdict="$(printf '%s\n' "$REC" | TODAY="$TODAY" awk -F'\t' "$AWK_LIB"'
    { if (is_expired($9, ENVIRON["TODAY"])) print "expired"
      else if (stale_age($8, $5, ENVIRON["TODAY"]) >= 0) print "stale" }')"
  [ "$verdict" != "expired" ] || die 4 "$id expired on $expires"
  [ "$verdict" != "stale" ] || die 4 "$id was last verified $verified; re-verify it and update **Verified** first"
  case "$domain" in
    ""|-*|*[!a-z0-9-]*) die 2 "--domain must be lowercase letters, digits and dashes, e.g. terraform" ;;
  esac
  [ -n "$rule" ] || die 2 "--rule is required: one imperative line"
  [ "${#rule}" -le 160 ] || die 2 "--rule is ${#rule} characters; keep it to 160"
  case "$rule" in *"<!--"*|*"-->"*) die 2 "--rule must not contain an HTML comment" ;; esac
  project="$(project_name)"
  case "$scope" in
    project:*) [ "${scope#project:}" = "$project" ] || die 4 "$id is scoped to ${scope#project:}, but this project is $project" ;;
  esac

  # ── Target ────────────────────────────────────────────────────────────────
  # A rule file path is derived from scope and domain, never taken from the
  # command line, and an explicit --target names one of exactly three
  # project-local instruction files, matched literally. Matching a suffix
  # pattern against "$PROJECT/$target" instead accepted both an absolute path
  # and one containing "..", which writes a rule outside the project that
  # unpromote can never find: rule_candidates only searches the two rules
  # directories and those instruction files.
  local kind
  if [ -z "$target" ]; then
    kind="rules"
    if [ "$scope" = "global" ]; then target="$HOME/.claude/rules/$domain.md"; else target="$PROJECT/.claude/rules/$domain.md"; fi
  else
    case "$target" in
      CLAUDE.md|AGENTS.md|.github/copilot-instructions.md) kind="section"; target="$PROJECT/$target" ;;
      *) die 2 "--target must be CLAUDE.md, AGENTS.md or .github/copilot-instructions.md as a project-relative path; omit it to write .claude/rules/$domain.md" ;;
    esac
  fi
  [ "$kind" = "rules" ] || [ -z "$paths" ] || die 4 "$id has **Paths**; only a .claude/rules/ target can scope a rule to paths"

  # Applying takes the workspace lock before reading the target and keeps it
  # until the entry is rewritten. Writing the rule first and locking afterwards
  # left two failure modes: a busy workspace installed the rule and then exited
  # 3 with the entry still `resolved`, and two promotions reading the same
  # target could each overwrite the other's rule while both entries said
  # `promoted`.
  local marker="<!-- self-improve:$id -->" line
  line="- $rule $marker"
  [ "$apply" -eq 0 ] || lock_workspace
  if [ -f "$target" ] && grep -qF "$marker" "$target"; then
    echo "$id is already promoted to $target"
    if [ "$apply" -eq 1 ] && [ "$status" != "promoted" ]; then
      set_status "$id" promoted "promoted to $target" || die 1 "could not record the status of $id"
    fi
    unlock_workspace
    return 0
  fi
  # Past that point the marker is not in this target, so an entry that already
  # says `promoted` is promoted somewhere else. Writing here would leave one
  # entry owning two active rules while **Status-Note** recorded only the last,
  # and unpromoting would then remove whichever the note did not name.
  if [ "$status" = "promoted" ]; then
    die 4 "$id is already promoted, and $target does not carry its marker; run unpromote $id first"
  fi

  # ── Proposed file content ─────────────────────────────────────────────────
  local proposed want have
  proposed="$(mktemp "${TMPDIR:-/tmp}/learnings-promote.XXXXXX")" || die 1 "mktemp failed"
  if [ "$kind" = "rules" ]; then
    want="$(printf '%s' "$paths" | norm_paths)"
    if [ -f "$target" ]; then
      have="$(frontmatter_paths "$target")"
      if [ "$have" != "$want" ]; then
        rm -f "$proposed"
        die 4 "$target applies to paths [${have:-all files}] but $id needs [${want:-all files}]; choose another --domain"
      fi
      { cat "$target"; [ -z "$(tail -c1 "$target")" ] || echo; printf '%s\n' "$line"; } > "$proposed"
    else
      {
        if [ -n "$want" ]; then
          printf -- '---\npaths:\n'
          printf '%s\n' "$want" | tr ',' '\n' | sed 's/.*/  - "&"/'
          printf -- '---\n\n'
        fi
        printf '# %s rules\n\n%s\n' "$(printf '%s' "$domain" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')" "$line"
      } > "$proposed"
    fi
  elif [ -f "$target" ]; then
    # Insert at the end of the "## Agent Rules" section, creating it if absent.
    LINE="$line" awk '
      { lines[NR] = $0 }
      /^## Agent Rules[[:space:]]*$/ && !start { start = NR }
      END {
        if (!start) {
          for (i = 1; i <= NR; i++) print lines[i]
          if (NR > 0 && lines[NR] != "") print ""
          print "## Agent Rules"; print ""; print ENVIRON["LINE"]
          exit
        }
        stop = NR + 1
        for (i = start + 1; i <= NR; i++) if (lines[i] ~ /^# / || lines[i] ~ /^## /) { stop = i; break }
        at = stop - 1
        while (at > start && lines[at] == "") at--
        for (i = 1; i <= at; i++) print lines[i]
        if (at == start) print ""
        print ENVIRON["LINE"]
        for (i = at + 1; i <= NR; i++) print lines[i]
      }' "$target" > "$proposed"
  else
    printf '## Agent Rules\n\n%s\n' "$line" > "$proposed"
  fi

  if [ "$apply" -eq 0 ]; then
    local old="/dev/null"
    [ -f "$target" ] && old="$target"
    printf 'PROMOTION PROPOSAL %s\n' "$id"
    printf 'source=%s scope=%s verified=%s paths=%s\n' "$source" "$scope" "$verified" "${paths:-all files}"
    printf 'target=%s\n' "$target"
    diff -u "$old" "$proposed" | tail -n +3
    rm -f "$proposed"
    echo "Re-run with --apply to write it."
    return 0
  fi

  # Back the target up first, so a failure to record the status un-installs the
  # rule rather than leaving it loaded under an entry that never says promoted.
  # An absent backup means the target did not exist, so rolling back deletes it.
  local tmp backup="" rc=0
  mkdir -p "$(dirname "$target")" || { rm -f "$proposed"; die 1 "cannot create $(dirname "$target")"; }
  if [ -f "$target" ]; then
    backup="$(mktemp "$target.bak.XXXXXX")" || { rm -f "$proposed"; die 1 "cannot write next to $target"; }
    cp "$target" "$backup" || { rm -f "$proposed" "$backup"; die 1 "cannot back up $target"; }
  fi
  tmp="$(mktemp "$target.XXXXXX")" || { rm -f "$proposed" ${backup:+"$backup"}; die 1 "cannot write next to $target"; }
  if ! cat "$proposed" > "$tmp" || ! mv -f "$tmp" "$target"; then
    rm -f "$proposed" "$tmp" ${backup:+"$backup"}
    die 1 "could not write $target"
  fi
  rm -f "$proposed"
  set_status "$id" promoted "promoted to $target" || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -n "$backup" ]; then mv -f "$backup" "$target"; else rm -f "$target"; fi
    die 1 "could not record the status of $id; $target was left unchanged"
  fi
  rm -f ${backup:+"$backup"}
  unlock_workspace
  echo "promoted $id -> $target"
}

# restore_targets <newline-separated files> — put every already-rewritten rule
# file back from its .unpromote backup. Marking an entry revoked while a rule it
# installed is still loaded is the one outcome worth unwinding for: the entry
# then says the rule is gone when a session still reads it.
restore_targets() {
  local f
  [ -n "$1" ] || return 0
  printf '%s' "$1" | while IFS= read -r f; do
    [ -z "$f" ] || mv -f "$f.unpromote.$$" "$f" 2>/dev/null
  done
}

cmd_unpromote() {
  local id="${1:-}" revoke=0 note="unpromoted" marker f tmp changed="" new="resolved" rc=0 list
  [ -n "$id" ] || die 2 "usage: unpromote ID [--revoke] [--note TEXT]"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --revoke) revoke=1; shift ;;
      --note) need_arg $# "$1"; note="$2"; shift 2 ;;
      *) die 2 "unpromote: unknown option $1" ;;
    esac
  done
  REC="$(entry_record "$id")"
  [ -n "$REC" ] || die 4 "no entry $id"
  local status
  status="$(col 4)"
  marker="<!-- self-improve:$id -->"
  lock_workspace
  # Newline-separated, because a rule file under $HOME or the project can sit in
  # a directory whose name contains a space.
  while IFS= read -r f; do
    if [ ! -f "$f" ] || ! grep -qF "$marker" "$f"; then continue; fi
    cp "$f" "$f.unpromote.$$" || { restore_targets "$changed"; die 1 "cannot back up $f"; }
    tmp="$(mktemp "$f.XXXXXX")" || { rm -f "$f.unpromote.$$"; restore_targets "$changed"; die 1 "cannot write next to $f"; }
    # grep -v exits 1 when it selects no lines, which is a rule file that held
    # nothing but the marker. Only 2 and above is a real failure.
    grep -vF "$marker" "$f" > "$tmp"
    rc=$?
    if [ "$rc" -gt 1 ] || ! mv -f "$tmp" "$f"; then
      rm -f "$tmp" "$f.unpromote.$$"
      restore_targets "$changed"
      die 1 "could not rewrite $f"
    fi
    changed="$changed$f
"
  done < <(rule_candidates | sort -u)
  rc=0
  if [ -z "$changed" ]; then
    # An entry still reading `promoted` with no marker anywhere owns a rule this
    # command cannot find, so --revoke would record it as gone while sessions
    # keep loading it. Refuse until the pre-marker rule is removed by hand. A
    # markerless entry in any other status owns no rule, so --revoke is fine.
    if [ "$status" = "promoted" ]; then
      die 4 "no rule carries $marker but $id still reads promoted; remove its pre-marker rule by hand, then re-run"
    fi
    if [ "$revoke" -eq 0 ]; then
      die 4 "no rule carries $marker; a rule promoted before markers existed must be removed by hand"
    fi
  fi
  [ "$revoke" -eq 1 ] && new="revoked"
  list="$(printf '%s' "$changed" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  set_status "$id" "$new" "$note${list:+ (removed from $list)}" || rc=$?
  if [ "$rc" -ne 0 ]; then
    restore_targets "$changed"
    die 1 "could not record the status of $id; no rule was removed"
  fi
  printf '%s' "$changed" | while IFS= read -r f; do
    [ -z "$f" ] || rm -f "$f.unpromote.$$"
  done
  unlock_workspace
  [ -z "$list" ] || echo "removed $id from: $list"
  echo "$id: status $new"
}

# ── recall ────────────────────────────────────────────────────────────────────
# Read-only search. Excludes what should no longer influence behaviour
# (revoked, superseded, discarded, expired, another project's lessons) and
# says how many it excluded, so a hidden memory is never a silent one.
# Scoring is deliberately simple and explainable: +2 per term found in the
# Content, +1 in the Context, +5 for an exact id.
cmd_recall() {
  local all=0 limit=8 terms="" ranked summary matched nexcl reasons tab
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1; shift ;;
      --limit) need_arg $# "$1"; limit="$2"; shift 2 ;;
      *) terms="$terms $1"; shift ;;
    esac
  done
  case "$limit" in ""|*[!0-9]*) die 2 "--limit must be a number" ;; esac
  terms="$(printf '%s' "$terms" | tr '[:upper:]' '[:lower:]' | tr -s ' \t' '  ' | sed 's/^ //; s/ $//')"
  [ -n "$terms" ] || die 2 "usage: recall [--all] [--limit N] TERM..."
  ranked="$(mktemp "${TMPDIR:-/tmp}/learnings-recall.XXXXXX")" || die 1 "mktemp failed"
  summary="$(cmd_entries | TODAY="$TODAY" TERMS="$terms" ALL="$all" HERE="$(project_name)" OUT="$ranked" \
    awk -F'\t' "$AWK_LIB"'
    BEGIN {
      today = ENVIRON["TODAY"]; all = ENVIRON["ALL"] + 0; here = ENVIRON["HERE"]; out = ENVIRON["OUT"]
      nt = split(ENVIRON["TERMS"], t, " ")
    }
    {
      id = $1; status = $4; source = $5; scope = $6
      if (status == "example") next
      ctx = tolower($11); body = tolower($12); score = 0
      for (i = 1; i <= nt; i++) {
        if (length(t[i]) < 2) continue
        if (index(body, t[i])) score += 2
        if (index(ctx, t[i])) score += 1
        if (tolower(id) == t[i]) score += 5
      }
      if (score == 0) next
      reason = ""
      if (status == "revoked" || status == "superseded" || status == "discarded") reason = status
      else if (is_expired($9, today)) reason = "expired"
      else if (scope ~ /^project:/ && substr(scope, 9) != here) reason = "other-project"
      if (reason != "" && !all) { excluded[reason]++; nexcl++; next }
      flags = (reason != "") ? " " toupper(reason) : ""
      if (stale_age($8, source, today) >= 0) flags = flags " STALE"
      if (source == "" || source == "inferred") flags = flags " | verify before use"
      content = $12
      if (length(content) > 160) content = substr(content, 1, 157) "..."
      key = id; sub(/^[A-Z]+-/, "", key)
      printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", score, key, id, status,
        (source == "" ? "unknown" : source), ($8 == "" ? "unknown" : $8),
        (scope == "" ? "unknown" : scope), flags, content > out
      matched++
    }
    END {
      split("revoked superseded discarded expired other-project", order, " ")
      s = ""
      for (i = 1; i <= 5; i++) if (excluded[order[i]]) s = s (s == "" ? "" : ", ") excluded[order[i]] " " order[i]
      printf "%d\t%d\t%s\n", matched, nexcl, s
    }')"
  matched="$(printf '%s' "$summary" | cut -f1)"
  nexcl="$(printf '%s' "$summary" | cut -f2)"
  reasons="$(printf '%s' "$summary" | cut -f3)"
  local note=""
  [ "${nexcl:-0}" -gt 0 ] && note=" ($nexcl excluded: $reasons; --all shows them)"
  if [ "${matched:-0}" -eq 0 ]; then
    printf 'recall: no matches for "%s"%s\n' "$terms" "$note"
  else
    printf 'recall: %s match(es) for "%s"%s\n' "$matched" "$terms" "$note"
    tab="$(printf '\t')"
    sort -t "$tab" -k1,1nr -k2,2r "$ranked" | head -n "$limit" | awk -F'\t' '
      { printf "[%s] %s %s | source=%s verified=%s | scope=%s%s\n    %s\n", $1, $3, $4, $5, $6, $7, $8, $9 }'
  fi
  rm -f "$ranked"
}

# ── whereami ──────────────────────────────────────────────────────────────────
cmd_whereami() {
  local scope="project"
  [ "$BASE" = "$HOME/.claude" ] && scope="global"
  printf 'base=%s\nscope=%s\nproject=%s\ntoday=%s\n' "$BASE" "$scope" "$(project_name)" "$TODAY"
}

main() {
  # The lock is released however the script leaves, so no `die` path can leave
  # the workspace looking busy to the next command.
  trap 'unlock_workspace' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) need_arg $# "$1"; BASE="$2"; shift 2 ;;
      --today) need_arg $# "$1"; TODAY="$2"; shift 2 ;;
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
    promote)    cmd_promote "$@" ;;
    unpromote)  cmd_unpromote "$@" ;;
    recall)     cmd_recall "$@" ;;
    *) die 2 "usage: learnings.sh [--base DIR] [--today D] <subcommand> (see the header of this script)" ;;
  esac
}

main "$@"
