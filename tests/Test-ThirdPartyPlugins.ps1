#Requires -Version 5.1
<#
Behavior tests for native-connectors.json's thirdPartyExtensions block.

AgentHub owns the packages under packages/. It does not own Superpowers,
Remotion, or Creative Writing Skills, and the whole point of that block is to
keep it that way: each host installs a third-party extension from that host's
own official channel, and AgentHub records what was observed there. The failure
this guards is the quiet one -- a host falls behind by a few releases and
nobody notices, because nothing in the repo ever asserted what "current" was.

Renamed from thirdPartyPlugins on 2026-08-21 so skills packages (Remotion) and
similar non-plugin distributions share the same provenance system.

Load-bearing rules are Behavior 3 and 4. A host recorded as NOT current must
say how the owner fixes it, and a host recorded as current must be paired with
an observation date, because "current" decays.

Behavior 5 is the ownership boundary: vendoring a third-party extension into
AgentHub's own marketplace would make AgentHub its publisher and freeze it.

Run: pwsh -NoProfile -File tests/Test-ThirdPartyPlugins.ps1
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

$connectorsPath = Join-Path $repoRoot 'registry\native-connectors.json'
$connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$IsoDate = '^\d{4}-\d{2}-\d{2}$'
$knownKinds = @('plugin', 'skills-package', 'host-native-module')
$knownProvenance = @('official-upstream', 'community-upstream', 'personal-runtime')
$knownMaturity = @('stable', 'beta', 'experimental')

$block = $connectors.thirdPartyExtensions
$extensions = @($block.extensions)

$r1 = if (-not $block) {
    @{ Passed = $false; Detail = 'native-connectors.json declares no thirdPartyExtensions block.' }
} elseif ($extensions.Count -eq 0) {
    @{ Passed = $false; Detail = 'thirdPartyExtensions.extensions is empty; nothing is being tracked.' }
} else {
    @{ Passed = $true; Detail = '' }
}
Report 'thirdPartyExtensions declares at least one tracked extension' $r1.Passed $r1.Detail

Report 'legacy thirdPartyPlugins block is absent after rename' `
    (-not ($connectors.PSObject.Properties.Name -contains 'thirdPartyPlugins')) `
    'native-connectors.json still declares thirdPartyPlugins; remove it so thirdPartyExtensions is the only inventory.'

$bad = foreach ($e in $extensions) {
    if ([string]::IsNullOrWhiteSpace($e.extensionId)) { 'an entry has no extensionId'; continue }
    if ([string]::IsNullOrWhiteSpace($e.upstream)) { "$($e.extensionId): no upstream" }
    if (-not $e.observedAt -or $e.observedAt -notmatch $IsoDate) { "$($e.extensionId): observedAt missing or not ISO yyyy-MM-dd" }
    if (@($e.hostChannels).Count -eq 0) { "$($e.extensionId): no hostChannels" }
    if ($e.kind -notin $knownKinds) { "$($e.extensionId): kind '$($e.kind)' not in $($knownKinds -join ', ')" }
    if ($e.provenance -notin $knownProvenance) { "$($e.extensionId): provenance '$($e.provenance)' not in $($knownProvenance -join ', ')" }
    if ($e.maturity -notin $knownMaturity) { "$($e.extensionId): maturity '$($e.maturity)' not in $($knownMaturity -join ', ')" }
}
Report 'every tracked extension carries extensionId, upstream, ISO observedAt, host channels, kind, provenance, and maturity' `
    (@($bad).Count -eq 0) (@($bad) -join '; ')

$ids = @($extensions | ForEach-Object { [string]$_.extensionId })
Report 'superpowers remains tracked after generalization' ($ids -contains 'superpowers') 'superpowers missing'
Report 'remotion is tracked as an official skills-package extension' ($ids -contains 'remotion') 'remotion missing'

$remotion = @($extensions | Where-Object { $_.extensionId -eq 'remotion' })[0]
if ($remotion) {
    Report 'remotion is not marked required' (-not [bool]$remotion.required) 'remotion.required must be false'
    Report 'remotion declares video.programmatic-composition' `
        (@($remotion.provides) -contains 'video.programmatic-composition') `
        'remotion.provides must include video.programmatic-composition'
}

$cw = @($extensions | Where-Object { $_.extensionId -eq 'creative-writing-skills' })[0]
if ($cw) {
    Report 'creative-writing-skills is optional' (-not [bool]$cw.required) 'creative-writing-skills.required must be false'
    Report 'creative-writing-skills maturity is beta' ($cw.maturity -eq 'beta') "expected beta, got '$($cw.maturity)'"
}

$silentlyBehind = foreach ($e in $extensions) {
    foreach ($h in @($e.hostChannels)) {
        if ($null -ne $h.channel -and -not $h.current -and [string]::IsNullOrWhiteSpace($h.updateCommand)) {
            "$($e.extensionId)/$($h.hostId)"
        }
    }
}
Report 'every host recorded as not current names the command or UI that updates it' `
    (@($silentlyBehind).Count -eq 0) ("no updateCommand: " + (@($silentlyBehind) -join ', '))

$unexplainedGap = foreach ($e in $extensions) {
    foreach ($h in @($e.hostChannels)) {
        if ($null -eq $h.channel -and [string]::IsNullOrWhiteSpace($h.note)) {
            "$($e.extensionId)/$($h.hostId)"
        }
    }
}
Report 'every host with no channel explains why it is a deliberate gap' `
    (@($unexplainedGap).Count -eq 0) ("unexplained: " + (@($unexplainedGap) -join ', '))

$marketplacePath = Join-Path $repoRoot '.claude-plugin\marketplace.json'
$vendored = @()
if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $published = @($marketplace.plugins | ForEach-Object { $_.name })
    $vendored = @($extensions | Where-Object { $published -contains $_.extensionId } | ForEach-Object { $_.extensionId })
}
Report 'no tracked third-party extension is republished from AgentHub own marketplace' `
    (@($vendored).Count -eq 0) ("vendored: " + (@($vendored) -join ', '))

$hpe = $connectors.hostPrivateExtensionPolicy
$r6 = if ($block.policy.agentHubOwnership -ne 'none') {
    @{ Passed = $false; Detail = "thirdPartyExtensions.policy.agentHubOwnership is '$($block.policy.agentHubOwnership)', expected 'none'." }
} elseif ($hpe.agentHubMayInstallOrRemove) {
    @{ Passed = $false; Detail = 'hostPrivateExtensionPolicy now allows AgentHub to install or remove host-private extensions, which contradicts agentHubOwnership: none. Reconcile the two.' }
} else {
    @{ Passed = $true; Detail = '' }
}
Report 'third-party ownership claim agrees with hostPrivateExtensionPolicy' $r6.Passed $r6.Detail

Write-Host ""
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
