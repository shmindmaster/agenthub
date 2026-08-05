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

$fleet  = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
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
# and `false` is never a bare assertion.
#
# `null` is the honest value for "not established". `false` is a claim that
# something was checked and found absent, and a claim needs evidence. Without
# this rule the cheapest way to fill the table is to write false everywhere,
# producing a document that looks verified and is not. ---
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
        $asserted = @($surface.capabilities.PSObject.Properties | Where-Object { $_.Value -is [bool] })
        if ($asserted.Count -gt 0 -and [string]::IsNullOrWhiteSpace($verification)) {
            $bad.Add("$id asserts $($asserted.Count) capability value(s) with no evidence")
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

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
