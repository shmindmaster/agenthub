#Requires -Version 5.1
<#
Behavior tests for task-6b coverage-gap priority 1: the registry contract.
Every hostId referenced anywhere in registry/capabilities.json,
registry/mcps.json, registry/native-connectors.json,
registry/gateway-profiles.json, and registry/fleet-profile.json's
autonomyProfiles must resolve against registry/agents.json (either a real
agent id or a declared surfaceAliases surfaceId). Every capability's
canonicalSource must exist on disk. Nothing in scripts/ currently enforces
the first four files against each other -- only capabilities.json's
canonicalSource and fleet-profile.json's autonomyProfiles are covered by
scripts/Validate-AgentHub.ps1 today; mcps.json, native-connectors.json, and
gateway-profiles.json host references are unprotected. This file closes
that gap without modifying any production script (out of this task's
scope): the collector and checker below are test-only code.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this file
follows). Same self-checking idiom: each Test-* function returns a result,
the runner prints one PASS/FAIL line per behavior, accumulates failures,
and exits 1 if any behavior did not hold, 0 otherwise.

This file only ever reads the real registry; it never writes to it and
never invokes any script with -Apply.

Run: pwsh -NoProfile -File tests/Test-RegistryHostReferences.ps1
     powershell.exe -NoProfile -File tests/Test-RegistryHostReferences.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

# ---------------------------------------------------------------------------
# Get-HostIdReferences: recursively walks a parsed JSON document (any of the
# five registry files' shapes) and collects every hostId reference. Two
# patterns are observed across the registry: a property literally named
# 'hostId' (capabilities.json hostMappings[], native-connectors.json
# hosts[], gateway-profiles.json hosts[] and profiles[].hostMappings[],
# fleet-profile.json autonomyProfiles.profiles[]/aliases[]), and a property
# named 'hosts' whose value is a bare array of host-id strings
# (mcps.json mcpServers[].hosts). Both are collected generically so this
# does not need to be re-taught every registry file's exact schema.
# ---------------------------------------------------------------------------
function Get-HostIdReferences {
    param($Node, [string]$PathPrefix = '$', [Collections.Generic.List[object]]$Results)
    if ($null -eq $Results) { $Results = [Collections.Generic.List[object]]::new() }
    if ($null -eq $Node) { return $Results }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $Node.PSObject.Properties) {
            $childPath = "$PathPrefix.$($prop.Name)"
            if ($prop.Name -eq 'hostId' -and ($prop.Value -is [string])) {
                $Results.Add([pscustomobject]@{ HostId = $prop.Value; Path = $childPath })
            }
            if ($prop.Name -eq 'hosts' -and ($prop.Value -is [array])) {
                $idx = 0
                foreach ($item in $prop.Value) {
                    $itemPath = "$childPath[$idx]"
                    if ($item -is [string]) {
                        $Results.Add([pscustomobject]@{ HostId = $item; Path = $itemPath })
                    } else {
                        [void](Get-HostIdReferences -Node $item -PathPrefix $itemPath -Results $Results)
                    }
                    $idx++
                }
                continue
            }
            [void](Get-HostIdReferences -Node $prop.Value -PathPrefix $childPath -Results $Results)
        }
    } elseif ($Node -is [array]) {
        $idx = 0
        foreach ($item in $Node) {
            [void](Get-HostIdReferences -Node $item -PathPrefix "$PathPrefix[$idx]" -Results $Results)
            $idx++
        }
    }
    return $Results
}

# Get-ValidHostIds: the resolvable set is every registered agent id PLUS
# every declared surface alias (registry/agents.json's surfaceAliases --
# e.g. 'cursor-agent', 'antigravity-desktop' -- which several registry
# files legitimately reference instead of the underlying hostId).
function Get-ValidHostIds {
    param($AgentsDoc)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in (@($AgentsDoc.activeAgents) + @($AgentsDoc.inactiveAgents))) { [void]$ids.Add([string]$a.id) }
    foreach ($alias in @($AgentsDoc.surfaceAliases)) { [void]$ids.Add([string]$alias.surfaceId) }
    return $ids
}

function Get-HostReferenceViolations {
    param([hashtable]$DocsByLabel, [Collections.Generic.HashSet[string]]$ValidHostIds)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($label in $DocsByLabel.Keys) {
        $refs = Get-HostIdReferences -Node $DocsByLabel[$label]
        foreach ($ref in $refs) {
            if (-not $ValidHostIds.Contains($ref.HostId)) {
                $violations.Add("$label`: unresolved hostId '$($ref.HostId)' at $($ref.Path)")
            }
        }
    }
    return $violations
}

function Get-CanonicalSourceViolations {
    param($CapabilitiesDoc, [string]$RepoRootPath)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($capability in @($CapabilitiesDoc.capabilities)) {
        $source = [string]$capability.canonicalSource
        if ([string]::IsNullOrWhiteSpace($source)) {
            $violations.Add("capability '$($capability.id)' has an empty canonicalSource")
            continue
        }
        $resolved = Join-Path $RepoRootPath $source
        if (-not (Test-Path -LiteralPath $resolved)) {
            $violations.Add("capability '$($capability.id)' canonicalSource does not exist on disk: $source")
        }
    }
    return $violations
}

