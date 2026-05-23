# How Agent Self-Improvement Works

This document explains what the self-improve skill does, why it exists, and how to use each part of it.

---

## The Problem It Solves

AI agents forget between sessions. Every time you start a new conversation, the agent has no memory of the last one. This means:

- The same mistake gets made twice (or ten times)
- A useful shortcut you discovered in one session is gone in the next
- When a long task is interrupted mid-way, the agent cannot safely resume without manual re-briefing
- Proactive actions happen on gut feel rather than a consistent decision framework

The self-improve skill gives the agent a persistent memory layer and a set of behavioral protocols that survive session boundaries, context compaction, and interruptions.

---

## Two Patterns in One Skill

The skill combines two complementary patterns:

| Pattern | What it does |
|---|---|
| **Self-Improving Agent** | Captures mistakes, learnings, and feature requests in `.learnings/`. Detects recurring patterns. Promotes stable lessons to project memory. |
| **Proactive Agent** | Gives the agent a consistent framework for when and how to act without being asked — WAL protocol, working buffer, decision scoring, heartbeat, and reverse prompting. |

You can use either pattern in isolation, but they work best together.

---

## Directory Structure

After running `/platform-skills:self-improve init`, your project gains:

```
.learnings/
  LEARNINGS.md          # Positive learnings — what worked, useful techniques
  ERRORS.md             # Mistakes and wrong assumptions — what broke and why
  FEATURE_REQUESTS.md   # Recurring needs the current tool set couldn't meet
  .pending-errors.log   # Scratch file written by the PostToolUse hook (gitignored)
memory/
  working-buffer.md     # Live task state and WAL log
```

Add to `.gitignore` for personal/local notes:
```
.learnings/
memory/working-buffer.md
```

Commit the directories if you want the team to share and build on them.

---

## Entry Lifecycle

Every entry in `.learnings/` follows the same structure and lifecycle:

```
pending → resolved → promoted
```

```markdown
### ERR-20260520-001
**Status**: pending
**Context**: Applying a Terraform plan that replaced an RDS instance
**Content**: Assumed changing db_subnet_group_name was non-destructive. It forces replacement.
**Action**: Added lifecycle { prevent_destroy = true }. Promote to references/terraform.md.
```

| Stage | Meaning | Who acts |
|---|---|---|
| `pending` | Logged, not yet addressed | Agent logs automatically |
| `resolved` | Fix applied — action recorded | Agent sets this in the same session if the fix was applied; otherwise user confirms |
| `promoted` | Written to project memory | Agent after running `/platform-skills:self-improve promote` |

**Key rule:** If the agent logs an error and applies the fix in the same session, it sets `Status: resolved` immediately — no manual step needed.

---

## The Five Modes

### `init` — Bootstrap the workspace

```text
/platform-skills:self-improve init
```

First asks whether you want a **global** workspace (`~/.claude/`) or a **project-local** one (`.`):

- **Global** — learnings persist across all projects on your machine. Recommended for individuals. Hook installs to `~/.claude/settings.json`.
- **Project-local** — learnings live in the repo, can be committed and shared with the team. Hook installs to `.claude/settings.json`.

Then creates the `.learnings/` and `memory/` directories with seed templates. For project-local setup, also asks whether to gitignore them.

Run once (globally or per project).

---

### `log` — Capture a learning, error, or feature request

```text
/platform-skills:self-improve log ERR
We assumed the EKS node group could be renamed in-place. It cannot — rename forces replacement of all nodes.
```

What the agent does:

1. Classifies the entry (`LRN`, `ERR`, or `FEAT`)
2. Checks `.learnings/` for an existing entry with the same context — updates rather than duplicating
3. Assigns the next sequential ID for today: `ERR-20260520-001`
4. Writes the four-field entry and sets `Status: resolved` if the fix was applied
5. Confirms: "Logged as `ERR-20260520-001` in `.learnings/ERRORS.md`"

---

### `resume` — Resume after an interruption

```text
/platform-skills:self-improve resume
```

Use this when a session was interrupted (context compaction, browser close, long pause). The agent:

1. Reads `memory/working-buffer.md`
2. Identifies the last completed step
3. Verifies the actual state of affected resources before proceeding:
   - Files: checks they exist and have expected content
   - Kubernetes: `kubectl get <resource> -n <namespace>`
   - Terraform: `terraform state list`
   - Git: `git log --oneline -5`
4. Resumes from the first incomplete step — does not re-run committed steps
5. Resolves any WAL entries still in `PENDING` state

**Example scenario:**

```
Session 1: You ask the agent to apply a Terraform plan across three modules.
           The agent completes module 1 and 2, then your laptop sleeps.

Session 2: /platform-skills:self-improve resume
           Agent reads the buffer: "Step 3: [ ] Apply module 3"
           Agent runs: terraform state list → confirms module 1 and 2 applied
           Agent applies module 3 and updates the buffer to [x]
```

---

### `review` — Surface recurring patterns

```text
/platform-skills:self-improve review
```

The agent reads all three `.learnings/` files, groups entries by shared root-cause keywords, and reports:

- **Promotion candidates** — contexts that appear three or more times
- **Stale entries** — `pending` entries older than 7 days
- **Actionable FEATs** — feature requests that an existing platform-skills domain could now address

Example output:

```
PROMOTION CANDIDATE — ERR: "resource limits missing"
Entries: ERR-20260518-001, ERR-20260519-002, ERR-20260520-001
Suggested target: CLAUDE.md → "Always add resource requests and limits to every container spec"

Stale pending entries: 1
  ERR-20260510-001 — "helm upgrade failed on rollback" — 10 days old, still pending

Learnings: 8 total, 3 pending, 5 resolved
Errors: 5 total, 1 pending, 4 resolved
Feature requests: 2 total, 2 pending
Promotion candidates: 1
```

