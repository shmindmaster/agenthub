#Requires -Version 5.1
[CmdletBinding()]
param([string]$RepositoryRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
$errors = [Collections.Generic.List[string]]::new()
. (Join-Path $root 'scripts\RegistryContentHash.ps1')

function Fail([string]$Message) { $script:errors.Add($Message) }
function Read-Json([string]$Path) {
  try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { Fail "invalid JSON: $Path ($($_.Exception.Message))"; $null }
}

$forbiddenRoots = @(
  'adapters','capabilities','docs','generated','profiles','reports','roles',
  'standards','state','templates','packages\plugins','packages\handoff-plugins','packages\portfolio-plugins'
)
foreach ($relative in $forbiddenRoots) {
  if (Test-Path -LiteralPath (Join-Path $root $relative)) { Fail "forbidden root exists: $relative" }
}

$marketplace = Read-Json (Join-Path $root '.agents\plugins\marketplace.json')
$capabilities = Read-Json (Join-Path $root 'registry\capabilities.json')
$mcps = Read-Json (Join-Path $root 'registry\mcps.json')
$agents = Read-Json (Join-Path $root 'registry\agents.json')
$delivery = Read-Json (Join-Path $root 'registry\product-video-delivery.json')
$pluginFormats = Read-Json (Join-Path $root 'registry\plugin-formats.json')

$pluginRoot = Join-Path $root 'packages'
$packageNames = @(Get-ChildItem -LiteralPath $pluginRoot -Directory | ForEach-Object Name | Sort-Object)
foreach ($packageName in $packageNames) {
  $packageRoot = Join-Path $pluginRoot $packageName
  $skills = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'skills') -Directory -ErrorAction SilentlyContinue)
  if ($skills.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $packageRoot '.mcp.json'))) {
    Fail "plugin has neither skills nor MCP manifest: $packageName"
  }
  foreach ($skill in $skills) {
    $skillPath = Join-Path $skill.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath)) { Fail "skill missing SKILL.md: $($skill.FullName)"; continue }
    $skillText = Get-Content -LiteralPath $skillPath -Raw
    $skillName = [regex]::Match($skillText, '(?m)^name:\s*([^\n]+)$').Groups[1].Value.Trim().Trim('"')
    $description = [regex]::Match($skillText, '(?m)^description:\s*([^\n]+)$').Groups[1].Value.Trim().Trim('"')
    if ($skillName -ne $skill.Name) { Fail "skill frontmatter name mismatch: $skillPath" }
    if (-not $description.StartsWith('Use when')) { Fail "skill description must start with 'Use when': $skillPath" }
    if ($description.Length -gt 500) { Fail "skill description exceeds 500 characters: $skillPath" }
  }
}

$catalogNames = @($marketplace.plugins | ForEach-Object name | Sort-Object)
foreach ($entry in $marketplace.plugins) {
  $expected = "./packages/$($entry.name)"
  if ($entry.source.path -ne $expected) { Fail "marketplace path mismatch for $($entry.name): $($entry.source.path)" }
  $entryRoot = Join-Path $root $entry.source.path
  if (-not (Test-Path -LiteralPath $entryRoot)) { Fail "marketplace package missing: $($entry.name)"; continue }
  foreach ($manifest in @('plugin.json', '.claude-plugin\plugin.json')) {
    $manifestPath = Join-Path $entryRoot $manifest
    if (-not (Test-Path -LiteralPath $manifestPath)) { Fail "installable package missing $manifest`: $($entry.name)"; continue }
    $metadata = Read-Json $manifestPath
    if ($metadata -and $metadata.name -ne $entry.name) { Fail "manifest name mismatch in $manifestPath" }
  }
}

$claudeMarketplace = Read-Json (Join-Path $root '.claude-plugin\marketplace.json')
if ((@($claudeMarketplace.plugins.name | Sort-Object) -join '|') -ne ($catalogNames -join '|')) {
  Fail 'Claude-compatible marketplace does not match the canonical plugin catalog'
}
foreach ($hostId in @(
  'claude','codex','cursor','factory','vscode-insiders','qwen-code','copilot',
  'antigravity','qoder','devin','grok','opencode','amp','cline','gemini',
  'hermes','warp','windsurf'
)) {
  if ($hostId -notin @($pluginFormats.hosts.id)) { Fail "plugin format registry is missing host: $hostId" }
}
if (@($pluginFormats.hosts | Where-Object id -eq 'opencode').manifest) {
  Fail 'OpenCode must not be assigned a capability-bundle manifest'
}

foreach ($packageName in @('product-demo-studio','product-experience-engineering')) {
  $agentFiles = @(Get-ChildItem -LiteralPath (Join-Path $pluginRoot "$packageName\agents") -File -ErrorAction SilentlyContinue)
  if ($agentFiles.Count -eq 0) { Fail "subagent-driven package has no agents: $packageName" }
  foreach ($agentFile in $agentFiles) {
    if ($agentFile.Name -notlike '*.agent.md') { Fail "non-portable agent filename: $($agentFile.FullName)" }
  }
}

