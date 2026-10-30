#Requires -Version 5.1
[CmdletBinding()]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$Prune,
  [switch]$AdoptExisting,
  [switch]$IncludeInactiveAgents,
  [switch]$QuietOverlayResolution,
  [string[]]$CapabilityId,
  [string]$RepositoryRoot,
  [string]$UserProfile
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
if (-not $Apply) { $Audit = $true }
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
# Dot-sourced for Get-AgentHubStableFileHash (see Get-TreeHash below).
# RegistryContentHash.ps1 defines functions only -- no top-level side effects
# -- which is why scripts/Validate-AgentHub.ps1 loads it the same way.
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
# Quotes unmanaged SKILL.md frontmatter that strict YAML parsers (Zed) reject.
# Functions only; the pass runs after deploy/prune so it never rewrites a
# destination this script is about to delete.
. (Join-Path $PSScriptRoot 'SkillFrontmatterYaml.ps1')
. (Join-Path $PSScriptRoot 'lib\HostCatalog.ps1')
. (Join-Path $PSScriptRoot 'lib\CapabilityGraph.ps1')

# -UserProfile has to actually move where this script writes, or it is a
# safety promise the script does not keep. Registry skillsDir values are
# absolute and baked against the real profile, so rebase both them and the
# runtime state directory whenever an override is supplied. A prior task in
# this effort shipped a live-fleet write on exactly this gap.
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
  $UserProfile = Get-AgentHubDefaultHome
}
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
  throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = Get-AgentHubNormalizedDirectory $UserProfile
$realProfile = Get-AgentHubNormalizedDirectory (Get-AgentHubDefaultHome)
$profileIsOverridden = $realProfile -and ($UserProfile -ne $realProfile)

