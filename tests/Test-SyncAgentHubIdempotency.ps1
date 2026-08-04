#Requires -Version 5.1
<#
Behavior test for task-6b coverage-gap priority 4: idempotency for
scripts/Sync-AgentHub.ps1. Sync-Instructions.ps1 (tests/Test-SyncInstructions.ps1
Behavior 3) and Sync-Subagents.ps1 (tests/Test-SyncSubagents.ps1 Behavior 6)
already cover this for their own scripts; Sync-AgentHub.ps1 did not have an
idempotency test anywhere before this file.

Sync-AgentHub.ps1 does not print an "updated=N" summary the way the other
Sync-*.ps1 scripts do (its drift report is a JSON file at
%LOCALAPPDATA%\AgentHub\sync\latest-drift.json under the effective
-UserProfile), so idempotency here is proven directly against the managed
host file's bytes: two consecutive -Apply runs against the same synthetic
-RegistryRoot/-UserProfile pair produce byte-identical output on the
second run.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this
file follows). Same self-checking idiom: each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

Every -Apply invocation below targets a synthetic -RegistryRoot/-UserProfile
pair under $env:AGENTHUB_TEST_SCRATCH. Never the real registry root or the
real user profile.

Run: pwsh -NoProfile -File tests/Test-SyncAgentHubIdempotency.ps1
     powershell.exe -NoProfile -File tests/Test-SyncAgentHubIdempotency.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'
$hostExe = (Get-Process -Id $PID).Path

$failures = [Collections.Generic.List[string]]::new()
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

