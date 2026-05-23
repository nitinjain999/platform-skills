# session-start-reminder.ps1 — wired to the PreToolUse hook in ~/.claude/settings.json (Windows)
# PowerShell equivalent of session-start-reminder.sh — injects a memory-load
# reminder before the first tool use of each new session, then stays silent.
#
# Requires: PowerShell 5.1+ (built into Windows 10/11) or PowerShell 7+
#
# Install: add to %USERPROFILE%\.claude\settings.json:
#   "hooks": { "PreToolUse": [{ "matcher": ".*", "hooks": [{ "type": "command",
#     "command": "powershell -NonInteractive -File %USERPROFILE%\\.claude\\scripts\\session-start-reminder.ps1" }] }] }

$ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
$MemoryDir    = Join-Path $ClaudeDir 'memory'
$SessionMarker = Join-Path $MemoryDir '.session-active'
$DATE = Get-Date -Format 'yyyy-MM-dd'

# Already active this session — stay silent
if (Test-Path $SessionMarker) { exit 0 }

# Mark session as active to prevent repeat output on subsequent tool calls
New-Item -ItemType Directory -Force -Path $MemoryDir | Out-Null
New-Item -ItemType File -Force -Path $SessionMarker | Out-Null

Write-Host "╔══════════════════════════════════════════════════════════╗"
Write-Host "║  SESSION START — load memory before proceeding           ║"
Write-Host "╠══════════════════════════════════════════════════════════╣"
Write-Host "║  Read these files now:                                   ║"
Write-Host "║  1. ~/.claude/memory/working-buffer.md  (active task)    ║"
Write-Host "║  2. ~/.claude/memory/SESSION-STATE.md   (preferences)    ║"

$DailyNote = Join-Path $MemoryDir "$DATE.md"
if (Test-Path $DailyNote) {
    Write-Host "║  3. ~/.claude/memory/$DATE.md  (today)      ║"
}

# Surface active task if present
$BufferFile = Join-Path $MemoryDir 'working-buffer.md'
if (Test-Path $BufferFile) {
    $Content = Get-Content $BufferFile -Raw -ErrorAction SilentlyContinue
    if ($Content -match '(?m)^## Current Task\r?\n(.+)') {
        $Task = $Matches[1].Trim()
        if ($Task -and $Task -notmatch 'No active task') {
            $Short = if ($Task.Length -gt 44) { $Task.Substring(0, 44) } else { $Task }
            Write-Host "║                                                          ║"
            Write-Host ("║  Active task: {0,-44}║" -f $Short)
        }
    }
}

# Warn if unprocessed tool errors are waiting
$PendingLog = Join-Path $ClaudeDir '.learnings' '.pending-errors.log'
if ((Test-Path $PendingLog) -and (Get-Item $PendingLog).Length -gt 0) {
    $ErrorCount = (Get-Content $PendingLog | Where-Object { $_ -ne '' }).Count
    Write-Host "║                                                          ║"
    Write-Host ("║  {0,-56}║" -f "WARNING: $ErrorCount unprocessed error(s) in .pending-errors.log")
}

Write-Host "╚══════════════════════════════════════════════════════════╝"
