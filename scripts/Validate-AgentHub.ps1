#Requires -Version 5.1
[CmdletBinding()]
param([string]$RepositoryRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$errors = [Collections.Generic.List[string]]::new()
. (Join-Path $root 'scripts\RegistryContentHash.ps1')
. (Join-Path $root 'scripts\lib\CapabilityGraph.ps1')

function Fail([string]$Message) { $script:errors.Add($Message) }
function Read-Json([string]$Path) {
  try { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { Fail "invalid JSON: $Path ($($_.Exception.Message))"; $null }
}

# 'docs' was removed from this list on 2026-08-08: the fleet repository
# standard (registry/repo-standard.json) requires a curated docs/ taxonomy in
# every repo including this one. The ban historically targeted ungoverned
# report/state dumps; those stay forbidden via the remaining roots below.
$forbiddenRoots = @(
  'adapters','capabilities','generated','profiles','reports','roles',
  'standards','state','templates','packages\plugins','packages\handoff-plugins','packages\portfolio-plugins'
)
foreach ($relative in $forbiddenRoots) {
  if (Test-Path -LiteralPath (Join-Path $root $relative)) { Fail "forbidden root exists: $relative" }
}

$marketplace = Read-Json (Join-Path $root '.agents\plugins\marketplace.json')
$capabilities = Read-Json (Join-Path $root 'registry\capabilities.json')
$mcps = Read-Json (Join-Path $root 'registry\mcps.json')
$agents = Read-Json (Join-Path $root 'registry\agents.json')
$distribution = [string]$capabilities.distribution
$isPublicCore = $distribution -eq 'public-core'
if ($distribution -and -not $isPublicCore) { Fail "unknown capabilities distribution: $distribution" }
$deliveryPath = Join-Path $root 'registry\product-video-delivery.json'
$delivery = $null
if ($isPublicCore) {
  # The exporter removes fleet-private inputs; a public marker must not turn
  # validation into a bypass for a canonical checkout that still contains them.
  foreach ($relative in @('global-agent-policy.md', 'registry\product-video-delivery.json', 'registry\repo-standard.json', 'registry\mobile-scope.json')) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) { Fail "public-core distribution contains private fleet input: $relative" }
  }
  if (@($capabilities.capabilities | Where-Object { $_.visibility -eq 'private' }).Count -gt 0) {
    Fail 'public-core distribution contains private capabilities'
  }
} else {
  # Absence is not an opt-out. Canonical fleet validation still requires this
  # registry and its eighteen-product baseline below (2026-10-21).
  $delivery = Read-Json $deliveryPath
}
$pluginFormats = Read-Json (Join-Path $root 'registry\plugin-formats.json')

