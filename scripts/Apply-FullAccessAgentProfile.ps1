#Requires -Version 5.1
<#
.SYNOPSIS
  Applies the user-authorized full-access profile to installed coding hosts.

.DESCRIPTION
  C:\Repos\agent-capabilities remains the source of truth for MCP definitions
  and reusable skills. This script writes no credential values: MCP processes
  receive environment-variable references only. It deliberately does not
  attempt to bypass OAuth or provider-owned sign-in pages.
#>
[CmdletBinding()]
param(
  [string]$RegistryRoot = 'C:\Repos\agent-capabilities',
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$SkillDistributionOnly,
  [switch]$RetireLegacyVideoOwners
)

$ErrorActionPreference = 'Stop'
$mcps = Get-Content (Join-Path $RegistryRoot 'registry\mcps.json') -Raw | ConvertFrom-Json
$caps = Get-Content (Join-Path $RegistryRoot 'registry\capabilities.json') -Raw | ConvertFrom-Json
$profile = Get-Content (Join-Path $RegistryRoot 'registry\fleet-profile.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'AgentCtl.CursorReadiness.ps1')

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

function Get-DirectoryInventory([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Container)) { return @() }
  $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
  return @(
    Get-ChildItem -LiteralPath $root -Recurse -Force |
      Sort-Object FullName |
      ForEach-Object {
        $relativePath = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        # Claude writes per-process .in_use sentinels inside a live plugin
        # cache. They are runtime state, not package content, and must not
        # make an otherwise current native plugin appear stale.
        if ($relativePath -eq '.in_use' -or $relativePath.StartsWith('.in_use/')) { return }
        if ($_.PSIsContainer) { 'D|{0}' -f $relativePath }
        else { 'F|{0}|{1}' -f $relativePath, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
      }
  )
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
  return ((Get-DirectoryInventory $Left) -join "`n") -ceq ((Get-DirectoryInventory $Right) -join "`n")
}

function Copy-DirectoryToStage([string]$Source, [string]$Stage) {
  New-Item -ItemType Directory -Path $Stage -Force | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Stage -Recurse -Force
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
  'devin' = "$env:APPDATA\devin\skills"
  'amp' = "$UserProfile\.config\amp\skills"
  'windsurf' = "$UserProfile\.codeium\windsurf\skills"
  'gemini' = "$UserProfile\.gemini\skills"
  'hermes' = "$UserProfile\AppData\Local\hermes\skills"
  'grok' = "$UserProfile\.grok\skills"
  'antigravity' = "$UserProfile\.gemini\config\skills"
  'warp' = "$UserProfile\.warp\skills"
  'copilot' = "$UserProfile\.copilot\skills"
}

$nativeOnlyVideoHosts = @('vscode-insiders')
$unknownSkillHosts = @($profile.managedHosts | Where-Object { -not $skillTargets.Contains($_) -and $_ -notin $nativeOnlyVideoHosts } | Sort-Object -Unique)
if ($unknownSkillHosts.Count) {
  throw "Managed host(s) have no reviewed skill target: $($unknownSkillHosts -join ', '). Update the allowlist before applying the profile."
}

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
$videoPluginRoot = [string]$videoCapability[0].canonicalSource
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
$experiencePluginRoot = [string]$experienceCapability[0].canonicalSource
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

$quarantineBatchId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$quarantineBatchRoot = Join-Path $UserProfile ".agent-capabilities\quarantine\$quarantineBatchId"
$quarantineEntries = New-Object System.Collections.ArrayList

function Save-QuarantineManifest {
  if ($quarantineEntries.Count -eq 0) { return }
  New-Item -ItemType Directory -Path $quarantineBatchRoot -Force | Out-Null
  $manifest = @{
    schemaVersion = 1
    createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    sourceRegistry = $RegistryRoot
    entries = @($quarantineEntries)
  }
  $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $quarantineBatchRoot 'manifest.json') -Encoding UTF8
}

function Move-ToManagedQuarantine([string]$Path, [string]$HostId, [string]$ArtifactKind, [string]$ArtifactName, [string]$Reason) {
  $quarantinePath = Join-Path $quarantineBatchRoot "$HostId\$ArtifactKind\$ArtifactName"
  New-Item -ItemType Directory -Path (Split-Path -Parent $quarantinePath) -Force | Out-Null
  Move-Item -LiteralPath $Path -Destination $quarantinePath
  [void]$quarantineEntries.Add(@{
    hostId = $HostId
    artifactKind = $ArtifactKind
    artifactName = $ArtifactName
    originalPath = $Path
    quarantinePath = $quarantinePath
    reason = $Reason
  })
  Save-QuarantineManifest
  return $quarantinePath
}

