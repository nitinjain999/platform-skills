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
| `scripts/self-improve-hook.sh` | All four hooks (macOS/Linux/WSL/Git Bash). One script, four subcommands |
| `scripts/self-improve-hook.ps1` | Same four hooks for Windows native PowerShell 5.1+ |
| `tests/self_improve_hook_test.sh` | Behavioural suite, run against both implementations |
| `scripts/learnings.sh` | Deterministic helper the command calls: parse, lint and change the status of `.learnings/` entries |
| `tests/learnings_test.sh` | Behavioural suite for `learnings.sh` |
| `global-claude.md` | Template for `~/.claude/CLAUDE.md` — path override, session-start, in-session logging rules |
| `settings.json.example` | All 4 hooks wired for macOS / Linux / WSL / Git Bash |
| `settings-windows.json.example` | All 4 hooks wired for Windows native (PowerShell) |

## Platform support

| Platform | Hook script | Settings file |
|---|---|---|
| macOS | `self-improve-hook.sh` | `settings.json.example` |
| Linux (Ubuntu, Debian, RHEL, Fedora, Arch) | `self-improve-hook.sh` | `settings.json.example` |
| Linux (Alpine, busybox-only) | Install bash first: `apk add bash` | `settings.json.example` |
| Windows — WSL or Git Bash | `self-improve-hook.sh` | `settings.json.example` |
| Windows — native PowerShell | `self-improve-hook.ps1` | `settings-windows.json.example` |

**Windows recommendation:** WSL (Windows Subsystem for Linux) or Git Bash is the simplest path — no PowerShell script needed, and the bash setup is identical to macOS/Linux. Use the native PowerShell script only if you cannot use WSL or Git Bash.

The bash script needs bash 3.2 or newer. `jq` is optional: without it a `sed` fallback reads the handful of scalar fields the hooks use. The PowerShell script needs 5.1 or newer, and both write UTF-8 without a BOM using LF endings, so the two can share one workspace.

The global config directory (`~/.claude/`) resolves to the same location on all platforms:
- macOS / Linux: `~/.claude/` → `/Users/<you>/.claude/` or `/home/<you>/.claude/`
- Windows: `~/.claude/` → `C:\Users\<you>\.claude\` (Node.js `os.homedir()` resolves `~`)
- WSL / Git Bash on Windows: same as Linux above

## Usage

The recommended approach is to run the init command — it asks whether you want global or project-local setup before creating anything:

```
/platform-skills:self-improve init
```

Or copy manually:

```bash
# macOS / Linux / WSL / Git Bash — global setup (recommended for individuals)
cp -r examples/agent-self-improve/.learnings ~/.claude/
cp -r examples/agent-self-improve/memory ~/.claude/

# macOS / Linux / WSL / Git Bash — project-local setup (shareable with the team)
cp -r examples/agent-self-improve/.learnings .
cp -r examples/agent-self-improve/memory .
```

For project-local setup, add to `.gitignore` for personal-only notes (recommended — daily notes grow fast):
```
.learnings/
memory/
```

Commit `.learnings/` only if you want the team to share and build on these learnings; keep `memory/` local.

### Wire the hooks — macOS / Linux / WSL / Git Bash

```bash
# Copy the hook script
mkdir -p ~/.claude/scripts
cp examples/agent-self-improve/scripts/self-improve-hook.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/self-improve-hook.sh
cp examples/agent-self-improve/scripts/learnings.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/learnings.sh

# Copy settings (merge manually if ~/.claude/settings.json already exists)
cp examples/agent-self-improve/settings.json.example ~/.claude/settings.json

# Copy global CLAUDE.md
cp examples/agent-self-improve/global-claude.md ~/.claude/CLAUDE.md
```

### Wire the hooks — Windows native (PowerShell)

```powershell
# Copy the hook script
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts"
Copy-Item examples\agent-self-improve\scripts\self-improve-hook.ps1 "$env:USERPROFILE\.claude\scripts\"
Copy-Item examples\agent-self-improve\scripts\learnings.sh "$env:USERPROFILE\.claude\scripts\"

# Copy settings (merge manually if settings.json already exists)
Copy-Item examples\agent-self-improve\settings-windows.json.example "$env:USERPROFILE\.claude\settings.json"

