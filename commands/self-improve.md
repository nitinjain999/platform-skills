---
name: self-improve
description: Bootstrap and operate a self-improving agent workspace. Scaffolds .learnings/ and memory/ directories, captures errors and learnings during a session, detects recurring patterns, and promotes stable entries to project memory (CLAUDE.md, AGENTS.md, or references/). Also implements the Proactive Agent pillars — WAL protocol, working buffer, SESSION-STATE, daily notes, VBR, VFM scoring, ADL decision logic, heartbeat, and reverse prompting. Use when asked to "remember this lesson", "set up agent memory", "log that error", "promote learnings", "capture session state", or "enable proactive mode".
argument-hint: "[init [global|local]|log [LRN|ERR|FEAT]|promote <ID>|migrate [global|local]|status|resume|review|state]"
---

Bootstrap and operate a self-improving, proactive agent workspace.

## Path Resolution (applies to all modes)

Before executing any mode, resolve `LEARNINGS_BASE`:

1. If mode is `init global` → use `~/.claude/`
2. Else if mode is `init local` → use `.` (current working directory)
3. Else if `~/.claude/.learnings/` exists → use `~/.claude/` as base (global setup)
4. Else if `.learnings/` exists in the current working directory → use `.` as base (project setup)
5. Else if mode is `init` (no argument) → ask the user to choose (see init mode below)
6. Else → default to `~/.claude/`, create the directories, and inform the user that global setup was auto-created

