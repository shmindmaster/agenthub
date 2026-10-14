#Requires -Version 5.1
<#
.SYNOPSIS
    Keep the machine RepoWise CLI on the latest PyPI release.

.DESCRIPTION
    RepoWise is uv-managed machine tooling (`uv tool install repowise`), not
    AgentHub package content. This script is the fleet control for that CLI:
    compare the installed version to PyPI and upgrade when behind. Updates are
    manual or capability-invoked: by owner direction (2026-10-13) no scheduled
    job runs this script, because a Task Scheduler powershell.exe action opens
    a console window and takes keyboard focus.

    Audit (default) never writes. Apply upgrades (or installs if missing).
    RemoveSchedule deletes the retired AgentHub-Update-RepoWise task if an
    older checkout registered it.

.PARAMETER Audit
    Report installed vs PyPI. Exit 1 if missing or behind. Default if neither
    -Audit nor -Apply is passed.

.PARAMETER Apply
    Install or upgrade to the PyPI latest via `uv tool`.

.PARAMETER RemoveSchedule
    Delete the retired current-user scheduled task AgentHub-Update-RepoWise if
    it exists. Does not require -Apply. Never creates a task.

.PARAMETER RegisterSchedule
    Retired. Fails without creating anything; run -Apply manually instead.

.PARAMETER InstalledVersion
    Test override. Skip probing the live CLI.

.PARAMETER LatestVersion
    Test override. Skip querying PyPI.

.PARAMETER UvExe
    Test override. Path to uv. Live runs resolve uv themselves.

.PARAMETER SchtasksExe
    Test override. Path to schtasks. Live runs use System32\schtasks.exe.
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [switch]$RemoveSchedule,
    [switch]$RegisterSchedule,
    [string]$InstalledVersion,
    [string]$LatestVersion,
    [string]$UvExe,
    [string]$SchtasksExe,
    [string]$StateFile
)

$ErrorActionPreference = 'Stop'
$TaskName = 'AgentHub-Update-RepoWise'
$PypiUrl = 'https://pypi.org/pypi/repowise/json'
if ([string]::IsNullOrWhiteSpace($StateFile)) {
    $StateFile = Join-Path $env:LOCALAPPDATA 'AgentHub\repowise-cli.json'
}

if (-not $Audit -and -not $Apply -and -not $RemoveSchedule -and -not $RegisterSchedule) { $Audit = $true }

function Get-RepoWiseVersionFromText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(?i)(?:version\s+)?v?(\d+\.\d+\.\d+)')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function ConvertTo-ComparableVersion([string]$Version) {
    return [version]$Version
}

function Resolve-UvExe {
    if (-not [string]::IsNullOrWhiteSpace($UvExe)) {
        if (-not (Test-Path -LiteralPath $UvExe)) {
            throw "uv executable override not found: $UvExe"
        }
        return (Get-Item -LiteralPath $UvExe).FullName
    }
    $cmd = Get-Command -Name uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:USERPROFILE '.local\bin\uv.exe'),
        (Join-Path $env:USERPROFILE '.cargo\bin\uv.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return (Get-Item -LiteralPath $c).FullName }
    }
    throw "uv was not found on PATH or in the usual user install locations. Install uv, then re-run."
}

function Get-InstalledRepoWiseVersion {
    if ($InstalledVersion -eq 'none') { return $null }
    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) { return $InstalledVersion }
    $cmd = Get-Command -Name repowise -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $exe = $null
    if ($cmd) { $exe = $cmd.Source }
    else {
        $fallback = Join-Path $env:USERPROFILE '.local\bin\repowise.exe'
        if (Test-Path -LiteralPath $fallback) { $exe = $fallback }
    }
    if (-not $exe) { return $null }
    $out = & $exe --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "repowise --version failed (exit $LASTEXITCODE): $out"
    }
    $parsed = Get-RepoWiseVersionFromText $out
    if (-not $parsed) { throw "could not parse repowise --version output: $out" }
    return $parsed
}

