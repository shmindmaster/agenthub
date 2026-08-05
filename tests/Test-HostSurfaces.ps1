#Requires -Version 5.1
<#
Behavior tests for fleet-profile.json's hostSurfaces table.

The table exists because a registered host is not one uniform capability
target: Codex CLI and the ChatGPT desktop app read the same ~/.codex config
but do not expose the same tools. Routing a task to a capability the active
surface lacks fails by finding nothing, which is the quiet kind of failure.

What these tests defend is the table's honesty rather than its contents. A
capability matrix is only worth having if `false` means "checked, absent" and
`null` means "not established" -- the moment an unchecked entry can be written
as `false`, the table reads as evidence while being guesswork.

Run: pwsh -NoProfile -File tests/Test-HostSurfaces.ps1
     powershell.exe -NoProfile -File tests/Test-HostSurfaces.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

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

# -Encoding UTF8 is not decoration: Windows PowerShell 5.1 decodes a BOM-less
# file as the ANSI code page, so the first non-ASCII character to enter the
# registry would reach ConvertFrom-Json as mojibake under 5.1 and intact under
# 7. tests/Test-CapabilityRouting.ps1 already reads this same file that way;
# matching it means the two suites cannot read the same bytes differently.
$fleet  = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw | ConvertFrom-Json

