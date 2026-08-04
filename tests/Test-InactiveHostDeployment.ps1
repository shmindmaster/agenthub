#Requires -Version 5.1
<#
Behavior tests for inactive-host handling in scripts/Sync-Capabilities.ps1.

registry/agents.json splits hosts into activeAgents and inactiveAgents.
Sync-Capabilities used to concatenate both and deploy to all of them, so 33
of the registry's capability->host mappings -- amp, devin, factory,
vscode-insiders and windsurf -- produced a full skill copy each for hosts the
fleet profile never dispatches to. Sync-AgentHub.ps1 had already settled the
convention for this with -IncludeInactiveAgents (inactive excluded unless
asked for); this brings capability deployment onto the same convention rather
than leaving the fleet with two.

The interesting failure mode is not "deploys too much" -- it is the silent
inverse. A filter that accidentally matched nothing would deploy nothing and
still print PASS, which is the defect class this suite exists to eliminate.
So behavior 2 pins the active host down in the same fixture: the inactive
host must be skipped WHILE the active host still deploys. And behavior 4
requires an all-inactive registry to fail loudly naming the real cause,
instead of falling through to the generic zero-rows guard.

Not a Pester suite: same self-checking accumulate-and-report idiom as
tests/Test-SharedSkillsDeployment.ps1 (this repo carries no Pester
dependency). Each Test-* function returns @{ Passed; Detail }, Report()
prints one PASS/FAIL line, the runner exits 1 if anything failed.

SAFETY: every invocation below targets a synthetic -RepositoryRoot, a
synthetic -UserProfile, and a synthetic -LOCALAPPDATA runtime-state
directory, all under $env:AGENTHUB_TEST_SCRATCH. None ever targets the real
repository, the real user profile, or the real %LOCALAPPDATA%.

Run: pwsh -NoProfile -File tests/Test-InactiveHostDeployment.ps1
     powershell.exe -NoProfile -File tests/Test-InactiveHostDeployment.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-Capabilities.ps1'
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

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

