#!/usr/bin/env bash
# self-improve-hook.sh — Claude Code lifecycle hooks for the self-improve
# workspace. One script, three subcommands, each wired to a native event:
#
#   session-start  SessionStart. Plain stdout becomes context Claude sees.
#   session-end    SessionEnd. Cannot block. All SessionEnd hooks share a
#                  1.5 s budget unless the hook sets a longer "timeout".
#   tool-failure   PostToolUseFailure, wired with "async": true. PostToolUse
#                  never fires for a failed tool.
#
# Hook input arrives as JSON on stdin; Claude Code sets no CLAUDE_TOOL_* env
# vars. Every path exits 0: a memory hook must never block a session, a tool
# call, or compaction.
#
# Workspace resolution matches commands/self-improve.md: ~/.claude/.learnings
# wins, then $CLAUDE_PROJECT_DIR/.learnings. With neither, the hook does
# nothing and creates nothing.
#
# Requires bash 3.2+. jq is optional; without it a sed fallback reads the few
# scalar fields used here.

set -u

# Strings that only the legacy Stop/PreToolUse/PostToolUse wiring contained.
LEGACY_HOOK_PATTERN='session-start-reminder|session-end\.(sh|ps1)|CLAUDE_TOOL_EXIT_CODE'

resolve_base() {
  local project="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [ -d "$HOME/.claude/.learnings" ]; then
    printf '%s\n' "$HOME/.claude"
  elif [ -d "$project/.learnings" ]; then
    printf '%s\n' "$project"
  fi
}

# json_field <json> <key> — print a top-level scalar, or nothing. The sed
# fallback takes the last match of the key anywhere in the payload, so a
# nested key of the same name can win; that is why jq is preferred.
json_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg k "$2" \
      'if type == "object" and has($k) then .[$k] | tostring else empty end' 2>/dev/null
  else
    printf '%s' "$1" | tr -d '\n' |
      sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p"
  fi
}

# sanitize — keep only characters that cannot forge a log line or break a
# Markdown heading. Tool names, session ids and end reasons all fit.
sanitize() {
  tr -cd 'A-Za-z0-9_.:-' | cut -c1-128
}

