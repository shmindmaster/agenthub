#Requires -Version 5.1
<#
What this repository puts on an agent host -- rendered or copied -- and the
verdict it reports about what is already there must not depend on the line
endings of the checkout it ran from.

This was a live defect, twice, by two different mechanisms.

RENDERED FILES (Sync-Subagents.ps1, Sync-Instructions.ps1). The subagent and
instruction files were deployed from a CRLF worktree (core.autocrlf=true), so
the deployed bytes embedded CRLF. The same commit rendered from the LF main
checkout then reported drift on 48 of 72 subagent files and 14 of 14
instruction files, while each checkout reported itself clean. The fix
normalizes source content to LF before rendering.

COPIED FILES (Sync-Capabilities.ps1). Skills are not rendered, they are copied
verbatim by Copy-Item, so the deployed bytes carry whatever the deploying
checkout had. Get-TreeHash then compared those bytes with a raw Get-FileHash.
One checkout reported current=370, drift=0; a second checkout at the identical
commit reported current=6, drift=364. The fix reuses
RegistryContentHash.ps1's Get-AgentHubStableFileHash, which normalizes text
files to LF before hashing. The copy stays verbatim on purpose -- the hash's
job is to answer "is this the same content", not "are these the same bytes",
and a per-file text/binary transform on the write path would be a far larger
blast radius than the bug.

Identical content, opposite verdicts, decided by git config -- the exact defect
class this repository's test suite exists to eliminate. This file proves both
fixes the same way: build two byte-different fixture trees whose only
difference is line endings, and require them to agree.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom.

Every -Apply below targets a synthetic -RepositoryRoot/-UserProfile pair under
$env:AGENTHUB_TEST_SCRATCH, and every Sync-Capabilities invocation additionally
overrides the child process's LOCALAPPDATA (see tests/Test-SyncCapabilities.ps1
for why that belt-and-braces matters). None ever targets the real registry,
the real profile, or the real %LOCALAPPDATA%.

Run: pwsh -NoProfile -File tests/Test-RenderLineEndingIndependence.ps1
     powershell.exe -NoProfile -File tests/Test-RenderLineEndingIndependence.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncSubagents = Join-Path $repoRoot 'scripts\Sync-Subagents.ps1'
$syncCapabilities = Join-Path $repoRoot 'scripts\Sync-Capabilities.ps1'
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

$agentMarkdown = @(
    '---'
    'name: fixture-reviewer'
    'description: A fixture subagent used only by this test.'
    'tools: Read, Grep, Glob'
    'readonly: true'
    '---'
    ''
    '# Fixture Reviewer'
    ''
    'First body line.'
    'Second body line.'
    ''
) -join "`n"

