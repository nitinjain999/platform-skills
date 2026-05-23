#!/usr/bin/env bash
# session-start-reminder.sh — wired to the PreToolUse hook in ~/.claude/settings.json
# Injects a memory-load reminder before the first tool use of each new session.
# Subsequent tool uses in the same session are silent (marker file controls this).
#
# Install: add to ~/.claude/settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": ".*", "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/session-start-reminder.sh" }] }] }

MEMORY_DIR="$HOME/.claude/memory"
SESSION_MARKER="$MEMORY_DIR/.session-active"
DATE=$(date '+%Y-%m-%d')

# Already active this session — stay silent
[ -f "$SESSION_MARKER" ] && exit 0

# Mark session as active to prevent repeat output on subsequent tool calls
touch "$SESSION_MARKER"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  SESSION START — load memory before proceeding           ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Read these files now:                                   ║"
echo "║  1. ~/.claude/memory/working-buffer.md  (active task)    ║"
echo "║  2. ~/.claude/memory/SESSION-STATE.md   (preferences)    ║"

if [ -f "$MEMORY_DIR/$DATE.md" ]; then
echo "║  3. ~/.claude/memory/$DATE.md  (today)      ║"
fi

# Surface active task if present
if [ -f "$MEMORY_DIR/working-buffer.md" ]; then
  TASK=$(awk '/^## Current Task/{found=1; next} found && /^[^#]/{print; exit}' \
    "$MEMORY_DIR/working-buffer.md" | tr -d '\n' | xargs)
  if [ -n "$TASK" ] && [[ "$TASK" != *"No active task"* ]]; then
    echo "║                                                          ║"
    printf "║  Active task: %-44s║\n" "$(echo "$TASK" | cut -c1-44)"
  fi
fi

# Warn if unprocessed tool errors are waiting
if [ -f "$HOME/.claude/.learnings/.pending-errors.log" ] && \
   [ -s "$HOME/.claude/.learnings/.pending-errors.log" ]; then
  COUNT=$(wc -l < "$HOME/.claude/.learnings/.pending-errors.log" | tr -d ' ')
  echo "║                                                          ║"
  printf "║  %-56s║\n" "WARNING: $COUNT unprocessed error(s) in .pending-errors.log"
fi

echo "╚══════════════════════════════════════════════════════════╝"
