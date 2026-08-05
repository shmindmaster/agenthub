#Requires -Version 5.1
<#
Behavior tests for registry/capabilities.json: one capability, one owner,
one canonical location, addressed the same way as every other.

WHY THIS FILE EXISTS

AGENTS.md: "Before changing a capability, identify its single registry
owner." CLAUDE.md: "Reuse the owner recorded in
registry/capabilities.json before creating a skill, plugin, MCP server,
role, hook, or wrapper." Both rules were unenforced until this file.

Measured 2026-08-05, on a real occurrence. A second entry appeared
claiming managedSkillName 'local-ai-stack', which packages/local-ai
already owned, from an absolute canonicalSource rooted at this checkout
and pointing into the forbidden legacy directory. (The path is elided
here: Validate-AgentHub.ps1 greps the tree for that exact sequence, so
quoting it verbatim in a test about it would fail the build -- which is
itself a small lesson about writing rules that cannot describe
themselves.) Probing the duplicate on its own -- two valid packages, both
claiming one skill name, nothing else wrong -- produced:

    Validate-AgentHub.ps1  PASS
    Run-AllTests.ps1       136 passed, 0 failed
    AgentHub.ps1 drift     PASS: 4 of 4 delegated sync steps succeeded

Three green verdicts over a registry that named two owners for one skill.
The consequence is not an error anywhere; it is that whichever entry syncs
last wins, silently, and the losing capability's content is quietly
replaced on every host. Work proceeds, nothing fails, the result is wrong
-- the defect class this repository keeps rediscovering, arriving this
time through the ownership contract itself.

The real occurrence was caught only because it ALSO used a forbidden
directory, which a different check happens to flag. Strip that away and it
would have merged clean. These behaviors do not depend on that accident.

Not a Pester suite: this repo carries no Pester dependency. Same
accumulate-and-report idiom as the rest of tests/.

Run: pwsh -NoProfile -File tests/Test-CapabilityOwnership.ps1
     powershell.exe -NoProfile -File tests/Test-CapabilityOwnership.ps1
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
# Enforced repo-wide by tests/Test-FileEncodingDiscipline.ps1.
$registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities = @($registry.capabilities)

