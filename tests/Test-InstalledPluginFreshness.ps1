#Requires -Version 5.1
<#
Proves that what a host actually LOADS matches what this repository contains.

Why this exists: mobile-device-lab sat at version 1.0.9 while its content
changed across roughly twenty commits -- Open-MobileLabWebTarget.ps1,
Start-MobileLabMetro.ps1, Test-MobileLabAppConfig.ps1 and the documentation for
all of it. SKILL.md was 505 lines in the repository and 368 lines in the
installed copy, with zero mentions of the web-target script. The installed
plugin was pinned at a git commit three days old.

Every existing check passed the whole time. Validate-AgentHub validates the
repository. Test-PluginManifests validates the manifests. The reachability
suite compares the INSTALLED version against the manifest version -- and those
two agreed, because the manifest was never bumped. A version comparison cannot
see content drift held at a constant version, which is precisely the shape this
defect had.

The result is the repository's most common defect class: work complete at one
layer and unreachable at another, with nothing failing. An agent invoking the
skill read instructions that predated the entire capability.

So this compares CONTENT, not versions: every file the installed plugin exposes
must be byte-identical to its source in packages/. That is a check a missing
version bump cannot satisfy.

Scope note: only plugins that are actually installed are checked. An
uninstalled plugin is not drifting, and demanding installation here would make
the suite fail on a machine that has deliberately not enabled one.

The comparison is against COMMITTED source, and the "left behind" arm is not
academic. The agenthub marketplace is a Directory source pointed at this
working tree, so `claude plugin update` copies whatever is on disk --
uncommitted files included. Measured 2026-08-18: a half-finished skill that had
deliberately not been committed was installed into the plugin cache by an
unrelated update, where agents would have loaded it. Comparing against the
committed tree is what makes that visible instead of invisible.

Run: pwsh -NoProfile -File tests/Test-InstalledPluginFreshness.ps1
     powershell.exe -NoProfile -File tests/Test-InstalledPluginFreshness.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

# Reuse the repository's own tracked-file enumerator rather than
# reimplementing it. It already fails loudly instead of falling back to a
# filesystem walk, which is the property this check depends on.
. (Join-Path $repoRoot 'scripts\RegistryContentHash.ps1')

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

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    # -Encoding UTF8 is mandatory here: without it Windows PowerShell 5.1
    # decodes in the ANSI code page and PowerShell 7 in UTF-8, so the same file
    # parses differently depending on which shell ran the suite.
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Compare-DeployedTree {
    <#
    .SYNOPSIS
        Which of $RelativePaths are missing from, or differ in, the deployed copy.
    .DESCRIPTION
        The caller supplies the file list rather than this function walking the
        filesystem, and for the real check that list is git-tracked content
        only. That matters: a filesystem walk counts uncommitted work in
        packages/ as "missing from the installed copy", so anyone mid-edit would
        see a red suite for work they had not shipped yet. RegistryContentHash
        already settled this for the content hash -- only committed content is a
        trust root -- and this check follows the same rule.

        Extra files in the deployed copy are reported rather than ignored: a
        file the installer left behind from an earlier version misleads a reader
        exactly as much as a stale one.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DeployedRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RelativePaths
    )

    if ($RelativePaths.Count -eq 0) {
        # An empty comparison would otherwise "pass" by having nothing to
        # disagree about -- the same silent-success shape this suite exists to
        # eliminate.
        throw "No source files supplied for $SourceRoot; refusing to report a comparison that examined nothing."
    }

    $differences = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($relative in $RelativePaths) {
        $normalized = $relative -replace '/', [string][IO.Path]::DirectorySeparatorChar
        [void]$seen.Add($normalized)

        $source = Join-Path $SourceRoot $normalized
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }

        $deployed = Join-Path $DeployedRoot $normalized
        if (-not (Test-Path -LiteralPath $deployed -PathType Leaf)) {
            $differences.Add("missing from the installed copy: $normalized")
            continue
        }
        if ((Get-FileSha256 -Path $source) -ne (Get-FileSha256 -Path $deployed)) {
            $differences.Add("content differs: $normalized")
        }
    }

    if (Test-Path -LiteralPath $DeployedRoot) {
        $deployedPrefix = $DeployedRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        foreach ($file in @(Get-ChildItem -LiteralPath $DeployedRoot -Recurse -File -Force)) {
            $relative = $file.FullName.Substring($deployedPrefix.Length)
            if (-not $seen.Contains($relative)) {
                $differences.Add("left behind in the installed copy, absent from committed source: $relative")
            }
        }
    }

    return $differences.ToArray()
}

