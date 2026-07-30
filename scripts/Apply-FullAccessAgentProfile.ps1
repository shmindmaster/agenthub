#Requires -Version 5.1
<#
.SYNOPSIS
  Applies the user-authorized full-access profile to installed coding hosts.

.DESCRIPTION
  C:\Repos\shmindmaster\agenthub remains the source of truth for MCP definitions
  and reusable skills. This script writes no credential values: MCP processes
  receive environment-variable references only. It deliberately does not
  attempt to bypass OAuth or provider-owned sign-in pages.
#>
[CmdletBinding()]
param(
  [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$SkillDistributionOnly,
  [switch]$RetireLegacyVideoOwners
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PathSafety.ps1')
. (Join-Path $PSScriptRoot 'ManagedQuarantine.ps1')
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
$RegistryRoot = [System.IO.Path]::GetFullPath($RegistryRoot).TrimEnd('\')
$canonicalRepositoryRoot = [System.IO.Path]::GetFullPath(
  'C:\Repos\shmindmaster\agenthub'
).TrimEnd('\')
$UserProfile = Assert-AgentHubSafeWritePath -Path $UserProfile -Purpose 'the agent profile user directory'
if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
  throw 'APPDATA is required before the agent profile can create host configuration files.'
}
$appDataRoot = Assert-AgentHubSafeWritePath -Path $env:APPDATA -Purpose 'the agent profile AppData directory'
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  throw 'LOCALAPPDATA is required before the agent profile can create host runtime adapters.'
}
$localAppDataRoot = Assert-AgentHubSafeWritePath -Path $env:LOCALAPPDATA -Purpose 'the AgentHub user runtime directory'
$mcps = Get-Content (Join-Path $RegistryRoot 'registry\mcps.json') -Raw | ConvertFrom-Json
$caps = Get-Content (Join-Path $RegistryRoot 'registry\capabilities.json') -Raw | ConvertFrom-Json
$profile = Get-Content (Join-Path $RegistryRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'AgentCtl.CursorReadiness.ps1')

function Resolve-RegistryOwnedPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if ($fullPath.Equals($canonicalRepositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
    return $RegistryRoot
  }
  $canonicalPrefix = $canonicalRepositoryRoot + '\'
  if ($fullPath.StartsWith($canonicalPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    return Join-Path $RegistryRoot $fullPath.Substring($canonicalPrefix.Length)
  }
  return $fullPath
}

function To-Hash($value) {
  if ($null -eq $value) { return $null }
  if ($value -is [hashtable]) { return $value }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $h = @{}; foreach ($p in $value.PSObject.Properties) { $h[$p.Name] = To-Hash $p.Value }; return $h
  }
  if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { return @($value | ForEach-Object { To-Hash $_ }) }
  return $value
}

function Read-JsonHash([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) { return @{} }
  return To-Hash (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Save-JsonHash([string]$Path, [hashtable]$Value) {
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline
}

function Get-DirectoryInventory([string]$Path, [string[]]$ExcludedRelativePaths = @()) {
  if (!(Test-Path -LiteralPath $Path -PathType Container)) { return @() }
  $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
  return @(
    Get-ChildItem -LiteralPath $root -Recurse -Force |
      Sort-Object FullName |
      ForEach-Object {
        $relativePath = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        foreach ($excludedPath in @($ExcludedRelativePaths)) {
          $normalizedExcludedPath = ([string]$excludedPath).Trim('/').Replace('\', '/')
          if ($relativePath -eq $normalizedExcludedPath -or
              $relativePath.StartsWith("$normalizedExcludedPath/", [StringComparison]::OrdinalIgnoreCase)) {
            return
          }
        }
        # Claude writes per-process .in_use sentinels inside a live plugin
        # cache. They are runtime state, not package content, and must not
        # make an otherwise current native plugin appear stale.
        if ($relativePath -eq '.in_use' -or $relativePath.StartsWith('.in_use/')) { return }
        # Qoder's optional manifest directory is host-specific metadata. It is
        # intentionally excluded from Claude/Codex package equivalence checks
        # so adding a verified Qoder adapter cannot make another native plugin
        # appear stale.
        if ($relativePath -eq '.qoder-plugin' -or $relativePath.StartsWith('.qoder-plugin/')) { return }
        # Dependency and build artifact directories are runtime state, not
        # package content. They must not make an otherwise current capability
        # appear stale when npm/pip/etc. materializes them between syncs.
        # Match at any depth (e.g. product-demo-studio/node_modules/...).
        $segments = $relativePath -split '/'
        if ($segments -contains 'node_modules') { return }
        if ($segments -contains '.venv') { return }
        if ($segments -contains '__pycache__') { return }
        if ($segments -contains 'dist') { return }
        if ($segments -contains 'build') { return }
        if ($segments -contains '.next') { return }
        if ($_.PSIsContainer) { 'D|{0}' -f $relativePath }
        else { 'F|{0}|{1}' -f $relativePath, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
      }
  )
}

function Get-ManagedQuarantineContentHash([string]$Path) {
  $rootItem = Get-Item -LiteralPath $Path -Force
  $hashBasis = if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    @("L||$($rootItem.LinkType)|$(@($rootItem.Target) -join '|')")
  } elseif (-not $rootItem.PSIsContainer) {
    @("F||$($rootItem.Length)|$((Get-FileHash -LiteralPath $rootItem.FullName -Algorithm SHA256).Hash)")
  } else {
    $root = $rootItem.FullName.TrimEnd('\')
    @(
      Get-ChildItem -LiteralPath $root -Recurse -Force |
        Sort-Object FullName |
        ForEach-Object {
          $relativePath = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
          if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            "L|$relativePath|$($_.LinkType)|$(@($_.Target) -join '|')"
          } elseif ($_.PSIsContainer) {
            "D|$relativePath"
          } else {
            "F|$relativePath|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
          }
        }
    )
  }
  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($hashBasis -join "`n"))
    return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $sha256.Dispose()
  }
}

function Sync-QwenSubagents([string]$SourceRoot, [string]$DestinationRoot) {
  if (!(Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Managed Qwen subagent source is missing: $SourceRoot"
  }
  New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
  foreach ($source in @(Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.md' | Sort-Object Name)) {
    $destination = Join-Path $DestinationRoot $source.Name
    $current = if (Test-Path -LiteralPath $destination -PathType Leaf) { Get-Content -LiteralPath $destination -Raw -Encoding UTF8 } else { $null }
    $canonical = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8
    if ($current -cne $canonical) {
      Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    }
  }
}

function Sync-QoderSubagents([string]$SourceRoot, [string]$DestinationRoot) {
  if (!(Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Managed Qoder subagent source is missing: $SourceRoot"
  }
  New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
  foreach ($source in @(Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.md' | Sort-Object Name)) {
    $destination = Join-Path $DestinationRoot $source.Name
    $current = if (Test-Path -LiteralPath $destination -PathType Leaf) { Get-Content -LiteralPath $destination -Raw -Encoding UTF8 } else { $null }
    $canonical = Get-Content -LiteralPath $source.FullName -Raw -Encoding UTF8
    if ($current -cne $canonical) {
      Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    }
  }
}

function Sync-QwenPortfolioLsp([string]$RegistryRoot) {
  $contractPath = Join-Path $RegistryRoot 'registry\qwen-lsp-projects.json'
  if (!(Test-Path -LiteralPath $contractPath -PathType Leaf)) { return }
  $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $template = Join-Path $RegistryRoot ([string]$contract.template)
  if (!(Test-Path -LiteralPath $template -PathType Leaf)) { throw "Qwen LSP template is missing: $template" }
  $canonical = Get-Content -LiteralPath $template -Raw -Encoding UTF8
  foreach ($project in @($contract.projects)) {
    $projectPath = [string]$project
    if (!(Test-Path -LiteralPath $projectPath -PathType Container)) {
      Write-Warning "Qwen LSP project is unavailable; preserving configuration state: $projectPath"
      continue
    }
    $destination = Join-Path $projectPath '.lsp.json'
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
      $existing = Get-Content -LiteralPath $destination -Raw -Encoding UTF8
      if ($existing -cne $canonical) { Write-Warning "Preserving repository-owned Qwen LSP configuration: $destination" }
      continue
    }
    Copy-Item -LiteralPath $template -Destination $destination
  }
}

function Set-TomlBoolean([string]$Path, [string]$Section, [string]$Key, [bool]$Value) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $toml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $valueText = if ($Value) { 'true' } else { 'false' }
  $sectionPattern = '(?ms)(^\[' + [regex]::Escape($Section) + '\]\s*$)(.*?)(?=^\[|\z)'
  if ($toml -notmatch $sectionPattern) {
    if ($toml.Length -gt 0 -and -not $toml.EndsWith("`n")) { $toml += "`n" }
    $toml += "`n[$Section]`n$Key = $valueText`n"
  } else {
    $block = $Matches[0]
    if ($block -match ('(?m)^' + [regex]::Escape($Key) + '\s*=')) {
      $replacement = $block -replace ('(?m)^' + [regex]::Escape($Key) + '\s*=.*$'), "$Key = $valueText"
    } else {
      $replacement = $block.TrimEnd() + "`n$Key = $valueText`n"
    }
    $toml = [regex]::Replace($toml, $sectionPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
  }
  [System.IO.File]::WriteAllText($Path, $toml, [System.Text.UTF8Encoding]::new($false))
}

function Test-DirectoryEquivalent([string]$Left, [string]$Right) {
  if (!(Test-Path -LiteralPath $Left -PathType Container) -or !(Test-Path -LiteralPath $Right -PathType Container)) {
    return $false
  }
  try {
    return ((Get-DirectoryInventory $Left) -join "`n") -ceq ((Get-DirectoryInventory $Right) -join "`n")
  } catch [System.IO.IOException], [System.Management.Automation.ItemNotFoundException] {
    # A stale junction can still satisfy Test-Path even when its target was
    # retired. Treat an unreadable managed destination as drift so the exact
    # reparse point can be quarantined and replaced without traversing it.
    return $false
  }
}

function Test-QoderPluginEquivalent([string]$Left, [string]$Right) {
  if (!(Test-Path -LiteralPath $Left -PathType Container) -or !(Test-Path -LiteralPath $Right -PathType Container)) {
    return $false
  }
  try {
    # Qoder materializes empty optional directories and writes .orphaned_at
    # lifecycle state into local plugin caches. Neither changes executable
    # package content, so compare the managed files only.
    $leftFiles = @(Get-DirectoryInventory $Left | Where-Object {
      $_.StartsWith('F|', [StringComparison]::Ordinal) -and -not $_.StartsWith('F|.orphaned_at|', [StringComparison]::Ordinal)
    })
    $rightFiles = @(Get-DirectoryInventory $Right | Where-Object {
      $_.StartsWith('F|', [StringComparison]::Ordinal) -and -not $_.StartsWith('F|.orphaned_at|', [StringComparison]::Ordinal)
    })
    return ($leftFiles -join "`n") -ceq ($rightFiles -join "`n")
  } catch [System.IO.IOException], [System.Management.Automation.ItemNotFoundException] {
    return $false
  }
}

function Test-CopilotPluginAdapterEquivalent([string]$Source, [string]$Destination, [bool]$StripMcpManifest) {
  if (!(Test-Path -LiteralPath $Source -PathType Container) -or
      !(Test-Path -LiteralPath $Destination -PathType Container)) {
    return $false
  }
  $sourceExclusions = if ($StripMcpManifest) { @('.mcp.json') } else { @() }
  try {
    return ((Get-DirectoryInventory $Source $sourceExclusions) -join "`n") -ceq
      ((Get-DirectoryInventory $Destination) -join "`n")
  } catch [System.IO.IOException], [System.Management.Automation.ItemNotFoundException] {
    return $false
  }
}

function Copy-DirectoryToStage([string]$Source, [string]$Stage) {
  New-Item -ItemType Directory -Path $Stage -Force | Out-Null
  $excludedNames = @('node_modules', '.venv', '__pycache__', 'dist', 'build', '.next')
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin $excludedNames } |
    Copy-Item -Destination $Stage -Recurse -Force
}

# Skill targets are an explicit host allowlist. A new managed host must declare a
# reviewed, host-native skill location here before this script will write to it.
$skillTargets = [ordered]@{
  'claude' = "$UserProfile\.claude\skills"
  'codex' = "$UserProfile\.codex\skills"
  'cursor' = "$UserProfile\.cursor\skills"
  'qwen-code' = "$UserProfile\.qwen\skills"
  'opencode' = "$UserProfile\.config\opencode\skills"
  'factory' = "$UserProfile\.factory\skills"
  'devin' = "$appDataRoot\devin\skills"
  'amp' = "$UserProfile\.config\amp\skills"
  'windsurf' = "$UserProfile\.codeium\windsurf\skills"
  'gemini' = "$UserProfile\.gemini\skills"
  'hermes' = "$UserProfile\AppData\Local\hermes\skills"
  'grok' = "$UserProfile\.grok\skills"
  'antigravity' = "$UserProfile\.gemini\config\skills"
  'warp' = "$UserProfile\.warp\skills"
  'copilot' = "$UserProfile\.copilot\skills"
  'cline' = "$UserProfile\.cline\skills"
  'qoder' = "$UserProfile\.qoder\skills"
}

$nativeOnlyVideoHosts = @('vscode-insiders')
$unknownSkillHosts = @($profile.managedHosts | Where-Object { -not $skillTargets.Contains($_) -and $_ -notin $nativeOnlyVideoHosts } | Sort-Object -Unique)
if ($unknownSkillHosts.Count) {
  throw "Managed host(s) have no reviewed skill target: $($unknownSkillHosts -join ', '). Update the allowlist before applying the profile."
}

# Global instruction deployment is owned by scripts/agentctl.ps1 sync so the
# generated artifacts, destination inventory, drift guard, and backups stay
# centralized. Qoder uses repository AGENTS.md directly; its documented rules
# are project-scoped under .qoder/rules.
$globalPolicySource = Join-Path $RegistryRoot 'standards\global-agent-policy.md'
if (!(Test-Path -LiteralPath $globalPolicySource -PathType Leaf)) { throw "Canonical global policy is missing: $globalPolicySource" }

# product-demo-studio is the single owner of the managed product-video skill
# surface. Keep its sibling list explicit so a rename/addition fails closed
# instead of leaving different hosts with different generations of the plugin.
$managedVideoSkillNames = @(
  'product-demo-studio',
  'product-demo-studio-capture',
  'product-demo-studio-descript',
  'product-demo-studio-narration',
  'product-demo-studio-qa',
  'product-demo-studio-remotion',
  'product-demo-studio-render',
  'product-demo-studio-visual-assets'
)
$retiredVideoArtifacts = @(
  @{ name = 'remotion-video-creation'; reason = 'Legacy end-to-end video owner superseded by product-demo-studio.' }
)

$videoCapability = @($caps.capabilities | Where-Object { $_.id -eq 'product-demo-studio' })
if ($videoCapability.Count -ne 1) { throw "Expected exactly one canonical product-demo-studio capability; found $($videoCapability.Count)." }
$videoPluginRoot = Resolve-RegistryOwnedPath ([string]$videoCapability[0].canonicalSource)
$videoSkillsSource = Join-Path $videoPluginRoot 'skills'
if (!(Test-Path -LiteralPath $videoSkillsSource -PathType Container)) { throw "Canonical product-demo-studio skills are missing: $videoSkillsSource" }
$videoManifestPath = Join-Path $videoPluginRoot '.codex-plugin\plugin.json'
if (!(Test-Path -LiteralPath $videoManifestPath -PathType Leaf)) { throw "Canonical Codex plugin manifest is missing: $videoManifestPath" }
$videoPluginVersion = [string](Get-Content -LiteralPath $videoManifestPath -Raw | ConvertFrom-Json).version
$actualVideoSkillNames = @(Get-ChildItem -LiteralPath $videoSkillsSource -Directory | ForEach-Object Name | Sort-Object)
if (($actualVideoSkillNames -join '|') -cne (($managedVideoSkillNames | Sort-Object) -join '|')) {
  throw "Canonical product-demo-studio siblings do not match the managed allowlist. Canonical: $($actualVideoSkillNames -join ', '); allowlist: $(($managedVideoSkillNames | Sort-Object) -join ', ')."
}
foreach ($skillName in $managedVideoSkillNames) {
  $skillFile = Join-Path $videoSkillsSource "$skillName\SKILL.md"
  if (!(Test-Path -LiteralPath $skillFile -PathType Leaf)) { throw "Canonical sibling is missing SKILL.md: $skillFile" }
}

# Product Experience Engineering is a second canonical package with the same
# native/loose host policy. Its complete sibling list is explicit so source
# drift fails closed before any host tree is changed.
$managedExperienceSkillNames = @(
  'audit-product-experience',
  'design-agentic-experiences',
  'design-new-application-experience',
  'design-workflows-and-features',
  'discover-application',
  'engineer-product-experience',
  'implement-experience-improvements',
  'measure-experience-outcomes',
  'prepare-product-for-demo',
  'specify-experience-improvements',
  'validate-product-experience'
)
$experienceCapability = @($caps.capabilities | Where-Object { $_.id -eq 'product-experience-engineering' })
if ($experienceCapability.Count -ne 1) { throw "Expected exactly one canonical product-experience-engineering capability; found $($experienceCapability.Count)." }
$experiencePluginRoot = Resolve-RegistryOwnedPath ([string]$experienceCapability[0].canonicalSource)
$experienceSkillsSource = Join-Path $experiencePluginRoot 'skills'
if (!(Test-Path -LiteralPath $experienceSkillsSource -PathType Container)) { throw "Canonical product-experience-engineering skills are missing: $experienceSkillsSource" }
$experienceManifestPath = Join-Path $experiencePluginRoot '.codex-plugin\plugin.json'
if (!(Test-Path -LiteralPath $experienceManifestPath -PathType Leaf)) { throw "Canonical Codex plugin manifest is missing: $experienceManifestPath" }
$experiencePluginVersion = [string](Get-Content -LiteralPath $experienceManifestPath -Raw | ConvertFrom-Json).version
if ([string]::IsNullOrWhiteSpace($experiencePluginVersion)) { throw "Canonical product-experience-engineering manifest has no version: $experienceManifestPath" }
$actualExperienceSkillNames = @(Get-ChildItem -LiteralPath $experienceSkillsSource -Directory | ForEach-Object Name | Sort-Object)
if (($actualExperienceSkillNames -join '|') -cne (($managedExperienceSkillNames | Sort-Object) -join '|')) {
  throw "Canonical product-experience-engineering siblings do not match the managed allowlist. Canonical: $($actualExperienceSkillNames -join ', '); allowlist: $(($managedExperienceSkillNames | Sort-Object) -join ', ')."
}
foreach ($skillName in $managedExperienceSkillNames) {
  $skillFile = Join-Path $experienceSkillsSource "$skillName\SKILL.md"
  if (!(Test-Path -LiteralPath $skillFile -PathType Leaf)) { throw "Canonical sibling is missing SKILL.md: $skillFile" }
}

$managedSkillCapabilities = @(
  @{ id='product-demo-studio'; pluginRoot=$videoPluginRoot; skillsSource=$videoSkillsSource; version=$videoPluginVersion; skillNames=$managedVideoSkillNames },
  @{ id='product-experience-engineering'; pluginRoot=$experiencePluginRoot; skillsSource=$experienceSkillsSource; version=$experiencePluginVersion; skillNames=$managedExperienceSkillNames }
)
$copilotPluginRoots = @($managedSkillCapabilities | ForEach-Object {
  Join-Path $localAppDataRoot "AgentHub\runtime\copilot\plugins\$($_.id)"
})
$copilotPluginArgs = @($copilotPluginRoots | ForEach-Object {
  '--plugin-dir "' + ([string]$_).Replace('\','/') + '"'
}) -join ' '

$quarantineBatch = New-AgentHubQuarantineBatch -UserProfilePath $UserProfile
$quarantineBatchRoot = $quarantineBatch.BatchRoot

function Install-ManagedSkill([string]$HostId, [string]$TargetRoot, [string]$SkillName, [string]$SkillsSource, [string]$OwnerId) {
  $source = Join-Path $SkillsSource $SkillName
  $destination = Join-Path $TargetRoot $SkillName
  if (Test-DirectoryEquivalent $source $destination) { return }

  New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
  $stage = Join-Path $TargetRoot ('.agenthub-stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $null
  try {
    Copy-DirectoryToStage $source $stage
    if (Test-Path -LiteralPath $destination -PathType Container) {
      $backup = Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $destination `
        -HostId $HostId -ArtifactKind 'skills' -ArtifactName $SkillName `
        -Reason "Replaced by the current canonical $OwnerId sibling." `
        -ContentHash (Get-ManagedQuarantineContentHash -Path $destination)
    }
    Move-Item -LiteralPath $stage -Destination $destination
  } catch {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($backup -and !(Test-Path -LiteralPath $destination) -and (Test-Path -LiteralPath $backup)) {
      Move-Item -LiteralPath $backup -Destination $destination
    }
    throw
  }
}

function Get-NativePluginState([string]$HostId, [string]$CapabilityId, [string]$PluginRoot, [string]$PluginVersion) {
  $marketplaceKey = "$CapabilityId@handoff"
  $capability = $caps.capabilities | Where-Object id -eq $CapabilityId | Select-Object -First 1
  $mapping = @($capability.hostMappings | Where-Object hostId -eq $HostId | Select-Object -First 1)
  $deploymentStatus = if ($mapping.Count -eq 1) { [string]$mapping[0].deploymentStatus } else { '' }
  $expectsNativePlugin = $deploymentStatus -in @(
    'native-plugin-installed',
    'native-local-plugin',
    'native-local-plugin-skills-only'
  )
  if ($HostId -eq 'claude') {
    $installedPath = Join-Path $UserProfile '.claude\plugins\installed_plugins.json'
    $settingsPath = Join-Path $UserProfile '.claude\settings.json'
    $enabled = $false
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
      $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
      $enabledProperty = if ($settings.enabledPlugins) {
        $settings.enabledPlugins.PSObject.Properties[$marketplaceKey]
      } else {
        $null
      }
      $enabled = $enabledProperty -and $enabledProperty.Value -eq $true
    }
    if ($enabled -and -not $expectsNativePlugin) {
      throw "Claude has enabled $marketplaceKey, but the registry maps $CapabilityId as '$deploymentStatus'. Disable or uninstall the plugin before deploying loose skills."
    }
    if (-not $enabled -or !(Test-Path -LiteralPath $installedPath -PathType Leaf)) {
      return @{ installed=$false; current=$false; path=$null }
    }
    $installed = Get-Content -LiteralPath $installedPath -Raw | ConvertFrom-Json
    $pluginProperty = if ($installed.plugins) { $installed.plugins.PSObject.Properties[$marketplaceKey] } else { $null }
    if (-not $pluginProperty) { return @{ installed=$false; current=$false; path=$null } }
    $entries = @($pluginProperty.Value)
    if ($entries.Count -eq 0) { return @{ installed=$false; current=$false; path=$null } }
    $entry = $entries | Where-Object { $_.scope -eq 'user' } | Select-Object -First 1
    if (-not $entry) { $entry = $entries | Select-Object -First 1 }
    $path = [string]$entry.installPath
    $current = [string]$entry.version -eq $PluginVersion -and (Test-DirectoryEquivalent $PluginRoot $path)
    return @{ installed=$true; current=$current; path=$path }
  }
  if ($HostId -eq 'codex') {
    $configPath = Join-Path $UserProfile '.codex\config.toml'
    $enabledPattern = '(?m)^\[plugins\."' + [regex]::Escape($marketplaceKey) + '"\]\r?\nenabled\s*=\s*true\s*$'
    $enabled = (Test-Path -LiteralPath $configPath -PathType Leaf) -and
      ((Get-Content -LiteralPath $configPath -Raw) -match $enabledPattern)
    if ($enabled -and -not $expectsNativePlugin) {
      throw "Codex has enabled $marketplaceKey, but the registry maps $CapabilityId as '$deploymentStatus'. Disable the plugin before deploying loose skills."
    }
    if (-not $enabled) { return @{ installed=$false; current=$false; path=$null } }
    $path = Join-Path $UserProfile ".codex\plugins\cache\handoff\$CapabilityId\$PluginVersion"
    return @{ installed=$true; current=(Test-DirectoryEquivalent $PluginRoot $path); path=$path }
  }
  if ($HostId -eq 'copilot') {
    $wrapper = Join-Path $UserProfile 'bin\copilot.cmd'
    if (!(Test-Path -LiteralPath $wrapper -PathType Leaf)) { return @{ installed=$false; current=$false; path=$null } }
    $path = Join-Path $localAppDataRoot "AgentHub\runtime\copilot\plugins\$CapabilityId"
    $raw = Get-Content -LiteralPath $wrapper -Raw
    $portablePath = $path.Replace('\','/')
    $stripMcpManifest = $CapabilityId -eq 'product-demo-studio'
    $current = $raw.Contains('--plugin-dir') -and
      ($raw.Contains($path) -or $raw.Contains($portablePath)) -and
      (Test-CopilotPluginAdapterEquivalent $PluginRoot $path $stripMcpManifest)
    if ($current -and -not $expectsNativePlugin) {
      throw "Copilot loads $CapabilityId as a native adapter, but the registry maps it as '$deploymentStatus'."
    }
    return @{ installed=$current; current=$current; path=$path }
  }
  return @{ installed=$false; current=$false; path=$null }
}

function Ensure-QoderPlugins {
  $qoderCli = Join-Path $UserProfile '.qoder\bin\qodercli\qodercli.exe'
  if (!(Test-Path -LiteralPath $qoderCli -PathType Leaf)) { throw "Qoder CLI is missing: $qoderCli" }
  $installed = @()
  try { $installed = @((& $qoderCli plugins list --json 2>$null | ConvertFrom-Json)) } catch { $installed = @() }
  foreach ($capability in @($caps.capabilities)) {
    $mapping = @($capability.hostMappings | Where-Object hostId -eq 'qoder' | Select-Object -First 1)
    if ($mapping.Count -ne 1 -or [string]$mapping[0].deploymentStatus -ne 'native-local-plugin') { continue }

    $source = Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
    $current = @($installed | Where-Object {
      $_.name -eq [string]$capability.id -and $_.scope -eq 'user' -and $_.enabled -eq $true
    })
    $currentEntry = $current | Select-Object -First 1
    $currentPath = if ($currentEntry) { [string]$currentEntry.installPath } else { $null }
    $needsInstall = $current.Count -ne 1 -or
      [string]::IsNullOrWhiteSpace($currentPath) -or
      -not (Test-QoderPluginEquivalent $source $currentPath)

    if ($needsInstall) {
      if ($current.Count -gt 0) {
        & $qoderCli plugins uninstall --scope user "$($capability.id)@local" --json | Out-Host
        if ($LASTEXITCODE -ne 0) {
          throw "Qoder could not uninstall stale native plugin $($capability.id) before replacement."
        }
      }

      & $qoderCli plugins install --scope user $source --json | Out-Host
      if ($LASTEXITCODE -ne 0) { throw "Qoder could not install native plugin $($capability.id) from $source" }
    }

    $refreshed = @()
    try { $refreshed = @((& $qoderCli plugins list --json 2>$null | ConvertFrom-Json)) } catch { $refreshed = @() }
    $current = @($refreshed | Where-Object {
      $_.name -eq [string]$capability.id -and $_.scope -eq 'user' -and $_.enabled -eq $true
    })
    if ($current.Count -ne 1) {
      throw "Qoder did not report exactly one enabled user plugin for $($capability.id) after reconciliation."
    }
    $currentPath = [string]$current[0].installPath
    if (-not (Test-QoderPluginEquivalent $source $currentPath)) {
      throw "Qoder plugin $($capability.id) remains content-stale after reconciliation: $currentPath"
    }

    # Qoder's official uninstall leaves old version directories in its cache.
    # They remain discoverable to inventory tools and can be selected by older
    # host builds, so retire only same-name version siblings after the current
    # installed tree has been verified byte-equivalent.
    $cacheRoot = Split-Path -Parent $currentPath
    foreach ($cachedVersion in @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force)) {
      if ($cachedVersion.FullName.Equals($currentPath, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $cachedManifestPath = Join-Path $cachedVersion.FullName '.qoder-plugin\plugin.json'
      if (!(Test-Path -LiteralPath $cachedManifestPath -PathType Leaf)) {
        Write-Warning "Preserving unverified Qoder cache sibling: $($cachedVersion.FullName)"
        continue
      }
      try {
        $cachedManifest = Get-Content -LiteralPath $cachedManifestPath -Raw | ConvertFrom-Json
      } catch {
        Write-Warning "Preserving unreadable Qoder cache sibling: $($cachedVersion.FullName)"
        continue
      }
      if ([string]$cachedManifest.name -ne [string]$capability.id) {
        Write-Warning "Preserving mismatched Qoder cache sibling: $($cachedVersion.FullName)"
        continue
      }
      Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $cachedVersion.FullName `
        -HostId 'qoder' -ArtifactKind 'plugin-cache' `
        -ArtifactName "$($capability.id)-$($cachedVersion.Name)" `
        -Reason "Superseded Qoder cache generation retired after the current native plugin was verified." `
        -ContentHash (Get-ManagedQuarantineContentHash -Path $cachedVersion.FullName) |
        Out-Null
    }

    $installed = $refreshed
  }
}

function Ensure-LocalNativeAdapters {
  # Copilot CLI can load a local plugin directly. VS Code Insiders automatically
  # supports the same plugin format and exposes an official local-location map.
  $bin = Join-Path $UserProfile 'bin'
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  foreach ($capability in $managedSkillCapabilities) {
    $adapterRoot = Join-Path $localAppDataRoot "AgentHub\runtime\copilot\plugins\$($capability.id)"
    $stripMcpManifest = $capability.id -eq 'product-demo-studio'
    if (!(Test-CopilotPluginAdapterEquivalent $capability.pluginRoot $adapterRoot $stripMcpManifest)) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $adapterRoot) -Force | Out-Null
      $stage = Join-Path (Split-Path -Parent $adapterRoot) ('.agenthub-stage-' + [guid]::NewGuid().ToString('N'))
      $backup = $null
      try {
        Copy-DirectoryToStage $capability.pluginRoot $stage
        if ($stripMcpManifest) {
          $mcpManifest = Join-Path $stage '.mcp.json'
          if (Test-Path -LiteralPath $mcpManifest -PathType Leaf) {
            Remove-Item -LiteralPath $mcpManifest -Force
          }
        }
        if (Test-Path -LiteralPath $adapterRoot -PathType Container) {
          $backup = Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $adapterRoot `
            -HostId 'copilot' -ArtifactKind 'plugin-adapters' `
            -ArtifactName $capability.id `
            -Reason "Replaced by the current canonical $($capability.id) Copilot adapter." `
            -ContentHash (Get-ManagedQuarantineContentHash -Path $adapterRoot)
        }
        Move-Item -LiteralPath $stage -Destination $adapterRoot
      } catch {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        if ($backup -and !(Test-Path -LiteralPath $adapterRoot) -and (Test-Path -LiteralPath $backup)) {
          Move-Item -LiteralPath $backup -Destination $adapterRoot
        }
        throw
      }
    }
  }
  $copilotWrapper = Join-Path $bin 'copilot.cmd'
  $copilotWrapperContent = '@echo off' + "`r`n" + '"%APPDATA%\npm\copilot.cmd" ' + $copilotPluginArgs + ' --allow-all --autopilot --no-ask-user --allow-all-mcp-server-instructions %*'
  if (!(Test-Path -LiteralPath $copilotWrapper) -or (Get-Content -LiteralPath $copilotWrapper -Raw) -cne $copilotWrapperContent) {
    Set-Content -LiteralPath $copilotWrapper -Value $copilotWrapperContent -Encoding ASCII -NoNewline
  }

  $vscodeSettingsPath = Join-Path $UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json'
  $vscodeSettings = Read-JsonHash $vscodeSettingsPath
  $locations = @{}
  if ($vscodeSettings.ContainsKey('chat.pluginLocations')) { $locations = To-Hash $vscodeSettings['chat.pluginLocations'] }
  $locationsChanged = $false
  foreach ($existingLocation in @($locations.Keys)) {
    $portableExistingLocation = ([string]$existingLocation).Replace('\','/')
    if ($portableExistingLocation.StartsWith('C:/Repos/agent-capabilities/', [StringComparison]::OrdinalIgnoreCase) -or
        $portableExistingLocation.StartsWith('C:/Repos/agenthub/', [StringComparison]::OrdinalIgnoreCase)) {
      $locations.Remove($existingLocation)
      $locationsChanged = $true
    }
  }
  foreach ($capability in $managedSkillCapabilities) {
    $portablePluginPath = ([string]$capability.pluginRoot).Replace('\','/')
    if (-not $locations.ContainsKey($portablePluginPath) -or $locations[$portablePluginPath] -ne $true) {
      $locations[$portablePluginPath] = $true
      $locationsChanged = $true
    }
  }
  if ($locationsChanged) {
      $vscodeSettings['chat.pluginLocations'] = $locations
      Save-JsonHash $vscodeSettingsPath $vscodeSettings
  }
}

function Retire-QoderNativePluginLooseSkills {
  $qoderSkillRoot = Join-Path $UserProfile '.qoder\skills'
  foreach ($capability in @($caps.capabilities)) {
    $qoderMapping = @($capability.hostMappings | Where-Object hostId -eq 'qoder' | Select-Object -First 1)
    if ($qoderMapping.Count -ne 1 -or [string]$qoderMapping[0].deploymentStatus -ne 'native-local-plugin') { continue }
    $sourceSkills = Join-Path (
      Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
    ) 'skills'
    if (!(Test-Path -LiteralPath $sourceSkills -PathType Container)) { continue }
    foreach ($sourceSkill in @(Get-ChildItem -LiteralPath $sourceSkills -Directory)) {
      $loosePath = Join-Path $qoderSkillRoot $sourceSkill.Name
      if (!(Test-Path -LiteralPath $loosePath -PathType Container)) { continue }
      if (-not (Test-DirectoryEquivalent $sourceSkill.FullName $loosePath)) {
        throw "Qoder has a divergent loose $($sourceSkill.Name) skill alongside the verified native $($capability.id) plugin: $loosePath"
      }
      Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $loosePath `
        -HostId 'qoder' -ArtifactKind 'skills' -ArtifactName $sourceSkill.Name `
        -Reason "Current native $($capability.id) plugin is enabled; duplicate loose skill retired." `
        -ContentHash (Get-ManagedQuarantineContentHash -Path $loosePath) |
        Out-Null
    }
  }
}

Ensure-LocalNativeAdapters
if (-not $SkillDistributionOnly) {
  Ensure-QoderPlugins
  Retire-QoderNativePluginLooseSkills
}
$nativePluginStates = @{}
foreach ($capability in $managedSkillCapabilities) {
  foreach ($hostId in @('claude','codex','copilot')) {
    $stateForHost = Get-NativePluginState $hostId $capability.id $capability.pluginRoot $capability.version
    if ($stateForHost.installed -and -not $stateForHost.current) {
      throw "$hostId has an enabled but stale $($capability.id) plugin at $($stateForHost.path). Reinstall v$($capability.version) before distribution to avoid duplicate generations."
    }
    $nativePluginStates["$($capability.id)::$hostId"] = $stateForHost
  }
}

# Replace every owned sibling as a complete tree. This removes stale files that
# Copy-Item -Force cannot remove while retaining the prior tree in quarantine.
foreach ($capability in $managedSkillCapabilities) {
  foreach ($hostId in @($profile.managedHosts | Where-Object { $_ -ne 'qwen-code' -and $skillTargets.Contains($_) })) {
    $targetRoot = [string]$skillTargets[$hostId]
    $qoderMapping = @($capabilityHostMappings = $caps.capabilities | Where-Object id -eq $capability.id | Select-Object -First 1)
    if ($hostId -eq 'qoder' -and @($qoderMapping.hostMappings | Where-Object { $_.hostId -eq 'qoder' -and $_.deploymentStatus -eq 'native-local-plugin' }).Count -eq 1) {
      continue
    }
    $nativeState = $nativePluginStates["$($capability.id)::$hostId"]
    if ($nativeState -and $nativeState.current) {
      foreach ($skillName in $capability.skillNames) {
        $loosePath = Join-Path $targetRoot $skillName
        if (Test-Path -LiteralPath $loosePath -PathType Container) {
          Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $loosePath `
            -HostId $hostId -ArtifactKind 'skills' -ArtifactName $skillName `
            -Reason "Native $($capability.id) plugin v$($capability.version) is enabled; duplicate loose skill retired." `
            -ContentHash (Get-ManagedQuarantineContentHash -Path $loosePath) |
            Out-Null
        }
      }
    } else {
      foreach ($skillName in $capability.skillNames) {
        Install-ManagedSkill $hostId $targetRoot $skillName $capability.skillsSource $capability.id
      }
    }
  }
}

# Cursor discovers both ~/.cursor/skills and ~/.cursor/plugins/local. Capabilities
# mapped as managed loose skills must not retain an older local plugin copy,
# otherwise Cursor sees two owners (and can select stale instructions). Cursor
# remains provider-held; this only reconciles its on-disk discovery paths and
# does not launch or probe the host.
$cursorLocalPluginRoot = Join-Path $UserProfile '.cursor\plugins\local'
foreach ($capability in @($caps.capabilities)) {
  $cursorMapping = @($capability.hostMappings | Where-Object hostId -eq 'cursor' | Select-Object -First 1)
  if ($cursorMapping.Count -ne 1 -or [string]$cursorMapping[0].deploymentStatus -ne 'managed') { continue }
  $legacyPluginPath = Join-Path $cursorLocalPluginRoot ([string]$capability.id)
  if (Test-Path -LiteralPath $legacyPluginPath -PathType Container) {
    Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $legacyPluginPath `
      -HostId 'cursor' -ArtifactKind 'plugins' `
      -ArtifactName ([string]$capability.id) `
      -Reason "Registry maps this capability to managed loose skills; conflicting local plugin copy retired." `
      -ContentHash (Get-ManagedQuarantineContentHash -Path $legacyPluginPath) |
      Out-Null
  }
}

# Qwen's native extensions are junctions to the canonical capabilities. Copying
# the same skills into ~/.qwen/skills would expose two owners in the same host.
# Validate the adapter instead and let Sync-AgentHub maintain it.
if ('qwen-code' -in @($profile.managedHosts)) {
  foreach ($capability in $managedSkillCapabilities) {
    $extensionName = "agenthub-$($capability.id)"
    $qwenExtensionRoot = Join-Path $UserProfile ".qwen\extensions\$extensionName"
    $qwenAdapterRoot = Join-Path $localAppDataRoot "AgentHub\runtime\qwen-code\extensions\$extensionName"
    if (!(Test-Path -LiteralPath $qwenExtensionRoot -PathType Container) -and (Test-Path -LiteralPath $qwenAdapterRoot -PathType Container)) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $qwenExtensionRoot) -Force | Out-Null
      New-Item -ItemType Junction -Path $qwenExtensionRoot -Target $qwenAdapterRoot | Out-Null
    }
    $qwenExtensionSkills = Join-Path $qwenExtensionRoot 'skills'
    if (!(Test-DirectoryEquivalent $capability.skillsSource $qwenExtensionSkills)) {
      throw "Qwen $($capability.id) extension is missing or stale: $qwenExtensionSkills. Run Sync-AgentHub before applying skill distribution."
    }
  }
}

# Retire only exact names in the reviewed conflict map. Similar-looking or
# user-authored video skills are deliberately preserved. Plugin/extension roots
# are limited to native paths already registered for these hosts.
$legacyArtifactRoots = @()
foreach ($hostId in @($profile.managedHosts | Where-Object { $skillTargets.Contains($_) })) {
  $legacyArtifactRoots += @{ hostId = $hostId; kind = 'skills'; path = [string]$skillTargets[$hostId] }
}
if ($RetireLegacyVideoOwners) {
  $legacyArtifactRoots += @(
    @{ hostId = 'claude'; kind = 'plugins'; path = "$UserProfile\.claude\plugins" },
    @{ hostId = 'codex'; kind = 'plugins'; path = "$UserProfile\.codex\plugins" },
    @{ hostId = 'cursor'; kind = 'plugins'; path = "$UserProfile\.cursor\plugins" },
    @{ hostId = 'factory'; kind = 'plugins'; path = "$UserProfile\.factory\plugins" },
    @{ hostId = 'qwen-code'; kind = 'extensions'; path = "$UserProfile\.qwen\extensions" }
  )
}
function Test-RetiredVideoArtifactSignature([string]$Path, [string]$Kind, [string]$ExpectedName) {
  if ($Kind -eq 'skills') {
    $skillFile = Join-Path $Path 'SKILL.md'
    if (!(Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $false }
    return (Get-Content -LiteralPath $skillFile -Raw) -match ('(?m)^name:\s*' + [regex]::Escape($ExpectedName) + '\s*$')
  }
  if ($Kind -eq 'extensions') {
    $manifest = Join-Path $Path 'qwen-extension.json'
    if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) { return $false }
    try { return (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).name -eq $ExpectedName } catch { return $false }
  }
  foreach ($relative in @('.claude-plugin\plugin.json','.codex-plugin\plugin.json','plugin.json')) {
    $manifest = Join-Path $Path $relative
    if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
    try { if ((Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).name -eq $ExpectedName) { return $true } } catch { }
  }
  return $false
}
foreach ($artifactRoot in $legacyArtifactRoots) {
  foreach ($retired in $retiredVideoArtifacts) {
    $legacyPath = Join-Path $artifactRoot.path $retired.name
    if (Test-Path -LiteralPath $legacyPath -PathType Container) {
      if (Test-RetiredVideoArtifactSignature $legacyPath $artifactRoot.kind $retired.name) {
        Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $legacyPath `
          -HostId $artifactRoot.hostId -ArtifactKind $artifactRoot.kind `
          -ArtifactName $retired.name -Reason $retired.reason `
          -ContentHash (Get-ManagedQuarantineContentHash -Path $legacyPath) |
          Out-Null
      } else {
        Write-Warning "Preserving exact-named artifact without the audited legacy signature: $legacyPath"
      }
    }
  }
}

# Exact dormant owners from pre-registry generations. These paths were audited
# as unreferenced or uninstalled; quarantine them as whole trees so rollback is
# possible and no old slash-command surface can be rediscovered from a cache.
$retiredLegacyOwners = @(
  @{
    hostId = 'codex'
    kind = 'plugin-source'
    name = 'autonomous-product-video-studio'
    path = (Join-Path $UserProfile 'plugins\autonomous-product-video-studio')
    signature = 'autonomous-0.1'
    reason = "Dormant pre-registry video owner superseded by canonical product-demo-studio $videoPluginVersion."
  },
  @{
    hostId = 'shared'
    kind = 'plugin-source'
    name = 'product-demo-studio-pre-registry'
    path = (Join-Path $UserProfile '.agents\plugins\plugins\product-demo-studio')
    signature = 'product-demo-pre-registry'
    reason = 'Orphan pre-registry product-demo-studio source superseded by the repository canonical owner.'
  },
  @{
    hostId = 'claude'
    kind = 'plugin-cache'
    name = 'product-demo-studio-0.1.x'
    path = (Join-Path $UserProfile '.claude\plugins\cache\handoff\product-demo-studio')
    signature = 'claude-cache-0.1'
    reason = 'Uninstalled Claude cache generations 0.1.0 through 0.1.4 superseded by canonical 0.3.0.'
  }
)
$localAiCapabilities = @($caps.capabilities | Where-Object id -eq 'local-ai-stack')
if ($localAiCapabilities.Count -eq 1) {
  $localAiCapability = $localAiCapabilities[0]
  $localAiHostIds = @($localAiCapability.hostMappings | ForEach-Object { [string]$_.hostId })
  $localAiSkill = Join-Path (
    Resolve-RegistryOwnedPath ([string]$localAiCapability.canonicalSource)
  ) 'skills\local-ai-stack\SKILL.md'
  if ($localAiHostIds.Count -eq 1 -and
      $localAiHostIds[0] -eq 'codex' -and
      (Test-Path -LiteralPath $localAiSkill -PathType Leaf)) {
    $retiredLegacyOwners += @{
      hostId = 'claude'
      kind = 'skills'
      name = 'local-ai-stack'
      path = (Join-Path $UserProfile '.claude\skills\local-ai-stack')
      signature = 'claude-creative-lab-local-ai'
      reason = 'Orphan Creative Lab local-ai-stack skill superseded by the AgentHub-owned Codex capability and D:\AI-Platform runtime.'
    }
  }
}
function Test-RetiredLegacySignature([hashtable]$Owner) {
  switch ($Owner.signature) {
    'autonomous-0.1' {
      $manifest = Join-Path $Owner.path '.codex-plugin\plugin.json'
      if (!(Test-Path -LiteralPath $manifest -PathType Leaf)) { return $false }
      $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
      return $data.name -eq 'autonomous-product-video-studio' -and "$($data.version)" -like '0.1.0+codex.*'
    }
    'product-demo-pre-registry' {
      $claudeManifest = Join-Path $Owner.path '.claude-plugin\plugin.json'
      $codexManifest = Join-Path $Owner.path '.codex-plugin\plugin.json'
      if (!(Test-Path -LiteralPath $claudeManifest) -or !(Test-Path -LiteralPath $codexManifest)) { return $false }
      $claudeData = Get-Content -LiteralPath $claudeManifest -Raw | ConvertFrom-Json
      $codexData = Get-Content -LiteralPath $codexManifest -Raw | ConvertFrom-Json
      return "$($claudeData.version)" -eq '0.2.0' -and "$($codexData.version)" -like '0.1.4+codex.*'
    }
    'claude-cache-0.1' {
      $versions = @(Get-ChildItem -LiteralPath $Owner.path -Directory | ForEach-Object Name)
      return $versions.Count -gt 0 -and @($versions | Where-Object { $_ -notin @('0.1.0','0.1.1','0.1.2','0.1.3','0.1.4') }).Count -eq 0
    }
    'claude-creative-lab-local-ai' {
      $skillFile = Join-Path $Owner.path 'SKILL.md'
      if (!(Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $false }
      $content = Get-Content -LiteralPath $skillFile -Raw
      return $content -match '(?m)^name:\s*local-ai-stack\s*$' -and
        $content.Contains('Canonical copy: `C:\Repos\creative-lab\skills\local-ai-stack\SKILL.md` (committed).') -and
        $content.Contains("## The father's-memorial pipeline (personal, high-care)")
    }
    default { return $false }
  }
}
if ($RetireLegacyVideoOwners) {
  foreach ($legacyOwner in $retiredLegacyOwners) {
    if (Test-Path -LiteralPath $legacyOwner.path -PathType Container) {
      if (Test-RetiredLegacySignature $legacyOwner) {
        Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $legacyOwner.path `
          -HostId $legacyOwner.hostId -ArtifactKind $legacyOwner.kind `
          -ArtifactName $legacyOwner.name -Reason $legacyOwner.reason `
          -ContentHash (
            Get-ManagedQuarantineContentHash -Path $legacyOwner.path
          ) | Out-Null
      } elseif ($legacyOwner.signature -eq 'claude-cache-0.1' -and (Test-Path -LiteralPath (Join-Path $legacyOwner.path $videoPluginVersion) -PathType Container)) {
        # The canonical native Claude plugin now owns this cache root. Its
        # current version is expected and must not be treated as legacy noise.
        continue
      } else {
        Write-Warning "Preserving unexpected artifact at $($legacyOwner.path); it no longer matches the audited retirement signature."
      }
    }
  }
}

# Preserve the existing merge behavior for unrelated canonical capabilities.
# The two canonical handoff packages are excluded because they are managed as
# exact trees above.
function Test-ExpectedSkillJunction([string]$Path, [string]$Source) {
  if (!(Test-Path -LiteralPath $Path -PathType Container)) { return $false }
  $item = Get-Item -LiteralPath $Path -Force
  if ($item.LinkType -ne 'Junction') { return $false }
  $target = [IO.Path]::GetFullPath([string]$item.Target)
  $expected = [IO.Path]::GetFullPath($Source)
  return $target.Equals($expected, [StringComparison]::OrdinalIgnoreCase)
}

foreach ($target in $skillTargets.Values | Select-Object -Unique) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
foreach ($cap in $caps.capabilities | Where-Object { $_.id -notin @('product-demo-studio','product-experience-engineering') }) {
  $sourceSkills = Join-Path (
    Resolve-RegistryOwnedPath ([string]$cap.canonicalSource)
  ) 'skills'
  if (!(Test-Path -LiteralPath $sourceSkills)) { continue }
  $sourceSkillDirectories = @(Get-ChildItem -LiteralPath $sourceSkills -Directory)
  $managedSkillNames = if ($cap.PSObject.Properties.Name -contains 'managedSkillNames') {
    @($cap.managedSkillNames | ForEach-Object { [string]$_ })
  } else {
    @($sourceSkillDirectories | ForEach-Object Name)
  }
  $missingManagedSkills = @($managedSkillNames | Where-Object { $_ -notin @($sourceSkillDirectories | ForEach-Object Name) })
  if ($missingManagedSkills.Count) {
    throw "Capability $($cap.id) manages missing canonical skill(s): $($missingManagedSkills -join ', ')"
  }
  $retiredSkillNames = if ($cap.PSObject.Properties.Name -contains 'retiredSkillNames') {
    @($cap.retiredSkillNames | ForEach-Object { [string]$_ })
  } else {
    @()
  }
  $retiredSkillContracts = if ($cap.PSObject.Properties.Name -contains 'retiredSkills') {
    @($cap.retiredSkills)
  } else {
    @()
  }
  $invalidRetiredSkillContracts = @($retiredSkillContracts | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.name) -or
    [string]$_.contentHash -notmatch '^[A-Fa-f0-9]{64}$'
  })
  if ($invalidRetiredSkillContracts.Count) {
    throw "Capability $($cap.id) has an invalid retired skill signature contract."
  }
  foreach ($targetEntry in $skillTargets.GetEnumerator()) {
    $target = [string]$targetEntry.Value
    $mapping = @($cap.hostMappings | Where-Object { $_.hostId -eq $targetEntry.Key })
    if ($mapping.Count -gt 1) { throw "Capability $($cap.id) has duplicate mapping entries for host $($targetEntry.Key)." }
    $deploymentStatus = if ($mapping.Count -eq 1) { [string]$mapping[0].deploymentStatus } else { '' }
    $deployLooseSkills = $deploymentStatus -in @(
      'managed',
      'managed-loose-skill',
      'managed-loose-skills',
      'managed-native-skills-and-mcp',
      'managed-loose-skills-and-mcp',
      'managed-loose-skills-native-browser-plus-mcp',
      'preprovisioned-loose-skills'
    )
    $skipManagedDeployment = $deploymentStatus -match 'native|offline|observed'
    if ($mapping.Count -eq 1 -and -not $deployLooseSkills -and -not $skipManagedDeployment) {
      throw "Capability $($cap.id) has unsupported deployment status '$deploymentStatus' for host $($targetEntry.Key)."
    }

    foreach ($skill in $sourceSkillDirectories | Where-Object Name -in $managedSkillNames) {
      $destination = Join-Path $target $skill.Name
      if ($deployLooseSkills) {
        if (Test-ExpectedSkillJunction -Path $destination -Source $skill.FullName) {
          continue
        }
        Install-ManagedSkill $targetEntry.Key $target $skill.Name $sourceSkills $cap.id
      } elseif (
          (Test-Path -LiteralPath $destination -PathType Container) -and
          -not (Test-ExpectedSkillJunction -Path $destination -Source $skill.FullName) -and
          (Test-DirectoryEquivalent $skill.FullName $destination)
      ) {
        Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $destination `
          -HostId $targetEntry.Key -ArtifactKind 'skills' `
          -ArtifactName $skill.Name `
          -Reason "Removed an exact canonical $($cap.id) duplicate from a host without a loose-skill ownership mapping." `
          -ContentHash (Get-ManagedQuarantineContentHash -Path $destination) |
          Out-Null
      }
    }

    foreach ($retiredName in $retiredSkillNames) {
      $retiredSource = Join-Path $sourceSkills $retiredName
      $destination = Join-Path $target $retiredName
      if (!(Test-Path -LiteralPath $destination -PathType Container)) { continue }
      if ((Test-Path -LiteralPath $retiredSource -PathType Container) -and (Test-DirectoryEquivalent $retiredSource $destination)) {
        Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $destination `
          -HostId $targetEntry.Key -ArtifactKind 'skills' `
          -ArtifactName $retiredName `
          -Reason "Removed an exact canonical $($cap.id) skill name retired by the capability contract." `
          -ContentHash (Get-ManagedQuarantineContentHash -Path $destination) |
          Out-Null
      } else {
        Write-Warning "Preserving non-canonical or ambiguous retired skill path: $destination"
      }
    }

    foreach ($retiredSkill in $retiredSkillContracts) {
      $retiredName = [string]$retiredSkill.name
      $destination = Join-Path $target $retiredName
      if (!(Test-Path -LiteralPath $destination -PathType Container)) { continue }
      $entries = @(Get-ChildItem -LiteralPath $destination -Recurse -Force)
      $skillFile = Join-Path $destination 'SKILL.md'
      $isExactRetiredSkill = $entries.Count -eq 1 -and
        (Test-Path -LiteralPath $skillFile -PathType Leaf) -and
        (Get-FileHash -LiteralPath $skillFile -Algorithm SHA256).Hash -ceq
          ([string]$retiredSkill.contentHash).ToUpperInvariant()
      if ($isExactRetiredSkill) {
        $reason = if ([string]::IsNullOrWhiteSpace([string]$retiredSkill.reason)) {
          "Removed an exact retired $($cap.id) skill generation."
        } else {
          [string]$retiredSkill.reason
        }
        Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $destination `
          -HostId $targetEntry.Key -ArtifactKind 'skills' `
          -ArtifactName $retiredName -Reason $reason `
          -ContentHash (Get-ManagedQuarantineContentHash -Path $destination) |
          Out-Null
      } else {
        Write-Warning "Preserving non-canonical or ambiguous retired skill path: $destination"
      }
    }
  }
}

# ~/.agents/skills is discovered alongside host-native skill directories by
# several coding agents. It is not an AgentHub deployment target, so retaining
# an AgentHub-managed name there creates a second owner, can override a current
# host-native copy, and can expose a capability to hosts that are not mapped to
# it. Preserve only those managed-name shadows in quarantine after every mapped
# host deployment has completed successfully. Unregistered user skills remain
# untouched.
$sharedAgentSkillsRoot = Join-Path $UserProfile '.agents\skills'
$sharedManagedSkillOwners = @{}
$sharedRetiredSkillContracts = @{}
foreach ($cap in @($caps.capabilities)) {
  $sourceSkills = Join-Path (
    Resolve-RegistryOwnedPath ([string]$cap.canonicalSource)
  ) 'skills'
  if (!(Test-Path -LiteralPath $sourceSkills -PathType Container)) { continue }
  $sourceSkillDirectories = @(Get-ChildItem -LiteralPath $sourceSkills -Directory)
  $managedSkillNames = if ($cap.PSObject.Properties.Name -contains 'managedSkillNames') {
    @($cap.managedSkillNames | ForEach-Object { [string]$_ })
  } else {
    @($sourceSkillDirectories | ForEach-Object Name)
  }
  foreach ($skillName in $managedSkillNames) {
    if ($sharedManagedSkillOwners.ContainsKey($skillName) -and
        $sharedManagedSkillOwners[$skillName].capabilityId -ne [string]$cap.id) {
      throw "Managed skill $skillName has multiple capability owners: $($sharedManagedSkillOwners[$skillName].capabilityId), $($cap.id)."
    }
    $legacyHashes = @()
    if ($cap.PSObject.Properties.Name -contains 'legacySkillTreeHashes') {
      $legacyProperty = $cap.legacySkillTreeHashes.PSObject.Properties[$skillName]
      if ($null -ne $legacyProperty) {
        $legacyHashes = @($legacyProperty.Value | ForEach-Object {
          ([string]$_).ToUpperInvariant()
        })
      }
    }
    $sharedManagedSkillOwners[$skillName] = [pscustomobject]@{
      capabilityId = [string]$cap.id
      trustedTreeHashes = @(
        Get-AgentHubRegistryHashBasisValue -Path (
          Join-Path $sourceSkills $skillName
        )
      ) + $legacyHashes
    }
  }
  if ($cap.PSObject.Properties.Name -contains 'retiredSkills') {
    foreach ($retiredSkill in @($cap.retiredSkills)) {
      $retiredName = [string]$retiredSkill.name
      if ([string]::IsNullOrWhiteSpace($retiredName)) { continue }
      if ($sharedRetiredSkillContracts.ContainsKey($retiredName)) {
        throw "Retired skill $retiredName has multiple capability retirement contracts."
      }
      $sharedRetiredSkillContracts[$retiredName] = [pscustomobject]@{
        capabilityId = [string]$cap.id
        contentHash = ([string]$retiredSkill.contentHash).ToUpperInvariant()
        reason = [string]$retiredSkill.reason
      }
    }
  }
}
foreach ($skillName in @($sharedManagedSkillOwners.Keys | Sort-Object)) {
  $sharedPath = Join-Path $sharedAgentSkillsRoot $skillName
  if (!(Test-Path -LiteralPath $sharedPath -PathType Container)) { continue }
  $owner = $sharedManagedSkillOwners[$skillName]
  $ownerId = [string]$owner.capabilityId
  $sharedHash = Get-AgentHubRegistryHashBasisValue -Path $sharedPath
  if ($sharedHash -notin @($owner.trustedTreeHashes)) {
    Write-Warning "Preserving divergent shared skill content outside the trusted $ownerId generations: $sharedPath"
    continue
  }
  Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $sharedPath `
    -HostId 'shared-agent-skills' -ArtifactKind 'skills' `
    -ArtifactName $skillName `
    -Reason "Removed a shared Agent Skills shadow of the canonical $ownerId capability." `
    -ContentHash (Get-ManagedQuarantineContentHash -Path $sharedPath) |
    Out-Null
}
foreach ($skillName in @($sharedRetiredSkillContracts.Keys | Sort-Object)) {
  $sharedPath = Join-Path $sharedAgentSkillsRoot $skillName
  if (!(Test-Path -LiteralPath $sharedPath -PathType Container)) { continue }
  $contract = $sharedRetiredSkillContracts[$skillName]
  $entries = @(Get-ChildItem -LiteralPath $sharedPath -Recurse -Force)
  $skillFile = Join-Path $sharedPath 'SKILL.md'
  $isExactRetiredSkill = $entries.Count -eq 1 -and
    (Test-Path -LiteralPath $skillFile -PathType Leaf) -and
    (Get-FileHash -LiteralPath $skillFile -Algorithm SHA256).Hash -ceq
      $contract.contentHash
  if (-not $isExactRetiredSkill) {
    Write-Warning "Preserving non-canonical or ambiguous shared retired skill path: $sharedPath"
    continue
  }
  $reason = if ([string]::IsNullOrWhiteSpace($contract.reason)) {
    "Removed an exact retired $($contract.capabilityId) skill generation."
  } else {
    $contract.reason
  }
  Move-ToAgentHubQuarantine -Batch $quarantineBatch -Path $sharedPath `
    -HostId 'shared-agent-skills' -ArtifactKind 'skills' `
    -ArtifactName $skillName -Reason $reason `
    -ContentHash (Get-ManagedQuarantineContentHash -Path $sharedPath) |
    Out-Null
}

if ($SkillDistributionOnly) {
  Write-AgentHubQuarantineManifest -Batch $quarantineBatch | Out-Null
  Write-Host 'Canonical managed capabilities distributed; host configuration and MCP synchronization were not changed.' -ForegroundColor Green
  return
}

function Convert-Placeholder([object]$Value, [ValidateSet('generic','claude','qwen','opencode','gemini','windsurf')]$TargetHost) {
  if ($Value -isnot [string]) { return $Value }
  switch ($TargetHost) {
    'claude'   { return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) '${' + $m.Groups[1].Value + '}' }) }
    'qwen'     { return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) '${' + $m.Groups[1].Value + '}' }) }
    'opencode' { return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) '{env:' + $m.Groups[1].Value + '}' }) }
    'gemini'   { return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', { param($m) '$' + $m.Groups[1].Value }) }
    default    { return $Value }
  }
}

function Get-McpMap([ValidateSet('generic','claude','qwen','opencode','gemini','windsurf')]$TargetHost) {
  $out = @{}
  foreach ($mcp in $mcps.mcpServers) {
    if ($mcp.scope -ne 'global-default') { continue }
    $entry = @{}
    if ($mcp.transport -eq 'http') {
      if ($TargetHost -eq 'windsurf') { $entry.serverUrl = $mcp.url }
      else { $entry.type = 'http'; $entry.url = $mcp.url }
      if ($mcp.headers) {
        $headers = @{}
        foreach ($p in $mcp.headers.PSObject.Properties) { $headers[$p.Name] = Convert-Placeholder $p.Value $TargetHost }
        $entry.headers = $headers
      }
    } else {
      if ($TargetHost -ne 'windsurf') { $entry.type = 'stdio' }
      $entry.command = $mcp.command
      $entry.args = @($mcp.args)
      $envValues = @{}
      if ($mcp.env) { foreach ($p in $mcp.env.PSObject.Properties) { $envValues[$p.Name] = Convert-Placeholder $p.Value $TargetHost } }
      $entry.env = $envValues
    }
    if ($TargetHost -eq 'gemini') { $entry.trust = $true }
    $out[$mcp.id] = $entry
  }
  return $out
}

function Set-McpProperty([string]$Path, [string]$Property, [string]$TargetHost) {
  $root = Read-JsonHash $Path
  $root[$Property] = Get-McpMap $TargetHost
  Save-JsonHash $Path $root
}

# MCPs are rendered only by Sync-AgentHub.ps1. It owns each host's
# native format, documented Devin roaming user-config path, aliases, and
# secret references. Keeping a second writer here caused endpoint drift.

$gemini = Read-JsonHash "$UserProfile\.gemini\settings.json"
$gemini['autoAccept'] = $true
$gemini['sandbox'] = $false
$gemini['contextFileName'] = @('AGENTS.md', 'GEMINI.md')
# Gemini intentionally rejects persistent YOLO in settings. The generated
# gemini.cmd launcher supplies --yolo; auto_edit is the strongest valid stored
# fallback for sessions launched outside that wrapper.
$gemini['general'] = @{ defaultApprovalMode = 'auto_edit' }
Save-JsonHash "$UserProfile\.gemini\settings.json" $gemini

$claude = Read-JsonHash "$UserProfile\.claude\settings.json"
$claude['permissions'] = @{ defaultMode='bypassPermissions'; deny=@(); additionalDirectories=@('C:\') }
$claude['skipDangerousModePermissionPrompt'] = $true
$claude['cleanupPeriodDays'] = 7
if ($claude.ContainsKey('env') -and $claude['env'] -is [hashtable]) {
  $claude['env'].Remove('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS')
}
if ($claude.ContainsKey('hooks')) { $claude['hooks'].Remove('PreToolUse') }
Save-JsonHash "$UserProfile\.claude\settings.json" $claude

$qwenPath = "$UserProfile\.qwen\settings.json"
$qwen = Read-JsonHash $qwenPath
$qwen['tools'] = @{ approvalMode='yolo' }
$qwen['permissions'] = @{ allow=@('*') }
$qwen['mcp'] = @{ allowed=@((Get-McpMap 'qwen').Keys | Sort-Object) }
if (-not $qwen.ContainsKey('memory') -or -not ($qwen['memory'] -is [hashtable])) { $qwen['memory'] = @{} }
# Qwen's managed memory is host-local Markdown.  It keeps useful repository
# context across sessions without centralizing project data in this registry.
$qwen['memory']['enableManagedAutoMemory'] = $true
$qwen['memory']['enableManagedAutoDream'] = $true

# qwen3.8-max-preview is thinking-mandatory on Token Plan.  Qwen Code's
# side-query path (including /compress) normally asks to disable thinking;
# without this model flag it sends enable_thinking=false and the API rejects
# the request.  Keep this in the fleet profile so a future profile apply does
# not silently regress the fix.
$qwenRequiredGeneration = To-Hash $profile.hostSettings.'qwen-code'.requiredModelGeneration
if ($qwenRequiredGeneration -and $qwen.ContainsKey('modelProviders')) {
  foreach ($providerName in @($qwen['modelProviders'].Keys)) {
    $models = @($qwen['modelProviders'][$providerName])
    for ($index = 0; $index -lt $models.Count; $index++) {
      $model = To-Hash $models[$index]
      if (-not ($model -is [hashtable]) -or -not $model.ContainsKey('id')) { continue }
      $required = $qwenRequiredGeneration[$model['id']]
      if (-not $required) { continue }
      $required = To-Hash $required
      if (-not $model.ContainsKey('generationConfig') -or -not ($model['generationConfig'] -is [hashtable])) {
        $model['generationConfig'] = @{}
      }
      foreach ($setting in $required.GetEnumerator()) {
        if ($setting.Key -eq 'extra_body') {
          if (-not $model['generationConfig'].ContainsKey('extra_body') -or -not ($model['generationConfig']['extra_body'] -is [hashtable])) {
            $model['generationConfig']['extra_body'] = @{}
          }
          foreach ($extra in (To-Hash $setting.Value).GetEnumerator()) {
            $model['generationConfig']['extra_body'][$extra.Key] = $extra.Value
          }
        } else {
          $model['generationConfig'][$setting.Key] = $setting.Value
        }
      }
      $models[$index] = $model
    }
    $qwen['modelProviders'][$providerName] = $models
  }
}
Save-JsonHash $qwenPath $qwen
Sync-QwenSubagents -SourceRoot (Join-Path $RegistryRoot 'adapters\qwen-code\agents') -DestinationRoot "$UserProfile\.qwen\agents"
Sync-QoderSubagents -SourceRoot (Join-Path $RegistryRoot 'adapters\qoder\agents') -DestinationRoot "$UserProfile\.qoder\agents"
Sync-QwenPortfolioLsp -RegistryRoot $RegistryRoot

$openCodePath = "$UserProfile\.config\opencode\opencode.json"
$openCode = Read-JsonHash $openCodePath
$openCode['permission'] = 'allow'
$openCode['mcp'] = Get-McpMap 'opencode'
Save-JsonHash $openCodePath $openCode

$copilotPath = "$UserProfile\.copilot\settings.json"
$copilot = Read-JsonHash $copilotPath
$copilot['stayInAutopilot'] = $true
$copilot['askUser'] = $false
Save-JsonHash $copilotPath $copilot

# Grok documents both an always-approve permission mode and a native YOLO
# switch. Keep both aligned without rewriting unrelated TOML settings.
Set-TomlBoolean -Path "$UserProfile\.grok\config.toml" -Section 'ui' -Key 'yolo' -Value $true

$cursorPath = "$UserProfile\.cursor\cli-config.json"
$cursor = Read-JsonHash $cursorPath
if (Test-CursorDispatchEnabled $profile) {
  $cursor['approvalMode'] = 'unrestricted'
  $cursor['permissions'] = @{ allow=@('Shell(*)','Read(**)','Write(**)'); deny=@() }
  $cursor['sandbox'] = @{ mode='disabled'; networkAccess='full' }
  $cursor['autoAcceptWebSearch'] = $true
} else {
  $cursor['approvalMode'] = 'allowlist'
  $cursor['permissions'] = @{ allow=@('Read(**)'); deny=@('Shell(*)','Write(**)') }
  $cursor['sandbox'] = @{ mode='enabled'; networkAccess='restricted' }
  $cursor['autoAcceptWebSearch'] = $false
  [Environment]::SetEnvironmentVariable('CURSOR_API_KEY', $null, 'User')
  [Environment]::SetEnvironmentVariable('CURSOR_ADMIN_API_KEY', $null, 'User')
  $cursorHoldRulePath = "$UserProfile\.cursor\rules\00-provider-hold.mdc"
  New-Item -ItemType Directory -Path (Split-Path -Parent $cursorHoldRulePath) -Force | Out-Null
  Set-Content -LiteralPath $cursorHoldRulePath -Value (Get-CursorProviderHoldRuleContent) -Encoding UTF8 -NoNewline
}
Save-JsonHash $cursorPath $cursor

$factorySettingsPath = "$UserProfile\.factory\settings.json"
$factorySettings = Read-JsonHash $factorySettingsPath
$factorySettings['interactionMode'] = 'auto'
$factorySettings['autonomyLevel'] = 'high'
$factorySettings['autonomyMode'] = 'auto-high'
Save-JsonHash $factorySettingsPath $factorySettings

$antigravityPath = "$UserProfile\.gemini\antigravity-cli\settings.json"
$antigravity = Read-JsonHash $antigravityPath
$antigravity['agentMode'] = 'accept-edits'
$antigravity['allowNonWorkspaceAccess'] = $true
$antigravity['artifactReviewPolicy'] = 'always-proceed'
$antigravity['toolPermission'] = 'always-proceed'
$antigravity['permissions'] = @{ allow=@('read_file(*)','write_file(*)','read_url(*)','execute_url(*)','command(*)','unsandboxed(*)','mcp(*)') }
Save-JsonHash $antigravityPath $antigravity

$commanderPath = "$UserProfile\.claude-server-commander\config.json"
if (Test-Path -LiteralPath $commanderPath) {
  $commander = Read-JsonHash $commanderPath
  $commander['blockedCommands'] = @()
  $commander['allowedDirectories'] = @('C:\')
  Save-JsonHash $commanderPath $commander
}

# Official environment-backed unattended defaults for hosts whose permission
# control is command-line based. New terminals inherit these values.
# Record prior presence (not values) for rollback before overwriting.
$agentTempRoot = Assert-AgentHubSafeWritePath `
  -Path (Join-Path $localAppDataRoot 'AgentHub\tmp') `
  -Purpose 'the shared coding-agent temporary directory'
New-Item -ItemType Directory -Path $agentTempRoot -Force | Out-Null
$envVarRollback = @{}
$envVarsToSet = @(
  @{ name='DEVIN_PERMISSION_MODE'; value='dangerous' }
  @{ name='COPILOT_ALLOW_ALL'; value='1' }
  @{ name='GEMINI_CLI_TRUST_WORKSPACE'; value='true' }
  @{ name='QWEN_CODE_SUPPRESS_YOLO_WARNING'; value='1' }
  # Codex Desktop's code-mode host honors the POSIX TMPDIR convention. Without
  # it, its /tmp/sessions path materializes as C:\tmp on Windows.
  @{ name='TMPDIR'; value=$agentTempRoot }
)
foreach ($ev in $envVarsToSet) {
  $priorValue = [Environment]::GetEnvironmentVariable($ev.name, 'User')
  $envVarRollback[$ev.name] = @{ wasPresent = (-not [string]::IsNullOrEmpty($priorValue)) }
  [Environment]::SetEnvironmentVariable($ev.name, $ev.value, 'User')
}
# Write the env-var rollback manifest alongside the quarantine manifest.
$envRollbackPath = Join-Path $quarantineBatchRoot 'env-var-rollback.json'
if ($envVarRollback.Count -gt 0) {
  New-Item -ItemType Directory -Path $quarantineBatchRoot -Force | Out-Null
  @{ schemaVersion=1; createdAtUtc=(Get-Date).ToUniversalTime().ToString('o'); variables=$envVarRollback } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $envRollbackPath -Encoding UTF8
}

# Amp's current CLI serializes a one-rule configuration as an object, although
# its runtime schema requires an array. Write the documented array shape here.
$ampPath = "$UserProfile\.config\amp\settings.json"
$amp = Read-JsonHash $ampPath
$amp['amp.permissions'] = @(@{ action='allow'; tool='*' })
Save-JsonHash $ampPath $amp

# Ensure the five CLIs that only expose full autonomy as launch flags have
# predictable full-access launchers. The user bin directory is placed first in
# the user PATH, so normal command names use these launchers in new terminals.
$bin = "$UserProfile\bin"
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$wrappers = @{
  'gemini.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\gemini.cmd" --yolo --skip-trust %*'
  'qwen.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\qwen.cmd" --yolo --experimental-lsp %*'
  'copilot.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\copilot.cmd" ' + $copilotPluginArgs + ' --allow-all --autopilot --no-ask-user --allow-all-mcp-server-instructions %*'
  'devin.cmd' = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\devin\cli\bin\devin.exe" --permission-mode dangerous --respect-workspace-trust false %*'
  'agy.cmd' = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\agy\bin\agy.exe" --dangerously-skip-permissions %*'
  'cline.cmd' = '@echo off' + "`r`n" + 'set "_cline_admin="' + "`r`n" + 'for %%A in (auth config plugin skill connect mcp doctor history hook schedule hub dashboard update kanban) do if /I "%~1"=="%%A" set "_cline_admin=1"' + "`r`n" + 'if defined _cline_admin ("%APPDATA%\npm\cline.cmd" %*) else ("%APPDATA%\npm\cline.cmd" --auto-approve true %*)'
  'cline-acp.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\cline.cmd" --acp --auto-approve true %*'
  'qodercli.cmd' = '@echo off' + "`r`n" + 'set "_qoder_admin="' + "`r`n" + 'for %%A in (login mcp plugins plugin skills skill hooks hook agents agent update status feedback rollback) do if /I "%~1"=="%%A" set "_qoder_admin=1"' + "`r`n" + 'if defined _qoder_admin ("%USERPROFILE%\.qoder\bin\qodercli\qodercli.exe" %*) else ("%USERPROFILE%\.qoder\bin\qodercli\qodercli.exe" --dangerously-skip-permissions --tools default %*)'
  'qoder-acp.cmd' = '@echo off' + "`r`n" + '"%USERPROFILE%\.qoder\bin\qodercli\qodercli.exe" --acp --dangerously-skip-permissions --tools default %*'
  'opencode-acp.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\opencode.cmd" acp %*'
  'gemini-acp.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\gemini.cmd" --acp --yolo --skip-trust %*'
  'copilot-acp.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\copilot.cmd" ' + $copilotPluginArgs + ' --acp --allow-all --autopilot --no-ask-user --allow-all-mcp-server-instructions %*'
  'hermes-acp.cmd' = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe" acp --accept-hooks %*'
  'cursor-agent.cmd' = Get-CursorLauncherContent -FleetProfile $profile -Surface agent -Shell cmd
  'cursor-agent' = Get-CursorLauncherContent -FleetProfile $profile -Surface agent -Shell posix
  'cursor.cmd' = Get-CursorLauncherContent -FleetProfile $profile -Surface ide -Shell cmd
  'cursor' = Get-CursorLauncherContent -FleetProfile $profile -Surface ide -Shell posix
}
foreach ($pair in $wrappers.GetEnumerator()) { Set-Content -LiteralPath (Join-Path $bin $pair.Key) -Value $pair.Value -Encoding ASCII -NoNewline }
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ((@($userPath -split ';') | Where-Object { $_.TrimEnd('\\') -ieq $bin.TrimEnd('\\') }).Count -eq 0) { $userPath = "$bin;$userPath" }
elseif (-not $userPath.StartsWith($bin, [System.StringComparison]::OrdinalIgnoreCase)) { $userPath = "$bin;" + (($userPath -split ';' | Where-Object { $_.TrimEnd('\\') -ine $bin.TrimEnd('\\') }) -join ';') }
[Environment]::SetEnvironmentVariable('Path', $userPath, 'User')

# Let the existing host-aware synchronizer render Codex and Qwen's native
# formats and Qwen extension adapters from this same registry.
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Sync-AgentHub.ps1') -Apply -Validate -IncludeInactiveAgents -ScopeProfile global-default -RegistryRoot $RegistryRoot -UserProfile $UserProfile
Retire-QoderNativePluginLooseSkills
Write-AgentHubQuarantineManifest -Batch $quarantineBatch | Out-Null

Write-Host 'Full-access agent profile applied. Restart open agent sessions and open a new terminal for launcher PATH changes.' -ForegroundColor Green