`~/.claude/` resolves consistently across all platforms (macOS, Linux, Windows) because Claude Code uses `os.homedir()` for `~`. On Windows this maps to `C:\Users\<you>\.claude\` — no manual path adjustment needed.

All path references in every mode below use `LEARNINGS_BASE` as the root:

| Logical path | Resolved path (global) | Resolved path (project) |
|---|---|---|
| `.learnings/LEARNINGS.md` | `~/.claude/.learnings/LEARNINGS.md` | `.learnings/LEARNINGS.md` |
| `.learnings/ERRORS.md` | `~/.claude/.learnings/ERRORS.md` | `.learnings/ERRORS.md` |
| `.learnings/FEATURE_REQUESTS.md` | `~/.claude/.learnings/FEATURE_REQUESTS.md` | `.learnings/FEATURE_REQUESTS.md` |
| `memory/working-buffer.md` | `~/.claude/memory/working-buffer.md` | `memory/working-buffer.md` |
| `memory/SESSION-STATE.md` | `~/.claude/memory/SESSION-STATE.md` | `memory/SESSION-STATE.md` |
| `memory/YYYY-MM-DD.md` | `~/.claude/memory/YYYY-MM-DD.md` | `memory/YYYY-MM-DD.md` |
| `.learnings/.pending-errors.log` | `~/.claude/.learnings/.pending-errors.log` | `.learnings/.pending-errors.log` |

Promotion targets (`CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`) always remain project-local regardless of scope — only the capture files follow `LEARNINGS_BASE`.

Reference: `references/agent-self-improve.md` → Global vs project scope

## Mode: init global

Scaffold the global workspace under `~/.claude/` — learnings persist across all projects.

```
/platform-skills:self-improve init global
```

Steps:
1. Set `LEARNINGS_BASE=~/.claude/`
2. If `~/.claude/.learnings/` already exists: report current state, list existing files, and stop — do not overwrite
3. Create the directory structure:
   ```
   ~/.claude/.learnings/
     LEARNINGS.md
     ERRORS.md
     FEATURE_REQUESTS.md
   ~/.claude/memory/
     working-buffer.md
     SESSION-STATE.md
   ```
4. Seed each file with the correct header and an example entry marked `Status: example`
5. Detect the user's platform and offer to wire all three hooks in `~/.claude/settings.json`:
   - **macOS / Linux / WSL / Git Bash** → bash scripts (`session-end.sh`, `session-start-reminder.sh`) + inline bash PostToolUse; point to `settings.json.example`
   - **Windows native (PowerShell)** → PS1 scripts (`session-end.ps1`, `session-start-reminder.ps1`) + inline PowerShell PostToolUse; point to `settings-windows.json.example`
   - **Alpine or minimal Linux** → same as macOS/Linux but remind the user to install bash first: `apk add bash`
   - All scripts are in `examples/agent-self-improve/scripts/`; PostToolUse hook must use absolute path to `.pending-errors.log` (global setup)
6. Offer to create `~/.claude/CLAUDE.md` from the template at `examples/agent-self-improve/global-claude.md`
7. Print bootstrap summary:
   ```
   ✓ ~/.claude/.learnings/LEARNINGS.md        — positive learnings
   ✓ ~/.claude/.learnings/ERRORS.md           — mistakes and root causes
   ✓ ~/.claude/.learnings/FEATURE_REQUESTS.md — recurring unmet needs
   ✓ ~/.claude/memory/working-buffer.md       — WAL scratchpad and task state
   ✓ ~/.claude/memory/SESSION-STATE.md        — always-on session capture
   ✓ ~/.claude/memory/YYYY-MM-DD.md           — daily notes (created on first use)
   ```
8. Remind the user to run `/platform-skills:self-improve review` after a few sessions

Reference: `references/agent-self-improve.md` → Global vs project scope

---

## Mode: init local

Scaffold a project-local workspace in the current working directory — learnings live in the repo.

```
/platform-skills:self-improve init local
```

Steps:
1. Set `LEARNINGS_BASE=.` (current working directory)
2. If `.learnings/` already exists in `$PWD`: report current state, list existing files, and stop — do not overwrite
3. Create the directory structure:
   ```
   .learnings/
     LEARNINGS.md
     ERRORS.md
     FEATURE_REQUESTS.md
   memory/
     working-buffer.md
     SESSION-STATE.md
   ```
4. Seed each file with the correct header and an example entry marked `Status: example`
5. Check `.gitignore` — ask the user:
   - **Gitignore** (recommended for personal notes): add `.learnings/` and `memory/` to `.gitignore`
   - **Commit**: leave untracked so the team can share and build on them; note that `memory/` daily notes grow fast
6. Offer to add hooks to `.claude/settings.json` (this project only):
   - **PostToolUse** → inline command writing to `.learnings/.pending-errors.log` (relative path is safe here — hooks run from project root)
   - Note: Stop and PreToolUse session scripts should be wired globally via `~/.claude/settings.json` even for project-local learnings
7. Print bootstrap summary:
   ```
   ✓ .learnings/LEARNINGS.md        — positive learnings
   ✓ .learnings/ERRORS.md           — mistakes and root causes
   ✓ .learnings/FEATURE_REQUESTS.md — recurring unmet needs
   ✓ memory/working-buffer.md       — WAL scratchpad and task state
   ✓ memory/SESSION-STATE.md        — always-on session capture
   ✓ memory/YYYY-MM-DD.md           — daily notes (created on first use)
   ```
8. Remind the user to run `/platform-skills:self-improve review` after a few sessions

Reference: `references/agent-self-improve.md` → Global vs project scope

---

## Mode: init (no argument)

When called without `global` or `local`, ask the user to choose:

- Recommend `init global` if neither `~/.claude/.learnings/` nor `.learnings/` in `$PWD` exists
- If `~/.claude/.learnings/` already exists, recommend `init local` (global already set up)
- If `.learnings/` in `$PWD` already exists, report its state and suggest using `log`, `resume`, or `review` instead

Then proceed as `init global` or `init local` based on the answer.

Reference: `references/agent-self-improve.md` → Directory layout, Entry format

## Mode: log

Log a learning, error, or feature request to the appropriate file.

Steps:
1. Classify the entry:
   - **Learning** (`LRN`) — a technique, pattern, or shortcut that worked
   - **Error** (`ERR`) — a mistake, misunderstanding, or failed assumption
   - **Feature request** (`FEAT`) — a need that was unmet by the current skill or tool set
2. Generate the ID: `<TYPE>-YYYYMMDD-NNN` where `NNN` is the next sequential number in that file today
3. Before logging, scan `$LEARNINGS_BASE/.learnings/` for an existing entry with the same context keywords. If one exists, update its **Action** field and keep the existing ID — do not create a duplicate.
4. Write the entry using the four-field format:
   ```markdown
   ### LRN-20260520-001
   **Status**: pending
   **Context**: <one sentence — what was happening>
   **Content**: <the learning, error description, or feature request>
   **Action**: <what was done or should be done>
   ```
5. If the fix was applied in this same session, immediately set `Status: resolved` and record what was done in **Action**.
6. Append to the correct file without modifying any existing entries
7. Confirm: "Logged as `<ID>` in `$LEARNINGS_BASE/.learnings/<FILE>.md`"

Reference: `references/agent-self-improve.md` → Entry format, Recurring Pattern Detection

## Mode: resume

Resume an incomplete task after context compaction or session interruption.

Steps:
1. Read `$LEARNINGS_BASE/memory/working-buffer.md` — identify current task and last `[x]` step
2. Check the buffer's last-modified date:
   - If the buffer is **3 or more days old**, warn: "Working buffer is N days old — state may be stale. Verify resources before resuming."
   - If the buffer is **7 or more days old**, surface as a blocker: "Buffer is N days old. Recommended to clear and start fresh unless you can verify all resource state."
3. Read `$LEARNINGS_BASE/memory/SESSION-STATE.md` — reload corrections, preferences, and decisions
4. Read today's `$LEARNINGS_BASE/memory/YYYY-MM-DD.md` — reload recent session exchanges
5. Verify the actual state of affected resources before continuing:
   - Files: check they exist and have expected content
   - Kubernetes: `kubectl get <resource> -n <namespace>`
   - Terraform: `terraform state list`
   - Git: `git log --oneline -5`
6. Resume from the first `[ ]` step — do not re-run already-committed steps
7. If a WAL entry shows `Status: PENDING`, determine whether the operation completed (check the resource) and update to `COMMITTED` or `ROLLED_BACK` accordingly

Never ask "where were we?" — the buffer and session state answer that.

Reference: `references/agent-self-improve.md` → Compaction Recovery, SESSION-STATE

## Mode: review

Scan `$LEARNINGS_BASE/.learnings/` for recurring patterns and surface actionable items.

Steps:
1. Read all three `$LEARNINGS_BASE/.learnings/` files
2. Group entries by context keyword similarity
3. Report any context that appears three or more times as a **promotion candidate**:
   ```
   PROMOTION CANDIDATE — ERR: "missing resource limits"
   Entries: ERR-20260518-001, ERR-20260519-002, ERR-20260520-001
   Suggested target: .github/copilot-instructions.md → "Always add resource limits"
   ```
4. Report entries still in `pending` state older than 7 days
5. Report entries in `resolved` state older than 30 days — these are stale and should be either promoted or discarded:
   ```
   STALE RESOLVED — LRN-20260410-001: "helm diff before upgrade" (45 days in resolved)
   Action: run /platform-skills:self-improve promote LRN-20260410-001 or set Status: discarded
   ```
6. Report unresolved `FEAT` entries that could be addressed by an existing platform-skills domain
7. Process `$LEARNINGS_BASE/.learnings/.pending-errors.log` if it exists and is non-empty — convert each line to a proper `ERR` entry and clear the log
8. Print totals:
   ```
   Learnings: 8 total, 3 pending, 5 resolved (1 stale)
   Errors: 5 total, 1 pending, 4 resolved
   Feature requests: 2 total, 2 pending
   Promotion candidates: 1 | Stale resolved: 1
   ```

Reference: `references/agent-self-improve.md` → Recurring Pattern Detection

## Mode: promote

Promote a resolved entry to the correct memory file.

Steps:
1. Read the entry by ID (e.g. `ERR-20260520-001`)
2. Determine if this rule applies globally (all projects) or locally (this project only):
   - **Global** — applies regardless of which project is open → promote to `~/.claude/CLAUDE.md` under `## Agent Rules`
   - **Project** — applies only in this repo → promote to `CLAUDE.md` / `AGENTS.md` or `.github/copilot-instructions.md`

