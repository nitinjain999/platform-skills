---
name: self-improve
description: Bootstrap and operate a self-improving agent workspace. Scaffolds .learnings/ and memory/ directories, captures errors and learnings during a session, detects recurring patterns, recalls verified lessons, and promotes stable entries to scoped rule files (.claude/rules/ or ~/.claude/rules/). Also implements the Proactive Agent pillars — WAL protocol, working buffer, SESSION-STATE, daily notes, VBR, VFM scoring, ADL decision logic, heartbeat, and reverse prompting. Use when asked to "remember this lesson", "set up agent memory", "log that error", "what did we learn about X", "promote learnings", "revoke that rule", "capture session state", or "enable proactive mode".
argument-hint: "[init [global|local]|log [LRN|ERR|FEAT]|recall <terms>|promote <ID>|revoke <ID> <reason>|migrate [global|local]|status|resume|review|state]"
title: "Self-Improve Command"
sidebar_label: "self-improve"
custom_edit_url: null
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

Promoted rules follow the **entry's** `Scope`, not `LEARNINGS_BASE`: a global lesson lands in `~/.claude/rules/<domain>.md`, a project lesson in `.claude/rules/<domain>.md`. The opt-in targets (`CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`) are always project-local. Only the capture files follow `LEARNINGS_BASE`.

Reference: `references/agent-self-improve.md` → Global vs project scope

## Helper Script

Modes below run `bash ~/.claude/scripts/learnings.sh <subcommand>` for anything deterministic: reading entries, validating them, checking dates, changing a status. If the script is missing, say so once, offer to install it (`init global` step 5), and do the step by hand. Exit code 3 means another session holds `.learnings/.drain.lock`. Wait a few seconds and retry once. Exit code 4 means the entry doesn't exist.

Reference: `references/agent-self-improve.md` → Helper script

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
5. Detect the user's platform and offer to wire all four hooks (`SessionStart`, `SessionEnd`, `PostToolUseFailure`, `PreCompact`) in `~/.claude/settings.json`:
   - **macOS / Linux / WSL / Git Bash** → `self-improve-hook.sh` with the `session-start`, `session-end`, `tool-failure` and `precompact` subcommands; point to `settings.json.example`
   - **Windows native (PowerShell)** → `self-improve-hook.ps1`, same four subcommands; point to `settings-windows.json.example`, and have the user replace the literal `C:\Users\alex` with their own profile path
   - **Alpine or minimal Linux** → same as macOS/Linux but remind the user to install bash first: `apk add bash`
   - Also copy `examples/agent-self-improve/scripts/learnings.sh` to `~/.claude/scripts/` and `chmod +x` it. `log`, `recall`, `review`, `status`, `promote` and `revoke` call it
   - The script is in `examples/agent-self-improve/scripts/`. Keep `"timeout": 10` on `SessionEnd` and on `PreCompact`, and `"async": true` on `PostToolUseFailure`
   - `PreCompact` takes no `matcher`; it is filtered by its `trigger` field (`manual` or `auto`), not by tool name. Do not wire a `PostCompact` hook: `SessionStart` already fires again with `source=compact`
   - If any settings file still contains `Stop`, `PreToolUse` or `PostToolUse` self-improve entries, point the user at "Migrating from the legacy hooks" in `examples/agent-self-improve/README.md` and do not leave both wirings active
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
   - **PostToolUseFailure** → `self-improve-hook.sh tool-failure` with `"async": true`. The script resolves `.learnings/` itself, so the same command works at either scope
   - **PreCompact** → `self-improve-hook.sh precompact` with `"timeout": 10`. This drains captured failures at each compaction, which is the only consolidation that still happens when a session is killed rather than closed
   - Note: the `SessionStart` and `SessionEnd` hooks should be wired globally via `~/.claude/settings.json` even for project-local learnings
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
3. Before logging, run `bash ~/.claude/scripts/learnings.sh recall --all <2-3 keywords from the Context>` to find an existing entry for the same root cause. If one exists, update its **Action**, set **Verified** to today, and keep the existing ID. Don't create a duplicate. If the new lesson *replaces* an older one, write the new entry with `**Supersedes**: <old-id>` and run `bash ~/.claude/scripts/learnings.sh set-status <old-id> superseded --note "replaced by <new-id>"`
4. Run `bash ~/.claude/scripts/learnings.sh whereami` for the scope and project name, then write the entry:
   ```markdown
   ### LRN-20260520-001
   **Status**: pending
   **Context**: <one sentence — what was happening>
   **Content**: <the learning, error description, or feature request>
   **Action**: <what was done or should be done>
   **Source**: <user | observed | ci | repo | vendor-docs | inferred>
   **Scope**: <global | project:<name>>
   **Verified**: <today, YYYY-MM-DD>
   ```
   - **Source**: `user` when the user stated it, `observed` or `ci` when a tool result proved it, `repo` or `vendor-docs` when documentation says so, `inferred` when you concluded it yourself. Pick honestly: `inferred` goes stale in 30 days and needs confirmation before promotion
   - **Scope**: `global` only when the lesson holds in any repository. Otherwise use `project:<name>` from `whereami`. Project-specific details must not leak into global memory
   - Add `**Paths**: <glob>, <glob>` when the lesson only concerns certain files, and `**Expires**: <date>` for a workaround or exception with a known end
