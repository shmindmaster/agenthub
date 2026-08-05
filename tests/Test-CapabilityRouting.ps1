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

function Get-SkillCapabilityDeclarations {
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
            HasSection         = ($null -ne $capabilitySection)
            CapabilitySection  = $section
            ResolutionSection  = $resolutionSection
            PostResolutionText = $postResolutionText
            Capabilities       = $capabilities
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

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
