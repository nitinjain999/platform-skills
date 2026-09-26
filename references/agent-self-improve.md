---
title: Agent Self-Improvement
custom_edit_url: null
---

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

Bootstrap with `/platform-skills:self-improve init global` (cross-project) or `/platform-skills:self-improve init local` (project-scoped), or copy from `examples/agent-self-improve/`:

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

### Global vs project scope

The `init` mode asks which scope to use before creating anything:

| Scope | Base path (`LEARNINGS_BASE`) | When to use |
|---|---|---|
| **Global** | `~/.claude/` | Learnings apply across all projects — recommended default for individuals |
| **Project** | `.` (current working directory) | Team-shared memory committed to the repo |

**Auto-detection order** (used by all modes except `init`):

1. `~/.claude/.learnings/` exists → global setup detected, use `~/.claude/`
2. `.learnings/` exists in `$PWD` → project setup detected, use `.`
3. Neither exists → default to `~/.claude/` and auto-create

**Promotion targets are always project-local** regardless of scope. `CLAUDE.md`, `AGENTS.md`, and `.github/copilot-instructions.md` live in the project repo — only the capture files (`.learnings/`, `memory/`) follow `LEARNINGS_BASE`.

**Hook script paths must be absolute** when using global setup, so that the hook resolves the same way from any project:

```json
{
  "hooks": {
    "PostToolUseFailure": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/self-improve-hook.sh tool-failure",
            "async": true
          }
        ]
      }
    ]
  }
}
```

The same block serves project-scoped setup unchanged. The script applies the resolution order above on every invocation, so the log lands next to whichever `.learnings/` is in use rather than wherever the hook happened to be launched from.

### Entry format

Every entry has four required fields, plus optional metadata. `log` writes the metadata for every new entry. Older entries without it stay valid: `lint` counts them as "without metadata". They need `Source`, `Scope` and `Verified` before they can be promoted.

```markdown
### LRN-20260520-001
**Status**: pending | resolved | promoted | superseded | revoked | discarded
**Context**: One sentence — what was happening
**Content**: The actual learning, error, or feature request
**Action**: What was done or should be done
**Source**: user | observed | ci | repo | vendor-docs | inferred
**Scope**: global | project:<repo-name>
**Paths**: infrastructure/**/*.tf, modules/**/*.tf
**Verified**: 2026-09-26
**Expires**: 2026-12-31 | never
**Supersedes**: LRN-20260401-003
```

#### Metadata fields