function Get-LatestRepoWiseVersion {
    if (-not [string]::IsNullOrWhiteSpace($LatestVersion)) { return $LatestVersion }
    $info = Invoke-RestMethod -Uri $PypiUrl -TimeoutSec 30
    $v = [string]$info.info.version
    if ([string]::IsNullOrWhiteSpace($v)) { throw "PyPI returned no version for repowise" }
    $parsed = Get-RepoWiseVersionFromText $v
    if (-not $parsed) { throw "could not parse PyPI version '$v'" }
    return $parsed
}

function Write-State([hashtable]$Record) {
    $dir = Split-Path -Parent $StateFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($Record | ConvertTo-Json -Compress)
    [IO.File]::WriteAllText($StateFile, $json, [Text.UTF8Encoding]::new($false))
}

function Invoke-Upgrade([string]$UvPath, [bool]$AlreadyInstalled) {
    $args = if ($AlreadyInstalled) { @('tool', 'upgrade', 'repowise') } else { @('tool', 'install', 'repowise') }
    $out = & $UvPath @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "uv $($args -join ' ') failed (exit $LASTEXITCODE): $out"
    }
    Write-Host $out.TrimEnd()
}

function Remove-UpdateTask {
    $exe = if (-not [string]::IsNullOrWhiteSpace($SchtasksExe)) { $SchtasksExe } else { Join-Path $env:WINDIR 'System32\schtasks.exe' }
    $null = & $exe /Query /TN $TaskName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PASS: scheduled task $TaskName is absent."
        return
    }
    $out = & $exe /Delete /TN $TaskName /F 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks /Delete $TaskName failed (exit $LASTEXITCODE): $out"
    }
    Write-Host "PASS: removed scheduled task $TaskName."
}

$installed = $null
$latest = $null
$exit = 0
try {
    if ($RegisterSchedule) {
        throw "-RegisterSchedule is retired (owner direction 2026-10-13: no scheduled agent jobs). Run -Apply manually; use -RemoveSchedule to delete an old $TaskName task."
    }
    if ($Audit -or $Apply) {
        $installed = Get-InstalledRepoWiseVersion
        $latest = Get-LatestRepoWiseVersion
        $status = 'current'
        if (-not $installed) {
            $status = 'missing'
        } elseif ((ConvertTo-ComparableVersion $installed) -lt (ConvertTo-ComparableVersion $latest)) {
            $status = 'behind'
        }

        Write-Host ("installed={0} latest={1} status={2}" -f $(if ($installed) { $installed } else { 'none' }), $latest, $status)

        if ($Apply) {
            if ($status -eq 'current') {
                Write-Host "PASS: RepoWise CLI is already the PyPI latest ($latest)."
            } else {
                $uvPath = Resolve-UvExe
                Invoke-Upgrade -UvPath $uvPath -AlreadyInstalled:($status -eq 'behind')
                $installed = Get-InstalledRepoWiseVersion
                if (-not $installed -or ((ConvertTo-ComparableVersion $installed) -lt (ConvertTo-ComparableVersion $latest))) {
                    throw "upgrade finished but installed version is still '$installed' (wanted $latest)"
                }
                Write-Host "PASS: RepoWise CLI is now $installed. Restart MCP clients so they pick up the new binary."
                $status = 'current'
            }
        } elseif ($status -ne 'current') {
            Write-Host "FAIL: RepoWise CLI is $status. Run: pwsh -NoProfile -File scripts/Update-RepoWise.ps1 -Apply"
            $exit = 1
        } else {
            Write-Host "PASS: RepoWise CLI is the PyPI latest ($latest)."
        }

        Write-State @{
            checkedAt = [datetime]::UtcNow.ToString('o')
            installed = $installed
            latest = $latest
            status = $status
            apply = [bool]$Apply
        }
    }

    if ($RemoveSchedule) { Remove-UpdateTask }
} catch {
    Write-Host "FAIL: $($_.Exception.Message)"
    $exit = 1
}

exit $exit
