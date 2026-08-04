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

$r1 = Test-SecondApplyMakesNoFurtherChanges
Report 'second consecutive -Apply -Prune against the same synthetic host makes no further byte changes' $r1.Passed $r1.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $(1 - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: 1 passed, 0 failed' -ForegroundColor Green
exit 0
