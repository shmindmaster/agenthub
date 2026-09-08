#Requires -Version 5.1
<#
On-demand local MCP servers must not start at session start.

OpenCode is the verified host that may *write* them with enabled=false
(https://opencode.ai/docs/mcp-servers/). Plugin hosts keep them out of
host MCP config.

Run: pwsh -NoProfile -File tests/Test-OptInDisabledMcp.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report([string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp = Get-Content (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$conn = Get-Content (Join-Path $repoRoot 'registry\native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$persisted = @($conn.lifecyclePolicy.persistedOnDemandLocalMcpIds)
$optIn = @($conn.lifecyclePolicy.optInDisabledLocalMcpIds)
$optHosts = @($conn.lifecyclePolicy.optInDisabledHosts)

foreach ($id in @('playwright', 'chrome-devtools', 'linkedin', 'appium-mobile')) {
    Report "'$id' is not session-start persisted" ($id -notin $persisted) "still in persistedOnDemandLocalMcpIds"
}
foreach ($id in @('playwright', 'chrome-devtools', 'linkedin')) {
    Report "'$id' is opt-in-disabled" ($id -in $optIn) "missing from optInDisabledLocalMcpIds"
}
Report 'OpenCode is the opt-in-disabled host' ($optHosts -contains 'opencode') "optInDisabledHosts=$($optHosts -join ',')"
Report 'Grok is not an opt-in-disabled host' ($optHosts -notcontains 'grok') 'Grok would start stdio MCP from config.toml'

$li = @($mcp.mcpServers | Where-Object id -eq 'linkedin')[0]
Report 'linkedin MCP is registered' ($null -ne $li) 'missing from mcps.json'
if ($li) {
    Report 'linkedin is on-demand-local' ($li.activationMode -eq 'on-demand-local') "activationMode=$($li.activationMode)"
    Report 'linkedin startupEnabled is false' ($li.startupEnabled -eq $false) "startupEnabled=$($li.startupEnabled)"
    Report 'linkedin pins mcp-server-linkedin@4.24.0' (($li.args -join ' ') -match 'mcp-server-linkedin@4\.24\.0') ($li.args -join ' ')
}

$pluginMcp = Get-Content (Join-Path $repoRoot 'packages\linkedin\.mcp.json') -Raw -Encoding UTF8
Report 'linkedin plugin declares mcp id linkedin' ($pluginMcp -match '"linkedin"') 'packages/linkedin/.mcp.json'
$catalog = Get-Content (Join-Path $repoRoot '.agents\plugins\marketplace.json') -Raw -Encoding UTF8
Report 'agenthub marketplace catalogs linkedin' ($catalog -match '"linkedin"') 'missing from .agents/plugins/marketplace.json'
$claudeCat = Get-Content (Join-Path $repoRoot '.claude-plugin\marketplace.json') -Raw -Encoding UTF8
Report 'claude marketplace catalogs linkedin' ($claudeCat -match '"linkedin"') 'missing from .claude-plugin/marketplace.json'

$sync = Get-Content (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') -Raw -Encoding UTF8
Report 'sync reads optInDisabledLocalMcpIds' ($sync -match 'optInDisabledLocalMcpIds') 'Sync-AgentHub does not consume the list'
Report 'sync reads optInDisabledHosts' ($sync -match 'optInDisabledHosts') 'Sync-AgentHub does not consume the host list'

$oc = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
if (Test-Path $oc) {
    $oj = Get-Content $oc -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($id in @('playwright', 'chrome-devtools', 'linkedin')) {
        $node = $oj.mcp.$id
        if ($null -eq $node) {
            Report "OpenCode config lists '$id'" $false 'absent — run Sync-AgentHub -Apply after registry change'
            continue
        }
        Report "OpenCode '$id' is disabled" ($node.enabled -eq $false) "enabled=$($node.enabled)"
    }
} else {
    Report 'OpenCode config exists to check opt-in MCP' $false "missing $oc"
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
