#Requires -Version 5.1
<#
Behavior tests for scripts/Sync-AgentHub.ps1's registry-root and user-profile
resolution (task-0c: stop the script silently defaulting to a hardcoded
checkout, and stop it reporting success against an empty/wrong tree).

Not a Pester suite: this repo carries no Pester dependency, Windows
PowerShell 5.1 here only exposes the bundled Pester 3.4.0 (old `Should Be`
dialect), and pwsh's newer Pester versions live in a module path invisible to
powershell.exe. Same self-checking idiom scripts/Validate-AgentHub.ps1 and
tests/Test-RegistryContentHash.ps1 already use: each Test-* function returns
a result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

Every invocation below runs scripts/Sync-AgentHub.ps1 in -Audit mode ONLY.
-Apply is never used here: it mutates live coding-agent host configuration on
this machine.

Run: pwsh -NoProfile -File tests/Test-SyncAgentHubRegistryRoot.ps1
     powershell.exe -NoProfile -File tests/Test-SyncAgentHubRegistryRoot.ps1
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

function Invoke-SyncAgentHub {
    param([string[]]$ExtraArgs = @())
    $allArgs = @('-NoProfile', '-File', $syncScript, '-Audit') + $ExtraArgs
    # Windows PowerShell 5.1 wraps a native child process's stderr lines as
    # ErrorRecords; under $ErrorActionPreference = 'Stop' those become
    # terminating even though the child process itself did not fail. Relax
    # locally so a failing child's stderr is captured as output, not thrown.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

# --- Behavior 1: a registry root with zero agents and no capabilities.json
# must fail loudly, never report success. This is the "empty or wrong tree"
# guard from task-0c: a run that finds zero capabilities must not report
# success. ---
function Test-EmptyRegistryRootFailsLoudly {
    $emptyRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-empty-registry-root-" + [guid]::NewGuid())
    $registryDir = Join-Path $emptyRoot 'registry'
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-empty-registry-profile-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Value '{ "activeAgents": [], "inactiveAgents": [] }' -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Value '{ "mcpServers": [] }' -Encoding UTF8 -NoNewline
    try {
        $result = Invoke-SyncAgentHub -ExtraArgs @('-RegistryRoot', $emptyRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) against a registry root with zero agents and no capabilities.json. Output: $($result.Output)" }
        }
        if ($result.Output -match 'Sync complete') {
            return @{ Passed = $false; Detail = "script printed 'Sync complete' against an empty/wrong registry tree. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $emptyRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2: with no -RegistryRoot, the script must resolve its registry
# root from its own on-disk location, not a hardcoded checkout. Proven by
# planting a uniquely-named canary agent into THIS repository's own
# registry/agents.json, running the script with no -RegistryRoot, and
# confirming the canary shows up in the drift output -- which is only
# possible if the script read the copy of the registry sitting next to
# itself. The edit is fully reverted (byte-identical) in the finally block. ---
function Test-NoRegistryRootSelfDerivesFromScriptLocation {
    $agentsJsonPath = Join-Path $repoRoot 'registry\agents.json'
    $originalBytes = [IO.File]::ReadAllBytes($agentsJsonPath)
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-self-derive-profile-" + [guid]::NewGuid())
    $marker = 'agenthub-task0c-canary-' + [guid]::NewGuid().ToString('N')
    try {
        $agentsDoc = Get-Content -LiteralPath $agentsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $canaryAgent = [pscustomobject]@{
            id = $marker
            name = 'AgentHub Task 0c Canary (reverted by test)'
            status = 'inactive'
            nativePaths = [pscustomobject]@{ instructions = $null }
            supportedCapabilities = @()
        }
        $agentsDoc.inactiveAgents = @(@($agentsDoc.inactiveAgents) + @($canaryAgent))
        ($agentsDoc | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $agentsJsonPath -Encoding UTF8

        $result = Invoke-SyncAgentHub -ExtraArgs @('-UserProfile', $userProfile, '-IncludeInactiveAgents')

        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode) instead of 0 running with no -RegistryRoot against this repository. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch [regex]::Escape("[$marker]")) {
            return @{ Passed = $false; Detail = "drift output did not mention canary host '$marker' -- self-derived root does not appear to be this repository's own checkout. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        [IO.File]::WriteAllBytes($agentsJsonPath, $originalBytes)
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 3: -UserProfile must still be overridable, and the override
# must actually redirect where runtime state (the drift report) is written. ---
function Test-UserProfileOverrideRedirectsRuntimeState {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-userprofile-override-" + [guid]::NewGuid())
    $expectedDriftPath = Join-Path $userProfile 'AppData\Local\AgentHub\sync\latest-drift.json'
    try {
        $result = Invoke-SyncAgentHub -ExtraArgs @('-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode). Output: $($result.Output)" }
        }
        if (-not (Test-Path -LiteralPath $expectedDriftPath)) {
            return @{ Passed = $false; Detail = "drift report was not written under the overridden -UserProfile path: $expectedDriftPath. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-EmptyRegistryRootFailsLoudly
Report 'empty/wrong registry root fails loudly instead of reporting success' $r1.Passed $r1.Detail

$r2 = Test-NoRegistryRootSelfDerivesFromScriptLocation
Report 'no -RegistryRoot self-derives from the running script location' $r2.Passed $r2.Detail

$r3 = Test-UserProfileOverrideRedirectsRuntimeState
Report '-UserProfile override still redirects runtime state to the specified path' $r3.Passed $r3.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $(3 - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: 3 passed, 0 failed' -ForegroundColor Green
exit 0