---

### `promote` — Write a lesson to project memory

```text
/platform-skills:self-improve promote ERR-20260520-001
```

The agent:

1. Reads the entry
2. Identifies the right promotion target:

   | Target | When |
   |---|---|
   | `CLAUDE.md` / `AGENTS.md` | Agent-level rule for every session in this project |
   | `.github/copilot-instructions.md` | GitHub Copilot workspace rules |
   | `references/` guide | Reusable pattern for the whole team |

3. Drafts the promoted line in imperative voice (≤ 80 characters):
   - ERR → negative rule: `"Never change db_subnet_group_name without a replace plan and snapshot"`
   - LRN → positive rule: `"Run helm diff upgrade before helm upgrade to preview rendered changes"`
4. Asks you to confirm the target file and wording before writing
5. Appends to the confirmed file and updates the entry status to `promoted`
6. Commits with: `docs(memory): promote ERR-20260520-001 — never rename EKS node group in-place`

---

## WAL Protocol — Safe Destructive Operations

Before any hard-to-reverse operation, the agent writes a WAL entry to `memory/working-buffer.md`:

```markdown
## WAL Entry — 2026-05-20 14:32
**Operation**: terraform apply — destroys and recreates payments-rds RDS instance
**Affected resources**: aws_db_instance.payments (us-east-1)
**Blast radius**: payments-api will lose database connectivity during replacement (~8 min)
**Rollback**: Restore from snapshot rds:payments-rds-2026-05-20 using aws rds restore-db-instance-from-db-snapshot
**Status**: PENDING
```

After the operation succeeds, it updates `Status: COMMITTED`. If aborted, `Status: ROLLED_BACK`.

**Operations that always get a WAL entry:**
- Deleting or overwriting files
- `git reset --hard`, `git push --force`
- `terraform destroy` or `terraform apply`
- Dropping database tables or truncating data
- Modifying shared infrastructure

The WAL entry survives context compaction. If the session is interrupted between writing the entry and completing the operation, `resume` mode reads it and verifies actual resource state before proceeding.

---

## VFM Scoring — When to Act Without Being Asked

Before taking any unsolicited proactive action, the agent scores the action:

| Dimension | Weight | Example score |
|---|---|---|
| High Frequency (will this recur?) | ×3 | 8 |
| Failure Reduction (prevents real breakage?) | ×3 | 9 |
| User Burden (saves meaningful effort?) | ×2 | 7 |
| Self Cost (low effort for the agent?) | ×2 | 9 |

**Threshold:** score ≥ 50 → act proactively. Score < 50 → surface as a note and defer.

Example — proactively adding missing resource limits to a Deployment:
```
High Frequency:    8 × 3 = 24  (missing limits is a repeat pattern)
Failure Reduction: 9 × 3 = 27  (OOM kills cause production incidents)
User Burden:       7 × 2 = 14  (user would need to find and fix manually)
Self Cost:         9 × 2 = 18  (trivial three-line edit)
Total: 83 → act
```

To raise the threshold for your project, add to `CLAUDE.md` or `AGENTS.md`:
```
VFM_THRESHOLD=70
```

---

## The Growth Loop

Each session follows a consistent cycle that compounds over time:

```
Session start
  → Read working-buffer.md and .learnings/ to seed context
  → If buffer shows incomplete task: run /platform-skills:self-improve resume

During work
  → Log errors to ERRORS.md as they occur (Status: resolved immediately if fix applied)
  → Log useful techniques to LEARNINGS.md
  → Write WAL entry before any destructive operation
  → Update working-buffer.md after each significant step

Session end
  → Update buffer with final state
  → Check for recurring patterns (three+ same-context entries → promote)
  → Leave buffer intact if task is incomplete

Next session start
  → Buffer and learnings shorten ramp-up to < 60 seconds
```

---

## Automatic Error Capture via Hook

With the PostToolUse hook configured in `.claude/settings.json`, tool failures are automatically appended to `.learnings/.pending-errors.log`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ \"$CLAUDE_TOOL_EXIT_CODE\" -ne 0 ]; then echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) TOOL_FAILURE: $CLAUDE_TOOL_NAME\" >> ~/.claude/.learnings/.pending-errors.log; fi"
          }
        ]
      }
    ]
  }
}
```

On `/platform-skills:self-improve review`, the agent reads `.pending-errors.log`, converts each line into a proper `ERR` entry in `ERRORS.md`, and clears the log.

Add to `.gitignore`:
```
.learnings/.pending-errors.log
```

---

## What This Skill Cannot Do

- **It does not replace human post-mortems.** It captures agent-level errors. System-level incidents and team retrospectives still belong in your incident management process.
- **It cannot verify that promoted rules are being followed.** Once a rule is in `CLAUDE.md`, it is up to you to review it periodically and retire it if it becomes stale.
- **The working buffer is not a database.** Keep it lean — summarise completed WAL entries into a single `## Completed` block and delete individual entries once the task is done.
- **Global learnings are not shared automatically.** The global workspace (`~/.claude/`) is local to your machine. To share lessons with the team, use project-local setup and commit `.learnings/`, or promote entries to a shared `references/` file.

---

## Further Reading

- [references/agent-self-improve.md](../../references/agent-self-improve.md) — full reference for all protocols
- [commands/self-improve.md](../../commands/self-improve.md) — slash command specification
- [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md) — how the platform-skills skill works in general
- [GETTING_STARTED.md](../../GETTING_STARTED.md) — install and first session
