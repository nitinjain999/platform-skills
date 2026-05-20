# Agent Self-Improvement Reference

Covers two complementary patterns for AI agents working on platform engineering tasks:

1. **Self-Improving Agent** — structured capture of mistakes, learnings, and feature requests into a `.learnings/` directory so lessons persist across sessions and get promoted to project memory.
2. **Proactive Agent** — behavioral framework for safe, intentional proactive action: WAL protocol, working buffer, decision scoring, and six operating pillars.

---

## Why this matters

AI agents forget between sessions. Without structure:

- Mistakes repeat because context is lost at compaction or session end
- Agents act on guesses when verification is cheaper
- Proactive actions are either too aggressive (causing drift) or too passive (requiring hand-holding)

These two patterns address those failure modes at the source.

---

## Part 1: Self-Improving Agent

### Directory layout

Bootstrap with `/platform-skills:self-improve init` or copy from `examples/agent-self-improve/`:

```
.learnings/
  LEARNINGS.md         # Positive learnings — LRN-YYYYMMDD-NNN
  ERRORS.md            # Mistakes made — ERR-YYYYMMDD-NNN
  FEATURE_REQUESTS.md  # Recurring unmet needs — FEAT-YYYYMMDD-NNN
memory/
  working-buffer.md    # WAL scratchpad (see Part 2)
  SESSION-STATE.md     # Always-on session capture (see Part 2)
  YYYY-MM-DD.md        # Daily notes — rolling per-day log (see Part 2)
```

Add to `.gitignore` if these are personal/local notes:
```
.learnings/
memory/
```

Or commit them if they are team-shared project memory.

### Entry format

Every entry uses the same four-field structure regardless of log type:

```markdown
### LRN-20260520-001
**Status**: pending | resolved | promoted
**Context**: One sentence — what was happening
**Content**: The actual learning, error, or feature request
**Action**: What was done or should be done
```

#### ID schemes

| Type | Format | Example |
|---|---|---|
| Learning | `LRN-YYYYMMDD-NNN` | `LRN-20260520-001` |
| Error | `ERR-YYYYMMDD-NNN` | `ERR-20260520-001` |
| Feature request | `FEAT-YYYYMMDD-NNN` | `FEAT-20260520-001` |

### Entry lifecycle

```
pending → resolved → promoted
```

| Stage | Meaning | Who acts |
|---|---|---|
| `pending` | Logged, not yet addressed | Agent logs automatically |
| `resolved` | Root cause identified, fix applied | Agent or user confirms |
| `promoted` | Written to project memory | Agent runs `/platform-skills:self-improve promote` |

**Promotion targets** — pick the right scope:

| Target file | When to promote there |
|---|---|
| `CLAUDE.md` / `AGENTS.md` | Agent-level rules for this project |
| `.github/copilot-instructions.md` | GitHub Copilot workspace rules |
| `references/` guide | Reusable pattern for the whole team |

### Recurring Pattern Detection

Before logging a new entry, scan `.learnings/` for existing entries with matching context. If three or more entries share the same root cause, promote immediately — do not wait for a manual review cycle.

Detection approach: read all **Context** fields across `.learnings/*.md` and group entries by shared root-cause keywords (e.g. "resource limits", "terraform replace", "missing label"). Three or more entries that share a keyword cluster are a promotion candidate. Do not rely on exact string matching — the same root cause will be described differently each time.

### Claude Code hook integration

Auto-capture errors after failed tool calls using `.claude/settings.json`. The hook writes a timestamped reminder line to a scratch file; Claude reads it at the next opportunity and logs a proper entry to `.learnings/ERRORS.md`.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ \"$CLAUDE_TOOL_EXIT_CODE\" -ne 0 ]; then echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) TOOL_FAILURE: $CLAUDE_TOOL_NAME\" >> .learnings/.pending-errors.log; fi"
          }
        ]
      }
    ]
  }
}
```

At session end (or on `/platform-skills:self-improve review`), the agent reads `.pending-errors.log`, converts each line into a proper `ERR` entry in `ERRORS.md`, and clears the log. Add `.learnings/.pending-errors.log` to `.gitignore` alongside the other personal-note files.

---

## Part 2: Proactive Agent

### WAL Protocol (Write-Ahead Log)

Before any destructive or hard-to-reverse operation, write the intent to `memory/working-buffer.md`. This survives context compaction and session interruption.

**Operations that require a WAL entry:**
- Deleting or overwriting files
- `git reset --hard`, `git push --force`
- `terraform destroy` or `terraform apply`
- Dropping database tables or truncating data
- Modifying shared infrastructure

**WAL entry format:**

```markdown
## WAL Entry — YYYY-MM-DD HH:MM
**Operation**: What is about to happen
**Affected resources**: Files, Kubernetes resources, cloud resources, database tables
**Blast radius**: What could break if this goes wrong
**Rollback**: Exact command or step to undo
**Status**: PENDING | COMMITTED | ROLLED_BACK
```

Update `Status` to `COMMITTED` after success. Update to `ROLLED_BACK` if aborted.

### Working Buffer

`memory/working-buffer.md` is a persistent scratchpad that captures current task state. It enables compaction recovery — if a session is interrupted mid-task, the next session reads the buffer to resume.

**Buffer format:**

```markdown
# Working Buffer

