#Requires -Version 7.0
<#
.SYNOPSIS
Refresh only the RepoWise workspace entries whose indexed files moved.
.DESCRIPTION
One entry at a time through Invoke-RepoWiseBoundedIndex.ps1. Unchanged entries
cost one git comparison and are never started. Manual or capability-invoked:
this registers no schedule. A repeat within -MinimumHours returns without
visiting anything, so calling it from a capability cannot exceed once a day. A
run where every visit failed does not count, so it can be retried at once.
#>
[CmdletBinding()]
param(
    [string]$Workspace = 'C:\Repos',
    [string[]]$Only = @(),
    [switch]$DryRun,
    [switch]$Force,
    [switch]$FactsOnly,
    [ValidateRange(1, 168)][double]$MinimumHours = 20,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 1800,
    [string]$RuntimeDir = (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\repowise-refresh')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows Job Objects are required.' }

function Invoke-Hidden {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$ArgumentList)
    $startInfo = [Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout.Result }
    } finally { $process.Dispose() }
}

function Resolve-Interpreter {
    foreach ($name in 'python.exe', 'py.exe') {
        foreach ($command in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) {
            try { $found = (Invoke-Hidden $command.Source @('-c', 'import sys; print(sys.executable)')).StdOut.Trim() }
            catch { continue }
            if ($found -and $found -notlike '*\WindowsApps\*' -and (Test-Path -LiteralPath $found -PathType Leaf)) { return $found }
        }
    }
    throw 'No installed (non-Store) Python found.'
}

function Clear-DeadLease {
    # A killed wrapper skips its cleanup. A live wrapper, a live child (its command
    # line carries the token) and a lease kept on purpose all stay.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $lease = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($lease.PSObject.Properties['retained'] -and $lease.retained) { return }
        if (Get-Process -Id $lease.pid -ErrorAction SilentlyContinue) { return }
        $token = $lease.token
        if (@(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
                Where-Object { $_.CommandLine -like "*$token*" }).Count) { return }
        [IO.File]::Delete($Path)
    } catch { return }
}

$python = Resolve-Interpreter
$scanned = Invoke-Hidden $python @((Join-Path $PSScriptRoot 'changed_repos.py'), $Workspace)
if ($scanned.ExitCode -ne 0) { throw 'Could not survey the workspace.' }
$survey = $scanned.StdOut | ConvertFrom-Json -Depth 8
$changed = @($survey.changed)
if ($Only) {
    $wanted = @($Only | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.TrimEnd('\') })
    $changed = @($changed | Where-Object { $wanted -contains $_.path })
}
$report = [ordered]@{ entries = $survey.entries; counts = $survey.counts; visit = $changed.Count; other = @($survey.other) }
if ($DryRun) {
    $report.changed = $changed
    $report | ConvertTo-Json -Depth 8
    return
}

$null = New-Item -ItemType Directory -Force -Path $RuntimeDir
$stamp = Join-Path $RuntimeDir 'last-run.json'
if (-not $Force -and -not $Only -and (Test-Path -LiteralPath $stamp)) {
    $last = (Get-Content -LiteralPath $stamp -Raw -Encoding UTF8 | ConvertFrom-Json).finishedUtc
    $hours = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$last).TotalHours
    if ($hours -lt $MinimumHours) {
        [ordered]@{ skipped = "refreshed $([math]::Round($hours, 1)) hours ago"; wouldVisit = $changed.Count } | ConvertTo-Json
        return
    }
}

$wrapper = Join-Path $PSScriptRoot 'Invoke-RepoWiseBoundedIndex.ps1'
$lease = Join-Path $RuntimeDir 'refresh.lease'
Clear-DeadLease -Path $lease
$stopped = $null
$runId = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
$results = foreach ($entry in $changed) {
    if (Test-Path -LiteralPath $lease) { $stopped = "held lease at $lease"; break }
    $name = (($entry.path.Substring($Workspace.TrimEnd('\').Length).TrimStart('\')) -replace '[\\/]', '-')
    $outDir = Join-Path $RuntimeDir "$runId\$name"
    $arguments = @{ Workspace = $Workspace; RepositoryRoot = $entry.path; Python = $python
        LeasePath = $lease
        OutputDirectory = $outDir
        Deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds + 60)
        TimeoutSeconds = $TimeoutSeconds; FactsOnly = $FactsOnly }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $failure = $null
    try { $null = & $wrapper @arguments *>&1 } catch { $failure = $_.Exception.Message }
    $row = [ordered]@{ path = $entry.path; files = $entry.files; seconds = [math]::Round($clock.Elapsed.TotalSeconds, 1); failure = $failure }
    if ($failure) {
        # A rejected visit still leaves RepoWise's own commit marker advanced, so
        # this script selects nothing on the next run and "retry on the next
        # update" never arrives through here. Name the invocation that does
        # retry instead of leaving it to be discovered. Measured 2026-11-05: an
        # embedding degradation on two pages was rejected, the marker still moved
        # to HEAD, and a repeat run reported visit 0.
        $row['retry'] = "pwsh -NoProfile -File $wrapper -Workspace '$Workspace' -RepositoryRoot '$($entry.path)' -Python '$python' -LeasePath '$lease' -OutputDirectory '$outDir-retry' -Deadline ([DateTimeOffset]::Now.AddSeconds($($TimeoutSeconds + 60))) -TimeoutSeconds $TimeoutSeconds"
    }
    $row
}
$results = @($results)
$report.accepted = @($results | Where-Object { -not $_['failure'] }).Count
$report.failed = @($results | Where-Object { $_['failure'] })
if ($report.failed.Count -gt 0) {
    $report.retryNote = 'A rejected visit still advances that entry''s commit marker, so re-running this script visits nothing and cannot retry it. Run the command in each failed[].retry to force the bounded index directly. The existing index stays usable meanwhile, and full-text search is unaffected by an embedding degradation.'
}
$report.seconds = [math]::Round((($results | ForEach-Object { $_['seconds'] } | Measure-Object -Sum).Sum), 1)
$report.receipts = Join-Path $RuntimeDir $runId
if ($stopped) { $report.stopped = $stopped }
if (-not $Only -and -not $stopped -and ($results.Count -eq 0 -or $report.accepted -gt 0)) {
    @{ finishedUtc = [DateTimeOffset]::UtcNow.ToString('o'); visited = $results.Count } | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $stamp -Encoding UTF8
}
$report | ConvertTo-Json -Depth 8
