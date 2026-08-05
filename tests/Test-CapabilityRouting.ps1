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

# A skill "requires" a capability by writing it as an inline-code token -- the
# same form the registry uses -- inside its "## Capability required" section.
# Reading it back out of the rendered SKILL.md means the test checks what a host
# actually ships, not a parallel declaration that could drift from the prose.
#
# Extraction is scoped to that one section, not the whole file, so a capability
# can be named elsewhere WITHOUT being requested: a skill must be able to say
# "browser.authenticated is a different capability this skill must not obtain"
# without the test reading that prohibition as a requirement and then failing
# because nothing provides it.
$capabilitySectionHeading = 'Capability required'

function Get-SkillCapabilityDeclarations {
    $declarations = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { return $declarations }
    foreach ($skillDirectory in @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($skillFile)
        # `\r?\n` throughout: this repository is checked out CRLF in worktrees and
        # LF in the main checkout, and a section boundary that only matches LF
        # would silently extract nothing in one of them.
        $sectionMatch = [regex]::Match(
            $text,
            ('(?s)^##\s+' + [regex]::Escape($capabilitySectionHeading) + '\s*\r?\n(.*?)(?=\r?\n##\s|\z)'),
            [Text.RegularExpressions.RegexOptions]::Multiline)
        $section = if ($sectionMatch.Success) { $sectionMatch.Groups[1].Value } else { '' }
        $tokens = @([regex]::Matches($section, '`([a-z][a-z0-9]*\.[a-z][a-z0-9.]*)`') | ForEach-Object { $_.Groups[1].Value })
        $capabilities = @($tokens | Where-Object { ($_ -split '\.')[0] -in $capabilityNamespaces } | Select-Object -Unique)
        $declarations.Add([pscustomobject]@{
            Skill        = $skillDirectory.Name
            Path         = $skillFile
            Text         = $text
            HasSection   = $sectionMatch.Success
            Capabilities = $capabilities
        })
    }
    return $declarations
}