# One fixture repository, written with the requested line endings. Everything
# else -- ids, order, content -- is identical between the two.
function New-LineEndingFixture {
    param([Parameter(Mandatory)][ValidateSet('LF', 'CRLF')][string]$LineEnding)
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-eol-$LineEnding-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    $agentsDir = Join-Path $root 'packages\zz-eol-cap\agents'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

    $body = if ($LineEnding -eq 'CRLF') { $agentMarkdown.Replace("`n", "`r`n") } else { $agentMarkdown }
    [IO.File]::WriteAllText((Join-Path $agentsDir 'fixture-reviewer.agent.md'), $body, [Text.UTF8Encoding]::new($false))

    $manifestDir = Join-Path $root 'packages\zz-eol-cap\.codex-plugin'
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $manifestDir 'plugin.json') -Value '{ "name": "zz-eol-cap", "version": "1.0.0" }' -Encoding UTF8 -NoNewline

    $capabilities = @{
        schemaVersion = 2
        capabilities  = @(
            @{ id = 'zz-eol-cap'; owner = 'test'; capabilityType = 'skill-pack'; canonicalSource = 'packages/zz-eol-cap'; hostMappings = @() }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    # Reuse the real subagent-formats contract rather than inventing one, so
    # this test exercises the shipped rendering rules.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'registry\subagent-formats.json') -Destination (Join-Path $registryDir 'subagent-formats.json')

    $profile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-eol-$LineEnding-profile-" + [guid]::NewGuid())
    # Sync-Subagents skips a host whose root config directory is absent, so
    # create the one host root this fixture renders for.
    New-Item -ItemType Directory -Path (Join-Path $profile '.codex') -Force | Out-Null
    return [pscustomobject]@{ Root = $root; Profile = $profile }
}

function Invoke-SyncSubagents {
    param([Parameter(Mandatory)]$Fixture)
    $allArgs = @('-NoProfile', '-File', $syncSubagents, '-Apply', '-RepositoryRoot', $Fixture.Root, '-UserProfile', $Fixture.Profile)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-RenderedFileMap {
    param([Parameter(Mandatory)][string]$Profile)
    $map = @{}
    $agentsRoot = Join-Path $Profile '.codex\agents'
    if (-not (Test-Path -LiteralPath $agentsRoot)) { return $map }
    foreach ($file in @(Get-ChildItem -LiteralPath $agentsRoot -File -Recurse)) {
        $map[$file.Name] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    }
    return $map
}

# --- Behavior 1: rendering the same logical agent from an LF tree and from a
# CRLF tree must produce byte-identical host files. ---
function Test-RenderIsLineEndingIndependent {
    $lf = New-LineEndingFixture -LineEnding 'LF'
    $crlf = New-LineEndingFixture -LineEnding 'CRLF'
    try {
        $lfSourceBytes = [IO.File]::ReadAllBytes((Join-Path $lf.Root 'packages\zz-eol-cap\agents\fixture-reviewer.agent.md'))
        $crlfSourceBytes = [IO.File]::ReadAllBytes((Join-Path $crlf.Root 'packages\zz-eol-cap\agents\fixture-reviewer.agent.md'))
        if ([Convert]::ToBase64String($lfSourceBytes) -eq [Convert]::ToBase64String($crlfSourceBytes)) {
            return @{ Passed = $false; Detail = 'the two fixture sources are byte-identical, so this assertion would pass trivially and prove nothing.' }
        }

        $lfResult = Invoke-SyncSubagents -Fixture $lf
        if ($lfResult.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "LF fixture -Apply exit code was $($lfResult.ExitCode). Output: $($lfResult.Output)" }
        }
        $crlfResult = Invoke-SyncSubagents -Fixture $crlf
        if ($crlfResult.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "CRLF fixture -Apply exit code was $($crlfResult.ExitCode). Output: $($crlfResult.Output)" }
        }

        $lfFiles = Get-RenderedFileMap -Profile $lf.Profile
        $crlfFiles = Get-RenderedFileMap -Profile $crlf.Profile
        if ($lfFiles.Count -eq 0) {
            return @{ Passed = $false; Detail = "the LF fixture rendered zero files, so this assertion checked nothing. Output: $($lfResult.Output)" }
        }
        if ($lfFiles.Count -ne $crlfFiles.Count) {
            return @{ Passed = $false; Detail = "LF rendered $($lfFiles.Count) file(s), CRLF rendered $($crlfFiles.Count)." }
        }
        foreach ($name in $lfFiles.Keys) {
            if (-not $crlfFiles.ContainsKey($name)) {
                return @{ Passed = $false; Detail = "CRLF fixture did not render '$name'." }
            }
            if ($lfFiles[$name] -ne $crlfFiles[$name]) {
                return @{ Passed = $false; Detail = "'$name' differs between an LF and a CRLF checkout of identical content -- the rendered output depends on git's core.autocrlf." }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        foreach ($fixture in @($lf, $crlf)) {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fixture.Profile -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Sync-Capabilities.ps1: skills are COPIED, not rendered. The two fixtures
# below deliberately share one skillsDir, one -UserProfile and one synthetic
# LOCALAPPDATA, because that is the real-world shape of the defect: two
# checkouts of the same commit, on one machine, deploying to and auditing the
# same destination against the same runtime state.
# ---------------------------------------------------------------------------
$skillMarkdown = @(
    '---'
    'name: fixture-eol-skill'
    'description: A fixture skill used only by this test.'
    '---'
    ''
    '# Fixture Skill'
    ''
    'First body line.'
    'Second body line.'
    ''
) -join "`n"

# Mirrors the -UserProfile rebasing in scripts/Sync-Capabilities.ps1. The
# fixture's skillsDir lives under $env:TEMP, which on Windows is itself under
# the real profile, so the script legitimately rebases it. The fixture has to
# resolve destinations the same way or it asserts against a path nothing was
# ever written to. Same helper as tests/Test-SyncCapabilities.ps1.
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

# One capability, one host, one skill, written with the requested line endings.
# Everything else -- ids, order, content, and critically the declared skillsDir
# -- is identical between the two fixtures.
function New-CapabilityLineEndingFixture {
    param(
        [Parameter(Mandatory)][ValidateSet('LF', 'CRLF')][string]$LineEnding,
        [Parameter(Mandatory)][string]$SkillsDir
    )
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-capeol-$LineEnding-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null

    $agents = @{
        activeAgents   = @(
            @{ id = 'zz-capeol-host'; name = 'Fixture Host'; status = 'active'; nativePaths = @{ skillsDir = $SkillsDir } }
        )
        inactiveAgents = @()
    }
    ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

    $capabilities = @{
        schemaVersion = 2
        capabilities  = @(
            @{
                id              = 'zz-capeol-cap'
                owner           = 'test'
                capabilityType  = 'skill-pack'
                canonicalSource = 'packages/zz-capeol-cap'
                hostMappings    = @(@{ hostId = 'zz-capeol-host'; deploymentStatus = 'managed' })
            }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    $skillRoot = Join-Path $root 'packages\zz-capeol-cap\skills\fixture-eol-skill'
    New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
    $body = if ($LineEnding -eq 'CRLF') { $skillMarkdown.Replace("`n", "`r`n") } else { $skillMarkdown }
    [IO.File]::WriteAllText((Join-Path $skillRoot 'SKILL.md'), $body, [Text.UTF8Encoding]::new($false))
    return $root
}

function Invoke-SyncCapabilities {
    param([Parameter(Mandatory)][string[]]$ExtraArgs, [Parameter(Mandatory)][string]$LocalAppData)
    $allArgs = @('-NoProfile', '-File', $syncCapabilities) + $ExtraArgs
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

# Builds the shared-destination pair and runs $Body against it. $Body receives
# a context object and returns the usual @{ Passed; Detail } result.
function Use-SharedCapabilityFixturePair {
    param([Parameter(Mandatory)][scriptblock]$Body)
    $skillsDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-capeol-dest-" + [guid]::NewGuid())
    $userProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-capeol-profile-" + [guid]::NewGuid())
    $localAppData = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-capeol-lad-" + [guid]::NewGuid())
    $roots = @{
        LF   = New-CapabilityLineEndingFixture -LineEnding 'LF' -SkillsDir $skillsDir
        CRLF = New-CapabilityLineEndingFixture -LineEnding 'CRLF' -SkillsDir $skillsDir
    }
    $context = [pscustomobject]@{
        Roots        = $roots
        UserProfile  = $userProfile
        LocalAppData = $localAppData
        SkillsDir    = Get-EffectiveDestination -Path $skillsDir -UserProfile $userProfile
        SkillFile    = Join-Path (Get-EffectiveDestination -Path (Join-Path $skillsDir 'fixture-eol-skill') -UserProfile $userProfile) 'SKILL.md'
    }
    try {
        # Anti-vacuous guard: if the two fixture sources are byte-identical
        # every assertion below would hold trivially and prove nothing.
        $lfBytes = [IO.File]::ReadAllBytes((Join-Path $roots.LF 'packages\zz-capeol-cap\skills\fixture-eol-skill\SKILL.md'))
        $crlfBytes = [IO.File]::ReadAllBytes((Join-Path $roots.CRLF 'packages\zz-capeol-cap\skills\fixture-eol-skill\SKILL.md'))
        if ([Convert]::ToBase64String($lfBytes) -eq [Convert]::ToBase64String($crlfBytes)) {
            return @{ Passed = $false; Detail = 'the two fixture sources are byte-identical, so this assertion would pass trivially and prove nothing.' }
        }
        return & $Body $context
    } finally {
        foreach ($path in @($roots.LF, $roots.CRLF, $skillsDir, $userProfile, $localAppData, $context.SkillsDir)) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Behavior 2: deploy from one checkout, audit from the other. The audit
# must report the destination as current. Before the fix it reported drift,
# which is how one machine came to hold 364 "drifted" skills that nothing had
# touched. ---
function Test-CapabilityAuditIsLineEndingIndependent {
    param([Parameter(Mandatory)][ValidateSet('LF', 'CRLF')][string]$DeployFrom)
    $auditFrom = if ($DeployFrom -eq 'LF') { 'CRLF' } else { 'LF' }
    Use-SharedCapabilityFixturePair -Body {
        param($ctx)
        $apply = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $ctx.Roots[$DeployFrom], '-UserProfile', $ctx.UserProfile) -LocalAppData $ctx.LocalAppData
        if ($apply.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "$DeployFrom -Apply exit code was $($apply.ExitCode) -- test setup invalid. Output: $($apply.Output)" }
        }
        if (-not (Test-Path -LiteralPath $ctx.SkillFile)) {
            return @{ Passed = $false; Detail = "$DeployFrom -Apply did not deploy the fixture skill to $($ctx.SkillFile) -- test setup invalid. Output: $($apply.Output)" }
        }

        $audit = Invoke-SyncCapabilities -ExtraArgs @('-Audit', '-RepositoryRoot', $ctx.Roots[$auditFrom], '-UserProfile', $ctx.UserProfile) -LocalAppData $ctx.LocalAppData
        if ($audit.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "$auditFrom -Audit exit code was $($audit.ExitCode). Output: $($audit.Output)" }
        }
        if ($audit.Output -match 'drift=') {
            return @{ Passed = $false; Detail = "the $auditFrom checkout reported drift against a destination the $DeployFrom checkout had just deployed from identical content -- the verdict depends on git's core.autocrlf. Output: $($audit.Output)" }
        }
        if ($audit.Output -notmatch 'current=1') {
            return @{ Passed = $false; Detail = "expected the $auditFrom checkout's audit to report current=1. Output: $($audit.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    }
}

# --- Behavior 3: the sharper consequence. A cross-checkout -Apply must leave
# the deployed bytes alone. Before the fix it did not: status was 'drift', and
# the user-modified guard did NOT fire (the stored raw hash still equalled the
# deployed tree's raw hash), so the script fell through to
# Remove-Item -Recurse -Force and re-copied with the other checkout's line
# endings. Whichever checkout ran last won, and the other then saw drift --
# the two ping-ponging every deployed skill on the machine. ---
function Test-CapabilityApplyDoesNotRewriteAcrossCheckouts {
    param([Parameter(Mandatory)][ValidateSet('LF', 'CRLF')][string]$DeployFrom)
    $applyFrom = if ($DeployFrom -eq 'LF') { 'CRLF' } else { 'LF' }
    Use-SharedCapabilityFixturePair -Body {
        param($ctx)
        $first = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $ctx.Roots[$DeployFrom], '-UserProfile', $ctx.UserProfile) -LocalAppData $ctx.LocalAppData
        if ($first.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "$DeployFrom -Apply exit code was $($first.ExitCode) -- test setup invalid. Output: $($first.Output)" }
        }
        if (-not (Test-Path -LiteralPath $ctx.SkillFile)) {
            return @{ Passed = $false; Detail = "$DeployFrom -Apply did not deploy the fixture skill -- test setup invalid. Output: $($first.Output)" }
        }
        $before = [IO.File]::ReadAllBytes($ctx.SkillFile)

        $second = Invoke-SyncCapabilities -ExtraArgs @('-Apply', '-RepositoryRoot', $ctx.Roots[$applyFrom], '-UserProfile', $ctx.UserProfile) -LocalAppData $ctx.LocalAppData
        if ($second.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "$applyFrom -Apply exit code was $($second.ExitCode). Output: $($second.Output)" }
        }
        $after = [IO.File]::ReadAllBytes($ctx.SkillFile)
        if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$before, [byte[]]$after)) {
            return @{ Passed = $false; Detail = "the $applyFrom checkout rewrote a skill the $DeployFrom checkout had deployed from identical content, flipping its line endings on disk. Output: $($second.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    }
}

$r1 = Test-RenderIsLineEndingIndependent
Report 'subagent rendering is byte-identical from an LF and a CRLF checkout' $r1.Passed $r1.Detail

$r2 = Test-CapabilityAuditIsLineEndingIndependent -DeployFrom 'LF'
Report 'a CRLF checkout audits an LF-deployed skill as current, not drift' $r2.Passed $r2.Detail

$r3 = Test-CapabilityAuditIsLineEndingIndependent -DeployFrom 'CRLF'
Report 'an LF checkout audits a CRLF-deployed skill as current, not drift' $r3.Passed $r3.Detail

$r4 = Test-CapabilityApplyDoesNotRewriteAcrossCheckouts -DeployFrom 'LF'
Report 'a CRLF checkout -Apply leaves an LF-deployed skill byte-identical' $r4.Passed $r4.Detail

$r5 = Test-CapabilityApplyDoesNotRewriteAcrossCheckouts -DeployFrom 'CRLF'
Report 'an LF checkout -Apply leaves a CRLF-deployed skill byte-identical' $r5.Passed $r5.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
