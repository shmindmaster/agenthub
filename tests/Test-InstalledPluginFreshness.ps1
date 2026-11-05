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
must match its source in packages/, with registry-standard newline normalization. That is a check a missing
version bump cannot satisfy.

Scope note: only plugins that are actually installed are checked. An
uninstalled plugin is not drifting, and demanding installation here would make
the suite fail on a machine that has deliberately not enabled one.

Hosts covered: Claude, from ~/.claude/plugins/installed_plugins.json, plus every
host that copies a plugin into its own cache -- Codex and Qoder by version
folder, Cursor, Antigravity and Cline as flat folders, and Factory by nested
manifest. Where a host keeps several version folders, the newest is the copy it
resolves, because neither Codex nor Qoder records the active one in a manifest.
Private overlay packages resolve under overlays/personal/packages, so ah-sarosh
and ah-linkedin are covered rather than silently skipped. Copilot loads this
repository live and copies nothing, and Amp is built from source by
scripts/Install-AmpPlugins.py, so neither has a version to compare.

Measured 2026-11-05: reading Claude alone let a stale ah-product sit on Codex and
a two-versions-behind ah-media-studio sit on Qoder while this suite reported
7 passed, 0 failed. Widening the scan then found ah-sarosh's write/SKILL.md
differing from source on Antigravity and Factory at an unchanged version 1.1.2,
which no version comparison could ever have caught.

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
    # Match the registry's text-content contract across LF and CRLF checkouts.
    # Binary files and every substantive text byte still participate.
    return Get-AgentHubStableFileHash -Path $Path
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

# Every host that COPIES a plugin keeps its own cache shape, and a freshness
# check that knows only one shape silently skips the rest. Reading Claude alone
# let a stale ah-product 2.0.2 sit on Codex against source 2.1.0, and
# ah-media-studio 2.1.2 sit on Qoder against 2.1.4, while this suite reported
# 7 passed, 0 failed. Parity with no UNDETECTED drift means the detector has to
# look where every copy actually is.
#
# Layouts:
#   versioned -- <Root>\<name>\<version>\. Neither Codex nor Qoder records the
#                active version in a manifest, so the newest folder is the copy
#                the host resolves.
#   flat      -- <Root>\<name>\ holding the manifest directly.
#   nested    -- manifests anywhere under Root, grouped by the name they declare.
#                Factory nests by marketplace and Grok renames each folder to
#                <package>-<hash>, so neither can be found by folder name; both
#                declare the real ah-* name inside plugin.json, which is what
#                this layout reads. Grok was invisible to every earlier version
#                of this check and carried ah-product 2.0.2 against source 2.1.0.
#
# Copilot loads this repository live and Amp is rebuilt from source by
# scripts/Install-AmpPlugins.py, so neither carries a version to compare;
# Test-AmpPlugins.ps1 covers Amp's shape instead.
$PluginCacheHosts = @(
    @{ Host = 'codex';       Layout = 'versioned'; Root = (Join-Path $HOME '.codex\plugins\cache\agenthub');  PrivateMarketplace = 'sarosh-private'; Remedy = 'codex plugin add {0}@{2}' },
    @{ Host = 'qoder';       Layout = 'versioned'; Root = (Join-Path $HOME '.qoder\plugins\cache\agenthub');  PrivateMarketplace = 'sarosh-private'; Remedy = 'qodercli plugins marketplace update {2}, then qodercli plugins update {0}@{2}' },
    @{ Host = 'cursor';      Layout = 'flat';      Root = (Join-Path $HOME '.cursor\plugins\local');          PrivateMarketplace = 'sarosh-private'; Remedy = 'scripts\Install-CursorLocalPlugins.ps1' },
    @{ Host = 'antigravity'; Layout = 'flat';      Root = (Join-Path $HOME '.gemini\config\plugins');         PrivateMarketplace = $null;            Remedy = 'agy plugin uninstall {0}, then agy plugin install {3}' },
    @{ Host = 'cline';       Layout = 'flat';      Root = (Join-Path $HOME '.agents\plugins');                PrivateMarketplace = $null;            Remedy = 're-junction {0} to {3}' },
    @{ Host = 'factory';     Layout = 'nested';    Root = (Join-Path $HOME '.factory\plugins\cache');         PrivateMarketplace = 'personal';       Remedy = 'droid plugin update {0}@{2}' },
    @{ Host = 'grok';        Layout = 'nested';    Root = (Join-Path $HOME '.grok\installed-plugins');        PrivateMarketplace = 'sarosh-private'; Remedy = 'grok plugin uninstall {0}, then grok plugin install {3} --trust' }
)

