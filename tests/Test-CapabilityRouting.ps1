#Requires -Version 5.1
<#
Behavior tests for capability routing: the browser-toolkit skills must state
the capability they need and resolve a provider from the registry, instead of
naming one tool that may not exist where the skill runs.

registry/fleet-profile.json's hostSurfaces matrix was added with no consumer.
A capability table that is declared, shape-validated (tests/Test-HostSurfaces.ps1)
and never resolved by anything looks like capability awareness while changing no
behavior. These tests assert the routing is real: every capability a skill names
is vocabulary the matrix knows, something actually provides it, and a surface --
not only the fallback -- is among the things that do.

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

# The resolution order lives in its own section, whose heading begins with this
# prefix and then says what is being resolved for ("...before capturing",
# "...before choosing the lane"). Behavior 4 reads the fallback out of THAT
# section rather than out of the whole file, for the same reason capability
# extraction is section-scoped: a server id can be named incidentally -- in a
# closing paragraph about profile isolation, say -- and an unscoped search reads
# that mention as a declared fallback. Reproduced before this scoping landed:
# deleting the entire resolution section from browser-debugging, and separately
# from interactive-browser-testing, left this file at 5 passed, 0 failed. Only
# browser-evidence fired, and only because it happened to name the server
# nowhere else.
#
# The granularity is the section, not the individual step: each of these
# sections closes with a paragraph explaining why native comes first, and that
# paragraph names the fallback too, so deleting only the numbered fallback step
# would still leave the id inside the section. Section granularity is what makes
# "the resolution order was removed" detectable; step granularity would mean
# parsing the list, and is not claimed here.
$resolutionSectionHeadingPrefix = 'Resolve a provider'

# Not every SKILL.md under this package routes. `use-chrome-devtools-mcp` is the
# tool catalog for ONE registered server, loaded BY the routing skills after they
# have already resolved to it ("For MCP tool names ... also load
# `use-chrome-devtools-mcp`", in all three). Requiring it to route would require
# it to re-declare a decision that has provably already been made, and behavior 6
# would additionally require its tool catalog to name no MCP tool -- that is, to
# stop being a tool catalog.
#
# This file was written on 2026-08-04 for the three routing skills; the reference
# skill arrived on 2026-08-06 and nobody reconciled the two, so the suite has been
# red ever since. A permanently red gate is not a gate -- it is read as background
# noise, and the next real regression lands underneath it.
#
# So the kind is DATA, for the same reason the step roles are (see behavior 8):
# inferring "is this a router?" from prose is the interpretation step that has
# already produced defects in this repository twice.
#
# Default is `routing`. A skill that declares nothing is held to the full
# contract, so the exemption cannot be taken by omission -- opting out of a guard
# by doing nothing is this repository's signature defect, and an optional marker
# would reintroduce it. And the exemption is CHECKED, not granted: behavior 9
# requires a provider-reference skill to be loaded by name from a routing skill
# and to document a server that is actually registered. An orphan cannot hide
# here; it has no reader, so it must route on its own.
$skillKindMarkerPattern = '<!--\s*skill-kind:\s*([^\s>]+)\s*-->'
$defaultSkillKind = 'routing'
$knownSkillKinds = @('routing', 'provider-reference')
function Get-SkillKind {
    param([string]$Text)
    # All matches, not the first: two markers disagreeing is a finding, and
    # taking the first would silently pick a winner.
    $roles = @([regex]::Matches($Text, $skillKindMarkerPattern) | ForEach-Object { $_.Groups[1].Value })
    if ($roles.Count -eq 0) { return $defaultSkillKind }
    if ($roles.Count -gt 1) { return '<multiple:' + ($roles -join ',') + '>' }
    return $roles[0]
}