3. Identify the correct promotion target:
   | Target | Scope | When to use |
   |---|---|---|
   | `~/.claude/CLAUDE.md` → `## Agent Rules` | Global | Rule applies across all projects (only available for global setup) |
   | `CLAUDE.md` / `AGENTS.md` | Project | Agent-level rules for this project only |
   | `.github/copilot-instructions.md` | Project | GitHub Copilot workspace rules |
   | A `references/` guide | Shared | Reusable pattern for the whole team |

4. Draft the promoted line — imperative voice, ≤ 80 characters:
   - ERR → negative rule: "Never use `kubectl delete` without first capturing the manifest"
   - LRN → positive rule: "Prefer `helm diff upgrade` before `helm upgrade` to preview changes"
5. Ask the user to confirm the target file and wording before writing
6. Append to the confirmed target file under `## Agent Rules` or `## Platform Rules`
7. Update the entry `Status` in `$LEARNINGS_BASE/.learnings/` from `resolved` to `promoted`
8. Commit with a conventional commit message:
   `docs(memory): promote <ID> — <imperative summary>`

Reference: `references/agent-self-improve.md` → Entry lifecycle, Promotion targets

## Mode: state

Capture a correction, preference, decision, or proper noun to `memory/SESSION-STATE.md`.

Steps:
1. Classify the signal:
   - **Correction** — user ruled something out or redirected approach
   - **Preference** — stated preference for this project or session
   - **Decision** — a choice was made between options
   - **Proper noun** — cluster name, team name, account ID, service name