function Get-InstalledAgentHubPlugins {
    <#
    .SYNOPSIS
        Installed plugins whose marketplace is this repository's, with source paths.
    #>
    $installedPath = Join-Path $env:USERPROFILE '.claude\plugins\installed_plugins.json'
    if (-not (Test-Path -LiteralPath $installedPath)) {
        throw "No installed_plugins.json at $installedPath. Cannot tell what any host loads, so nothing here may report success."
    }

    $installed = Read-JsonFile -Path $installedPath
    $result = [Collections.Generic.List[object]]::new()

    foreach ($property in $installed.plugins.PSObject.Properties) {
        if ($property.Name -notlike '*@agenthub') { continue }
        $entry = @($property.Value | Select-Object -Last 1)
        if ($entry.Count -ne 1) { continue }

        $pluginName = $property.Name -replace '@agenthub$', ''
        $sourcePackage = Join-Path $repoRoot "packages\$pluginName"
        if (-not (Test-Path -LiteralPath $sourcePackage -PathType Container)) { continue }

        $result.Add([pscustomobject]@{
            Name             = $pluginName
            InstalledVersion = [string]$entry[0].version
            InstallPath      = [string]$entry[0].installPath
            SourcePackage    = $sourcePackage
        })
    }

    return $result.ToArray()
}

# --- Behavior 1: the enumeration reaches something.
#
# A freshness suite that silently examined zero plugins would pass forever.
# This asserts the target set is non-empty before any freshness claim is made. ---
function Test-InstalledSetIsProvenNonEmpty {
    $plugins = Get-InstalledAgentHubPlugins
    if ($plugins.Count -eq 0) {
        return @{ Passed = $false; Detail = 'No @agenthub plugins are installed, so every freshness check below would pass by examining nothing.' }
    }
    return @{ Passed = $true; Detail = "$($plugins.Count) installed @agenthub plugin(s): $(($plugins | ForEach-Object Name) -join ', ')" }
}

# --- Behavior 2: the installed version matches the source manifest.
#
# This is the cheap half, and on its own it is the check that already existed
# and already missed the defect. It is kept because a version mismatch names
# the remedy precisely (`claude plugin update <name>@agenthub`). ---
function Test-InstalledVersionMatchesSource {
    $mismatches = [Collections.Generic.List[string]]::new()
    foreach ($plugin in Get-InstalledAgentHubPlugins) {
        $manifest = Join-Path $plugin.SourcePackage '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) {
            $mismatches.Add("$($plugin.Name): no .claude-plugin/plugin.json in packages/")
            continue
        }
        $sourceVersion = [string](Read-JsonFile -Path $manifest).version
        if ($sourceVersion -ne $plugin.InstalledVersion) {
            $mismatches.Add("$($plugin.Name): installed $($plugin.InstalledVersion), source declares $sourceVersion -- run: claude plugin update $($plugin.Name)@agenthub")
        }
    }
    if ($mismatches.Count -gt 0) {
        return @{ Passed = $false; Detail = ($mismatches -join '; ') }
    }
    return @{ Passed = $true; Detail = 'every installed @agenthub plugin is at the version its source manifest declares' }
}

# --- Behavior 3: the installed CONTENT matches source, byte for byte.
#
# The check the missing version bump could not satisfy. A plugin held at a
# constant version while its skills change passes Behavior 2 and fails here. ---
function Test-InstalledContentMatchesSource {
    $drifted = [Collections.Generic.List[string]]::new()
    foreach ($plugin in Get-InstalledAgentHubPlugins) {
        if (-not (Test-Path -LiteralPath $plugin.InstallPath -PathType Container)) {
            $drifted.Add("$($plugin.Name): installPath does not exist: $($plugin.InstallPath)")
            continue
        }
        $sourceSkills = Join-Path $plugin.SourcePackage 'skills'
        if (-not (Test-Path -LiteralPath $sourceSkills -PathType Container)) { continue }

        $deployedSkills = Join-Path $plugin.InstallPath 'skills'
        if (-not (Test-Path -LiteralPath $deployedSkills -PathType Container)) {
            $drifted.Add("$($plugin.Name): the installed copy exposes no skills/ directory at all")
            continue
        }

        # Git-tracked only, matching RegistryContentHash's trust root: a
        # filesystem walk would report a colleague's uncommitted skill as
        # "missing from the installed copy" and turn every mid-edit run red.
        $tracked = @(Get-AgentHubGitTrackedRelativeFiles -Path $sourceSkills)
        if ($tracked.Count -eq 0) {
            $drifted.Add("$($plugin.Name): no git-tracked files under packages/$($plugin.Name)/skills -- refusing to report this plugin as fresh on the strength of an empty comparison")
            continue
        }

        $differences = @(Compare-DeployedTree -SourceRoot $sourceSkills -DeployedRoot $deployedSkills -RelativePaths $tracked)
        if ($differences.Count -gt 0) {
            $shown = @($differences | Select-Object -First 5)
            $suffix = if ($differences.Count -gt $shown.Count) { " (+$($differences.Count - $shown.Count) more)" } else { '' }
            $drifted.Add("$($plugin.Name): $($differences.Count) difference(s) -- $($shown -join '; ')$suffix -- run: claude plugin update $($plugin.Name)@agenthub")
        }
    }
    if ($drifted.Count -gt 0) {
        return @{ Passed = $false; Detail = ($drifted -join ' || ') }
    }
    return @{ Passed = $true; Detail = 'every installed @agenthub skill file is byte-identical to its source in packages/' }
}

