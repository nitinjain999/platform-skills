# Global Claude Rules

Copy this file to `~/.claude/CLAUDE.md` to apply these rules across every project and session.

---

## Session Start

When the session-start banner fires (╔══╗ from the PreToolUse hook), immediately read:

1. `~/.claude/memory/working-buffer.md` — resume any incomplete task
2. `~/.claude/memory/SESSION-STATE.md` — reload corrections and preferences
3. `~/.claude/memory/YYYY-MM-DD.md` (today's date) — today's daily notes, if it exists

Do this **before** answering the user's first message. If an incomplete task is found,
surface it: "I see an incomplete task from last session: [task]. Shall I resume or start fresh?"

---

## In-Session Logging

Log learnings and errors **at the moment they occur**, not at session end:

- Correct an assumption → `/platform-skills:self-improve state`
- Discover a useful technique → `/platform-skills:self-improve log LRN`
- Make a mistake or wrong assumption → `/platform-skills:self-improve log ERR`
- Hit an unmet need in the toolset → `/platform-skills:self-improve log FEAT`

Do not defer — context compaction will erase it.

---

## Agent Behaviour Settings

```
VFM_THRESHOLD=60
```

---

## Agent Rules

Rules promoted from `~/.claude/.learnings/` — add your own as you promote entries.

- Always clarify global vs project scope before scaffolding directories.
- Dispatch all independent tool calls in a single message block — sequential only when output feeds the next.