# --- Behavior 1: an unknown hostId embedded in any of the recognized
# shapes (hostId property, or a bare string in a 'hosts' array) is flagged
# by name. Synthetic fixture, never touches the real registry. ---
function Test-CollectorFlagsUnknownHostId {
    $validHostIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$validHostIds.Add('claude')
    [void]$validHostIds.Add('codex')

    $capabilitiesShaped = [pscustomobject]@{
        capabilities = @(
            [pscustomobject]@{
                id = 'fixture-cap'
                hostMappings = @([pscustomobject]@{ hostId = 'totally-bogus-host'; deploymentStatus = 'managed' })
            }
        )
    }
    $mcpsShaped = [pscustomobject]@{
        mcpServers = @([pscustomobject]@{ id = 'sample'; hosts = @('claude', 'another-bogus-host') })
    }
    $docs = @{ 'capabilities.json' = $capabilitiesShaped; 'mcps.json' = $mcpsShaped }
    $violations = Get-HostReferenceViolations -DocsByLabel $docs -ValidHostIds $validHostIds
    if ($violations.Count -ne 2) {
        return @{ Passed = $false; Detail = "expected exactly 2 violations, got $($violations.Count): $($violations -join ' | ')" }
    }
    if (($violations -join '|') -notmatch 'totally-bogus-host' -or ($violations -join '|') -notmatch 'another-bogus-host') {
        return @{ Passed = $false; Detail = "violations did not name both bogus host ids: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2 (regression guard): a real agent id AND a declared surface
# alias id must both be accepted -- zero violations. Proves the alias
# mechanism (gateway-profiles.json/fleet-profile.json legitimately
# reference surface ids like 'cursor-agent', not just raw agent ids) is not
# a false-positive source. ---
function Test-CollectorAcceptsKnownHostIdsAndSurfaceAliases {
    $agentsDoc = [pscustomobject]@{
        activeAgents = @([pscustomobject]@{ id = 'claude' })
        inactiveAgents = @()
        surfaceAliases = @([pscustomobject]@{ surfaceId = 'cursor-agent'; inheritsHostId = 'cursor' })
    }
    $validHostIds = Get-ValidHostIds -AgentsDoc $agentsDoc
    $doc = [pscustomobject]@{
        profiles = @(
            [pscustomobject]@{ hostId = 'claude' },
            [pscustomobject]@{ hostId = 'cursor-agent' }
        )
    }
    $violations = Get-HostReferenceViolations -DocsByLabel @{ 'fixture.json' = $doc } -ValidHostIds $validHostIds
    if ($violations.Count -ne 0) {
        return @{ Passed = $false; Detail = "expected zero violations for a real host id and a declared surface alias, got: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: the live registry. Every hostId reference across the real
# capabilities.json, mcps.json, native-connectors.json, gateway-profiles.json,
# and fleet-profile.json resolves against the real agents.json. This is the
# permanent regression guard -- if it ever fails, the registry has drifted. ---
function Test-LiveRegistryHostReferencesAllResolve {
    $registryDir = Join-Path $repoRoot 'registry'
    $agentsDoc = Get-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $validHostIds = Get-ValidHostIds -AgentsDoc $agentsDoc
    $docs = @{
        'capabilities.json'      = (Get-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'mcps.json'               = (Get-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'native-connectors.json'  = (Get-Content -LiteralPath (Join-Path $registryDir 'native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'gateway-profiles.json'   = (Get-Content -LiteralPath (Join-Path $registryDir 'gateway-profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        'fleet-profile.json.autonomyProfiles' = (Get-Content -LiteralPath (Join-Path $registryDir 'fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json).autonomyProfiles
    }
    $violations = Get-HostReferenceViolations -DocsByLabel $docs -ValidHostIds $validHostIds
    if ($violations.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($violations.Count) unresolved hostId reference(s): $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: a capability whose canonicalSource does not exist on disk
# is flagged by id. Synthetic fixture. ---
function Test-CanonicalSourceMissingOnDiskIsFlagged {
    $doc = [pscustomobject]@{
        capabilities = @([pscustomobject]@{ id = 'ghost-capability'; canonicalSource = 'packages/this-directory-does-not-exist-zz' })
    }
    $violations = Get-CanonicalSourceViolations -CapabilitiesDoc $doc -RepoRootPath $repoRoot
    if ($violations.Count -ne 1) {
        return @{ Passed = $false; Detail = "expected exactly 1 violation, got $($violations.Count): $($violations -join ' | ')" }
    }
    if (($violations -join '|') -notmatch 'ghost-capability') {
        return @{ Passed = $false; Detail = "violation did not name the capability: $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: the live registry. Every real capability's canonicalSource
# exists on disk. Permanent regression guard. ---
function Test-LiveCapabilitiesCanonicalSourcesAllExistOnDisk {
    $capabilitiesDoc = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $violations = Get-CanonicalSourceViolations -CapabilitiesDoc $capabilitiesDoc -RepoRootPath $repoRoot
    if ($violations.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($violations.Count) missing canonicalSource(s): $($violations -join ' | ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-CollectorFlagsUnknownHostId
Report 'an unresolved hostId (hostId property or bare hosts[] string) is flagged by name' $r1.Passed $r1.Detail

$r2 = Test-CollectorAcceptsKnownHostIdsAndSurfaceAliases
Report 'a real agent id and a declared surface alias id both resolve with zero false positives' $r2.Passed $r2.Detail

$r3 = Test-LiveRegistryHostReferencesAllResolve
Report 'every hostId reference in the live registry (capabilities/mcps/native-connectors/gateway-profiles/fleet-profile) resolves against agents.json' $r3.Passed $r3.Detail

$r4 = Test-CanonicalSourceMissingOnDiskIsFlagged
Report 'a capability whose canonicalSource is missing on disk is flagged by id' $r4.Passed $r4.Detail

$r5 = Test-LiveCapabilitiesCanonicalSourcesAllExistOnDisk
Report 'every live capability canonicalSource exists on disk' $r5.Passed $r5.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $(5 - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: 5 passed, 0 failed' -ForegroundColor Green
exit 0