# Private capability packages live in the gitignored overlay, so a plugin whose
# folder is not under packages/ is resolved there before it is dropped. Dropping
# it would quietly exempt ah-sarosh and ah-linkedin from every check below.
function Resolve-PluginSourcePackage([string]$PluginName) {
    $folder = $PluginName -replace '^ah-', ''
    foreach ($candidate in @("packages\$folder", "overlays\personal\packages\$folder")) {
        $path = Join-Path $repoRoot $candidate
        if (Test-Path -LiteralPath $path -PathType Container) { return $path }
    }
    return $null
}

function New-CachePluginRow($Spec, [string]$Name, [string]$Version, [string]$Path) {
    $sourcePackage = Resolve-PluginSourcePackage $Name
    if (-not $sourcePackage) { return $null }
    # The remedy has to name the real source and the real marketplace. A private
    # overlay plugin does not live under packages/ and is not published as
    # @agenthub, and Factory registers that overlay under a different name than
    # every other host does, so a hardcoded remedy would send the reader to a
    # path and a marketplace that do not exist.
    $relative = $sourcePackage.Substring($repoRoot.Length).TrimStart('\', '/')
    $isOverlay = $relative -like 'overlays*'
    $marketplace = if ($isOverlay) { $spec.PrivateMarketplace } else { 'agenthub' }
    # Grok and Antigravity install from a path, and both reject the backslash
    # form, so the remedy carries an absolute POSIX-style path rather than
    # something the reader has to translate.
    $absolute = $sourcePackage.Replace('\', '/')
    return [pscustomobject]@{
        Name             = $Name
        Host             = $Spec.Host
        InstalledVersion = $Version
        InstallPath      = $Path
        SourcePackage    = $sourcePackage
        Remedy           = ($Spec.Remedy -f @($Name, $relative, $marketplace, $absolute))
    }
}

function Get-CachedAgentHubPlugins {
    param($Specs = $PluginCacheHosts)
    $result = [Collections.Generic.List[object]]::new()
    foreach ($spec in $Specs) {
        if (-not (Test-Path -LiteralPath $spec.Root -PathType Container)) { continue }
        switch ($spec.Layout) {
            'versioned' {
                foreach ($pluginDir in @(Get-ChildItem -LiteralPath $spec.Root -Directory -ErrorAction SilentlyContinue)) {
                    if ($pluginDir.Name -notlike 'ah-*') { continue }
                    $versions = @(Get-ChildItem -LiteralPath $pluginDir.FullName -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
                        Sort-Object { [version]$_.Name })
                    if ($versions.Count -eq 0) { continue }
                    $row = New-CachePluginRow $spec $pluginDir.Name $versions[-1].Name $versions[-1].FullName
                    if ($row) { $result.Add($row) }
                }
            }
            'flat' {
                foreach ($pluginDir in @(Get-ChildItem -LiteralPath $spec.Root -Directory -ErrorAction SilentlyContinue)) {
                    if ($pluginDir.Name -notlike 'ah-*') { continue }
                    $manifest = $null
                    foreach ($candidate in @('plugin.json', '.claude-plugin\plugin.json')) {
                        $path = Join-Path $pluginDir.FullName $candidate
                        if (Test-Path -LiteralPath $path -PathType Leaf) { $manifest = $path; break }
                    }
                    if (-not $manifest) { continue }
                    $row = New-CachePluginRow $spec $pluginDir.Name ([string](Read-JsonFile -Path $manifest).version) $pluginDir.FullName
                    if ($row) { $result.Add($row) }
                }
            }
            'nested' {
                $best = @{}
                foreach ($manifest in @(Get-ChildItem -LiteralPath $spec.Root -Recurse -File -Filter 'plugin.json' -ErrorAction SilentlyContinue)) {
                    try { $doc = Read-JsonFile -Path $manifest.FullName } catch { continue }
                    $name = [string]$doc.name
                    if ($name -notlike 'ah-*') { continue }
                    $version = [string]$doc.version
                    if ($version -notmatch '^\d+\.\d+\.\d+$') { continue }
                    if (-not $best.ContainsKey($name) -or [version]$version -gt [version]$best[$name].Version) {
                        $best[$name] = @{ Version = $version; Path = $manifest.DirectoryName }
                    }
                }
                foreach ($name in $best.Keys) {
                    $row = New-CachePluginRow $spec $name $best[$name].Version $best[$name].Path
                    if ($row) { $result.Add($row) }
                }
            }
        }
    }
    return $result.ToArray()
}

function Get-InstalledAgentHubPlugins {
    <#
    .SYNOPSIS
        Installed plugins whose marketplace is this repository's, with source paths.
    #>
    $installedPath = Join-Path $HOME '.claude\plugins\installed_plugins.json'
    if (-not (Test-Path -LiteralPath $installedPath)) {
        throw "No installed_plugins.json at $installedPath. Cannot tell what any host loads, so nothing here may report success."
    }

    $installed = Read-JsonFile -Path $installedPath
    $result = [Collections.Generic.List[object]]::new()

    foreach ($property in $installed.plugins.PSObject.Properties) {
        if ($property.Name -notlike '*@agenthub') { continue }
        $entry = @($property.Value | Select-Object -Last 1)
        if ($entry.Count -ne 1) { continue }

        # AgentHub plugins are named ah-<package folder>. A registration without
        # the prefix is a legacy install; the legacy-identity check reports it.
        $pluginName = $property.Name -replace '@agenthub$', ''
        if ($pluginName -notlike 'ah-*') { continue }
        $sourcePackage = Join-Path $repoRoot ('packages\' + ($pluginName -replace '^ah-', ''))
        if (-not (Test-Path -LiteralPath $sourcePackage -PathType Container)) { continue }

        $result.Add([pscustomobject]@{
            Name             = $pluginName
            Host             = 'claude'
            InstalledVersion = [string]$entry[0].version
            InstallPath      = [string]$entry[0].installPath
            SourcePackage    = $sourcePackage
            Remedy           = "claude plugin update $pluginName@agenthub"
        })
    }

    return @($result.ToArray()) + @(Get-CachedAgentHubPlugins)
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
    return @{ Passed = $true; Detail = "$($plugins.Count) installed @agenthub plugin copy/copies: $(($plugins | ForEach-Object { "$($_.Name)@$($_.Host)" }) -join ', ')" }
}

# --- Behavior 2: the installed version matches the source manifest.
#
# This is the cheap half, and on its own it is the check that already existed
# and already missed the defect. It is kept because a version mismatch names
# the remedy precisely (`claude plugin update <name>@agenthub`). ---
function Test-InstalledVersionMatchesSource {
    param($Plugins = (Get-InstalledAgentHubPlugins))
    $mismatches = [Collections.Generic.List[string]]::new()
    foreach ($plugin in $Plugins) {
        $manifest = Join-Path $plugin.SourcePackage '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) {
            $mismatches.Add("$($plugin.Name): no .claude-plugin/plugin.json in packages/")
            continue
        }
        $sourceVersion = [string](Read-JsonFile -Path $manifest).version
        if ($sourceVersion -ne $plugin.InstalledVersion) {
            $mismatches.Add("$($plugin.Name) on $($plugin.Host): installed $($plugin.InstalledVersion), source declares $sourceVersion -- run: $($plugin.Remedy)")
        }
    }
    if ($mismatches.Count -gt 0) {
        return @{ Passed = $false; Detail = ($mismatches -join '; ') }
    }
    return @{ Passed = $true; Detail = 'every installed @agenthub plugin is at the version its source manifest declares' }
}

# --- Behavior 3: installed CONTENT matches under the registry's newline policy.
#
# The check the missing version bump could not satisfy. A plugin held at a
# constant version while its skills change passes Behavior 2 and fails here. ---
function Test-InstalledContentMatchesSource {
    $drifted = [Collections.Generic.List[string]]::new()
    foreach ($plugin in Get-InstalledAgentHubPlugins) {
        if (-not (Test-Path -LiteralPath $plugin.InstallPath -PathType Container)) {
            $drifted.Add("$($plugin.Name) on $($plugin.Host): installPath does not exist: $($plugin.InstallPath)")
            continue
        }
        $sourceSkills = Join-Path $plugin.SourcePackage 'skills'
        if (-not (Test-Path -LiteralPath $sourceSkills -PathType Container)) { continue }

        $deployedSkills = Join-Path $plugin.InstallPath 'skills'
        if (-not (Test-Path -LiteralPath $deployedSkills -PathType Container)) {
            $drifted.Add("$($plugin.Name) on $($plugin.Host): the installed copy exposes no skills/ directory at all")
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
            $drifted.Add("$($plugin.Name) on $($plugin.Host): $($differences.Count) difference(s) -- $($shown -join '; ')$suffix -- run: $($plugin.Remedy)")
        }
    }
    if ($drifted.Count -gt 0) {
        return @{ Passed = $false; Detail = ($drifted -join ' || ') }
    }
    return @{ Passed = $true; Detail = 'every installed @agenthub skill file matches source under the registry newline policy' }
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
        [IO.File]::WriteAllText((Join-Path $source 'eol.md'), "same`r`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'eol.md'), "same`n")
        [IO.File]::WriteAllText((Join-Path $source 'nested\drifted.ps1'), "new content`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'nested\drifted.ps1'), "old content`n")
        [IO.File]::WriteAllText((Join-Path $source 'added.md'), "only in source`n")
        [IO.File]::WriteAllText((Join-Path $deployed 'stale.md'), "only in deployed`n")

        $fixtureFiles = @('SKILL.md', 'eol.md', 'nested/drifted.ps1', 'added.md')
        $differences = @(Compare-DeployedTree -SourceRoot $source -DeployedRoot $deployed -RelativePaths $fixtureFiles)

        $sawContent = @($differences | Where-Object { $_ -like 'content differs: *drifted.ps1' }).Count -eq 1
        $sawMissing = @($differences | Where-Object { $_ -like 'missing from the installed copy: added.md' }).Count -eq 1
        $sawStale = @($differences | Where-Object { $_ -like 'left behind*stale.md' }).Count -eq 1
        $ignoredIdentical = @($differences | Where-Object { $_ -like '*SKILL.md*' -or $_ -like '*eol.md*' }).Count -eq 0

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

# --- Behavior 6: a retired package identity is absent from deployed state.
#
# This is intentionally separate from content freshness. Unrelated installed
# plugins may be stale without disguising whether a retired package still has a
# registration or loadable cache. Deleting a package also makes Behaviors 2-3
# skip its installation (there is no source to compare against), so without
# this check a native copy of a retired plugin could keep exposing its retired
# skills indefinitely: Sync-Capabilities sweeps loose skill directories only and
# treats native plugins as host-managed. Marketplace source is excluded: a
# catalog row is not an installed registration or deployed cache. ---
$RetiredPluginNames = @(
    'mobile-device-lab',        # retired 2026-08
    'technical-storytelling',   # retired 2026-10-21 into media-studio (consolidation P5)
    'story-series-studio'       # retired 2026-10-21 into media-studio (consolidation P4)
)
# Plugins were named after their package folder until they became ah-<folder>.
# A registration under the old name is a second, stale copy of the same plugin.
$LegacyUnprefixedPluginNames = @('product', 'media-studio', 'mobile-development', 'repowise', 'assemblyai')
function Test-RetiredPluginIdentitiesAreAbsent {
    $hits = [Collections.Generic.List[string]]::new()
    foreach ($legacyName in $LegacyUnprefixedPluginNames) {
        $legacyId = "$legacyName@agenthub"
        foreach ($file in @((Join-Path $HOME '.claude\settings.json'), (Join-Path $HOME '.claude\plugins\installed_plugins.json'), (Join-Path $HOME '.codex\config.toml'))) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            if (Select-String -LiteralPath $file -SimpleMatch -Quiet -Pattern ('"' + $legacyId + '"')) { $hits.Add("legacy $legacyId registration: $file") }
            if (Select-String -LiteralPath $file -SimpleMatch -Quiet -Pattern ('[plugins."' + $legacyId + '"]')) { $hits.Add("legacy $legacyId registration: $file") }
        }
    }
    $files = @(
        (Join-Path $HOME '.claude\settings.json'),
        (Join-Path $HOME '.claude\plugins\installed_plugins.json'),
        (Join-Path $HOME '.codex\config.toml')
    )
    $codexPlugins = Join-Path $HOME '.codex\plugins'
    $codexDirs = if (Test-Path -LiteralPath $codexPlugins) { @(Get-ChildItem -LiteralPath $codexPlugins -Directory -Recurse -Force -ErrorAction SilentlyContinue) } else { @() }
    foreach ($retiredName in $RetiredPluginNames) {
        $retiredId = "$retiredName@agenthub"
        foreach ($file in $files) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            if (Select-String -LiteralPath $file -SimpleMatch -Quiet -Pattern $retiredId) {
                $hits.Add("$retiredId registration/config: $file")
            }
        }
        $claudeCache = Join-Path $HOME ".claude\plugins\cache\agenthub\$retiredName"
        if (Test-Path -LiteralPath $claudeCache) { $hits.Add("Claude cache: $claudeCache") }
        foreach ($directory in @($codexDirs | Where-Object Name -eq $retiredName)) {
            $hits.Add("Codex cache: $($directory.FullName)")
        }
    }

    if ($hits.Count -gt 0) { return @{ Passed = $false; Detail = ($hits -join '; ') } }
    return @{ Passed = $true; Detail = 'no retired registration, config entry, or deployed cache exists in the declared Claude/Codex plugin spaces' }
}

