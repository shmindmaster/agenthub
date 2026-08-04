#Requires -Version 5.1
<#
Behavior tests for scripts/Sync-Instructions.ps1 (task-2: restore the
mechanism that keeps every host's global instruction file generated from
the canonical global-agent-policy.md).

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and tests/Test-SyncAgentHubRegistryRoot.ps1
for the prior art this file follows). Same self-checking idiom: each Test-*
function returns a result, the runner prints one PASS/FAIL line per
behavior, accumulates failures, and exits 1 if any behavior did not hold, 0
otherwise.

Every -Apply invocation below targets a synthetic -UserProfile under
$env:AGENTHUB_TEST_SCRATCH. None ever targets the real user profile.

Run: pwsh -NoProfile -File tests/Test-SyncInstructions.ps1
     powershell.exe -NoProfile -File tests/Test-SyncInstructions.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-Instructions.ps1'
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

function Invoke-SyncInstructions {
    param([string[]]$ExtraArgs = @())
    $allArgs = @('-NoProfile', '-File', $syncScript) + $ExtraArgs
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

# --- Behavior 0 (safety-critical -- this is the ONLY thing standing between
# a future -UserProfile test run and the live fleet, and it earned that
# status the hard way during this task's own development):
#
# registry/agents.json stores ABSOLUTE destination paths baked to the real
# invoking user's profile (e.g. "C:\\Users\\<realUser>\\.claude\\CLAUDE.md"),
# not paths relative to %USERPROFILE%. Before this behavior existed, this
# script used those paths verbatim as destinations regardless of
# -UserProfile -- so a test run that passed -UserProfile <temp-dir>
# correctly staged its preview under the temp dir's %LOCALAPPDATA%, but
# still WROTE THE REAL, LIVE PROFILE via -Apply, because the actual
# destination path was never rebased. That defect really fired once during
# this task's own test development and modified 12 real, live host files
# before being caught, reverted, and root-caused (see task-2-report.md,
# "Safety incident"). If this behavior ever regresses, the exact same thing
# happens again to whoever runs the test suite next.
#
# When -UserProfile is overridden to a synthetic test profile, every
# reported destination path must be rebased under that synthetic profile --
# never left pointing at the real profile. -Audit is read-only, so this is
# safe to run even if the rebase is missing or wrong; it just proves the
# bug via the reported path, without ever writing anywhere. ---
function Test-DestinationPathsAreRebasedUnderUserProfileOverride {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-rebase-check-" + [guid]::NewGuid())
    try {
        $result = Invoke-SyncInstructions -ExtraArgs @('-Audit', '-UserProfile', $userProfile)
        if ($result.Output -notmatch '(?m)^claude\s+\S+\s+\S+\s+(\S+)') {
            return @{ Passed = $false; Detail = "could not find a claude row with a path in the audit output. Output: $($result.Output)" }
        }
        $reportedPath = $Matches[1]
        if (-not $reportedPath.StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
            return @{ Passed = $false; Detail = "claude's reported destination path was '$reportedPath', which is not under the synthetic -UserProfile '$userProfile' -- destination paths from the registry are not being rebased under an overridden -UserProfile. This is the exact defect that would make -Apply write to the real, live user profile regardless of -UserProfile." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 1: the render contract. -Audit against a fresh synthetic
# profile reports Claude 'missing'; -Apply then writes bytes that are
# EXACTLY <instructionHeader>\n\n<!-- agenthub:managed -->\n\n<canonical
# body>, byte for byte against the real global-agent-policy.md; a second
# -Audit then reports Claude 'current'. ---
function Test-RenderContractProducesExactBytes {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-render-contract-" + [guid]::NewGuid())
    $claudeDest = Join-Path $userProfile '.claude\CLAUDE.md'
    try {
        $before = Invoke-SyncInstructions -ExtraArgs @('-Audit', '-UserProfile', $userProfile)
        if ($before.Output -notmatch '(?m)^claude\s+missing\b') {
            return @{ Passed = $false; Detail = "expected 'claude ... missing' in the pre-apply audit. Output: $($before.Output)" }
        }

        $apply = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($apply.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply exit code was $($apply.ExitCode). Output: $($apply.Output)" }
        }
        if (-not (Test-Path -LiteralPath $claudeDest)) {
            return @{ Passed = $false; Detail = "expected file was not written: $claudeDest. Output: $($apply.Output)" }
        }

        $expected = "# Claude Code Global Instructions`n`n<!-- agenthub:managed -->`n`n" +
            # The renderer normalizes the policy body to LF so the deployed
            # bytes do not depend on this checkout's line endings. The expected
            # value has to be normalized the same way or this assertion passes
            # in an LF checkout and fails in a CRLF worktree -- the very defect
            # the normalization removed.
            [IO.File]::ReadAllText((Join-Path $repoRoot 'global-agent-policy.md')).Replace("`r`n", "`n")
        $actual = [IO.File]::ReadAllText($claudeDest)
        if ($actual -cne $expected) {
            return @{ Passed = $false; Detail = "rendered bytes did not match the render contract exactly. First 200 chars expected=[$($expected.Substring(0,[Math]::Min(200,$expected.Length)))] actual=[$($actual.Substring(0,[Math]::Min(200,$actual.Length)))]" }
        }

        $after = Invoke-SyncInstructions -ExtraArgs @('-Audit', '-UserProfile', $userProfile)
        if ($after.Output -notmatch '(?m)^claude\s+current\b') {
            return @{ Passed = $false; Detail = "expected 'claude ... current' in the post-apply audit. Output: $($after.Output)" }
        }

        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 1b (fix round 1, CRITICAL): Hermes carries a registry-declared
# instructionBodyTemplate (header + identity preamble + {{globalPolicy}}
# placeholder + trailing marker) because its real deployed layout is NOT
# the generic header/marker/body contract every other host uses -- it has a
# preamble BEFORE the policy and the marker AFTER it. The renderer must
# substitute the canonical body into the placeholder rather than
# concatenating header+marker+body, or it would silently strip the "You are
# Hermes Agent ... Nous Research" identity text on every -Apply. Asserts an
# EXACT byte match against a template-substitution built independently in
# the test (not by calling into the renderer's own helper), so this cannot
# pass by both sides sharing the same bug. ---
function Test-HermesTemplateSubstitutionPreservesPreambleAndMarkerAtEnd {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-hermes-template-" + [guid]::NewGuid())
    $hermesDest = Join-Path $userProfile 'AppData\Local\hermes\SOUL.md'
    try {
        $apply = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($apply.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply exit code was $($apply.ExitCode). Output: $($apply.Output)" }
        }
        if (-not (Test-Path -LiteralPath $hermesDest)) {
            return @{ Passed = $false; Detail = "expected Hermes file was not written: $hermesDest. Output: $($apply.Output)" }
        }

        $policyBody = [IO.File]::ReadAllText((Join-Path $repoRoot 'global-agent-policy.md')).Replace("`r`n", "`n")
        $expectedPersona = 'You are Hermes Agent, an intelligent AI assistant created by Nous Research. Be helpful, knowledgeable, direct, targeted, and efficient. Admit uncertainty when appropriate and prioritize genuine usefulness.'
        $expected = "# Hermes Agent`n`n$expectedPersona`n`n$policyBody`n<!-- agenthub:managed -->`n"
        $actual = [IO.File]::ReadAllText($hermesDest)

        if ($actual -cne $expected) {
            return @{ Passed = $false; Detail = "Hermes rendered bytes did not match the preamble+placeholder template. This means the renderer is concatenating header+marker+body instead of substituting into instructionBodyTemplate -- it would strip the Hermes identity preamble on a real host. First 220 chars expected=[$($expected.Substring(0,[Math]::Min(220,$expected.Length)))] actual=[$($actual.Substring(0,[Math]::Min(220,$actual.Length)))]" }
        }
        if ($actual.IndexOf($expectedPersona, [StringComparison]::Ordinal) -lt 0) {
            return @{ Passed = $false; Detail = "the Hermes identity preamble ('You are Hermes Agent ... Nous Research ...') is missing from the rendered output entirely." }
        }
        $markerIndex = $actual.IndexOf('<!-- agenthub:managed -->', [StringComparison]::Ordinal)
        $lastRealCharIndex = $actual.TrimEnd().Length - 1
        if ($markerIndex -lt ($lastRealCharIndex - 30)) {
            return @{ Passed = $false; Detail = "the managed marker is not near the end of the Hermes file (markerIndex=$markerIndex, contentLength=$($actual.TrimEnd().Length)) -- Hermes' real deployed layout puts the marker at the end of the file, not after the header." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2: marker refusal. A destination that exists without the
# <!-- agenthub:managed --> marker must never be overwritten; the run must
# report it 'unmanaged' and exit non-zero. ---
function Test-UnmanagedDestinationRefusesAndExitsNonZero {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-unmanaged-" + [guid]::NewGuid())
    $claudeDest = Join-Path $userProfile '.claude\CLAUDE.md'
    $handWritten = "# My own hand-written CLAUDE.md`n`nThis is real user content with no AgentHub marker.`n"
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeDest) -Force | Out-Null
        [IO.File]::WriteAllText($claudeDest, $handWritten, [System.Text.UTF8Encoding]::new($false))

        $result = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) with an unmanaged destination present. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch '(?m)^claude\s+unmanaged\b') {
            return @{ Passed = $false; Detail = "expected 'claude ... unmanaged' in the output. Output: $($result.Output)" }
        }
        $stillThere = [IO.File]::ReadAllText($claudeDest)
        if ($stillThere -cne $handWritten) {
            return @{ Passed = $false; Detail = "the unmanaged destination was overwritten -- this is the exact defect the marker guard exists to prevent." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2b (fix round 1, IMPORTANT): the canonical policy body
# itself contains <!-- agenthub:canonical --> at its own line 3. The
# managed-marker guard must key on <!-- agenthub:managed --> SPECIFICALLY
# and must never be satisfiable by the canonical marker alone -- a
# destination containing only the canonical marker (no managed marker) is
# NOT AgentHub-managed and must still be refused as 'unmanaged'. A guard
# that accepts the wrong marker is a guard that does not guard. ---
function Test-MarkerDetectionCannotBeSatisfiedByCanonicalMarker {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-marker-specificity-" + [guid]::NewGuid())
    $claudeDest = Join-Path $userProfile '.claude\CLAUDE.md'
    # Realistic trap: a file that embeds the full canonical policy body
    # (and therefore the real <!-- agenthub:canonical --> marker at its own
    # line 3) but was never written by this renderer -- e.g. hand-pasted by
    # a user -- and so carries no <!-- agenthub:managed --> anywhere.
    $trapContent = "# Hand-pasted copy, not AgentHub-managed`n`n" +
        [IO.File]::ReadAllText((Join-Path $repoRoot 'global-agent-policy.md'))
    if ($trapContent.IndexOf('<!-- agenthub:managed -->', [StringComparison]::Ordinal) -ge 0) {
        return @{ Passed = $false; Detail = 'test setup invalid: the trap content unexpectedly already contains the managed marker' }
    }
    if ($trapContent.IndexOf('<!-- agenthub:canonical -->', [StringComparison]::Ordinal) -lt 0) {
        return @{ Passed = $false; Detail = 'test setup invalid: the trap content does not contain the canonical marker -- global-agent-policy.md may have changed shape' }
    }
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeDest) -Force | Out-Null
        [IO.File]::WriteAllText($claudeDest, $trapContent, [System.Text.UTF8Encoding]::new($false))

        $result = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 -- a destination containing only the canonical marker (no managed marker) was accepted as managed. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch '(?m)^claude\s+unmanaged\b') {
            return @{ Passed = $false; Detail = "expected 'claude ... unmanaged' for a destination that only contains the canonical marker. Output: $($result.Output)" }
        }
        $stillThere = [IO.File]::ReadAllText($claudeDest)
        if ($stillThere -cne $trapContent) {
            return @{ Passed = $false; Detail = "the destination was overwritten despite only containing the canonical marker, not the managed marker." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 3: idempotency. Two consecutive -Apply runs against the same
# fresh synthetic profile; the second reports zero updates. ---
function Test-SecondApplyIsIdempotent {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-idempotent-" + [guid]::NewGuid())
    try {
        $first = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode). Output: $($first.Output)" }
        }
        if ($first.Output -notmatch 'updated=(\d+)' -or [int]$Matches[1] -le 0) {
            return @{ Passed = $false; Detail = "first -Apply reported zero updates against a fresh profile -- test setup invalid. Output: $($first.Output)" }
        }

        $second = Invoke-SyncInstructions -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply exit code was $($second.ExitCode). Output: $($second.Output)" }
        }
        if ($second.Output -notmatch 'updated=(\d+)') {
            return @{ Passed = $false; Detail = "second -Apply output did not contain an 'updated=' summary. Output: $($second.Output)" }
        }
        if ([int]$Matches[1] -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply against an already-applied profile reported updated=$($Matches[1]), expected 0. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 4: empty work set must fail loudly, never report success. ---
function Test-EmptyWorkSetFailsLoudly {
    $emptyRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-empty-workset-root-" + [guid]::NewGuid())
    $registryDir = Join-Path $emptyRoot 'registry'
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-empty-workset-profile-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    $stubAgents = @{
        activeAgents = @(
            @{ id = 'stub-host'; name = 'Stub Host'; nativePaths = @{ instructions = $null }; status = 'active' }
        )
        inactiveAgents = @()
    }
    ($stubAgents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline
    Copy-Item -LiteralPath (Join-Path $repoRoot 'global-agent-policy.md') -Destination (Join-Path $emptyRoot 'global-agent-policy.md')
    try {
        $result = Invoke-SyncInstructions -ExtraArgs @('-Audit', '-RepositoryRoot', $emptyRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) against a registry with zero real destinations. Output: $($result.Output)" }
        }
        if ($result.Output -match 'Sync-Instructions complete') {
            return @{ Passed = $false; Detail = "script printed the success line against an empty work set. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $emptyRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r0 = Test-DestinationPathsAreRebasedUnderUserProfileOverride
Report 'destination paths are rebased under an overridden -UserProfile, never left pointing at the real profile' $r0.Passed $r0.Detail

$r1 = Test-RenderContractProducesExactBytes
Report 'render contract produces exact bytes: header, blank, marker, blank, canonical body' $r1.Passed $r1.Detail

$r1b = Test-HermesTemplateSubstitutionPreservesPreambleAndMarkerAtEnd
Report 'Hermes template substitution preserves the identity preamble and places the marker at the end' $r1b.Passed $r1b.Detail

$r2 = Test-UnmanagedDestinationRefusesAndExitsNonZero
Report 'unmanaged destination is refused and the run exits non-zero' $r2.Passed $r2.Detail

$r2b = Test-MarkerDetectionCannotBeSatisfiedByCanonicalMarker
Report 'marker detection keys on agenthub:managed specifically and cannot be satisfied by agenthub:canonical' $r2b.Passed $r2b.Detail

$r3 = Test-SecondApplyIsIdempotent
Report 'second consecutive -Apply against the same profile reports zero updates' $r3.Passed $r3.Detail

$r4 = Test-EmptyWorkSetFailsLoudly
Report 'zero real destinations in the work set fails loudly instead of reporting success' $r4.Passed $r4.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $(7 - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: 7 passed, 0 failed' -ForegroundColor Green
exit 0
