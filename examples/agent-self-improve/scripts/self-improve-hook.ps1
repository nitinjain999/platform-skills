# self-improve-hook.ps1 - Windows PowerShell port of self-improve-hook.sh.
# Same subcommands, same files, same line formats:
#
#   session-start  SessionStart. Plain stdout becomes context Claude sees.
#                  Also fires with source=compact after a compaction, which is
#                  what restores the workspace pointers; no PostCompact hook is
#                  needed for that.
#   session-end    SessionEnd. Cannot block; 1.5 s budget unless "timeout" is set.
#   tool-failure   PostToolUseFailure, wired with "async": true.
#   precompact     PreCompact. Drains captured failures, because SessionEnd is
#                  not guaranteed to run. Must never exit non-zero: on this
#                  event exit 2 aborts the compaction.
#
# Hook input arrives as JSON on stdin. Every path exits 0.
#
# Compatibility rules (PowerShell 5.1 and 7+):
#   - This file stays ASCII-only. 5.1 reads a BOM-less script as ANSI, so a
#     literal em dash would reach disk as mojibake; use [char]0x2014.
#   - Files are written UTF-8 without a BOM, with LF line endings, so the bash
#     and PowerShell hooks can share one workspace.
#   - No three-argument Join-Path (7+ only); use [IO.Path]::Combine.
param([string]$Command = '')

$ErrorActionPreference = 'SilentlyContinue'
$Inv      = [Globalization.CultureInfo]::InvariantCulture
$Utf8     = New-Object System.Text.UTF8Encoding $false
$Dash     = [char]0x2014
$UserHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$Project  = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
$LegacyHookPattern = 'session-start-reminder|session-end\.(sh|ps1)|CLAUDE_TOOL_EXIT_CODE'

function Resolve-Base {
    $globalBase = [IO.Path]::Combine($UserHome, '.claude')
    # No -Force here: Test-Path has no such parameter, and passing one throws
    # a binding error that the outer catch swallows into a silent no-op.
    # Test-Path ignores the Hidden attribute anyway, so it sees a
    # dot-directory like ".learnings" unaided. Get-Item and Get-ChildItem do
    # need -Force; see Enter-Lock.
    if (Test-Path -LiteralPath ([IO.Path]::Combine($globalBase, '.learnings')) -PathType Container) { return $globalBase }
    if (Test-Path -LiteralPath ([IO.Path]::Combine($Project, '.learnings')) -PathType Container) { return $Project }
    return $null
}

function Get-Field([string]$Name) {
    if ($null -ne $script:Payload -and ($script:Payload.PSObject.Properties.Name -contains $Name)) {
        $value = $script:Payload.$Name
        if ($value -is [bool]) { return $value.ToString().ToLowerInvariant() }
        return [string]$value
    }
    return ''
}

function Protect-Field([string]$Value) {
    $clean = $Value -replace '[^A-Za-z0-9_.:-]', ''
    if ($clean.Length -gt 128) { $clean = $clean.Substring(0, 128) }
    return $clean
}

function Show-Path([string]$Path) {
    if ($UserHome -and $Path.StartsWith($UserHome + [IO.Path]::DirectorySeparatorChar)) {
        return '~' + $Path.Substring($UserHome.Length)
    }
    return $Path
}

# One mutex serialises every append. Without it concurrent writers silently
# lose records: .NET opens an append handle by seeking to the current end and
# writing at that remembered offset, so two hooks that open the same file
# together overwrite each other's bytes. Nothing throws - the records just
# vanish. Measured on macOS pwsh 7, twelve concurrent tool-failure hooks wrote
# 7 of 12 lines. The bash port needs no guard because ">>" is O_APPEND, which
# the kernel makes atomic for writes this small.
#
# A named mutex beats a lock file here: the OS releases it when the holder
# dies, and tool-failure runs with "async": true, so it can be killed
# mid-write when the session ends. A stale lock file would instead stall every
# later append. The name is unprefixed, so on Windows it lives in the session
# namespace - every hook for one user runs in that session.
$script:AppendMutex = $null
function Get-AppendMutex {
    if ($null -eq $script:AppendMutex) {
        # $false records "tried and failed", so creation is attempted once.
        try { $script:AppendMutex = New-Object System.Threading.Mutex($false, 'platform-skills-self-improve-append') }
        catch { $script:AppendMutex = $false }
    }
    if ($script:AppendMutex -is [Threading.Mutex]) { return $script:AppendMutex }
    return $null
}