function Resolve-UnderUserProfile([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
  return Resolve-AgentHubBoundPath -Declared $Path -Context $script:skillPathBinding
}

$requestedPlatform = Get-AgentHubRequestedPlatform -RepositoryRoot $root
$agentHubLocalData = Get-AgentHubIsolatedLocalData -TargetUserProfile $UserProfile -InvokingUserProfile $realProfile -LocalAppData (Get-AgentHubDefaultLocalData) -AlwaysIsolateOnOverride -Platform $requestedPlatform
$agentHubRuntimeRoot = Join-AgentHubPlatformPath -Platform (Get-AgentHubPlatformId $requestedPlatform) -Base $agentHubLocalData -Child 'AgentHub'
$runtimeRoot = Join-Path $agentHubRuntimeRoot 'sync'
$statePath = Join-Path $runtimeRoot 'managed-skills.json'
$capabilities = Get-Content (Join-Path $root 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agentsDocument = Get-Content (Join-Path $root 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Use-AgentHubPlatformPaths -AgentsDocument $agentsDocument -Platform $requestedPlatform | Out-Null
$script:skillPathBinding = New-AgentHubPathBindingContext -TargetUserProfile $UserProfile -InvokingUserProfile $realProfile -RegistryUserProfile (Get-AgentHubRecordedUserProfile $agentsDocument) -Platform $requestedPlatform
$overlayRoot = Get-AgentHubOverlayRoot -RepositoryRoot $root -ReportPrimaryCheckout:(-not $QuietOverlayResolution)
$capabilities.capabilities = @(Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $overlayRoot)

# Inactive hosts are retained as inventory, not as deployment targets, matching
# the -IncludeInactiveAgents switch Sync-AgentHub.ps1 already exposes for MCP so
# the fleet has one convention rather than two. The mappings stay in
# capabilities.json: this narrows what is deployed, not what is recorded.
#
# registry/agents.json currently declares NO inactive hosts, so this filter is
# inert. It did not start that way, and the history is the point. amp, devin,
# factory, vscode-insiders and windsurf were labelled inactive; wiring skill
# deployment to that label withheld 129 deployments and pruned 158 directories
# from hosts that were in fact in daily use. The label was stale, and it had
# been harmless right up until something depended on it.
#
# So: before making this filter matter again, confirm the label against reality
# rather than against the registry. A host being absent from disk, or a config
# directory looking untouched, is not evidence -- this repository has now
# recorded three separate globalSkillsDir errors built on exactly that
# inference.
#
# Narrowing the host set must not discard ownership before an explicit prune.
# A plain -Apply retains prior records so a later -Apply -Prune can still
# identify stale copies and protect any owner modifications.
$allAgents = @($agentsDocument.activeAgents) + @($agentsDocument.inactiveAgents)
$agents = if ($IncludeInactiveAgents) { $allAgents } else { @($agentsDocument.activeAgents) }
$agents = @($agents | Where-Object { Test-AgentHubHostSyncEnabled -Agent $_ })

# A registry that declares nothing is a wrong or empty tree, not a clean run.
if (@($capabilities.capabilities).Count -eq 0) {
  throw "Registry '$(Join-Path $root 'registry\capabilities.json')' declares zero capabilities. Refusing to report success against what looks like an empty or wrong registry tree."
}
if ($allAgents.Count -eq 0) {
  throw "Registry '$(Join-Path $root 'registry\agents.json')' declares zero agents. Refusing to report success against what looks like an empty or wrong registry tree."
}
# Every host being inactive is a configuration error, not a reason to deploy
# nothing quietly. Without this the run would reach the zero-rows guard and
# report a confusing 'empty work set' instead of naming the real cause.
if ($agents.Count -eq 0) {
  throw "Registry '$(Join-Path $root 'registry\agents.json')' declares no ACTIVE agents; every host is inactive. Refusing to deploy nothing quietly. Pass -IncludeInactiveAgents if that is genuinely intended."
}

# Skills are deployed by Copy-Item, verbatim, so the deployed bytes carry
# whatever line endings the deploying checkout had. Hashing those bytes raw
# made this script's verdict a function of git's core.autocrlf: one checkout
# reported current=370/drift=0 while a second checkout at the IDENTICAL commit
# reported current=6/drift=364, and a cross-checkout -Apply then rewrote every
# "drifted" destination, so the two checkouts ping-ponged the whole fleet's
# line endings between them.
#
# Get-AgentHubStableFileHash (scripts/RegistryContentHash.ps1) already solves
# exactly this for the registry content hash: it normalizes known text
# extensions to LF before hashing and passes everything else through byte-for-
# byte. Reusing it keeps one implementation of this rule rather than a third
# variant.
#
# The copy stays verbatim on purpose. This hash answers "is this the same
# content", which is the only question any caller below asks; it no longer
# implies "these are the same bytes". Normalizing on the WRITE path
# instead would mean classifying text-vs-binary for every file a skill ever
# ships -- a far larger blast radius than the defect -- and would not converge
# the already-deployed CRLF copies anyway, since a normalized hash reports
# them current.
function Get-TreeHash([string]$Path) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $lines = Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
      Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|dist|coverage)[\\/]' } |
      Sort-Object FullName |
      ForEach-Object {
        $relative = $_.FullName.Substring($Path.TrimEnd('\', '/').Length + 1).Replace('\','/')
        "${relative}:$(Get-AgentHubStableFileHash -Path $_.FullName)"
      }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
  } finally { $sha.Dispose() }
}

# The schemaVersion 1 hash format, kept solely to READ state files written
# before Get-TreeHash started normalizing. Every managed-skills.json already on
# disk holds digests in this format, and the two guards below compare a stored
# digest against a freshly computed one -- so reading an old file with the new
# function makes both guards fire on destinations nobody touched. Roughly half
# the files in a real deployment contain CRLF, which is how many would falsely
# refuse. This is self-retiring: the next -Apply rewrites the state at
# $StateSchemaVersion and nothing reaches this function again.
function Get-TreeHashLegacy([string]$Path) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $lines = Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
      Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|dist|coverage)[\\/]' } |
      Sort-Object FullName |
      ForEach-Object {
        $relative = $_.FullName.Substring($Path.TrimEnd('\', '/').Length + 1).Replace('\','/')
        "${relative}:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
      }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
  } finally { $sha.Dispose() }
}

# Bumped from 1 when Get-TreeHash switched to newline-normalized hashing. A
# state file with no schemaVersion at all reads as 0, which is treated as
# legacy -- the safe direction, since it preserves the guards rather than
# disarming them.
$StateSchemaVersion = 2
$priorSchemaVersion = 0
$prior = if (Test-Path -LiteralPath $statePath) {
  $stateDocument = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $priorSchemaVersion = [int]$stateDocument.schemaVersion
  $managed = @{}
  foreach ($property in @($stateDocument.managed.PSObject.Properties)) {
    $managed[$property.Name] = $property.Value
  }
  @{ managed = $managed }
} else { @{ managed = @{} } }
if (-not $prior.ContainsKey('managed')) { $prior.managed = @{} }
$priorHashesAreLegacy = $priorSchemaVersion -lt $StateSchemaVersion
function Test-LegacyManagedHash([string]$Destination) {
  $entry = $prior.managed[$Destination]
  if ($entry -and $entry.PSObject.Properties['hashSchemaVersion']) {
    return [int]$entry.hashSchemaVersion -lt $StateSchemaVersion
  }
  return $priorHashesAreLegacy
}
$desired = @{}
if ($CapabilityId) {
  foreach ($id in $CapabilityId) {
    if ($id -notin @($capabilities.capabilities.id)) { throw "Unknown capability: $id" }
  }
  if ($Prune) { throw 'Scoped capability sync cannot prune fleet state.' }
  if ($priorHashesAreLegacy) { throw 'Run a full sync to migrate the legacy ledger before scoped sync.' }
}
$retiredDestinations = @{}
# Destinations that came from a host's nativePaths.cliSkillsDir. Sync owns that
# directory (see the cliSkillsDir pass below) but never deploys into it, and it
# never removes a reparse point from it.
$cliRetiredDestinations = @{}
# Per host: names of the skills AgentHub ships and deploys to that host's shared
# library. Anything of the same name in the host's cliSkillsDir is a shadow copy.
$shippedByHost = @{}
$rows = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()
# Destinations a guard declined to touch this run, keyed by path. Parallel to
# $failures, which is prose for the operator; this is what the ledger write
# below reads to avoid recording ownership of anything it refused.
$refused = @{}

function Resolve-AgentHubRuntimeDestination([string]$RelativePath) {
  if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
    throw "Managed runtime path must be non-empty and relative to '$agentHubRuntimeRoot': '$RelativePath'"
  }
  $destination = [IO.Path]::GetFullPath((Join-Path $agentHubRuntimeRoot $RelativePath))
  $prefix = $agentHubRuntimeRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Managed runtime path escapes '$agentHubRuntimeRoot': '$RelativePath'"
  }
  return $destination
}

