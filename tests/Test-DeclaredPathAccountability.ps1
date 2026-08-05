#Requires -Version 5.1
<#
Behavior tests for registry/agents.json: every declared native path that is
absent from disk must say why.

WHY THIS FILE EXISTS

registry/agents.json declares absolute paths for each host's settings,
instructions, skills, agents, plugins, hooks and rules directories. Some of
those paths do not exist on disk, and an absent path is ambiguous in a way
a present one is not: it is either a correct path for a feature nobody has
deployed yet, or a wrong path nobody has checked. Nothing distinguishes the
two by looking.

That ambiguity has already cost this repo once, in the opposite direction.
gemini.agentsDirNote records it: an earlier edit changed that path "on the
mistaken basis that a directory absent from disk must be wrong", and had to
be reverted the same day. Gemini CLI does document ~/.gemini/agents; the
directory was simply empty because AgentHub's own subagents ship as
extension bundles instead. Absence proved nothing, and treating it as
evidence broke a correct entry.

Measured 2026-08-05: 18 declared paths were absent and only 2 carried a
note. This file requires the other 16 to be accounted for, and keeps every
future one accounted for.

SCOPE, STATED SO IT IS NOT MISTAKEN FOR MORE

A note is not proof the path is right. It is a record that somebody looked,
and what they found -- including "could not establish", which is a valid
and expected finding for the more obscure hosts in this fleet. The rule
this file enforces is only that the looking happened and left a trace.

THIS TEST READS THE LOCAL FILESYSTEM, DELIBERATELY

registry/agents.json is not portable: it carries absolute paths under a
specific user profile and a top-level userProfile field to match. This test
is therefore machine-local by construction, exactly like the inventory
command it complements. On a different machine a different set of paths
would be absent and a different set of notes required. That is correct
behavior for a personal fleet registry, not a portability defect -- but it
does mean this file asserts something about THIS machine, and a reader
should not mistake a pass here for a claim about anyone else's.

Not a Pester suite: this repo carries no Pester dependency. Same
accumulate-and-report idiom as the rest of tests/.

Run: pwsh -NoProfile -File tests/Test-DeclaredPathAccountability.ps1
     powershell.exe -NoProfile -File tests/Test-DeclaredPathAccountability.ps1
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

# -Encoding UTF8 is load-bearing under Windows PowerShell 5.1, which
# otherwise decodes this BOM-less UTF-8 file as the ANSI code page.
# tests/Test-FileEncodingDiscipline.ps1 enforces it repo-wide.
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Classify every declared path field. A field is a "path field" when its
# value looks like an absolute Windows path; nativePaths also carries
# non-path scalars (instructionHeader, instructionFormat) and the *Note
# annotations themselves, none of which name a filesystem location.
# ---------------------------------------------------------------------------
$pathFields = [Collections.Generic.List[object]]::new()
foreach ($agent in $agents.activeAgents) {
    if (-not $agent.nativePaths) { continue }
    foreach ($property in $agent.nativePaths.PSObject.Properties) {
        if ($property.Name -like '*Note') { continue }
        $value = $property.Value
        if ($value -isnot [string]) { continue }
        if ($value -notmatch '^(?:[A-Za-z]:\\|\\\\)') { continue }
        $noteProperty = $agent.nativePaths.PSObject.Properties["$($property.Name)Note"]
        $pathFields.Add([pscustomobject]@{
            HostId  = $agent.id
            Field   = $property.Name
            Path    = $value
            Present = (Test-Path -LiteralPath $value)
            Note    = if ($noteProperty) { [string]$noteProperty.Value } else { $null }
        })
    }
}

$absent = @($pathFields | Where-Object { -not $_.Present })