function Add-Text([string]$Path, [string]$Text) {
    $mutex = Get-AppendMutex
    if ($null -eq $mutex) {
        # No mutex available: a possibly interleaved write still beats no write.
        [IO.File]::AppendAllText($Path, $Text, $Utf8)
        return
    }
    $held = $false
    # AbandonedMutexException means an earlier holder died and ownership has
    # passed to us. That is a success path, not an error.
    try { $held = $mutex.WaitOne(5000) }
    catch [Threading.AbandonedMutexException] { $held = $true }
    catch { $held = $false }
    try { [IO.File]::AppendAllText($Path, $Text, $Utf8) }
    finally { if ($held) { $mutex.ReleaseMutex() } }
}

function Get-LastErrNumber([string]$File, [string]$Stamp) {
    $max = 0
    if (Test-Path -LiteralPath $File) {
        foreach ($line in [IO.File]::ReadAllLines($File)) {
            if ($line -match "^### ERR-$Stamp-(\d+)") {
                $n = [int]$Matches[1]
                if ($n -gt $max) { $max = $n }
            }
        }
    }
    return $max
}

function Add-Err([string]$File, [int]$Number, [string]$Stamp, [string]$Context, [string]$Content, [string]$Action) {
    $id = 'ERR-{0}-{1:D3}' -f $Stamp, $Number
    Add-Text $File ("`n### $id`n**Status**: pending`n**Context**: $Context`n**Content**: $Content`n**Action**: $Action`n")
}

# Exclusive create (FileMode.CreateNew), so two sessions ending together
# never both drain or both pick the same ERR id. A lock older than
# 10 minutes is presumed left by a killed session. Atomic claim via rename
# closes the two-party race where both processes see the same stale lock:
# only one process can successfully move the lock to its own private name.
# After claiming, re-verify the claim was actually stale before recreating,
# since a second racer's own claim attempt might land after we already
# replaced the lock with a live one -- if so, put it back rather than
# destroying an active lock.
# -Force on Get-Item: on Unix, .NET marks a dotfile Hidden, and Get-Item
# treats a hidden item as absent without -Force. The lock file
# (".drain.lock") is a dotfile. Test-Path is exempt -- it ignores the
# attribute and rejects -Force outright.
function Enter-Lock([string]$Path) {
    try { [IO.File]::Open($Path, [IO.FileMode]::CreateNew).Dispose(); return $true } catch { }
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path -Force).LastWriteTime -lt (Get-Date).AddMinutes(-10))) {
        $claim = "$Path.claim.$PID"
        try { [IO.File]::Move($Path, $claim) } catch { return $false }
        if ((Get-Item -LiteralPath $claim -Force).LastWriteTime -lt (Get-Date).AddMinutes(-10)) {
            Remove-Item -LiteralPath $claim -Force
            try { [IO.File]::Open($Path, [IO.FileMode]::CreateNew).Dispose(); return $true } catch { }
        } else {
            # What we claimed turned out to be a live lock someone else just
            # created between our staleness check and our move; give it back.
            try { [IO.File]::Move($claim, $Path) } catch { }
        }
    }
    return $false
}

