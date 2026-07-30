#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
$fleetProfile = Get-Content (Join-Path $RegistryRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'AgentCtl.CursorReadiness.ps1')
$mcpRegistry = Get-Content (Join-Path $RegistryRoot 'registry\mcps.json') -Raw | ConvertFrom-Json
$connectorRegistry = Get-Content (Join-Path $RegistryRoot 'registry\native-connectors.json') -Raw | ConvertFrom-Json
$expectedGlobal = @($mcpRegistry.mcpServers | Where-Object scope -eq 'global-default' | ForEach-Object id | Sort-Object)
$pluginOwnedByHost = @{}
foreach ($mcp in @($mcpRegistry.mcpServers)) {
  $ownersProperty = $mcp.PSObject.Properties['pluginOwnersByHost']
  if ($ownersProperty -and $ownersProperty.Value) {
    foreach ($owner in $ownersProperty.Value.PSObject.Properties) {
      $hostId = [string]$owner.Name
      if (-not $pluginOwnedByHost.ContainsKey($hostId)) { $pluginOwnedByHost[$hostId] = @{} }
      $pluginOwnedByHost[$hostId][[string]$mcp.id] = $true
    }
  }
}
$failures = @()
function Assert-Profile([bool]$Condition, [string]$Check) {
  if ($Condition) { Write-Host "PASS  $Check" -ForegroundColor Green }
  else { Write-Host "FAIL  $Check" -ForegroundColor Red; $script:failures += $Check }
}
function Read-ServerSet([string]$Path, [string]$Property) {
  try {
    $root = Get-Content $Path -Raw | ConvertFrom-Json
    $propertyInfo = $root.PSObject.Properties[$Property]
    if ($null -eq $propertyInfo) { return $null }
    return $propertyInfo.Value
  } catch { return @() }
}
function Read-ServerNames([string]$Path, [string]$Property) {
  $serverSet = Read-ServerSet $Path $Property
  if ($null -eq $serverSet) { return @() }
  return @($serverSet.PSObject.Properties.Name | Sort-Object)
}

$mcpPaths = @{
  'claude' = @("$UserProfile\.claude.json", 'mcpServers')
  'cursor' = @("$UserProfile\.cursor\mcp.json", 'mcpServers')
  'factory' = @("$UserProfile\.factory\mcp.json", 'mcpServers')
  'devin' = @("$env:APPDATA\devin\config.json", 'mcpServers')
  'amp' = @("$UserProfile\.config\amp\settings.json", 'amp.mcpServers')
  'windsurf' = @("$UserProfile\.codeium\windsurf\mcp_config.json", 'mcpServers')
  'copilot' = @("$UserProfile\.copilot\mcp-config.json", 'mcpServers')
  'gemini' = @("$UserProfile\.gemini\settings.json", 'mcpServers')
  'antigravity' = @("$UserProfile\.gemini\antigravity\mcp_config.json", 'mcpServers')
  'warp' = @("$UserProfile\.warp\.mcp.json", 'mcpServers')
  'cline' = @("$UserProfile\.cline\data\settings\cline_mcp_settings.json", 'mcpServers')
  'qoder' = @("$UserProfile\.qoder\settings.json", 'mcpServers')
  'qwen' = @("$UserProfile\.qwen\settings.json", 'mcp')
}
foreach ($hostId in $mcpPaths.Keys | Sort-Object) {
  $path, $prop = $mcpPaths[$hostId]
  $actual = Read-ServerNames $path $prop
  $registryHostId = if ($hostId -eq 'qwen') { 'qwen-code' } else { $hostId }
  $connectorRows = @($connectorRegistry.hosts | Where-Object hostId -eq $registryHostId)
  Assert-Profile ($connectorRows.Count -eq 1) "$hostId has one native-connector ownership row"
  $expectedForHost = if ($connectorRows.Count -eq 1) {
    @($connectorRows[0].exposures.'shared-gateway' | Sort-Object -Unique)
  } else {
    @()
  }
  if ($hostId -eq 'qwen') { $actual = @((Get-Content $path -Raw | ConvertFrom-Json).mcp.allowed | Sort-Object) }
  Assert-Profile (($actual -join '|') -eq ($expectedForHost -join '|')) "$hostId has the canonical MCP registrations"
  $leakedLocalMcpIds = @($actual | Where-Object {
    $_ -in @($connectorRegistry.lifecyclePolicy.onDemandLocalMcpIds)
  })
  Assert-Profile ($leakedLocalMcpIds.Count -eq 0) "$hostId omits on-demand local MCP registrations"
  $configRaw = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
  Assert-Profile ($configRaw -notmatch 'exaApiKey=|fc-[a-z0-9]{20,}|pendoah\.app\.n8n') "$hostId has no stale embedded-provider endpoint"
}

