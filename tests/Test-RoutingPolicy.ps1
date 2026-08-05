#Requires -Version 5.1
<#
Behavior tests for the capability-routing section of global-agent-policy.md.

That file is rendered byte-for-byte into the instruction file of every
registered host that has one, by scripts/Sync-Instructions.ps1, so a sentence
here is a sentence those agent surfaces read. Not all 22: `Sync-Instructions.ps1
-Audit` reported `total=22, workSet=15, skipped=7 (no destination)` on
2026-08-04, so 15 files carry it and seven registered hosts have nowhere to
render it to. Two external proposals argued for native-first routing; their
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
$mcps   = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# The empty-string filter is not decoration, and it belongs on EVERY set derived
# from the registry. Reading a missing property yields $null, and $null in a
# pipeline is one item rather than none -- so renaming `hostId` under
# autonomyProfiles.profiles produced eight empty strings here, not eight host
# ids, and every Count-based emptiness guard below stayed satisfied while the
# derivation had silently become phantom. Review reproduced exactly that:
# interactiveHostIds.Count=8 content=[,,,,,,,] with the suite green.
function Select-NonBlank { param([Parameter(ValueFromPipeline = $true)]$Value) process { if (-not [string]::IsNullOrWhiteSpace([string]$Value)) { $Value } } }

$registeredHostIds    = @(@($agents.activeAgents | ForEach-Object id) + @($agents.inactiveAgents | ForEach-Object id) | Select-NonBlank)
$knownDefaultProfiles = @(@($fleet.autonomyProfiles.knownDefaultProfiles) | Select-NonBlank)
# Derived, never transcribed: which hosts must ask is the registry's answer, and
# a copy of that list in this file would be one more thing to keep in step.
$interactiveHostIds   = @($fleet.autonomyProfiles.profiles |
    Where-Object { [string]$_.defaultProfile -eq 'interactive' } | ForEach-Object { [string]$_.hostId } | Select-NonBlank)

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