| Field | Meaning | Rules |
|---|---|---|
| `Source` | Where the lesson came from | `user` (the user said it), `observed` (live state or tool output), `ci` (a test or pipeline result), `repo` (the repository's own config or docs), `vendor-docs` (official documentation), `inferred` (the agent concluded it) |
| `Scope` | Where it applies | `global`, or `project:<name>` where `<name>` is the git top-level's directory name. `learnings.sh whereami` prints it |
| `Paths` | Files it applies to | Optional. Project scope only. Comma-separated globs, no quotes. Becomes the `paths:` frontmatter of a promoted rule |
| `Verified` | When it was last confirmed true | `YYYY-MM-DD`. Update it whenever the lesson is re-confirmed |
| `Expires` | When it stops applying | `YYYY-MM-DD` or `never`. Use it for workarounds and exceptions |
| `Supersedes` | The entry this one replaces | Also set the old entry to `superseded` with `learnings.sh set-status` |
| `Status-Note` | Why the status last changed | Written by `learnings.sh set-status`. Don't edit it by hand |

#### Staleness and expiry

An active entry (`pending`, `resolved` or `promoted`) is **stale** once its `Verified` date is older than the window for its source, and **expired** after its `Expires` date. `lint` and `review` report both. A stale or expired entry can't be promoted. A stale *promoted* entry is flagged first, because its rule is still loaded into every session.

| Source | Re-verify after |
|---|---|
| `user` | Never goes stale |
| `inferred` | 30 days |
| `observed`, `ci`, `repo`, `vendor-docs` | 90 days |

#### ID schemes

| Type | Format | Example |
|---|---|---|
| Learning | `LRN-YYYYMMDD-NNN` | `LRN-20260520-001` |
| Error | `ERR-YYYYMMDD-NNN` | `ERR-20260520-001` |
| Feature request | `FEAT-YYYYMMDD-NNN` | `FEAT-20260520-001` |

### Entry lifecycle

```
pending → resolved → promoted
              ↘ superseded | revoked | discarded
```

| Stage | Meaning | Who acts |
|---|---|---|
| `pending` | Logged, not yet addressed | Agent logs automatically |
| `resolved` | Root cause identified, fix applied | Agent or user confirms |
| `promoted` | Written to project memory | Agent runs `/platform-skills:self-improve promote` |
| `superseded` | Replaced by a newer entry that names it in `Supersedes` | `learnings.sh set-status <old-id> superseded` |
| `revoked` | Found to be wrong. Must stop influencing behaviour | `/platform-skills:self-improve revoke` |
| `discarded` | Not worth keeping | `review` suggests it for stale resolved entries |

**Promotion targets.** `learnings.sh promote` chooses from the entry's scope:

| Entry scope | Target | Loaded |
|---|---|---|
| `global` | `~/.claude/rules/<domain>.md` | Every session on this machine |
| `project:<name>` with `Paths` | `.claude/rules/<domain>.md`, with `paths:` frontmatter from the entry's `Paths` | When Claude reads a matching file |
| `project:<name>` without `Paths` | `.claude/rules/<domain>.md` | Every session in this project |
| Opt-in, with `--target` | `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, under `## Agent Rules` | For rules other tools must also read |
| By hand | A `references/` guide | Reusable patterns for the whole team |

Each promoted rule ends in a `<!-- self-improve:<ID> -->` marker, so the rule is traceable to its evidence. `learnings.sh unpromote <ID>` removes exactly that line (add `--revoke` to retire the entry too). Promotion is refused for entries that aren't `resolved`, lack `Source`/`Scope`/`Verified`, are stale or expired, are `inferred` without confirmation, or belong to another project. A rules file whose `paths` differ from the entry's is never widened or narrowed; pick another domain.

### Helper script: `learnings.sh`

The command runs `bash ~/.claude/scripts/learnings.sh <subcommand>` instead of parsing entries or doing date arithmetic itself. It resolves the workspace the same way as the command and the hooks.

| Subcommand | What it does |
|---|---|
| `whereami` | Prints the workspace, `scope=global` or `project`, the project name for `Scope: project:<name>`, and today's date |
| `entries` | One tab-separated record per entry |
| `lint` | Reports `ERROR` (invalid entries), `WARN`, `EXPIRED` and `STALE` lines and a summary. Exits 1 on any error |
| `set-status ID STATUS [--note TEXT]` | Rewrites one entry's status and `Status-Note`, under the same lock as the `SessionEnd` drain |
| `promote ID --domain D --rule T [--target F] [--allow-inferred] [--apply]` | Checks eligibility, previews the rule as a diff, and with `--apply` writes it and marks the entry `promoted` |
| `unpromote ID [--revoke] [--note T]` | Removes the marked rule from every promotion target; resets the entry to `resolved`, or `revoked` |
| `recall [--all] [--limit N] TERM...` | Read-only search. Ranks by term matches (+2 Content, +1 Context, +5 exact id), excludes revoked, superseded, discarded, expired and other-project entries while counting them, and flags `STALE` and `verify before use` results |

Exit codes: 0 ok, 1 lint errors, 2 usage or no workspace, 3 workspace busy (another session holds the lock; retry), 4 refused.

Install: `cp examples/agent-self-improve/scripts/learnings.sh ~/.claude/scripts/ && chmod +x ~/.claude/scripts/learnings.sh`

**Trusting a recalled lesson.** A result flagged `STALE` hasn't been verified within its source's window. One flagged `verify before use` came from an inference or has no source at all. Treat both as leads, not facts: check the current state first, then update `Verified` if the lesson still holds, or revoke it. Prefer verified current state over remembered assumptions every time.

### Recurring Pattern Detection

Before logging a new entry, scan `.learnings/` for existing entries with matching context. If three or more entries share the same root cause, promote immediately — do not wait for a manual review cycle.

Detection approach: read all **Context** fields across `.learnings/*.md` and group entries by shared root-cause keywords (e.g. "resource limits", "terraform replace", "missing label"). Three or more entries that share a keyword cluster are a promotion candidate. Do not rely on exact string matching — the same root cause will be described differently each time.

### Claude Code hook integration

Auto-capture errors after failed tool calls. The hook appends a timestamped line to `.pending-errors.log`; the agent converts it to a proper `ERR` entry at session end or on `review`.

Hook setup varies by platform — see the **Platform Compatibility** section (below Part 2) for per-platform `settings.json` snippets and script copy commands.

Key rules regardless of platform:
- Global setup must use an absolute path to the hook script. The workspace itself is resolved by the script, not by the settings file.
- For project-local setup, add `.learnings/.pending-errors.log` to `.gitignore`.

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

## Platform Compatibility

The self-improve workspace runs on macOS, Linux, Windows (WSL / Git Bash), and Windows native (PowerShell). The core skill logic is identical on all platforms — only the hook scripts and their invocation differ.

### Global config path

Claude Code resolves `~` via Node.js `os.homedir()`, which maps consistently across platforms:

| Platform | `~/.claude/` resolves to |
|---|---|
| macOS | `/Users/<you>/.claude/` |
| Linux | `/home/<you>/.claude/` |
| Windows (WSL / Git Bash) | `/home/<you>/.claude/` (WSL home) |
| Windows native | `C:\Users\<you>\.claude\` |

All skill modes use `~/.claude/` notation — no platform-specific path changes are needed in the skill itself.

### Hook scripts by platform

One script serves all four events, selected by subcommand:

| Platform | Hook script | `SessionStart` | `SessionEnd` | `PostToolUseFailure` | `PreCompact` |
|---|---|---|---|---|---|
| macOS / Linux | `self-improve-hook.sh` | `session-start` | `session-end` | `tool-failure` | `precompact` |
| Windows — WSL / Git Bash | `self-improve-hook.sh` | `session-start` | `session-end` | `tool-failure` | `precompact` |
| Windows — native PowerShell | `self-improve-hook.ps1` | `session-start` | `session-end` | `tool-failure` | `precompact` |

There is deliberately no `PostCompact` hook. `SessionStart` fires again with `source=compact` after a compaction, and its stdout is added to the rebuilt context, so the workspace pointers are restored by the hook that is already wired.

**Windows recommendation:** WSL or Git Bash is the simpler path — the bash script works identically to macOS/Linux. Use the PowerShell (`.ps1`) script only when WSL or Git Bash is not available.

**Alpine Linux / busybox-only containers:** The bash script requires bash 3.2+. Install it first:
```sh
apk add bash
```

`jq` is optional. Without it, a `sed` fallback reads the few scalar payload fields the hooks use; that fallback takes the last match of a key anywhere in the payload, so a nested key of the same name can win. Install `jq` if you want the strict reading.

### Hook setup — macOS / Linux / WSL / Git Bash

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{"type": "command", "command": "bash ~/.claude/scripts/self-improve-hook.sh session-start"}]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [{"type": "command", "command": "bash ~/.claude/scripts/self-improve-hook.sh session-end", "timeout": 10}]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/self-improve-hook.sh tool-failure",
            "async": true
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{"type": "command", "command": "bash ~/.claude/scripts/self-improve-hook.sh precompact", "timeout": 10}]
      }
    ]
  }
}
```

`"timeout": 10` on `SessionEnd` is not optional in practice: all `SessionEnd` hooks share a 1.5-second budget by default, and the error drain plus daily-note write can exceed it. `"async": true` on `PostToolUseFailure` keeps the capture off the critical path of a tool call.

`PreCompact` is the safety net for `SessionEnd` never running. A session killed outright, or one whose window is closed, leaves `.pending-errors.log` undrained indefinitely; a long session compacts several times, so the drain becomes recurring rather than once-at-the-end. It takes no `matcher` — the event carries a `trigger` field (`manual` or `auto`) rather than a tool name. It must also never fail: `PreCompact` is one of the events where exit 2 aborts the operation, and a hook that stopped compaction would strand the session with a full context window.

Copy the script:
```sh
mkdir -p ~/.claude/scripts
cp examples/agent-self-improve/scripts/self-improve-hook.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/self-improve-hook.sh
```

### Hook setup — Windows native (PowerShell)

Add to `C:\Users\<you>\.claude\settings.json` (see `examples/agent-self-improve/settings-windows.json.example`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [{"type": "command", "command": "powershell -NoLogo -NoProfile -NonInteractive -File C:\\Users\\alex\\.claude\\scripts\\self-improve-hook.ps1 session-start"}]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [{"type": "command", "command": "powershell -NoLogo -NoProfile -NonInteractive -File C:\\Users\\alex\\.claude\\scripts\\self-improve-hook.ps1 session-end", "timeout": 10}]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoLogo -NoProfile -NonInteractive -File C:\\Users\\alex\\.claude\\scripts\\self-improve-hook.ps1 tool-failure",
            "async": true
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [{"type": "command", "command": "powershell -NoLogo -NoProfile -NonInteractive -File C:\\Users\\alex\\.claude\\scripts\\self-improve-hook.ps1 precompact", "timeout": 10}]
      }
    ]
  }
}
```

Replace `C:\Users\alex` with your own profile directory. The path is written out in full deliberately. A hook `command` is a raw string handed to a shell, so `%USERPROFILE%` expands only under `cmd` and `$env:USERPROFILE` only under PowerShell; earlier versions of this example used `%USERPROFILE%` and failed silently when the hook was not spawned through `cmd`. A literal path cannot be misexpanded.

`-NoProfile` matters beyond speed: a user profile that writes to stdout would otherwise corrupt the `SessionStart` banner, since that hook's stdout becomes context.

If PowerShell blocks script execution, allow local scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## What users need to do

### Bootstrap

Two explicit subcommands — no interactive prompt needed:

```
/platform-skills:self-improve init global
/platform-skills:self-improve init local
```

`init` without an argument asks you to choose and then proceeds as one of the above.

Or copy from `examples/agent-self-improve/` (macOS/Linux/WSL):

```bash
cp -r examples/agent-self-improve/.learnings ~/.claude/
cp -r examples/agent-self-improve/memory ~/.claude/
```

Windows native (PowerShell):

```powershell
Copy-Item -Recurse examples\agent-self-improve\.learnings "$env:USERPROFILE\.claude\"
Copy-Item -Recurse examples\agent-self-improve\memory "$env:USERPROFILE\.claude\"
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

Check that the `PostToolUseFailure` hook is configured in `.claude/settings.json`. If it is still wired to `PostToolUse`, that is the cause: `PostToolUse` fires only for tool calls that succeed. Alternatively, ask the agent to log manually: "Log that error to `.learnings/ERRORS.md`."