# --- Behavior 7: Appium remains absent from persistent host configuration.
function Test-AppiumIsNotPersisted {
    $hits = [Collections.Generic.List[string]]::new()
    foreach ($file in @(
        (Join-Path $HOME '.claude.json'),
        (Join-Path $HOME '.claude\settings.json'),
        (Join-Path $HOME '.codex\config.toml')
    )) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        if (Select-String -LiteralPath $file -SimpleMatch -Quiet -Pattern 'appium-mobile') {
            $hits.Add($file)
        }
    }
    if ($hits.Count -gt 0) { return @{ Passed = $false; Detail = "persistent Appium entry found in: $($hits -join ', ')" } }
    return @{ Passed = $true; Detail = 'no appium-mobile entry exists in Claude or Codex persistent configuration' }
}

# --- Behavior 8: the cache scan reaches what it claims, and orders versions by
# value.
#
# A cache root that exists but contributes nothing would silently drop that host
# out of Behaviors 2 and 3, which is exactly how Codex went unobserved while it
# carried a stale plugin. And a lexical sort would call 1.9.0 newer than 1.10.0,
# so the fixture below fails on a string comparison. ---
function Test-VersionedCacheScanIsProvenSound {
    $problems = [Collections.Generic.List[string]]::new()
    $scanned = @(Get-CachedAgentHubPlugins)
    foreach ($spec in $PluginCacheHosts) {
        if (-not (Test-Path -LiteralPath $spec.Root -PathType Container)) { continue }
        if (@($scanned | Where-Object { $_.Host -eq $spec.Host }).Count -eq 0) {
            $problems.Add("$($spec.Host) cache root exists at $($spec.Root) but contributed no ah-* plugin, so the version and content checks observe nothing on that host")
        }
    }

    $root = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-cache-scan-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $pluginDir = Join-Path $root 'ah-aws'
        foreach ($version in @('1.9.0', '1.10.0', '2.0.0')) {
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $pluginDir $version)
        }
        $picked = @(Get-CachedAgentHubPlugins -Specs @(@{ Host = 'fixture'; Layout = 'versioned'; Root = $root; Remedy = 'not applicable' }))
        if ($picked.Count -ne 1) {
            $problems.Add("fixture cache produced $($picked.Count) entries, expected exactly 1")
        } elseif ($picked[0].InstalledVersion -ne '2.0.0') {
            $problems.Add("fixture cache picked $($picked[0].InstalledVersion) instead of 2.0.0, so version ordering is not numeric")
        }
    } finally {
        if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
    }

    if ($problems.Count -gt 0) { return @{ Passed = $false; Detail = ($problems -join '; ') } }
    $hosts = @($scanned | ForEach-Object { $_.Host } | Select-Object -Unique)
    return @{ Passed = $true; Detail = "cache scan reached $(if ($hosts.Count) { $hosts -join ', ' } else { 'no installed host' }) and orders versions numerically" }
}

