#Requires -Version 5.1
<#
Behavior tests for scripts/Sync-Capabilities.ps1 (task-6b coverage-gap
priority 3): this script has NO test at all today and performs
Remove-Item -Recurse -Force on deployment destinations. Covers the
refuse-to-replace-unowned-skill path, the refuse-to-replace-user-modified
path, prune refusing a modified managed skill (plus a positive companion:
prune DOES remove an unmodified stale managed skill), and idempotency.
These guards already exist in scripts/Sync-Capabilities.ps1; nothing
verified them before this file.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this file
follows). Same self-checking idiom: each Test-* function returns a result,
the runner prints one PASS/FAIL line per behavior, accumulates failures,
and exits 1 if any behavior did not hold, 0 otherwise.

SAFETY NOTE (discovered while building this file, reported not fixed --
see task-6 report): scripts/Sync-Capabilities.ps1 declares a -UserProfile
parameter but never references it anywhere in its body. Its runtime state
file (managed-skills.json, which -Apply reads AND writes, and whose guard
logic this file exists to test) is instead always resolved from
$env:LOCALAPPDATA directly. A caller who passes -UserProfile <synthetic>
expecting isolation, the way every other Sync-*.ps1 script in this repo
supports, would still read/write the REAL, LIVE managed-skills.json state
for the invoking user. To keep every -Apply invocation below fully
isolated from the real machine regardless of this defect, Invoke-
SyncCapabilities below ALSO overrides the child process's LOCALAPPDATA
environment variable to a synthetic scratch path for the duration of the
call (restored immediately after). This is a workaround for a real,
separately-reported bug, not evidence that -UserProfile works correctly
here.

Every -Apply invocation below targets a synthetic -RepositoryRoot with a
synthetic-agent skillsDir AND a synthetic-LOCALAPPDATA runtime-state
directory, both under $env:AGENTHUB_TEST_SCRATCH. None ever targets the
real repository, the real user profile, or the real %LOCALAPPDATA%.

Run: pwsh -NoProfile -File tests/Test-SyncCapabilities.ps1
     powershell.exe -NoProfile -File tests/Test-SyncCapabilities.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'scripts\Sync-Capabilities.ps1'
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

# One capability, one host, one skill -- the minimal fixture shape
# Sync-Capabilities.ps1 needs: registry/agents.json with an active agent
# whose nativePaths.skillsDir is a synthetic scratch destination (fully
# controlled here, never a real host path), and registry/capabilities.json
# with one capability whose canonicalSource resolves to a real skills/
# directory under the fixture root.
function New-SyncCapabilitiesFixture {
    param(
        [Parameter(Mandatory)][string]$CapabilityId,
        [Parameter(Mandatory)][string]$HostId,
        [Parameter(Mandatory)][string]$SkillName,
        [Parameter(Mandatory)][string]$SkillContent
    )
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-repo-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    $skillsDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-dest-" + [guid]::NewGuid())

    $agents = @{
        activeAgents = @(
            @{ id = $HostId; name = 'Fixture Host'; status = 'active'; nativePaths = @{ skillsDir = $skillsDir } }
        )
        inactiveAgents = @()
    }
    ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    Set-SyncCapabilitiesFixtureCapabilities -RegistryDir $registryDir -CapabilityId $CapabilityId -HostId $HostId

    $skillRoot = Join-Path $root "packages\$CapabilityId\skills\$SkillName"
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value $SkillContent -Encoding UTF8 -NoNewline

    return [pscustomobject]@{
        Root         = $root
        SkillsDir    = $skillsDir
        Destination  = Join-Path $skillsDir $SkillName
        LocalAppData = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-lad-" + [guid]::NewGuid())
        UserProfile  = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-profile-" + [guid]::NewGuid())
        RegistryDir  = $registryDir
    }
}

