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

## Usage

```bash
# Copy into your project root
cp -r examples/agent-self-improve/.learnings .
cp -r examples/agent-self-improve/memory .

# Or run the init command
# /platform-skills:self-improve init
```

Add to `.gitignore` for personal-only notes:
```
.learnings/
memory/working-buffer.md
```

Commit the directory if you want the team to share and build on these learnings.

## Reference

- How it works (concepts, lifecycle, examples): [examples/agent-self-improve/HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- Full protocol reference: [references/agent-self-improve.md](../../references/agent-self-improve.md)
- Slash command specification: [commands/self-improve.md](../../commands/self-improve.md)
