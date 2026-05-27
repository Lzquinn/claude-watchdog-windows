<#
.SYNOPSIS
    Claude Code Session Watchdog for Windows
.DESCRIPTION
    Monitors all Claude Code sessions, detects stuck/idle sessions,
    and auto-recovers them with `claude --continue`.
.PARAMETER IdleMinutes
    Minutes of inactivity before a session is considered stuck. Default: 10.
.PARAMETER PollSeconds
    Seconds between each check. Default: 30.
.PARAMETER MaxRetries
    Max auto-recovery attempts per session before giving up. Default: 3.
.EXAMPLE
    powershell -File watchdog.ps1
    powershell -File watchdog.ps1 -IdleMinutes 5
#>

param(
    [int]$IdleMinutes = 10,
    [int]$PollSeconds = 30,
    [int]$MaxRetries = 3,
    [string]$ProjectPath = ""
)

$ErrorActionPreference = "Stop"

# --- Paths ---
$ClaudeHome = Join-Path $env:USERPROFILE ".claude"
$ProjectsDir = Join-Path $ClaudeHome "projects"
$StateDir = Join-Path $ClaudeHome "watchdog-state"
$EventsLog = Join-Path $StateDir "events.log"
$SessionsJson = Join-Path $StateDir "sessions.json"

if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}

# --- Session State ---
# Hashtable: sessionId -> @{ LastWrite; LastOutputTokens; StuckCount; Recovered; FilePath }
$script:Sessions = @{}

function Write-Event {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $EventsLog -Value $line -Encoding UTF8
    if ($Level -eq "WARN" -or $Level -eq "ERROR") {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor Gray
    }
}

function Save-Sessions {
    $script:Sessions | ConvertTo-Json | Set-Content -Path $SessionsJson -Encoding UTF8
}

function Get-JsonlSessions {
    <#
    .SYNOPSIS
        Scan project dirs for JSONL session files, return active ones.
    #>
    $sessions = @()
    if (-not (Test-Path $ProjectsDir)) { return $sessions }

    $dirsToScan = @()

    if ($ProjectPath -ne "") {
        # Scan only the specified project directory
        $targetDir = $ProjectPath
        if (-not (Test-Path $targetDir)) {
            Write-Event "WARN" "Project path not found: $targetDir"
            return $sessions
        }
        $dirsToScan += $targetDir
    } else {
        # Auto-detect: match current working directory to a project folder
        $cwd = (Get-Location).Path
        $encoded = $cwd -replace '\\', '-'
        $encoded = [regex]::Replace($encoded, '[^\x00-\x7F]', '-')
        $matched = Get-ChildItem -Path $ProjectsDir -Directory |
            Where-Object { $_.Name -eq $encoded } |
            Select-Object -First 1
        if ($matched) {
            $dirsToScan += $matched.FullName
        } else {
            Write-Event "WARN" "No matching project for: $cwd  (use -ProjectPath to specify)"
            return $sessions
        }
    }

    $dirsToScan | ForEach-Object {
        $projDir = $_
        Get-ChildItem -Path $projDir -Filter "*.jsonl" -ErrorAction SilentlyContinue | ForEach-Object {
            $sessions += @{
                SessionId  = $_.BaseName
                FilePath   = $_.FullName
                LastWrite  = $_.LastWriteTime
                ProjectDir = $projDir
            }
        }
    }
    return $sessions
}

function Get-LastOutputTokens {
    param([string]$FilePath)
    <#
    .SYNOPSIS
        Parse the last 20 lines of a JSONL file, find the latest output_tokens value.
    #>
    try {
        $lines = Get-Content -Path $FilePath -Tail 20 -ErrorAction SilentlyContinue
        $lastTokens = 0
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($obj.message.usage.output_tokens -gt 0) {
                    $lastTokens = $obj.message.usage.output_tokens
                }
            } catch { }
        }
        return $lastTokens
    } catch {
        return -1
    }
}

function Test-SessionStuck {
    param(
        [hashtable]$SessionInfo,
        [hashtable]$PrevState
    )
    <#
    .SYNOPSIS
        Triple detection: file idle + token stagnation + process check.
        Returns $true only if all three agree.
    #>
    $file = $SessionInfo.FilePath
    $lastWrite = $SessionInfo.LastWrite
    $idleThreshold = (Get-Date).AddMinutes(-$IdleMinutes)

    # Check 1: File hasn't been modified in IdleMinutes
    if ($lastWrite -gt $idleThreshold) {
        return $false  # Still active
    }

    # Check 2: Output tokens stagnated
    $currentTokens = Get-LastOutputTokens -FilePath $file
    if ($PrevState -and $PrevState.ContainsKey("LastOutputTokens")) {
        $prevTokens = $PrevState.LastOutputTokens
        if ($currentTokens -ne $prevTokens) {
            return $false  # Tokens are changing, not stuck
        }
    }

    # Check 3: Claude process exists
    $claudeProcs = Get-Process -Name "claude" -ErrorAction SilentlyContinue
    if (-not $claudeProcs) {
        return $false  # No claude process = session ended, not stuck
    }

    return $true  # All three agree: stuck
}