# One extractor for both sections; $HeadingPattern is the regex for whatever
# follows '## ' on the heading line, so the capability section can be matched
# exactly while the resolution section is matched on its prefix. `\r?\n`
# throughout: this repository is checked out CRLF in worktrees and LF in the
# main checkout, and a section boundary that only matches LF would silently
# extract nothing in one of them.
$capabilityHeadingPattern = [regex]::Escape($capabilitySectionHeading) + '\s*'
$resolutionHeadingPattern = [regex]::Escape($resolutionSectionHeadingPrefix) + '[^\r\n]*'
function Get-MarkdownSection {
    param([string]$Text, [string]$HeadingPattern)
    $match = [regex]::Match(
        $Text,
        ('(?s)^##\s+' + $HeadingPattern + '\r?\n(.*?)(?=\r?\n##\s|\z)'),
        [Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

# Everything from the first heading AFTER the resolution section to the end of
# the file: the steps a skill performs once a provider has been resolved.
# Derived from where the resolution section ends rather than from a list of
# workflow heading names, so renaming '## Workflow' to '## Procedure' -- the
# three skills already use three different names -- cannot drop a skill out of
# the check.
function Get-PostResolutionText {
    param([string]$Text)
    $heading = [regex]::Match($Text, ('(?m)^##\s+' + $resolutionHeadingPattern))
    if (-not $heading.Success) { return $null }
    $rest = $Text.Substring($heading.Index + $heading.Length)
    $next = [regex]::Match($rest, '(?m)^##\s')
    if (-not $next.Success) { return '' }
    return $rest.Substring($next.Index)
}

# The numbered steps within that text, continuation lines included. Prose
# paragraphs around the list are deliberately NOT steps: browser-debugging's
# closing paragraph forbids attaching to a personal Chrome profile, and
# interactive-browser-testing's explains how `chrome-devtools` is launched --
# both are true statements about specific providers, and neither is an
# instruction about how to carry out a step.
function Get-NumberedStepLines {
    param([string]$Text)
    $steps = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrEmpty($Text)) { return $steps }
    $inStep = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\d+\.\s') { $inStep = $true; $steps.Add($line); continue }
        if ([string]::IsNullOrWhiteSpace($line)) { $inStep = $false; continue }
        if ($inStep -and $line -match '^\s+\S') { $steps.Add($line); continue }
        $inStep = $false
    }
    return $steps
}

function Get-AllSkillDeclarations {
    $declarations = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { return $declarations }
    foreach ($skillDirectory in @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)) {
        $skillFile = Join-Path $skillDirectory.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($skillFile)
        $capabilitySection = Get-MarkdownSection -Text $text -HeadingPattern $capabilityHeadingPattern
        $resolutionSection = Get-MarkdownSection -Text $text -HeadingPattern $resolutionHeadingPattern
        $postResolutionText = Get-PostResolutionText -Text $text
        $section = if ($null -ne $capabilitySection) { $capabilitySection } else { '' }
        $tokens = @([regex]::Matches($section, '`([a-z][a-z0-9]*\.[a-z][a-z0-9.]*)`') | ForEach-Object { $_.Groups[1].Value })
        $capabilities = @($tokens | Where-Object { ($_ -split '\.')[0] -in $capabilityNamespaces } | Select-Object -Unique)
        $declarations.Add([pscustomobject]@{
            Skill              = $skillDirectory.Name
            Path               = $skillFile
            Text               = $text
            Kind               = (Get-SkillKind -Text $text)
            HasSection         = ($null -ne $capabilitySection)
            CapabilitySection  = $section
            ResolutionSection  = $resolutionSection
            PostResolutionText = $postResolutionText
            Capabilities       = $capabilities
        })
    }
    return $declarations
}

# Behaviors 1-8 are the routing contract, so they see routing skills only. An
# unknown or duplicated kind marker is NOT quietly dropped from that set -- it
# stays in, and fails behaviors 1-8 exactly as an unmarked skill would, because a
# marker the vocabulary does not know must not act as an exemption. Behavior 9
# names it explicitly.
function Get-SkillCapabilityDeclarations {
    return @(Get-AllSkillDeclarations | Where-Object { $_.Kind -ne 'provider-reference' })
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
    $allSkills = Get-AllSkillDeclarations
    if ($allSkills.Count -eq 0) {
        return @{ Passed = $false; Detail = "found zero SKILL.md files under $skillsRoot." }
    }
    $declarations = Get-SkillCapabilityDeclarations
    # The exemption's own anti-vacuity guard. Behaviors 1-8 all iterate the
    # routing set, so marking every skill `provider-reference` would turn the
    # entire routing contract green while checking nothing -- the same shape as
    # the empty-directory case above, reached by adding a line rather than by
    # deleting a folder, and therefore easier to do by accident.
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = "all $($allSkills.Count) SKILL.md file(s) under $skillsRoot declare '<!-- skill-kind: provider-reference -->', so no skill routes and behaviors 1-8 would pass over an empty set. At least one must be a routing skill, or this package documents providers nobody resolves." }
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