# --- Behavior 9: the version check rejects a stale copy.
#
# Every host being current is the expected state, so Behaviors 2 and 3 pass on a
# machine that is simply fine. Without this, a scan that quietly returned nothing
# would look identical to a fleet in perfect parity. A fabricated 0.0.1 copy of a
# real package must be refused. ---
function Test-VersionCheckRejectsStaleCopy {
    $problems = [Collections.Generic.List[string]]::new()
    $stale = [pscustomobject]@{
        Name             = 'ah-aws'
        Host             = 'fixture'
        InstalledVersion = '0.0.1'
        InstallPath      = ''
        SourcePackage    = (Join-Path $repoRoot 'packages\aws')
        Remedy           = 'not applicable'
    }
    $result = Test-InstalledVersionMatchesSource -Plugins @($stale)
    if ($result.Passed) {
        $problems.Add('the version check accepted a fabricated 0.0.1 copy of ah-aws, so it cannot detect a stale host')
    }
    if ($result.Detail -notmatch '0\.0\.1') {
        $problems.Add("the version check failed without naming the stale version: $($result.Detail)")
    }
    if ($problems.Count -gt 0) { return @{ Passed = $false; Detail = ($problems -join '; ') } }
    return @{ Passed = $true; Detail = 'a fabricated stale copy is refused and its version is named' }
}