# The count of capabilities actually extracted -- NOT the count of skills.
#
# Behaviors 2-4 iterate over capabilities, so three skills that declare nothing
# leave them iterating over an empty set while three SKILL.md files sit on disk.
# Guarding on "zero skills" does not catch that: it was reproduced by emptying
# hostSurfaces.knownCapabilities, where behaviors 3 and 4 printed PASS while
# checking nothing and only behaviors 1 and 2 held the run down.
function Get-DeclaredCapabilityCount {
    param($Declarations)
    return @($Declarations | ForEach-Object { $_.Capabilities } | Where-Object { $_ }).Count
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
    $missingSection = @($declarations | Where-Object { -not $_.HasSection } | ForEach-Object { $_.Skill })
    if ($missingSection.Count -gt 0) {
        return @{ Passed = $false; Detail = "these skills have no '## $capabilitySectionHeading' section, so there is nowhere for them to state what they need: $($missingSection -join ', ')" }
    }
    $silent = @($declarations | Where-Object { $_.Capabilities.Count -eq 0 } | ForEach-Object { $_.Skill })
    if ($silent.Count -gt 0) {
        return @{ Passed = $false; Detail = "these skills name no capability from hostSurfaces in their '## $capabilitySectionHeading' section, so nothing about them can be routed or checked: $($silent -join ', ')" }
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
    $declarations = Get-SkillCapabilityDeclarations
    $capabilityCount = Get-DeclaredCapabilityCount -Declarations $declarations
    if ($capabilityCount -eq 0) {
        return @{ Passed = $false; Detail = "the skills declare zero capabilities between them ($($declarations.Count) SKILL.md file(s) read), so this check would validate an empty set; see behavior 1." }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $declarations) {
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
    $capabilityCount = Get-DeclaredCapabilityCount -Declarations $declarations
    if ($capabilityCount -eq 0) {
        return @{ Passed = $false; Detail = "the skills declare zero capabilities between them ($($declarations.Count) SKILL.md file(s) read), so this check would confirm provider coverage of nothing; see behavior 1." }
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

# --- Behavior 5: a capability meaning a skill quotes must be the registry's own
# words, character for character.
#
# The skills present the meaning of browser.isolated as a quotation from
# fleet-profile.json. A near-quote -- relettered, repunctuated, "close enough" --
# is where drift starts: it reads as evidence while no longer being the text it
# cites, and nothing then notices when the registry's wording moves. So every
# double-quoted passage inside a "Capability required" section must equal a
# capabilityMeanings value exactly. Paraphrase is fine; paraphrase wearing
# quotation marks is not. ---
function Test-QuotedCapabilityMeaningsAreVerbatim {
    $meanings = @{}
    foreach ($property in @($fleet.hostSurfaces.capabilityMeanings.PSObject.Properties)) {
        $meanings[$property.Name] = [string]$property.Value
    }
    if ($meanings.Count -eq 0) {
        return @{ Passed = $false; Detail = 'fleet-profile.json declares no hostSurfaces.capabilityMeanings, so any quotation would have nothing to be checked against.' }
    }
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'no SKILL.md files were read, so this check compared nothing; see behavior 1.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    $uncited = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $declarations) {
        $sectionMatch = [regex]::Match(
            $declaration.Text,
            ('(?s)^##\s+' + [regex]::Escape($capabilitySectionHeading) + '\s*\r?\n(.*?)(?=\r?\n##\s|\z)'),
            [Text.RegularExpressions.RegexOptions]::Multiline)
        if (-not $sectionMatch.Success) { $uncited.Add("$($declaration.Skill) (no declaration section)"); continue }
        # Line wrapping in Markdown is presentation, not content: collapse it
        # before comparing, so a quotation is judged on its words rather than on
        # where the author's editor broke the line.
        $section = [regex]::Replace($sectionMatch.Groups[1].Value, '\s+', ' ')
        # The meanings this particular skill is entitled to quote: quoting
        # computer.gui's definition inside a skill that routes on
        # browser.isolated is a citation of something it does not use.
        $ownMeanings = @($declaration.Capabilities | Where-Object { $meanings.ContainsKey($_) } | ForEach-Object { $meanings[$_] })
        $skillQuoteCount = 0
        foreach ($quote in @([regex]::Matches($section, '"([^"]+)"'))) {
            $skillQuoteCount++
            $quotedText = $quote.Groups[1].Value.Trim()
            # -ceq, not -contains: PowerShell's containment operators are
            # case-INSENSITIVE, so "a first-party browser..." compared clean
            # against the registry's "A first-party browser...". Relettering is
            # precisely one of the near-quote defects this behavior exists to
            # catch, and the first version of it did not.
            if (@($ownMeanings | Where-Object { $_ -ceq $quotedText }).Count -eq 0) {
                $bad.Add("$($declaration.Skill) quotes `"$quotedText`", which is not verbatim the capabilityMeanings definition of any capability it declares")
            }
        }
        # PER-SKILL, not global. A single surviving quotation anywhere in the
        # package used to satisfy this check for the whole package, so two of
        # three skills could quietly stop citing the definition they route on
        # and the suite stayed green. Behavior 1 is no backstop here: it counts
        # capability tokens, not citations.
        if ($skillQuoteCount -eq 0) { $uncited.Add($declaration.Skill) }
    }
    if ($uncited.Count -gt 0) {
        $bad.Add("these skills cite no capability definition at all, so nothing about their stated meaning is checked: $($uncited -join ', ')")
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
    $capabilityCount = Get-DeclaredCapabilityCount -Declarations $declarations
    if ($capabilityCount -eq 0) {
        return @{ Passed = $false; Detail = "the skills declare zero capabilities between them ($($declarations.Count) SKILL.md file(s) read), so every fallback would trivially cover everything asked of it; see behavior 1." }
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

$r5 = Test-QuotedCapabilityMeaningsAreVerbatim
Report 'every capability meaning a skill quotes is verbatim the registry definition' $r5.Passed $r5.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
