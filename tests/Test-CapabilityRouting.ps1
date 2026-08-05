#Requires -Version 5.1
<#
Behavior tests for capability routing: the browser-toolkit skills must state
the capability they need and resolve a provider from the registry, instead of
naming one tool that may not exist where the skill runs.

registry/fleet-profile.json's hostSurfaces matrix was added with no consumer.
A capability table that is declared, shape-validated (tests/Test-HostSurfaces.ps1)
and never resolved by anything looks like capability awareness while changing no
behavior. These tests assert the routing is real: every capability a skill names
is vocabulary the matrix knows, and something actually provides it.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom -- one PASS/FAIL line per behavior, exit 1 if any
behavior did not hold.

Run: pwsh -NoProfile -File tests/Test-CapabilityRouting.ps1
     powershell.exe -NoProfile -File tests/Test-CapabilityRouting.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$skillsRoot = Join-Path $repoRoot 'packages\browser-toolkit\skills'

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

$fleet = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mcps  = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$knownCapabilities = @($fleet.hostSurfaces.knownCapabilities)
# Namespaces are derived from the registry rather than hardcoded, so a token
# like `plugin.json` is never mistaken for a capability while a misspelt
# `browser.isolatd` still is one.
$capabilityNamespaces = @($knownCapabilities | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique)

# A skill "names" a capability by writing it as an inline-code token, which is
# the same form the registry uses. Reading it back out of the rendered SKILL.md
# means the test checks what a host actually ships, not a parallel declaration
# that could drift from the prose.
function Get-SkillCapabilityDeclarations {
    $declarations = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { return $declarations }
    foreach ($skillDirectory in @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($skillFile)
        $tokens = @([regex]::Matches($text, '`([a-z][a-z0-9]*\.[a-z][a-z0-9.]*)`') | ForEach-Object { $_.Groups[1].Value })
        $capabilities = @($tokens | Where-Object { ($_ -split '\.')[0] -in $capabilityNamespaces } | Select-Object -Unique)
        $declarations.Add([pscustomobject]@{
            Skill        = $skillDirectory.Name
            Path         = $skillFile
            Text         = $text
            Capabilities = $capabilities
        })
    }
    return $declarations
}