$pluginRoot = Join-Path $root 'packages'
$overlayRoot = Get-AgentHubOverlayRoot -RepositoryRoot $root -ReportPrimaryCheckout
$packageNames = @(Get-ChildItem -LiteralPath $pluginRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object Name | Sort-Object)
# Public-first: private package trees must not remain under packages/.
foreach ($packageName in $packageNames) {
  $capHit = @($capabilities.capabilities | Where-Object { [string]$_.id -eq $packageName -and (Test-AgentHubCapabilityPrivate $_) })
  if ($capHit.Count -gt 0) {
    Fail "private capability '$packageName' is still tracked under packages/. Move it to overlays/personal/packages/$packageName."
  }
}
$overlayPackagesRoot = if ($overlayRoot) { Join-Path $overlayRoot 'packages' } else { $null }
if ($overlayPackagesRoot -and (Test-Path -LiteralPath $overlayPackagesRoot)) {
  foreach ($overlayPkg in @(Get-ChildItem -LiteralPath $overlayPackagesRoot -Directory -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $pluginRoot $overlayPkg.Name)) {
      Fail "private package '$($overlayPkg.Name)' exists under both packages/ and overlays/personal/packages/. Keep only the overlay copy."
    }
  }
}
function Test-AgentHubSkillPackageTree([string]$PackageRoot, [string]$PackageName) {
  $skills = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'skills') -Directory -ErrorAction SilentlyContinue)
  $isDistributedPlugin = Test-Path -LiteralPath (Join-Path $PackageRoot '.claude-plugin\plugin.json')
  if ($skills.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $PackageRoot '.mcp.json'))) {
    if ($isDistributedPlugin) {
      Fail "plugin has neither skills nor MCP manifest: $PackageName"
    }
    return
  }
  foreach ($skill in $skills) {
    $skillPath = Join-Path $skill.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath)) { Fail "skill missing SKILL.md: $($skill.FullName)"; continue }
    $skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
    $skillName = [regex]::Match($skillText, '(?m)^name:\s*([^\r\n]+)\r?$').Groups[1].Value.Trim().Trim('"')
    $description = [regex]::Match($skillText, '(?m)^description:\s*([^\r\n]+)\r?$').Groups[1].Value.Trim().Trim('"')
    if ($skillName -ne $skill.Name) { Fail "skill frontmatter name mismatch: $skillPath" }
    if (-not $description.StartsWith('Use when')) { Fail "skill description must start with 'Use when': $skillPath" }
    if ($description.Length -gt 500) { Fail "skill description exceeds 500 characters: $skillPath" }
  }
}
foreach ($packageName in $packageNames) {
  Test-AgentHubSkillPackageTree -PackageRoot (Join-Path $pluginRoot $packageName) -PackageName $packageName
}
if ($overlayRoot -and (Test-Path -LiteralPath $overlayPackagesRoot)) {
  foreach ($overlayPkg in @(Get-ChildItem -LiteralPath $overlayPackagesRoot -Directory -ErrorAction SilentlyContinue)) {
    Test-AgentHubSkillPackageTree -PackageRoot $overlayPkg.FullName -PackageName $overlayPkg.Name
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

    # Component-field TYPES, not just presence. Claude Code validates plugin.json
    # against a schema and refuses to load the whole plugin on a type mismatch --
    # with no signal here, because a wrong type is still valid JSON and still has
    # the right name.
    #
    # product-experience-engineering shipped `"agents": "./agents/"` (a directory
    # string) and was rejected with `agents: Invalid input`, so all four of its
    # subagents were unavailable, while this validator reported PASS and counted
    # it among the installable plugins. Found only by running `claude plugin
    # list` by hand. Parity that is never checked against what the host will
    # actually accept is not parity.
    #
    # Per the plugin reference: directory-valued fields take a path string,
    # file-list fields take an ARRAY of individual file paths.
    if ($metadata) {
      $directoryFields = @('skills', 'hooks', 'mcpServers', 'outputStyles', 'lspServers')
      $fileListFields  = @('agents', 'commands')
      foreach ($field in $directoryFields) {
        if (-not $metadata.PSObject.Properties[$field]) { continue }
        if ($metadata.$field -isnot [string]) {
          Fail "$manifestPath field '$field' must be a path string, found $($metadata.$field.GetType().Name). Claude Code rejects the entire plugin on a schema mismatch."
        }
      }
      foreach ($field in $fileListFields) {
        if (-not $metadata.PSObject.Properties[$field]) { continue }
        if ($metadata.$field -is [string]) {
          Fail "$manifestPath field '$field' is a string ('$($metadata.$field)'), but the plugin schema requires an array of individual file paths (e.g. [`"./agents/reviewer.agent.md`"]). Claude Code rejects the entire plugin with '$field`: Invalid input', so every component it ships becomes unavailable."
          continue
        }
        foreach ($item in @($metadata.$field)) {
          $itemPath = Join-Path $entryRoot ([string]$item)
          if (-not (Test-Path -LiteralPath $itemPath)) {
            Fail "$manifestPath field '$field' references a file that does not exist: $item"
          }
        }
      }
    }
  }
}

# A package that carries a plugin manifest but is absent from the catalog is
# built, registered, hashed -- and installed by nobody. mobile-device-lab
# shipped that way on 2026-08-10 and was found only on 2026-08-11, when an
# agent needed the Appium MCP, did not have it, and drove the emulator with raw
# adb instead. Every other check passed the whole time, and the PASS line even
# counted "7 installable plugins" without noticing the eighth manifest.
#
# This is the packaging twin of the reachability gates in Rexa: correctness and
# distribution are separate properties, and only one of them was being checked.
foreach ($packageName in $packageNames) {
  $claudeManifest = Join-Path $pluginRoot "$packageName\.claude-plugin\plugin.json"
  if (-not (Test-Path -LiteralPath $claudeManifest)) { continue }
  if ($packageName -notin $catalogNames) {
    Fail "package '$packageName' has .claude-plugin/plugin.json but is absent from the plugin catalog, so no host can install it. Add it to .agents/plugins/marketplace.json and .claude-plugin/marketplace.json, or delete the manifest if it is deliberately not distributed."
  }
}

