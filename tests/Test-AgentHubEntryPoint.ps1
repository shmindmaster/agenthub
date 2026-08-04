#Requires -Version 5.1
<#
Behavior tests for scripts/AgentHub.ps1 (task-8: one lifecycle entry point
replacing the deleted scripts/agentctl.ps1 -- see
.superpowers/sdd/control-plane-restore-plan/research/agentctl-spec.md).

Not a Pester suite: same dependency-free accumulate-and-report idiom as
tests/Test-SyncInstructions.ps1 and friends. Each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

Every -Apply invocation below targets either a synthetic -UserProfile under
$env:AGENTHUB_TEST_SCRATCH or a synthetic -RepositoryRoot with stub
delegated scripts. None ever targets the real user profile.

Run: pwsh -NoProfile -File tests/Test-AgentHubEntryPoint.ps1
     powershell.exe -NoProfile -File tests/Test-AgentHubEntryPoint.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$entryScript = Join-Path $repoRoot 'scripts\AgentHub.ps1'
$hostExe = (Get-Process -Id $PID).Path

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Invoke-AgentHub {
    param([string[]]$ExtraArgs = @())
    $allArgs = @('-NoProfile', '-File', $entryScript) + $ExtraArgs
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

# A stub delegated script that does no real work: it never touches disk on
# its own (unless -MarkerPath is supplied, in which case it writes exactly
# one marker file so a test can prove it WAS invoked) and exits with a
# caller-controlled code. Used to test AgentHub.ps1's own orchestration
# logic (dispatch, aggregation, gating) in isolation from the real Sync-*
# scripts' internal behavior, which already has its own dedicated test
# files.
function New-StubDelegatedScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$MarkerPath
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[CmdletBinding()]')
    $lines.Add('param([switch]$Audit,[switch]$Apply,[switch]$Prune,[string]$RepositoryRoot,[string]$RegistryRoot,[string]$UserProfile)')
    $lines.Add("Write-Host 'STUB EXECUTED: $(Split-Path -Leaf $Path)'")
    if ($MarkerPath) {
        # Only a real deploy (-Apply) is a write worth catching here -- an
        # audit-mode stub invocation must NOT drop the marker, or a test
        # relying on 'no marker means no write' would pass even when the
        # orchestrator wrongly invoked -Apply during an audit-only command.
        $escapedMarker = $MarkerPath.Replace("'", "''")
        $lines.Add('if ($Apply) {')
        $lines.Add("    New-Item -ItemType Directory -Path (Split-Path -Parent '$escapedMarker') -Force | Out-Null")
        $lines.Add("    Set-Content -LiteralPath '$escapedMarker' -Value 'invoked' -Encoding UTF8")
        $lines.Add('}')
    }
    $lines.Add("exit $ExitCode")
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Set-Content -LiteralPath $Path -Value ($lines -join "`r`n") -Encoding UTF8
}

# Builds a synthetic repository root with scripts/<name> for each of the
# four real delegated script names, each a controllable stub, so
# AgentHub.ps1's dispatch/aggregation can be exercised without depending on
# the real Sync-*/Validate-AgentHub.ps1 scripts' own preconditions (a real
# registry, a real host installed, etc).
function New-StubRepositoryRoot {
    param(
        [hashtable]$ExitCodes = @{},
        [switch]$IncludeValidate,
        [int]$ValidateExitCode = 0,
        [string]$MarkerDir
    )
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-entrypoint-" + [guid]::NewGuid())
    $scriptsDir = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    $names = @('Sync-Instructions.ps1', 'Sync-Subagents.ps1', 'Sync-Capabilities.ps1', 'Sync-AgentHub.ps1')
    foreach ($name in $names) {
        $code = if ($ExitCodes.ContainsKey($name)) { [int]$ExitCodes[$name] } else { 0 }
        $marker = if ($MarkerDir) { Join-Path $MarkerDir "$name.invoked" } else { $null }
        New-StubDelegatedScript -Path (Join-Path $scriptsDir $name) -ExitCode $code -MarkerPath $marker
    }
    if ($IncludeValidate) {
        New-StubDelegatedScript -Path (Join-Path $scriptsDir 'Validate-AgentHub.ps1') -ExitCode $ValidateExitCode
    }
    return $root
}

