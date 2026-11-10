#Requires -Version 5.1
<# Package build check for coding-agent-dispatch. Verifies the plugin packaging
   is complete and consistent: every host manifest exists, parses and agrees on
   name and version; the version matches SKILL.md metadata; both marketplace
   catalogs and the capabilities registry reference the package; and every file
   the skill and its host contracts depend on is present. Synthetic only. #>
$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $pluginRoot)
$pluginName = 'ah-coding-agent-dispatch'
$expectedSkills = @('dispatch')
$requiredFiles = @(
    'plugin.json', '.mcp.json',
    '.claude-plugin/plugin.json', '.codex-plugin/plugin.json',
    '.cursor-plugin/plugin.json', '.devin-plugin/plugin.json',
    '.antigravity-plugin/plugin.json',
    'skills/dispatch/SKILL.md', 'skills/dispatch/Invoke-CodingAgent.ps1',
    'skills/dispatch/references/hosts.md',
    'skills/dispatch/cline/acp-session.mjs', 'skills/dispatch/cline/acp-dispatch.mjs',
    'skills/dispatch/cline/peer-guard.js', 'skills/dispatch/cline/lightweight-chat.js',
    'skills/dispatch/opencode/lightweight-chat.js',
    'skills/dispatch/factory/runtime-settings.json',
    'agents/claude/coding-agent.md', 'agents/codex/coding-agent.toml',
    'assets/icon.svg'
)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

foreach ($relative in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $pluginRoot $relative)) "Missing required file: $relative"
}

# Every manifest must parse and agree on the plugin identity and version.
$manifestPaths = @(
    'plugin.json', '.claude-plugin/plugin.json', '.codex-plugin/plugin.json',
    '.cursor-plugin/plugin.json', '.devin-plugin/plugin.json', '.antigravity-plugin/plugin.json'
)
$manifests = @{}
foreach ($relative in $manifestPaths) {
    $manifests[$relative] = Read-Json (Join-Path $pluginRoot $relative)
    Assert-True ($manifests[$relative].name -eq $pluginName) "$relative has unexpected name '$($manifests[$relative].name)'."
}
$version = [string]$manifests['plugin.json'].version
Assert-True ($version -match '^\d+\.\d+\.\d+$') "Root plugin.json version must be semver, found '$version'."
foreach ($relative in $manifestPaths | Where-Object { $_ -ne 'plugin.json' }) {
    Assert-True ([string]$manifests[$relative].version -eq $version) "$relative version '$($manifests[$relative].version)' diverges from root plugin.json '$version'."
}

# SKILL.md metadata.version is the skill-side copy of the same version.
$skillText = Get-Content -LiteralPath (Join-Path $pluginRoot 'skills/dispatch/SKILL.md') -Raw -Encoding UTF8
Assert-True ($skillText -match '(?m)^name:\s*dispatch\s*$') 'SKILL.md frontmatter must name the skill dispatch.'
Assert-True ($skillText -match "(?m)^\s*version:\s*[`"']?$([regex]::Escape($version))[`"']?\s*$") "SKILL.md metadata.version must match root plugin.json ($version)."

# Both marketplace catalogs must offer the plugin at this package path.
$claudeMarket = Read-Json (Join-Path $repoRoot '.claude-plugin/marketplace.json')
$claudeEntry = @($claudeMarket.plugins | Where-Object { $_.name -eq $pluginName })
Assert-True ($claudeEntry.Count -eq 1) '.claude-plugin/marketplace.json must list ah-coding-agent-dispatch exactly once.'
Assert-True ($claudeEntry[0].source -eq './packages/coding-agent-dispatch') 'Claude marketplace source must point at ./packages/coding-agent-dispatch.'

$agentsMarket = Read-Json (Join-Path $repoRoot '.agents/plugins/marketplace.json')
$agentsEntry = @($agentsMarket.plugins | Where-Object { $_.name -eq $pluginName })
Assert-True ($agentsEntry.Count -eq 1) '.agents/plugins/marketplace.json must list ah-coding-agent-dispatch exactly once.'
Assert-True ($agentsEntry[0].source.path -eq './packages/coding-agent-dispatch') 'Agent Plugins marketplace source.path must point at ./packages/coding-agent-dispatch.'

# The registry must keep the capability wired to this package.
$capabilities = Read-Json (Join-Path $repoRoot 'registry/capabilities.json')
$capability = @($capabilities.capabilities | Where-Object { $_.id -eq 'coding-agent-dispatch' })
Assert-True ($capability.Count -eq 1) 'registry/capabilities.json must contain coding-agent-dispatch exactly once.'
Assert-True ($capability[0].canonicalSource -eq 'packages/coding-agent-dispatch') 'canonicalSource must be packages/coding-agent-dispatch.'
Assert-True ($capability[0].capabilityType -eq 'plugin+skills') "capabilityType must be plugin+skills, found '$($capability[0].capabilityType)'."
foreach ($skill in $expectedSkills) {
    Assert-True ($capability[0].managedSkillNames -contains $skill) "managedSkillNames must include $skill."
    Assert-True (Test-Path -LiteralPath (Join-Path $pluginRoot "skills/$skill/SKILL.md")) "skills/$skill/SKILL.md missing."
}

# The empty MCP file is deliberate: the dispatcher has no MCP surface, but the
# manifest still parses so generic plugin loaders do not choke on it.
$mcp = Read-Json (Join-Path $pluginRoot '.mcp.json')
Assert-True ($null -ne $mcp.mcpServers) '.mcp.json must carry a mcpServers object.'

Write-Host 'PASS: coding-agent-dispatch packaging is complete and consistent.'