# Copy global CLAUDE.md
Copy-Item examples\agent-self-improve\global-claude.md "$env:USERPROFILE\.claude\CLAUDE.md"
```

`learnings.sh` is a bash script that the command runs through Claude Code's Bash tool (Git Bash on Windows).

Then edit the four `command` strings in `settings.json` and replace `C:\Users\alex` with your own profile directory. The paths are spelled out in full on purpose: a hook `command` is a raw string handed to a shell, so `%USERPROFILE%` is only expanded by `cmd` and `$env:USERPROFILE` only by PowerShell. A literal path works whichever shell Claude Code uses to spawn the hook. `echo $env:USERPROFILE` prints the value to paste in.

If you see an execution policy error when the hooks run, allow local scripts once:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

What the hooks do:

| Hook | Subcommand | Trigger | What it does |
|---|---|---|---|
| `SessionStart` | `session-start` | Startup, resume, clear, compact, fork | Prints the memory-load banner. Plain stdout becomes context Claude sees |
| `SessionEnd` | `session-end` | Session close | Saves daily notes, drains `.pending-errors.log` into ERR entries, records the session, nudges if no LRN was logged today |
| `PostToolUseFailure` | `tool-failure` | Every failed tool call | Appends one line to `.pending-errors.log` for batch processing at session end |
| `PreCompact` | `precompact` | Before each auto or manual compaction | Drains `.pending-errors.log` again, so a long session consolidates repeatedly instead of only at close |

Four details in the settings files are deliberate:

- `SessionEnd` sets `"timeout": 10`. Every `SessionEnd` hook shares a 1.5-second budget by default, which the drain can exceed on a busy day.
- `PostToolUseFailure` sets `"async": true` so a failing tool call is never slowed by the capture.
- `PreCompact` is wired because `SessionEnd` is not guaranteed to run. Close the window or kill the process and `.pending-errors.log` is never drained; a long session compacts several times, so the drain becomes recurring rather than once-at-the-end. This narrows the window, it does not close it: a session killed before it ever compacts, or one that fails a tool call after its last compaction, still leaves lines pending. Those lines are not lost. `SessionStart` counts them and warns, and the next `review` or `SessionEnd` drains them. `PreCompact` takes no `matcher` — its filter is the `trigger` field (`manual` or `auto`), not a tool name.
- Every path exits 0. A memory hook must never block a session, a tool call, or compaction. That matters most on `PreCompact`, which is one of the events where exit 2 aborts the operation: a hook that failed there would strand the session with a full context window.

`PreCompact` does not write a daily note and does not record a session. Compaction is not the end of a session. It also does not flag a `PENDING` WAL entry, which is a fault only once the session has closed — mid-session the operation may simply be in flight.

The capture records the tool name, session id and `tool_use_id` only. The `error` and `tool_input` fields are deliberately never persisted, because either can carry a credential.

## Migrating from the legacy hooks

Earlier versions wired `Stop`, `PreToolUse` and `PostToolUse` to four separate scripts. That wiring was wrong in two ways that are worth knowing if you are still running it:

- `Stop` fires at the end of **every assistant turn**, not at session end. The daily note gained a "Session closed" heading per turn and the session counter ran up at the same rate.
- `PostToolUse` never fires for a failed tool call, and the snippet it ran tested `$CLAUDE_TOOL_EXIT_CODE`, an environment variable Claude Code does not set. Failure capture recorded nothing at all.

To migrate:

```bash
# 1. Remove the old scripts
rm -f ~/.claude/scripts/session-end.sh ~/.claude/scripts/session-start-reminder.sh
rm -f ~/.claude/scripts/session-end.ps1 ~/.claude/scripts/session-start-reminder.ps1

# 2. Install the new one
cp examples/agent-self-improve/scripts/self-improve-hook.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/self-improve-hook.sh
```

3. In `~/.claude/settings.json`, delete the `Stop`, `PreToolUse` and `PostToolUse` self-improve entries and add the three blocks from `settings.json.example`. Leave any unrelated hooks on those events alone.

4. Delete the stale marker the old banner used: `rm -f ~/.claude/memory/.session-active`.

Nothing else needs touching. `.learnings/` and `memory/` file formats are unchanged, so existing notes, LRN and ERR entries carry over as they are. `SessionStart` scans `settings.json` and `settings.local.json` at both global and project scope and prints a warning for each one that still contains the old wiring, so you will be told if a copy was missed.

## Reference

- How it works (concepts, lifecycle, examples): [examples/agent-self-improve/HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- Full protocol reference: [references/agent-self-improve.md](../../references/agent-self-improve.md)
- Slash command specification: [commands/self-improve.md](../../commands/self-improve.md)
