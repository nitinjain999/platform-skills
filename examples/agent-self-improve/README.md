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
| `scripts/session-end.sh` | Stop hook (macOS/Linux/WSL): drains errors, saves daily notes, session counter, review reminder |
| `scripts/session-start-reminder.sh` | PreToolUse hook (macOS/Linux/WSL): injects memory-load banner at first tool use each session |
| `scripts/session-end.ps1` | Stop hook (Windows native PowerShell): same behaviour as `.sh` equivalent |
| `scripts/session-start-reminder.ps1` | PreToolUse hook (Windows native PowerShell): same behaviour as `.sh` equivalent |
| `global-claude.md` | Template for `~/.claude/CLAUDE.md` — path override, session-start, in-session logging rules |
| `settings.json.example` | All 3 hooks wired for macOS / Linux / WSL / Git Bash |
| `settings-windows.json.example` | All 3 hooks wired for Windows native (PowerShell) |

## Platform support

| Platform | Shell scripts | Settings file |
|---|---|---|
| macOS | `session-end.sh`, `session-start-reminder.sh` | `settings.json.example` |
| Linux (Ubuntu, Debian, RHEL, Fedora, Arch) | `session-end.sh`, `session-start-reminder.sh` | `settings.json.example` |
| Linux (Alpine, busybox-only) | Install bash first: `apk add bash` | `settings.json.example` |
| Windows — WSL or Git Bash | `session-end.sh`, `session-start-reminder.sh` | `settings.json.example` |
| Windows — native PowerShell | `session-end.ps1`, `session-start-reminder.ps1` | `settings-windows.json.example` |

**Windows recommendation:** WSL (Windows Subsystem for Linux) or Git Bash is the simplest path — no PowerShell scripts needed, and the bash setup is identical to macOS/Linux. Use the native PowerShell scripts only if you cannot use WSL or Git Bash.

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
# Copy scripts
mkdir -p ~/.claude/scripts
cp examples/agent-self-improve/scripts/session-end.sh ~/.claude/scripts/
cp examples/agent-self-improve/scripts/session-start-reminder.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/*.sh

# Copy settings (merge manually if ~/.claude/settings.json already exists)
cp examples/agent-self-improve/settings.json.example ~/.claude/settings.json

# Copy global CLAUDE.md
cp examples/agent-self-improve/global-claude.md ~/.claude/CLAUDE.md
```

### Wire the hooks — Windows native (PowerShell)

```powershell
# Copy scripts
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts"
Copy-Item examples\agent-self-improve\scripts\session-end.ps1 "$env:USERPROFILE\.claude\scripts\"
Copy-Item examples\agent-self-improve\scripts\session-start-reminder.ps1 "$env:USERPROFILE\.claude\scripts\"

# Copy settings (merge manually if settings.json already exists)
Copy-Item examples\agent-self-improve\settings-windows.json.example "$env:USERPROFILE\.claude\settings.json"

# Copy global CLAUDE.md
Copy-Item examples\agent-self-improve\global-claude.md "$env:USERPROFILE\.claude\CLAUDE.md"
```

If you see an execution policy error when the hooks run, allow local scripts once:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

What the hooks do:

| Hook | Trigger | What it does |
|---|---|---|
| `Stop` → `session-end.sh` / `.ps1` | Session close | Saves daily notes, drains `.pending-errors.log` → ERR entries, clears session marker, increments counter, nudges if no LRN logged |
| `PreToolUse` → `session-start-reminder.sh` / `.ps1` | First tool use per session | Prints memory-load banner once, silent after that |
| `PostToolUse` | Every failed tool call | Appends to `.pending-errors.log` for batch processing at session end |

## Reference

- How it works (concepts, lifecycle, examples): [examples/agent-self-improve/HOW_IT_WORKS.md](HOW_IT_WORKS.md)
- Full protocol reference: [references/agent-self-improve.md](../../references/agent-self-improve.md)
- Slash command specification: [commands/self-improve.md](../../commands/self-improve.md)
