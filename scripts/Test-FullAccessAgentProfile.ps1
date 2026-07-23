#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$RegistryRoot = 'C:\Repos\agent-capabilities',
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
$fleetProfile = Get-Content (Join-Path $RegistryRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'AgentCtl.CursorReadiness.ps1')
$expected = @((Get-Content (Join-Path $RegistryRoot 'registry\mcps.json') -Raw | ConvertFrom-Json).mcpServers | Where-Object scope -eq 'global-default' | ForEach-Object id | Sort-Object)
$failures = @()
function Assert-Profile([bool]$Condition, [string]$Check) {
  if ($Condition) { Write-Host "PASS  $Check" -ForegroundColor Green }
  else { Write-Host "FAIL  $Check" -ForegroundColor Red; $script:failures += $Check }
}
function Read-ServerNames([string]$Path, [string]$Property) {
  try {
    $root = Get-Content $Path -Raw | ConvertFrom-Json -Depth 100
    $serverSet = $root.$Property
    if ($null -eq $serverSet) { return @() }
    return @($serverSet.PSObject.Properties.Name | Sort-Object)
  } catch { return @() }
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
  'qwen' = @("$UserProfile\.qwen\settings.json", 'mcp')
}
foreach ($hostId in $mcpPaths.Keys | Sort-Object) {
  $path, $prop = $mcpPaths[$hostId]
  $actual = Read-ServerNames $path $prop
  if ($hostId -eq 'qwen') { $actual = @((Get-Content $path -Raw | ConvertFrom-Json).mcp.allowed | Sort-Object) }
  Assert-Profile (($actual -join '|') -eq ($expected -join '|')) "$hostId has the canonical nine MCP registrations"
  $raw = if (Test-Path $path) { Get-Content $path -Raw } else { '' }
  Assert-Profile ($raw -match '"playwright"[\s\S]*?--isolated') "$hostId uses isolated Playwright"
  Assert-Profile ($raw -notmatch 'exaApiKey=|fc-[a-z0-9]{20,}|pendoah\.app\.n8n|mcp\.canva') "$hostId has no stale embedded-provider endpoint"
}

$claude = Get-Content "$UserProfile\.claude\settings.json" -Raw | ConvertFrom-Json
$qwen = Get-Content "$UserProfile\.qwen\settings.json" -Raw | ConvertFrom-Json
$openCode = Get-Content "$UserProfile\.config\opencode\opencode.json" -Raw | ConvertFrom-Json
$cursor = Get-Content "$UserProfile\.cursor\cli-config.json" -Raw | ConvertFrom-Json
$antigravity = Get-Content "$UserProfile\.gemini\antigravity-cli\settings.json" -Raw | ConvertFrom-Json
$amp = Get-Content "$UserProfile\.config\amp\settings.json" -Raw | ConvertFrom-Json
$factory = Get-Content "$UserProfile\.factory\settings.json" -Raw | ConvertFrom-Json
Assert-Profile ($claude.permissions.defaultMode -eq 'bypassPermissions') 'Claude Code default is bypassPermissions'
Assert-Profile ($qwen.tools.approvalMode -eq 'yolo') 'Qwen Code default is yolo'
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
Assert-Profile ($factory.interactionMode -eq 'auto' -and $factory.autonomyMode -eq 'auto-high') 'Factory uses its highest discovered autonomous profile'
foreach ($name in 'DEVIN_PERMISSION_MODE','COPILOT_ALLOW_ALL','GEMINI_CLI_TRUST_WORKSPACE','QWEN_CODE_SUPPRESS_YOLO_WARNING') {
  Assert-Profile (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'User'))) "user environment contains $name"
}
foreach ($launcher in 'gemini.cmd','copilot.cmd','devin.cmd','agy.cmd','cursor-agent.cmd','cursor-agent','cursor.cmd','cursor') {
  Assert-Profile (Test-Path "$UserProfile\bin\$launcher") "unattended launcher exists: $launcher"
}
if ($failures.Count) { exit 1 }
Write-Host "Profile validation passed: $($expected.Count) MCPs across $($mcpPaths.Count) managed hosts." -ForegroundColor Green
