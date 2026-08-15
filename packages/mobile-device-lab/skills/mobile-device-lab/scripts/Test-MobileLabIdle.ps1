#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GuestIp,
    [string]$SshHost = 'macvm',
    [string]$AppiumUrl,
    [string]$SnapshotPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Get-ConflictKind {
    param([Parameter(Mandatory)][string]$CommandLine)
    $checks = @(
        @{ Name = 'Appium MCP smoke'; Pattern = 'Invoke-AppiumMcpSmoke\.mjs' },
        @{ Name = 'mobile fixture build'; Pattern = 'Build-MobileLabSmokeFixture\.ps1|run-smoke-fixture-build\.sh.*--worker|build-expo-simulator\.sh' },
        @{ Name = 'Maestro run'; Pattern = '(?i)(^|[\\/\s])maestro(?:\.bat|\.cmd|\.exe)?(?:\s|$)' },
        @{ Name = 'Xcode build'; Pattern = '(?i)(^|[\\/\s])xcodebuild(?:\s|$)' },
        @{ Name = 'Simulator mutation'; Pattern = '(?i)\bxcrun\s+simctl\s+(boot|shutdown|erase|install|uninstall|launch|terminate|spawn)\b' },
        @{ Name = 'Android install/build'; Pattern = '(?i)\b(?:adb(?:\.exe)?\s+[^\r\n]*\binstall\b|gradlew(?:\.bat)?\s+[^\r\n]*\bassemble\w*\b)' },
        @{ Name = 'native dependency build'; Pattern = '(?i)(^|[\\/\s])(?:pod\s+install|expo\s+prebuild)(?:\s|$)' }
    )
    foreach ($check in $checks) {
        if ($CommandLine -match $check.Pattern) { return $check.Name }
    }
    return $null
}

function Emit-Result {
    param([bool]$Idle, [object[]]$Conflicts, [object[]]$ProbeErrors)
    $result = [ordered]@{
        idle = $Idle
        checkedScopes = @('Windows process table', 'macOS guest process table', 'guest Appium sessions')
        conflicts = @($Conflicts)
        probeErrors = @($ProbeErrors)
        remediation = if ($Idle) { $null } else { 'Wait for every reported operation/session to finish. Do not terminate it unless its owner confirms it is stale, then rerun Test-MobileLab.ps1 -Deep -Json.' }
    }
    if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 5 -Compress) }
    else { $result }
}

try {
    $hostProcesses = @()
    $guestProcesses = @()
    $appiumSessions = @()
    $probeErrors = [Collections.Generic.List[object]]::new()

    if ($SnapshotPath) {
        $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hostProcesses = @($snapshot.hostProcesses | ForEach-Object { [string]$_ })
        $guestProcesses = @($snapshot.guestProcesses | ForEach-Object { [string]$_ })
        $appiumSessions = @($snapshot.appiumSessions)
    }
    else {
        if ([string]::IsNullOrWhiteSpace($GuestIp)) { throw 'GuestIp is required for a live idle probe.' }
        if ([string]::IsNullOrWhiteSpace($AppiumUrl)) { $AppiumUrl = "http://${GuestIp}:4723" }

        $hostProcesses = @(Get-CimInstance Win32_Process | Where-Object {
                $_.ProcessId -ne $PID -and -not [string]::IsNullOrWhiteSpace($_.CommandLine)
            } | ForEach-Object {
                [pscustomobject]@{ Pid = [int]$_.ProcessId; Name = [string]$_.Name; Command = [string]$_.CommandLine }
            })

        $sshArgs = @('-o', "HostName=$GuestIp", '-o', "HostKeyAlias=$SshHost", '-o', 'LogLevel=ERROR', '-o', 'ConnectTimeout=10', '-o', 'BatchMode=yes', $SshHost, 'ps -axo pid=,ppid=,command=')
        $guestOutput = @(& ssh @sshArgs 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $probeErrors.Add([pscustomobject]@{ Scope = 'macOS guest process table'; Error = (($guestOutput | Select-Object -Last 3) -join ' ') })
        }
        else { $guestProcesses = @($guestOutput | ForEach-Object { [string]$_ }) }

        try {
            # Appium 3 removed legacy GET /sessions. The replacement is
            # deliberately feature-gated and enabled only for this private
            # guest service by start-appium-guest.sh.
            $sessionResponse = Invoke-RestMethod -Uri "$AppiumUrl/appium/sessions" -TimeoutSec 20
            $appiumSessions = @($sessionResponse.value)
        }
        catch {
            $probeErrors.Add([pscustomobject]@{ Scope = 'guest Appium sessions'; Error = $_.Exception.Message })
        }
    }

    $conflicts = [Collections.Generic.List[object]]::new()
    foreach ($process in $hostProcesses) {
        $command = if ($process -is [string]) { [string]$process } else { [string]$process.Command }
        $kind = Get-ConflictKind -CommandLine $command
        if ($kind) {
            $pidValue = if ($process -is [string]) { if ($command -match '^\s*(\d+)') { $Matches[1] } else { $null } } else { $process.Pid }
            $conflicts.Add([pscustomobject]@{ Scope = 'Windows'; Kind = $kind; Pid = $pidValue })
        }
    }
    foreach ($command in $guestProcesses) {
        $kind = Get-ConflictKind -CommandLine ([string]$command)
        if ($kind) {
            $guestPid = if ([string]$command -match '^\s*(\d+)') { $Matches[1] } else { $null }
            $conflicts.Add([pscustomobject]@{ Scope = 'macOS guest'; Kind = $kind; Pid = $guestPid })
        }
    }
    foreach ($session in $appiumSessions) {
        $sessionId = if ($session -is [string]) { [string]$session } elseif ($session.PSObject.Properties['id']) { [string]$session.id } else { '<unknown>' }
        $conflicts.Add([pscustomobject]@{ Scope = 'guest Appium'; Kind = 'active session'; SessionId = $sessionId })
    }

    $idle = ($conflicts.Count -eq 0 -and $probeErrors.Count -eq 0)
    Emit-Result -Idle $idle -Conflicts @($conflicts) -ProbeErrors @($probeErrors)
    if (-not $idle) { exit 1 }
    exit 0
}
catch {
    Emit-Result -Idle $false -Conflicts @() -ProbeErrors @([pscustomobject]@{ Scope = 'idle probe'; Error = $_.Exception.Message })
    exit 1
}