# A single bullet, not the whole section. Two bullets cite
# registry/fleet-profile.json, so a section-scoped search for it is satisfied by
# whichever bullet still carries it: delete the citation from the resolution
# bullet and the assertion labelled "names the file that carries it" stays green
# on the gate bullet's copy. Returning $null for zero OR more than one match also
# catches an anchor that has been duplicated across bullets.
function Get-SectionBullets {
    $section = Get-RoutingSection
    if ($null -eq $section) { return @() }
    return @($section -split "`n" | Where-Object { $_.TrimStart().StartsWith('- ') })
}
function Get-SectionBullet {
    param([string]$Anchor)
    $matched = @(Get-SectionBullets | Where-Object { $_.IndexOf($Anchor, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($matched.Count -ne 1) { return $null }
    return [string]$matched[0]
}
# Sentences, because some claims are true or false depending on which verb the
# rest of the sentence is predicated of, and a bullet-level co-occurrence test
# cannot tell those apart.
#
# A plain [.;] split is not sentence granularity, it is punctuation granularity,
# and the difference is exploitable by ordinary prose. `registry/fleet-profile.json`
# is the most-cited token in this section -- three bullets carry it -- so a
# sentence merely mentioning it was cut in half, and a claim written across the
# cut stopped co-occurring with itself:
#
#   "- On Claude Code, `claude plugin disable`, per registry/fleet-profile.json,
#      removes an installed plugin."
#
# split into "...`claude plugin disable`, per registry/fleet-profile" and
# "json, removes an installed plugin" -- disable in one half, removal in the
# other, no violation found. "(since v2.1)" evades identically. A sentence-ending
# period is one followed by whitespace or the end of the bullet; a period inside
# a token is not, and that is the whole of the fix.
function Get-SectionSentences {
    return @(Get-SectionBullets |
        ForEach-Object { $_ -split '(?<=\S)\.(?=\s|$)|;' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ })
}

function Find-MissingPhrases {
    param([string]$Text, $Phrases)
    $missing = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Phrases.GetEnumerator()) {
        if ($Text.IndexOf([string]$entry.Value, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $missing.Add("$($entry.Key) (expected the text to contain '$($entry.Value)')")
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
    'a stated preference order, not a hard tier list' = 'Prefer, in this order'
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
# global-agent-policy.md reaches every host with an instruction-file
# destination, a product name written here is a routing instruction each of
# those surfaces would follow into nothing. ---
$unevidencedClaims = [ordered]@{
    'Claude in Chrome' = 'browser.authenticated is recorded false for claude-cli in registry/fleet-profile.json -- list_connected_browsers returned an empty array, so the product exists and the capability does not'
    'agent teams'      = 'Claude agent teams are experimental and inert unless CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, which is not set on this machine'
    'Computer Use'     = 'computer use is tier-limited here: browsers are read-only and terminals/IDEs reject typing, so it substitutes for neither a browser nor a shell'
    'macOS'            = 'this fleet runs on Windows 11; one source proposal routed to native macOS applications'
}
$capabilityResolutionAnchor = 'hostSurfaces'
$capabilityResolutionPhrases = [ordered]@{
    'it names the registry file that carries the matrix' = 'registry/fleet-profile.json'
    'null is not a licence to assume'                    = 'not established'
    'and false is a checked absence, not a gap'          = 'checked and absent'
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
    $resolutionBullet = Get-SectionBullet -Anchor $capabilityResolutionAnchor
    if ($null -eq $resolutionBullet) {
        return @{ Passed = $false; Detail = "the routing section has no single bullet resolving a capability against '$capabilityResolutionAnchor'; routing by resolved capability is what stops the policy naming products that do not exist on the active surface." }
    }
    $missing = @(Find-MissingPhrases -Text $resolutionBullet -Phrases $capabilityResolutionPhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the capability-resolution bullet does not say how a capability is resolved: $($missing -join '; ')" }
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
# it gets a line rather than a memory.
#
# The removal check below is the second half of the same lesson, and it was
# earned by getting it wrong in this very bullet. `claude plugin --help` reports
# two distinct commands: "disable [options] [plugin]  Disable an enabled plugin"
# and "uninstall|remove [options] <plugin>  Uninstall an installed plugin". A
# policy that says disable removes a plugin sends every rendered instruction
# file an agent that disables a plugin and reports it removed.
#
# The two halves are scoped differently, on purpose, and the difference is the
# whole point. The REQUIRED phrases are matched against the management bullet
# alone: a section-scoped match is satisfied by any neighbour that happens to
# mention the same command, so moving the disable clause out of this bullet into
# a sibling used to leave the suite green. The FORBIDDEN removal language is
# matched against EVERY bullet that names a plugin command, because the false
# claim is exactly as wrong in a sibling bullet as in this one -- scoping that
# half to a single bullet would be the same over-broad/over-narrow mistake in a
# smaller box. Both scenarios were reproduced green before this shape landed.
#
# The anchor is 'management surface' rather than a command name so that removing
# either command from the bullet is caught by the phrase check with a useful
# message, while losing the confirm-before-assuming language is caught by the
# anchor lookup itself. ---
$managementSurfaceAnchor = 'management surface'
$managementSurfacePhrases = [ordered]@{
    'the authoritative manifest checker is named' = 'claude plugin validate'
    # With its argument, because the argument is what the non-interactive claim
    # rests on. `claude plugin disable --help` reports
    # "Usage: claude plugin disable [options] [plugin]" -- SQUARE brackets, so
    # the plugin argument is optional and a bare invocation does prompt. The
    # bullet claimed the command runs "without an interactive dialog" full stop,
    # which is true only when a plugin is named. Requiring the argument form
    # keeps the claim and its condition in the same breath.
    'the non-interactive management command is named, with the argument that makes it non-interactive' = 'claude plugin disable <plugin>'
    # Round 3: the anchor above only proves the words 'management surface' occur.
    # Replacing the instruction with its inversion -- "A management surface may be
    # assumed absent when none is obvious" -- keeps the anchor and used to pass,
    # while the failure message claimed the check verified the instruction. The
    # instruction is now pinned, so the message and the check say the same thing.
    'and it is the confirm-before-assuming instruction, not merely the words' = 'Confirm that a management surface is absent'
}
# The claim, not a token that happens to sit near it. This used to require the
# literal 'claude plugin' to co-occur with 'remov', so "disabling a plugin
# removes an installed plugin" -- the same false claim in plain English -- passed,
# and so did "disabling a plugin uninstalls it", which carries no 'remov' at all.
# Meanwhile a TRUE sentence naming the real removal command failed, so the section
# could never document it.
#
# What is actually false is predicating removal of DISABLING. So: a sentence that
# talks about disabling AND about removal is the violation, and a sentence that
# talks about removal alone is fine -- which is exactly what
# "`claude plugin uninstall|remove` removes an installed plugin" is.
$disableLanguage = @('disabl')
$removalLanguage = @('remov', 'uninstall')
function Find-DisableRemovalConflations {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($sentence in Get-SectionSentences) {
        $saysDisable = @($disableLanguage | Where-Object { $sentence.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($saysDisable.Count -eq 0) { continue }
        $saysRemoval = @($removalLanguage | Where-Object { $sentence.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($saysRemoval.Count -gt 0) { $bad.Add($sentence) }
    }
    return $bad
}
function Test-SectionNamesTheHostsOwnManagementCli {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($managementSurfacePhrases.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: the required-phrase set is empty.' }
    }
    $managementBullet = Get-SectionBullet -Anchor $managementSurfaceAnchor
    if ($null -eq $managementBullet) {
        # Says only what it checked. The instruction itself is pinned by the
        # phrase table below, not here.
        return @{ Passed = $false; Detail = "the words '$managementSurfaceAnchor' do not appear in exactly one bullet of the routing section, so there is no single bullet to hold the confirm-before-assuming instruction. Assuming a first-party management surface does not exist is the recorded mistake that bullet exists to prevent." }
    }
    $missing = @(Find-MissingPhrases -Text $managementBullet -Phrases $managementSurfacePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the management-CLI bullet is incomplete: $($missing -join '; '). Bullet as written: '$managementBullet'" }
    }
    $conflating = @(Find-DisableRemovalConflations)
    if ($conflating.Count -gt 0) {
        return @{ Passed = $false; Detail = "a sentence in the routing section predicates removal of disabling: '$($conflating[0])'. Disabling and uninstalling are different commands, so say what each one does in its own sentence rather than in one clause. Stating what the removal command removes, without mentioning disabling in the same sentence, is fine and does not trip this." }
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
# Token presence alone is not a gate assertion. Review rewrote this bullet to say
# continuous execution "is available on every host", that the autonomy profile
# "records context only", and that on an `interactive` host you should "continue
# as well" -- an exact inversion of the requirement, with every token this test
# used to look for still in place, and the suite reported 6 passed, 0 failed. An
# assertion that passes over an inverted gate is worse than no assertion, because
# it certifies the inversion. The two phrases that carry the conditional are
# pinned first, and the whole set is matched against the gate bullet alone. ---
$gatedProfileName = 'interactive'
$autonomyGateAnchor = 'Continuous execution'
$autonomyGatePhrases = [ordered]@{
    'the permission is conditional, not a grant'             = 'applies only where'
    'and it says what to do when the condition fails'        = 'ask instead'
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
        return @{ Passed = $false; Detail = "the policy gates on the '$gatedProfileName' profile, which registry/fleet-profile.json no longer lists in autonomyProfiles.knownDefaultProfiles ($($knownDefaultProfiles -join ', ')). The policy and the registry have drifted apart: the sentence rendered into the fleet's instruction files names a profile nothing assigns." }
    }
    if ($interactiveHostIds.Count -eq 0) {
        return @{ Passed = $false; Detail = "anti-vacuity: registry/fleet-profile.json marks zero hosts '$gatedProfileName', so the gate applies to no host and this behavior would be asserting nothing." }
    }
    $gateBullet = Get-SectionBullet -Anchor $autonomyGateAnchor
    if ($null -eq $gateBullet) {
        return @{ Passed = $false; Detail = "the routing section has no single bullet gating '$autonomyGateAnchor'. $($interactiveHostIds.Count) of the fleet's hosts are marked '$gatedProfileName' and must never be dispatched unattended; without this bullet their instruction files carry an unconditional licence to continue." }
    }
    $missing = @(Find-MissingPhrases -Text $gateBullet -Phrases $autonomyGatePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the autonomy-gate bullet does not gate continuous execution: $($missing -join '; '). Bullet as written: '$gateBullet'" }
    }
    # Backticked, not bare: 'interactive' also occurs in ordinary prose in this
    # section, so a bare substring search would stay green with the whole gate
    # sentence deleted.
    if ($gateBullet.IndexOf(('`' + $gatedProfileName + '`'), [StringComparison]::Ordinal) -lt 0) {
        return @{ Passed = $false; Detail = "the autonomy-gate bullet never names the ``$gatedProfileName`` profile as an identifier, so it does not say which of the $($interactiveHostIds.Count) gated hosts must ask." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: if the policy writes a host ID as an identifier, the registry
# must agree that host is gated.
#
# The proposals named products and hosts inline. A hardcoded host list in a file
# rendered into the fleet's instruction files goes stale the moment
# fleet-profile.json changes, and stale here means a host is told it may run
# unattended when its profile says otherwise.
#
# The scope is BACKTICKED HOST IDS -- the identifier form the registry itself
# uses -- and the label says so, because the section does name a host in prose:
# "On Claude Code, `claude plugin validate` ...", and `claude` is not marked
# interactive. That sentence is required content (the management-CLI bullet has
# to say whose CLI it documents), so widening this guard to display names in
# prose would forbid the thing Behavior 3 requires. The guard was already
# id-scoped; what was wrong was the label claiming it covered every naming of a
# host. An identifier is what a reader would copy into a config or a dispatch
# list, and a stale copy of the gated-host list is what this exists to stop. ---
function Get-UngatedHostIdsWrittenIn {
    param([string]$Text)
    $named = @([regex]::Matches($Text, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    return @($named | Where-Object { $_ -in $registeredHostIds -and $_ -notin $interactiveHostIds })
}
function Test-NoHostIdIsWrittenThatTheRegistryDoesNotGate {
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
    $controlHits = @(Get-UngatedHostIdsWrittenIn -Text "control: ``$ungatedControl`` and ``$gatedControl``")
    if ($controlHits.Count -ne 1 -or $controlHits[0] -ne $ungatedControl) {
        return @{ Passed = $false; Detail = "the host-id finder returned [$($controlHits -join ', ')] for a control writing the ungated host id '$ungatedControl' and the gated host id '$gatedControl'; it must return exactly the ungated one, or a clean result against the real section means nothing." }
    }
    $found = @(Get-UngatedHostIdsWrittenIn -Text $section)
    if ($found.Count -gt 0) {
        return @{ Passed = $false; Detail = "the routing section writes host id(s) [$($found -join ', ')] as identifiers, and registry/fleet-profile.json does not mark them '$gatedProfileName'. Either the registry changed under the policy, or the policy is carrying a hand-maintained host list that will go stale in every rendered instruction file at once." }
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
#
# Round 3, self-found rather than flagged: this checked only 'never widens',
# anywhere in the section. Keeping that phrase while deleting the clause that
# says the escalation check survives -- "...never widens it: that is all." --
# left the deference gone and the suite green. The message named two things and
# the check verified one of them. Both are pinned now, in the gate bullet where
# they belong. ---
$escalationLine = '- Ask before destructive, production-affecting, externally communicating, credential-changing, or scope-expanding operations unless the task explicitly authorizes them.'
$deferencePhrases = [ordered]@{
    'the gate is stated as a narrowing, not a licence'    = 'never widens'
    'and the escalation check is stated to survive it'    = 'applies on every host'
}
function Test-EscalationGateIsNotRelaxed {
    if ($policyText.IndexOf($escalationLine, [StringComparison]::Ordinal) -lt 0) {
        return @{ Passed = $false; Detail = "global-agent-policy.md no longer contains the escalation line verbatim: '$escalationLine'. Continuous execution under the routing section must never be the reason this weakened." }
    }
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    if ($deferencePhrases.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: the required-phrase set is empty.' }
    }
    $gateBullet = Get-SectionBullet -Anchor $autonomyGateAnchor
    if ($null -eq $gateBullet) {
        return @{ Passed = $false; Detail = "the routing section has no single bullet anchored on '$autonomyGateAnchor', so nothing carries the statement that the gate does not override the escalation check." }
    }
    $missing = @(Find-MissingPhrases -Text $gateBullet -Phrases $deferencePhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the autonomy-gate bullet does not defer to the escalation check: $($missing -join '; '). A reader could take 'continue without prompting' as overriding it. Bullet as written: '$gateBullet'" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 7: the preference order says which of two first-party providers
# wins, and cites the registry rule that decides it.
#
# The two halves of this branch contradicted each other on the one decision it
# exists to make. The ordering bullet ranked "first-party plugins, skills, and
# MCP servers" ABOVE "a first-party browser" and closed "take the highest step
# that can" -- while all three browser-toolkit skills resolve the opposite way,
# the surface's own browser first and the `chrome-devtools` MCP server only as a
# fallback. Neither artifact defined "first-party", so both readings were
# defensible, and an agent on claude-cli or codex-desktop (both recording
# `browser.isolated: true`) reading only the policy would start the npx server
# the skills exist to avoid. The policy reaches all hosts; the skills reach only
# hosts carrying browser-toolkit, so the policy is the half that had to move.
#
# The tiebreak is not a preference invented here: registry/mcps.json ->
# activationPolicy prefers a shared remote endpoint over a local process, one
# shared local process over per-host duplicates, and a capability-invoked start
# over a session-start one. This behavior checks the policy states the tiebreak
# AND that the registry still says what the policy cites it as saying, so the
# two cannot drift apart silently.
#
# Scope, because the label used to overstate it: this reads global-agent-policy.md
# and registry/mcps.json and opens no SKILL.md, so it establishes nothing about
# what the skills do. The nearest thing that is enforced is behavior 8 of
# tests/Test-CapabilityRouting.ps1, 'each skill declares its surface-provided
# step before its local-fallback step' -- note "declares": since the markers
# went in, that check reads each step's declared role and no longer verifies
# the step's prose argues for the role it claims. So no test in this repository
# establishes that the skills' SENTENCES resolve the way the policy does; a
# marker on the wrong step would pass both. Detecting that would mean
# re-deriving a role from prose, which failed here badly enough to be worth not
# repeating. Broadening this check would duplicate behavior 8 without closing
# that gap. ---
$preferenceOrderAnchor = 'Prefer, in this order'
$activationTiebreakPhrases = [ordered]@{
    'a capability the surface already provides outranks one that must be started' = 'already provides'
    'the tiebreak names the registry rule that decides it'                        = 'activationPolicy'
    'and the file that carries that rule'                                         = 'registry/mcps.json'
}
$sharedRemotePreference = 'shared-remote'
$onDemandLocalPreference = 'on-demand-local'
function Test-PreferenceOrderRanksSurfaceProvidedAboveLocallyStarted {
    $section = Get-RoutingSection
    if ($null -eq $section) {
        return @{ Passed = $false; Detail = "global-agent-policy.md has no '$routingHeading' section." }
    }
    $activationPreference = @(@($mcps.activationPolicy.preferenceOrder) | Select-NonBlank)
    if ($activationPreference.Count -eq 0) {
        return @{ Passed = $false; Detail = 'anti-vacuity: registry/mcps.json declares no activationPolicy.preferenceOrder, so the policy would be citing a rule that no longer exists and this check would be comparing against nothing.' }
    }
    if ($activationPreference[0] -ne $sharedRemotePreference -or $onDemandLocalPreference -notin $activationPreference) {
        return @{ Passed = $false; Detail = "registry/mcps.json activationPolicy.preferenceOrder is [$($activationPreference -join ', ')], which no longer prefers '$sharedRemotePreference' over '$onDemandLocalPreference'. The routing bullet tells every host that a locally started server is the fallback because of that rule; if the rule inverted, the sentence rendered into the fleet's instruction files is now false." }
    }
    $orderBullet = Get-SectionBullet -Anchor $preferenceOrderAnchor
    if ($null -eq $orderBullet) {
        return @{ Passed = $false; Detail = "the routing section has no single bullet anchored on '$preferenceOrderAnchor', so there is no ordering bullet to carry the tiebreak between a capability the surface provides and one a local server would provide." }
    }
    $missing = @(Find-MissingPhrases -Text $orderBullet -Phrases $activationTiebreakPhrases)
    if ($missing.Count -gt 0) {
        return @{ Passed = $false; Detail = "the ordering bullet does not resolve first-party surface against first-party server: $($missing -join '; '). Without it the bullet ranks MCP servers above a browser while packages/browser-toolkit's skills resolve the surface's own browser first, and a host reading only the policy starts a local process it does not need. Bullet as written: '$orderBullet'" }
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

$r5 = Test-NoHostIdIsWrittenThatTheRegistryDoesNotGate
Report 'the routing section writes no host ID as an identifier that the registry does not mark interactive' $r5.Passed $r5.Detail

$r6 = Test-EscalationGateIsNotRelaxed
Report 'the existing escalation gate survives verbatim and the routing section defers to it' $r6.Passed $r6.Detail

$r7 = Test-PreferenceOrderRanksSurfaceProvidedAboveLocallyStarted
Report 'the policy ranks a capability the surface already provides above one a local server would start, and cites the registry rule that still says so' $r7.Passed $r7.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
