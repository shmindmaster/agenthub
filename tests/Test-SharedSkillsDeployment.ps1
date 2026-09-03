#Requires -Version 5.1
<#
Behavior tests for the task-7b "shared skills directory" feature in
scripts/Sync-Capabilities.ps1: several hosts declare nativePaths.sharedSkillsDir pointing at the same physical
directory (~/.agents/skills). Deploying a per-host copy AND a shared copy
duplicates every skill; the fix is to deploy once to the shared directory
and skip that host's own per-host copy when a host declares one.

The task-7 brief calls out the exact way this goes wrong: "the desired-state
map -- currently keyed by destination -- must collapse [multiple hosts
sharing one directory] to a single entry rather than having hosts overwrite
each other." A naive per-host key (e.g. "$hostId::$destination") would
defeat the existing $desired[$destination] collapsing and could make
-Prune misjudge a still-wanted shared file as stale.

Covers, per the brief's "Tests" section:
  1. Shared-dir collapse -- two hosts sharing one sharedSkillsDir produce
     ONE desired entry (one physical file), not two competing per-host
     copies, and neither host's own dedicated skillsDir receives a copy.
  2. A host with no sharedSkillsDir declared still gets its own copy in its
     own skillsDir (the reachability rule: hosts that do not share a
     directory must not lose their skill).
  3. -Prune never touches a path outside managed-skills.json even when that
     path is a sibling inside the now-shared, multi-tenant directory --
     the specific new risk this feature introduces (a "clean the whole
     shared directory" implementation would delete other hosts' or the
     user's own content living alongside AgentHub's managed skills).

Not a Pester suite: same self-checking accumulate-and-report idiom as
tests/Test-SyncCapabilities.ps1 (this repo carries no Pester dependency).
Each Test-* function returns @{ Passed; Detail }, Report() prints one
PASS/FAIL line, the runner exits 1 if anything failed.

SAFETY: every -Apply invocation below targets a synthetic -RepositoryRoot,
a synthetic -UserProfile, and a synthetic -LOCALAPPDATA runtime-state
directory, all under $env:AGENTHUB_TEST_SCRATCH. None ever targets the real
repository, the real user profile, or the real %LOCALAPPDATA%.

Run: pwsh -NoProfile -File tests/Test-SharedSkillsDeployment.ps1
     powershell.exe -NoProfile -File tests/Test-SharedSkillsDeployment.ps1
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

# Builds a fixture with one capability/one skill and an arbitrary set of
# hosts. Each host descriptor is @{ Id; SkillsDir; SharedSkillsDir } where
# SharedSkillsDir may be $null (no shared-dir declared for that host).
function New-SharedSkillsFixture {
    param(
        [Parameter(Mandatory)][string]$CapabilityId,
        [Parameter(Mandatory)][string]$SkillName,
        [Parameter(Mandatory)][string]$SkillContent,
        [Parameter(Mandatory)][object[]]$HostDescriptors
    )
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-repo-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-profile-" + [guid]::NewGuid())

    $activeAgents = @()
    $hostMappings = @()
    $effectiveHosts = @{}
    foreach ($descriptor in $HostDescriptors) {
        $nativePaths = @{ skillsDir = $descriptor.SkillsDir }
        if ($descriptor.ContainsKey('SharedSkillsDir') -and -not [string]::IsNullOrWhiteSpace($descriptor.SharedSkillsDir)) {
            $nativePaths.sharedSkillsDir = $descriptor.SharedSkillsDir
        }
        $activeAgents += @{ id = $descriptor.Id; name = "Fixture Host $($descriptor.Id)"; status = 'active'; nativePaths = $nativePaths }
        $hostMappings += @{ hostId = $descriptor.Id; deploymentStatus = 'managed' }
        $effectiveHosts[$descriptor.Id] = [pscustomobject]@{
            SkillsDir       = Get-EffectiveDestination -Path $descriptor.SkillsDir -UserProfile $userProfile
            SharedSkillsDir = if ($descriptor.SharedSkillsDir) { Get-EffectiveDestination -Path $descriptor.SharedSkillsDir -UserProfile $userProfile } else { $null }
        }
    }
    (@{ activeAgents = $activeAgents; inactiveAgents = @() } | ConvertTo-Json -Depth 10) |
        Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    Set-SharedSkillsFixtureCapabilities -RegistryDir $registryDir -CapabilityId $CapabilityId -HostIds @($HostDescriptors | ForEach-Object { $_.Id })

    $skillRoot = Join-Path $root "packages\$CapabilityId\skills\$SkillName"
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value $SkillContent -Encoding UTF8 -NoNewline

    return [pscustomobject]@{
        Root         = $root
        RegistryDir  = $registryDir
        SkillName    = $SkillName
        Hosts        = $effectiveHosts
        LocalAppData = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-lad-" + [guid]::NewGuid())
        UserProfile  = $userProfile
    }
}