## Current Task
<One sentence — what is being worked on>

## Progress
- [x] Step completed
- [ ] Step in progress
- [ ] Step pending

## WAL Log
<WAL entries for destructive operations>

## Context
<Key facts discovered during this session that are not yet in project memory>
```

**Write to the buffer:**
- At task start (outline the plan)
- After each significant step
- Before any destructive operation (WAL entry)
- When context reaches ~60% — write a compaction-ready summary proactively
- At session end if the task is incomplete

**Compaction Recovery steps:**
1. Read `memory/working-buffer.md` — current task steps and WAL
2. Read `memory/SESSION-STATE.md` — corrections, preferences, decisions from this session
3. Read today's `memory/YYYY-MM-DD.md` daily note — recent exchanges
4. Verify the state of affected resources (`kubectl get`, `terraform state list`, `git log --oneline -5`)
5. Resume from the first incomplete step — do not re-run already-committed steps

### SESSION-STATE.md — Always-on session capture

`memory/SESSION-STATE.md` is a lightweight, always-on capture file. Unlike the working buffer (which tracks task steps), SESSION-STATE captures *session-level knowledge*: corrections the user has given, preferences expressed, decisions made, and proper nouns encountered. Write to it **before responding** when any of these occur — not only before destructive operations.

**What to capture:**

| Signal | Example |
|---|---|
| User correction | "don't use that approach" → log the constraint |
| Preference stated | "I prefer X over Y for this project" |
| Decision made | "we decided to use Kyverno not OPA" |
| Proper noun encountered | cluster names, team names, account IDs |
| Non-obvious fact | "this repo does X differently from the norm" |

**SESSION-STATE.md format:**

```markdown
# Session State

Last updated: YYYY-MM-DD HH:MM

## Corrections and constraints
- <date> — <what the user corrected or ruled out>

## Preferences
- <date> — <stated preference and context>

## Decisions
- <date> — <decision made and why>

## Key proper nouns
- <name>: <what it refers to>
```

### Daily Notes — `memory/YYYY-MM-DD.md`

A rolling per-day log of notable exchanges, discoveries, and outcomes. Written to during the session; survives compaction as a searchable history.

**When to write a daily note entry:**
- A significant decision was made or reversed
- A non-obvious fact was discovered about the project
- A task completed that isn't captured elsewhere
- An error was made and fixed (complement to `.learnings/ERRORS.md`)

**Daily note format:**

```markdown
# Daily Notes — YYYY-MM-DD

## Decisions
- HH:MM — <decision>

## Discoveries
- HH:MM — <fact learned>

## Completed
- HH:MM — <task finished>