# The two kinds of provider, kept separate so a caller can ask about either one
# alone. Behavior 3 merges them (does anything provide this at all?); behavior 7
# needs them apart, because "a surface provides it" and "the fallback provides
# it" are the two steps of the resolution order and conflating them is the gap
# behavior 7 exists to close.
function Add-SurfaceProviders {
    param([hashtable]$Providers)
    foreach ($surface in @($fleet.hostSurfaces.surfaces)) {
        foreach ($property in @($surface.capabilities.PSObject.Properties)) {
            if ($property.Value -is [bool] -and $property.Value) {
                if (-not $Providers.ContainsKey($property.Name)) { $Providers[$property.Name] = [Collections.Generic.List[string]]::new() }
                $Providers[$property.Name].Add("surface:$($surface.surfaceId)")
            }
        }
    }
}
function Add-McpProviders {
    param([hashtable]$Providers)
    foreach ($server in @($mcps.mcpServers)) {
        foreach ($capability in @($server.providesCapabilities)) {
            if ([string]::IsNullOrWhiteSpace([string]$capability)) { continue }
            if (-not $Providers.ContainsKey([string]$capability)) { $Providers[[string]$capability] = [Collections.Generic.List[string]]::new() }
            $Providers[[string]$capability].Add("mcp:$($server.id)")
        }
    }
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
    Add-SurfaceProviders -Providers $providers
    Add-McpProviders -Providers $providers
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
        if (-not $declaration.HasSection) { $uncited.Add("$($declaration.Skill) (no declaration section)"); continue }
        # Line wrapping in Markdown is presentation, not content: collapse it
        # before comparing, so a quotation is judged on its words rather than on
        # where the author's editor broke the line.
        $section = [regex]::Replace($declaration.CapabilitySection, '\s+', ' ')
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
# so deleting or renaming the server in registry/mcps.json breaks this too.
#
# Read out of the '## Resolve a provider ...' section, not the whole SKILL.md.
# The routing this whole file exists to assert is the resolution order, and an
# unscoped search let that order be deleted outright as long as the server id
# survived anywhere else in the file. ---
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
        if ($null -eq $declaration.ResolutionSection) {
            $bad.Add("$($declaration.Skill) has no '## $resolutionSectionHeadingPrefix ...' section, so it states no resolution order at all and there is nowhere for it to declare a fallback")
            continue
        }
        $namedServers = @($serverIds | Where-Object { $declaration.ResolutionSection -match ('`' + [regex]::Escape($_) + '`') })
        if ($namedServers.Count -eq 0) {
            $bad.Add("$($declaration.Skill) names no registered MCP server as its fallback provider in its '## $resolutionSectionHeadingPrefix ...' section")
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

# --- Behavior 6: the steps that run AFTER resolution work for whatever provider
# was resolved.
#
# A resolution order at the top of the file means nothing if the steps below it
# only make sense for one provider. Both defects this catches were real:
# browser-debugging's workflow said "Use `list_pages`" -- a chrome-devtools tool
# name, in steps that now also run on a natively resolved provider -- and
# browser-evidence's said "the resolved provider's isolated headed Chrome
# profile", when codex-desktop's surface records `browser.isolated` true and the
# browser it drives is not Chrome. Either one silently converts the fallback
# back into the only supported path, undoing the routing in the same file that
# declares it.
#
# Two forms are forbidden, both scoped to the numbered steps:
#   - a backticked snake_case identifier, which in this context is an MCP tool
#     name and belongs to one server's API;
#   - an engine or vendor browser name, which presumes what the resolved
#     provider drives.
# `chrome-devtools` itself is not caught by either (it is hyphenated, and it is
# a registry id, not a tool name) -- naming the fallback in the resolution
# section is the point. Matching is case-SENSITIVE and word-bounded on purpose:
# 'edge' appears in "relevant edge state" in two of these skills, and a
# case-insensitive search for the browser would have flagged it. ---
$providerSpecificTerms = [ordered]@{
    'Chrome'   = "presumes the resolved provider drives Chrome; codex-desktop records browser.isolated true and its built-in browser is not Chrome"
    'Chromium' = 'same presumption, one layer down'
    'Firefox'  = 'names an engine instead of the resolved provider'
    'Edge'     = 'names an engine instead of the resolved provider'
    'Safari'   = 'names an engine instead of the resolved provider'
    'WebKit'   = 'names an engine instead of the resolved provider'
}
$mcpToolNamePattern = '`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`'
function Find-ProviderSpecificSteps {
    param($StepLines)
    $found = [Collections.Generic.List[string]]::new()
    foreach ($line in $StepLines) {
        foreach ($term in $providerSpecificTerms.GetEnumerator()) {
            if ([regex]::IsMatch($line, '\b' + [regex]::Escape([string]$term.Key) + '\b')) {
                $found.Add("'$($term.Key)' -- $($term.Value)")
            }
        }
        foreach ($tool in @([regex]::Matches($line, $mcpToolNamePattern))) {
            $found.Add("``$($tool.Groups[1].Value)`` -- an MCP tool name belongs to one server's API, so the step only runs on that server")
        }
    }
    return $found
}
function Test-PostResolutionStepsNameNoSpecificProvider {
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'no SKILL.md files were read, so this check inspected nothing; see behavior 1.' }
    }
    # Anti-vacuity for a negative check: prove the finder finds before trusting
    # that it found nothing.
    $control = @("1. Use ``list_pages`` in Chrome, then check the relevant edge state.")
    $controlHits = @(Find-ProviderSpecificSteps -StepLines $control)
    if ($controlHits.Count -ne 2) {
        return @{ Passed = $false; Detail = "the provider-specific finder returned $($controlHits.Count) hit(s) [$($controlHits -join ' | ')] against a control step naming one tool and one browser (and one lowercase 'edge' it must ignore); it must return exactly those two, or a clean result against the real skills would mean nothing." }
    }
    $bad = [Collections.Generic.List[string]]::new()
    $totalSteps = 0
    foreach ($declaration in $declarations) {
        if ($null -eq $declaration.PostResolutionText) {
            $bad.Add("$($declaration.Skill) has no '## $resolutionSectionHeadingPrefix ...' section, so there is no post-resolution boundary to read its steps after")
            continue
        }
        $stepLines = @(Get-NumberedStepLines -Text $declaration.PostResolutionText)
        $totalSteps += $stepLines.Count
        foreach ($hit in @(Find-ProviderSpecificSteps -StepLines $stepLines)) {
            $bad.Add("$($declaration.Skill) states a step that names $hit")
        }
    }
    if ($bad.Count -eq 0 -and $totalSteps -eq 0) {
        return @{ Passed = $false; Detail = "the skills state zero numbered steps after their resolution sections, so this check inspected no steps at all. Either the workflows moved out of numbered lists or the post-resolution boundary stopped resolving." }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 7: every capability a skill declares is reachable NATIVELY --
# recorded true on at least one hostSurfaces surface -- and not only through the
# MCP fallback.
#
# Behavior 3 asks whether anything at all provides a declared capability, and
# `chrome-devtools`' providesCapabilities answers yes on its own. So every
# surface in the fleet could stop offering `browser.isolated` and behavior 3
# would still pass: reproduced by flipping both `"browser.isolated": true`
# entries to false, which left this file at 6 passed, 0 failed. That deletes
# step 1 of the resolution order every skill documents -- the running surface's
# own provider -- fleet-wide, and the routing degenerates into "always start the
# local process", which is what registry/mcps.json's activationPolicy (remote
# over local, capability-invoked over session-start) exists to avoid: a browser
# process spawned per host costs CPU and memory on sessions that never use it.
#
# Deliberately NOT tied to a named surface. browser.authenticated is recorded
# false for claude-cli on measured evidence (no connected browser), and a check
# that demanded a particular host would fail on a true reading of the fleet. The
# claim is that the capability is natively reachable SOMEWHERE.
#
# Per-capability, not fleet-wide: a capability that keeps its own surface
# providers must not be named by a failure about a different one, and only
# capabilities a skill actually declares are in scope -- a knownCapabilities
# entry no skill routes on is vocabulary, not a live requirement. ---
function Test-DeclaredCapabilitiesHaveASurfaceProvider {
    $surfaceProviders = @{}
    $mcpProviders = @{}
    Add-SurfaceProviders -Providers $surfaceProviders
    Add-McpProviders -Providers $mcpProviders
    $declarations = Get-SkillCapabilityDeclarations
    $capabilityCount = Get-DeclaredCapabilityCount -Declarations $declarations
    if ($capabilityCount -eq 0) {
        return @{ Passed = $false; Detail = "the skills declare zero capabilities between them ($($declarations.Count) SKILL.md file(s) read), so this check would confirm native reachability of nothing; see behavior 1." }
    }
    # Which skills asked for what, so a finding names the callers that lose the
    # native path rather than just the capability in the abstract.
    $declaredBy = [ordered]@{}
    foreach ($declaration in $declarations) {
        foreach ($capability in $declaration.Capabilities) {
            if (-not $declaredBy.Contains($capability)) { $declaredBy[$capability] = [Collections.Generic.List[string]]::new() }
            $declaredBy[$capability].Add($declaration.Skill)
        }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($capability in @($declaredBy.Keys)) {
        if ($surfaceProviders.ContainsKey($capability)) { continue }
        $askers = "declared by $($declaredBy[$capability] -join ', ')"
        # The two findings are different failures and must not share a message.
        # "no provider" when the truth is "only the fallback" sends the reader
        # looking for an unroutable requirement instead of a dead native path.
        if ($mcpProviders.ContainsKey($capability)) {
            $bad.Add("'$capability' ($askers) is recorded true on no surface in hostSurfaces -- only the MCP fallback(s) $($mcpProviders[$capability] -join ', ') still provide it, so step 1 of the documented resolution order (the running surface's own provider) is dead fleet-wide and every host would start the local process")
        } else {
            $bad.Add("'$capability' ($askers) is recorded true on no surface in hostSurfaces and no MCP server declares it either, so it has neither a native path nor a fallback; see behavior 3")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 8: inside each skill's resolution section, the step that resolves
# the running surface's own provider comes BEFORE the step that starts the local
# fallback process.
#
# Behavior 4 reads that section at SECTION granularity and says so (see the note
# above $resolutionSectionHeadingPrefix): it asks whether a registered fallback
# is named anywhere in the section, which is what makes "the resolution order was
# deleted" detectable. It cannot see the order WITHIN the section. Reproduced by
# exchanging steps 1 and 2 in all three skills so `chrome-devtools` became the
# first step while each file's "Native first is not a quality judgement"
# paragraph stayed in place -- every skill then contradicted itself and
# Test-CapabilityRouting was 7 passed, 0 failed, with Test-RoutingPolicy,
# Test-HostSurfaces and Test-SharedSkillsDeployment green alongside it.
#
# The order is the whole design: registry/mcps.json's activationPolicy prefers a
# shared remote over a locally spawned process, requires one shared local process
# rather than one per host, and requires that process to be started by the
# capability that needs it rather than at session start. A skill that reaches for
# the local server first spawns an `npx` browser process on a surface that
# already had a browser.
#
# What is pinned is the RELATION between two steps, not their wording: each step
# DECLARES its role in the resolution order, so these paragraphs stay free to be
# reworded, to name any server, in any order of mention.
#
# The role used to be inferred from the prose -- the surface step was the first
# step carrying a backticked `hostSurfaces`/`fleet-profile.json` token and not
# naming the local server; the fallback step was the first naming it. Inference
# was wrong in both directions and review demonstrated both:
#   - a correctly ordered step 1 that forward-references the fallback ("look up
#     `hostSurfaces`; if `false`, go to step 2 (`chrome-devtools`)") was
#     disqualified from being the surface step, and a correct skill FAILED;
#   - a step citing the registry for an unrelated reason ("confirm the capture is
#     authorized; fleet inventory lives in `registry/fleet-profile.json`") WAS
#     accepted as the surface step, so a file whose real surface lookup sat at
#     step 3, below the fallback at step 2, scored 8 passed, 0 failed.
# Tightening the wording match would only move the boundary: distinguishing a
# step that DIRECTS use of the local server from one that MENTIONS it is
# interpretation, and interpretation is what produced both defects (and, in
# Sync-Capabilities, a family matcher that accepted `computer.gui: false` because
# the word "Computer" appeared in a sentence saying the capability was never
# established).
#
# So the role is data, not prose. Each numbered step of the resolution section
# carries an HTML comment marker naming its role, and the order becomes checkable
# without reading a single sentence.
#
# The markers are not invisible to the reader that matters. Sync-Capabilities
# copies SKILL.md byte for byte -- which is exactly why adding them drifted 39
# deployed mappings -- so an agent consuming the raw Markdown has the marker text
# in its context. They render as nothing in a Markdown VIEWER, which is not the
# consumer here. Kept terse for that reason, and worth remembering before adding
# more of them.
#
# Re-proved against this mechanism, each in a throwaway copy of the tree: the step
# swap above still FAILS (it now moves the markers with the steps), the
# forward-referencing step 1 PASSES, the unrelated-citation ordering FAILS, and a
# skill with its markers stripped FAILS rather than quietly passing.
#
# The marker is a DECLARATION and is trusted as one: a marker placed on the wrong
# step is not detectable here, by construction, because detecting it would mean
# re-deriving the role from the prose. What is still tied to the registry is the
# section as a whole -- behavior 4 requires it to name a registered fallback
# server that covers the skill's capabilities, and behavior 7 requires a surface
# to provide them natively. ---

# The role vocabulary. Two roles are the resolution order itself and each skill
# must declare exactly one of each; a step that is neither (the Playwright CLI
# lane in two of these skills) declares `additional-lane`, which may appear any
# number of times including none. Every numbered step must carry exactly one
# marker: an OPTIONAL marker is a guard a new skill opts out of by doing nothing,
# which is this repository's signature defect.
$singletonStepRoles = [ordered]@{
    'surface-provided' = "resolves the running surface's own provider"
    'local-fallback'   = 'reaches the locally started fallback server'
}
$optionalStepRoles = [ordered]@{
    'additional-lane'  = 'a further option that is neither of the two above'
}
$knownStepRoles = @($singletonStepRoles.Keys) + @($optionalStepRoles.Keys)
# `([^\s>]+)` rather than the known roles alternated: a marker naming an unknown
# role must be READ and reported by name, not silently fail to match and be
# indistinguishable from a step nobody marked.
$stepRoleMarkerPattern = '<!--\s*resolution-step:\s*([^\s>]+)\s*-->'

# Marker placements across a WHOLE SKILL.md: which numbered step of the
# resolution section each marker sits on, and which markers sit somewhere else.
# Whole-file, not section-scoped, because "this marker is on something that is
# not a resolution step" is a finding -- a role claim in the closing paragraph or
# on a workflow step below is exactly the silent mistake a section-scoped scan
# would drop on the floor.
#
# Deliberately NOT Get-NumberedStepLines, which flattens every line of a section
# into one list: behavior 6 asks "does any line say Chrome" and does not care
# which step a line belongs to, while this behavior is only about which step is
# which. Sharing one helper would mean behavior 6's flattening and this
# behavior's grouping constraining each other, and a change made for one silently
# loosening the other.
function Get-StepRoleMarkerPlacements {
    param([string]$Text)
    $steps = [Collections.Generic.List[object]]::new()
    $stray = [Collections.Generic.List[object]]::new()
    $inResolutionSection = $false
    $current = $null
    $lineNumber = 0
    foreach ($line in ($Text -split '\r?\n')) {
        $lineNumber++
        if ($line -match '^##\s') {
            $inResolutionSection = [regex]::IsMatch($line, '^##\s+' + $resolutionHeadingPattern + '$')
            $current = $null
        } elseif ($inResolutionSection) {
            $start = [regex]::Match($line, '^\s*(\d+)\.\s')
            if ($start.Success) {
                $current = [pscustomobject]@{
                    Number = [int]$start.Groups[1].Value
                    Line   = $lineNumber
                    Roles  = [Collections.Generic.List[string]]::new()
                }
                $steps.Add($current)
            } elseif ([string]::IsNullOrWhiteSpace($line)) {
                $current = $null
            } elseif (-not ($null -ne $current -and $line -match '^\s+\S')) {
                $current = $null
            }
        }
        foreach ($marker in @([regex]::Matches($line, $stepRoleMarkerPattern))) {
            $role = $marker.Groups[1].Value
            if ($inResolutionSection -and $null -ne $current) {
                $current.Roles.Add($role)
            } else {
                $stray.Add([pscustomobject]@{ Role = $role; Line = $lineNumber })
            }
        }
    }
    return [pscustomobject]@{ Steps = $steps; Stray = $stray }
}

function Test-SurfaceStepPrecedesLocalFallbackStep {
    # Anti-vacuity for the parser: prove it attaches, ignores and strands the
    # three placements it must tell apart, before any clean result against the
    # real skills is worth anything.
    $control = @'
## Capability required

Not a step. <!-- resolution-step: surface-provided -->

## Resolve a provider in the control fixture

1. Marked on the step line. <!-- resolution-step: surface-provided -->
2. Marked on a continuation line.
   <!-- resolution-step: local-fallback -->
3. Left unmarked.

Closing prose. <!-- resolution-step: additional-lane -->
'@
    $controlPlacements = Get-StepRoleMarkerPlacements -Text $control
    $controlRoles = @($controlPlacements.Steps | ForEach-Object { '[' + ($_.Roles -join '+') + ']' }) -join ' '
    if ($controlPlacements.Steps.Count -ne 3 -or $controlRoles -ne '[surface-provided] [local-fallback] []' -or $controlPlacements.Stray.Count -ne 2) {
        return @{ Passed = $false; Detail = "the marker parser read the control fixture as $($controlPlacements.Steps.Count) step(s) $controlRoles with $($controlPlacements.Stray.Count) stray marker(s); it must read 3 steps [surface-provided] [local-fallback] [] with 2 stray, or it cannot tell a marked step from an unmarked one from a marker on something that is not a step." }
    }
    $declarations = Get-SkillCapabilityDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'no SKILL.md files were read, so no resolution order was inspected; see behavior 1.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    $totalSteps = 0
    # PER SKILL, not fleet-wide. An anti-vacuity guard keyed on a total across
    # the three skills lets one skill's entire step list be deleted while the
    # other two keep the total non-zero; every skill must state both steps and be
    # judged on its own.
    foreach ($declaration in $declarations) {
        if ($null -eq $declaration.ResolutionSection) {
            $bad.Add("$($declaration.Skill) has no '## $resolutionSectionHeadingPrefix ...' section, so it states no order for a surface-provided step and a locally started one to be in")
            continue
        }
        # Findings about a marker name the FILE and a line, not just the skill:
        # a marker is a thing an author has to go and look at, and repo-relative
        # so the message is the same string in every checkout and worktree.
        $relativePath = $declaration.Path.Substring($repoRoot.Length).TrimStart('\', '/')
        $placements = Get-StepRoleMarkerPlacements -Text $declaration.Text
        $steps = @($placements.Steps)
        if ($steps.Count -eq 0) {
            $bad.Add("$($declaration.Skill) states no numbered steps in its '## $resolutionSectionHeadingPrefix ...' section, so it documents no resolution order at all and this check would pass over nothing")
            continue
        }
        $totalSteps += $steps.Count
        $malformed = $false
        foreach ($marker in @($placements.Stray)) {
            $malformed = $true
            $bad.Add("$relativePath line $($marker.Line) carries the marker '<!-- resolution-step: $($marker.Role) -->' outside the numbered steps of its '## $resolutionSectionHeadingPrefix ...' section, so it claims a resolution role for something that is not a resolution step")
        }
        foreach ($step in $steps) {
            if ($step.Roles.Count -eq 0) {
                $malformed = $true
                $bad.Add("$relativePath step $($step.Number) (line $($step.Line)) carries no '<!-- resolution-step: ... -->' marker, so its role would have to be guessed from its prose; every numbered step of the resolution section must declare one of: $($knownStepRoles -join ', ')")
                continue
            }
            if ($step.Roles.Count -gt 1) {
                $malformed = $true
                $bad.Add("$relativePath step $($step.Number) (line $($step.Line)) carries $($step.Roles.Count) markers ($(($step.Roles | ForEach-Object { "'$_'" }) -join ', ')), so it declares more than one role and no single role can be read from it")
            }
            foreach ($role in $step.Roles) {
                if ($role -notin $knownStepRoles) {
                    $malformed = $true
                    $bad.Add("$relativePath step $($step.Number) (line $($step.Line)) carries the marker '<!-- resolution-step: $role -->', naming a role this check does not know; the vocabulary is: $($knownStepRoles -join ', ')")
                }
            }
        }
        $stepsByRole = @{}
        for ($i = 0; $i -lt $steps.Count; $i++) {
            foreach ($role in $steps[$i].Roles) {
                if (-not $stepsByRole.ContainsKey($role)) { $stepsByRole[$role] = [Collections.Generic.List[object]]::new() }
                $stepsByRole[$role].Add([pscustomobject]@{ Index = $i; Number = $steps[$i].Number })
            }
        }
        foreach ($role in @($singletonStepRoles.Keys)) {
            $carriers = @(if ($stepsByRole.ContainsKey($role)) { $stepsByRole[$role] } else { @() })
            if ($carriers.Count -eq 0) {
                $malformed = $true
                $bad.Add("$relativePath declares no '<!-- resolution-step: $role -->' step ($($singletonStepRoles[$role])), so half the resolution order is unstated and there is no pair of steps to order")
            } elseif ($carriers.Count -gt 1) {
                $malformed = $true
                $bad.Add("$relativePath declares '<!-- resolution-step: $role -->' on $($carriers.Count) steps (steps $(($carriers | ForEach-Object { $_.Number }) -join ', ')); exactly one step may hold that role, or which step it refers to is ambiguous")
            }
        }
        if ($malformed) { continue }
        $surfaceStep  = $stepsByRole['surface-provided'][0]
        $fallbackStep = $stepsByRole['local-fallback'][0]
        if ($fallbackStep.Index -lt $surfaceStep.Index) {
            $bad.Add("$($declaration.Skill) puts its '<!-- resolution-step: local-fallback -->' step at step $($fallbackStep.Number), BEFORE its '<!-- resolution-step: surface-provided -->' step at step $($surfaceStep.Number), so the skill reaches for a spawned local process before checking the browser the running surface already has. That contradicts the rationale the same section carries -- registry/mcps.json activationPolicy prefers a shared remote over a locally spawned process, requires one shared local process rather than one per host, and requires it to be started by the capability that needs it -- and the fleet preference order in global-agent-policy.md")
        }
    }
    if ($bad.Count -eq 0 -and $totalSteps -eq 0) {
        return @{ Passed = $false; Detail = "the skills state zero numbered steps in their '## $resolutionSectionHeadingPrefix ...' sections between them, so this check ordered nothing at all." }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 9: a skill excused from the routing contract must be what it says
# it is.
#
# `<!-- skill-kind: provider-reference -->` removes a file from behaviors 1-8, so
# on its own it is a way to switch this suite off one skill at a time. Two things
# make the claim checkable instead of merely stated:
#
#   - Something must LOAD it. A provider reference is only excused from routing
#     because the routing already happened in the skill that sent the reader here;
#     if no routing skill names it, that premise is false and the file is an
#     orphan that must state its own capability and resolution order like any
#     other. This is what stops the marker from being a way to smuggle in an
#     unrouted skill.
#   - It must document a REGISTERED server. A tool catalog for a server absent
#     from registry/mcps.json routes readers to something the fleet does not run,
#     which is the exact failure ("naming one tool that may not exist where the
#     skill runs") this whole file was written to prevent -- the marker must not
#     become the way back to it.
#
# The kind vocabulary is closed and checked here for the same reason behavior 8
# reads unknown step roles by name: a typo'd `<!-- skill-kind: provider_reference -->`
# is not 'provider-reference', so it stays in the routing set and fails behaviors
# 1-8 -- but with a message about a missing capability section, which sends the
# author to rewrite a skill when the actual defect is one character in a marker. ---
function Test-ProviderReferenceSkillsAreLoadedAndRegistered {
    # Anti-vacuity for the kind parser: prove it reads the three placements apart
    # before any exemption it grants is worth anything.
    $controlKinds = @(
        (Get-SkillKind -Text "# A`n`nNo marker here."),
        (Get-SkillKind -Text "# B`n`n<!-- skill-kind: provider-reference -->"),
        (Get-SkillKind -Text "# C`n`n<!-- skill-kind: routing -->`n<!-- skill-kind: provider-reference -->")
    ) -join ' '
    $expectedKinds = 'routing provider-reference <multiple:routing,provider-reference>'
    if ($controlKinds -ne $expectedKinds) {
        return @{ Passed = $false; Detail = "the kind parser read the control fixtures as '$controlKinds'; it must read '$expectedKinds', or it cannot tell an unmarked skill from a marked one from one carrying two contradictory markers." }
    }
    $allSkills = Get-AllSkillDeclarations
    if ($allSkills.Count -eq 0) {
        return @{ Passed = $false; Detail = "found zero SKILL.md files under $skillsRoot; see behavior 1." }
    }
    $serverIds = @($mcps.mcpServers | ForEach-Object { [string]$_.id } | Where-Object { $_ })
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $allSkills) {
        if ($declaration.Kind -eq $defaultSkillKind) { continue }
        $relativePath = $declaration.Path.Substring($repoRoot.Length).TrimStart('\', '/')
        if ($declaration.Kind -notin $knownSkillKinds) {
            $bad.Add("$relativePath declares '<!-- skill-kind: $($declaration.Kind) -->', which is not a kind this check knows; the vocabulary is: $($knownSkillKinds -join ', '). It stays in the routing set, so any behavior 1-8 finding against it is a symptom of this marker, not of the skill's prose.")
            continue
        }
        # Backticked, matching how the routing skills already cite it and how
        # every other cross-reference in this file is matched: a bare mention in
        # a sentence about something else is not a load instruction.
        $loaders = @(
            $allSkills |
                Where-Object { $_.Skill -ne $declaration.Skill -and $_.Kind -eq $defaultSkillKind } |
                Where-Object { $_.Text -match ('`' + [regex]::Escape($declaration.Skill) + '`') } |
                ForEach-Object { $_.Skill }
        )
        if ($loaders.Count -eq 0) {
            $bad.Add("$($declaration.Skill) is excused from the routing contract as a provider reference, but no routing skill names ``$($declaration.Skill)``, so nothing resolves a provider before sending a reader to it. An unloaded skill has no prior resolution to rely on and must state its own '## $capabilitySectionHeading' and '## $resolutionSectionHeadingPrefix ...' sections; remove the marker or give it a reader.")
            continue
        }
        $namedServers = @($serverIds | Where-Object { $declaration.Text -match ('`' + [regex]::Escape($_) + '`') })
        if ($namedServers.Count -eq 0) {
            $bad.Add("$($declaration.Skill) is excused as a provider reference (loaded by $($loaders -join ', ')) but names no server registered in registry/mcps.json, so it documents tools for something the fleet does not run -- the failure this file exists to prevent.")
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

$r6 = Test-PostResolutionStepsNameNoSpecificProvider
Report 'the numbered steps after resolution name no backticked MCP tool name and no browser engine name' $r6.Passed $r6.Detail

$r7 = Test-DeclaredCapabilitiesHaveASurfaceProvider
Report 'every capability a skill names is recorded true on at least one surface, not served only by the MCP fallback' $r7.Passed $r7.Detail

$r8 = Test-SurfaceStepPrecedesLocalFallbackStep
Report 'each skill declares its surface-provided step before its local-fallback step' $r8.Passed $r8.Detail

$r9 = Test-ProviderReferenceSkillsAreLoadedAndRegistered
Report 'every skill excused from routing is loaded by a routing skill and documents a registered server' $r9.Passed $r9.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