# ---------------------------------------------------------------------------
# Behavior 1: every absent declared path carries a note.
# ---------------------------------------------------------------------------
function Test-EveryAbsentPathIsAccountedFor {
    $unaccounted = @($absent | Where-Object { [string]::IsNullOrWhiteSpace($_.Note) })
    if ($unaccounted.Count -gt 0) {
        $rendered = @($unaccounted | ForEach-Object { "$($_.HostId).$($_.Field) ($($_.Path))" })
        return @{ Passed = $false; Detail = "$($unaccounted.Count) declared path(s) are absent from disk with no <field>Note saying whether the path is correct-but-unused or simply wrong: $($rendered -join '; '). Research the host's own documentation and add the note. 'Could not establish from official docs' is a valid note; silence is not, because it is indistinguishable from nobody having looked." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 2: no note is orphaned.
#
# A <field>Note whose subject no longer exists is a sentence explaining a
# path that has been renamed or deleted out from under it -- still reading
# as an account of something, while accounting for nothing.
#
# The match is by PREFIX, not equality, and that is not laziness. The first
# version of this behavior required an exactly-named sibling and
# immediately flagged devin.mcpNote, whose subject is the mcpKey field --
# a real, current, correctly-named pair. Demanding exact equality would
# have meant renaming a good registry field to satisfy a test, which is the
# tail wagging the dog. A prefix rule still catches the case that matters:
# a note whose subject has vanished entirely.
# ---------------------------------------------------------------------------
function Test-NoNoteIsOrphaned {
    $orphans = [Collections.Generic.List[string]]::new()
    foreach ($agent in $agents.activeAgents) {
        if (-not $agent.nativePaths) { continue }
        $subjects = @($agent.nativePaths.PSObject.Properties | Where-Object { $_.Name -notlike '*Note' } | ForEach-Object { $_.Name })
        foreach ($property in $agent.nativePaths.PSObject.Properties) {
            if ($property.Name -notlike '*Note') { continue }
            $stem = $property.Name.Substring(0, $property.Name.Length - 4)
            if (-not @($subjects | Where-Object { $_ -eq $stem -or $_.StartsWith($stem) }).Count) {
                $orphans.Add("$($agent.id).$($property.Name) (no field named '$stem' or starting with it)")
            }
        }
    }
    if ($orphans.Count -gt 0) {
        return @{ Passed = $false; Detail = "note(s) annotating a field that no longer exists: $($orphans -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 3: a note says something a later reader can act on.
#
# Deliberately weak -- this cannot judge whether a note is TRUE, only
# whether it is substantive enough to be checkable. A one-word note passes
# nothing on to the next person.
# ---------------------------------------------------------------------------
function Test-EveryNoteIsSubstantive {
    $thin = [Collections.Generic.List[string]]::new()
    foreach ($field in $pathFields) {
        if ([string]::IsNullOrWhiteSpace($field.Note)) { continue }
        if ($field.Note.Trim().Length -lt 40) {
            $thin.Add("$($field.HostId).$($field.Field): '$($field.Note.Trim())'")
        }
    }
    if ($thin.Count -gt 0) {
        return @{ Passed = $false; Detail = "note(s) too short to tell a later reader what was checked or what was found: $($thin -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 4: anti-vacuity. Behaviors 1 and 3 iterate sets that a broken
# read, a renamed schema key, or a changed path shape would silently empty,
# and an empty loop passes without asserting anything.
# ---------------------------------------------------------------------------
function Test-ScanExaminedRealInput {
    if (@($agents.activeAgents).Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/agents.json yielded zero activeAgents; every other behavior here iterates that empty set and passes trivially.' }
    }
    if ($pathFields.Count -eq 0) {
        return @{ Passed = $false; Detail = "found $(@($agents.activeAgents).Count) active agents but zero nativePaths fields that look like an absolute path. The path-shape filter or the schema has changed, and behaviors 1 and 3 are now asserting over nothing." }
    }
    $present = @($pathFields | Where-Object { $_.Present })
    if ($present.Count -eq 0) {
        return @{ Passed = $false; Detail = "not one of $($pathFields.Count) declared paths exists on disk. That is far more likely a broken Test-Path or a registry pointing at the wrong user profile than a fleet with nothing deployed." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------

$behaviors = @(
    @{ Name = 'every absent declared path carries a note explaining it'; Run = { Test-EveryAbsentPathIsAccountedFor } }
    @{ Name = 'no note annotates a field that no longer exists';         Run = { Test-NoNoteIsOrphaned } }
    @{ Name = 'every note is substantive enough to act on';              Run = { Test-EveryNoteIsSubstantive } }
    @{ Name = 'the scan examined real agents and real paths';            Run = { Test-ScanExaminedRealInput } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "SCOPE: $($pathFields.Count) declared path fields, $($absent.Count) absent from disk on this machine"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
