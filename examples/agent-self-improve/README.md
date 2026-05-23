# Agent Self-Improvement — Examples

Status: Beta

This directory contains ready-to-copy templates for bootstrapping the self-improving agent pattern in any project.

## Contents

| File | Purpose |
|---|---|
| `.learnings/LEARNINGS.md` | Positive learnings log template |
| `.learnings/ERRORS.md` | Error and mistake log template |
| `.learnings/FEATURE_REQUESTS.md` | Recurring unmet needs log template |
| `memory/working-buffer.md` | WAL scratchpad and task state template |
| `memory/SESSION-STATE.md` | Always-on capture of corrections, preferences, decisions, proper nouns |
| `memory/YYYY-MM-DD.md` | Daily notes template — rename to actual date on first use |
| `scripts/session-end.sh` | Stop hook: drains errors, saves daily notes, session counter, review reminder |
| `scripts/session-start-reminder.sh` | PreToolUse hook: injects memory-load banner at first tool use each session |
| `global-claude.md` | Template for `~/.claude/CLAUDE.md` — path override, session-start, in-session logging rules |
| `settings.json.example` | All 3 hooks wired: Stop, PreToolUse, PostToolUse |

## Usage

The recommended approach is to run the init command — it asks whether you want global or project-local setup before creating anything:

```bash
/platform-skills:self-improve init
```

Or copy manually:

```bash
# Global setup — learnings persist across all projects (recommended for individuals)
cp -r examples/agent-self-improve/.learnings ~/.claude/
cp -r examples/agent-self-improve/memory ~/.claude/

# Project-local setup — learnings live in the repo, shareable with the team
cp -r examples/agent-self-improve/.learnings .
cp -r examples/agent-self-improve/memory .
```

For project-local setup, add to `.gitignore` for personal-only notes (recommended — daily notes grow fast):
```
.learnings/
memory/
```

Commit `.learnings/` only if you want the team to share and build on these learnings; keep `memory/` local.

### Wire the hooks (global setup)

```bash
# Copy scripts
mkdir -p ~/.claude/scripts
cp examples/agent-self-improve/scripts/session-end.sh ~/.claude/scripts/
cp examples/agent-self-improve/scripts/session-start-reminder.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/*.sh

# Copy settings (merge manually if ~/.claude/settings.json already exists)
cp examples/agent-self-improve/settings.json.example ~/.claude/settings.json

# Copy global CLAUDE.md
cp examples/agent-self-improve/global-claude.md ~/.claude/CLAUDE.md
```

What the hooks do:

| Hook | Trigger | What it does |
|---|---|---|
| `Stop` → `session-end.sh` | Session close | Saves daily notes, drains `.pending-errors.log` → ERR entries, clears session marker, increments counter, nudges if no LRN logged |
| `PreToolUse` → `session-start-reminder.sh` | First tool use per session | Prints memory-load banner once, silent after that |
| `PostToolUse` | Every failed tool call | Appends to `.pending-errors.log` for batch processing at session end |

## Reference

- How it works (concepts, lifecycle, examples): [examples/agent-self-improve/HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- Full protocol reference: [references/agent-self-improve.md](../../references/agent-self-improve.md)
- Slash command specification: [commands/self-improve.md](../../commands/self-improve.md)