5. If the fix was applied in this same session, immediately set `Status: resolved` and record what was done in **Action**.
6. Append to the correct file without modifying any existing entries
7. Run `bash ~/.claude/scripts/learnings.sh lint` and fix any `ERROR` line that names the new entry
8. Confirm: "Logged as `<ID>` in `$LEARNINGS_BASE/.learnings/<FILE>.md`"

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
2. Run `bash ~/.claude/scripts/learnings.sh lint`. Report every `ERROR` (fix it), every `EXPIRED` (ask whether to extend `Expires` or revoke), and every `STALE` (check the current state, then either update `Verified` or revoke). Put a `STALE` line that says "its promoted rule is still loaded" first
3. Group entries by context keyword similarity
4. Report any context that appears three or more times as a **promotion candidate**:
   ```
   PROMOTION CANDIDATE — ERR: "missing resource limits"
   Entries: ERR-20260518-001, ERR-20260519-002, ERR-20260520-001
   Suggested target: .github/copilot-instructions.md → "Always add resource limits"
   ```
5. Report entries still in `pending` state older than 7 days
6. Report entries in `resolved` state older than 30 days — these are stale and should be either promoted or discarded:
   ```
   STALE RESOLVED — LRN-20260410-001: "helm diff before upgrade" (45 days in resolved)
   Action: run /platform-skills:self-improve promote LRN-20260410-001 or set Status: discarded
   ```
7. Report unresolved `FEAT` entries that could be addressed by an existing platform-skills domain
8. Process `$LEARNINGS_BASE/.learnings/.pending-errors.log` if it exists and is non-empty — convert each line to a proper `ERR` entry and clear the log
9. Print totals:
   ```
   Learnings: 8 total, 3 pending, 5 resolved (1 stale)
   Errors: 5 total, 1 pending, 4 resolved
   Feature requests: 2 total, 2 pending
   Promotion candidates: 1 | Stale resolved: 1
   ```

Reference: `references/agent-self-improve.md` → Recurring Pattern Detection

## Mode: recall

Search learnings without changing anything.

```
/platform-skills:self-improve recall karpenter pod identity
```

Steps:
1. Run `bash ~/.claude/scripts/learnings.sh recall <terms>`. Add `--limit N` to see more than 8 results. Add `--all` to include revoked, superseded, discarded, expired and other-project entries, which are flagged
2. Relay each result with how far to trust it:
   - `STALE` or `verify before use`: check the current state (repository, cluster, docs) before relying on it, and say that you're checking
   - No flag, source `user`, `ci` or `observed`: apply it and cite the ID
3. If recall reports excluded entries, mention them. A revoked lesson that matches is a warning worth hearing
4. If nothing matches, say so. Never invent a memory

Reference: `references/agent-self-improve.md` → Helper script

