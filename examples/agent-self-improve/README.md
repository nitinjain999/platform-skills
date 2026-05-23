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

## Reference

- How it works (concepts, lifecycle, examples): [examples/agent-self-improve/HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- Full protocol reference: [references/agent-self-improve.md](../../references/agent-self-improve.md)
- Slash command specification: [commands/self-improve.md](../../commands/self-improve.md)
