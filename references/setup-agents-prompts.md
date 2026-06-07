# Agent Prompt Writing Guide

## 3-section format

Every generated agent has exactly three sections. Test: could this section be copy-pasted for a different repo, or does it only make sense for this one?

### Context

One paragraph. Who this agent is, what repo it works in, what it owns, what it doesn't.
End with: "Your source of truth is `AGENTS.md`. Always read it first before acting."

Bad: "You are a helpful application agent."
Good: "You are the app agent for payments-service — a FastAPI service on EKS. You own: src/, tests/, Dockerfile. You never touch: terraform/, .github/workflows/. Your source of truth is AGENTS.md."

### How to work here

Specific facts about THIS codebase. Must pass this checklist:
- Names ≥3 actual file paths or directories
- States ≥1 non-obvious convention (e.g. "DB sessions use async with in src/db/session.py")
- States ≥1 non-obvious decision already made (e.g. "SQLAlchemy 2.0 async — no sync sessions")

Verify every path you write actually exists before writing it:
- For files: `test -f <path>`
- For directories: `test -d <path>`

The staleness checker in `scripts/verify-agents.sh` catches both (`test -f` for extension-bearing paths, `test -d` for trailing-slash paths). If you write a dead directory reference it will fail CI.

### Boundaries

- Autonomy level: `interactive` / `plan` / `autopilot`
- Handoff triggers: "When asked about X, hand off to Y"
- Approval gates: "Never deploy to prod without human approval"
- Off-limits: explicit path list
- **Always read `AGENTS.md` first** before acting on any request. It contains the roster, off-limits paths, and conventions that override anything else.

## Coordinator pattern

Written last. Starts with: "Your source of truth is `AGENTS.md`. Keep it current. When the repo changes, update `AGENTS.md` before updating any agent file."

Gets a handoff table covering every sub-agent:

| Request type | Route to | Trigger |
|---|---|---|
| src/ change | app | code or test |
| terraform/ change | infra | any IaC |
| prod deploy | human | always |

## Navigator pattern

The agent that gets used every day — new team members, code reviews, incident investigation.
Offer for every repo.

```markdown
## Context
Navigator for <repo>. Helps developers understand this codebase.
Not task-specific — read access only, writes nothing.
Your source of truth is AGENTS.md. Always read it first.

## How to work here
- Entry points: <list from scan>
- Most confusing parts: <from interview if surfaced>
- Common questions new team members have: <from interview>
- Where to start for common task types: <inferred from workflows>

## Boundaries
- Autonomy: interactive, read-only
- Never modifies files
- When developer needs to act, hand off to the appropriate task agent
- Off-limits for writes: everything
```

## Staleness prevention

Before writing: every path in `## How to work here` must exist in the current file tree.
If a path doesn't exist → remove or correct it before writing.
Never write dead references.
