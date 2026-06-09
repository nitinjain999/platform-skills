---
name: setup-agents
description: Scaffold a multi-agent AI setup for any repo. Scans the codebase, interviews the developer, generates agent configs for whichever AI tools the repo uses (Copilot, Claude Code, Cursor, Codex, Windsurf). Use when asked to "set up agents", "scaffold Copilot agents", or "create an AGENTS.md".
argument-hint: "[generate|upgrade|add|review]"
---

Scaffold a multi-agent AI configuration for any repo — any language, any framework.

Reference index: `references/setup-agents.md` — read this first. It routes to mode-specific files.

## Modes

- **generate** — fresh setup: ranked scan, interview, roster decision, generate all files
- **upgrade** — re-scan, read metadata from last session, git-diff, patch what's stale
- **add** — add one new agent without re-running the full interview
- **review** — quality check on 6 dimensions, output options at end

## Interactive wizard (no args)

```
What do you need?
  generate — fresh setup
  upgrade  — patch what's stale since last update
  add      — add one new agent
  review   — quality check, no writes
```

Then load the appropriate reference file and follow its steps exactly.

## Closing

After any mode: log non-obvious findings with `/platform-skills:self-improve log`.