function Get-DirectorySnapshot {
    param([string]$Path, [string]$ExcludePrefix)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File)
    if ($ExcludePrefix) {
        $files = @($files | Where-Object { -not $_.FullName.StartsWith($ExcludePrefix, [StringComparison]::OrdinalIgnoreCase) })
    }
    return @($files |
        ForEach-Object { "$($_.FullName.Substring($Path.Length))=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" } |
        Sort-Object)
}

# --- Behavior 1: an unknown subcommand exits non-zero and names the valid
# ones. ---
function Test-UnknownSubcommandExitsNonZeroAndListsValidOnes {
    $result = Invoke-AgentHub -ExtraArgs @('not-a-real-subcommand', '-RepositoryRoot', $repoRoot)
    if ($result.ExitCode -eq 0) {
        return @{ Passed = $false; Detail = "exit code was 0 for an unknown subcommand. Output: $($result.Output)" }
    }
    foreach ($valid in @('inventory', 'validate', 'sync', 'drift')) {
        if ($result.Output -notmatch [regex]::Escape($valid)) {
            return @{ Passed = $false; Detail = "expected the valid subcommand '$valid' to be named in the output. Output: $($result.Output)" }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: 'sync' without -Apply (audit, the default) performs no
# writes to any real host destination under -UserProfile. Uses the real
# repository (so all four real delegated scripts run for real, read-only)
# with a synthetic -UserProfile fixture pre-populated with a sentinel file.
#
# Excludes -UserProfile\AppData\Local\AgentHub specifically: that is each
# delegated script's own documented runtime/staging root (Sync-AgentHub.ps1
# and Sync-Instructions.ps1 both stage/persist state there UNCONDITIONALLY,
# in both -Audit and -Apply, per their own headers and Task 2's prior
# verification -- this is pre-existing, already-shipped behavior of scripts
# this task must not change, not something -Command sync introduces).
# Everywhere else under the profile (destinations like .claude\CLAUDE.md,
# .codex\AGENTS.md, etc.) must stay byte-identical. ---
function Test-SyncWithoutApplyPerformsNoWrites {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sync-audit-nowrites-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    $sentinel = Join-Path $userProfile 'sentinel.txt'
    Set-Content -LiteralPath $sentinel -Value 'untouched' -Encoding UTF8
    $runtimeExclude = Join-Path $userProfile 'AppData\Local\AgentHub'
    try {
        $before = Get-DirectorySnapshot $userProfile -ExcludePrefix $runtimeExclude
        $result = Invoke-AgentHub -ExtraArgs @('sync', '-RepositoryRoot', $repoRoot, '-UserProfile', $userProfile)
        $after = Get-DirectorySnapshot $userProfile -ExcludePrefix $runtimeExclude
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "'sync' (audit) against the real repository exited $($result.ExitCode), expected 0. Output: $($result.Output)" }
        }
        $diff = Compare-Object $before $after
        if ($diff) {
            return @{ Passed = $false; Detail = "the synthetic -UserProfile fixture changed (outside its AppData\Local\AgentHub runtime/staging area) during a 'sync' run with no -Apply. Diff: $($diff | Out-String)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 3: a delegated script failure propagates to a non-zero
# aggregate exit. One of the four stubs exits 1; the other three exit 0.
# The aggregate run must still exit non-zero. ---
function Test-DelegatedFailurePropagatesToNonZeroAggregateExit {
    $stubRoot = New-StubRepositoryRoot -ExitCodes @{ 'Sync-Capabilities.ps1' = 1 }
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-delegated-failure-profile-" + [guid]::NewGuid())
    try {
        $result = Invoke-AgentHub -ExtraArgs @('sync', '-RepositoryRoot', $stubRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 even though one delegated stub script exited 1. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 4: 'inventory' writes nothing at all -- against the real
# repository with a synthetic -UserProfile fixture pre-populated with a
# sentinel file, the fixture must stay byte-identical after the run. ---
function Test-InventoryWritesNothing {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-inventory-nowrites-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    $sentinel = Join-Path $userProfile 'sentinel.txt'
    Set-Content -LiteralPath $sentinel -Value 'untouched' -Encoding UTF8
    try {
        $before = Get-DirectorySnapshot $userProfile
        $result = Invoke-AgentHub -ExtraArgs @('inventory', '-RepositoryRoot', $repoRoot, '-UserProfile', $userProfile)
        $after = Get-DirectorySnapshot $userProfile
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "'inventory' against the real repository exited $($result.ExitCode), expected 0. Output: $($result.Output)" }
        }
        $diff = Compare-Object $before $after
        if ($diff) {
            return @{ Passed = $false; Detail = "the synthetic -UserProfile fixture changed during an 'inventory' run. Diff: $($diff | Out-String)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: 'drift' writes nothing at all, using controllable stubs so
# the assertion covers AgentHub.ps1's own drift aggregation regardless of
# what the real Sync-* scripts happen to do today. Every stub would write a
# marker file into $markerDir if (and only if) it were invoked with -Apply;
# 'drift' must invoke every stub in audit mode only, so no marker file may
# ever appear. ---
function Test-DriftWritesNothing {
    $markerDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-drift-markers-" + [guid]::NewGuid())
    $stubRoot = New-StubRepositoryRoot -MarkerDir $markerDir
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-drift-profile-" + [guid]::NewGuid())
    try {
        $result = Invoke-AgentHub -ExtraArgs @('drift', '-RepositoryRoot', $stubRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "'drift' against a fully-passing stub fixture exited $($result.ExitCode), expected 0. Output: $($result.Output)" }
        }
        if (Test-Path -LiteralPath $markerDir) {
            $found = @(Get-ChildItem -LiteralPath $markerDir -File -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) {
                return @{ Passed = $false; Detail = "'drift' wrote marker file(s) that a stub only writes when invoked, proving a write happened: $($found.Name -join ', ')" }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $markerDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 6: zero executed delegated steps fails loudly rather than
# reporting success. A -RepositoryRoot whose scripts/ directory contains
# none of the four known delegated script names. ---
function Test-ZeroExecutedStepsFailsLoudly {
    $emptyRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-zero-steps-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'scripts') -Force | Out-Null
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-zero-steps-profile-" + [guid]::NewGuid())
    try {
        $result = Invoke-AgentHub -ExtraArgs @('drift', '-RepositoryRoot', $emptyRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) with zero delegated scripts present under $emptyRoot\scripts. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch '(?i)zero') {
            return @{ Passed = $false; Detail = "expected the failure output to explicitly call out zero executed steps. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $emptyRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 7: 'sync -Apply' refuses to run any delegated sync script at
# all if 'validate' would fail -- and performs zero writes as a result. A
# stub Validate-AgentHub.ps1 exits 1; every stub Sync-* script would write a
# marker file into $markerDir only if actually invoked. ---
function Test-ApplyRefusedWhenValidateFails {
    $markerDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-apply-refused-markers-" + [guid]::NewGuid())
    $stubRoot = New-StubRepositoryRoot -MarkerDir $markerDir -IncludeValidate -ValidateExitCode 1
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-apply-refused-profile-" + [guid]::NewGuid())
    try {
        $result = Invoke-AgentHub -ExtraArgs @('sync', '-Apply', '-RepositoryRoot', $stubRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 for 'sync -Apply' despite a failing 'validate'. Output: $($result.Output)" }
        }
        if (Test-Path -LiteralPath $markerDir) {
            $found = @(Get-ChildItem -LiteralPath $markerDir -File -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) {
                return @{ Passed = $false; Detail = "'sync -Apply' invoked a delegated Sync-* stub despite the validate gate failing: $($found.Name -join ', ')" }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $markerDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-UnknownSubcommandExitsNonZeroAndListsValidOnes
Report 'an unknown subcommand exits non-zero and names the valid subcommands' $r1.Passed $r1.Detail

$r2 = Test-SyncWithoutApplyPerformsNoWrites
Report "'sync' without -Apply performs no writes under -UserProfile" $r2.Passed $r2.Detail

$r3 = Test-DelegatedFailurePropagatesToNonZeroAggregateExit
Report 'a delegated script failure propagates to a non-zero aggregate exit' $r3.Passed $r3.Detail

$r4 = Test-InventoryWritesNothing
Report "'inventory' writes nothing at all" $r4.Passed $r4.Detail

$r5 = Test-DriftWritesNothing
Report "'drift' writes nothing at all" $r5.Passed $r5.Detail

$r6 = Test-ZeroExecutedStepsFailsLoudly
Report 'zero executed delegated steps fails loudly rather than reporting success' $r6.Passed $r6.Detail

$r7 = Test-ApplyRefusedWhenValidateFails
Report "'sync -Apply' refuses to run any delegated script when 'validate' would fail" $r7.Passed $r7.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
