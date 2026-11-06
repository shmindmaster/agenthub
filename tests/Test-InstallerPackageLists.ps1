#Requires -Version 5.1
<#
The Amp and Warp installers carry hardcoded package lists, while
Install-CursorLocalPlugins.ps1 derives its list from registry/capabilities.json.
A hardcoded list fails by omission: a capability is registered, every host that
reads the registry receives it, and Amp or Warp quietly never do. Nothing fails
at the time, and the gap surfaces later as a host that cannot do work its
registry row says it can.

So this asserts each list still covers every capability the registry maps to that
host, minus the exclusions named below with their reason. An exclusion here is a
decision; an omission in the installer is an accident, and this is what tells them
apart.

Run: pwsh -NoProfile -File tests/Test-InstallerPackageLists.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

# Deliberate exclusions, each with the reason it is not an accident.
$WarpExcluded = @{
    'repowise'              = 'Needs the loopback shared server, which Warp does not run under the plugin-only policy, so the skill would dead-end. Install-WarpSkills.ps1 records the same reason.'
    'linkedin'              = 'Its server is a local stdio process and activationPolicy.pluginOnly does not permit linkedin on warp, so Warp cannot run it and the skill would dead-end. The plugin is on-demand by design.'
    'coding-agent-dispatch' = 'capabilityType is skills and it is not in either marketplace, so there is no plugin to link; hosts reach it through their own agent directories.'
    'mobile-development'    = 'On demand only. Test-MobileDevelopment requires the catalog to be readable, which the deployed runtime package provides; no Warp skill link is part of that contract.'
}
$AmpExcluded = @{}

function Get-MappedCapabilities([string]$HostId, [string[]]$Statuses) {
    $found = [Collections.Generic.List[string]]::new()
    foreach ($file in @('registry\capabilities.json', 'overlays\personal\capabilities.json')) {
        $path = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $doc = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($cap in @($doc.capabilities)) {
            foreach ($mapping in @($cap.hostMappings)) {
                if ([string]$mapping.hostId -ne $HostId) { continue }
                if ($Statuses -and ($Statuses -notcontains [string]$mapping.deploymentStatus)) { continue }
                $found.Add([string]$cap.id)
            }
        }
    }
    return @($found | Select-Object -Unique)
}

function Get-Missing([string[]]$Mapped, [string[]]$Listed, [hashtable]$Excluded) {
    return @($Mapped | Where-Object { ($Listed -notcontains $_) -and (-not $Excluded.ContainsKey($_)) })
}

# --- Amp: scripts/Install-AmpPlugins.py PACKAGES dict, keyed by ah-<folder>.
$ampPath = Join-Path $repoRoot 'scripts\Install-AmpPlugins.py'
Report 'Install-AmpPlugins.py exists' (Test-Path -LiteralPath $ampPath -PathType Leaf) "missing $ampPath"
$ampListed = @()
if (Test-Path -LiteralPath $ampPath -PathType Leaf) {
    $ampText = Get-Content -LiteralPath $ampPath -Raw -Encoding UTF8
    $block = [regex]::Match($ampText, '(?s)PACKAGES\s*=\s*\{(.*?)\r?\n\}')
    Report 'the Amp PACKAGES dict was found before claiming it is complete' $block.Success 'PACKAGES block did not parse; the coverage check below would pass on nothing'
    if ($block.Success) {
        $ampListed = @([regex]::Matches($block.Groups[1].Value, '"ah-([a-z0-9-]+)"\s*:') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    }
}
$PluginStatuses = @('native-local-plugin', 'native-plugin-installed', 'plugin-owned', 'native-extension-junction')
$ampMapped = @(Get-MappedCapabilities 'amp' $PluginStatuses)
$ampMissing = @(Get-Missing $ampMapped $ampListed $AmpExcluded)
Report 'the Amp installer lists every capability the registry maps to amp as a plugin' `
    ($ampMissing.Count -eq 0) ("registry maps but the script omits: " + ($ampMissing -join ', '))
Report 'the Amp list was proven non-empty' ($ampListed.Count -gt 0) 'no ah-* keys parsed from PACKAGES'

# --- Warp: scripts/Install-WarpSkills.ps1 $packages array, bare folder paths.
$warpPath = Join-Path $repoRoot 'scripts\Install-WarpSkills.ps1'
Report 'Install-WarpSkills.ps1 exists' (Test-Path -LiteralPath $warpPath -PathType Leaf) "missing $warpPath"
$warpListed = @()
if (Test-Path -LiteralPath $warpPath -PathType Leaf) {
    $warpText = Get-Content -LiteralPath $warpPath -Raw -Encoding UTF8
    $warpListed = @([regex]::Matches($warpText, "'(?:packages|overlays/personal/packages)/([a-z0-9-]+)'") |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}
# Warp has no plugin format, so every mapped row counts, not only plugin statuses.
$warpMapped = @(Get-MappedCapabilities 'warp' @())
$warpMissing = @(Get-Missing $warpMapped $warpListed $WarpExcluded)
Report 'the Warp installer links every capability the registry maps to warp, or names it as excluded' `
    ($warpMissing.Count -eq 0) ("registry maps but the script omits and no exclusion explains it: " + ($warpMissing -join ', '))
Report 'the Warp list was proven non-empty' ($warpListed.Count -gt 0) 'no package paths parsed from $packages'

# Every exclusion must still be a live registry row. An exclusion left behind
# after a capability is retired or unmapped would hide a future omission forever.
# linkedin is mapped only in the personal overlay. A public checkout has no
# overlay file, so that exclusion is not a retired public row.
$overlayPresent = Test-Path -LiteralPath (Join-Path $repoRoot 'overlays\personal\capabilities.json') -PathType Leaf
$overlayOnlyExclusions = @('linkedin')
$staleExclusions = @($WarpExcluded.Keys | Where-Object {
    $warpMapped -notcontains $_ -and ($overlayPresent -or ($overlayOnlyExclusions -notcontains $_))
})
Report 'every Warp exclusion still names a capability the registry maps to warp' `
    ($staleExclusions.Count -eq 0) ("excluded but no longer mapped: " + ($staleExclusions -join ', '))

# --- Anti-vacuity: the detector has to be able to fail.
$detectorWorks = @(Get-Missing @('product', 'fabricated-capability') @('product') @{}).Count -eq 1
Report 'the coverage detector flags a mapped capability the installer omits' $detectorWorks 'detector returned nothing for a fabricated omission'

Write-Host ""
Write-Host "SCOPE: amp maps $($ampMapped.Count) and lists $($ampListed.Count); warp maps $($warpMapped.Count), links $($warpListed.Count) and excludes $($WarpExcluded.Count)"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