function Set-SyncCapabilitiesFixtureCapabilities {
    param([string]$RegistryDir, [string]$CapabilityId, [string]$HostId, [switch]$DropHostMapping)
    $hostMappings = if ($DropHostMapping) { @() } else { @(@{ hostId = $HostId; deploymentStatus = 'managed' }) }
    $capabilities = @{
        schemaVersion = 2
        capabilities = @(
            @{
                id = $CapabilityId
                owner = 'test'
                capabilityType = 'skill-pack'
                canonicalSource = "packages/$CapabilityId"
                hostMappings = $hostMappings
            }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $RegistryDir 'capabilities.json') -Encoding UTF8 -NoNewline
}

function Remove-SyncCapabilitiesFixture {
    param($Fixture)
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.SkillsDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.LocalAppData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.UserProfile -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Behavior 1: a destination that already exists, and is NOT recorded as
# managed in the (fresh, empty) runtime state, is refused -- never
# overwritten -- and the run exits non-zero. ---
function Test-RefusesToReplaceUnownedSkill {
    $fixture = New-SyncCapabilitiesFixture -CapabilityId 'zz-unowned-cap' -HostId 'zz-unowned-host' -SkillName 'sample-skill' -SkillContent 'canonical content v1'
    try {
        New-Item -ItemType Directory -Path $fixture.Destination -Force | Out-Null
        $unrelatedFile = Join-Path $fixture.Destination 'unrelated.txt'
        Set-Content -LiteralPath $unrelatedFile -Value 'pre-existing content, not deployed by AgentHub' -Encoding UTF8 -NoNewline

        $result = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) with an unowned pre-existing destination present. Output: $($result.Output)" }
        }
        if ($result.Output -notmatch [regex]::Escape('refusing to replace unowned skill')) {
            return @{ Passed = $false; Detail = "expected 'refusing to replace unowned skill' in the output. Output: $($result.Output)" }
        }
        if (-not (Test-Path -LiteralPath $unrelatedFile)) {
            return @{ Passed = $false; Detail = "the unowned destination was replaced -- this is the exact defect the guard exists to prevent." }
        }
        $stillThere = [IO.File]::ReadAllText($unrelatedFile)
        if ($stillThere -ne 'pre-existing content, not deployed by AgentHub') {
            return @{ Passed = $false; Detail = "the unowned destination's content changed. Content: $stillThere" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SyncCapabilitiesFixture -Fixture $fixture
    }
}

# --- Behavior 2: a destination that WAS deployed by this script (recorded
# in managed-skills.json), then hand-modified afterward, is refused on the
# next -Apply -- never silently overwritten -- and the run exits non-zero. ---
function Test-RefusesToReplaceUserModifiedManagedSkill {
    $fixture = New-SyncCapabilitiesFixture -CapabilityId 'zz-usermod-cap' -HostId 'zz-usermod-host' -SkillName 'sample-skill' -SkillContent 'canonical content v1'
    try {
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        $skillFile = Join-Path $fixture.Destination 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile)) {
            return @{ Passed = $false; Detail = "first -Apply did not deploy the fixture skill -- test setup invalid. Output: $($first.Output)" }
        }

        [IO.File]::WriteAllText($skillFile, 'hand-edited by the user after deployment', [Text.UTF8Encoding]::new($false))

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($second.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "second -Apply exit code was 0 (reported success) with a hand-modified managed skill present. Output: $($second.Output)" }
        }
        if ($second.Output -notmatch [regex]::Escape('refusing to replace user-modified managed skill')) {
            return @{ Passed = $false; Detail = "expected 'refusing to replace user-modified managed skill' in the output. Output: $($second.Output)" }
        }
        $stillThere = [IO.File]::ReadAllText($skillFile)
        if ($stillThere -ne 'hand-edited by the user after deployment') {
            return @{ Passed = $false; Detail = "the hand-edited managed destination was overwritten -- this is the exact defect the guard exists to prevent. Content: $stillThere" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SyncCapabilitiesFixture -Fixture $fixture
    }
}

# --- Behavior 3: -Prune refuses to remove a managed destination that was
# hand-modified after deployment, even though the capability/hostMapping
# that used to own it has since been withdrawn (making it a prune
# candidate). Never silently deletes user-modified content. ---
function Test-PruneRefusesModifiedManagedSkill {
    $fixture = New-SyncCapabilitiesFixture -CapabilityId 'zz-prunemod-cap' -HostId 'zz-prunemod-host' -SkillName 'sample-skill' -SkillContent 'canonical content v1'
    try {
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        $skillFile = Join-Path $fixture.Destination 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile)) {
            return @{ Passed = $false; Detail = "first -Apply did not deploy the fixture skill -- test setup invalid. Output: $($first.Output)" }
        }

        [IO.File]::WriteAllText($skillFile, 'hand-edited before the mapping was withdrawn', [Text.UTF8Encoding]::new($false))
        Set-SyncCapabilitiesFixtureCapabilities -RegistryDir $fixture.RegistryDir -CapabilityId 'zz-prunemod-cap' -HostId 'zz-prunemod-host' -DropHostMapping

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-Prune', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($second.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) while pruning a hand-modified managed skill. Output: $($second.Output)" }
        }
        if ($second.Output -notmatch [regex]::Escape('refusing to prune modified managed skill')) {
            return @{ Passed = $false; Detail = "expected 'refusing to prune modified managed skill' in the output. Output: $($second.Output)" }
        }
        if (-not (Test-Path -LiteralPath $skillFile)) {
            return @{ Passed = $false; Detail = "the hand-modified managed destination was pruned anyway -- this is the exact defect the guard exists to prevent." }
        }
        $stillThere = [IO.File]::ReadAllText($skillFile)
        if ($stillThere -ne 'hand-edited before the mapping was withdrawn') {
            return @{ Passed = $false; Detail = "destination content changed unexpectedly. Content: $stillThere" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SyncCapabilitiesFixture -Fixture $fixture
    }
}

