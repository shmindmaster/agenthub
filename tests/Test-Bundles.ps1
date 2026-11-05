#Requires -Version 5.1
<#
Behavior tests for registry/bundles.json.

Bundles are recipes, not mega-plugins. They may name capabilities that are not
registered yet while a plan is in flight, but every named third-party extension
must already be tracked in native-connectors.json thirdPartyExtensions, and
every capability that IS registered must exist as packages/<id>.

Run: pwsh -NoProfile -File tests/Test-Bundles.ps1
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

$bundlesPath = Join-Path $repoRoot 'registry\bundles.json'
$capsPath = Join-Path $repoRoot 'registry\capabilities.json'
$connectorsPath = Join-Path $repoRoot 'registry\native-connectors.json'

Report 'registry/bundles.json exists' (Test-Path -LiteralPath $bundlesPath) 'missing registry/bundles.json'

$bundlesDoc = Get-Content -LiteralPath $bundlesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$caps = Get-Content -LiteralPath $capsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$bundles = @($bundlesDoc.bundles)
Report 'bundles.json declares at least one bundle' ($bundles.Count -gt 0) 'bundles array is empty'

$capabilityIds = @($caps.capabilities | ForEach-Object { [string]$_.id })
$extensionIds = @($connectors.thirdPartyExtensions.extensions | ForEach-Object { [string]$_.extensionId })

$ids = @($bundles | ForEach-Object { [string]$_.id })
Report 'bundle ids are unique' ($ids.Count -eq @($ids | Select-Object -Unique).Count) ("duplicates: " + (($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) -join ', '))

$badCaps = [Collections.Generic.List[string]]::new()
$badExt = [Collections.Generic.List[string]]::new()
$plannedOk = [Collections.Generic.List[string]]::new()
foreach ($b in $bundles) {
    if ([string]::IsNullOrWhiteSpace($b.id)) { $badCaps.Add('a bundle has no id'); continue }
    if ([string]::IsNullOrWhiteSpace($b.title)) { $badCaps.Add("$($b.id): no title") }
    $required = @($b.requires) + @($b.recommends)
    foreach ($capId in $required) {
        if ([string]::IsNullOrWhiteSpace($capId)) { continue }
        if ($capabilityIds -contains $capId) {
            $pkg = Join-Path $repoRoot "packages\$capId"
            if (-not (Test-Path -LiteralPath $pkg)) {
                $badCaps.Add("$($b.id) names registered capability '$capId' but packages/$capId is missing")
            }
        } else {
            # Bundle may name a capability that is registered later.
            $plannedOk.Add("$($b.id)->$capId")
        }
    }
    foreach ($section in @('recommends', 'optional')) {
        $list = @($b.thirdParty.$section)
        foreach ($extId in $list) {
            if ([string]::IsNullOrWhiteSpace($extId)) { continue }
            if ($extensionIds -notcontains $extId) {
                $badExt.Add("$($b.id) thirdParty.$section names '$extId' which is not in thirdPartyExtensions")
            }
        }
    }
}

Report 'every third-party id named by a bundle is tracked in thirdPartyExtensions' ($badExt.Count -eq 0) ($badExt -join '; ')

# A bundle may name a capability that is not registered yet, but only while a
# plan is genuinely in flight. The NOTE at the end of this file is advisory and
# nothing else looked at these ids, so a retired or misspelled one hid in it
# indefinitely: browser-toolkit and learning-studio were both retired on
# 2026-10-30 and were still required or recommended by three bundles.
function Get-UnplannedCapability([string[]]$Named, [string]$PlanText) {
    return @($Named | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique | Where-Object { $PlanText -notmatch [regex]::Escape($_) })
}

$plansDir = Join-Path $repoRoot 'docs\plans\active'
$planText = if (Test-Path -LiteralPath $plansDir) {
    (@(Get-ChildItem -LiteralPath $plansDir -File -Filter '*.md' | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    }) -join "`n")
} else { '' }

$plannedNames = @($plannedOk | ForEach-Object { ($_ -split '->')[1] })
$unplanned = @(Get-UnplannedCapability $plannedNames $planText)
Report 'every unregistered capability a bundle names has an active plan' `
    ($unplanned.Count -eq 0) ("no plan under docs/plans/active names: " + ($unplanned -join ', '))

# An empty or stale plan directory would make the check above pass on nothing,
# so prove the detector rejects an id that no plan mentions.
Report 'the plan detector rejects a capability no plan names' `
    (@(Get-UnplannedCapability @('definitely-not-a-planned-capability') $planText).Count -eq 1) `
    'detector returned nothing for a fabricated id'
Report 'registered capabilities named by bundles have packages on disk' (($badCaps | Where-Object { $_ -match 'packages/' }).Count -eq 0) (($badCaps | Where-Object { $_ -match 'packages/' }) -join '; ')
Report 'technical-series-production bundle exists' ($ids -contains 'technical-series-production') 'missing bundle id technical-series-production'
Report 'engaging-learning bundle exists' ($ids -contains 'engaging-learning') 'missing bundle id engaging-learning'
Report 'local-media-production bundle exists' ($ids -contains 'local-media-production') 'missing bundle id local-media-production'

Write-Host ""
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($plannedOk.Count -gt 0) {
    Write-Host "NOTE: bundles name capabilities that are planned but not yet registered; each is backed by a plan under docs/plans/active: $($plannedOk -join ', ')"
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
