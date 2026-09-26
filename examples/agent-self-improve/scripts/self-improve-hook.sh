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

main() {
  local payload=""
  [ -t 0 ] || payload="$(cat)"
  case "${1:-}" in
    tool-failure) cmd_tool_failure "$payload" ;;
    *) echo "usage: self-improve-hook.sh session-start|session-end|tool-failure" >&2 ;;
  esac
}

main "$@"
exit 0
