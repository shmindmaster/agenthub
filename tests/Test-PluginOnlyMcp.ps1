#Requires -Version 5.1
<#
Behavior test for the plugin-only MCP rule (owner direction 2026-11-04).

Why: the sync used to write every registry server to every host unless that
server was marked plugin-owned, so direct entries came back after each removal.
activationPolicy.pluginOnly in registry/mcps.json flips the default: a listed
host gets no direct entry unless the policy names it with a reason.

Checks that the rule holds in three places:
- the registry: every plugin-only host is real and every exception has a reason;
- the sync: Get-HostMcpEntries, run on a fixture, drops what the policy does not allow;
- the machine: each host's real config holds nothing beyond its allowed entries.
  A missing config file is skipped, so this passes on a machine without the host.

The detector runs on a fixture first, so a clean machine cannot hide a broken check.

Run: pwsh -NoProfile -File tests/Test-PluginOnlyMcp.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry/mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry/agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agentIds = @($agents.activeAgents.id) + @($agents.inactiveAgents.id)
$policy = $registry.activationPolicy.pluginOnly

# --- registry -----------------------------------------------------------------
Assert-True ($null -ne $policy) 'activationPolicy.pluginOnly is missing'
foreach ($hostEntry in $policy.hosts.PSObject.Properties) {
    Assert-True ($hostEntry.Name -in $agentIds) "pluginOnly names unknown host '$($hostEntry.Name)'"
    foreach ($allowed in $hostEntry.Value.PSObject.Properties) {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$allowed.Value)) "$($hostEntry.Name)/$($allowed.Name) has no reason"
    }
}
foreach ($named in 'claude', 'codex', 'cursor', 'grok', 'factory', 'antigravity', 'qoder', 'copilot', 'vscode-insiders', 'cline', 'opencode', 'amp', 'devin', 'warp') {
    Assert-True ($null -ne $policy.hosts.PSObject.Properties[$named]) "coding host '$named' is not plugin-only"
}

# --- sync: run the real function on a fixture ---------------------------------
$syncPath = Join-Path $repoRoot 'scripts/Sync-AgentHub.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($syncPath, [ref]$tokens, [ref]$errors)
$functionAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-HostMcpEntries' }, $true)
Assert-True ($null -ne $functionAst) 'Get-HostMcpEntries not found in Sync-AgentHub.ps1'
if ($functionAst) {
    function Resolve-McpAliasKey([string]$Key) { return $Key }
    function ConvertTo-Hashtable($Value) { return $Value }
    Invoke-Expression $functionAst.Extent.Text
    $base = @{ alpha = @{ url = 'https://a.example' }; beta = @{ url = 'https://b.example' } }
    $common = @{ HostId = 'fixture'; BaseEntries = $base; HostAllowlist = @{}; HostConfigOverrides = @{}; PluginProvidedByHost = @{}; GatewayPlan = $null }
    $open = Get-HostMcpEntries @common
    Assert-True ($open.Count -eq 2) 'a host outside the policy should keep every entry'
    $none = Get-HostMcpEntries @common -PluginOnlyAllowed ([string[]]@())
    Assert-True ($none.Count -eq 0) 'a plugin-only host with no exceptions should get no direct entry'
    $one = Get-HostMcpEntries @common -PluginOnlyAllowed ([string[]]@('beta'))
    Assert-True ($one.Count -eq 1 -and $one.ContainsKey('beta')) 'a plugin-only host should get only its allowed entry'
}

# A disabled entry is a host's off switch for a plugin server, so the sync must leave it in place.
foreach ($name in 'Test-McpEntryDisabled', 'Remove-McpTargetKeys') {
    $helperAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    Assert-True ($null -ne $helperAst) "$name not found in Sync-AgentHub.ps1"
    if ($helperAst) { Invoke-Expression $helperAst.Extent.Text }
}
if (Get-Command Remove-McpTargetKeys -ErrorAction SilentlyContinue) {
    function Get-McpAliasesForCanonicalKey([string]$Key) { return @() }
    $switches = @{ live = @{ url = 'https://a.example' }; off = @{ disabled = $true } }
    $kept = Remove-McpTargetKeys -Target $switches -Keys @('live', 'off')
    Assert-True ((@($kept.Keys) -join ',') -eq 'off') 'the sync removed a disabled entry, which starts that plugin server again'
}

# --- machine ------------------------------------------------------------------
function Get-JsonKeys([string]$Path, [string]$Property) {
    $data = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $node = $data.PSObject.Properties[$Property]
    if (-not $node -or $null -eq $node.Value) { return @() }
    # A disabled entry is how Devin and Antigravity switch a plugin's server off. It runs nothing.
    return @($node.Value.PSObject.Properties | Where-Object { $_.Value.disabled -ne $true -and $_.Value.enabled -ne $false } | ForEach-Object Name)
}