function Set-SharedSkillsFixtureCapabilities {
    param([string]$RegistryDir, [string]$CapabilityId, [string[]]$HostIds, [switch]$DropAllHostMappings)
    $hostMappings = if ($DropAllHostMappings) { @() } else { @($HostIds | ForEach-Object { @{ hostId = $_; deploymentStatus = 'managed' } }) }
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

function Remove-SharedSkillsFixture {
    param($Fixture)
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.LocalAppData -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Fixture.UserProfile -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($hostEntry in $Fixture.Hosts.Values) {
        Remove-Item -LiteralPath $hostEntry.SkillsDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($hostEntry.SharedSkillsDir) { Remove-Item -LiteralPath $hostEntry.SharedSkillsDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# --- Behavior 1: two hosts that declare the SAME sharedSkillsDir collapse
# to exactly one physical deployment, and neither host's own dedicated
# skillsDir receives a redundant per-host copy. ---
function Test-SharedDirCollapsesToOneEntry {
    $sharedDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-shared-" + [guid]::NewGuid())
    $hostA = @{ Id = 'zz-shared-hosta'; SkillsDir = (Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-hosta-" + [guid]::NewGuid())); SharedSkillsDir = $sharedDir }
    $hostB = @{ Id = 'zz-shared-hostb'; SkillsDir = (Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-hostb-" + [guid]::NewGuid())); SharedSkillsDir = $sharedDir }
    $fixture = New-SharedSkillsFixture -CapabilityId 'zz-shared-cap' -SkillName 'sample-skill' -SkillContent 'canonical content v1' -HostDescriptors @($hostA, $hostB)
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply exit code was $($result.ExitCode). Output: $($result.Output)" }
        }

        $sharedDestination = Join-Path $fixture.Hosts['zz-shared-hosta'].SharedSkillsDir 'sample-skill'
        $sharedFile = Join-Path $sharedDestination 'SKILL.md'
        if (-not (Test-Path -LiteralPath $sharedFile)) {
            return @{ Passed = $false; Detail = "skill was not deployed to the shared directory $sharedFile. Output: $($result.Output)" }
        }

        $hostAOwnDestination = Join-Path $fixture.Hosts['zz-shared-hosta'].SkillsDir 'sample-skill'
        if (Test-Path -LiteralPath $hostAOwnDestination) {
            return @{ Passed = $false; Detail = "host A's own dedicated skillsDir received a redundant per-host copy at $hostAOwnDestination even though it declares sharedSkillsDir." }
        }
        $hostBOwnDestination = Join-Path $fixture.Hosts['zz-shared-hostb'].SkillsDir 'sample-skill'
        if (Test-Path -LiteralPath $hostBOwnDestination) {
            return @{ Passed = $false; Detail = "host B's own dedicated skillsDir received a redundant per-host copy at $hostBOwnDestination even though it declares sharedSkillsDir." }
        }

        # Runtime state is rebased under -UserProfile (not $env:LOCALAPPDATA)
        # whenever -UserProfile is overridden -- see Sync-Capabilities.ps1's
        # $runtimeRoot logic and Test-SyncCapabilities.ps1's equivalent
        # Test-UserProfileRebasesDestinations assertion.
        $statePath = Join-Path $fixture.UserProfile 'AppData\Local\AgentHub\sync\managed-skills.json'
        if (-not (Test-Path -LiteralPath $statePath)) {
            return @{ Passed = $false; Detail = "runtime state file was not written at $statePath." }
        }
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $managedCount = @($state.managed.PSObject.Properties).Count
        if ($managedCount -ne 1) {
            return @{ Passed = $false; Detail = "expected exactly 1 managed entry (one collapsed shared destination), got $managedCount. This is the exact 'hosts overwrite each other instead of collapsing to one entry' failure mode the brief warns about." }
        }

        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SharedSkillsFixture -Fixture $fixture
    }
}

# --- Behavior 2: a host that declares no sharedSkillsDir still gets its
# own dedicated copy -- the reachability rule. Consolidation must never
# make a skill invisible to a host that does not participate in sharing. ---
function Test-HostWithoutSharedDirStillGetsOwnCopy {
    $hostSolo = @{ Id = 'zz-solo-host'; SkillsDir = (Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-solo-" + [guid]::NewGuid())) }
    $fixture = New-SharedSkillsFixture -CapabilityId 'zz-solo-cap' -SkillName 'sample-skill' -SkillContent 'canonical content v1' -HostDescriptors @($hostSolo)
    try {
        $result = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($result.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply exit code was $($result.ExitCode). Output: $($result.Output)" }
        }
        $destination = Join-Path $fixture.Hosts['zz-solo-host'].SkillsDir 'sample-skill\SKILL.md'
        if (-not (Test-Path -LiteralPath $destination)) {
            return @{ Passed = $false; Detail = "a host with no sharedSkillsDir declared did not receive its own dedicated copy at $destination. A skill became unreachable for this host -- exactly the failure the reachability rule forbids. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SharedSkillsFixture -Fixture $fixture
    }
}

# --- Behavior 3: -Prune, operating inside a now-shared multi-tenant
# directory, never touches a sibling path that is not itself recorded in
# managed-skills.json -- even after pruning the managed skill that used to
# live right next to it. A "clean the whole shared directory" prune
# implementation would fail this. ---
function Test-PruneNeverTouchesUnmanagedPathInSharedDir {
    $sharedDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-pruneshared-" + [guid]::NewGuid())
    $hostA = @{ Id = 'zz-pruneshared-hosta'; SkillsDir = (Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-pha-" + [guid]::NewGuid())); SharedSkillsDir = $sharedDir }
    $hostB = @{ Id = 'zz-pruneshared-hostb'; SkillsDir = (Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sharedskills-phb-" + [guid]::NewGuid())); SharedSkillsDir = $sharedDir }
    $fixture = New-SharedSkillsFixture -CapabilityId 'zz-pruneshared-cap' -SkillName 'sample-skill' -SkillContent 'canonical content v1' -HostDescriptors @($hostA, $hostB)
    try {
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "first -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        $effectiveSharedDir = $fixture.Hosts['zz-pruneshared-hosta'].SharedSkillsDir
        $managedSkillDestination = Join-Path $effectiveSharedDir 'sample-skill'
        if (-not (Test-Path -LiteralPath (Join-Path $managedSkillDestination 'SKILL.md'))) {
            return @{ Passed = $false; Detail = "first -Apply did not deploy the fixture skill to the shared directory -- test setup invalid. Output: $($first.Output)" }
        }

        # An alien, never-managed sibling directly inside the same shared
        # directory -- simulates a user-authored skill or another process's
        # content living alongside AgentHub's managed deployment.
        $alienDestination = Join-Path $effectiveSharedDir 'alien-skill'
        New-Item -ItemType Directory -Path $alienDestination -Force | Out-Null
        $alienFile = Join-Path $alienDestination 'NOTES.md'
        Set-Content -LiteralPath $alienFile -Value 'not deployed by AgentHub, must survive prune' -Encoding UTF8 -NoNewline

        # Withdraw both host mappings so the managed shared skill becomes a
        # genuine prune candidate.
        Set-SharedSkillsFixtureCapabilities -RegistryDir $fixture.RegistryDir -CapabilityId 'zz-pruneshared-cap' -HostIds @('zz-pruneshared-hosta', 'zz-pruneshared-hostb') -DropAllHostMappings

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-Prune', '-RepositoryRoot', $fixture.Root, '-UserProfile', $fixture.UserProfile) -LocalAppData $fixture.LocalAppData
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "-Apply -Prune exit code was $($second.ExitCode) pruning an unmodified stale shared skill. Output: $($second.Output)" }
        }
        if (Test-Path -LiteralPath $managedSkillDestination) {
            return @{ Passed = $false; Detail = "the stale managed shared skill was NOT pruned -- test did not exercise pruning at all. Output: $($second.Output)" }
        }
        if (-not (Test-Path -LiteralPath $alienFile)) {
            return @{ Passed = $false; Detail = "the alien, never-managed sibling inside the shared directory was deleted by -Prune. This is the exact regression this test exists to prevent: a shared directory is multi-tenant, and prune must only ever touch paths recorded in managed-skills.json." }
        }
        $alienStillThere = [IO.File]::ReadAllText($alienFile)
        if ($alienStillThere -ne 'not deployed by AgentHub, must survive prune') {
            return @{ Passed = $false; Detail = "the alien sibling's content changed unexpectedly. Content: $alienStillThere" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-SharedSkillsFixture -Fixture $fixture
    }
}

$r1 = Test-SharedDirCollapsesToOneEntry
Report 'two hosts sharing one sharedSkillsDir collapse to a single deployed entry, with no redundant per-host copies' $r1.Passed $r1.Detail

$r2 = Test-HostWithoutSharedDirStillGetsOwnCopy
Report 'a host with no sharedSkillsDir declared still gets its own dedicated per-host copy' $r2.Passed $r2.Detail

$r3 = Test-PruneNeverTouchesUnmanagedPathInSharedDir
Report '-Prune never touches an unmanaged sibling path inside a now-shared, multi-tenant directory' $r3.Passed $r3.Detail

# --- live end-state check, added 2026-08-20 -------------------------------
# The three fixture tests above prove the COLLAPSE works. They cannot see the
# residue it leaves behind: when a host that already had its own per-host copy
# later gains a sharedSkillsDir, sync starts writing only to the shared
# directory and the host's original copy is stranded. Sync can never reach it
# again -- it is not a desired destination, and prune only removes paths the
# ledger still tracks -- so it sits there at whatever version it was, forever.
#
# Found live: adopting use-railway converged 9 copies on 1.3.7 and left 1.3.6
# shadows in ~/.codex/skills and ~/.gemini/skills. That is not cosmetic --
# gemini documents ~/.gemini/skills and the ~/.agents/skills alias at the SAME
# precedence tier, so two copies of one skill name at two versions is a genuine
# ambiguity about which one the host loads.
$caps   = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$managedNames = @{}
foreach ($c in @($caps.capabilities)) {
    foreach ($n in @($c.managedSkillNames)) { if ($n) { $managedNames[[string]$n] = [string]$c.id } }
}

function Expand-HomePath([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    # Not a regex-escaped -replace: escaping a REPLACEMENT operand leaves the
    # doubled backslashes in the result.
    $x = if ($Raw.StartsWith('~')) { $env:USERPROFILE + $Raw.Substring(1) } else { $Raw }
    # Assign before the call. Inside method parentheses the comma of -replace's
    # second operand is parsed as an argument separator, so the inline form dies
    # with "cannot find an overload ... argument count: 2".
    $x = $x -replace '/', '\'
    return [Environment]::ExpandEnvironmentVariables($x)
}

function Get-PhysicalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $item = Get-Item -LiteralPath $Path -Force
    $target = @($item.Target)[0]
    if ([string]::IsNullOrWhiteSpace($target)) { return $item.FullName }
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $item.PSParentPath $target
    }
    return [IO.Path]::GetFullPath($target)
}

$shadowed = [Collections.Generic.List[string]]::new()
$sharedHosts = 0
foreach ($a in @($agents.activeAgents)) {
    $shared = Expand-HomePath ([string]$a.nativePaths.sharedSkillsDir)
    $own    = Expand-HomePath ([string]$a.nativePaths.skillsDir)
    if (-not $shared -or -not $own) { continue }
    if ($shared -eq $own) { continue }
    # A junction from the host path onto the master library is reachability,
    # not a stale shadow copy.
    if ((Get-PhysicalPath $own) -eq (Get-PhysicalPath $shared)) { continue }
    $sharedHosts++
    if (-not (Test-Path -LiteralPath $own)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $own -Directory -ErrorAction SilentlyContinue)) {
        if ($managedNames.ContainsKey($d.Name)) {
            $shadowed.Add("$($a.id): $($d.FullName) shadows the managed copy in $shared (owner: $($managedNames[$d.Name]))")
        }
    }
}

# Without this the check passes vacuously the moment sharedSkillsDir is renamed
# or no host declares one.
Report 'at least one host declares a sharedSkillsDir distinct from its own skillsDir' ($sharedHosts -gt 0) `
    'No host resolved to a shared-vs-own directory pair, so the shadow-copy check below examined nothing.'

Report 'no managed skill is shadowed by a stale copy in a shared-dir host own skillsDir' ($shadowed.Count -eq 0) `
    "sync writes only to the shared directory for these hosts, so these copies are unreachable and frozen at whatever version they hold: $($shadowed -join '; ')"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