2. Append to the correct section in `$LEARNINGS_BASE/memory/SESSION-STATE.md`:
   ```markdown
   - YYYY-MM-DD — <one sentence capturing what was said or decided>
   ```
3. Update the `Last updated:` timestamp at the top of the file
4. Confirm: "Captured to `$LEARNINGS_BASE/memory/SESSION-STATE.md`"

**When to invoke proactively (without being asked):**
- User corrects an assumption mid-session
- User states a preference ("I prefer X", "don't do Y here")
- A decision is reached between two approaches
- A non-obvious proper noun appears that isn't in project docs

Reference: `references/agent-self-improve.md` → SESSION-STATE, Compaction Recovery

## Mode: status

Print a one-screen health summary of the self-improve workspace — no changes made.

```
/platform-skills:self-improve status
```

Steps:
1. Resolve `LEARNINGS_BASE` (same auto-detection as all other modes)
2. Read all three `$LEARNINGS_BASE/.learnings/` files and `$LEARNINGS_BASE/memory/working-buffer.md`
3. Print the summary:
   ```
   Self-Improve Status
   ───────────────────────────────────────────────
   Workspace:   ~/.claude/ (global)            [or: ./  (local)]
   
   Learnings    3 pending   8 resolved   2 promoted
   Errors       1 pending   4 resolved   0 promoted
   Feature reqs 2 pending   0 resolved   0 promoted
   
   Pending errors log:  2 unprocessed entries
   Working buffer:      active task — "deploy payments service"
   Buffer age:          2 days
   Last session:        2026-05-23 (today)
   Sessions since review: 3 of 5
   
   Action items:
     • 1 pending ERR older than 7 days → run review
     • 2 stale resolved LRN (30+ days) → promote or discard
     • Run /platform-skills:self-improve review (due in 2 sessions)
   ───────────────────────────────────────────────
   ```
4. If `.pending-errors.log` is non-empty, note count but do not drain it (status is read-only)
5. If no action items exist, print: "✓ Workspace is healthy"

Reference: `references/agent-self-improve.md` → Entry lifecycle

---

## Mode: migrate

Move the workspace from one scope to the other without losing any entries.

```
/platform-skills:self-improve migrate global   # project-local → ~/.claude/
/platform-skills:self-improve migrate local    # ~/.claude/ → current project
```

Steps:
1. Detect the **source** location:
   - `migrate global`: source is `.learnings/` and `memory/` in `$PWD`
   - `migrate local`: source is `~/.claude/.learnings/` and `~/.claude/memory/`
2. Detect the **target** location (opposite of source)
3. If target already has entries, ask the user:
   - **Merge** — append source entries to target files (default)
   - **Replace** — overwrite target with source
   - **Cancel** — abort with no changes