# --- Behavior 4 (regression guard companion to Behavior 3): -Prune DOES
# remove an UNMODIFIED stale managed skill once its owning capability/
# hostMapping is withdrawn -- proves the guard in Behavior 3 is a targeted
# hash check, not a blanket refusal to ever prune anything. ---
function Test-PruneRemovesUnmodifiedStaleManagedSkill {
    $fixture = New-SyncCapabilitiesFixture -CapabilityId 'zz-prunestale-cap' -HostId 'zz-prunestale-host' -SkillName 'sample-skill' -SkillContent 'canonical content v1'
    try {
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        if (-not (Test-Path -LiteralPath $fixture.Destination)) {
            return @{ Passed = $false; Detail = "first -Apply did not deploy the fixture skill -- test setup invalid. Output: $($first.Output)" }
        }

        Set-SyncCapabilitiesFixtureCapabilities -RegistryDir $fixture.RegistryDir -CapabilityId 'zz-prunestale-cap' -HostId 'zz-prunestale-host' -DropHostMapping

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-Prune', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply -Prune exit code was $($second.ExitCode) pruning an unmodified stale managed skill. Output: $($second.Output)" }
        }
        if (Test-Path -LiteralPath $fixture.Destination) {
            return @{ Passed = $false; Detail = "the unmodified stale managed skill was NOT pruned. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SyncCapabilitiesFixture -Fixture $fixture
    }
}

# --- Behavior 5: idempotency. Two consecutive -Apply runs against the same
# fresh fixture; the second makes no further changes to the deployed file
# (byte-identical) and the summary reports the skill as 'current', not
# 'missing' or 'drift'. ---
function Test-SecondApplyIsIdempotent {
    $fixture = New-SyncCapabilitiesFixture -CapabilityId 'zz-idempotent-cap' -HostId 'zz-idempotent-host' -SkillName 'sample-skill' -SkillContent 'canonical content v1'
    try {
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        $skillFile = Join-Path $fixture.Destination 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile)) {
            return @{ Passed = $false; Detail = "first -Apply did not deploy the fixture skill -- test setup invalid. Output: $($first.Output)" }
        }
        $bytesAfterFirst = [IO.File]::ReadAllBytes($skillFile)

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "second -Apply exit code was $($second.ExitCode). Output: $($second.Output)" }
        }
        $bytesAfterSecond = [IO.File]::ReadAllBytes($skillFile)
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$bytesAfterFirst, [byte[]]$bytesAfterSecond)) {
            return @{ Passed = $false; Detail = 'the deployed skill file changed bytes on a second, no-op -Apply run.' }
        }
        if ($second.Output -notmatch 'current=1') {
            return @{ Passed = $false; Detail = "expected the second -Apply's summary to report current=1. Output: $($second.Output)" }
        }
        if ($second.Output -match 'missing=|drift=') {
            return @{ Passed = $false; Detail = "second -Apply's summary unexpectedly reports missing/drift entries. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SyncCapabilitiesFixture -Fixture $fixture
    }
}