# --- Behavior 4: the comparison can actually fail.
#
# The whole point of this file is that a check which cannot fail is decoration.
# This proves the comparator detects a changed byte, a missing file, and a file
# left behind -- against fixtures, never against the real tree. ---
function Test-ComparatorDetectsEachDriftShape {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-freshness-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $source = Join-Path $root 'source'
        $deployed = Join-Path $root 'deployed'
        New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $deployed 'nested') -Force | Out-Null

        [IO.File]::WriteAllText((Join-Path $source 'SKILL.md'), "same`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'SKILL.md'), "same`n")
        [IO.File]::WriteAllText((Join-Path $source 'nested\drifted.ps1'), "new content`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'nested\drifted.ps1'), "old content`n")
        [IO.File]::WriteAllText((Join-Path $source 'added.md'), "only in source`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'stale.md'), "only in deployed`n")

        $fixtureFiles = @('SKILL.md', 'nested/drifted.ps1', 'added.md')
        $differences = @(Compare-DeployedTree -SourceRoot $source -DeployedRoot $deployed -RelativePaths $fixtureFiles)

        $sawContent = @($differences | Where-Object { $_ -like 'content differs: *drifted.ps1' }).Count -eq 1
        $sawMissing = @($differences | Where-Object { $_ -like 'missing from the installed copy: added.md' }).Count -eq 1
        $sawStale = @($differences | Where-Object { $_ -like 'left behind*stale.md' }).Count -eq 1
        $ignoredIdentical = @($differences | Where-Object { $_ -like '*SKILL.md*' }).Count -eq 0

        if (-not ($sawContent -and $sawMissing -and $sawStale -and $ignoredIdentical)) {
            return @{ Passed = $false; Detail = "comparator missed a drift shape (content=$sawContent missing=$sawMissing stale=$sawStale identicalIgnored=$ignoredIdentical): $($differences -join '; ')" }
        }

        # And an identical pair must produce nothing, or every run would fail.
        $clean = @(Compare-DeployedTree -SourceRoot $source -DeployedRoot $source -RelativePaths $fixtureFiles)
        if ($clean.Count -ne 0) {
            return @{ Passed = $false; Detail = "an identical tree reported $($clean.Count) difference(s): $($clean -join '; ')" }
        }

        return @{ Passed = $true; Detail = 'detects a changed byte, a missing file and a left-behind file, and clears an identical tree' }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: an empty source tree fails loudly rather than passing.
function Test-EmptySourceFailsLoudly {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-freshness-empty-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        try {
            $null = Compare-DeployedTree -SourceRoot $root -DeployedRoot $root -RelativePaths @()
            return @{ Passed = $false; Detail = 'an empty source tree returned a clean comparison instead of throwing' }
        } catch {
            return @{ Passed = $true; Detail = "throws rather than reporting a comparison that examined nothing: $($_.Exception.Message)" }
        }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-InstalledSetIsProvenNonEmpty
Report 'the installed @agenthub plugin set is proven non-empty before anything claims freshness' $r1.Passed $r1.Detail

$r2 = Test-InstalledVersionMatchesSource
Report 'every installed @agenthub plugin is at the version its source manifest declares' $r2.Passed $r2.Detail

$r3 = Test-InstalledContentMatchesSource
Report 'every installed @agenthub skill file is byte-identical to source, which a version match alone cannot prove' $r3.Passed $r3.Detail

$r4 = Test-ComparatorDetectsEachDriftShape
Report 'the comparator detects changed, missing and left-behind files, and clears an identical tree' $r4.Passed $r4.Detail

$r5 = Test-EmptySourceFailsLoudly
Report 'an empty source tree fails loudly instead of reporting a clean comparison' $r5.Passed $r5.Detail

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