# Consolidate captured tool failures into ERRORS.md under the drain lock.
# Called from SessionEnd and from PreCompact: SessionEnd never runs if the
# process is killed, so compaction is a second, safe consolidation point.
# If a parallel session holds the lock it owns this drain; pending lines stay
# for the next caller and the SessionStart banner keeps counting them.
#
# Pass -Buffer only from SessionEnd. A PENDING WAL entry is a fault when the
# session has closed, but at compaction the session is still live.
#
# The locked section runs in its own try/finally so the lock is always
# released, even on an exception -- the outer try/catch at the bottom of this
# script would otherwise swallow the error and leave the lock held for up to
# 10 minutes.
function Invoke-Drain([string]$Lrn, [string]$Errors, [string]$Stamp, [string]$Buffer = '') {
    $pending  = Join-Path $Lrn '.pending-errors.log'
    $draining = Join-Path $Lrn '.pending-errors.draining'
    $lock     = Join-Path $Lrn '.drain.lock'
    if (-not (Enter-Lock $lock)) { return }
    try {
        # Rename before reading so an async tool-failure hook that fires
        # mid-drain appends to a fresh log.
        # -Force on Get-Item: ".pending-errors.log" and
        # ".pending-errors.draining" are dotfiles, hidden on Unix, and
        # Get-Item reports a hidden file as absent without it.
        if ((Test-Path -LiteralPath $pending) -and (Get-Item -LiteralPath $pending -Force).Length -gt 0) {
            $tmp = Join-Path $Lrn ('.pending-errors.' + [Guid]::NewGuid().ToString('N'))
            try {
                [IO.File]::Move($pending, $tmp)
                Add-Text $draining ([IO.File]::ReadAllText($tmp, $Utf8))
                [IO.File]::Delete($tmp)
            } catch { }
        }
        $n = Get-LastErrNumber $Errors $Stamp
        if ((Test-Path -LiteralPath $draining) -and (Get-Item -LiteralPath $draining -Force).Length -gt 0) {
            # One entry per (tool, session), in first-seen order.
            $groups = [ordered]@{}
            foreach ($line in [IO.File]::ReadAllLines($draining)) {
                $i = $line.IndexOf('TOOL_FAILURE: ')
                if ($i -lt 0) { continue }
                $ts     = @($line.Trim() -split '\s+')[0]
                $fields = @($line.Substring($i + 'TOOL_FAILURE: '.Length).Trim() -split '\s+' | Where-Object { $_ })
                $tool   = if ($fields.Count -ge 1) { $fields[0] } else { 'unknown' }
                $session = 'unknown'
                $useId   = 'unknown'
                # A for loop, not $fields[1..($fields.Count - 1)]: with one
                # field that range runs 1..0 and revisits element 0.
                for ($k = 1; $k -lt $fields.Count; $k++) {
                    $f = $fields[$k]
                    if ($f.StartsWith('session=') -and $f.Length -gt 8) { $session = $f.Substring(8) }
                    elseif ($f.StartsWith('tool_use_id=') -and $f.Length -gt 12) { $useId = $f.Substring(12) }
                }
                $key = "$tool|$session"
                if (-not $groups.Contains($key)) {
                    $groups[$key] = [pscustomobject]@{ Tool = $tool; Session = $session; Ts = $ts; UseId = $useId; N = 0 }
                }
                $groups[$key].N++
            }
            foreach ($g in $groups.Values) {
                $n++
                if ($g.N -gt 1) {
                    $content = "``$($g.Tool)`` failed $($g.N) times (session $($g.Session), first tool_use_id $($g.UseId))"
                } else {
                    $content = "``$($g.Tool)`` failed (session $($g.Session), tool_use_id $($g.UseId))"
                }
                Add-Err $Errors $n $Stamp "Tool failure captured by the PostToolUseFailure hook at $($g.Ts)" $content "Run ``/platform-skills:self-improve review`` to find the root cause in that session's transcript"
            }
            Remove-Item -LiteralPath $draining -Force
        }

        # Match a real WAL status line only; the template's HTML comment reads
        # "**Status**: PENDING | COMMITTED | ROLLED_BACK" and must not count.
        if ($Buffer -and (Test-Path -LiteralPath $Buffer) -and (@([IO.File]::ReadAllLines($Buffer) | Where-Object { $_ -match '^\*\*Status\*\*: PENDING\s*$' }).Count -gt 0)) {
            $n++
            Add-Err $Errors $n $Stamp 'Session closed with a PENDING WAL entry in working-buffer.md' 'A destructive operation was started but not confirmed as COMMITTED before the session ended' 'Run `/platform-skills:self-improve resume` next session to verify and update the WAL status'
        }
    } finally {
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
}

# Record this session end and return the total. See session_count in the bash
# port for the full reasoning; in short, appends are atomic and rewrites are
# not, so a legacy single-integer file is left as line 1 and read as a
# baseline rather than converted in place.
function Get-SessionCount([string]$Counter) {
    if (Test-Path -LiteralPath $Counter) {
        # A legacy file with no trailing newline would splice the first
        # timestamp onto its integer. 10 is LF.
        $bytes = [IO.File]::ReadAllBytes($Counter)
        if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10) { Add-Text $Counter "`n" }
    }
    Add-Text $Counter ([DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $Inv) + "`n")
    [long]$count = 0
    $lines = @([IO.File]::ReadAllLines($Counter))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        # Bounded to 18 digits so the parse always fits a long and cannot throw.
        if ($i -eq 0 -and $lines[0] -match '^[0-9]{1,18}$') { $count += [long]$lines[0]; continue }
        if ($lines[$i] -match '^[0-9]{4}-[0-9]') { $count++ }
    }
    return $count
}