display_path() {
  case "$1" in
    "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# last_err_number <errors-file> <yyyymmdd> — highest ERR number used today,
# or 0. Counting headings would reuse an id after a deletion, and the legacy
# `grep -c ... || echo 0` produced "0\n0" whenever nothing matched.
last_err_number() {
  local n
  [ -f "$1" ] || { echo 0; return; }
  n="$(grep -o "^### ERR-$2-[0-9][0-9]*" "$1" 2>/dev/null | sed 's/.*-//' | sort -n | tail -1)"
  echo $((10#${n:-0}))
}

# append_err <errors-file> <number> <yyyymmdd> <context> <content> <action>
append_err() {
  printf '\n### ERR-%s-%03d\n**Status**: pending\n**Context**: %s\n**Content**: %s\n**Action**: %s\n' \
    "$3" "$2" "$4" "$5" "$6" >> "$1"
}

# acquire_lock <file> — exclusive create (noclobber is O_EXCL), so two
# sessions ending together never both drain or both pick the same ERR id.
# A lock older than 10 minutes is presumed left by a killed session. Atomic
# claim via rename closes the two-party race where both processes see the
# same stale lock: only one process can successfully mv the lock to its own
# private name. After claiming, re-verify the claim was actually stale
# before recreating, since a second racer's own claim attempt might land
# after we already replaced the lock with a live one — if so, put it back
# rather than destroying an active lock.
acquire_lock() {
  if ( set -C; : > "$1" ) 2>/dev/null; then return 0; fi
  if [ -n "$(find "$1" -mmin +10 2>/dev/null)" ]; then
    local claim="$1.claim.$$"
    if mv "$1" "$claim" 2>/dev/null; then
      if [ -n "$(find "$claim" -mmin +10 2>/dev/null)" ]; then
        rm -f "$claim"
        ( set -C; : > "$1" ) 2>/dev/null && return 0
      else
        # What we claimed turned out to be a live lock someone else just
        # created between our staleness check and our mv; give it back.
        # (A third racer landing in this exact window could still clobber
        # this restore — accepted residual risk; see the comment this
        # replaces for the two-party race this DOES close.)
        mv "$claim" "$1" 2>/dev/null
      fi
    fi
  fi
  return 1
}

cmd_tool_failure() {
  local payload="$1" base tool session use_id
  base="$(resolve_base)"
  [ -n "$base" ] || return 0
  # A user interrupt is not a failure worth learning from.
  if [ "$(json_field "$payload" is_interrupt)" = "true" ]; then return 0; fi
  tool="$(json_field "$payload" tool_name | sanitize)"
  session="$(json_field "$payload" session_id | sanitize)"
  use_id="$(json_field "$payload" tool_use_id | sanitize)"
  # Never persist "error" or "tool_input": either can carry credentials. One
  # short line per append keeps concurrent async writers from interleaving.
  printf '%s TOOL_FAILURE: %s session=%s tool_use_id=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${tool:-unknown}" "${session:-unknown}" "${use_id:-unknown}" \
    >> "$base/.learnings/.pending-errors.log" 2>/dev/null
}

cmd_session_end() {
  local payload="$1" base mem lrn today stamp now reason
  local daily state buffer errors pending draining counter lock tmp lines
  local n count ts tool session use_id content
  base="$(resolve_base)"
  [ -n "$base" ] || return 0
  mem="$base/memory"
  lrn="$base/.learnings"
  mkdir -p "$mem" 2>/dev/null
  today="$(date +%Y-%m-%d)"
  stamp="$(date +%Y%m%d)"
  now="$(date +%H:%M)"
  reason="$(json_field "$payload" reason | sanitize)"
  daily="$mem/$today.md"
  state="$mem/SESSION-STATE.md"
  buffer="$mem/working-buffer.md"
  errors="$lrn/ERRORS.md"
  pending="$lrn/.pending-errors.log"
  draining="$lrn/.pending-errors.draining"
  counter="$mem/.session-count"
  lock="$lrn/.drain.lock"

  # ── Daily note ──────────────────────────────────────────────────────────────
  [ -f "$daily" ] || printf '# Daily Notes — %s\n\n' "$today" > "$daily"
  printf '\n## Session closed: %s (%s)\n\n' "$now" "${reason:-unknown}" >> "$daily"
  if [ -f "$state" ]; then
    lines="$(grep "^- $today" "$state" 2>/dev/null)"
    [ -n "$lines" ] && printf '### State captured today:\n\n%s\n' "$lines" >> "$daily"
  fi
  if [ -f "$buffer" ]; then
    lines="$(grep '^- \[ \]' "$buffer" 2>/dev/null)"
    [ -n "$lines" ] && printf '\n### Incomplete steps (resume next session):\n\n%s\n' "$lines" >> "$daily"
  fi

  # ── ERRORS.md writes, under the drain lock ──────────────────────────────────
  # If a parallel session holds the lock, it owns this drain; pending lines
  # stay for the next SessionEnd and the banner keeps counting them.
  if acquire_lock "$lock"; then
    # Rename before reading: an async tool-failure hook that fires mid-drain
    # appends to a fresh log instead of racing this loop. A .draining file
    # left behind by an interrupted run is drained here too.
    if [ -s "$pending" ] && tmp="$(mktemp "$lrn/.pending-errors.XXXXXX" 2>/dev/null)"; then
      if mv -f "$pending" "$tmp"; then
        cat "$tmp" >> "$draining" && rm -f "$tmp"
      else
        rm -f "$tmp"
      fi
    fi
    n="$(last_err_number "$errors" "$stamp")"
    if [ -s "$draining" ]; then
      # One entry per (tool, session): a run of failed Edits is one lesson,
      # not ten. Fields are whitespace-free by construction (the capture
      # sanitizes them), so tab-separated records are safe.
      while IFS=$'\t' read -r tool session ts use_id count; do
        n=$((n + 1))
        if [ "$count" -gt 1 ]; then
          content="\`$tool\` failed $count times (session $session, first tool_use_id $use_id)"
        else
          content="\`$tool\` failed (session $session, tool_use_id $use_id)"
        fi
        append_err "$errors" "$n" "$stamp" \
          "Tool failure captured by the PostToolUseFailure hook at $ts" "$content" \
          "Run \`/platform-skills:self-improve review\` to find the root cause in that session's transcript"
      done < <(awk '
        /TOOL_FAILURE: / {
          ts = $1
          rest = $0
          sub(/.*TOOL_FAILURE: /, "", rest)
          nf = split(rest, f, " ")
          tool = (nf >= 1 && f[1] != "") ? f[1] : "unknown"
          session = "unknown"; use_id = "unknown"
          for (i = 2; i <= nf; i++) {
            if (f[i] ~ /^session=./) session = substr(f[i], 9)
            else if (f[i] ~ /^tool_use_id=./) use_id = substr(f[i], 13)
          }
          key = tool SUBSEP session
          if (!(key in count)) {
            order[++keys] = key; name[key] = tool; sess[key] = session
            first_ts[key] = ts; first_id[key] = use_id
          }
          count[key]++
        }
        END {
          for (k = 1; k <= keys; k++) {
            key = order[k]
            printf "%s\t%s\t%s\t%s\t%d\n", name[key], sess[key], first_ts[key], first_id[key], count[key]
          }
        }' "$draining")
      rm -f "$draining"
    fi

    # Match a real WAL status line only. The buffer template's HTML comment
    # reads "**Status**: PENDING | COMMITTED | ROLLED_BACK" and must not count.
    if [ -f "$buffer" ] && grep -q '^\*\*Status\*\*: PENDING[[:space:]]*$' "$buffer" 2>/dev/null; then
      n=$((n + 1))
      append_err "$errors" "$n" "$stamp" \
        "Session closed with a PENDING WAL entry in working-buffer.md" \
        "A destructive operation was started but not confirmed as COMMITTED before the session ended" \
        "Run \`/platform-skills:self-improve resume\` next session to verify and update the WAL status"
    fi
    rm -f "$lock"
  fi

  # The legacy PreToolUse banner keyed off this marker; nothing reads it now.
  rm -f "$mem/.session-active"

  # ── Session counter and review reminder ─────────────────────────────────────
  count=0
  [ -f "$counter" ] && count="$(tr -cd '0-9' < "$counter")"
  count=$((10#${count:-0} + 1))
  printf '%s\n' "$count" > "$counter"
  if [ $((count % 5)) -eq 0 ]; then
    printf '\n### Review reminder (session %d):\n\nRun `/platform-skills:self-improve review`. 5 sessions have elapsed.\n' \
      "$count" >> "$daily"
  fi

  if ! grep -q "^### LRN-$stamp" "$lrn/LEARNINGS.md" 2>/dev/null; then
    printf -- '- No learnings logged today. Consider `/platform-skills:self-improve log` before the next session.\n' >> "$daily"
  fi
}

cmd_session_start() {
  local base mem today scope task count f project
  base="$(resolve_base)"
  [ -n "$base" ] || return 0
  mem="$base/memory"
  today="$(date +%Y-%m-%d)"
  project="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [ "$base" = "$HOME/.claude" ]; then scope="global"; else scope="project"; fi

  printf 'Self-improve workspace: %s (%s)\n' "$(display_path "$base")" "$scope"
  printf 'Read these before starting work:\n'
  printf '  1. %s (active task, WAL)\n' "$(display_path "$mem/working-buffer.md")"
  printf '  2. %s (corrections, preferences, decisions)\n' "$(display_path "$mem/SESSION-STATE.md")"
  if [ -f "$mem/$today.md" ]; then
    printf '  3. %s (today)\n' "$(display_path "$mem/$today.md")"
  fi

  if [ -f "$mem/working-buffer.md" ]; then
    task="$(awk '/^## Current Task/{found=1; next} found && /^[^#]/{print; exit}' \
      "$mem/working-buffer.md" | cut -c1-120)"
    case "$task" in
      ""|*"No active task"*) ;;
      *) printf 'Active task: %s\n' "$task" ;;
    esac
  fi

  if [ -s "$base/.learnings/.pending-errors.log" ]; then
    count="$(grep -c 'TOOL_FAILURE' "$base/.learnings/.pending-errors.log" 2>/dev/null)"
    printf 'WARNING: %s unprocessed tool failure(s) in %s. Run /platform-skills:self-improve review.\n' \
      "${count:-0}" "$(display_path "$base/.learnings/.pending-errors.log")"
  fi

  for f in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$project/.claude/settings.json" "$project/.claude/settings.local.json"; do
    # With the project at $HOME, the last two paths are the same files as the first two.
    if [ "$project" = "$HOME" ] && { [ "$f" = "$project/.claude/settings.json" ] || [ "$f" = "$project/.claude/settings.local.json" ]; }; then continue; fi
    if [ -f "$f" ] && grep -qE "$LEGACY_HOOK_PATTERN" "$f" 2>/dev/null; then
      printf 'WARNING: legacy self-improve hooks are still wired in %s. Remove its Stop, PreToolUse and PostToolUse self-improve entries (see "Migrating from the legacy hooks" in examples/agent-self-improve/README.md).\n' \
        "$(display_path "$f")"
    fi
  done
}

main() {
  local payload=""
  [ -t 0 ] || payload="$(cat)"
  case "${1:-}" in
    session-start) cmd_session_start "$payload" ;;
    session-end)  cmd_session_end "$payload" ;;
    tool-failure) cmd_tool_failure "$payload" ;;
    *) echo "usage: self-improve-hook.sh session-start|session-end|tool-failure" >&2 ;;
  esac
}

# Allow the script to be sourced for testing without executing main.
if [ "${1:-}" != "--source-only" ]; then
  main "$@"
  exit 0
fi
