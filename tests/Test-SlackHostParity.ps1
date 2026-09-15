#Requires -Version 5.1
<#
Parity for Slack is the same contract on every host, not "an MCP exists
somewhere". This file checks the registry wiring: one capability, one MCP
id, plugin-gated delivery, gateway recorded but not claimed live, official
Slack plugin tracked as optional UX.

Run: pwsh -NoProfile -File tests/Test-SlackHostParity.ps1
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

function Read-Json([string]$Rel) {
    Get-Content -LiteralPath (Join-Path $repoRoot $Rel) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$caps = Read-Json 'registry\capabilities.json'
$mcps = Read-Json 'registry\mcps.json'
$agents = Read-Json 'registry\agents.json'
$conn = Read-Json 'registry\native-connectors.json'
$gateway = Read-Json 'registry\gateway-profiles.json'
$marketplace = Read-Json '.agents\plugins\marketplace.json'
$claudeMarket = Read-Json '.claude-plugin\marketplace.json'
$bundles = Read-Json 'registry\bundles.json'

$cap = @($caps.capabilities | Where-Object { $_.id -eq 'slack' })[0]
Report 'capabilities.json has id slack' ($null -ne $cap) 'missing capability slack'
if ($cap) {
    Report 'slack canonicalSource is packages/slack' ($cap.canonicalSource -eq 'packages/slack') $cap.canonicalSource
    Report 'slack managed skill is slack' (@($cap.managedSkillNames) -contains 'slack') (($cap.managedSkillNames) -join ',')
    $mapped = @($cap.hostMappings | ForEach-Object { [string]$_.hostId })
    Report 'slack maps to at least 15 hosts' ($mapped.Count -ge 15) "mapped $($mapped.Count)"
    $known = @(@($agents.activeAgents) + @($agents.inactiveAgents) | ForEach-Object { [string]$_.id })
    $stray = @($mapped | Where-Object { $known -notcontains $_ })
    Report 'every slack hostMapping resolves in agents.json' ($stray.Count -eq 0) ($stray -join ', ')
    $pluginHosts = @('claude', 'codex', 'cursor', 'grok')
    foreach ($hid in $pluginHosts) {
        $row = @($cap.hostMappings | Where-Object { $_.hostId -eq $hid })[0]
        Report "slack mapping for $hid includes mcp" (
            $null -ne $row -and @($row.components) -contains 'mcp'
        ) "expected components mcp on $hid"
    }
}

$server = @($mcps.mcpServers | Where-Object { $_.id -eq 'slack' })[0]
Report 'mcps.json has id slack' ($null -ne $server) 'missing MCP slack'
if ($server) {
    Report 'slack MCP is on-demand-local' ($server.activationMode -eq 'on-demand-local') $server.activationMode
    Report 'slack MCP is stdio' ($server.transport -eq 'stdio') $server.transport
    Report 'slack MCP startupEnabled is false' ($server.startupEnabled -eq $false) "startupEnabled=$($server.startupEnabled)"
    Report 'slack MCP is owned by capability slack' ($server.owner.type -eq 'capability' -and $server.owner.id -eq 'slack') 'wrong owner'
    Report 'slack MCP is not Slack hosted MCP' (
        [string]$server.url -notmatch 'mcp\.slack\.com' -and [string]$server.url -notmatch 'slack\.com/mcp'
    ) 'do not point the canonical server at Slack hosted MCP'
    Report 'slack protocol revision is recorded' (
        [string]$server.protocol.revision -eq '2025-11-25' -and
        [string]$server.protocol.verifiedOn -match '^\d{4}-\d{2}-\d{2}$'
    ) 'protocol block incomplete'
    $localHosts = @($server.hosts | Where-Object { $_ })
    $installed = @($mcps.hostInventory.hosts)
    $badLocal = @($localHosts | Where-Object { $installed -notcontains $_ })
    Report 'slack MCP hosts are installed' ($badLocal.Count -eq 0) ($badLocal -join ', ')
}

$lifecycle = $conn.lifecyclePolicy
Report 'slack is on-demand-local in lifecyclePolicy' (@($lifecycle.onDemandLocalMcpIds) -contains 'slack') 'add slack to onDemandLocalMcpIds'
Report 'slack is not session-start persisted' (@($lifecycle.persistedOnDemandLocalMcpIds) -notcontains 'slack') 'do not persist stdio slack'
Report 'slack is opt-in-disabled' (@($lifecycle.optInDisabledLocalMcpIds) -contains 'slack') 'add slack to optInDisabledLocalMcpIds'

$pluginOwned = @{}
foreach ($h in @($conn.hosts)) {
    foreach ($sid in @($h.exposures.'plugin-owned')) {
        if ($sid -eq 'slack') { $pluginOwned[[string]$h.hostId] = $true }
    }
}
foreach ($hid in @('claude', 'codex', 'cursor', 'grok')) {
    Report "native-connectors plugin-owned slack on $hid" ($pluginOwned.ContainsKey($hid)) "missing plugin-owned slack for $hid"
}

$mapping = $null
foreach ($cand in @($gateway.candidates)) {
    foreach ($row in @($cand.serverMappings)) {
        if ($row.mcpId -eq 'slack') { $mapping = $row; break }
    }
}
Report 'gateway-profiles maps mcpId slack' ($null -ne $mapping) 'add a slack serverMapping'
if ($mapping) {
    Report 'gateway does not claim Slack is production-routed yet' (
        [string]$mapping.proofState -match 'not-yet|discovery-required|contract-defined'
    ) "proofState=$($mapping.proofState)"
    Report 'gateway generation remains disabled' (
        @($gateway.candidates | Where-Object { $_.generationEnabled -eq $true }).Count -eq 0
    ) 'do not enable gateway generation in this milestone'
}

$marketNames = @($marketplace.plugins | ForEach-Object name)
$claudeNames = @($claudeMarket.plugins | ForEach-Object name)
Report 'agenthub marketplace catalogs slack' ($marketNames -contains 'slack') 'add packages/slack to .agents/plugins/marketplace.json'
Report 'claude marketplace catalogs slack' ($claudeNames -contains 'slack') 'add packages/slack to .claude-plugin/marketplace.json'

$ext = @($conn.thirdPartyExtensions.extensions | Where-Object { $_.extensionId -eq 'slack-skills-plugin' })[0]
Report 'official Slack plugin is tracked as slack-skills-plugin' ($null -ne $ext) 'do not use extensionId slack; that would collide with AgentHub marketplace name slack'
if ($ext) {
    Report 'official Slack plugin is optional UX' (-not [bool]$ext.required) 'required must be false'
    Report 'official Slack plugin is not AgentHub-owned' ($ext.provenance -eq 'official-upstream') $ext.provenance
}

$bundle = @($bundles.bundles | Where-Object { $_.id -eq 'slack-workspace' })[0]
Report 'slack-workspace bundle exists' ($null -ne $bundle) 'add bundle slack-workspace'
if ($bundle) {
    Report 'bundle requires AgentHub slack capability' (@($bundle.requires) -contains 'slack') 'requires must include slack'
    Report 'bundle treats official plugin as optional' (@($bundle.thirdParty.optional) -contains 'slack-skills-plugin') 'optional slack-skills-plugin'
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