$r1 = Test-InstalledSetIsProvenNonEmpty
Report 'the installed @agenthub plugin set is proven non-empty before anything claims freshness' $r1.Passed $r1.Detail

$r2 = Test-InstalledVersionMatchesSource
Report 'every installed @agenthub plugin is at the version its source manifest declares' $r2.Passed $r2.Detail

$r3 = Test-InstalledContentMatchesSource
Report 'every installed @agenthub skill file matches source under the registry newline policy' $r3.Passed $r3.Detail

$r4 = Test-ComparatorDetectsEachDriftShape
Report 'the comparator detects changed, missing and left-behind files, and clears an identical tree' $r4.Passed $r4.Detail

$r5 = Test-EmptySourceFailsLoudly
Report 'an empty source tree fails loudly instead of reporting a clean comparison' $r5.Passed $r5.Detail

$r6 = Test-RetiredPluginIdentitiesAreAbsent
Report "retired plugin registrations and cache residue ($($RetiredPluginNames -join ', ')) are absent from Claude and Codex" $r6.Passed $r6.Detail

$r7 = Test-AppiumIsNotPersisted
Report 'Appium remains absent from Claude and Codex persistent configuration' $r7.Passed $r7.Detail

$r8 = Test-VersionedCacheScanIsProvenSound
Report 'every copying host cache scan reaches the host it claims and orders versions numerically' $r8.Passed $r8.Detail

$r9 = Test-VersionCheckRejectsStaleCopy
Report 'the version check refuses a fabricated stale copy instead of passing on an unobserved fleet' $r9.Passed $r9.Detail

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
