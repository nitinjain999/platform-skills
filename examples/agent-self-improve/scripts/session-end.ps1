# session-end.ps1 — wired to the Stop hook in ~/.claude/settings.json (Windows)
# PowerShell equivalent of session-end.sh — auto-captures session state,
# drains pending errors, and manages session lifecycle.
#
# Requires: PowerShell 5.1+ (built into Windows 10/11) or PowerShell 7+
#
# Install: add to %USERPROFILE%\.claude\settings.json:
#   "hooks": { "Stop": [{ "hooks": [{ "type": "command",
#     "command": "powershell -NonInteractive -File %USERPROFILE%\\.claude\\scripts\\session-end.ps1" }] }] }

$DATE = Get-Date -Format 'yyyy-MM-dd'
$TIME = Get-Date -Format 'HH:mm'
$ClaudeDir   = Join-Path $env:USERPROFILE '.claude'
$LearningsDir = Join-Path $ClaudeDir '.learnings'
$MemoryDir   = Join-Path $ClaudeDir 'memory'
$Daily        = Join-Path $MemoryDir "$DATE.md"
$SessionState = Join-Path $MemoryDir 'SESSION-STATE.md'
$Buffer       = Join-Path $MemoryDir 'working-buffer.md'
$ErrorsFile   = Join-Path $LearningsDir 'ERRORS.md'
$LearningsFile = Join-Path $LearningsDir 'LEARNINGS.md'
$PendingLog   = Join-Path $LearningsDir '.pending-errors.log'
$SessionMarker = Join-Path $MemoryDir '.session-active'
$SessionCounter = Join-Path $MemoryDir '.session-count'

New-Item -ItemType Directory -Force -Path $LearningsDir | Out-Null
New-Item -ItemType Directory -Force -Path $MemoryDir    | Out-Null

# ── Daily notes ───────────────────────────────────────────────────────────────
if (-not (Test-Path $Daily)) {
    "# Daily Notes — $DATE`n" | Set-Content -Encoding UTF8 $Daily
}
"`n## Session closed: $TIME`n" | Add-Content -Encoding UTF8 $Daily

if (Test-Path $SessionState) {
    $TodayLines = Get-Content $SessionState | Where-Object { $_ -match "^- $DATE" }
    if ($TodayLines) {
        "### State captured today:`n`n$($TodayLines -join "`n")" | Add-Content -Encoding UTF8 $Daily
    }
}

if (Test-Path $Buffer) {
    $Incomplete = Get-Content $Buffer | Where-Object { $_ -match '^\- \[ \]' }
    if ($Incomplete) {
        "`n### Incomplete steps (resume next session):`n`n$($Incomplete -join "`n")" | Add-Content -Encoding UTF8 $Daily
    }
}

# ── Drain .pending-errors.log → ERR entries ───────────────────────────────────
if ((Test-Path $PendingLog) -and (Get-Item $PendingLog).Length -gt 0) {
    $Lines = Get-Content $PendingLog
    $DateCompact = $DATE -replace '-', ''
    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $ToolName  = $Line -replace '.*TOOL_FAILURE: ', ''
        $Timestamp = ($Line -split ' ')[0]
        $ExistingCount = if (Test-Path $ErrorsFile) {
            (Select-String -Path $ErrorsFile -Pattern "^### ERR-$DateCompact" -AllMatches).Matches.Count
        } else { 0 }
        $NNN = '{0:D3}' -f ($ExistingCount + 1)
        $ID = "ERR-$DateCompact-$NNN"
        @"

### $ID
**Status**: pending
**Context**: Tool failure captured automatically via PostToolUse hook at $Timestamp
**Content**: ``$ToolName`` returned a non-zero exit code during this session
**Action**: Run ``/platform-skills:self-improve review`` to investigate and resolve
"@ | Add-Content -Encoding UTF8 $ErrorsFile
    }
    Clear-Content $PendingLog
    Write-Host "[session-end] Drained .pending-errors.log -> $ErrorsFile"
}

# ── Auto-log ERR for PENDING WAL entries ──────────────────────────────────────
if ((Test-Path $Buffer) -and (Select-String -Path $Buffer -Pattern 'Status.*PENDING' -Quiet)) {
    $DateCompact = $DATE -replace '-', ''
    $ExistingCount = if (Test-Path $ErrorsFile) {
        (Select-String -Path $ErrorsFile -Pattern "^### ERR-$DateCompact" -AllMatches).Matches.Count
    } else { 0 }
    $NNN = '{0:D3}' -f ($ExistingCount + 1)
    $ID = "ERR-$DateCompact-$NNN"
    @"

### $ID
**Status**: pending
**Context**: Session closed with PENDING WAL entry in working-buffer.md
**Content**: A destructive operation was started but not confirmed as COMMITTED before session ended
**Action**: Run ``/platform-skills:self-improve resume`` next session to verify and update WAL status
"@ | Add-Content -Encoding UTF8 $ErrorsFile
}

# ── Clear session marker so next session triggers fresh memory load ───────────
if (Test-Path $SessionMarker) { Remove-Item $SessionMarker -Force }

# ── Session counter — remind about /self-improve review every 5 sessions ─────
$Count = 1
if (Test-Path $SessionCounter) { $Count = [int](Get-Content $SessionCounter) + 1 }
$Count | Set-Content -Encoding UTF8 $SessionCounter

if ($Count % 5 -eq 0) {
    "`n### Review reminder (session $Count):`n`nRun ``/platform-skills:self-improve review`` — 5 sessions have elapsed." |
        Add-Content -Encoding UTF8 $Daily
    Write-Host "[session-end] Review reminder added (session $Count)"
}

# ── Nudge if no learnings logged today ────────────────────────────────────────
$DateCompact = $DATE -replace '-', ''
$LrnToday = if (Test-Path $LearningsFile) {
    (Select-String -Path $LearningsFile -Pattern "^### LRN-$DateCompact" -AllMatches).Matches.Count
} else { 0 }
if ($LrnToday -eq 0) {
    Write-Host "[session-end] No learnings logged today — consider /platform-skills:self-improve log before next session"
}

Write-Host "[session-end] Saved to $Daily (session $Count)"