## Mode: promote

Promote a resolved entry to the correct memory file.

Steps:
1. Read the entry by ID. Promotion changes behaviour in every future session, so `learnings.sh promote` refuses entries that:
   - aren't `resolved`
   - lack `Source`, `Scope` or `Verified`
   - are stale or expired
   - come from an `inferred` source, unless the user confirms the lesson and you pass `--allow-inferred`
   - are scoped to another project

   Relay a refusal as-is and help fix its cause. For example, re-verify the lesson and update `Verified`.
2. Pick the domain: a lowercase topic name (`terraform`, `kubernetes`, `github-actions`). The rule lands in `<domain>.md`
3. Draft the rule: imperative voice, one line, at most 160 characters:
   - ERR → negative rule: "Never use `kubectl delete` without first capturing the manifest"
   - LRN → positive rule: "Prefer `helm diff upgrade` before `helm upgrade` to preview changes"
4. Preview. This prints the evidence, the target and a diff, and writes nothing:
   ```bash
   bash ~/.claude/scripts/learnings.sh promote <ID> --domain <domain> --rule "<rule>"
   ```
   | Entry scope | Default target | Loaded |
   |---|---|---|
   | `global` | `~/.claude/rules/<domain>.md` | Every session on this machine |
   | `project:<name>` with `Paths` | `.claude/rules/<domain>.md` with `paths:` frontmatter | When Claude reads a matching file |
   | `project:<name>` without `Paths` | `.claude/rules/<domain>.md` | Every session in this project |

   When the team needs the rule in a file other tools read, pass `--target CLAUDE.md`, `--target AGENTS.md` or `--target .github/copilot-instructions.md`. The rule goes under `## Agent Rules`. A rule with `Paths` can only go to `.claude/rules/`
5. Show the preview and ask the user to confirm the target and wording
6. Apply: re-run with `--apply`. The script writes the rule with a `<!-- self-improve:<ID> -->` marker and sets the entry to `promoted`, recording the target in `Status-Note`
7. For a target inside the repository, commit with a conventional commit message:
   `docs(memory): promote <ID> — <imperative summary>`

Rollback: `bash ~/.claude/scripts/learnings.sh unpromote <ID>` removes the marked line and sets the entry back to `resolved`.

Reference: `references/agent-self-improve.md` → Entry lifecycle, Promotion targets

## Mode: revoke

Stop a lesson from influencing behaviour while keeping its history.

```
/platform-skills:self-improve revoke ERR-20260520-001 "wrong since EKS 1.35"
```

Steps:
1. Ask for the reason if none was given. A revocation without a reason can't be audited later
2. If a newer entry replaces this one, use `superseded` instead: set `**Supersedes**: <ID>` on the newer entry and run `set-status <ID> superseded`
3. Retire it. If the entry is `promoted`, run `bash ~/.claude/scripts/learnings.sh unpromote <ID> --revoke --note "<reason>"`. That removes the marked rule from every promotion target and sets `revoked` in one step. If it reports that no rule carries the marker (the rule predates markers), remove the line by hand first. Otherwise run `bash ~/.claude/scripts/learnings.sh set-status <ID> revoked --note "<reason>"`
4. Confirm: "Revoked `<ID>`: <reason>"

Reference: `references/agent-self-improve.md` → Entry lifecycle

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
2. Read all three `$LEARNINGS_BASE/.learnings/` files and `$LEARNINGS_BASE/memory/working-buffer.md`. Also run `bash ~/.claude/scripts/learnings.sh lint`.
3. Print the summary:
   ```
   Self-Improve Status
   ───────────────────────────────────────────────
   Workspace:   ~/.claude/ (global)            [or: ./  (local)]
   
   Learnings    3 pending   8 resolved   2 promoted
   Errors       1 pending   4 resolved   0 promoted
   Feature reqs 2 pending   0 resolved   0 promoted
   
   Pending errors log:  2 unprocessed entries
   Lint:                0 errors, 2 stale, 1 expired, 5 without metadata
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

> Load this section only when the user has run `init` or explicitly enables proactive mode.

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