$claudeMarketplace = Read-Json (Join-Path $root '.claude-plugin\marketplace.json')
if ((@($claudeMarketplace.plugins.name | Sort-Object) -join '|') -ne ($catalogNames -join '|')) {
  Fail 'Claude-compatible marketplace does not match the canonical plugin catalog'
}
foreach ($hostId in @(
  'claude','codex','cursor','factory','vscode-insiders','copilot',
  'antigravity','qoder','devin','grok','opencode','amp','cline','gemini',
  'warp','windsurf'
)) {
  if ($hostId -notin @($pluginFormats.hosts.id)) { Fail "plugin format registry is missing host: $hostId" }
}
if (@($pluginFormats.hosts | Where-Object id -eq 'opencode').manifest) {
  Fail 'OpenCode must not be assigned a capability-bundle manifest'
}

foreach ($packageName in @('product-experience-engineering')) {
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
    [string]$CapabilityId,
    [string]$OverlayRoot
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
  $sep = [IO.Path]::DirectorySeparatorChar
  $rootPrefix = $Root.TrimEnd('\', '/') + $sep
  if (-not ($resolved.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
      $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase))) {
    Fail "$FieldName escapes the repository root: $CapabilityId ($Value)"
    return $null
  }
  $normalizedValue = $Value.Replace('\', '/')
  if ($OverlayRoot -and $normalizedValue.StartsWith('overlays/personal/', [StringComparison]::OrdinalIgnoreCase)) {
    $overlayRelative = $normalizedValue.Substring('overlays/personal/'.Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $resolved = [IO.Path]::GetFullPath((Join-Path $OverlayRoot $overlayRelative))
    $overlayFull = [IO.Path]::GetFullPath($OverlayRoot).TrimEnd('\', '/')
    $overlayPrefix = $overlayFull + $sep
    if (-not $resolved.StartsWith($overlayPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      Fail "$FieldName escapes the personal overlay: $CapabilityId ($Value)"
      return $null
    }
  }
  return $resolved
}

# Core registry must not carry private rows — those live in the personal overlay.
foreach ($capability in @($capabilities.capabilities)) {
  if (Test-AgentHubCapabilityPrivate $capability) {
    Fail "core registry still lists private capability '$($capability.id)'. Move the row to overlays/personal/capabilities.json."
  }
}
$effectiveCapabilities = @(Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $overlayRoot)
foreach ($capability in $effectiveCapabilities) {
  try {
    $expectedRoot = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $capability -OverlayRoot $overlayRoot
  } catch {
    Fail $_.Exception.Message
    continue
  }
  if (-not (Test-Path -LiteralPath $expectedRoot)) { Fail "registered capability missing: $($capability.id) ($expectedRoot)"; continue }
  $resolvedSource = Test-RegistryRelativePath -Value ([string]$capability.canonicalSource) -Root $root -FieldName 'canonicalSource' -CapabilityId $capability.id -OverlayRoot $overlayRoot
  if ($resolvedSource -and $resolvedSource -ne $expectedRoot) { Fail "canonicalSource mismatch: $($capability.id)" }
  $resolvedHashBasis = Test-RegistryRelativePath -Value ([string]$capability.hashBasis) -Root $root -FieldName 'hashBasis' -CapabilityId $capability.id -OverlayRoot $overlayRoot
  if ($resolvedHashBasis -and $resolvedHashBasis -ne $expectedRoot) { Fail "hashBasis must cover the complete package: $($capability.id)" }
  $actualHash = Get-AgentHubRegistryHashBasisValue -Path $expectedRoot
  if ($actualHash -ne $capability.contentHash) { Fail "contentHash drift: $($capability.id)" }
}

if (@($agents.activeAgents).Count -eq 0) { Fail 'agents registry has no active agents' }
if (@($mcps.mcpServers).Count -eq 0) { Fail 'MCP registry is empty' }

$retiredMcpIds = @($mcps.retiredMcpIds | Where-Object { $_ })
$retiredMcpPackages = @($mcps.retiredMcpPackages | Where-Object { $_ })
foreach ($alias in @($mcps.migrationAliases.PSObject.Properties)) {
  if ($alias.Name -in $retiredMcpIds -or $alias.Value -in $retiredMcpIds) { Fail "retired MCP alias: $($alias.Name)" }
}
foreach ($server in @($mcps.mcpServers)) {
  if ($server.id -in $retiredMcpIds) { Fail "retired MCP registered: $($server.id)" }
  foreach ($package in $retiredMcpPackages) {
    if ((@($server.command) + @($server.args) -join ' ') -match ('(?i)(?<![\w-])' + [regex]::Escape($package) + '(?![\w-])')) { Fail "retired MCP package registered: $package" }
  }
}
function Test-RetiredMcpDocument($document, [string]$source) {
  foreach ($entry in @($document.mcpServers.PSObject.Properties)) {
    if ($entry.Name -in $retiredMcpIds) { Fail "retired MCP in plugin: $source" }
    foreach ($package in $retiredMcpPackages) {
      if (($entry.Value | ConvertTo-Json -Depth 20 -Compress) -match ('(?i)(?<![\w-])' + [regex]::Escape($package) + '(?![\w-])')) { Fail "retired MCP package in plugin: $source" }
    }
  }
}
$mcpPackageRoots = @($pluginRoot)
if ($overlayRoot -and (Test-Path -LiteralPath $overlayPackagesRoot)) { $mcpPackageRoots += $overlayPackagesRoot }
foreach ($packageTree in $mcpPackageRoots) {
  foreach ($packageRoot in @(Get-ChildItem -LiteralPath $packageTree -Directory)) {
    $mcpPaths = @((Join-Path $packageRoot.FullName '.mcp.json'))
    foreach ($relative in @('plugin.json','.claude-plugin\plugin.json','.codex-plugin\plugin.json','.cursor-plugin\plugin.json')) {
      $manifestPath = Join-Path $packageRoot.FullName $relative
      if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
      $manifest = Read-Json $manifestPath
      if ($manifest.mcpServers -is [string]) {
        $mcpPaths += Join-Path $packageRoot.FullName $manifest.mcpServers
      } elseif ($manifest.mcpServers) {
        Test-RetiredMcpDocument $manifest $manifestPath
      }
    }
    foreach ($path in @($mcpPaths | Sort-Object -Unique)) {
      if (Test-Path -LiteralPath $path -PathType Leaf) { Test-RetiredMcpDocument (Read-Json $path) $path }
    }
  }
}

# MCP protocol revision and activation policy (registry/mcps.json).
#
# The 2026-07-28 revision made the core protocol stateless -- sessions and the
# initialize handshake are gone -- so `transport: "http"` no longer says whether
# two endpoints are wire-compatible. A 2025-11-25 server and a 2026-07-28 server
# are both "http". Without a recorded revision the registry cannot notice that a
# server migrated, nor that one is stuck on a deprecated mechanism.
#
# `revision: null` is a legitimate state: three endpoints refuse protocol
# negotiation before an interactive OAuth grant. What must never be legitimate is
# a null with no explanation, because that is indistinguishable from an entry
# nobody checked.
$knownRevisions = @($mcps.knownProtocolRevisions)
if ($knownRevisions.Count -eq 0) { Fail 'mcps.json declares no knownProtocolRevisions to validate against' }
$preferenceOrder = @($mcps.activationPolicy.preferenceOrder)
if ($preferenceOrder.Count -eq 0) { Fail 'mcps.json declares no activationPolicy.preferenceOrder' }
$verifiedRevisionCount = 0
foreach ($mcpServer in @($mcps.mcpServers)) {
  $serverId = [string]$mcpServer.id
  $protocol = $mcpServer.protocol
  if (-not $protocol) { Fail "MCP server '$serverId' declares no protocol block"; continue }

  # A verification claim with no date rots invisibly; that is the whole failure
  # mode this block guards against.
  $verifiedOn = [string]$protocol.verifiedOn
  if ($verifiedOn -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Fail "MCP server '$serverId' has no dated protocol.verifiedOn (found '$verifiedOn')"
  }
  if ([string]::IsNullOrWhiteSpace([string]$protocol.verification)) {
    Fail "MCP server '$serverId' records no protocol.verification evidence"
  }

  $revision = [string]$protocol.revision
  if ([string]::IsNullOrWhiteSpace($revision)) {
    # Null is allowed only as a recorded finding, never as an unfilled field.
    if ([string]$protocol.verification -notmatch 'cannot be established|401') {
      Fail "MCP server '$serverId' has a null protocol.revision whose verification does not explain why it could not be established"
    }
  } elseif ($revision -notin $knownRevisions) {
    Fail "MCP server '$serverId' declares protocol.revision '$revision', which is not in knownProtocolRevisions"
  } else {
    $verifiedRevisionCount++
  }

  if (([string]$mcpServer.activationMode) -notin $preferenceOrder) {
    Fail "MCP server '$serverId' has activationMode '$($mcpServer.activationMode)', which is not a value declared in activationPolicy.preferenceOrder"
  }

  # A local server is the thing that multiplies into one process per host, so it
  # has to state how it is instanced. Remote servers spawn nothing and are exempt.
  if (([string]$mcpServer.transport) -eq 'stdio') {
    if ([string]::IsNullOrWhiteSpace([string]$mcpServer.localProcessPolicy.instancing)) {
      Fail "local (stdio) MCP server '$serverId' declares no localProcessPolicy.instancing"
    }
  }
}
# Anti-vacuous guard: if every entry were an unverifiable null, each one would
# pass its own check and the registry would claim a protocol contract it never
# established. At least one revision has to be a real, probed value.
if ($verifiedRevisionCount -eq 0) {
  Fail 'no MCP server has a verified protocol.revision; the registry records a protocol contract that was never established against any server'
}
if (-not $isPublicCore) {
  # Delivery roots (2026-10-21): every registered product is unique, delivers under F:/My Drive/Videos, and never into a
  # personal or restricted folder, its own subfolders included. The floor is the 2026-10-21 baseline of eighteen
  # products; dropping a mapping is a deliberate edit to this baseline, never a silent shrink.
  $deliveryBaseline = 18
  $deliveryProducts = @(@($delivery.products) | Where-Object { $null -ne $_ })
  if ($deliveryProducts.Count -lt $deliveryBaseline) { Fail "product video delivery registry must contain at least $deliveryBaseline products (lists $($deliveryProducts.Count)); it covered $deliveryBaseline on 2026-10-21 and must not shrink silently" }
  $deliveryIds = @($deliveryProducts | ForEach-Object { [string]$_.productId })
  $dupIds = @($deliveryIds | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
  if ($dupIds.Count) { Fail "product video delivery registry repeats productId: $($dupIds -join ', ')" }
  $excludedFolders = @($delivery.excludedFolders.folders)
  foreach ($product in $deliveryProducts) {
    $reviewRoot = [string]$product.reviewRoot
    if (-not $reviewRoot.StartsWith('F:/My Drive/Videos/')) { Fail "product $($product.productId) reviewRoot '$reviewRoot' is not under F:/My Drive/Videos/"; continue }
    # Normalise separators and trailing slashes, then compare the first path segment: 'Gartner', 'Gartner/' and
    # 'Gartner/Client' all deliver inside the restricted Gartner tree.
    $folder = ($reviewRoot.Substring('F:/My Drive/Videos/'.Length) -replace '\\', '/').Trim('/')
    $topFolder = ($folder -split '/')[0]
    $excludedHit = @($excludedFolders | Where-Object { [string]::Equals(([string]$_).Trim('/'), $topFolder, [StringComparison]::OrdinalIgnoreCase) })
    if ([string]::IsNullOrWhiteSpace($folder)) { Fail "product $($product.productId) reviewRoot '$reviewRoot' names the Videos root itself, not a product folder" }
    elseif ($excludedHit.Count) { Fail "product $($product.productId) delivers into excluded folder '$($excludedHit[0])' ($reviewRoot)" }
  }
}

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

# registry/subagent-formats.json is the authority for where AgentHub's own
# capability-bundled subagents are written. It is deliberately NOT compared
# against agents.json's nativePaths.agentsDir: those are two different
# documented mechanisms. agentsDir records a host's native user-level agent
# directory (gemini: ~/.gemini/agents; antigravity: ~/.gemini/config/agents),
# while this registry records extension/plugin-bundled agents. An earlier
# version of this rule required them to agree, which forced two correct,
# separately-documented values to be rewritten into one wrong one. What is
# worth enforcing is that every host receiving subagents is real and has a
# destination at all.
$subagentFormatsFile = Join-Path $root 'registry\subagent-formats.json'
if (-not (Test-Path -LiteralPath $subagentFormatsFile)) {
  Fail "missing registry file: $subagentFormatsFile"
} else {
  $subagentFormats = Get-Content -LiteralPath $subagentFormatsFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $subagentHosts = @($subagentFormats.hosts)
  if ($subagentHosts.Count -eq 0) { Fail 'subagent-formats.json declares zero hosts' }
  foreach ($subagentHost in $subagentHosts) {
    $subagentHostId = [string]$subagentHost.id
    if ($subagentHostId -notin $registeredHostIds) {
      Fail "subagent-formats.json targets a host that is not registered: $subagentHostId"
      continue
    }
    if ([string]::IsNullOrWhiteSpace([string]$subagentHost.destinationTemplate)) {
      Fail "subagent-formats.json host '$subagentHostId' declares no destinationTemplate"
    }
  }
}

$stale = @(rg -l --hidden --glob '!node_modules/**' --glob '!tests/validate.ps1' `
  'packages/(handoff-plugins/plugins|portfolio-plugins)|agenthub[/\\]capabilities[/\\]|agenthub[/\\](reports|state|generated)[/\\]' `
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
