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
            # Allowed while the creative-capabilities plan is landing packages.
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
Report 'registered capabilities named by bundles have packages on disk' (($badCaps | Where-Object { $_ -match 'packages/' }).Count -eq 0) (($badCaps | Where-Object { $_ -match 'packages/' }) -join '; ')
Report 'technical-series-production bundle exists' ($ids -contains 'technical-series-production') 'missing bundle id technical-series-production'
Report 'engaging-learning bundle exists' ($ids -contains 'engaging-learning') 'missing bundle id engaging-learning'
Report 'local-media-production bundle exists' ($ids -contains 'local-media-production') 'missing bundle id local-media-production'

Write-Host ""
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($plannedOk.Count -gt 0) {
    Write-Host "NOTE: bundles reference not-yet-registered capabilities (expected during plan landing): $($plannedOk -join ', ')"
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
