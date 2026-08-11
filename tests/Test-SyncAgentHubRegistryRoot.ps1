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

function Invoke-SyncAgentHub {
    param([string[]]$ExtraArgs = @(), [string]$ScriptPath = $null)
    # -ScriptPath lets behavior 2 run a COPY of the script from a scratch tree.
    # The default stays the real script, so every other behavior is unchanged.
    $target = if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $syncScript } else { $ScriptPath }
    $allArgs = @('-NoProfile', '-File', $target, '-Audit') + $ExtraArgs
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
# root from its own on-disk location, not a hardcoded checkout.
#
# Proven by copying the repository to a scratch tree, planting a uniquely-named
# canary agent in THAT COPY's registry/agents.json, running THE COPIED SCRIPT
# with no -RegistryRoot, and requiring the canary in its drift output. The
# canary exists only in the copy, so seeing it proves the script read the
# registry sitting beside itself. A hardcoded path back to the real checkout
# fails, because that registry has no canary -- which is the defect this
# behavior exists to catch, now discriminated more sharply than before.
#
# It used to plant the canary in the REAL registry/agents.json and revert it in
# a finally block. A finally block does not run when the process is killed, and
# on 2026-08-11 an interrupted suite left a canary behind that was then
# committed -- a modified registry/agents.json looks exactly like the author's
# own edit. Test-PluginManifests.ps1 already records this rule for the plugin
# manifest ("A run killed between the write and the restore leaves that file
# broken in the user's checkout... Mutate a copy outside the repository
# instead"); the fleet now has one rule instead of two. Behavior 6 below pins
# it down so this cannot quietly regress.
#
# .git and node_modules are excluded: the script reads registry/, scripts/ and
# packages/, and copying history would dominate the runtime for nothing. ---
function Copy-RepositoryToScratch {
    param([string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($entry in @(Get-ChildItem -LiteralPath $repoRoot -Force)) {
        if ($entry.Name -in @('.git', 'node_modules')) { continue }
        Copy-Item -LiteralPath $entry.FullName -Destination $Destination -Recurse -Force
    }
}
function Test-NoRegistryRootSelfDerivesFromScriptLocation {
    $scratchRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-self-derive-" + [guid]::NewGuid())
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-self-derive-profile-" + [guid]::NewGuid())
    $marker = 'agenthub-task0c-canary-' + [guid]::NewGuid().ToString('N')
    try {
        Copy-RepositoryToScratch -Destination $scratchRoot
        $scratchAgentsJson = Join-Path $scratchRoot 'registry\agents.json'
        $scratchScript = Join-Path $scratchRoot 'scripts\Sync-AgentHub.ps1'
        if (-not (Test-Path -LiteralPath $scratchAgentsJson) -or -not (Test-Path -LiteralPath $scratchScript)) {
            return @{ Passed = $false; Detail = "the scratch copy at $scratchRoot is missing registry\agents.json or scripts\Sync-AgentHub.ps1, so this behavior would be testing an incomplete tree rather than root self-derivation." }
        }
        $agentsDoc = Get-Content -LiteralPath $scratchAgentsJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $canaryAgent = [pscustomobject]@{
            id = $marker
            name = 'AgentHub Task 0c Canary (scratch copy only)'
            status = 'inactive'
            nativePaths = [pscustomobject]@{ instructions = $null }
            supportedCapabilities = @()
        }
        $agentsDoc.inactiveAgents = @(@($agentsDoc.inactiveAgents) + @($canaryAgent))
        ($agentsDoc | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $scratchAgentsJson -Encoding UTF8

        $result = Invoke-SyncAgentHub -ScriptPath $scratchScript -ExtraArgs @('-UserProfile', $userProfile, '-IncludeInactiveAgents')

        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $($result.ExitCode) instead of 0 running the copied script with no -RegistryRoot against $scratchRoot. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch [regex]::Escape("[$marker]")) {
            return @{ Passed = $false; Detail = "drift output did not mention canary host '$marker', which exists ONLY in the scratch copy at $scratchRoot -- so the script did not read the registry sitting beside itself and is resolving its root from somewhere else (a hardcoded checkout would produce exactly this). Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
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

# --- Behavior 4: -UserProfile must rebase the HOST DESTINATIONS too, not just
# the runtime state directory. registry/agents.json stores every nativePaths
# value as an absolute path baked against the real profile, so before this was
# fixed a caller passing a synthetic profile for isolation still had every
# host destination pointing at the real, live fleet -- and an -Apply intended
# to be isolated wrote real host configuration. That happened twice in this
# repo's history, under two different scripts. This asserts it cannot recur:
# the audit's own drift report must name no path under the real profile.
# -Audit only; nothing is written by this test. ---
function Test-UserProfileRebasesHostDestinations {
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-syncah-hostdest-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $userProfile -Force | Out-Null
    $realProfile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    try {
        $result = Invoke-SyncAgentHub -ExtraArgs @('-UserProfile', $userProfile)
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Audit exit code was $($result.ExitCode). Output: $($result.Output)" }
        }
        $driftPath = Join-Path $userProfile 'AppData\Local\AgentHub\sync\latest-drift.json'
        if (-not (Test-Path -LiteralPath $driftPath)) {
            return @{ Passed = $false; Detail = "no drift report was written under the supplied profile (expected $driftPath)." }
        }
        $drift = Get-Content -LiteralPath $driftPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $paths = @()
        foreach ($hostEntry in @($drift.hosts)) {
            foreach ($entry in @($hostEntry.mcp) + @($hostEntry.files)) {
                if ($entry -and $entry.path) { $paths += [string]$entry.path }
            }
        }
        if ($paths.Count -eq 0) {
            return @{ Passed = $false; Detail = 'the drift report named zero destination paths, so this assertion checked nothing.' }
        }
        # Compare against the registry's own declared destinations rather than
        # a "under the real profile" prefix test: the scratch profile itself
        # lives under %TEMP%, which is under the real profile, so a prefix test
        # flags correctly-rebased paths.
        $declared = @{}
        $agentsDoc = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($agent in @(@($agentsDoc.activeAgents) + @($agentsDoc.inactiveAgents))) {
            if (-not $agent.nativePaths) { continue }
            foreach ($property in @($agent.nativePaths.PSObject.Properties)) {
                $candidate = $property.Value
                # nativePaths also carries non-path values (hermes stores an
                # instruction template and a prose note there), so filter to
                # rooted paths rather than calling GetFullPath on everything --
                # .NET Framework throws "Illegal characters in path" on the rest.
                if ($candidate -is [string] -and $candidate.Length -ge 3 -and $candidate[1] -eq ':' -and $candidate[2] -eq '\') {
                    $declared[$candidate.TrimEnd('\')] = $true
                }
            }
        }
        if ($declared.Count -eq 0) {
            return @{ Passed = $false; Detail = 'registry/agents.json declared zero nativePaths, so this assertion checked nothing.' }
        }
        $leaked = @($paths | Where-Object { $declared.ContainsKey($_.TrimEnd('\')) })
        if ($leaked.Count -gt 0) {
            return @{ Passed = $false; Detail = "-UserProfile did not rebase host destinations; $($leaked.Count) still point at the registry's real declared paths, e.g. $($leaked[0])" }
        }
        $rebased = @($paths | Where-Object { $_.StartsWith($userProfile + '\', [StringComparison]::OrdinalIgnoreCase) })
        if ($rebased.Count -eq 0) {
            return @{ Passed = $false; Detail = "no destination path landed under the supplied -UserProfile, so nothing was actually rebased. Paths: $($paths -join '; ')" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: an absolute nativePaths value in a shape the rebasing does
# not handle (UNC, or drive-letter with forward slashes) must fail loudly.
# Such a value would otherwise fall past the drive-letter test, stay
# unrebased, and be written to literally under an isolated -Apply -- the same
# leak Behavior 4 covers, arriving through a different door. Nothing in the
# registry has that shape today, which is exactly why it needs a test. ---
function Test-UnrebasablePathShapeFailsLoudly {
    $fixtureRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-unc-shape-root-" + [guid]::NewGuid())
    $registryDir = Join-Path $fixtureRoot 'registry'
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-unc-shape-profile-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    $agents = @{
        activeAgents = @(
            @{ id = 'codex'; name = 'Fixture Codex'; status = 'active'; nativePaths = @{ config = '\\fileserver\agents\codex\config.toml' } }
        )
        inactiveAgents = @()
    }
    ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline
    Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Value '{ "mcpServers": [] }' -Encoding UTF8 -NoNewline
    try {
        $result = Invoke-SyncAgentHub -ExtraArgs @('-RegistryRoot', $fixtureRoot, '-UserProfile', $userProfile)
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 against a UNC nativePaths value that cannot be rebased. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch 'rebasing does not support') {
            return @{ Passed = $false; Detail = "failed, but not with the unrebasable-shape message -- it may have failed for an unrelated reason, which would make this assertion vacuous. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 6: this suite leaves the tracked registry byte-identical.
#
# Behavior 2 is the only thing here that ever wanted to write it, and it no
# longer does. This pins that down, because the failure it prevents is not a
# wrong assertion -- it is a leaked canary committed into registry/agents.json,
# which is what happened on 2026-08-11 and cost a red suite plus a bad commit.
# The check is bytes, not parsed JSON: a re-serialization that changed only
# formatting or line endings would still be an unintended write to a tracked
# file, and this repository has CRLF gates that would then fire somewhere else
# entirely.
#
# Captured before the behaviors run and compared after, so it covers the whole
# file rather than trusting any one of them to clean up. It cannot catch a
# process killed mid-run -- nothing inside the process can -- which is exactly
# why behavior 2 was changed to never write the file in the first place, rather
# than being left to restore it more carefully. ---
$trackedRegistryPath = Join-Path $repoRoot 'registry\agents.json'
$trackedRegistryBytesBefore = [IO.File]::ReadAllBytes($trackedRegistryPath)

function Test-SuiteLeavesTrackedRegistryUntouched {
    $after = [IO.File]::ReadAllBytes($trackedRegistryPath)
    if ($trackedRegistryBytesBefore.Length -ne $after.Length) {
        return @{ Passed = $false; Detail = "registry/agents.json changed while this suite ran ($($trackedRegistryBytesBefore.Length) bytes before, $($after.Length) after). Nothing in this suite may write it -- behavior 2 works on a scratch copy precisely so an interrupted run cannot leave a canary in the checkout. Inspect `git diff registry/agents.json` before committing anything." }
    }
    for ($i = 0; $i -lt $after.Length; $i++) {
        if ($trackedRegistryBytesBefore[$i] -ne $after[$i]) {
            return @{ Passed = $false; Detail = "registry/agents.json changed while this suite ran -- same length, first differing byte at offset $i. Nothing in this suite may write it. Inspect `git diff registry/agents.json` before committing anything." }
        }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-EmptyRegistryRootFailsLoudly
Report 'empty/wrong registry root fails loudly instead of reporting success' $r1.Passed $r1.Detail

$r2 = Test-NoRegistryRootSelfDerivesFromScriptLocation
Report 'no -RegistryRoot self-derives from the running script location' $r2.Passed $r2.Detail

$r3 = Test-UserProfileOverrideRedirectsRuntimeState
Report '-UserProfile override still redirects runtime state to the specified path' $r3.Passed $r3.Detail

$r4 = Test-UserProfileRebasesHostDestinations
Report '-UserProfile rebases host destinations, not just the runtime state directory' $r4.Passed $r4.Detail

$r5 = Test-UnrebasablePathShapeFailsLoudly
Report 'an absolute nativePaths shape the rebasing cannot handle fails loudly' $r5.Passed $r5.Detail

# Last, so it observes every write the behaviors above could have made.
$r6 = Test-SuiteLeavesTrackedRegistryUntouched
Report 'the suite leaves the tracked registry/agents.json byte-identical' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