function Invoke-SyncCapabilities {
    param([string[]]$ExtraArgs = @(), [Parameter(Mandatory)][string]$LocalAppData)
    $allArgs = @('-NoProfile', '-File', $syncScript) + $ExtraArgs
    $previousEap = $ErrorActionPreference
    $previousLad = $env:LOCALAPPDATA
    $ErrorActionPreference = 'Continue'
    try {
        $env:LOCALAPPDATA = $LocalAppData
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
        $env:LOCALAPPDATA = $previousLad
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

# Mirrors the -UserProfile rebasing in scripts/Sync-Capabilities.ps1: fixture
# paths live under $env:TEMP (itself under the real profile), so the script
# legitimately rebases them under a synthetic -UserProfile. The fixture has
# to resolve destinations the same way or it asserts against paths nothing
# was ever written to.
function Get-EffectiveDestination {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$UserProfile)
    $full = [IO.Path]::GetFullPath($Path)
    $realProfile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    $effective = [IO.Path]::GetFullPath($UserProfile).TrimEnd('\')
    if ($effective -eq $realProfile) { return $full }
    if ($full.StartsWith($realProfile + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $effective $full.Substring($realProfile.Length + 1)
    }
    return $full
}

# One capability with one skill, mapped to every host given. Host descriptors
# are @{ Id; Status } where Status is 'active' or 'inactive'; each lands in
# the matching registry array with its own private skillsDir.
function New-InactiveHostFixture {
    param(
        [Parameter(Mandatory)][string]$CapabilityId,
        [Parameter(Mandatory)][object[]]$HostDescriptors
    )
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-inactive-repo-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-inactive-profile-" + [guid]::NewGuid())

    $activeAgents = @()
    $inactiveAgents = @()
    $hostMappings = @()
    $effectiveHosts = @{}
    foreach ($descriptor in $HostDescriptors) {
        $skillsDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-inactive-$($descriptor.Id)-" + [guid]::NewGuid())
        $agent = @{
            id          = $descriptor.Id
            name        = "Fixture Host $($descriptor.Id)"
            status      = $descriptor.Status
            nativePaths = @{ skillsDir = $skillsDir }
        }
        if ($descriptor.Status -eq 'active') { $activeAgents += $agent } else { $inactiveAgents += $agent }
        $hostMappings += @{ hostId = $descriptor.Id; deploymentStatus = 'managed' }
        $effectiveHosts[$descriptor.Id] = Get-EffectiveDestination -Path $skillsDir -UserProfile $userProfile
    }

    # PowerShell 5.1's ConvertTo-Json renders a single-element array as a bare
    # object. That is harmless here only because Sync-Capabilities.ps1 re-wraps
    # both arrays with @(...) on read; do not rely on the emitted shape.
    $agentsDocument = [ordered]@{
        schemaVersion  = 2
        activeAgents   = @($activeAgents)
        inactiveAgents = @($inactiveAgents)
    }
    ($agentsDocument | ConvertTo-Json -Depth 10) |
        Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    $capabilities = @{
        schemaVersion = 2
        capabilities  = @(
            @{
                id              = $CapabilityId
                owner           = 'test'
                capabilityType  = 'skill-pack'
                canonicalSource = "packages/$CapabilityId"
                hostMappings    = $hostMappings
            }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) |
        Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    $skillRoot = Join-Path $root "packages\$CapabilityId\skills\sample-skill"
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value 'canonical content v1' -Encoding UTF8 -NoNewline

    return [pscustomobject]@{
        Root         = $root
        RegistryDir  = $registryDir
        Hosts        = $effectiveHosts
        LocalAppData = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-inactive-lad-" + [guid]::NewGuid())
        UserProfile  = $userProfile
    }
}

function Remove-InactiveHostFixture {
    param($Fixture)
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.LocalAppData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.UserProfile -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($skillsDir in $Fixture.Hosts.Values) {
        Remove-Item -LiteralPath $skillsDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$mixedHosts = @(
    @{ Id = 'zz-inactive-active'; Status = 'active' },
    @{ Id = 'zz-inactive-dormant'; Status = 'inactive' }
)

# --- Behaviors 1 and 2 share one -Apply: a host in inactiveAgents receives
# nothing, WHILE a host in activeAgents mapped to the same capability still
# receives its copy. Asserting both against a single run is what makes the
# skip provably a filter rather than a blanket no-op. ---
function Test-DefaultRunSkipsInactiveButDeploysActive {
    $fixture = New-InactiveHostFixture -CapabilityId 'zz-inactive-cap' -HostDescriptors $mixedHosts
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply exit code was $($result.ExitCode). Output: $($result.Output)" }
        }

        $activeDestination = Join-Path $fixture.Hosts['zz-inactive-active'] 'sample-skill\SKILL.md'
        if (-not (Test-Path -LiteralPath $activeDestination)) {
            return @{ Passed = $false; Detail = "the ACTIVE host received nothing at $activeDestination. The inactive-host filter is a blanket no-op, not a filter -- it would have made the skip assertion pass for the wrong reason. Output: $($result.Output)" }
        }

        $inactiveDestination = Join-Path $fixture.Hosts['zz-inactive-dormant'] 'sample-skill'
        if (Test-Path -LiteralPath $inactiveDestination) {
            return @{ Passed = $false; Detail = "a host listed in inactiveAgents received a skill copy at $inactiveDestination on a default run. Inactive hosts are inventory, not deployment targets." }
        }

        $statePath = Join-Path $fixture.UserProfile 'AppData\Local\AgentHub\sync\managed-skills.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $managedCount = @($state.managed.PSObject.Properties).Count
        if ($managedCount -ne 1) {
            return @{ Passed = $false; Detail = "expected exactly 1 managed entry (the active host only), got $managedCount." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-InactiveHostFixture -Fixture $fixture
    }
}

# --- Behavior 3: -IncludeInactiveAgents restores the old behavior, so the
# inactive hosts remain reachable on demand rather than being unreachable.
# Without this the change would be a deletion of capability, not a default. ---
function Test-SwitchRestoresInactiveHosts {
    $fixture = New-InactiveHostFixture -CapabilityId 'zz-inactive-switch-cap' -HostDescriptors $mixedHosts
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-IncludeInactiveAgents', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply -IncludeInactiveAgents exit code was $($result.ExitCode). Output: $($result.Output)" }
        }
        $inactiveDestination = Join-Path $fixture.Hosts['zz-inactive-dormant'] 'sample-skill\SKILL.md'
        if (-not (Test-Path -LiteralPath $inactiveDestination)) {
            return @{ Passed = $false; Detail = "-IncludeInactiveAgents did not deploy to the inactive host at $inactiveDestination. The switch is the documented escape hatch; if it does nothing, inactive hosts are unreachable rather than opt-in. Output: $($result.Output)" }
        }
        $activeDestination = Join-Path $fixture.Hosts['zz-inactive-active'] 'sample-skill\SKILL.md'
        if (-not (Test-Path -LiteralPath $activeDestination)) {
            return @{ Passed = $false; Detail = "-IncludeInactiveAgents deployed to the inactive host but not the active one at $activeDestination." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-InactiveHostFixture -Fixture $fixture
    }
}

# --- Behavior 4: a registry whose hosts are ALL inactive must fail naming
# that cause. Before the filter existed this could not arise; now it can, and
# the generic "empty work set" guard downstream would describe the symptom
# while hiding the reason. ---
function Test-AllInactiveRegistryFailsNamingTheCause {
    $fixture = New-InactiveHostFixture -CapabilityId 'zz-allinactive-cap' -HostDescriptors @(
        @{ Id = 'zz-allinactive-one'; Status = 'inactive' },
        @{ Id = 'zz-allinactive-two'; Status = 'inactive' }
    )
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "a registry with zero active hosts exited 0. Deploying nothing must never be reported as parity. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch 'no ACTIVE agents') {
            return @{ Passed = $false; Detail = "the run failed, but not with the specific all-inactive diagnostic -- a reader would get the generic empty-work-set message and have to rediscover the cause. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch 'IncludeInactiveAgents') {
            return @{ Passed = $false; Detail = "the all-inactive failure does not name -IncludeInactiveAgents, so it reports a problem without pointing at the remedy. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-InactiveHostFixture -Fixture $fixture
    }
}

# --- Behavior 5: the real registry keeps warp on the shared skills
# directory. docs.warp.dev/agent-platform/capabilities/skills documents a
# root scope that mirrors Warp's multi-tool project search and names
# ~/.agents/skills first; Warp additionally scans ~/.claude/skills,
# ~/.codex/skills and the rest, so it is the one host that already sees other
# hosts' skills. Losing this field silently restores 29 redundant copies
# under ~/.warp/skills, which is the kind of quiet regression no fixture test
# would notice. ---
function Test-RealRegistryKeepsWarpOnSharedSkillsDir {
    $agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw | ConvertFrom-Json
    $warp = @($agents.activeAgents) | Where-Object id -eq 'warp' | Select-Object -First 1
    if (-not $warp) {
        return @{ Passed = $false; Detail = "warp is not present in registry/agents.json activeAgents, so this assertion checked nothing." }
    }
    $shared = [string]$warp.nativePaths.sharedSkillsDir
    if ([string]::IsNullOrWhiteSpace($shared)) {
        return @{ Passed = $false; Detail = "warp no longer declares nativePaths.sharedSkillsDir. It would fall back to a private copy of every skill under ~/.warp/skills, duplicating skills Warp already reads from the other hosts' documented directories." }
    }
    if ($shared -notmatch '[\\/]\.agents[\\/]skills$') {
        return @{ Passed = $false; Detail = "warp's sharedSkillsDir is '$shared', which is not the documented ~/.agents/skills root scope." }
    }
    $codex = @($agents.activeAgents) | Where-Object id -eq 'codex' | Select-Object -First 1
    if ($codex -and [string]$codex.nativePaths.sharedSkillsDir -ne $shared) {
        return @{ Passed = $false; Detail = "warp's sharedSkillsDir '$shared' does not match codex's '$([string]$codex.nativePaths.sharedSkillsDir)'. They must resolve to the identical path to collapse to one deployment instead of two." }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-DefaultRunSkipsInactiveButDeploysActive
Report 'a default run skips hosts in inactiveAgents while still deploying to active hosts' $r1.Passed $r1.Detail

$r2 = Test-SwitchRestoresInactiveHosts
Report '-IncludeInactiveAgents restores deployment to inactive hosts' $r2.Passed $r2.Detail

$r3 = Test-AllInactiveRegistryFailsNamingTheCause
Report 'a registry with zero active hosts fails naming that cause and the remedy' $r3.Passed $r3.Detail

$r4 = Test-RealRegistryKeepsWarpOnSharedSkillsDir
Report 'the real registry keeps warp on the documented shared ~/.agents/skills directory' $r4.Passed $r4.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
