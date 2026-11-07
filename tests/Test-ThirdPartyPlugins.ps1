#Requires -Version 5.1
<#
Behavior tests for native-connectors.json's thirdPartyExtensions block.

AgentHub owns the packages under packages/. It does not own Superpowers,
Firecrawl, Clerk, Railway, Framer, Remotion, CodeRabbit, or Creative Writing Skills, and
the whole point of that block is to keep it that way: each host installs a
third-party extension from that host's own official channel, and AgentHub
records what was observed there. The failure this guards is the quiet one --
a host falls behind by a few releases and nobody notices, because nothing in
the repo ever asserted what "current" was. Republishing those catalogs from
the AgentHub marketplace was the other failure: it pinned hosts to the last
copied revision and could overwrite a newer official install.

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
Report 'retired Firecrawl catalog is absent' ($ids -notcontains 'firecrawl') 'Firecrawl was removed by owner direction'
Report 'coderabbit official catalog is tracked rather than republished' ($ids -contains 'coderabbit') 'coderabbit missing'
Report 'clerk-skills official catalog is tracked rather than republished' ($ids -contains 'clerk-skills') 'clerk-skills missing'
Report 'railway is neither tracked nor vendored' ($ids -notcontains 'railway') 'railway is still a tracked extension; owner removed it 2026-11-06'
Report 'framer-agent official installer is tracked rather than vendored' ($ids -contains 'framer-agent') 'framer-agent missing'

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

# A republished extension is one whose own upstream name shows up as an AgentHub
# marketplace plugin, which is what clerk@agenthub was before 2026-08-24. A
# separate rule already forces every entry to ah-<folder>, so this detector
# cannot fire on the live catalogs today; it is the backstop for the day someone
# adds one back. Both catalogs are read, because .agents/plugins/marketplace.json
# is canonical and .claude-plugin/marketplace.json is only a projection. Proving
# the detector can fail is what keeps it a check rather than a comment.
function Get-RepublishedExtension([string[]]$Published, [string[]]$ExtensionIds) {
    return @($ExtensionIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique | Where-Object { $Published -contains $_ })
}

$publishedNames = @()
foreach ($catalog in @('.agents\plugins\marketplace.json', '.claude-plugin\marketplace.json')) {
    $catalogPath = Join-Path $repoRoot $catalog
    $exists = Test-Path -LiteralPath $catalogPath
    Report "marketplace catalog $catalog exists" $exists "missing $catalog"
    if (-not $exists) { continue }
    $doc = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $publishedNames += @($doc.plugins | ForEach-Object { [string]$_.name })
}
$extensionIds = @($extensions | ForEach-Object { [string]$_.extensionId })
$vendored = @(Get-RepublishedExtension $publishedNames $extensionIds)
Report 'no tracked third-party extension is republished from either AgentHub marketplace' `
    ($vendored.Count -eq 0) ("vendored: " + ($vendored -join ', '))
Report 'both marketplace catalogs were read before claiming nothing is republished' `
    ($publishedNames.Count -gt 0) 'no plugin names were read from either catalog'
Report 'the republishing detector flags an upstream plugin published under its own name' `
    (@(Get-RepublishedExtension @('ah-daytona', 'daytona') @('daytona', 'clerk-skills')).Count -eq 1) `
    'detector did not flag a fixture catalog entry named daytona against the tracked daytona extension'

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