# Registry-owned paths (canonicalSource, hashBasis) must be repository-relative
# so the same registry.json is correct in every worktree/clone. This resolves
# a relative value against $root and rejects it outright -- rather than
# silently rewriting it -- if it is absolute, UNC, or escapes the repository
# root via '..'. A capability whose path arrives absolute after this guard is
# a real regression, not something to paper over.
function Test-RegistryRelativePath {
  param(
    [string]$Value,
    [string]$Root,
    [string]$FieldName,
    [string]$CapabilityId
  )
  if ([string]::IsNullOrWhiteSpace($Value)) {
    Fail "$FieldName is missing: $CapabilityId"
    return $null
  }
  if ([IO.Path]::IsPathRooted($Value)) {
    Fail "$FieldName must be repository-relative, not absolute or UNC: $CapabilityId ($Value)"
    return $null
  }
  $resolved = [IO.Path]::GetFullPath((Join-Path $Root $Value))
  $rootPrefix = $Root.TrimEnd('\') + '\'
  if (-not ($resolved.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
      $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase))) {
    Fail "$FieldName escapes the repository root: $CapabilityId ($Value)"
    return $null
  }
  return $resolved
}

foreach ($capability in $capabilities.capabilities) {
  $expectedRoot = [IO.Path]::GetFullPath((Join-Path $pluginRoot $capability.id))
  if (-not (Test-Path -LiteralPath $expectedRoot)) { Fail "registered capability missing: $($capability.id)"; continue }
  $resolvedSource = Test-RegistryRelativePath -Value ([string]$capability.canonicalSource) -Root $root -FieldName 'canonicalSource' -CapabilityId $capability.id
  if ($resolvedSource -and $resolvedSource -ne $expectedRoot) { Fail "canonicalSource mismatch: $($capability.id)" }
  $resolvedHashBasis = Test-RegistryRelativePath -Value ([string]$capability.hashBasis) -Root $root -FieldName 'hashBasis' -CapabilityId $capability.id
  if ($resolvedHashBasis -and $resolvedHashBasis -ne $expectedRoot) { Fail "hashBasis must cover the complete package: $($capability.id)" }
  $actualHash = Get-AgentHubRegistryHashBasisValue -Path $expectedRoot
  if ($actualHash -ne $capability.contentHash) { Fail "contentHash drift: $($capability.id)" }
}

if (@($agents.activeAgents).Count -eq 0) { Fail 'agents registry has no active agents' }
if (@($mcps.mcpServers).Count -eq 0) { Fail 'MCP registry is empty' }
if (@($delivery.products).Count -ne 7) { Fail 'product video delivery registry must contain seven products' }

# Autonomy/permission model (registry/fleet-profile.json.autonomyProfiles): a host
# marked 'interactive' must never be dispatched unattended, so this data must not
# be able to silently rot -- every hostId must be real, every defaultProfile must
# be a known value (an unrecognized value defaulting to permissive is exactly the
# failure mode this guards against), and every active host must be covered or
# explicitly exempted with a reason.
$fleetProfile = Read-Json (Join-Path $root 'registry\fleet-profile.json')
$registeredHostIds = @(@($agents.activeAgents | ForEach-Object id) + @($agents.inactiveAgents | ForEach-Object id))
$knownDefaultProfiles = @($fleetProfile.autonomyProfiles.knownDefaultProfiles)
if ($knownDefaultProfiles.Count -eq 0) { Fail 'autonomyProfiles.knownDefaultProfiles is missing or empty' }
$autonomyProfiles = @($fleetProfile.autonomyProfiles.profiles)
if ($autonomyProfiles.Count -eq 0) { Fail 'autonomyProfiles.profiles is missing or empty' }
$coveredHostIds = [Collections.Generic.HashSet[string]]::new()
foreach ($autonomyProfile in $autonomyProfiles) {
  $hostId = [string]$autonomyProfile.hostId
  if ($hostId -notin $registeredHostIds) { Fail "autonomy profile hostId does not resolve to a registered host: $hostId" }
  if (([string]$autonomyProfile.defaultProfile) -notin $knownDefaultProfiles) {
    Fail "autonomy profile defaultProfile is not a known value: $hostId ($($autonomyProfile.defaultProfile))"
  }
  [void]$coveredHostIds.Add($hostId)
}
$exemptHostIds = @(@($fleetProfile.autonomyProfiles.exemptions) | ForEach-Object hostId)
foreach ($activeAgent in @($agents.activeAgents)) {
  $activeHostId = [string]$activeAgent.id
  if ($coveredHostIds.Contains($activeHostId)) { continue }
  if ($activeHostId -in $exemptHostIds) { continue }
  Fail "active host has no autonomy profile and no exemption: $activeHostId"
}

$stale = @(rg -l --hidden --glob '!node_modules/**' --glob '!tests/validate.ps1' `
  'packages/(handoff-plugins/plugins|portfolio-plugins)|agenthub[/\\]capabilities[/\\]|agenthub[/\\](docs|reports|state|generated)[/\\]' `
  $root 2>$null)
if ($stale.Count -gt 0) { Fail "stale legacy paths remain: $($stale -join ', ')" }

if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
  exit 1
}

Write-Output "PASS: $($packageNames.Count) capability packages, $($catalogNames.Count) installable plugins, $(@($mcps.mcpServers).Count) MCP servers, $(@($agents.activeAgents).Count) active agents."
# Terminate explicitly. The stale-path scan above is the last native command, and
# `rg` exits 1 when it finds nothing -- the passing case. Without this, a clean
# validation inherits that 1 and every caller reads PASS as a failure.
exit 0