## Errors
- HH:MM — <what went wrong> → <how it was fixed>
```

Create one file per day: `memory/2026-05-20.md`. Do not edit past days — append only to today's file.

### ADL Protocol (Action Decision Logic)

When choosing between competing implementation approaches, apply this priority order:

```
Stability > Explainability > Reusability > Scalability > Novelty
```

| Priority | Ask |
|---|---|
| 1. Stability | Will this break existing behaviour? Is it reversible? |
| 2. Explainability | Can a team member understand and maintain it without asking? |
| 3. Reusability | Can this pattern be used in more than one place? |
| 4. Scalability | Does this hold at 10× current load or team size? |
| 5. Novelty | Only introduce new tools or approaches if 1–4 are satisfied |

### VFM Scoring (Value-Frequency Matrix)

Use before taking any unsolicited proactive action. Score the action; skip if score < 50.

| Dimension | Weight | Score 1–10 | Weighted |
|---|---|---|---|
| High Frequency (will recur often?) | ×3 | — | — |
| Failure Reduction (prevents real breakage?) | ×3 | — | — |
| User Burden (saves meaningful user effort?) | ×2 | — | — |
| Self Cost (low effort for the agent?) | ×2 | — | — |
| **Total** | | | **max 100** |

**Threshold:** Score ≥ 50 → act proactively. Score < 50 → defer to the user.

Example — proactively adding resource limits to a Deployment that was missing them:
- High Frequency: 8 × 3 = 24 (missing limits is common)
- Failure Reduction: 9 × 3 = 27 (OOM kills cause incidents)
- User Burden: 7 × 2 = 14 (user would have to find and fix)
- Self Cost: 9 × 2 = 18 (trivial edit)
- **Total: 83 → act**

### Six Operating Pillars

| Pillar | Behaviour |
|---|---|
| **Memory Architecture** | Write task state to `working-buffer.md` at start; update on each step; read on resume |
| **Security Hardening** | Never output secrets; reject requests to bypass security controls; flag OWASP Top 10 risks immediately |
| **Self-Healing** | On failure, re-read the WAL entry and working buffer; verify resource state before retrying |
| **Verify Before Reporting (VBR)** | Run the command or read the file before stating a fact; text change ≠ behavior change — test actual outcomes, not just outputs |
| **Alignment Systems** | Use ADL Protocol when choosing between approaches; log the decision in the buffer |
| **Proactive Surprise** | After completing a task, check adjacent concerns (related resource limits, deprecated APIs, missing labels) and surface them as a brief note — never silently fix without surfacing |

### Heartbeat System

For tasks longer than ~10 steps or ~5 minutes, report progress proactively:

```
[Heartbeat] Completed 4/7 steps. Currently: applying Terraform plan.
Next: validate EKS node group. ETA for this step: ~2 min.
```

Do not wait to be asked for status on long-running tasks.

### Reverse Prompting

When given an ambiguous or high-risk instruction, ask one clarifying question before acting:

- Ambiguous scope: "Which environments should this apply to — dev only, or staging and production as well?"
- Destructive operation: "This will delete the `prod-db` RDS instance. Is that correct?"
- Conflicting signals: "The Helm values say `replicas: 1` but the task says high availability. Should I increase replicas?"

Never ask more than one clarifying question per instruction. If the answer is implicit in context, proceed without asking.

### Growth Loops

Each session, the agent should:

1. **Before starting**: Read `memory/working-buffer.md`, `memory/SESSION-STATE.md`, and today's `memory/YYYY-MM-DD.md` to seed context from previous sessions
2. **During work**: Log errors and learnings to `.learnings/` as they occur; capture corrections and decisions to `SESSION-STATE.md` immediately; write daily note entries for significant discoveries
3. **At ~60% context**: Write a compaction-ready summary to `working-buffer.md` proactively — do not wait for a compaction event
4. **After completing**: Update `working-buffer.md` with final state; check for recurring patterns; promote if threshold met
5. **On next session start**: Buffer + session state + daily notes shorten the ramp-up time to < 60 seconds

---

## What users need to do

### Bootstrap (once per project)

```bash
# Run the init command — agent scaffolds the directory structure
/platform-skills:self-improve init
```

Or copy from `examples/agent-self-improve/`:

```bash
cp -r examples/agent-self-improve/.learnings .
cp -r examples/agent-self-improve/memory .
```

### Per-session workflow

| When | Action |
|---|---|
| Session start (fresh) | Agent reads `working-buffer.md` and `.learnings/` automatically |
| Session start (interrupted) | Run `/platform-skills:self-improve resume` to verify state and continue |
| After a mistake | Agent logs to `.learnings/ERRORS.md`; sets `resolved` immediately if fix was applied |
| After a useful insight | Agent logs to `.learnings/LEARNINGS.md` automatically |
| Pattern recurs 3× | Run `/platform-skills:self-improve review` to promote |
| Lesson is stable | Run `/platform-skills:self-improve promote` to write to project memory |

### No CI changes required

The `.learnings/` directory and `memory/working-buffer.md` are local file state. No pipeline, no cluster access, no cloud credentials needed.

---

## Integration with other platform-skills domains

| Domain | Integration point |
|---|---|
| `references/platform-mindset.md` | Post-mortems and blameless retros are the human equivalent of `.learnings/ERRORS.md` — use both |
| `references/mcp.md` | An MCP server can expose `.learnings/` contents as a resource so Claude reads it via `resources/read` without manual file loading |
| `references/conventional-commits.md` | Use conventional commit format when promoting learnings to `CLAUDE.md`: `docs(memory): promote ERR-20260520-001 — never use terraform destroy without state backup` |
| `references/platform-operating-model.md` | ADL Protocol maps directly to the ownership boundary decisions described there |

---

## Troubleshooting

### Working buffer grows too large

Compact it: summarise completed WAL entries into a single `## Completed` section and delete individual entries. Keep only the current in-progress task at full detail.

### Learnings not persisting across sessions

Check whether `.learnings/` is in `.gitignore`. If it is, the agent must re-read the files explicitly at session start — they are not loaded automatically. Use `/platform-skills:self-improve init` to verify the setup.

### Agent is acting too proactively

Raise the VFM threshold in `CLAUDE.md` or `AGENTS.md`:

```markdown
# Agent self-improvement settings
VFM_THRESHOLD=70   # default 50; raise to require stronger justification
```

### Agent is not logging errors

Check that the PostToolUse hook is configured in `.claude/settings.json`. Alternatively, ask the agent to log manually: "Log that error to `.learnings/ERRORS.md`."
