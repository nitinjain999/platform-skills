---
name: self-improve
description: Bootstrap and operate a self-improving agent workspace. Scaffolds .learnings/ and memory/ directories, captures errors and learnings during a session, detects recurring patterns, and promotes stable entries to project memory (CLAUDE.md, AGENTS.md, or references/). Also implements the Proactive Agent pillars — WAL protocol, working buffer, VFM scoring, ADL decision logic, heartbeat, and reverse prompting. Use when asked to "remember this lesson", "set up agent memory", "log that error", "promote learnings", or "enable proactive mode".
argument-hint: "[init|log|review|promote] [description or file path]"
---

Bootstrap and operate a self-improving, proactive agent workspace.

## Mode: init

Scaffold the `.learnings/` and `memory/` directories in the current project.

Steps:
1. Check whether `.learnings/` already exists — if so, skip creation and report the existing state
2. Create the directory structure:
   ```
   .learnings/
     LEARNINGS.md
     ERRORS.md
     FEATURE_REQUESTS.md
   memory/
     working-buffer.md
   ```
3. Seed each file with the correct header and an example entry marked `Status: example`
4. Check `.gitignore` — ask the user whether these files should be committed or gitignored
5. If a `.claude/settings.json` exists, offer to add the PostToolUse hook for automatic error capture
6. Print the bootstrap summary:
   ```
   ✓ .learnings/LEARNINGS.md   — positive learnings
   ✓ .learnings/ERRORS.md      — mistakes and root causes
   ✓ .learnings/FEATURE_REQUESTS.md — recurring unmet needs
   ✓ memory/working-buffer.md  — WAL scratchpad and task state
   ```
7. Remind the user to run `/platform-skills:self-improve review` after a few sessions to promote recurring patterns

Reference: `references/agent-self-improve.md` → Directory layout, Entry format

## Mode: log

Log a learning, error, or feature request to the appropriate file.

Steps:
1. Classify the entry:
   - **Learning** (`LRN`) — a technique, pattern, or shortcut that worked
   - **Error** (`ERR`) — a mistake, misunderstanding, or failed assumption
   - **Feature request** (`FEAT`) — a need that was unmet by the current skill or tool set
2. Generate the ID: `<TYPE>-YYYYMMDD-NNN` where `NNN` is the next sequential number in that file today
3. Before logging, scan `.learnings/` for an existing entry with the same context keywords. If one exists, update its **Action** field and keep the existing ID — do not create a duplicate.
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
7. Confirm: "Logged as `<ID>` in `.learnings/<FILE>.md`"

Reference: `references/agent-self-improve.md` → Entry format, Recurring Pattern Detection

## Mode: resume

Resume an incomplete task after context compaction or session interruption.

Steps:
1. Read `memory/working-buffer.md`
2. Identify the last completed step (last `[x]` marker)
3. Verify the actual state of affected resources before continuing:
   - Files: check they exist and have expected content
   - Kubernetes: `kubectl get <resource> -n <namespace>`
   - Terraform: `terraform state list`
   - Git: `git log --oneline -5`
4. Resume from the first `[ ]` step — do not re-run already-committed steps
5. If a WAL entry shows `Status: PENDING`, determine whether the operation completed (check the resource) and update to `COMMITTED` or `ROLLED_BACK` accordingly

Reference: `references/agent-self-improve.md` → Compaction Recovery

## Mode: review

Scan `.learnings/` for recurring patterns and surface promotion candidates.

Steps:
1. Read all three `.learnings/` files
2. Group entries by context keyword similarity
3. Report any context that appears three or more times as a **promotion candidate**:
   ```
   PROMOTION CANDIDATE — ERR: "missing resource limits"
   Entries: ERR-20260518-001, ERR-20260519-002, ERR-20260520-001
   Suggested target: .github/copilot-instructions.md → "Always add resource limits"
   ```
4. Report entries still in `pending` state older than 7 days
5. Report unresolved `FEAT` entries that could be addressed by an existing platform-skills domain
6. Print totals:
   ```
   Learnings: 8 total, 3 pending, 5 resolved
   Errors: 5 total, 1 pending, 4 resolved
   Feature requests: 2 total, 2 pending
   Promotion candidates: 1
   ```

Reference: `references/agent-self-improve.md` → Recurring Pattern Detection

## Mode: promote

Promote a resolved entry to a project memory file.

Steps:
1. Read the entry by ID (e.g. `ERR-20260520-001`)
2. Identify the correct promotion target:
   | Target | When to use |
   |---|---|
   | `CLAUDE.md` / `AGENTS.md` | Agent-level rules that apply to every session in this project |
   | `.github/copilot-instructions.md` | Copilot workspace rules |
   | A `references/` guide | Reusable pattern for the whole team |
3. Draft the promoted line — use imperative voice, ≤ 80 characters:
   - ERR → negative rule: "Never use `kubectl delete` without first capturing the manifest"
   - LRN → positive rule: "Prefer `helm diff upgrade` before `helm upgrade` to preview changes"
4. Ask the user to confirm the target file and the promoted line before writing
5. Append to the confirmed target file under a `## Agent Rules` or `## Platform Rules` heading
6. Update the entry `Status` in `.learnings/` from `resolved` to `promoted`
7. Commit the change with a conventional commit message:
   `docs(memory): promote <ID> — <imperative summary>`

Reference: `references/agent-self-improve.md` → Entry lifecycle, Promotion targets

## Proactive Agent Protocols

These protocols run automatically when the proactive agent pattern is active. No explicit mode is required.

### WAL Protocol

Before any destructive or hard-to-reverse operation:
1. Write a WAL entry to `memory/working-buffer.md` before acting
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

Maintain `memory/working-buffer.md` as a live task scratchpad:
- Write at task start with the plan and steps
- Update after each significant step with `[x]` progress markers
- Read at session start to resume after compaction
- Do not delete the buffer at session end if the task is incomplete

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