function Get-TomlKeys([string]$Path) {
    return @(Select-String -LiteralPath $Path -Pattern '^\[mcp_servers\.([^.\]]+)\]\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
}

function Get-Disallowed([string[]]$Actual, [string[]]$Allowed) {
    return @($Actual | Where-Object { $_ -and $_ -notin $Allowed })
}

$found = @(Get-Disallowed -Actual @('node_repl', 'context7') -Allowed @('node_repl'))
Assert-True ($found.Count -eq 1 -and $found[0] -eq 'context7') 'the detector missed a stray entry on its fixture'
$jsonFixture = Join-Path ([IO.Path]::GetTempPath()) "plugin-only-$PID.json"
try {
    Set-Content -LiteralPath $jsonFixture -Value '{"mcpServers":{"off":{"disabled":true},"also-off":{"enabled":false},"on":{"url":"x"}}}'
    Assert-True ((@(Get-JsonKeys $jsonFixture 'mcpServers') -join ',') -eq 'on') 'the JSON reader should skip a disabled server and keep a live one'
} finally {
    Remove-Item -LiteralPath $jsonFixture -Force -ErrorAction SilentlyContinue
}
$tomlFixture = Join-Path ([IO.Path]::GetTempPath()) "plugin-only-$PID.toml"
try {
    Set-Content -LiteralPath $tomlFixture -Value "[mcp_servers.stray]`nurl = 'x'`n[mcp_servers.stray.env]`nA = 'b'`n"
    Assert-True ((@(Get-TomlKeys $tomlFixture) -join ',') -eq 'stray') 'the TOML reader missed a server on its fixture'
} finally {
    Remove-Item -LiteralPath $tomlFixture -Force -ErrorAction SilentlyContinue
}

$userHome = [Environment]::GetFolderPath('UserProfile')
$roaming = [Environment]::GetFolderPath('ApplicationData', 'DoNotVerify')
$targets = @(
    @{ HostId = 'claude'; Path = (Join-Path $userHome '.claude.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'codex'; Path = (Join-Path $userHome '.codex/config.toml'); Reader = { param($p) Get-TomlKeys $p } }
    @{ HostId = 'grok'; Path = (Join-Path $userHome '.grok/config.toml'); Reader = { param($p) Get-TomlKeys $p } }
    @{ HostId = 'cursor'; Path = (Join-Path $userHome '.cursor/mcp.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'factory'; Path = (Join-Path $userHome '.factory/mcp.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'antigravity'; Path = (Join-Path $userHome '.gemini/config/mcp_config.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'antigravity'; Path = (Join-Path $userHome '.gemini/antigravity/mcp_config.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'copilot'; Path = (Join-Path $userHome '.copilot/mcp-config.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'qoder'; Path = (Join-Path $userHome '.qoder/settings.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'cline'; Path = (Join-Path $userHome '.cline/data/settings/cline_mcp_settings.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'opencode'; Path = (Join-Path $userHome '.config/opencode/opencode.json'); Reader = { param($p) Get-JsonKeys $p 'mcp' } }
    @{ HostId = 'vscode-insiders'; Path = (Join-Path $roaming 'Code - Insiders/User/mcp.json'); Reader = { param($p) Get-JsonKeys $p 'servers' } }
    @{ HostId = 'amp'; Path = (Join-Path $userHome '.config/amp/settings.json'); Reader = { param($p) Get-JsonKeys $p 'amp.mcpServers' } }
    @{ HostId = 'devin'; Path = (Join-Path $roaming 'devin/mcp_config.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
    @{ HostId = 'warp'; Path = (Join-Path $userHome '.warp/.mcp.json'); Reader = { param($p) Get-JsonKeys $p 'mcpServers' } }
)

$checked = 0
foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target.Path)) { continue }
    $checked++
    $allowed = @($policy.hosts.PSObject.Properties[$target.HostId].Value.PSObject.Properties.Name)
    $actual = @(& $target.Reader $target.Path)
    $stray = @(Get-Disallowed -Actual $actual -Allowed $allowed)
    Assert-True ($stray.Count -eq 0) "$($target.HostId): direct MCP entries outside the policy in $($target.Path): $($stray -join ', ')"
}

# Hook files outside a plugin run on every tool call and nothing in a plugin list shows them.
foreach ($strayHook in (Join-Path $userHome '.cursor/hooks.json'), (Join-Path $userHome '.grok/hooks/repowise.json')) {
    Assert-True (-not (Test-Path -LiteralPath $strayHook)) "a hook file outside any plugin is back: $strayHook"
}

$sharedSkills = Join-Path $userHome '.agents/skills'
if (Test-Path -LiteralPath $sharedSkills) {
    $loose = @(Get-ChildItem -LiteralPath $sharedSkills -Force)
    Assert-True ($loose.Count -eq 0) "~/.agents/skills must stay empty, found: $($loose.Name -join ', ')"
}

Write-Host "Test-PluginOnlyMcp: passed=$passed failed=$($failures.Count) configsChecked=$checked"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "  FAIL: $_" }
    exit 1
}
exit 0