# ---------------------------------------------------------------------------
# Behavior 1: no skill name has two owners.
#
# This is the one the three green verdicts missed.
# ---------------------------------------------------------------------------
function Test-NoSkillHasTwoOwners {
    $owners = @{}
    foreach ($capability in $capabilities) {
        foreach ($skill in @($capability.managedSkillNames)) {
            if ([string]::IsNullOrWhiteSpace([string]$skill)) { continue }
            $key = [string]$skill
            if (-not $owners.ContainsKey($key)) { $owners[$key] = [Collections.Generic.List[string]]::new() }
            $owners[$key].Add([string]$capability.id)
        }
    }
    $contested = @($owners.Keys | Where-Object { $owners[$_].Count -gt 1 })
    if ($contested.Count -gt 0) {
        $rendered = @($contested | ForEach-Object { "'$_' claimed by $($owners[$_] -join ' and ')" })
        return @{ Passed = $false; Detail = "$($contested.Count) skill name(s) have more than one registry owner: $($rendered -join '; '). Whichever entry syncs last silently overwrites the other on every host. Pick the single owner AGENTS.md requires and fold the other entry into it." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 2: no two capabilities point at the same canonical source.
#
# The mirror image of behavior 1. Two ids over one directory means the
# directory has two owners even when no skill name collides, and a change
# to it belongs to both and neither.
# ---------------------------------------------------------------------------
function Test-NoSourceHasTwoOwners {
    $sources = @{}
    foreach ($capability in $capabilities) {
        $source = [string]$capability.canonicalSource
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $key = $source.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
        if (-not $sources.ContainsKey($key)) { $sources[$key] = [Collections.Generic.List[string]]::new() }
        $sources[$key].Add([string]$capability.id)
    }
    $contested = @($sources.Keys | Where-Object { $sources[$_].Count -gt 1 })
    if ($contested.Count -gt 0) {
        $rendered = @($contested | ForEach-Object { "$_ owned by $($sources[$_] -join ' and ')" })
        return @{ Passed = $false; Detail = "canonicalSource claimed by more than one capability: $($rendered -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 3: every capability lives under packages/, addressed relatively.
#
# AGENTS.md: "Every capability lives under packages/<name>", and lists
# capabilities/ among the directories not to reintroduce. An absolute path
# additionally hardcodes one machine's checkout into a registry that is
# otherwise portable across them, and reads as authoritative while being
# true of exactly one filesystem.
#
# Both halves are checked here rather than left to the filesystem sweep,
# because the filesystem only sees a violation once the directory exists.
# The registry states the intent first.
# ---------------------------------------------------------------------------
function Test-EverySourceIsRelativeUnderPackages {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($capability in $capabilities) {
        $id = [string]$capability.id
        $source = [string]$capability.canonicalSource
        if ([string]::IsNullOrWhiteSpace($source)) {
            $bad.Add("$id declares no canonicalSource")
            continue
        }
        $normalized = $source.Replace('\', '/')
        if ($normalized -match '^(?:[A-Za-z]:/|//)') {
            $bad.Add("$id has an absolute canonicalSource ('$source'); every other entry is repo-relative, and an absolute path is true of one machine while reading as true generally")
            continue
        }
        if ($normalized -notmatch '^packages/') {
            $bad.Add("$id has canonicalSource '$source', which is not under packages/. AGENTS.md places every capability at packages/<name> and lists capabilities/ among the directories not to reintroduce")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 4: ids are unique.
#
# Cheap, and the failure is nasty: any tooling keying on id silently reads
# whichever entry it met last.
# ---------------------------------------------------------------------------
function Test-IdsAreUnique {
    $seen = @{}
    $dupes = [Collections.Generic.List[string]]::new()
    foreach ($capability in $capabilities) {
        $id = [string]$capability.id
        if ([string]::IsNullOrWhiteSpace($id)) { $dupes.Add('an entry has no id'); continue }
        if ($seen.ContainsKey($id)) { $dupes.Add("duplicate id '$id'") } else { $seen[$id] = $true }
    }
    if ($dupes.Count -gt 0) { return @{ Passed = $false; Detail = ($dupes -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 5: anti-vacuity.
#
# Behaviors 1 and 2 detect collisions by grouping. A read that yields no
# capabilities, or capabilities carrying no skill names, makes every group
# a singleton and every check above pass while asserting nothing.
# ---------------------------------------------------------------------------
function Test-ScanExaminedRealInput {
    if ($capabilities.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/capabilities.json yielded zero capabilities; every behavior here groups over that empty set and passes trivially.' }
    }
    $withSkills = @($capabilities | Where-Object { @($_.managedSkillNames).Count -gt 0 })
    if ($withSkills.Count -eq 0) {
        return @{ Passed = $false; Detail = "found $($capabilities.Count) capabilities but not one declares managedSkillNames. Behavior 1 is now grouping over nothing, which is exactly how it would miss the duplicate it exists to catch." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------

$behaviors = @(
    @{ Name = 'no skill name is claimed by two capabilities';        Run = { Test-NoSkillHasTwoOwners } }
    @{ Name = 'no canonicalSource is claimed by two capabilities';   Run = { Test-NoSourceHasTwoOwners } }
    @{ Name = 'every canonicalSource is relative and under packages/'; Run = { Test-EverySourceIsRelativeUnderPackages } }
    @{ Name = 'capability ids are unique';                           Run = { Test-IdsAreUnique } }
    @{ Name = 'the scan examined real capabilities and real skills'; Run = { Test-ScanExaminedRealInput } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "SCOPE: $($capabilities.Count) capabilities, $(@($capabilities | ForEach-Object { $_.managedSkillNames } | Where-Object { $_ }).Count) managed skill names"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