function Invoke-SyncAgentHub {
    param([string[]]$ExtraArgs = @())
    $allArgs = @('-NoProfile', '-File', $syncScript) + $ExtraArgs
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

# --- Behavior: two consecutive -Apply -Prune runs against the same
# synthetic codex host (a CRLF config.toml with one stale, non-canonical
# mcp_servers section, matching the fixture shape already proven correct in
# tests/Test-CrlfAnchors.ps1) produce a byte-identical config.toml on the
# second run -- no further drift on a no-op re-apply. ---
function Test-SecondApplyMakesNoFurtherChanges {
    $fixtureRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-syncagenthub-idempotent-repo-" + [guid]::NewGuid())
    $fixtureProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-syncagenthub-idempotent-profile-" + [guid]::NewGuid())
    $registryDir = Join-Path $fixtureRoot 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $fixtureProfile -Force | Out-Null
    $configPath = Join-Path $fixtureProfile 'config.toml'
    try {
        $agents = @{
            activeAgents = @(
                @{ id = 'codex'; name = 'Fixture Codex'; status = 'active'; nativePaths = @{ config = $configPath } }
            )
            inactiveAgents = @()
        }
        ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

        $mcps = @{
            mcpServers = @(
                @{ id = 'sample-server'; transport = 'stdio'; command = 'sample.exe'; args = @('--flag') }
            )
        }
        ($mcps | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Encoding UTF8 -NoNewline

        $capabilities = @{
            schemaVersion = 2
            capabilities = @(
                @{ id = 'fixture-cap'; owner = 'test'; capabilityType = 'skills'; canonicalSource = 'packages/does-not-exist' }
            )
        }
        ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

        [IO.File]::WriteAllText($configPath, "[mcp_servers.stale-entry]`r`ncommand = `"old.exe`"`r`nargs = []`r`n", [Text.UTF8Encoding]::new($false))

        $allArgs = @('-Apply', '-Prune', '-RegistryRoot', $fixtureRoot, '-UserProfile', $fixtureProfile)
        $first = Invoke-SyncAgentHub -ExtraArgs $allArgs
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply -Prune exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        if (-not (Test-Path -LiteralPath $configPath)) {
            return @{ Passed = $false; Detail = "first -Apply -Prune did not produce the expected config.toml -- test setup invalid." }
        }
        $bytesAfterFirst = [IO.File]::ReadAllBytes($configPath)

        $second = Invoke-SyncAgentHub -ExtraArgs $allArgs
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply -Prune exit code was $($second.ExitCode). Output: $($second.Output)" }
        }
        $bytesAfterSecond = [IO.File]::ReadAllBytes($configPath)
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$bytesAfterFirst, [byte[]]$bytesAfterSecond)) {
            return @{ Passed = $false; Detail = 'config.toml changed bytes on a second, no-op -Apply -Prune run -- not idempotent.' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixtureProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Multi-host fixture for the reporting behaviors below. Behavior 1 above proves
# bytes; these prove the VERDICT, which is a different claim and was the gap.
#
# Three hosts on purpose, because the status is returned by a different writer
# for each: codex goes through Sync-HostMcp-Codex (TOML), factory through
# Sync-HostMcp-JsonFile, warp through Sync-HostMcp-ConvertedJsonFile. A fix
# applied to only one writer must not pass.
function New-ReportingFixture {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-mcpreport-repo-" + [guid]::NewGuid())
    $profileDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-mcpreport-profile-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    $codexConfig = Join-Path $profileDir 'config.toml'
    $factoryMcp = Join-Path $profileDir 'factory-mcp.json'
    $warpMcp = Join-Path $profileDir 'warp-mcp.json'

    $agents = @{
        activeAgents = @(
            @{ id = 'codex'; name = 'Fixture Codex'; status = 'active'; nativePaths = @{ config = $codexConfig } }
            @{ id = 'factory'; name = 'Fixture Factory'; status = 'active'; nativePaths = @{ mcp = $factoryMcp } }
            @{ id = 'warp'; name = 'Fixture Warp'; status = 'active'; nativePaths = @{ mcp = $warpMcp } }
        )
        inactiveAgents = @()
    }
    ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    $mcps = @{
        mcpServers = @(
            @{ id = 'sample-server'; transport = 'stdio'; command = 'sample.exe'; args = @('--flag') }
        )
    }
    ($mcps | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Encoding UTF8 -NoNewline

    $capabilities = @{
        schemaVersion = 2
        capabilities = @(
            @{ id = 'fixture-cap'; owner = 'test'; capabilityType = 'skills'; canonicalSource = 'packages/does-not-exist' }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    # Sync-HostMcp-Codex reports 'config-missing' rather than writing a config
    # that is not there, so codex needs a seed file or it never reaches the
    # writer and silently contributes nothing to these assertions. The stale
    # entry makes the first apply a genuine change, matching Behavior 1's
    # fixture shape. factory and warp need no seed: their writers create the
    # file, which is what makes their first apply a real change too.
    [IO.File]::WriteAllText($codexConfig, "[mcp_servers.stale-entry]`r`ncommand = `"old.exe`"`r`nargs = []`r`n", [Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        Root      = $root
        Profile   = $profileDir
        DriftPath = Join-Path $profileDir 'AppData\Local\AgentHub\sync\latest-drift.json'
        Args      = @('-Apply', '-RegistryRoot', $root, '-UserProfile', $profileDir)
    }
}

function Remove-ReportingFixture {
    param($Fixture)
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.Profile -Recurse -Force -ErrorAction SilentlyContinue
}

# Both evidence surfaces are read from the same field, so both are asserted:
# the console prints $_.mcp[].status and latest-drift.json serializes it.
function Get-ReportedMcpStatuses {
    param([Parameter(Mandatory)]$Fixture)
    if (-not (Test-Path -LiteralPath $Fixture.DriftPath)) { return $null }
    $report = Get-Content -LiteralPath $Fixture.DriftPath -Raw | ConvertFrom-Json
    $statuses = [Collections.Generic.List[string]]::new()
    foreach ($hostEntry in @($report.hosts)) {
        foreach ($mcpResult in @($hostEntry.mcp)) { $statuses.Add("$($hostEntry.host)=$($mcpResult.status)") }
    }
    return $statuses
}

# --- Behavior 2: a second consecutive -Apply, which changes nothing, must
# report unchanged rather than updated. latest-drift.json and the console
# summary are the fleet's evidence surface; a verdict that says "updated" for
# every host on a no-op makes a genuine single-host change indistinguishable
# from routine noise. Sync-Instructions.ps1 and Sync-Subagents.ps1 already
# report this correctly (updated=0 on a no-op run) -- this closes the gap for
# the MCP path. ---
function Test-NoOpApplyReportsUnchanged {
    $fixture = New-ReportingFixture
    try {
        $first = Invoke-SyncAgentHub -ExtraArgs $fixture.Args
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        $second = Invoke-SyncAgentHub -ExtraArgs $fixture.Args
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply exit code was $($second.ExitCode). Output: $($second.Output)" }
        }

        $statuses = Get-ReportedMcpStatuses -Fixture $fixture
        if ($null -eq $statuses -or $statuses.Count -eq 0) {
            return @{ Passed = $false; Detail = "the drift report at $($fixture.DriftPath) recorded no mcp results, so this assertion checked nothing. Output: $($second.Output)" }
        }
        if ($statuses.Count -lt 3) {
            return @{ Passed = $false; Detail = "expected an mcp result for each of the 3 fixture hosts, got $($statuses.Count): $($statuses -join ', '). A fix covering only one writer must not pass." }
        }
        $notUnchanged = @($statuses | Where-Object { $_ -notmatch '=unchanged$' })
        if ($notUnchanged.Count -gt 0) {
            return @{ Passed = $false; Detail = "a no-op second -Apply reported: $($notUnchanged -join ', '). Bytes did not change, so the verdict must be 'unchanged'." }
        }
        # The console is the surface most people actually read.
        if ($second.Output -match 'mcp=updated') {
            return @{ Passed = $false; Detail = "the drift report said unchanged but the console still printed 'mcp=updated'. The two surfaces disagree. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-ReportingFixture -Fixture $fixture
    }
}

# --- Behavior 3: the anti-vacuous counterpart. A first -Apply against hosts
# with no existing config genuinely writes new content and MUST still report
# updated. Without this, hardcoding 'unchanged' would satisfy Behavior 2 while
# destroying the report's only useful signal. ---
function Test-RealChangeStillReportsUpdated {
    $fixture = New-ReportingFixture
    try {
        $first = Invoke-SyncAgentHub -ExtraArgs $fixture.Args
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode). Output: $($first.Output)" }
        }
        $statuses = Get-ReportedMcpStatuses -Fixture $fixture
        if ($null -eq $statuses -or $statuses.Count -lt 3) {
            return @{ Passed = $false; Detail = "expected an mcp result for each of the 3 fixture hosts on the first apply, got $(if($statuses){$statuses.Count}else{0})." }
        }
        $notUpdated = @($statuses | Where-Object { $_ -notmatch '=updated$' })
        if ($notUpdated.Count -gt 0) {
            return @{ Passed = $false; Detail = "a first -Apply that genuinely created new config reported: $($notUpdated -join ', '). Real changes must still report 'updated' -- otherwise the report has no signal left at all." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-ReportingFixture -Fixture $fixture
    }
}

$r1 = Test-SecondApplyMakesNoFurtherChanges
Report 'second consecutive -Apply -Prune against the same synthetic host makes no further byte changes' $r1.Passed $r1.Detail

$r2 = Test-NoOpApplyReportsUnchanged
Report 'a no-op second -Apply reports mcp=unchanged on both the drift report and the console' $r2.Passed $r2.Detail

$r3 = Test-RealChangeStillReportsUpdated
Report 'a first -Apply that genuinely writes new config still reports mcp=updated' $r3.Passed $r3.Detail

$reported = 3
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