function Invoke-ToolFailure {
    $base = Resolve-Base
    if (-not $base) { return }
    # A user interrupt is not a failure worth learning from.
    if ((Get-Field 'is_interrupt') -eq 'true') { return }
    $tool    = Protect-Field (Get-Field 'tool_name');   if (-not $tool)    { $tool = 'unknown' }
    $session = Protect-Field (Get-Field 'session_id');  if (-not $session) { $session = 'unknown' }
    $useId   = Protect-Field (Get-Field 'tool_use_id'); if (-not $useId)   { $useId = 'unknown' }
    # Never persist "error" or "tool_input": either can carry credentials.
    $ts  = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $Inv)
    $log = [IO.Path]::Combine($base, '.learnings', '.pending-errors.log')
    Add-Text $log "$ts TOOL_FAILURE: $tool session=$session tool_use_id=$useId`n"
}

function Invoke-SessionEnd {
    $base = Resolve-Base
    if (-not $base) { return }
    $mem = Join-Path $base 'memory'
    $lrn = Join-Path $base '.learnings'
    [void](New-Item -ItemType Directory -Force -Path $mem)
    $now    = Get-Date
    $today  = $now.ToString('yyyy-MM-dd', $Inv)
    $stamp  = $now.ToString('yyyyMMdd', $Inv)
    $time   = $now.ToString('HH:mm', $Inv)
    $reason = Protect-Field (Get-Field 'reason'); if (-not $reason) { $reason = 'unknown' }

    $daily    = Join-Path $mem "$today.md"
    $state    = Join-Path $mem 'SESSION-STATE.md'
    $buffer   = Join-Path $mem 'working-buffer.md'
    $errors   = Join-Path $lrn 'ERRORS.md'
    $counter  = Join-Path $mem '.session-count'

    # Daily note
    if (-not (Test-Path -LiteralPath $daily)) { Add-Text $daily "# Daily Notes $Dash $today`n`n" }
    Add-Text $daily "`n## Session closed: $time ($reason)`n`n"
    if (Test-Path -LiteralPath $state) {
        $lines = @([IO.File]::ReadAllLines($state) | Where-Object { $_.StartsWith("- $today") })
        if ($lines.Count -gt 0) { Add-Text $daily ("### State captured today:`n`n" + ($lines -join "`n") + "`n") }
    }
    if (Test-Path -LiteralPath $buffer) {
        $lines = @([IO.File]::ReadAllLines($buffer) | Where-Object { $_.StartsWith('- [ ]') })
        if ($lines.Count -gt 0) { Add-Text $daily ("`n### Incomplete steps (resume next session):`n`n" + ($lines -join "`n") + "`n") }
    }

    # ERRORS.md writes, under the drain lock.
    Invoke-Drain $lrn $errors $stamp $buffer

    # The legacy PreToolUse banner keyed off this marker; nothing reads it now.
    Remove-Item -LiteralPath (Join-Path $mem '.session-active') -Force

    # Session counter and review reminder
    $count = Get-SessionCount $counter
    if ($count % 5 -eq 0) {
        Add-Text $daily "`n### Review reminder (session $count):`n`nRun ``/platform-skills:self-improve review``. 5 sessions have elapsed.`n"
    }

    $learnings = Join-Path $lrn 'LEARNINGS.md'
    $logged = (Test-Path -LiteralPath $learnings) -and (@([IO.File]::ReadAllLines($learnings) | Where-Object { $_.StartsWith("### LRN-$stamp") }).Count -gt 0)
    if (-not $logged) {
        Add-Text $daily "- No learnings logged today. Consider ``/platform-skills:self-improve log`` before the next session.`n"
    }
}

# PreCompact. Compaction discards context, not disk state, so there is nothing
# to rescue from the payload: a hook never sees the transcript. What it can do
# is consolidate, because SessionEnd is not guaranteed to run. A session killed
# outright, or one whose window is closed, leaves .pending-errors.log undrained
# indefinitely; a long session compacts several times, so this turns the drain
# into something that happens repeatedly rather than once at the end.
#
# Context restoration after compaction needs no hook here: SessionStart fires
# again with source=compact, and its stdout is added to the new context.
#
# This must never block. PreCompact is one of the events where exit 2 stops the
# operation, and a memory hook that can abort compaction would strand a session
# with a full context window. The outer try/catch plus "exit 0" cover that.
function Invoke-PreCompact {
    $base = Resolve-Base
    if (-not $base) { return }
    $lrn = Join-Path $base '.learnings'
    if (-not (Test-Path -LiteralPath $lrn -PathType Container)) { return }
    $stamp = (Get-Date).ToString('yyyyMMdd', $Inv)
    Invoke-Drain $lrn (Join-Path $lrn 'ERRORS.md') $stamp
}