$codexConfigPath = "$UserProfile\.codex\config.toml"
$codexRaw = if (Test-Path -LiteralPath $codexConfigPath) { Get-Content -LiteralPath $codexConfigPath -Raw } else { '' }
foreach ($pluginOwnedKey in @($pluginOwnedByHost['codex'].Keys)) {
  $escapedKey = [regex]::Escape([string]$pluginOwnedKey)
  Assert-Profile ($codexRaw -notmatch "(?m)^\[mcp_servers\.$escapedKey\]") "codex omits plugin-owned MCP: $pluginOwnedKey"
}
$portfolioSection = [regex]::Match(
  $codexRaw,
  '(?ms)^\[marketplaces\.portfolio\]\s*$.*?(?=^\[|\z)'
).Value
$portfolioSource = [regex]::Match(
  $portfolioSection,
  "(?m)^source\s*=\s*['`"](?<value>[^'`"]+)['`"]\s*$"
)
$expectedPortfolioSource = '\\?\C:\Repos\shmindmaster\agenthub\packages\portfolio-plugins'
Assert-Profile (
  $portfolioSource.Success -and
  $portfolioSource.Groups['value'].Value -ceq $expectedPortfolioSource
) 'Codex portfolio marketplace uses the canonical AgentHub repository'
$retiredShwikiSkillPaths = @(
  "$UserProfile\.agents\skills\shwiki-context",
  "$UserProfile\.claude\skills\shwiki-context",
  "$UserProfile\.codex\skills\shwiki-context",
  "$UserProfile\.cursor\skills\shwiki-context",
  "$UserProfile\.qwen\skills\shwiki-context",
  "$UserProfile\.config\opencode\skills\shwiki-context",
  "$UserProfile\.factory\skills\shwiki-context",
  "$env:APPDATA\devin\skills\shwiki-context",
  "$UserProfile\.config\amp\skills\shwiki-context",
  "$UserProfile\.codeium\windsurf\skills\shwiki-context",
  "$UserProfile\.gemini\skills\shwiki-context",
  "$UserProfile\AppData\Local\hermes\skills\shwiki-context",
  "$UserProfile\.grok\skills\shwiki-context",
  "$UserProfile\.gemini\config\skills\shwiki-context",
  "$UserProfile\.warp\skills\shwiki-context",
  "$UserProfile\.copilot\skills\shwiki-context",
  "$UserProfile\.cline\skills\shwiki-context",
  "$UserProfile\.qoder\skills\shwiki-context"
)
Assert-Profile (
  @($retiredShwikiSkillPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0
) 'retired shwiki-context loose skills are absent'

$claude = Get-Content "$UserProfile\.claude\settings.json" -Raw | ConvertFrom-Json
$qwen = Get-Content "$UserProfile\.qwen\settings.json" -Raw | ConvertFrom-Json
$openCode = Get-Content "$UserProfile\.config\opencode\opencode.json" -Raw | ConvertFrom-Json
$cursor = Get-Content "$UserProfile\.cursor\cli-config.json" -Raw | ConvertFrom-Json
$antigravity = Get-Content "$UserProfile\.gemini\antigravity-cli\settings.json" -Raw | ConvertFrom-Json
$amp = Get-Content "$UserProfile\.config\amp\settings.json" -Raw | ConvertFrom-Json
$factory = Get-Content "$UserProfile\.factory\settings.json" -Raw | ConvertFrom-Json
$copilot = Get-Content "$UserProfile\.copilot\settings.json" -Raw | ConvertFrom-Json
$grokToml = Get-Content "$UserProfile\.grok\config.toml" -Raw -ErrorAction SilentlyContinue
Assert-Profile ($claude.permissions.defaultMode -eq 'bypassPermissions') 'Claude Code default is bypassPermissions'
Assert-Profile ($qwen.tools.approvalMode -eq 'yolo') 'Qwen Code default is yolo'
Assert-Profile ($qwen.memory.enableManagedAutoMemory -eq $true -and $qwen.memory.enableManagedAutoDream -eq $true) 'Qwen Code managed memory and background consolidation are enabled'
foreach ($name in 'scout','implementer','reviewer','verifier') {
  $agentPath = Join-Path $UserProfile ".qwen\agents\$name.md"
  Assert-Profile ((Test-Path -LiteralPath $agentPath) -and (Get-Content -LiteralPath $agentPath -Raw) -match ("(?m)^name:\s*" + [regex]::Escape($name) + "\s*$")) "Qwen native subagent is present: $name"
}
$qwenPrimary = @($qwen.modelProviders.openai | Where-Object id -eq 'qwen3.8-max-preview' | Select-Object -First 1)
Assert-Profile ($qwenPrimary.Count -eq 1 -and $qwenPrimary[0].generationConfig.thinkingMandatory -eq $true -and $qwenPrimary[0].generationConfig.extra_body.enable_thinking -eq $true) 'Qwen 3.8 keeps mandatory thinking enabled for /compress side queries'
Assert-Profile ($openCode.permission -eq 'allow') 'OpenCode allows every permission class'
$cursorYoloLauncher = Get-Content "$UserProfile\bin\cursor-agent.cmd" -Raw -ErrorAction SilentlyContinue
$cursorPosixLauncher = Get-Content "$UserProfile\bin\cursor-agent" -Raw -ErrorAction SilentlyContinue
$cursorIdeLauncher = Get-Content "$UserProfile\bin\cursor.cmd" -Raw -ErrorAction SilentlyContinue
$cursorIdePosixLauncher = Get-Content "$UserProfile\bin\cursor" -Raw -ErrorAction SilentlyContinue
if (Test-CursorDispatchEnabled $fleetProfile) {
  Assert-Profile (($cursor.approvalMode -eq 'unrestricted' -or $cursorYoloLauncher -match '--yolo') -and $cursorPosixLauncher -match '--yolo' -and $cursor.sandbox.mode -eq 'disabled') 'Cursor defaults to yolo and is unsandboxed'
} else {
  $normalize = { param([string]$Value) $Value.Replace("`r`n", "`n").TrimEnd("`r", "`n") }
  $expectedCmd = & $normalize (Get-CursorBlockedLauncherContent -Shell cmd)
  $expectedPosix = & $normalize (Get-CursorBlockedLauncherContent -Shell posix)
  Assert-Profile ((& $normalize $cursorYoloLauncher) -ceq $expectedCmd -and (& $normalize $cursorIdeLauncher) -ceq $expectedCmd -and (& $normalize $cursorPosixLauncher) -ceq $expectedPosix -and (& $normalize $cursorIdePosixLauncher) -ceq $expectedPosix) 'Cursor launchers exactly match the owner-hold shims'
  Assert-Profile ($cursor.approvalMode -eq 'allowlist' -and $cursor.sandbox.mode -eq 'enabled' -and $cursor.sandbox.networkAccess -eq 'restricted' -and $cursor.autoAcceptWebSearch -eq $false -and @($cursor.permissions.deny) -contains 'Shell(*)' -and @($cursor.permissions.deny) -contains 'Write(**)') 'Cursor native configuration is restrictive while disabled'
  $actualCursorHoldRule = (Get-Content "$UserProfile\.cursor\rules\00-provider-hold.mdc" -Raw -ErrorAction SilentlyContinue).Replace("`r`n", "`n").TrimEnd("`r", "`n")
  $expectedCursorHoldRule = (Get-CursorProviderHoldRuleContent).Replace("`r`n", "`n").TrimEnd("`r", "`n")
  Assert-Profile ($actualCursorHoldRule -ceq $expectedCursorHoldRule) 'Cursor global provider-hold rule is exact'
}
Assert-Profile ($antigravity.toolPermission -eq 'always-proceed') 'Antigravity tool approval is always-proceed'
Assert-Profile ($amp.'amp.permissions' -is [System.Array] -and $amp.'amp.permissions'.Count -eq 1 -and $amp.'amp.permissions'[0].action -eq 'allow' -and $amp.'amp.permissions'[0].tool -eq '*') 'Amp has a valid global allow-all rule'
Assert-Profile (
  $null -eq $factory.PSObject.Properties['interactionMode'] -and
  $null -eq $factory.PSObject.Properties['autonomyLevel'] -and
  $null -eq $factory.PSObject.Properties['autonomyMode'] -and
  $factory.sessionDefaultSettings.interactionMode -eq 'auto' -and
  $factory.sessionDefaultSettings.autonomyLevel -eq 'high'
) 'Factory uses the current nested session-default autonomy schema'
Assert-Profile ($copilot.stayInAutopilot -eq $true -and $copilot.askUser -eq $false) 'Copilot persists autopilot and no-question defaults'
Assert-Profile ($grokToml -match '(?m)^yolo\s*=\s*true\s*$' -and $grokToml -match '(?m)^permission_mode\s*=\s*"always-approve"\s*$') 'Grok uses its persisted yolo and always-approve modes'
 $clineMcp = Read-ServerSet "$UserProfile\.cline\data\settings\cline_mcp_settings.json" 'mcpServers'
 $qoderMcp = Read-ServerSet "$UserProfile\.qoder\settings.json" 'mcpServers'
 Assert-Profile (
   $clineMcp.PSObject.Properties['context7'].Value.type -eq 'streamableHttp' -and
   $null -eq $clineMcp.PSObject.Properties['playwright']
 ) 'Cline uses native streamableHttp and keeps Playwright on demand'
 Assert-Profile ($clineMcp.PSObject.Properties['context7'].Value.autoApprove.Count -eq 0 -and ($clineMcp | ConvertTo-Json -Depth 30 -Compress) -notmatch '"auth"\s*:') 'Cline MCP keeps per-server auto-approval empty and no auth marker'
 Assert-Profile (
   $null -eq $qoderMcp.PSObject.Properties['context7'] -and
   $null -eq $qoderMcp.PSObject.Properties['playwright'] -and
   ($qoderMcp | ConvertTo-Json -Depth 30 -Compress) -notmatch '"auth"\s*:'
 ) 'Qoder defers Context7 to its plugin, keeps Playwright on demand, and omits the unsupported auth marker'
 Assert-Profile ((Test-Path "$UserProfile\.qoder\agents\scout.md") -and ((Get-Content "$UserProfile\.qoder\agents\scout.md" -Raw) -match '(?m)^name:\s*scout\s*$')) 'Qoder native scout agent is present'
 Assert-Profile ((Get-Content "$UserProfile\bin\cline.cmd" -Raw) -match '--auto-approve true' -and (Get-Content "$UserProfile\bin\cline.cmd" -Raw) -match 'auth config plugin') 'Cline launcher applies auto-approve only outside administrative commands'
 Assert-Profile ((Get-Content "$UserProfile\bin\qodercli.cmd" -Raw) -match '--dangerously-skip-permissions' -and (Get-Content "$UserProfile\bin\qodercli.cmd" -Raw) -match 'login mcp plugins') 'Qoder launcher applies bypass permissions only outside administrative commands'
 Assert-Profile ((Get-Content "$UserProfile\bin\cline-acp.cmd" -Raw) -match '--acp' -and (Get-Content "$UserProfile\bin\qoder-acp.cmd" -Raw) -match '--acp') 'Cline and Qoder ACP launchers are present'
foreach ($name in 'DEVIN_PERMISSION_MODE','COPILOT_ALLOW_ALL','GEMINI_CLI_TRUST_WORKSPACE','QWEN_CODE_SUPPRESS_YOLO_WARNING') {
  Assert-Profile (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'User'))) "user environment contains $name"
}
$expectedAgentTempRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'AgentHub\tmp'))
$configuredAgentTempRoot = [Environment]::GetEnvironmentVariable('TMPDIR', 'User')
Assert-Profile (
  -not [string]::IsNullOrWhiteSpace($configuredAgentTempRoot) -and
  [System.IO.Path]::GetFullPath($configuredAgentTempRoot).Equals(
    $expectedAgentTempRoot,
    [StringComparison]::OrdinalIgnoreCase
  ) -and
  (Test-Path -LiteralPath $expectedAgentTempRoot -PathType Container)
) 'user TMPDIR redirects coding-agent temporary files below AgentHub runtime'
foreach ($launcher in 'gemini.cmd','qwen.cmd','copilot.cmd','devin.cmd','agy.cmd','cline.cmd','qodercli.cmd','cline-acp.cmd','qoder-acp.cmd','opencode-acp.cmd','gemini-acp.cmd','copilot-acp.cmd','hermes-acp.cmd','cursor-agent.cmd','cursor-agent','cursor.cmd','cursor') {
  Assert-Profile (Test-Path "$UserProfile\bin\$launcher") "unattended launcher exists: $launcher"
}
$qwenLauncher = Get-Content "$UserProfile\bin\qwen.cmd" -Raw -ErrorAction SilentlyContinue
Assert-Profile ($qwenLauncher -match '--yolo' -and $qwenLauncher -match '--experimental-lsp') 'Qwen launcher enables yolo and experimental LSP'
if ($failures.Count) { exit 1 }
Write-Host "Profile validation passed: $($expectedGlobal.Count) global MCPs across $($mcpPaths.Count) managed hosts." -ForegroundColor Green
