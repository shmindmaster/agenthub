#Requires -Version 5.1
<#
Behavior tests for native-connectors.json's thirdPartyPlugins block.

AgentHub owns the packages under packages/. It does not own superpowers, and
the whole point of that block is to keep it that way: each host installs a
third-party plugin from that host's own official channel, and AgentHub records
what was observed there. The failure this guards is the quiet one -- a host
falls behind by a few releases and nobody notices, because nothing in the repo
ever asserted what "current" was.

So the load-bearing rules are Behavior 3 and 4. A host recorded as NOT current
must say how the owner fixes it, and a host recorded as current must be paired
with an observation date, because "current" decays. Neither rule can be
satisfied by adding a field; both are cheapest to satisfy by updating the host.

Behavior 5 is the ownership boundary. Vendoring a third-party plugin into
.claude-plugin/marketplace.json would make AgentHub its publisher and freeze it
at whatever revision was copied -- exactly the drift this block exists to
detect. The test refuses that shortcut structurally rather than by convention.

Run: pwsh -NoProfile -File tests/Test-ThirdPartyPlugins.ps1
     powershell.exe -NoProfile -File tests/Test-ThirdPartyPlugins.ps1
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

# -Encoding UTF8 for the same reason Test-OwnerActions.ps1 states: 5.1 decodes a
# BOM-less file as the ANSI code page, so the two shells would otherwise read
# different bytes.
$connectorsPath = Join-Path $repoRoot 'registry\native-connectors.json'
$connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$IsoDate = '^\d{4}-\d{2}-\d{2}$'

# Behavior 1 -- the block exists and is populated. Every behavior below iterates
# it, so its absence would make this whole file pass over nothing.
$block = $connectors.thirdPartyPlugins
$plugins = @($block.plugins)
$r1 = if (-not $block) {
    @{ Passed = $false; Detail = 'native-connectors.json declares no thirdPartyPlugins block.' }
} elseif ($plugins.Count -eq 0) {
    @{ Passed = $false; Detail = 'thirdPartyPlugins.plugins is empty; nothing is being tracked.' }
} else {
    @{ Passed = $true; Detail = '' }
}
Report 'thirdPartyPlugins declares at least one tracked plugin' $r1.Passed $r1.Detail

# Behavior 2 -- schema. An entry without an upstream is unverifiable, and one
# without host channels records nothing about the fleet.
$bad = foreach ($p in $plugins) {
    if ([string]::IsNullOrWhiteSpace($p.pluginId)) { 'an entry has no pluginId'; continue }
    if ([string]::IsNullOrWhiteSpace($p.upstream)) { "$($p.pluginId): no upstream" }
    if (-not $p.observedAt -or $p.observedAt -notmatch $IsoDate) { "$($p.pluginId): observedAt missing or not ISO yyyy-MM-dd" }
    if (@($p.hostChannels).Count -eq 0) { "$($p.pluginId): no hostChannels" }
}
Report 'every tracked plugin carries pluginId, upstream, ISO observedAt, and host channels' (@($bad).Count -eq 0) (@($bad) -join '; ')

# Behavior 3 -- a host that is behind must say how the owner fixes it. This is
# the rule that turns the block from an inventory into something actionable.
$silentlyBehind = foreach ($p in $plugins) {
    foreach ($h in @($p.hostChannels)) {
        # A null channel is a declared absence (upstream supports no such host),
        # which Behavior 4 covers. This rule is about hosts that HAVE it and lag.
        if ($null -ne $h.channel -and -not $h.current -and [string]::IsNullOrWhiteSpace($h.updateCommand)) {
            "$($p.pluginId)/$($h.hostId)"
        }
    }
}
Report 'every host recorded as not current names the command or UI that updates it' (@($silentlyBehind).Count -eq 0) ("no updateCommand: " + (@($silentlyBehind) -join ', '))

# Behavior 4 -- a host with no channel is a deliberate gap, not an oversight, and
# has to say why. Otherwise "not installed anywhere" reads identically to
# "nobody got around to it".
$unexplainedGap = foreach ($p in $plugins) {
    foreach ($h in @($p.hostChannels)) {
        if ($null -eq $h.channel -and [string]::IsNullOrWhiteSpace($h.note)) { "$($p.pluginId)/$($h.hostId)" }
    }
}
Report 'every host with no channel explains why it is a deliberate gap' (@($unexplainedGap).Count -eq 0) ("unexplained: " + (@($unexplainedGap) -join ', '))

# Behavior 5 -- the ownership boundary, asserted structurally. If a tracked
# third-party plugin ever appears in AgentHub's own marketplace, AgentHub has
# become its publisher and the upstream release stream is cut off.
$marketplacePath = Join-Path $repoRoot '.claude-plugin\marketplace.json'
$vendored = @()
if (Test-Path -LiteralPath $marketplacePath) {
    $marketplace = Get-Content -LiteralPath $marketplacePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $published = @($marketplace.plugins | ForEach-Object { $_.name })
    $vendored = @($plugins | Where-Object { $published -contains $_.pluginId } | ForEach-Object { $_.pluginId })
}
Report 'no tracked third-party plugin is republished from AgentHub own marketplace' (@($vendored).Count -eq 0) ("vendored: " + (@($vendored) -join ', '))

# Behavior 6 -- the recorded install authority must stay consistent with
# hostPrivateExtensionPolicy. If that policy ever grants AgentHub install rights,
# this block's "agentHubOwnership: none" claim is stale and misleading.
$hpe = $connectors.hostPrivateExtensionPolicy
$r6 = if ($block.policy.agentHubOwnership -ne 'none') {
    @{ Passed = $false; Detail = "thirdPartyPlugins.policy.agentHubOwnership is '$($block.policy.agentHubOwnership)', expected 'none'." }
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