function Invoke-SessionStart {
    $base = Resolve-Base
    if (-not $base) { return }
    $mem   = Join-Path $base 'memory'
    $today = (Get-Date).ToString('yyyy-MM-dd', $Inv)
    $scope = if ($base -eq [IO.Path]::Combine($UserHome, '.claude')) { 'global' } else { 'project' }
    $out   = New-Object System.Collections.Generic.List[string]

    $out.Add("Self-improve workspace: $(Show-Path $base) ($scope)")
    $out.Add('Read these before starting work:')
    $out.Add("  1. $(Show-Path (Join-Path $mem 'working-buffer.md')) (active task, WAL)")
    $out.Add("  2. $(Show-Path (Join-Path $mem 'SESSION-STATE.md')) (corrections, preferences, decisions)")
    $dailyNote = Join-Path $mem "$today.md"
    if (Test-Path -LiteralPath $dailyNote) { $out.Add("  3. $(Show-Path $dailyNote) (today)") }

    $buffer = Join-Path $mem 'working-buffer.md'
    if (Test-Path -LiteralPath $buffer) {
        $found = $false
        $task = ''
        foreach ($line in [IO.File]::ReadAllLines($buffer)) {
            if (-not $found) {
                if ($line.StartsWith('## Current Task')) { $found = $true }
                continue
            }
            if ($line -match '^[^#]') { $task = $line; break }
        }
        if ($task.Length -gt 120) { $task = $task.Substring(0, 120) }
        if ($task -and $task -notmatch 'No active task') { $out.Add("Active task: $task") }
    }

    $pendingLog = [IO.Path]::Combine($base, '.learnings', '.pending-errors.log')
    # -Force on Get-Item: ".pending-errors.log" is a dotfile, hidden on Unix,
    # and Get-Item reports a hidden file as absent without it.
    if ((Test-Path -LiteralPath $pendingLog) -and (Get-Item -LiteralPath $pendingLog -Force).Length -gt 0) {
        $count = @([IO.File]::ReadAllLines($pendingLog) | Where-Object { $_ -match 'TOOL_FAILURE' }).Count
        $out.Add("WARNING: $count unprocessed tool failure(s) in $(Show-Path $pendingLog). Run /platform-skills:self-improve review.")
    }

    $settingsFiles = @(
        [IO.Path]::Combine($UserHome, '.claude', 'settings.json'),
        [IO.Path]::Combine($UserHome, '.claude', 'settings.local.json')
    )
    # With the project at home, the project paths are the same files as the two above.
    if ($Project -ne $UserHome) {
        $settingsFiles += [IO.Path]::Combine($Project, '.claude', 'settings.json')
        $settingsFiles += [IO.Path]::Combine($Project, '.claude', 'settings.local.json')
    }
    foreach ($f in $settingsFiles) {
        if ((Test-Path -LiteralPath $f) -and (Select-String -LiteralPath $f -Pattern $LegacyHookPattern -Quiet)) {
            $out.Add("WARNING: legacy self-improve hooks are still wired in $(Show-Path $f). Remove its Stop, PreToolUse and PostToolUse self-improve entries (see `"Migrating from the legacy hooks`" in examples/agent-self-improve/README.md).")
        }
    }
    [Console]::Out.Write(($out -join "`n") + "`n")
}

# 5.1 writes console output in the OEM code page, which would garble a
# non-ASCII Windows user path in the SessionStart banner. Some hosts throw
# when the console handle is redirected; the default is then kept.
try { [Console]::OutputEncoding = $Utf8 } catch { }

$script:Payload = $null
if ([Console]::IsInputRedirected) {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        try { $script:Payload = ConvertFrom-Json -InputObject $raw -ErrorAction Stop } catch { $script:Payload = $null }
    }
}

try {
    switch ($Command) {
        'session-start' { Invoke-SessionStart }
        'session-end'   { Invoke-SessionEnd }
        'tool-failure'  { Invoke-ToolFailure }
        'precompact'    { Invoke-PreCompact }
        default         { [Console]::Error.WriteLine('usage: self-improve-hook.ps1 session-start|session-end|tool-failure|precompact') }
    }
} catch { }
exit 0