function Install-ManagedSkill([string]$HostId, [string]$TargetRoot, [string]$SkillName, [string]$SkillsSource, [string]$OwnerId) {
  $source = Join-Path $SkillsSource $SkillName
  $destination = Join-Path $TargetRoot $SkillName
  if (Test-DirectoryEquivalent $source $destination) { return }

  New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
  $stage = Join-Path $TargetRoot ('.agent-capabilities-stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $null
  try {
    Copy-DirectoryToStage $source $stage
    if (Test-Path -LiteralPath $destination -PathType Container) {
      $backup = Move-ToManagedQuarantine $destination $HostId 'skills' $SkillName "Replaced by the current canonical $OwnerId sibling."
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
  if ($HostId -eq 'claude') {
    $installedPath = Join-Path $UserProfile '.claude\plugins\installed_plugins.json'
    if (!(Test-Path -LiteralPath $installedPath -PathType Leaf)) { return @{ installed=$false; current=$false; path=$null } }
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
    if (-not $enabled) { return @{ installed=$false; current=$false; path=$null } }
    $path = Join-Path $UserProfile ".codex\plugins\cache\handoff\$CapabilityId\$PluginVersion"
    return @{ installed=$true; current=(Test-DirectoryEquivalent $PluginRoot $path); path=$path }
  }
  if ($HostId -eq 'copilot') {
    $wrapper = Join-Path $UserProfile 'bin\copilot.cmd'
    if (!(Test-Path -LiteralPath $wrapper -PathType Leaf)) { return @{ installed=$false; current=$false; path=$null } }
    $raw = Get-Content -LiteralPath $wrapper -Raw
    $current = $raw.Contains('--plugin-dir') -and $raw.Contains($PluginRoot)
    return @{ installed=$current; current=$current; path=$PluginRoot }
  }
  return @{ installed=$false; current=$false; path=$null }
}

function Ensure-LocalNativeAdapters {
  # Copilot CLI can load a local plugin directly. VS Code Insiders automatically
  # supports the same plugin format and exposes an official local-location map.
  $bin = Join-Path $UserProfile 'bin'
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  $copilotWrapper = Join-Path $bin 'copilot.cmd'
  $copilotPluginArgs = @($managedSkillCapabilities | ForEach-Object { '--plugin-dir "' + $_.pluginRoot + '"' }) -join ' '
  $copilotWrapperContent = '@echo off' + "`r`n" + '"%APPDATA%\npm\copilot.cmd" ' + $copilotPluginArgs + ' --allow-all --autopilot --no-ask-user --allow-all-mcp-server-instructions %*'
  if (!(Test-Path -LiteralPath $copilotWrapper) -or (Get-Content -LiteralPath $copilotWrapper -Raw) -cne $copilotWrapperContent) {
    Set-Content -LiteralPath $copilotWrapper -Value $copilotWrapperContent -Encoding ASCII -NoNewline
  }

  $vscodeSettingsPath = Join-Path $UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json'
  $vscodeSettings = Read-JsonHash $vscodeSettingsPath
  $locations = @{}
  if ($vscodeSettings.ContainsKey('chat.pluginLocations')) { $locations = To-Hash $vscodeSettings['chat.pluginLocations'] }
  $locationsChanged = $false
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

Ensure-LocalNativeAdapters
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
    $nativeState = $nativePluginStates["$($capability.id)::$hostId"]
    if ($nativeState -and $nativeState.current) {
      foreach ($skillName in $capability.skillNames) {
        $loosePath = Join-Path $targetRoot $skillName
        if (Test-Path -LiteralPath $loosePath -PathType Container) {
          Move-ToManagedQuarantine $loosePath $hostId 'skills' $skillName "Native $($capability.id) plugin v$($capability.version) is enabled; duplicate loose skill retired." | Out-Null
        }
      }
    } else {
      foreach ($skillName in $capability.skillNames) {
        Install-ManagedSkill $hostId $targetRoot $skillName $capability.skillsSource $capability.id
      }
    }
  }
}

# Qwen's native extensions are junctions to the canonical capabilities. Copying
# the same skills into ~/.qwen/skills would expose two owners in the same host.
# Validate the adapter instead and let Sync-AgentCapabilities maintain it.
if ('qwen-code' -in @($profile.managedHosts)) {
  foreach ($capability in $managedSkillCapabilities) {
    $extensionName = "agent-capabilities-$($capability.id)"
    $qwenExtensionRoot = Join-Path $UserProfile ".qwen\extensions\$extensionName"
    $qwenAdapterRoot = Join-Path $RegistryRoot "adapters\qwen-code\extensions\$extensionName"
    if (!(Test-Path -LiteralPath $qwenExtensionRoot -PathType Container) -and (Test-Path -LiteralPath $qwenAdapterRoot -PathType Container)) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $qwenExtensionRoot) -Force | Out-Null
      New-Item -ItemType Junction -Path $qwenExtensionRoot -Target $qwenAdapterRoot | Out-Null
    }
    $qwenExtensionSkills = Join-Path $qwenExtensionRoot 'skills'
    if (!(Test-DirectoryEquivalent $capability.skillsSource $qwenExtensionSkills)) {
      throw "Qwen $($capability.id) extension is missing or stale: $qwenExtensionSkills. Run Sync-AgentCapabilities before applying skill distribution."
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
        Move-ToManagedQuarantine $legacyPath $artifactRoot.hostId $artifactRoot.kind $retired.name $retired.reason | Out-Null
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
    default { return $false }
  }
}
if ($RetireLegacyVideoOwners) {
  foreach ($legacyOwner in $retiredLegacyOwners) {
    if (Test-Path -LiteralPath $legacyOwner.path -PathType Container) {
      if (Test-RetiredLegacySignature $legacyOwner) {
        Move-ToManagedQuarantine $legacyOwner.path $legacyOwner.hostId $legacyOwner.kind $legacyOwner.name $legacyOwner.reason | Out-Null
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
  $sourceSkills = Join-Path $cap.canonicalSource 'skills'
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
  foreach ($targetEntry in $skillTargets.GetEnumerator()) {
    $target = [string]$targetEntry.Value
    $mapping = @($cap.hostMappings | Where-Object { $_.hostId -eq $targetEntry.Key })
    if ($mapping.Count -gt 1) { throw "Capability $($cap.id) has duplicate mapping entries for host $($targetEntry.Key)." }
    $deploymentStatus = if ($mapping.Count -eq 1) { [string]$mapping[0].deploymentStatus } else { '' }
    $deployLooseSkills = $deploymentStatus -in @(
      'managed',
      'managed-loose-skills',
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
        if ($targetEntry.Key -eq 'gemini' -and (Test-Path -LiteralPath (Join-Path "$UserProfile\.agents\skills" $skill.Name) -PathType Container)) {
          continue
        }
        if (Test-ExpectedSkillJunction -Path $destination -Source $skill.FullName) {
          continue
        }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Get-ChildItem -LiteralPath $skill.FullName -Force | Copy-Item -Destination $destination -Recurse -Force
      } elseif (
          (Test-Path -LiteralPath $destination -PathType Container) -and
          -not (Test-ExpectedSkillJunction -Path $destination -Source $skill.FullName) -and
          (Test-DirectoryEquivalent $skill.FullName $destination)
      ) {
        Move-ToManagedQuarantine $destination $targetEntry.Key 'skills' $skill.Name "Removed an exact canonical $($cap.id) duplicate from a host without a loose-skill ownership mapping." | Out-Null
      }
    }

    foreach ($retiredName in $retiredSkillNames) {
      $retiredSource = Join-Path $sourceSkills $retiredName
      $destination = Join-Path $target $retiredName
      if (!(Test-Path -LiteralPath $destination -PathType Container)) { continue }
      if ((Test-Path -LiteralPath $retiredSource -PathType Container) -and (Test-DirectoryEquivalent $retiredSource $destination)) {
        Move-ToManagedQuarantine $destination $targetEntry.Key 'skills' $retiredName "Removed an exact canonical $($cap.id) skill name retired by the capability contract." | Out-Null
      } else {
        Write-Warning "Preserving non-canonical or ambiguous retired skill path: $destination"
      }
    }
  }
}

if ($SkillDistributionOnly) {
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

# MCPs are rendered only by Sync-AgentCapabilities.ps1. It owns each host's
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
[Environment]::SetEnvironmentVariable('DEVIN_PERMISSION_MODE', 'dangerous', 'User')
[Environment]::SetEnvironmentVariable('COPILOT_ALLOW_ALL', '1', 'User')
[Environment]::SetEnvironmentVariable('GEMINI_CLI_TRUST_WORKSPACE', 'true', 'User')
[Environment]::SetEnvironmentVariable('QWEN_CODE_SUPPRESS_YOLO_WARNING', '1', 'User')

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
  'copilot.cmd' = '@echo off' + "`r`n" + '"%APPDATA%\npm\copilot.cmd" ' + (@($managedSkillCapabilities | ForEach-Object { '--plugin-dir "' + $_.pluginRoot + '"' }) -join ' ') + ' --allow-all --autopilot --no-ask-user --allow-all-mcp-server-instructions %*'
  'devin.cmd' = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\devin\cli\bin\devin.exe" --permission-mode dangerous --respect-workspace-trust false %*'
  'agy.cmd' = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\agy\bin\agy.exe" --dangerously-skip-permissions %*'
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
& pwsh -NoProfile -File (Join-Path $RegistryRoot 'scripts\Sync-AgentCapabilities.ps1') -Apply -Validate -IncludeInactiveAgents -ScopeProfile global-default -RegistryRoot $RegistryRoot -UserProfile $UserProfile

Write-Host 'Full-access agent profile applied. Restart open agent sessions and open a new terminal for launcher PATH changes.' -ForegroundColor Green
