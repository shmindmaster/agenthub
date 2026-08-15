#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}
function Read-Json([string]$RelativePath) {
    Get-Content -LiteralPath (Join-Path $repoRoot $RelativePath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$agents = Read-Json 'registry\agents.json'
$capabilities = Read-Json 'registry\capabilities.json'
$mcps = Read-Json 'registry\mcps.json'
$formats = Read-Json 'registry\plugin-formats.json'
$connectors = Read-Json 'registry\native-connectors.json'
$mobile = @($capabilities.capabilities | Where-Object id -eq 'mobile-device-lab')
$appium = @($mcps.mcpServers | Where-Object id -eq 'appium-mobile')
$packageRoot = Join-Path $repoRoot 'packages\mobile-device-lab'
$syncScriptText = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') -Raw -Encoding UTF8
$mcpSmokeText = Get-Content -LiteralPath (Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Invoke-AppiumMcpSmoke.mjs') -Raw -Encoding UTF8

Report 'one canonical mobile capability exists' ($mobile.Count -eq 1) "count=$($mobile.Count)"
Report 'one pinned Appium MCP exists' ($appium.Count -eq 1 -and $appium[0].command -eq 'npx' -and 'appium-mcp@1.92.0' -in @($appium[0].args)) 'Expected registry/mcps.json#appium-mobile pinned to appium-mcp@1.92.0.'
Report 'Appium is the reviewed persistent on-demand exception' ('appium-mobile' -in @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)) 'Add only appium-mobile to persistedOnDemandLocalMcpIds.'
Report 'persistent on-demand exceptions participate in every sync scope' (
    $syncScriptText -match '\$scopedCandidateServers\s*\+\s*\$persistentExceptionServers'
) 'Merge reviewed persistent exceptions after scope selection so default audits agree with on-demand deployment.'
Report 'Grok partial-scope sync preserves existing section order' (
    $syncScriptText -match '\$canonicalSectionExists' -and
    $syncScriptText -match 'partial scope must not move an existing section'
) 'Replace existing Grok MCP sections in place so cross-scope audits are idempotent.'

$manifestByHost = @{}
foreach ($formatHost in @($formats.hosts)) { $manifestByHost[[string]$formatHost.id] = [string]$formatHost.manifest }
$mappingByHost = @{}
foreach ($mapping in @($mobile[0].hostMappings)) { $mappingByHost[[string]$mapping.hostId] = $mapping }
$inherits = @{
    'cursor-agent' = 'cursor'
    'opencode-desktop' = 'opencode'
    'antigravity-desktop' = 'antigravity'
    'antigravity-ide' = 'antigravity'
}

foreach ($agent in @($agents.activeAgents | Where-Object status -eq 'active')) {
    $hostId = [string]$agent.id
    $effectiveHost = if ($inherits.ContainsKey($hostId)) { $inherits[$hostId] } else { $hostId }
    $mapping = $mappingByHost[$effectiveHost]
    $format = @($formats.hosts | Where-Object id -eq $effectiveHost | Select-Object -First 1)
    $hasInstructionRoute = $mapping -and ($agent.nativePaths.skillsDir -or ($format.Count -eq 1 -and ($format[0].globalSkillsDir -or $format[0].alsoScannedSkillsDirs)))
    Report "$hostId has discoverable mobile instructions" ([bool]$hasInstructionRoute) "effectiveHost=$effectiveHost mapping=$($mapping.deploymentStatus)"

    $status = if ($mapping) { [string]$mapping.deploymentStatus } else { '' }
    $packageBacked = $status -in @('plugin-owned', 'native-plugin-installed', 'native-local-plugin', 'native-extension-junction')
    $directBacked = $status -match 'mcp'
    $packageManifest = if ($manifestByHost.ContainsKey($effectiveHost)) { $manifestByHost[$effectiveHost] } else { $null }
    $packageRoute = $packageBacked -and $packageManifest -and (Test-Path -LiteralPath (Join-Path $packageRoot $packageManifest))
    $directRoute = $directBacked -and $effectiveHost -in @($appium[0].hosts) -and 'appium-mobile' -in @($connectors.lifecyclePolicy.persistedOnDemandLocalMcpIds)
    Report "$hostId has an Appium MCP activation route" ([bool]($packageRoute -or $directRoute)) "status=$status manifest=$packageManifest direct=$directRoute"
}

foreach ($agent in @($agents.activeAgents | Where-Object status -eq 'unverified')) {
    $declared = [string]$agent.executable
    $resolves = $false
    if ($declared) {
        if ([IO.Path]::IsPathRooted($declared)) { $resolves = Test-Path -LiteralPath $declared }
        else { $resolves = [bool](Get-Command $declared -ErrorAction SilentlyContinue) }
    }
    Report "$($agent.id) is not counted functional without an executable" (-not $resolves) "status=$($agent.status) executable=$declared"
}

foreach ($connectorHost in @($connectors.hosts | Where-Object exposures)) {
    $routes = @($connectorHost.exposures.'plugin-owned') + @($connectorHost.exposures.'native-connector') +
        @($connectorHost.exposures.'shared-gateway') + @($connectorHost.exposures.'local-only')
    Report "$($connectorHost.hostId) classifies exactly one Appium route" (@($routes | Where-Object { $_ -eq 'appium-mobile' }).Count -eq 1) 'Classify appium-mobile exactly once as plugin-owned or local-only.'
}

$fixtureRoot = Join-Path $packageRoot 'fixtures\smoke-app'
$fixtureText = (Get-Content -LiteralPath (Join-Path $fixtureRoot 'app.json') -Raw -Encoding UTF8) +
    (Get-Content -LiteralPath (Join-Path $fixtureRoot 'package.json') -Raw -Encoding UTF8)
Report 'synthetic fixture is local-only and has no durable cloud identity' (
    (Test-Path -LiteralPath (Join-Path $fixtureRoot 'App.js')) -and
    (Test-Path -LiteralPath (Join-Path $fixtureRoot '.maestro\smoke.yaml')) -and
    -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'eas.json')) -and
    $fixtureText -notmatch 'projectId|owner|updates\.url|store'
) 'Fixture must not declare EAS project IDs, owners, store metadata, or cloud update URLs.'
Report 'cross-platform MCP interactions bind to explicit concurrent session IDs' (
    $mcpSmokeText -match 'exerciseSession\("android",\s*report\.android\.sessionId\)' -and
    $mcpSmokeText -match 'exerciseSession\("ios",\s*report\.ios\.sessionId\)' -and
    $mcpSmokeText -match 'appium_get_page_source",\s*\{ sessionId \}'
) 'Do not rely on Appium MCP active-session state after Android and iOS coexist.'

if ($failures.Count) {
    Write-Host "`n$($failures.Count) of $reported mobile reachability checks failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll $reported mobile reachability checks passed." -ForegroundColor Green
