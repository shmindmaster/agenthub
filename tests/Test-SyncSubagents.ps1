#Requires -Version 5.1
<#
Behavior tests for scripts/Sync-Subagents.ps1 (task-5: restore the deleted,
single-capability-hardcoded scripts/Sync-ProductDemoStudioHostAdapters.ps1
as a capability-generic generator).

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1, tests/Test-SyncAgentHubRegistryRoot.ps1,
tests/Test-SyncInstructions.ps1 for the prior art this file follows). Same
self-checking idiom: each Test-* function returns a result, the runner
prints one PASS/FAIL line per behavior, accumulates failures, and exits 1 if
any behavior did not hold, 0 otherwise.

Every -Apply invocation below targets a synthetic -UserProfile under
$env:AGENTHUB_TEST_SCRATCH, and every synthetic profile that needs to prove
a real write pre-creates the host's root marker directory (e.g. .codex) so
the "host not installed" skip path does not mask the behavior under test.
None ever targets the real user profile.

Run: pwsh -NoProfile -File tests/Test-SyncSubagents.ps1
     powershell.exe -NoProfile -File tests/Test-SyncSubagents.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-Subagents.ps1'
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

function Invoke-SyncSubagents {
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

function New-SyntheticProfile {
    param([string]$Name, [switch]$InstallCodex, [switch]$InstallOpenCode, [switch]$InstallGemini, [switch]$InstallAntigravity)
    $profileRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-$Name-" + [guid]::NewGuid())
    if ($InstallCodex) { New-Item -ItemType Directory -Path (Join-Path $profileRoot '.codex') -Force | Out-Null }
    if ($InstallOpenCode) { New-Item -ItemType Directory -Path (Join-Path $profileRoot '.config\opencode') -Force | Out-Null }
    if ($InstallGemini) { New-Item -ItemType Directory -Path (Join-Path $profileRoot '.gemini') -Force | Out-Null }
    if ($InstallAntigravity) { New-Item -ItemType Directory -Path (Join-Path $profileRoot '.gemini\antigravity-cli') -Force | Out-Null }
    return $profileRoot
}

# ---------------------------------------------------------------------------
# Fixture repository root: a throwaway registry/capabilities.json declaring
# exactly one capability, plus a real packages/<fixtureId>/agents/*.agent.md
# and .codex-plugin/plugin.json. Used to prove capability-generic iteration
# (the fixture id is never referenced by name inside Sync-Subagents.ps1) and
# to prove the flow-sequence tools: failure without touching any real,
# checked-in canonical agent file.
# ---------------------------------------------------------------------------
function New-FixtureRepositoryRoot {
    param([string]$FixtureCapabilityId, [string]$ToolsLine, [bool]$IncludeReadonlyTrue)
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-fixture-repo-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'registry\subagent-formats.json') -Destination (Join-Path $registryDir 'subagent-formats.json')

    $capabilities = @{
        schemaVersion = 2
        capabilities = @(
            @{
                id = $FixtureCapabilityId
                owner = 'test-fixture'
                capabilityType = 'agents'
                canonicalSource = "packages/$FixtureCapabilityId"
            }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    $packageRoot = Join-Path $root "packages\$FixtureCapabilityId"
    New-Item -ItemType Directory -Path (Join-Path $packageRoot 'agents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $packageRoot '.codex-plugin') -Force | Out-Null
    (@{ name = $FixtureCapabilityId; version = '0.1.0' } | ConvertTo-Json) |
        Set-Content -LiteralPath (Join-Path $packageRoot '.codex-plugin\plugin.json') -Encoding UTF8 -NoNewline

    $readonlyLine = if ($IncludeReadonlyTrue) { "`nreadonly: true" } else { '' }
    $agentContent = "---`nname: sample-role`ndescription: Fixture role for capability-generic iteration testing.`n$ToolsLine$readonlyLine`n---`n`nFixture body text, one paragraph, nothing else.`n"
    Set-Content -LiteralPath (Join-Path $packageRoot 'agents\sample-role.agent.md') -Value $agentContent -Encoding UTF8 -NoNewline

    return $root
}

# --- Behavior 1: capability-generic iteration. A fixture capability with an
# agents/ directory is picked up and appears in the audit output WITHOUT its
# id ever being written into Sync-Subagents.ps1 -- proven by using an id
# ("zz-fixture-capability-9f3c") that cannot possibly already appear in the
# script's source. ---
function Test-CapabilityGenericIterationPicksUpFixtureCapability {
    $fixtureId = 'zz-fixture-capability-9f3c'
    $scriptSource = [IO.File]::ReadAllText($syncScript)
    if ($scriptSource.IndexOf($fixtureId, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return @{ Passed = $false; Detail = 'test setup invalid: the fixture capability id already appears in Sync-Subagents.ps1 source' }
    }
    $fixtureRoot = New-FixtureRepositoryRoot -FixtureCapabilityId $fixtureId -ToolsLine 'tools: Read, Grep' -IncludeReadonlyTrue $false
    $userProfile = New-SyntheticProfile -Name 'generic-iter' -InstallCodex
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Audit', '-RepositoryRoot', $fixtureRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode). Output: $($result.Output)" }
        }
        $expectedRow = "$fixtureId" + '                            codex        sample-role'
        if ($result.Output.IndexOf($fixtureId, [StringComparison]::Ordinal) -lt 0) {
            return @{ Passed = $false; Detail = "fixture capability id '$fixtureId' did not appear anywhere in the audit output, meaning it was not iterated. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch [regex]::Escape($fixtureId) + '\s+codex\s+sample-role\s+missing') {
            return @{ Passed = $false; Detail = "expected a 'codex ... sample-role ... missing' row for the fixture capability. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2: a YAML flow-sequence tools: value ("tools: [Read, Grep]")
# must fail loudly with a specific, actionable error -- never silently
# produce stray-bracket tokens like "[Read" (the confirmed defect C4). ---
function Test-FlowSequenceToolsFailsLoudly {
    $fixtureId = 'zz-flow-seq-capability-2a71'
    $fixtureRoot = New-FixtureRepositoryRoot -FixtureCapabilityId $fixtureId -ToolsLine 'tools: [Read, Grep, Glob]' -IncludeReadonlyTrue $false
    $userProfile = New-SyntheticProfile -Name 'flow-seq' -InstallCodex
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Audit', '-RepositoryRoot', $fixtureRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 -- a flow-sequence tools: value was silently accepted instead of failing loudly. Output: $($result.Output)" }
        }
        if ($result.Output.IndexOf('"[Read', [StringComparison]::Ordinal) -ge 0) {
            return @{ Passed = $false; Detail = "output contains the stray-bracket token '[Read' -- this is the exact silent-mis-split defect (C4), not a loud failure. Output: $($result.Output)" }
        }
        if ($result.Output.IndexOf('flow-sequence', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return @{ Passed = $false; Detail = "expected an explicit error mentioning 'flow-sequence'. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 3: readonly: true maps to Codex's sandbox_mode = "read-only";
# a non-readonly agent must NOT carry that line. Applies against a synthetic
# profile so the rendered bytes can be read back and asserted directly. ---
function Test-ReadOnlyMapsToSandboxModeForCodex {
    $readonlyId = 'zz-readonly-capability-77b1'
    $readonlyRoot = New-FixtureRepositoryRoot -FixtureCapabilityId $readonlyId -ToolsLine 'tools: Read, Grep' -IncludeReadonlyTrue $true
    $plainId = 'zz-plain-capability-77b1'
    $plainRoot = New-FixtureRepositoryRoot -FixtureCapabilityId $plainId -ToolsLine 'tools: Read, Grep, Edit, Write' -IncludeReadonlyTrue $false
    $userProfile = New-SyntheticProfile -Name 'readonly-map' -InstallCodex
    try {
        $r1 = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-RepositoryRoot', $readonlyRoot, '-UserProfile', $userProfile)
        if ($r1.ExitCode -ne 0) { return @{ Passed = $false; Detail = "readonly fixture -Apply exit code $($r1.ExitCode). Output: $($r1.Output)" } }
        $readonlyDest = Join-Path $userProfile ".codex\agents\$readonlyId-sample-role.toml"
        if (-not (Test-Path -LiteralPath $readonlyDest)) { return @{ Passed = $false; Detail = "readonly fixture file was not written: $readonlyDest" } }
        $readonlyContent = [IO.File]::ReadAllText($readonlyDest)
        if ($readonlyContent -notmatch '(?m)^sandbox_mode = "read-only"\s*$') {
            return @{ Passed = $false; Detail = "readonly agent's Codex TOML is missing sandbox_mode = `"read-only`". Content: $readonlyContent" }
        }

        $r2 = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-RepositoryRoot', $plainRoot, '-UserProfile', $userProfile)
        if ($r2.ExitCode -ne 0) { return @{ Passed = $false; Detail = "plain fixture -Apply exit code $($r2.ExitCode). Output: $($r2.Output)" } }
        $plainDest = Join-Path $userProfile ".codex\agents\$plainId-sample-role.toml"
        $plainContent = [IO.File]::ReadAllText($plainDest)
        if ($plainContent -match 'sandbox_mode') {
            return @{ Passed = $false; Detail = "non-readonly agent's Codex TOML unexpectedly contains sandbox_mode. Content: $plainContent" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $readonlyRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $plainRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 4: destination paths are always rooted under the effective
# -UserProfile, never the real invoking profile. Unlike Sync-Instructions.ps1
# this script never reads a registry-baked absolute destination path at all
# (see scripts/Sync-Subagents.ps1's .DESCRIPTION), so this is a narrower,
# by-construction guarantee -- still worth a permanent regression test. ---
function Test-DestinationPathsAreRebasedUnderUserProfileOverride {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-rebase-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $userProfile '.codex') -Force | Out-Null
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Audit', '-UserProfile', $userProfile)
        if ($result.Output -notmatch '(?m)product-demo-studio\s+codex\s+remediation-agent\s+\S+\s+\S+\s+(\S+)') {
            return @{ Passed = $false; Detail = "could not find a product-demo-studio/codex/remediation-agent row with a path. Output: $($result.Output)" }
        }
        $reportedPath = $Matches[1]
        if (-not $reportedPath.StartsWith($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
            return @{ Passed = $false; Detail = "reported destination path was '$reportedPath', not under the synthetic -UserProfile '$userProfile'." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: marker/shape-guard refusal. A destination that exists but
# does not structurally resemble this generator's own output (garbage
# content, not TOML-shaped) must never be overwritten -- reported
# 'unmanaged', run exits non-zero, file left byte-identical. ---
function Test-UnmanagedDestinationRefusesAndExitsNonZero {
    $userProfile = New-SyntheticProfile -Name 'unmanaged' -InstallCodex
    $dest = Join-Path $userProfile '.codex\agents\product-demo-studio-episode-architect.toml'
    $handWritten = "this is not a TOML subagent file at all, just some unrelated hand-written text that happens to live at the exact generated filename`n"
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        [IO.File]::WriteAllText($dest, $handWritten, [Text.UTF8Encoding]::new($false))

        $result = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) with an unmanaged destination present. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch '(?m)product-demo-studio\s+codex\s+episode-architect\s+unmanaged\b') {
            return @{ Passed = $false; Detail = "expected an 'unmanaged' row for product-demo-studio/codex/episode-architect. Output: $($result.Output)" }
        }
        $stillThere = [IO.File]::ReadAllText($dest)
        if ($stillThere -cne $handWritten) {
            return @{ Passed = $false; Detail = "the unmanaged destination was overwritten -- this is the exact defect the guard exists to prevent." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 6: idempotency. Two consecutive -Apply runs against the same
# fresh synthetic profile (all 4 hosts installed); the second reports zero
# updates. ---
function Test-SecondApplyIsIdempotent {
    $userProfile = New-SyntheticProfile -Name 'idempotent' -InstallCodex -InstallOpenCode -InstallGemini -InstallAntigravity
    try {
        $first = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode). Output: $($first.Output)" }
        }
        if ($first.Output -notmatch 'updated=(\d+)' -or [int]$Matches[1] -le 0) {
            return @{ Passed = $false; Detail = "first -Apply reported zero updates against a fresh profile -- test setup invalid. Output: $($first.Output)" }
        }
        $firstUpdated = [int]$Matches[1]

        $second = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply exit code was $($second.ExitCode). Output: $($second.Output)" }
        }
        if ($second.Output -notmatch 'updated=(\d+)') {
            return @{ Passed = $false; Detail = "second -Apply output did not contain an 'updated=' summary. Output: $($second.Output)" }
        }
        if ([int]$Matches[1] -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply against an already-applied profile reported updated=$($Matches[1]) (first Apply had updated=$firstUpdated), expected 0. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 7: a capability with no agents/ directory at all (the
# majority of registry/capabilities.json -- e.g. digitalocean) is skipped cleanly,
# never causing an error, and never appears in the results. ---
function Test-CapabilityWithoutAgentsDirectoryIsSkippedCleanly {
    $userProfile = New-SyntheticProfile -Name 'no-agents-dir' -InstallCodex
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Audit', '-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode) running against the real registry, which contains capabilities with no agents/ dir. Output: $($result.Output)" }
        }
        if ($result.Output -match '(?m)^digitalocean\s') {
            return @{ Passed = $false; Detail = "capability 'digitalocean' (no agents/ directory) unexpectedly appears in the results. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 8: a host whose root config directory does not exist at all
# (e.g. no ~/.codex) is reported 'skipped (host not installed)' and no
# directory tree is created for it -- never force-installed. ---
function Test-HostNotInstalledIsSkippedCleanlyWithoutCreatingDirectories {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-not-installed-" + [guid]::NewGuid())
    # Deliberately do NOT pre-create .codex, .config\opencode, .gemini, etc.
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Apply', '-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode) for a profile with zero hosts installed. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch '(?m)product-demo-studio\s+codex\s+episode-architect\s+skipped \(host not installed\)') {
            return @{ Passed = $false; Detail = "expected a 'skipped (host not installed)' row for codex. Output: $($result.Output)" }
        }
        if (Test-Path -LiteralPath (Join-Path $userProfile '.codex')) {
            return @{ Passed = $false; Detail = "a .codex directory was created for a host that was never installed in this synthetic profile -- this generator must never force-create host installation directories." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 9: empty work set (zero capabilities with an agents/
# directory) must fail loudly, never report success. ---
function Test-EmptyWorkSetFailsLoudly {
    $emptyRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-empty-root-" + [guid]::NewGuid())
    $registryDir = Join-Path $emptyRoot 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'registry\subagent-formats.json') -Destination (Join-Path $registryDir 'subagent-formats.json')
    $stubCapabilities = @{
        schemaVersion = 2
        capabilities = @(
            @{ id = 'stub-capability-with-no-agents-dir'; owner = 'test'; capabilityType = 'skills'; canonicalSource = 'packages/does-not-exist' }
        )
    }
    ($stubCapabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-subagents-empty-profile-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $userProfile '.codex') -Force | Out-Null
    try {
        $result = Invoke-SyncSubagents -ExtraArgs @('-Audit', '-RepositoryRoot', $emptyRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) against a registry with zero capabilities that have an agents/ directory. Output: $($result.Output)" }
        }
        if ($result.Output -match 'Sync-Subagents complete') {
            return @{ Passed = $false; Detail = "script printed the success line against an empty work set. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $emptyRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-CapabilityGenericIterationPicksUpFixtureCapability
Report 'capability-generic iteration picks up a fixture capability the script never names' $r1.Passed $r1.Detail

$r2 = Test-FlowSequenceToolsFailsLoudly
Report 'a YAML flow-sequence tools: value fails loudly instead of silently mis-splitting' $r2.Passed $r2.Detail

$r3 = Test-ReadOnlyMapsToSandboxModeForCodex
Report 'readonly: true maps to Codex sandbox_mode = "read-only"; a non-readonly agent omits it' $r3.Passed $r3.Detail

$r4 = Test-DestinationPathsAreRebasedUnderUserProfileOverride
Report 'destination paths are always rooted under the effective -UserProfile' $r4.Passed $r4.Detail

$r5 = Test-UnmanagedDestinationRefusesAndExitsNonZero
Report 'a destination that does not match this generator''s own shape is refused and exits non-zero' $r5.Passed $r5.Detail

$r6 = Test-SecondApplyIsIdempotent
Report 'second consecutive -Apply against the same profile reports zero updates' $r6.Passed $r6.Detail

$r7 = Test-CapabilityWithoutAgentsDirectoryIsSkippedCleanly
Report 'a capability with no agents/ directory is skipped cleanly, not treated as an error' $r7.Passed $r7.Detail

$r8 = Test-HostNotInstalledIsSkippedCleanlyWithoutCreatingDirectories
Report 'a host with no root config directory is skipped cleanly without creating one' $r8.Passed $r8.Detail

$r9 = Test-EmptyWorkSetFailsLoudly
Report 'zero eligible capabilities fails loudly instead of reporting success' $r9.Passed $r9.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