# --- Behavior 6 (DISCOVERED BUG, reported not fixed -- see task-6 report):
# a registry with zero capabilities and zero agents ("empty work set") is
# expected to fail loudly per this project's global constraint ("never
# print success on an empty work set" -- see AGENTS.md-adjacent policy and
# task-6-brief.md coverage-gap priority 2). scripts/Sync-Capabilities.ps1
# instead prints "PASS: capability parity 0 host mappings checked..." and
# exits 0. This assertion encodes the CORRECT, required contract and is
# therefore expected to FAIL against the current script -- it is left in
# the suite, failing, as the honest record of a real defect this task was
# asked to find and report, not fix (out of scope: only tests/ and the
# nine CRLF regex fixes in their three named files may change). ---
function Test-EmptyWorkSetFailsLoudly {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-empty-root-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    (@{ activeAgents = @(); inactiveAgents = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline
    (@{ schemaVersion = 2; capabilities = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline
    $localAppData = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-empty-lad-" + [guid]::NewGuid())
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-synccaps-empty-profile-" + [guid]::NewGuid())
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-Audit', '-RepositoryRoot', $root, '-UserProfile', $userProfile) -LocalAppData $localAppData
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "KNOWN BUG (reported, not fixed): exit code was 0 (reported success) against a registry with zero capabilities and zero agents. Output: $($result.Output)" }
        }
        if ($result.Output -match 'PASS: capability parity') {
            return @{ Passed = $false; Detail = "KNOWN BUG (reported, not fixed): script printed its PASS success line against an empty work set. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $localAppData -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-RefusesToReplaceUnownedSkill
Report 'refuses to replace an unowned pre-existing skill destination and exits non-zero' $r1.Passed $r1.Detail

$r2 = Test-RefusesToReplaceUserModifiedManagedSkill
Report 'refuses to replace a managed skill that was hand-modified after deployment and exits non-zero' $r2.Passed $r2.Detail

$r3 = Test-PruneRefusesModifiedManagedSkill
Report '-Prune refuses to remove a hand-modified managed skill and exits non-zero' $r3.Passed $r3.Detail

$r4 = Test-PruneRemovesUnmodifiedStaleManagedSkill
Report '-Prune removes an unmodified stale managed skill once its mapping is withdrawn' $r4.Passed $r4.Detail

$r5 = Test-SecondApplyIsIdempotent
Report 'second consecutive -Apply against the same fixture makes no further byte changes and reports current' $r5.Passed $r5.Detail

$r6 = Test-EmptyWorkSetFailsLoudly
Report 'zero capabilities and zero agents fails loudly instead of reporting success (KNOWN BUG, see task-6 report)' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $(6 - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: 6 passed, 0 failed' -ForegroundColor Green
exit 0