# --- Behavior 1 (anti-vacuity): the browser-toolkit skills exist and every one
# of them states the capability it needs.
#
# Behaviors 2-4 all pass trivially over an empty set, so a renamed skills
# directory or a skill that quietly went back to naming a tool would make this
# whole file green while routing nothing. ---
function Test-EverySkillDeclaresACapability {
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) {
        return @{ Passed = $false; Detail = "no skills directory at $skillsRoot; the routing assertions below would pass over an empty set." }
    }
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = "found zero SKILL.md files under $skillsRoot." }
    }
    $silent = @($declarations | Where-Object { $_.Capabilities.Count -eq 0 } | ForEach-Object { $_.Skill })
    if ($silent.Count -gt 0) {
        return @{ Passed = $false; Detail = "these skills name no capability from hostSurfaces, so nothing about them can be routed or checked: $($silent -join ', ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: every capability a skill names is one hostSurfaces knows.
#
# A misspelt capability resolves to no row in the matrix, so the lookup returns
# nothing and the skill falls through to the fallback on every host -- the
# quiet failure, because the skill still reads as if it routes. ---
function Test-DeclaredCapabilitiesAreKnown {
    if ($knownCapabilities.Count -eq 0) {
        return @{ Passed = $false; Detail = 'fleet-profile.json declares no hostSurfaces.knownCapabilities, so any name a skill invented would validate.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($declaration in Get-SkillCapabilityDeclarations) {
        foreach ($capability in $declaration.Capabilities) {
            if ($capability -notin $knownCapabilities) {
                $bad.Add("$($declaration.Skill) names '$capability', which is not in hostSurfaces.knownCapabilities ($($knownCapabilities -join ', '))")
            }
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: every capability a skill names has at least one real provider.
#
# A provider is a surface recording the capability `true`, or an MCP server
# declaring it in providesCapabilities. A capability that no provider offers is
# an unroutable requirement: the resolution order runs out of steps and the
# skill cannot do the thing it says it does anywhere in the fleet. Note that
# `false` and `null` in the matrix are both non-providers, and deliberately
# distinct findings -- browser.authenticated is recorded false for claude-cli
# on this machine (no connected browser), and null where nothing was probed. ---
function Test-DeclaredCapabilitiesHaveAProvider {
    $providers = @{}
    foreach ($surface in @($fleet.hostSurfaces.surfaces)) {
        foreach ($property in @($surface.capabilities.PSObject.Properties)) {
            if ($property.Value -is [bool] -and $property.Value) {
                if (-not $providers.ContainsKey($property.Name)) { $providers[$property.Name] = [Collections.Generic.List[string]]::new() }
                $providers[$property.Name].Add("surface:$($surface.surfaceId)")
            }
        }
    }
    foreach ($server in @($mcps.mcpServers)) {
        foreach ($capability in @($server.providesCapabilities)) {
            if ([string]::IsNullOrWhiteSpace([string]$capability)) { continue }
            if (-not $providers.ContainsKey([string]$capability)) { $providers[[string]$capability] = [Collections.Generic.List[string]]::new() }
            $providers[[string]$capability].Add("mcp:$($server.id)")
        }
    }
    if ($providers.Count -eq 0) {
        return @{ Passed = $false; Detail = 'nothing in the fleet provides any capability -- no surface records one true and no MCP server declares providesCapabilities.' }
    }
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'no skills found; see behavior 1.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $declarations) {
        foreach ($capability in $declaration.Capabilities) {
            if (-not $providers.ContainsKey($capability)) {
                $bad.Add("$($declaration.Skill) requires '$capability', which no surface records true and no MCP server declares in providesCapabilities")
            }
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: the fallback a skill names must actually be able to serve it.
#
# The resolution order is native surface first, chrome-devtools second. That is
# only a routing rule if the second step covers what the skill asked for: a
# skill whose fallback provides none of its capabilities has a resolution order
# that dead-ends on exactly the surfaces the order exists for (codex-cli and
# codex-ide record no browser at all). The fallback is matched by registry id,
# so deleting or renaming the server in registry/mcps.json breaks this too. ---
function Test-EachSkillNamesAFallbackThatCoversIt {
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'no skills found; see behavior 1.' }
    }
    $serverIds = @($mcps.mcpServers | ForEach-Object { [string]$_.id } | Where-Object { $_ })
    if ($serverIds.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/mcps.json declares no MCP servers, so no skill could name a registered fallback.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $declarations) {
        $namedServers = @($serverIds | Where-Object { $declaration.Text -match ('`' + [regex]::Escape($_) + '`') })
        if ($namedServers.Count -eq 0) {
            $bad.Add("$($declaration.Skill) names no registered MCP server as its fallback provider")
            continue
        }
        $covered = @(
            foreach ($serverId in $namedServers) {
                $server = @($mcps.mcpServers | Where-Object { [string]$_.id -eq $serverId })[0]
                @($server.providesCapabilities) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            }
        )
        $missing = @($declaration.Capabilities | Where-Object { $_ -notin $covered })
        if ($missing.Count -gt 0) {
            $bad.Add("$($declaration.Skill) falls back to $($namedServers -join '/'), which declares no providesCapabilities entry for: $($missing -join ', ')")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-EverySkillDeclaresACapability
Report 'every browser-toolkit skill states the capability it requires' $r1.Passed $r1.Detail

$r2 = Test-DeclaredCapabilitiesAreKnown
Report 'every capability a skill names exists in hostSurfaces.knownCapabilities' $r2.Passed $r2.Detail

$r3 = Test-DeclaredCapabilitiesHaveAProvider
Report 'every capability a skill names is offered by at least one declared provider' $r3.Passed $r3.Detail

$r4 = Test-EachSkillNamesAFallbackThatCoversIt
Report 'each skill names a registered fallback provider that declares the capability it needs' $r4.Passed $r4.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
