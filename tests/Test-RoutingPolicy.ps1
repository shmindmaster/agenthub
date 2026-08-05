#Requires -Version 5.1
<#
Behavior tests for the capability-routing section of global-agent-policy.md.

That file is rendered byte-for-byte into all 22 hosts' instruction files by
scripts/Sync-Instructions.ps1, so a sentence here is a sentence every agent
surface reads. Two external proposals argued for native-first routing; their
durable principles are kept, and the factual claims they got wrong about this
machine must never be reintroduced. These tests hold both ends: the principle
is stated, and the wrong claims stay out.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom -- one PASS/FAIL line per behavior, exit 1 if any
behavior did not hold.

Run: pwsh -NoProfile -File tests/Test-RoutingPolicy.ps1
     powershell.exe -NoProfile -File tests/Test-RoutingPolicy.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$policyPath = Join-Path $repoRoot 'global-agent-policy.md'

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

# Normalized to LF the same way the renderer normalizes it, so a CRLF checkout
# and an LF checkout compare identically.
$policyText = [IO.File]::ReadAllText($policyPath).Replace("`r`n", "`n")

$fleet  = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# The empty-string filter is not decoration: piping a missing property into
# ForEach-Object emits one $null rather than nothing, so a renamed agents.json
# key yields a two-element array of nulls and a Count-based emptiness guard
# below would never notice.
$registeredHostIds    = @(@($agents.activeAgents | ForEach-Object id) + @($agents.inactiveAgents | ForEach-Object id) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$knownDefaultProfiles = @($fleet.autonomyProfiles.knownDefaultProfiles)
# Derived, never transcribed: which hosts must ask is the registry's answer, and
# a copy of that list in this file would be one more thing to keep in step.
$interactiveHostIds   = @($fleet.autonomyProfiles.profiles |
    Where-Object { [string]$_.defaultProfile -eq 'interactive' } | ForEach-Object { [string]$_.hostId })

$routingHeading = '## Capability routing'

# The section, not the whole file. Scoping every assertion to the routing
# section is what makes the forbidden-claim check below meaningful: a product
# name three sections away is somebody else's sentence, not a routing claim.
function Get-RoutingSection {
    $start = $policyText.IndexOf($routingHeading, [StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $rest = $policyText.Substring($start + $routingHeading.Length)
    $end = $rest.IndexOf("`n## ", [StringComparison]::Ordinal)
    if ($end -ge 0) { $rest = $rest.Substring(0, $end) }
    return $rest
}

function Find-MissingPhrases {
    param([string]$Text, $Phrases)
    $missing = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Phrases.GetEnumerator()) {
        if ($Text.IndexOf([string]$entry.Value, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $missing.Add("$($entry.Key) (expected the section to contain '$($entry.Value)')")
        }
    }
    return $missing
}

# --- Behavior 1: the section exists and states the routing principle.
#
# The durable half of both proposals: parity is of outcome, validation and
# delivery -- not of tools. Each host uses its strongest native capability, and
# nothing is emulated through GUI clicks that a structured tool performs
# directly. Without this stated, "native-first" is a preference nobody wrote
# down and every host improvises. ---
$principlePhrases = [ordered]@{
    'parity is of outcome, not of tools'         = 'not identical tools'
    'each host uses its strongest capability'    = 'strongest native capability'
    'no GUI emulation of what a tool does directly' = 'Never emulate'
    'no redundant integration to imitate another platform' = 'redundant integration'
    'a stated preference order, not a fixed tier list' = 'Prefer, in order'
}
function Test-SectionStatesTheRoutingPrinciple {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section, so every assertion in this file would be searching an empty string." }
    }
    if ($principlePhrases.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: the required-phrase set is empty, so this behavior would pass over any section text at all.' }
    }
    $missing = @(Find-MissingPhrases -Text $section -Phrases $principlePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section does not state: $($missing -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: routing resolves a capability from the registry, and the
# section makes no unevidenced claim that a named product is available here.
#
# This is the half of the source proposals that was wrong. Each forbidden
# phrase below is a specific claim that was checked on this machine and did not
# hold; the reason is carried with the phrase so a future author can see what
# would have to change before the claim becomes sayable. Because
# global-agent-policy.md reaches all 22 hosts, a product name written here is a
# routing instruction 22 surfaces would follow into nothing. ---
$unevidencedClaims = [ordered]@{
    'Claude in Chrome' = 'browser.authenticated is recorded false for claude-cli in registry/fleet-profile.json -- list_connected_browsers returned an empty array, so the product exists and the capability does not'
    'agent teams'      = 'Claude agent teams are experimental and inert unless CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, which is not set on this machine'
    'Computer Use'     = 'computer use is tier-limited here: browsers are read-only and terminals/IDEs reject typing, so it substitutes for neither a browser nor a shell'
    'macOS'            = 'this fleet runs on Windows 11; one source proposal routed to native macOS applications'
}
$capabilityResolutionPhrases = [ordered]@{
    'resolution is against the registry surface matrix' = 'hostSurfaces'
    'and names the file that carries it'                = 'registry/fleet-profile.json'
    'null is not a licence to assume'                   = 'not established'
}
function Find-UnevidencedClaims {
    param([string]$Text)
    $found = [Collections.Generic.List[string]]::new()
    foreach ($claim in $unevidencedClaims.GetEnumerator()) {
        if ($Text.IndexOf([string]$claim.Key, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $found.Add("'$($claim.Key)' -- $($claim.Value)")
        }
    }
    return $found
}
function Test-RoutingResolvesCapabilitiesInsteadOfNamingProducts {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    # Anti-vacuity for the negative half: a forbidden-phrase check that finds
    # nothing proves nothing unless the finder is known to find. Run it against
    # a control string built from the claims themselves.
    $control = ($unevidencedClaims.Keys -join ' / ')
    $controlHits = @(Find-UnevidencedClaims -Text $control)
    if ($unevidencedClaims.Count -eq 0 -or $controlHits.Count -ne $unevidencedClaims.Count) {
        return @{ Passed = $false; Detail = "the forbidden-claim matcher found $($controlHits.Count) of $($unevidencedClaims.Count) claims in a control string that contains all of them, so a clean result against the real section would mean nothing." }
    }
    $missing = @(Find-MissingPhrases -Text $section -Phrases $capabilityResolutionPhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section does not say how a capability is resolved: $($missing -join '; ')" }
    }
    $found = @(Find-UnevidencedClaims -Text $section)
    if ($found.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section asserts a capability this machine does not have: $($found -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: the host's own management CLI is named as a first-party
# surface.
#
# Earned during this work: `claude plugin disable` was asserted not to exist
# and an interactive dialog was used instead, and a hand-written manifest
# checker passed a manifest `claude plugin validate` rejects. Assuming a
# first-party management surface is absent is a repeated, recorded mistake, so
# it gets a line rather than a memory. ---
$managementSurfacePhrases = [ordered]@{
    'the authoritative manifest checker is named' = 'claude plugin validate'
    'the non-interactive management command is named' = 'claude plugin disable'
    'and absence must be confirmed, not assumed'  = 'management surface'
}
function Test-SectionNamesTheHostsOwnManagementCli {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($managementSurfacePhrases.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: the required-phrase set is empty.' }
    }
    $missing = @(Find-MissingPhrases -Text $section -Phrases $managementSurfacePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section does not cover the host's own management CLI: $($missing -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4 (the load-bearing one): continuous execution is gated on the
# host's autonomy profile, and the gate still resolves against the registry.
#
# Both source proposals said "continue directly to the next required task"
# unconditionally. registry/fleet-profile.json marks a third of the fleet
# `interactive`, meaning it must never be dispatched unattended -- so an
# unconditional instruction rendered into those hosts' instruction files tells
# them to do the one thing their profile forbids.
#
# 'interactive' appears as a literal here on purpose, because it is the profile
# whose semantics the policy sentence encodes; what is NOT hardcoded is which
# hosts carry it. The two registry assertions below are what stop the policy and
# the registry drifting apart: rename the profile in fleet-profile.json and the
# knownDefaultProfiles check fires; move every host off it and the anti-vacuity
# check fires, because a gate no host is subject to is a gate nothing tests. ---
$gatedProfileName = 'interactive'
$autonomyGatePhrases = [ordered]@{
    'continuous execution is named as the thing being gated' = 'Continuous execution'
    'the gate resolves against the registry autonomy table'  = 'autonomyProfiles'
    'and the file that carries it'                           = 'registry/fleet-profile.json'
}
function Test-ContinuousExecutionIsGatedOnTheAutonomyProfile {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($knownDefaultProfiles.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/fleet-profile.json declares no autonomyProfiles.knownDefaultProfiles, so any profile name the policy invented would validate.' }
    }
    if ($gatedProfileName -notin $knownDefaultProfiles) {
        return @{ Passed = $false; Detail = "the policy gates on the '$gatedProfileName' profile, which registry/fleet-profile.json no longer lists in autonomyProfiles.knownDefaultProfiles ($($knownDefaultProfiles -join ', ')). The policy and the registry have drifted apart: the sentence rendered into 22 instruction files names a profile nothing assigns." }
    }
    if ($interactiveHostIds.Count -eq 0) {
        return @{ Passed = $false; Detail = "anti-vacuity: registry/fleet-profile.json marks zero hosts '$gatedProfileName', so the gate applies to no host and this behavior would be asserting nothing." }
    }
    $missing = @(Find-MissingPhrases -Text $section -Phrases $autonomyGatePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section does not gate continuous execution: $($missing -join '; ')" }
    }
    # Backticked, not bare: 'interactive' also occurs in ordinary prose in this
    # section, so a bare substring search would stay green with the whole gate
    # sentence deleted.
    if ($section.IndexOf(('`' + $gatedProfileName + '`'), [StringComparison]::Ordinal) -lt 0) {
        return @{ Passed = $false; Detail = "the routing section never names the ``$gatedProfileName`` profile as an identifier, so it does not say which of the $($interactiveHostIds.Count) gated hosts must ask." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: if the policy names a host at all, the registry must agree
# that host is gated.
#
# The proposals named products and hosts inline. A hardcoded host list in a file
# rendered to 22 instruction files goes stale the moment fleet-profile.json
# changes, and stale here means a host is told it may run unattended when its
# profile says otherwise. Naming no host passes; naming a host the registry does
# not mark gated does not. ---
function Get-UngatedHostsNamedIn {
    param([string]$Text)
    $named = @([regex]::Matches($Text, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    return @($named | Where-Object { $_ -in $registeredHostIds -and $_ -notin $interactiveHostIds })
}
function Test-NoHostIsNamedThatTheRegistryDoesNotGate {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($registeredHostIds.Count -eq 0 -or $interactiveHostIds.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: the registered-host set or the gated-host set is empty, so the check below could not distinguish a gated host from an ungated one.' }
    }
    # Prove the finder both finds and discriminates before trusting a clean
    # result: an ungated host in a control string must be flagged, a gated one
    # must not. Otherwise "found nothing" could just mean "looks at nothing".
    $ungatedControl = @($registeredHostIds | Where-Object { $_ -notin $interactiveHostIds })[0]
    $gatedControl = $interactiveHostIds[0]
    # @() at the call site because PowerShell unrolls a one-element result into
    # a bare string, and indexing a bare string yields its first character.
    $controlHits = @(Get-UngatedHostsNamedIn -Text "control: ``$ungatedControl`` and ``$gatedControl``")
    if ($controlHits.Count -ne 1 -or $controlHits[0] -ne $ungatedControl) {
        return @{ Passed = $false; Detail = "the host-name finder returned [$($controlHits -join ', ')] for a control naming the ungated host '$ungatedControl' and the gated host '$gatedControl'; it must return exactly the ungated one, or a clean result against the real section means nothing." }
    }
    $found = @(Get-UngatedHostsNamedIn -Text $section)
    if ($found.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section names host(s) [$($found -join ', ')] that registry/fleet-profile.json does not mark '$gatedProfileName'. Either the registry changed under the policy, or the policy is carrying a hand-maintained host list that will go stale in 22 instruction files at once." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: the new section does not relax the existing escalation gate.
#
# No RED was available for the first half of this: the escalation line predates
# this task. It is a regression guard, proven by mutation instead -- weaken the
# line and this fires. The routing section grants continuous execution on
# autonomous hosts, which is exactly the shape of edit that quietly reads as
# permission to stop asking, so the line it must not override is pinned
# verbatim and the section is required to say it does not widen it. ---
$escalationLine = '- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.'
function Test-EscalationGateIsNotRelaxed {
    if ($policyText.IndexOf($escalationLine, [StringComparison]::Ordinal) -lt 0) {
        return @{ Passed = $false; Detail = "global-agent-policy.md no longer contains the escalation line verbatim: '$escalationLine'. Continuous execution under the routing section must never be the reason this weakened." }
    }
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($section.IndexOf('never widens', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return @{ Passed = $false; Detail = "the routing section does not state that the autonomy gate narrows autonomy and never widens it, so a reader could take 'continue without prompting' as overriding the escalation check." }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-SectionStatesTheRoutingPrinciple
Report 'the policy states the capability-routing principle and its preference order' $r1.Passed $r1.Detail

$r2 = Test-RoutingResolvesCapabilitiesInsteadOfNamingProducts
Report 'routing resolves a capability from hostSurfaces and claims no product capability this machine lacks' $r2.Passed $r2.Detail

$r3 = Test-SectionNamesTheHostsOwnManagementCli
Report "the host's own management CLI is named as a first-party surface" $r3.Passed $r3.Detail

$r4 = Test-ContinuousExecutionIsGatedOnTheAutonomyProfile
Report 'continuous execution is gated on the autonomy profile the registry actually declares' $r4.Passed $r4.Detail

$r5 = Test-NoHostIsNamedThatTheRegistryDoesNotGate
Report 'the routing section names no host the registry does not mark interactive' $r5.Passed $r5.Detail

$r6 = Test-EscalationGateIsNotRelaxed
Report 'the existing escalation gate survives verbatim and the routing section defers to it' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