function Invoke-Recovery {
    param([string]$SessionId)
    <#
    .SYNOPSIS
        Attempt to recover a stuck session by launching `claude --continue`.
    #>
    Write-Event "WARN" "Attempting recovery for session: $SessionId"

    try {
        # Beep to alert user
        [Console]::Beep(800, 500)
        Start-Sleep -Milliseconds 200
        [Console]::Beep(1000, 500)

        # Launch claude --continue in a new process
        $proc = Start-Process -FilePath "claude" -ArgumentList "--continue" `
            -WindowStyle Normal -PassThru -ErrorAction Stop

        Write-Event "INFO" "Recovery process started (PID: $($proc.Id))"
        return $true
    } catch {
        Write-Event "ERROR" "Recovery failed: $_"
        return $false
    }
}

# --- Main Loop ---
Write-Event "INFO" "Watchdog started (IdleMinutes=$IdleMinutes, PollSeconds=$PollSeconds, MaxRetries=$MaxRetries)"
Write-Host ""
Write-Host "=== Claude Code Watchdog ===" -ForegroundColor Cyan
Write-Host "  Mode:      Auto-Recover"
if ($ProjectPath -ne "") {
    Write-Host "  Project:   $ProjectPath"
} else {
    Write-Host "  Project:   Auto-detect from current directory"
}
Write-Host "  Idle:      $IdleMinutes minutes"
Write-Host "  Poll:      $PollSeconds seconds"
Write-Host "  State:     $StateDir"
Write-Host "  Press Ctrl+C to stop"
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

while ($true) {
    $foundSessions = Get-JsonlSessions

    foreach ($sess in $foundSessions) {
        $sid = $sess.SessionId

        # Initialize state for new sessions
        if (-not $script:Sessions.ContainsKey($sid)) {
            $script:Sessions[$sid] = @{
                LastWrite       = $sess.LastWrite
                LastOutputTokens = (Get-LastOutputTokens -FilePath $sess.FilePath)
                StuckCount      = 0
                Recovered       = $false
                FilePath        = $sess.FilePath
            }
            continue
        }

        $prevState = $script:Sessions[$sid]

        # Skip already-recovered sessions (don't spam)
        if ($prevState.Recovered) {
            # But update last write time to track if recovery worked
            if ($sess.LastWrite -gt $prevState.LastWrite) {
                $script:Sessions[$sid].LastWrite = $sess.LastWrite
                $script:Sessions[$sid].LastOutputTokens = (Get-LastOutputTokens -FilePath $sess.FilePath)
                $script:Sessions[$sid].StuckCount = 0
                $script:Sessions[$sid].Recovered = $false
                Write-Event "INFO" "Session $sid recovered and active again"
            }
            continue
        }

        # Check if stuck
        $isStuck = Test-SessionStuck -SessionInfo $sess -PrevState $prevState

        if ($isStuck) {
            $script:Sessions[$sid].StuckCount++

            if ($script:Sessions[$sid].StuckCount -ge 3) {
                # Confirmed stuck (3 consecutive checks)
                Write-Event "WARN" "Session $sid confirmed STUCK (idle >$IdleMinutes min, tokens stagnant)"

                # Beep alert
                [Console]::Beep(600, 300)

                $retryCount = 0
                if ($prevState.ContainsKey("RetryCount")) {
                    $retryCount = $prevState.RetryCount
                }

                if ($retryCount -lt $MaxRetries) {
                    $script:Sessions[$sid].RetryCount = $retryCount + 1
                    Invoke-Recovery -SessionId $sid
                    $script:Sessions[$sid].Recovered = $true
                } else {
                    Write-Event "ERROR" "Session $sid exceeded max retries ($MaxRetries), giving up"
                    [Console]::Beep(400, 1000)
                }

                $script:Sessions[$sid].StuckCount = 0
            }
        } else {
            # Not stuck, update state
            $script:Sessions[$sid].LastWrite = $sess.LastWrite
            $script:Sessions[$sid].LastOutputTokens = (Get-LastOutputTokens -FilePath $sess.FilePath)
            $script:Sessions[$sid].StuckCount = 0
        }
    }

    # Clean up sessions that no longer exist
    $currentIds = $foundSessions | ForEach-Object { $_.SessionId }
    $toRemove = $script:Sessions.Keys | Where-Object { $_ -notin $currentIds }
    foreach ($id in $toRemove) {
        $script:Sessions.Remove($id)
        Write-Event "INFO" "Session $id removed (file no longer exists)"
    }

    Save-Sessions
    Start-Sleep -Seconds $PollSeconds
}