4. Write a WAL entry to `$LEARNINGS_BASE/memory/working-buffer.md` before moving anything
5. Copy all `.learnings/*.md` entries and `memory/` files to the target
6. Verify the target has all entries (count matches source)
7. Ask the user to confirm deletion of the source directory before removing it
8. Print migration summary:
   ```
   Migrated to ~/.claude/ (global):
   ✓ .learnings/LEARNINGS.md  — 8 entries
   ✓ .learnings/ERRORS.md     — 5 entries
   ✓ .learnings/FEATURE_REQUESTS.md — 2 entries
   ✓ memory/working-buffer.md
   ✓ memory/SESSION-STATE.md
   Source removed: ./.learnings/, ./memory/
   ```
9. If the source had hooks in `.claude/settings.json`, offer to update them for the new scope

Reference: `references/agent-self-improve.md` → Global vs project scope

---

## Proactive Agent Protocols

These protocols run automatically when the proactive agent pattern is active. No explicit mode is required.

### WAL Protocol

Before any destructive or hard-to-reverse operation:
1. Write a WAL entry to `$LEARNINGS_BASE/memory/working-buffer.md` before acting
2. Format:
   ```markdown
   ## WAL Entry — YYYY-MM-DD HH:MM
   **Operation**: <what is about to happen>
   **Affected resources**: <list files, K8s resources, cloud resources>
   **Blast radius**: <what could break>
   **Rollback**: <exact command to undo>
   **Status**: PENDING
   ```
3. Proceed with the operation
4. Update `Status` to `COMMITTED` after success
5. Update to `ROLLED_BACK` if aborted

Destructive operations requiring a WAL entry: deleting files, `git reset --hard`, `git push --force`, `terraform destroy`, dropping database tables, modifying shared infrastructure.

### Working Buffer

Maintain `$LEARNINGS_BASE/memory/working-buffer.md` as a live task scratchpad:
- Write at task start with the plan and steps
- Update after each significant step with `[x]` progress markers
- At ~60% context: write a compaction-ready summary proactively — do not wait for a compaction event
- Read at session start to resume after compaction
- Do not delete the buffer at session end if the task is incomplete

### SESSION-STATE

Maintain `$LEARNINGS_BASE/memory/SESSION-STATE.md` as always-on session capture. Write to it **before responding** whenever:
- The user corrects an assumption or rules out an approach
- A preference is stated
- A decision is made between options
- A non-obvious proper noun or fact is encountered

This file is the second read in compaction recovery (after working-buffer, before daily notes).

### Daily Notes

Write notable exchanges, discoveries, and outcomes to `$LEARNINGS_BASE/memory/YYYY-MM-DD.md` (today's date). One file per day, append-only. Read today's file at session start alongside the working buffer.

### Verify Before Reporting (VBR)

Before reporting a task as complete:
- Run the validation command (CI check, test suite, `kubectl get`, `terraform plan`)
- Read the file that was changed to confirm the edit landed
- Text change ≠ behavior change — test actual outcomes

Never claim a fix is done based on the intent to fix it. Evidence required.

### ADL Protocol

When choosing between implementation approaches, apply this priority:
```
Stability > Explainability > Reusability > Scalability > Novelty
```
Log the decision in the buffer when it was a non-obvious choice.

### VFM Scoring

Before unsolicited proactive action, score against four dimensions (max 100). Act only if score ≥ 50:
- High Frequency (×3) — will this recur?
- Failure Reduction (×3) — prevents real breakage?
- User Burden (×2) — saves meaningful user effort?
- Self Cost (×2) — low effort for the agent?

Check `CLAUDE.md` or `AGENTS.md` for `VFM_THRESHOLD=<N>` before applying the default of 50. Use that value if present.

### Heartbeat

For tasks > 10 steps or > 5 minutes, report progress without waiting to be asked:
```
[Heartbeat] Completed 4/7 steps. Currently: <step>. Next: <step>.
```

### Reverse Prompting

Ask one clarifying question before acting on ambiguous or high-risk instructions. Never ask more than one question per instruction.