function Test-ReparsePoint([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return [bool]($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

# Resolve existing ancestor junctions only for I/O. Ledger keys stay logical.
function Resolve-PhysicalWritePath([string]$Path, [int]$Depth = 0) {
  if ($Depth -gt 64) { throw "Reparse-point cycle resolving '$Path'" }
  # [IO.Path] rather than Split-Path: on macOS and Linux, Split-Path -Parent '/var'
  # returns '' instead of '/', and macOS's temp root sits under the /var symlink.
  $full = [IO.Path]::GetFullPath($Path)
  $parent = [IO.Path]::GetDirectoryName($full)
  if (-not $parent -or $parent -eq $full) { return $full }
  $physicalParent = Resolve-PhysicalWritePath -Path $parent -Depth ($Depth + 1)
  $item = Get-Item -LiteralPath $physicalParent -Force -ErrorAction SilentlyContinue
  if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    $target = @($item.Target) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($target)) { throw "Cannot resolve reparse point '$physicalParent'" }
    if (-not [IO.Path]::IsPathRooted($target)) { $target = [IO.Path]::Combine([IO.Path]::GetDirectoryName($physicalParent), $target) }
    # Resolve the target itself too, including chained junctions.
    $sentinel = Resolve-PhysicalWritePath -Path (Join-Path $target '.agenthub-resolve') -Depth ($Depth + 1)
    $physicalParent = [IO.Path]::GetDirectoryName($sentinel)
  }
  return Join-Path $physicalParent ([IO.Path]::GetFileName($full))
}

function Register-ManagedTree {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$CapabilityId,
    [Parameter(Mandatory)][string]$ItemName,
    [Parameter(Mandatory)][string]$Mode,
    [Parameter(Mandatory)][ValidateSet('skill','runtime package')][string]$Kind,
    [string]$HostId = '<fleet>'
  )
  $sourceHash = Get-TreeHash $Source
  $desired[$Destination] = @{ capability=$CapabilityId; kind=$Kind; name=$ItemName; hash=$sourceHash }
  if ((Test-Path -LiteralPath $Destination) -and -not (Test-Path -LiteralPath $Destination -PathType Container)) {
    $failures.Add("refusing non-directory managed ${Kind}: $Destination")
    $refused[$Destination] = $true
    return
  }
  $currentHash = if (Test-Path -LiteralPath $Destination) { Get-TreeHash $Destination } else { $null }
  $status = if ($currentHash -eq $sourceHash) { 'current' } elseif ($currentHash) { 'drift' } else { 'missing' }
  $rows.Add([pscustomobject]@{ capability=$CapabilityId; host=$HostId; mode=$Mode; skill=$ItemName; status=$status })
  if (-not $Apply -or $status -eq 'current') { return }
  if ($currentHash -and -not $prior.managed.ContainsKey($Destination) -and -not $AdoptExisting) {
    $failures.Add("refusing to replace unowned ${Kind}: $Destination")
    $refused[$Destination] = $true
    return
  }
  $recordedComparableHash = if ($currentHash -and $prior.managed.ContainsKey($Destination) -and (Test-LegacyManagedHash $Destination)) {
    Get-TreeHashLegacy $Destination
  } else { $currentHash }
  if ($currentHash -and $prior.managed.ContainsKey($Destination) -and
      $prior.managed[$Destination].hash -ne $recordedComparableHash -and -not $AdoptExisting) {
    $failures.Add("refusing to replace user-modified managed ${Kind}: $Destination")
    $refused[$Destination] = $true
    return
  }
  $stage = $null
  $backup = $null
  $verified = $false
  try {
    $physicalDestination = Resolve-PhysicalWritePath $Destination
    $parent = Split-Path -Parent $physicalDestination
    $stage = Join-Path $parent ('.agenthub-stage-' + [guid]::NewGuid())
    $backup = Join-Path $parent ('.agenthub-backup-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $stage -Recurse
    if (-not (Test-Path -LiteralPath $stage -PathType Container) -or (Get-TreeHash $stage) -ne $sourceHash) {
      throw 'Staged copy failed directory/content verification'
    }
    if (Test-Path -LiteralPath $physicalDestination) { Move-Item -LiteralPath $physicalDestination -Destination $backup }
    Move-Item -LiteralPath $stage -Destination $physicalDestination
    if (-not (Test-Path -LiteralPath $physicalDestination -PathType Container) -or (Get-TreeHash $physicalDestination) -ne $sourceHash) {
      throw 'Deployed copy failed directory/content verification'
    }
    $verified = $true
  } catch {
    $failures.Add("failed to deploy ${Kind}: $Destination : $($_.Exception.Message)")
    $refused[$Destination] = $true
    if ($backup -and (Test-Path -LiteralPath $backup)) {
      try {
        if (Test-Path -LiteralPath $physicalDestination) { Remove-Item -LiteralPath $physicalDestination -Recurse -Force }
        Move-Item -LiteralPath $backup -Destination $physicalDestination
      } catch {
        $failures.Add("rollback failed for '$Destination'; preserved backup '$backup': $($_.Exception.Message)")
      }
    }
  } finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) {
      try { Remove-Item -LiteralPath $stage -Recurse -Force }
      catch { $failures.Add("staging cleanup failed for '$Destination': $($_.Exception.Message)") }
    }
  }
  # Cleanup cannot initiate rollback after a verified deployment: a partially
  # removed backup is no longer a safe source for restoring the old tree.
  if ($verified -and (Test-Path -LiteralPath $backup)) {
    try { Remove-Item -LiteralPath $backup -Recurse -Force }
    catch { $failures.Add("backup cleanup failed for '$Destination': $($_.Exception.Message)") }
  }
}