# @($null) | ForEach-Object id emits a phantom empty entry rather than
# nothing, and @($null) has Count -eq 1, not 0. If the `id` key under
# activeAgents/inactiveAgents were ever missing or renamed, the naive
# build below would silently yield a set of blanks instead of an empty
# set. Filtering out blank/whitespace entries makes a missing key produce
# a genuinely empty collection, so the anti-vacuity guard right after this
# can actually detect that case instead of finding phantom "coverage".
$rawHostIds = @($agents.activeAgents | ForEach-Object { [string]$_.id }) + @($agents.inactiveAgents | ForEach-Object { [string]$_.id })
$registeredHostIds = @($rawHostIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

function Get-Surfaces { @($fleet.hostSurfaces.surfaces) }

# --- Guard (anti-vacuity for the host-id set itself): registeredHostIds
# must be non-empty, or every "-notin $registeredHostIds" check below in
# Behavior 1 passes over nothing -- a bogus or unregistered hostId in
# fleet-profile.json would look identical to a genuinely registered one
# because there would be no real ids left to fail the membership test
# against. This is the guard the phantom-null shape above would otherwise
# defeat. ---
function Test-RegisteredHostIdSetIsNonEmpty {
    if ($registeredHostIds.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registeredHostIds resolved to an empty set from agents.json activeAgents/inactiveAgents. An empty set here makes the unregistered-hostId membership check below vacuous: it would pass any hostId, real or bogus, because there is nothing left to fail against.' }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 1: the table exists, is non-empty, and every surface names a
# registered host. A surface pointing at a host that no longer exists routes
# nowhere while still looking like coverage. ---
function Test-SurfacesResolveToRegisteredHosts {
    $surfaces = Get-Surfaces
    if ($surfaces.Count -eq 0) {
        return @{ Passed = $false; Detail = 'fleet-profile.json declares no hostSurfaces.surfaces. An empty capability matrix must not pass as a checked one.' }
    }
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($surface in $surfaces) {
        if ([string]::IsNullOrWhiteSpace([string]$surface.surfaceId)) { $bad.Add('a surface entry has no surfaceId'); continue }
        if ([string]$surface.hostId -notin $registeredHostIds) {
            $bad.Add("$($surface.surfaceId) -> unregistered hostId '$($surface.hostId)'")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: every declared capability is a known one.
#
# A typo'd capability name is worse than a missing entry: a router looking up
# "browser.authenticated" against a table that says "browser.authenicated"
# finds nothing and falls through to a default, silently. ---
function Test-CapabilityNamesAreKnown {
    $known = @($fleet.hostSurfaces.knownCapabilities)
    if ($known.Count -eq 0) {
        return @{ Passed = $false; Detail = 'knownCapabilities is missing or empty, so any capability name would validate and the vocabulary check below is vacuous.' }
    }
    $unknown = [Collections.Generic.List[string]]::new()
    foreach ($surface in Get-Surfaces) {
        foreach ($property in @($surface.capabilities.PSObject.Properties)) {
            if ($property.Name -notin $known) {
                $unknown.Add("$($surface.surfaceId) declares unknown capability '$($property.Name)'")
            }
        }
    }
    # Every known capability must also be described, or the vocabulary is
    # names without meanings and two authors will read one name differently.
    foreach ($capability in $known) {
        if (-not $fleet.hostSurfaces.capabilityMeanings.PSObject.Properties[$capability]) {
            $unknown.Add("known capability '$capability' has no entry in capabilityMeanings")
        }
    }
    if ($unknown.Count -gt 0) { return @{ Passed = $false; Detail = ($unknown -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3 (the load-bearing one): every surface carries dated evidence,
# and no single capability value is asserted bare.
#
# `null` is the honest value for "not established". `false` is a claim that
# something was checked and found absent, and a claim needs evidence. Without
# this rule the cheapest way to fill the table is to write false everywhere,
# producing a document that looks verified and is not.
#
# The claim is per capability, so the check has to be per capability. It used to
# be per surface: one non-empty `verification` string on the surface entry, after
# which every boolean underneath it counted as evidenced. Review demonstrated what
# that buys -- a mutation writing EIGHT evidence-free `false` values across the
# matrix passed this behavior cleanly, because each surface still carried its
# original verification sentence, one written about something else entirely. That
# is how codex-cli and codex-ide came to assert `computer.gui: false` backed by a
# sentence about Browser availability; both are now `null`, which is what they
# always were.
#
# Prose matching was tried and rejected before landing this shape. Requiring the
# verification text to name the capability fails six honestly-evidenced entries
# whose wording predates the rule; matching the capability family instead accepts
# `computer.gui: false` on the strength of the word "Computer" in the sentence
# "Computer Use surfaces were not probed ... recorded null rather than assumed" --
# a guard that reads as evidence while being noise. So the attribution is data,
# not inference: `capabilityEvidence` is keyed by capability name.
#
# Its keys must be exactly the capabilities this surface asserts:
#   * a bool with no entry is a bare claim -- the failure names the surface AND
#     the capability, because "this surface is deficient" is not actionable;
#   * an entry against a `null` is evidence attached to a value nobody asserted,
#     which is exactly what a later `false` would silently inherit. Removing it is
#     the cost of demoting a value, and it keeps `null` free of any requirement to
#     write anything -- an author must never be pushed toward `false` to dodge
#     friction. Why a value is not established belongs in `capabilityNotEstablished`,
#     which is a note and is deliberately not evidence.
# The surface-level `verification`/`verifiedOn` stay required: they date the visit
# and carry the narrative no single capability owns. ---
function Test-EverySurfaceCarriesDatedEvidence {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($surface in Get-Surfaces) {
        $id = [string]$surface.surfaceId
        $verification = [string]$surface.verification
        $verifiedOn = [string]$surface.verifiedOn

        if ([string]::IsNullOrWhiteSpace($verification)) {
            $bad.Add("$id declares no verification")
        }
        if ($verifiedOn -notmatch '^\d{4}-\d{2}-\d{2}$') {
            $bad.Add("$id has no ISO verifiedOn date (found '$verifiedOn'); an undated check cannot be audited for staleness")
        }

        $evidence = $surface.capabilityEvidence
        foreach ($property in @($surface.capabilities.PSObject.Properties)) {
            $capability = $property.Name
            $backing = $null
            if ($evidence) {
                $entry = $evidence.PSObject.Properties[$capability]
                if ($entry) { $backing = [string]$entry.Value }
            }
            if ($property.Value -is [bool]) {
                if ([string]::IsNullOrWhiteSpace($backing)) {
                    $value = ([string]$property.Value).ToLowerInvariant()
                    $bad.Add("$id asserts $capability = $value with no capabilityEvidence entry for $capability; the surface's verification backs the surface, not this value")
                }
            } elseif ($null -eq $property.Value -and -not [string]::IsNullOrWhiteSpace($backing)) {
                $bad.Add("$id records $capability as not established (null) yet carries capabilityEvidence for $capability; evidence for a value nobody asserted is what a later false would inherit without anyone writing it")
            }
        }
        if ($evidence) {
            foreach ($entry in @($evidence.PSObject.Properties)) {
                if (-not $surface.capabilities.PSObject.Properties[$entry.Name]) {
                    $bad.Add("$id records capabilityEvidence for '$($entry.Name)', which it does not declare under capabilities; a mistyped key leaves the real capability unbacked while looking backed")
                }
            }
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4 (anti-vacuity): the table must actually assert something.
#
# Behaviors 1-3 all pass trivially against a table of nothing but nulls. This
# requires at least one real true AND one real false somewhere in the matrix,
# so the table is proven capable of distinguishing present from absent. The
# recorded codex-cli/browser false and claude-cli/computer.gui true are the
# current witnesses. ---
function Test-TableDistinguishesPresentFromAbsent {
    $values = @(Get-Surfaces | ForEach-Object { $_.capabilities.PSObject.Properties } | ForEach-Object { $_.Value })
    $trues  = @($values | Where-Object { $_ -is [bool] -and $_ }).Count
    $falses = @($values | Where-Object { $_ -is [bool] -and -not $_ }).Count
    if ($trues -eq 0 -or $falses -eq 0) {
        return @{ Passed = $false; Detail = "the matrix records $trues true and $falses false values. It needs at least one of each, or it is not distinguishing available from unavailable and the other behaviors pass over an empty claim." }
    }
    return @{ Passed = $true; Detail = $null }
}

# Renders a capability value for a failure message. ConvertTo-Json is used so a
# JSON string "false" prints quoted and cannot be mistaken for a real false. The
# .NET type name is deliberately not printed: ConvertFrom-Json yields Int32 for
# a JSON number under 5.1 and Int64 under 7, so a message naming the type would
# differ by shell for identical registry bytes.
function Format-CapabilityValue([object]$Value) {
    if ($null -eq $Value) { return 'null' }
    return [string](ConvertTo-Json -InputObject $Value -Compress -Depth 3 -WarningAction SilentlyContinue)
}

# --- Behavior 5: a capability value is true, false, or null, and nothing else.
#
# Behavior 3 requires evidence only where the value `-is [bool]`, and Behavior 4
# counts witnesses the same way. Neither establishes that a value IS a bool, and
# nothing else did either. So `"browser.isolated": "false"` -- the JSON string --
# with its capabilityEvidence entry deleted passed the whole suite: the string is
# not a bool, so no evidence was demanded of it, and it is not null, so the
# stray-evidence branch stayed quiet. The unevidenced absence claim survives; it
# is just spelled differently. It is worse than that for a consumer, because
# `if ($surface.capabilities.'browser.isolated')` reads the non-empty string
# "false" as TRUE -- the table would then route work to a browser that the same
# line was trying to say is absent.
#
# The permitted set is exhaustive on purpose. A number, a string, an array or a
# nested object in this position is not a capability answer in any reading, and
# guessing which of the three it meant is exactly the assumption this table
# exists to forbid.
#
# Anti-vacuity: this iterates the same capability-value set that Behavior 4
# already fails unless it holds at least one real true and one real false, so
# the set is proven non-empty there rather than re-proven here. ---
function Test-CapabilityValuesAreBooleanOrNull {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($surface in Get-Surfaces) {
        $id = [string]$surface.surfaceId
        foreach ($property in @($surface.capabilities.PSObject.Properties)) {
            if ($null -eq $property.Value -or $property.Value -is [bool]) { continue }
            $bad.Add("$id records $($property.Name) = $(Format-CapabilityValue $property.Value), which is not true, false or null; a capability answer has exactly those three values, and anything else is read by neither the evidence rule nor a consumer the way its author meant it")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: a capabilityNotEstablished key must name a capability this
# surface actually records as null.
#
# The note's TEXT stays unread here, and must. Reading it would hand a sentence
# the evidentiary authority the design withholds from it -- the failure this
# table was rebuilt around is a family matcher accepting `computer.gui: false`
# on the strength of the word "Computer" appearing in a sentence saying that
# capability was never probed. Keys are structure, so they can be checked
# without anyone interpreting anything.
#
# What drifts without this: promote codex-cli's computer.gui back to false with
# a fresh capabilityEvidence entry and leave the note saying Computer Use was
# never probed from this surface, and the suite reports 5 passed while the
# registry asserts both at once. The note outlives the null it explains, and it
# is the more careful of the two claims that gets silently overruled.
#
# One direction only: a null is NOT required to carry a note. Requiring one
# would put a writing cost on the honest value that `false` does not pay, which
# is the incentive this table needs inverted, not reproduced.
#
# Anti-vacuity: the property name is read from data, so a rename in the registry
# or a typo here would make this iterate nothing forever while still printing
# PASS -- the shape of failure this repo keeps producing. So the union of note
# keys across the table must be non-empty. That is a witness that the mechanism
# is still reachable, not a demand that any particular null be annotated; if the
# last note is one day legitimately deleted, delete this behavior with it rather
# than write a note to satisfy it. ---
function Test-NotEstablishedNotesAnnotateOnlyNulls {
    $bad = [Collections.Generic.List[string]]::new()
    $noteKeys = 0
    foreach ($surface in Get-Surfaces) {
        $id = [string]$surface.surfaceId
        $notes = $surface.capabilityNotEstablished
        if (-not $notes) { continue }
        foreach ($note in @($notes.PSObject.Properties)) {
            $noteKeys++
            $declared = $surface.capabilities.PSObject.Properties[$note.Name]
            if (-not $declared) {
                $bad.Add("$id notes '$($note.Name)' under capabilityNotEstablished, a capability it does not declare under capabilities at all; the note explains the absence of something this surface never recorded")
            } elseif ($null -ne $declared.Value) {
                $bad.Add("$id notes '$($note.Name)' as not established while capabilities records $($note.Name) = $(Format-CapabilityValue $declared.Value); one of the two is stale and the table now asserts both. Delete the note when the value is promoted -- that is the cost of promoting it")
            }
        }
    }
    if ($noteKeys -eq 0) {
        return @{ Passed = $false; Detail = 'no surface carries a single capabilityNotEstablished key, so this check iterated nothing and would report PASS against any note at all. Either the registry key was renamed and this behavior no longer reads it, or every note is gone and this behavior should be deleted rather than left as decoration.' }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

$r0 = Test-RegisteredHostIdSetIsNonEmpty
Report 'the registered host-id set is non-empty' $r0.Passed $r0.Detail

$r1 = Test-SurfacesResolveToRegisteredHosts
Report 'every declared surface resolves to a registered host' $r1.Passed $r1.Detail

$r2 = Test-CapabilityNamesAreKnown
Report 'every capability name is known and carries a stated meaning' $r2.Passed $r2.Detail

$r3 = Test-EverySurfaceCarriesDatedEvidence
Report 'every surface carries dated evidence and no capability is asserted bare' $r3.Passed $r3.Detail

$r4 = Test-TableDistinguishesPresentFromAbsent
Report 'the matrix records both an available and an unavailable capability' $r4.Passed $r4.Detail

$r5 = Test-CapabilityValuesAreBooleanOrNull
Report 'every capability value is a real boolean or a real null, not a lookalike' $r5.Passed $r5.Detail

$r6 = Test-NotEstablishedNotesAnnotateOnlyNulls
Report 'every capabilityNotEstablished key names a capability that surface still records as null' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
