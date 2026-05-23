#!/bin/bash
# session-end.sh — wired to the Stop hook in ~/.claude/settings.json
# Auto-captures session state, drains pending errors, and manages session lifecycle.
#
# Install: add to ~/.claude/settings.json:
#   "hooks": { "Stop": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/scripts/session-end.sh" }] }] }

DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M')
LEARNINGS_DIR="$HOME/.claude/.learnings"
MEMORY_DIR="$HOME/.claude/memory"
DAILY="$MEMORY_DIR/$DATE.md"
SESSION_STATE="$MEMORY_DIR/SESSION-STATE.md"
BUFFER="$MEMORY_DIR/working-buffer.md"
ERRORS_FILE="$LEARNINGS_DIR/ERRORS.md"
LEARNINGS_FILE="$LEARNINGS_DIR/LEARNINGS.md"
PENDING_LOG="$LEARNINGS_DIR/.pending-errors.log"
SESSION_MARKER="$MEMORY_DIR/.session-active"
SESSION_COUNTER="$MEMORY_DIR/.session-count"

mkdir -p "$LEARNINGS_DIR" "$MEMORY_DIR"

# ── Daily notes ───────────────────────────────────────────────────────────────
[ ! -f "$DAILY" ] && printf "# Daily Notes — %s\n\n" "$DATE" > "$DAILY"
printf "\n## Session closed: %s\n\n" "$TIME" >> "$DAILY"

if [ -f "$SESSION_STATE" ]; then
  TODAY_LINES=$(grep "^- $DATE" "$SESSION_STATE" 2>/dev/null)
  [ -n "$TODAY_LINES" ] && printf "### State captured today:\n\n%s\n" "$TODAY_LINES" >> "$DAILY"
fi

if [ -f "$BUFFER" ]; then
  INCOMPLETE=$(grep "^\- \[ \]" "$BUFFER" 2>/dev/null)
  [ -n "$INCOMPLETE" ] && printf "\n### Incomplete steps (resume next session):\n\n%s\n" "$INCOMPLETE" >> "$DAILY"
fi

# ── Drain .pending-errors.log → ERR entries ───────────────────────────────────
if [ -f "$PENDING_LOG" ] && [ -s "$PENDING_LOG" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TOOL_NAME=$(echo "$line" | sed 's/.*TOOL_FAILURE: //')
    TIMESTAMP=$(echo "$line" | cut -d' ' -f1)
    NNN=$(grep -c "^### ERR-${DATE//-/}" "$ERRORS_FILE" 2>/dev/null || echo 0)
    NNN=$(printf "%03d" $((NNN + 1)))
    ID="ERR-${DATE//-/}-$NNN"
    cat >> "$ERRORS_FILE" << EOF

### $ID
**Status**: pending
**Context**: Tool failure captured automatically via PostToolUse hook at $TIMESTAMP
**Content**: \`$TOOL_NAME\` returned a non-zero exit code during this session
**Action**: Run \`/platform-skills:self-improve review\` to investigate and resolve
EOF
  done < "$PENDING_LOG"
  > "$PENDING_LOG"
  echo "[session-end] Drained .pending-errors.log → $ERRORS_FILE"
fi

# ── Auto-log ERR for PENDING WAL entries ──────────────────────────────────────
if [ -f "$BUFFER" ] && grep -q "Status.*PENDING" "$BUFFER" 2>/dev/null; then
  NNN=$(grep -c "^### ERR-${DATE//-/}" "$ERRORS_FILE" 2>/dev/null || echo 0)
  NNN=$(printf "%03d" $((NNN + 1)))
  ID="ERR-${DATE//-/}-$NNN"
  cat >> "$ERRORS_FILE" << EOF

### $ID
**Status**: pending
**Context**: Session closed with PENDING WAL entry in working-buffer.md
**Content**: A destructive operation was started but not confirmed as COMMITTED before session ended
**Action**: Run \`/platform-skills:self-improve resume\` next session to verify and update WAL status
EOF
fi

# ── Clear session marker so next session triggers fresh memory load ───────────
rm -f "$SESSION_MARKER"

# ── Session counter — remind about /self-improve review every 5 sessions ─────
COUNT=1
[ -f "$SESSION_COUNTER" ] && COUNT=$(( $(cat "$SESSION_COUNTER") + 1 ))
echo "$COUNT" > "$SESSION_COUNTER"

if [ $(( COUNT % 5 )) -eq 0 ]; then
  printf "\n### Review reminder (session %d):\n\nRun \`/platform-skills:self-improve review\` — 5 sessions have elapsed.\n" "$COUNT" >> "$DAILY"
  echo "[session-end] Review reminder added (session $COUNT)"
fi

# ── Nudge if no learnings logged today ────────────────────────────────────────
LRN_TODAY=$(grep -c "^### LRN-${DATE//-/}" "$LEARNINGS_FILE" 2>/dev/null || echo 0)
if [ "$LRN_TODAY" -eq 0 ]; then
  echo "[session-end] No learnings logged today — consider /platform-skills:self-improve log before next session"
fi

echo "[session-end] Saved to $DAILY (session $COUNT)"