foreach ($capability in $capabilities.capabilities) {
  if ($CapabilityId -and $capability.id -notin $CapabilityId) { continue }
  # canonicalSource is repo-relative (packages/<id> or overlays/personal/packages/<id>).
  $sourceRoot = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $capability -OverlayRoot $overlayRoot
  $skillsRoot = Join-Path $sourceRoot 'skills'
  $skills = if (Test-Path -LiteralPath $skillsRoot) { @(Get-ChildItem -LiteralPath $skillsRoot -Directory) } else { @() }
  if ($capability.deployedCatalog) {
    $catalogDestination = Resolve-AgentHubRuntimeDestination ([string]$capability.deployedCatalog.runtimeRelativeRoot)
    Register-ManagedTree -Source $sourceRoot -Destination $catalogDestination -CapabilityId ([string]$capability.id) `
      -ItemName ([string]$capability.deployedCatalog.entrypoint) -Mode 'managed-runtime-package' -Kind 'runtime package'
    $authoritySource = [IO.Path]::GetFullPath((Join-Path $root ([string]$capability.deployedCatalog.authoritySource)))
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $authoritySource.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Deployed catalog authority source escapes repository root: '$($capability.deployedCatalog.authoritySource)'"
    }
    $authorityDestination = Resolve-AgentHubRuntimeDestination ([string]$capability.deployedCatalog.authorityRuntimeRelativeRoot)
    Register-ManagedTree -Source $authoritySource -Destination $authorityDestination -CapabilityId ([string]$capability.id) `
      -ItemName 'registry' -Mode 'managed-runtime-authority' -Kind 'runtime package'
  }
  foreach ($mapping in $capability.hostMappings) {
    $agent = $agents | Where-Object id -eq $mapping.hostId | Select-Object -First 1
    if (-not $agent) { continue }
    $mode = [string]$mapping.deploymentStatus
    if ($mode -match 'native.*plugin|plugin-installed') {
      $rows.Add([pscustomobject]@{ capability=$capability.id; host=$agent.id; mode='native-plugin'; status='host-managed' })
      continue
    }
    # A host that declares nativePaths.sharedSkillsDir wants ONE deployment
    # in that shared directory instead of a redundant copy in its own
    # skillsDir. The fleet master is ~/.agents/skills. Hosts that natively
    # read that path (codex, gemini, cursor, copilot, warp, amp, factory,
    # opencode, windsurf, vscode-insiders) deploy only there. Hosts that do
    # not (claude, cline, grok, qoder) still declare sharedSkillsDir
    # so AgentHub writes once; their skillsDir is a directory junction to
    # the master library. $desired stays keyed purely by the physical
    # destination path (not e.g. "$hostId::$destination"), so when two
    # hosts resolve to the identical shared destination they collapse to
    # the same dictionary entry instead of competing. A host with no
    # sharedSkillsDir declared is unaffected and still gets its own copy
    # in its own skillsDir -- the reachability rule.
    $sharedSkillsDirRaw = [string]$agent.nativePaths.sharedSkillsDir
    $usesSharedDir = -not [string]::IsNullOrWhiteSpace($sharedSkillsDirRaw)
    $skillsDir = if ($usesSharedDir) { Resolve-UnderUserProfile $sharedSkillsDirRaw } else { Resolve-UnderUserProfile ([string]$agent.nativePaths.skillsDir) }
    if ([string]::IsNullOrWhiteSpace($skillsDir)) { continue }
    # retiredSkillNames records the PREVIOUS name of a renamed or withdrawn
    # skill. The ledger-based prune below cannot reach these: a renamed skill
    # drops out of the ledger and becomes unowned, which is exactly the state
    # prune skips, so copies survive forever. Until 2026-08-20 nothing read
    # this field at all and use-chrome-devtools-mcp sat on 12 hosts pointing
    # at an MCP id that no longer existed. Collected before the empty-skills
    # guard so a capability whose skills were ALL renamed is still cleaned up.
    foreach ($retiredName in @($capability.retiredSkillNames)) {
      if ([string]::IsNullOrWhiteSpace($retiredName)) { continue }
      if ($skills.Name -contains $retiredName) { continue }  # still shipping; not retired in fact
      $retiredDestinations[(Join-Path $skillsDir $retiredName)] = $capability.id
    }
    if ($skills.Count -eq 0) { continue }
    if (-not $shippedByHost.ContainsKey([string]$agent.id)) {
      $shippedByHost[[string]$agent.id] = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    foreach ($skill in $skills) { [void]$shippedByHost[[string]$agent.id].Add($skill.Name) }
    $deployMode = if ($usesSharedDir) { 'shared-loose-skill' } else { 'loose-skill' }
    foreach ($skill in $skills) {
      $destination = Join-Path $skillsDir $skill.Name
      Register-ManagedTree -Source $skill.FullName -Destination $destination -CapabilityId ([string]$capability.id) `
        -ItemName $skill.Name -Mode $deployMode -Kind 'skill' -HostId $agent.id
    }
  }
}

# Fleet-level retirement. capability.retiredSkillNames is scoped to the hosts
# that capability maps to, which is correct for a rename inside a capability but
# cannot reach a skill deployed more widely than any current capability maps.
# repocontext is the worked example: it sat on 14 hosts, and its natural
# successor capability (repowise) maps to 8, so retiring it there would have
# left it on 9 while reporting success. retiredFleetSkills names a skill dead
# EVERYWHERE and is swept across every agent's skills directory regardless of
# capability mapping.
$shippedAnywhere = @{}
foreach ($capability in $capabilities.capabilities) {
  try {
    $pkgRoot = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $capability -OverlayRoot $overlayRoot
  } catch { continue }
  $r = Join-Path $pkgRoot 'skills'
  if (Test-Path -LiteralPath $r) {
    foreach ($s in @(Get-ChildItem -LiteralPath $r -Directory)) { $shippedAnywhere[$s.Name] = $capability.id }
  }
}
foreach ($retired in @($capabilities.retiredFleetSkills)) {
  $name = [string]$retired.name
  if ([string]::IsNullOrWhiteSpace($name)) { continue }
  # Same self-check as the capability-scoped path: a name some package still
  # ships is not retired in fact, whatever this list claims.
  if ($shippedAnywhere.ContainsKey($name)) {
    $failures.Add("retiredFleetSkills names '$name' but packages/$($shippedAnywhere[$name])/skills still ships it")
    continue
  }
  foreach ($agent in $agents) {
    foreach ($raw in @([string]$agent.nativePaths.skillsDir, [string]$agent.nativePaths.sharedSkillsDir, [string]$agent.nativePaths.cliSkillsDir)) {
      if ([string]::IsNullOrWhiteSpace($raw)) { continue }
      $dir = Resolve-UnderUserProfile $raw
      if ([string]::IsNullOrWhiteSpace($dir)) { continue }
      $retiredDestinations[(Join-Path $dir $name)] = "<fleet:$name>"
      if ($raw -eq [string]$agent.nativePaths.cliSkillsDir) { $cliRetiredDestinations[(Join-Path $dir $name)] = $true }
    }
  }
}

$retiredPruned = 0
if ($Apply -and $Prune) {
  foreach ($destination in @($retiredDestinations.Keys)) {
    if (-not (Test-Path -LiteralPath $destination)) { continue }
    if ($desired.ContainsKey($destination)) { continue }   # a live skill reclaimed the name
    if ($cliRetiredDestinations.ContainsKey($destination) -and (Test-ReparsePoint $destination)) { continue }
    Remove-Item -LiteralPath (Resolve-PhysicalWritePath $destination) -Recurse -Force
    $retiredPruned++
  }
}

# cliSkillsDir pass. A host that declares nativePaths.cliSkillsDir (today only
# antigravity) has a directory its CLI loads IN ADDITION to the shared library
# it already reads, so a skill copied there is loaded twice. Sync therefore owns
# that directory but deploys nothing into it:
#   - retired names are pruned (the retiredFleetSkills sweep above covers it);
#   - an entry named like a skill AgentHub ships to that host is a shadow copy:
#     removed with -Apply -Prune, reported as drift otherwise;
#   - any other entry (a third-party skill the owner installed) is reported as
#     unmanaged and never touched;
#   - a reparse point is never removed, whatever its name.
# On 2026-10-20 this directory held 29 stale unmanaged copies that nothing
# detected until the CLI loaded them beside the managed set.
# Skipped for a scoped (-CapabilityId) run: its shipped set is partial, so it
# would misclassify skills of the unselected capabilities.
$cliShadowPruned = 0
$cliDirs = @{}
foreach ($agent in $agents) {
  if ($CapabilityId) { break }
  $raw = [string]$agent.nativePaths.cliSkillsDir
  if ([string]::IsNullOrWhiteSpace($raw)) { continue }
  $dir = Resolve-UnderUserProfile $raw
  if ([string]::IsNullOrWhiteSpace($dir)) { continue }
  # If the CLI directory is the same place skills are deployed to, every
  # shipped skill in it is the managed copy, not a shadow of it.
  $sameAsDeploy = $false
  foreach ($other in @([string]$agent.nativePaths.skillsDir, [string]$agent.nativePaths.sharedSkillsDir)) {
    if ([string]::IsNullOrWhiteSpace($other)) { continue }
    $otherDir = Resolve-UnderUserProfile $other
    if ($otherDir -and $otherDir.TrimEnd('\','/') -ieq $dir.TrimEnd('\','/')) { $sameAsDeploy = $true }
  }
  if ($sameAsDeploy) { continue }
  $key = $dir.TrimEnd('\','/').ToLowerInvariant()
  if (-not $cliDirs.ContainsKey($key)) {
    $cliDirs[$key] = @{ path=$dir; host=[string]$agent.id; shipped=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
  }
  if ($shippedByHost.ContainsKey([string]$agent.id)) {
    foreach ($n in $shippedByHost[[string]$agent.id]) { [void]$cliDirs[$key].shipped.Add($n) }
  }
}
foreach ($entry in $cliDirs.Values) {
  if (-not (Test-Path -LiteralPath $entry.path -PathType Container)) { continue }
  foreach ($child in @(Get-ChildItem -LiteralPath $entry.path -Force)) {
    $name = $child.Name
    $path = $child.FullName
    $cliRow = { param($status) $rows.Add([pscustomobject]@{ capability='<cli-skills-dir>'; host=$entry.host; mode='cli-skills-dir'; skill=$name; status=$status }) }
    if ($desired.ContainsKey($path)) { continue }   # a managed destination is never a shadow of itself
    if (Test-ReparsePoint $path) {
      & $cliRow 'reparse-skipped'
      Write-Host "CLI-SKILLS-DIR reparse point left in place (never removed): $path"
    } elseif ($retiredDestinations.ContainsKey($path)) {
      # Only reachable here when the retired prune did not run (no -Apply -Prune).
      & $cliRow 'retired-present'
      Write-Host "CLI-SKILLS-DIR retired skill still present (drift; -Apply -Prune removes it): $path"
    } elseif ($entry.shipped.Contains($name)) {
      if ($Apply -and $Prune) {
        Remove-Item -LiteralPath (Resolve-PhysicalWritePath $path) -Recurse -Force
        $cliShadowPruned++
        & $cliRow 'shadow-pruned'
        Write-Host "CLI-SKILLS-DIR shadow copy removed: $path"
      } else {
        & $cliRow 'shadow-copy'
        Write-Host "CLI-SKILLS-DIR shadow copy of a shipped skill (drift; -Apply -Prune removes it): $path"
      }
    } else {
      & $cliRow 'unmanaged'
      Write-Host "CLI-SKILLS-DIR unmanaged entry not shipped by AgentHub (left in place): $path"
    }
  }
}

$pruned = 0
$yamlRepaired = 0
$yamlNeedsRepair = 0
if ($Apply -and $Prune) {
  foreach ($destination in @($prior.managed.Keys)) {
    if ($desired.ContainsKey($destination) -or -not (Test-Path -LiteralPath $destination)) { continue }
    # Same stored-format rule as the replace guard above.
    $currentHash = if (Test-LegacyManagedHash $destination) { Get-TreeHashLegacy $destination } else { Get-TreeHash $destination }
    if ($currentHash -ne $prior.managed[$destination].hash) {
      $failures.Add("refusing to prune modified managed skill: $destination")
      $refused[$destination] = $true
      continue
    }
    Remove-Item -LiteralPath (Resolve-PhysicalWritePath $destination) -Recurse -Force
    $pruned++
  }
}

# Unmanaged siblings in the shared skills library (Railway's use-railway is
# the worked example) are not in $desired, so deploy and prune never touch
# them. Zed still loads every SKILL.md there and fails the whole skill on
# invalid YAML. Quote unsafe unmanaged frontmatter in place; skip managed
# destinations so this pass cannot create hash churn against canonical
# sources. AgentHub-owned skills must be YAML-safe at source.
$sharedRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($agent in $agents) {
  $raw = [string]$agent.nativePaths.sharedSkillsDir
  if ([string]::IsNullOrWhiteSpace($raw)) { continue }
  $dir = Resolve-UnderUserProfile $raw
  if ([string]::IsNullOrWhiteSpace($dir)) { continue }
  [void]$sharedRoots.Add($dir)
}
foreach ($dir in $sharedRoots) {
  if ($CapabilityId) { continue }
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
  $yamlResult = Repair-SkillFrontmatterYamlDirectory -SkillsRoot $dir -Apply:$Apply -SkipPaths @($desired.Keys)
  if ($Apply) {
    $yamlRepaired += $yamlResult.Repaired
    foreach ($path in @($yamlResult.NeedsRepair)) {
      Write-Host "YAML-repaired unmanaged skill frontmatter: $path"
    }
  } else {
    $yamlNeedsRepair += @($yamlResult.NeedsRepair).Count
    foreach ($path in @($yamlResult.NeedsRepair)) {
      Write-Host "YAML-needs-repair unmanaged skill frontmatter: $path"
    }
  }
}

# Host skill-visibility overrides. The native-plugin skip above withholds a
# host's own deployment, but a host whose skillsDir is a junction onto the
# shared library still loads every loose copy deployed there for OTHER hosts.
# On 2026-10-26 Claude listed media-studio (x5), product-experience-engineering
# (x11) and use-repowise twice: once from its plugin, once as a loose copy.
# Claude Code documents skillOverrides in settings.json: "off" hides a skill
# from the model listing and the / menu, and plugin skills are unaffected. So
# the junction stays (no swap under running sessions) and this pass hides the
# loose duplicate by name instead.
#
# A host opts in with an agents.json skillOverrides block. A loose skill is
# hidden when the host's settings enable the plugin shipping it, or when the
# block names it as a duplicate of a host built-in. Ownership is recorded in a
# separate state file: Sync removes only an "off" it wrote, and never changes
# an entry the owner set. Disabling the plugin restores the loose copy.
$overrideStatePath = Join-Path $runtimeRoot 'skill-overrides.json'
$priorOverrides = @{}
if (Test-Path -LiteralPath $overrideStatePath) {
  $overrideDocument = Get-Content -LiteralPath $overrideStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($property in @($overrideDocument.hosts.PSObject.Properties)) { $priorOverrides[$property.Name] = $property.Value }
}
$overridesAfterRun = @{}
foreach ($hostId in $priorOverrides.Keys) { $overridesAfterRun[$hostId] = $priorOverrides[$hostId] }
$overridesChanged = 0
# Unlike the passes above, this one also runs under -CapabilityId: it reads the
# whole registry and the host settings, never the scoped deployment set.
foreach ($agent in $agents) {
  $overrideConfig = $agent.skillOverrides
  if (-not $overrideConfig) { continue }
  $hostId = [string]$agent.id
  $settingsPath = Resolve-UnderUserProfile ([string]$agent.nativePaths.settings)
  $hostSkillsDir = Resolve-UnderUserProfile ([string]$agent.nativePaths.skillsDir)
  if ([string]::IsNullOrWhiteSpace($settingsPath) -or [string]::IsNullOrWhiteSpace($hostSkillsDir)) {
    $failures.Add("skillOverrides on '$hostId' needs nativePaths.settings and nativePaths.skillsDir")
    continue
  }
  $overrideRow = { param($Capability, $Name, $Status) $rows.Add([pscustomobject]@{ capability=$Capability; host=$hostId; mode='host-skill-override'; skill=$Name; status=$Status }) }
  if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    & $overrideRow '<host-settings>' '<settings>' 'settings-absent'
    continue
  }
  try {
    $settingsText = [IO.File]::ReadAllText($settingsPath)
    $settings = $settingsText | ConvertFrom-Json
  } catch {
    $failures.Add("cannot parse '$settingsPath' for skillOverrides: $($_.Exception.Message)")
    continue
  }

  # Desired hides: name -> owning capability (or the built-in marker).
  $desiredHides = [ordered]@{}
  $marketplace = [string]$overrideConfig.pluginMarketplace
  foreach ($capability in $capabilities.capabilities) {
    $pluginKey = "$($capability.id)@$marketplace"
    $pluginEnabled = $settings.enabledPlugins -and $settings.enabledPlugins.PSObject.Properties[$pluginKey] -and
      ($settings.enabledPlugins.$pluginKey -eq $true)
    if (-not $pluginEnabled) { continue }
    try { $pkgRoot = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $capability -OverlayRoot $overlayRoot } catch { continue }
    $pkgSkills = Join-Path $pkgRoot 'skills'
    if (-not (Test-Path -LiteralPath $pkgSkills)) { continue }
    foreach ($skill in @(Get-ChildItem -LiteralPath $pkgSkills -Directory)) {
      if (Test-Path -LiteralPath (Join-Path $hostSkillsDir $skill.Name) -PathType Container) {
        $desiredHides[$skill.Name] = [string]$capability.id
      }
    }
  }
  foreach ($name in @($overrideConfig.duplicateOfHostBuiltIns)) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($shippedAnywhere.ContainsKey($name)) {
      $failures.Add("skillOverrides on '$hostId' names '$name' as a host built-in duplicate, but packages/$($shippedAnywhere[$name]) ships it")
      continue
    }
    if (Test-Path -LiteralPath (Join-Path $hostSkillsDir $name) -PathType Container) {
      $desiredHides[$name] = '<host-built-in>'
    }
  }

  $current = [ordered]@{}
  if ($settings.PSObject.Properties['skillOverrides'] -and $settings.skillOverrides) {
    foreach ($property in @($settings.skillOverrides.PSObject.Properties)) { $current[$property.Name] = $property.Value }
  }
  # Ownership only carries for the same settings file; a moved profile starts clean.
  $priorOwned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $priorHost = $priorOverrides[$hostId]
  if ($priorHost -and [string]$priorHost.settings -eq $settingsPath) {
    foreach ($name in @($priorHost.owned)) { if ($name) { [void]$priorOwned.Add([string]$name) } }
  }
  $owned = [Collections.Generic.List[string]]::new()
  $changed = $false
  foreach ($name in $priorOwned) {
    if ($desiredHides.Contains($name)) { continue }
    if ($current.Contains($name) -and $current[$name] -eq 'off') {
      $current.Remove($name)
      $changed = $true
      & $overrideRow '<stale-override>' $name 'stale'
    }
    # Otherwise the owner changed or removed it: no longer ours to touch.
  }
  foreach ($name in $desiredHides.Keys) {
    if ($current.Contains($name)) {
      if ($priorOwned.Contains($name) -and $current[$name] -eq 'off') {
        $owned.Add($name)
        & $overrideRow $desiredHides[$name] $name 'current'
      } else {
        & $overrideRow $desiredHides[$name] $name 'owner-set'
      }
      continue
    }
    $current[$name] = 'off'
    $owned.Add($name)
    $changed = $true
    & $overrideRow $desiredHides[$name] $name 'missing'
  }

  if ($changed) { $overridesChanged++ }
  if (-not $Apply) { continue }
  if ($changed) {
    $updated = [ordered]@{}
    foreach ($property in @($settings.PSObject.Properties)) {
      if ($property.Name -ne 'skillOverrides') { $updated[$property.Name] = $property.Value }
    }
    if ($current.Count -gt 0) { $updated['skillOverrides'] = [pscustomobject]$current }
    # Keep the file's own line endings; ConvertTo-Json emits the platform's.
    $newText = (([pscustomobject]$updated | ConvertTo-Json -Depth 64) -replace "`r`n", "`n") + "`n"
    if ($settingsText.Contains("`r`n")) { $newText = $newText -replace "`n", "`r`n" }
    # Refuse a write that would change anything but skillOverrides.
    $before = [ordered]@{}
    foreach ($property in @($settings.PSObject.Properties)) { if ($property.Name -ne 'skillOverrides') { $before[$property.Name] = $property.Value } }
    $after = [ordered]@{}
    foreach ($property in @(($newText | ConvertFrom-Json).PSObject.Properties)) { if ($property.Name -ne 'skillOverrides') { $after[$property.Name] = $property.Value } }
    if (([pscustomobject]$before | ConvertTo-Json -Depth 64 -Compress) -ne ([pscustomobject]$after | ConvertTo-Json -Depth 64 -Compress)) {
      $failures.Add("refusing to write '$settingsPath': the round-trip would change keys other than skillOverrides")
      continue
    }
    $stageSettings = $null
    try {
      $physicalSettings = Resolve-PhysicalWritePath $settingsPath
      $stageSettings = "$physicalSettings.agenthub-stage-$([guid]::NewGuid())"
      [IO.File]::WriteAllText($stageSettings, $newText, (New-Object System.Text.UTF8Encoding($false)))
      Move-Item -LiteralPath $stageSettings -Destination $physicalSettings -Force
    } catch {
      $failures.Add("failed to write skillOverrides to '$settingsPath': $($_.Exception.Message)")
      if ($stageSettings -and (Test-Path -LiteralPath $stageSettings)) { Remove-Item -LiteralPath $stageSettings -Force }
      continue
    }
  }
  $overridesAfterRun[$hostId] = [pscustomobject]@{ settings=$settingsPath; owned=@($owned | Sort-Object) }
}
if ($Apply) {
  $physicalOverrideState = Resolve-PhysicalWritePath $overrideStatePath
  New-Item -ItemType Directory -Path (Split-Path -Parent $physicalOverrideState) -Force | Out-Null
  $overrideJson = @{ schemaVersion=1; updatedAt=(Get-Date).ToUniversalTime().ToString('o'); hosts=$overridesAfterRun } | ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText($physicalOverrideState, ($overrideJson + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# The ledger records what this run actually manages, and it is written BEFORE
# the failure gate below -- deliberately, and this ordering is load-bearing.
#
# THE DEFECT THIS FIXES. The copies above already happened by the time control
# reaches here. Writing the ledger after an `exit 1` meant a run that deployed
# 99 skills and refused 4 recorded NONE of the 99: every one became "unowned"
# on the next run, which then refused to ever update it. Measured 2026-08-08:
# the live ledger was last written 2026-08-05, so every skill deployed after
# the refusals appeared on 2026-08-06 was stranded exactly this way, and no
# -Apply could repair it. Nothing failed loudly; the state was just silently
# wrong -- this repo's signature defect class, in the deployment path.
#
# WHAT IS RECORDED, AND WHY IT IS NOT $desired. $desired is every destination
# the registry DECLARES, which is not the same as the set this run can
# honestly claim:
#   - refused, never owned    -> not recorded. Claiming it would let the next
#                                run overwrite a file we just declined to touch.
#   - refused, already owned  -> prior record carried forward verbatim. The
#     (user-modified, or        stored hash is what detects the modification,
#      unprunable)              so re-recording today's hash would launder the
#                               modification into the new baseline, and
#                               dropping it entirely would orphan a file the
#                               prune path can only reach through this ledger.
#   - everything else         -> recorded as deployed.
$managedAfterRun = @{}
if ($CapabilityId -or -not $Prune) {
  foreach ($destination in $prior.managed.Keys) {
    $managedAfterRun[$destination] = $prior.managed[$destination]
  }
}
foreach ($destination in $desired.Keys) {
  if ($refused.ContainsKey($destination)) {
    if ($prior.managed.ContainsKey($destination)) { $managedAfterRun[$destination] = $prior.managed[$destination] }
    continue
  }
  $managedAfterRun[$destination] = $desired[$destination]
}
# A prune we refused is still ours; it is absent from $desired by definition
# (that absence is what nominated it for pruning), so carry it separately.
foreach ($destination in $refused.Keys) {
  if ($managedAfterRun.ContainsKey($destination)) { continue }
  if ($prior.managed.ContainsKey($destination)) { $managedAfterRun[$destination] = $prior.managed[$destination] }
}

# Carried legacy entries keep their original comparison format, including
# modified copies. Never re-baseline their current bytes during migration.
if ($priorHashesAreLegacy) {
  foreach ($destination in $managedAfterRun.Keys) {
    if ($prior.managed.ContainsKey($destination) -and
        [object]::ReferenceEquals($managedAfterRun[$destination], $prior.managed[$destination])) {
      $managedAfterRun[$destination] | Add-Member -NotePropertyName hashSchemaVersion -NotePropertyValue 1 -Force
    }
  }
}

if ($Apply) {
  $physicalStatePath = Resolve-PhysicalWritePath $statePath
  New-Item -ItemType Directory -Path (Split-Path -Parent $physicalStatePath) -Force | Out-Null
  # Not Set-Content -Encoding UTF8: that writes a BOM under Windows PowerShell
  # 5.1 and none under PowerShell 7, so the state file this run leaves behind
  # would differ by shell. The trailing CRLF reproduces what Set-Content
  # appended, keeping the emitted bytes identical to today's PowerShell 7 run.
  $stateJson = @{ schemaVersion=$StateSchemaVersion; updatedAt=(Get-Date).ToUniversalTime().ToString('o'); managed=$managedAfterRun } |
    ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText($physicalStatePath, ($stateJson + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
  exit 1
}

if ($VerbosePreference -eq 'Continue') { $rows | Sort-Object capability,host,skill | Format-Table -AutoSize }

# Zero evaluated rows means no (capability, host) pair was even considered.
# That is a broken configuration, not parity. A prune-only run is the one
# legitimate way to do real work with no rows, so it does not trip this.
if ($rows.Count -eq 0 -and $pruned -eq 0) {
  throw "Zero (capability, host) rows were evaluated at all. Refusing to report success against an empty work set."
}

$counts = $rows | Group-Object status | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Output "PASS: capability parity $($rows.Count) host mappings checked; $($counts -join ', '); pruned=$pruned; retired-pruned=$retiredPruned; cli-shadow-pruned=$cliShadowPruned; yaml-repaired=$yamlRepaired; yaml-needs-repair=$yamlNeedsRepair; skill-override-hosts-changed=$overridesChanged; apply=$Apply."
