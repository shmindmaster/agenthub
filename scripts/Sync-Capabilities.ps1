#Requires -Version 5.1
[CmdletBinding()]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$Prune,
  [switch]$AdoptExisting,
  [switch]$IncludeInactiveAgents,
  [string]$RepositoryRoot,
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
if (-not $Apply) { $Audit = $true }
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
# Dot-sourced for Get-AgentHubStableFileHash (see Get-TreeHash below).
# RegistryContentHash.ps1 defines functions only -- no top-level side effects
# -- which is why scripts/Validate-AgentHub.ps1 loads it the same way.
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')

# -UserProfile has to actually move where this script writes, or it is a
# safety promise the script does not keep. Registry skillsDir values are
# absolute and baked against the real profile, so rebase both them and the
# runtime state directory whenever an override is supplied. A prior task in
# this effort shipped a live-fleet write on exactly this gap.
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
  throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = [IO.Path]::GetFullPath($UserProfile).TrimEnd('\')
$realProfile = if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $null } else { [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\') }
$profileIsOverridden = $realProfile -and ($UserProfile -ne $realProfile)

function Resolve-UnderUserProfile([string]$Path) {
  if (-not $profileIsOverridden -or [string]::IsNullOrWhiteSpace($Path)) { return $Path }
  $full = [IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($realProfile + '\', [StringComparison]::OrdinalIgnoreCase)) {
    return Join-Path $UserProfile $full.Substring($realProfile.Length + 1)
  }
  return $full
}

$agentHubRuntimeRoot = if ($profileIsOverridden) {
  Join-Path $UserProfile 'AppData\Local\AgentHub'
} else {
  Join-Path $env:LOCALAPPDATA 'AgentHub'
}
$runtimeRoot = Join-Path $agentHubRuntimeRoot 'sync'
$statePath = Join-Path $runtimeRoot 'managed-skills.json'
$capabilities = Get-Content (Join-Path $root 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agentsDocument = Get-Content (Join-Path $root 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

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
# SEQUENCING HAZARD: narrowing the host set drops those destinations out of
# $desired, and a plain -Apply rewrites the state file to exactly $desired.
# Prune compares $prior against $desired and so must run in the SAME -Apply
# that first narrows the set -- once a plain -Apply has rewritten the state,
# the already-deployed copies are orphaned beyond the reach of any later
# -Prune, because prune only ever iterates destinations the state still claims.
$allAgents = @($agentsDocument.activeAgents) + @($agentsDocument.inactiveAgents)
$agents = if ($IncludeInactiveAgents) { $allAgents } else { @($agentsDocument.activeAgents) }

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
        $relative = $_.FullName.Substring($Path.TrimEnd('\').Length + 1).Replace('\','/')
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
        $relative = $_.FullName.Substring($Path.TrimEnd('\').Length + 1).Replace('\','/')
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
$desired = @{}
$retiredDestinations = @{}
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
  $prefix = $agentHubRuntimeRoot.TrimEnd('\') + '\'
  if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Managed runtime path escapes '$agentHubRuntimeRoot': '$RelativePath'"
  }
  return $destination
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
  $currentHash = if (Test-Path -LiteralPath $Destination) { Get-TreeHash $Destination } else { $null }
  $status = if ($currentHash -eq $sourceHash) { 'current' } elseif ($currentHash) { 'drift' } else { 'missing' }
  $rows.Add([pscustomobject]@{ capability=$CapabilityId; host=$HostId; mode=$Mode; skill=$ItemName; status=$status })
  if (-not $Apply -or $status -eq 'current') { return }
  if ($currentHash -and -not $prior.managed.ContainsKey($Destination) -and -not $AdoptExisting) {
    $failures.Add("refusing to replace unowned ${Kind}: $Destination")
    $refused[$Destination] = $true
    return
  }
  $recordedComparableHash = if ($currentHash -and $priorHashesAreLegacy -and $prior.managed.ContainsKey($Destination)) {
    Get-TreeHashLegacy $Destination
  } else { $currentHash }
  if ($currentHash -and $prior.managed.ContainsKey($Destination) -and
      $prior.managed[$Destination].hash -ne $recordedComparableHash -and -not $AdoptExisting) {
    $failures.Add("refusing to replace user-modified managed ${Kind}: $Destination")
    $refused[$Destination] = $true
    return
  }
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
  New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
}

foreach ($capability in $capabilities.capabilities) {
  # canonicalSource is repo-relative (e.g. "packages/clerk"); resolve it
  # against the repository root this script is actually running from, not
  # the process's current working directory.
  $sourceRoot = [IO.Path]::GetFullPath((Join-Path $root ([string]$capability.canonicalSource)))
  $skillsRoot = Join-Path $sourceRoot 'skills'
  $skills = if (Test-Path -LiteralPath $skillsRoot) { @(Get-ChildItem -LiteralPath $skillsRoot -Directory) } else { @() }
  if ($capability.deployedCatalog) {
    $catalogDestination = Resolve-AgentHubRuntimeDestination ([string]$capability.deployedCatalog.runtimeRelativeRoot)
    Register-ManagedTree -Source $sourceRoot -Destination $catalogDestination -CapabilityId ([string]$capability.id) `
      -ItemName ([string]$capability.deployedCatalog.entrypoint) -Mode 'managed-runtime-package' -Kind 'runtime package'
    $authoritySource = [IO.Path]::GetFullPath((Join-Path $root ([string]$capability.deployedCatalog.authoritySource)))
    $rootPrefix = $root.TrimEnd('\') + '\'
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
    # skillsDir -- currently codex and gemini both point sharedSkillsDir at
    # ~/.agents/skills (documentation-confirmed for both: codex's USER tier
    # is $HOME/.agents/skills per learn.chatgpt.com/docs/build-skills; gemini
    # documents ~/.gemini/skills/ or the ~/.agents/skills/ alias at the same
    # precedence tier per geminicli.com/docs/cli/skills). cline intentionally
    # does NOT declare sharedSkillsDir: cline's own documentation names only
    # .cline/skills (workspace) and ~/.cline/skills (global) -- see the note
    # on the cline entry in registry/agents.json. $desired stays keyed
    # purely by the physical destination path (not e.g.
    # "$hostId::$destination"), so when two hosts resolve to the identical
    # shared destination they collapse to the same dictionary entry instead
    # of competing. A host with no sharedSkillsDir declared is unaffected
    # and still gets its own copy in its own skillsDir -- the reachability
    # rule.
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
  $r = Join-Path ([IO.Path]::GetFullPath((Join-Path $root ([string]$capability.canonicalSource)))) 'skills'
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
    foreach ($raw in @([string]$agent.nativePaths.skillsDir, [string]$agent.nativePaths.sharedSkillsDir)) {
      if ([string]::IsNullOrWhiteSpace($raw)) { continue }
      $dir = Resolve-UnderUserProfile $raw
      if ([string]::IsNullOrWhiteSpace($dir)) { continue }
      $retiredDestinations[(Join-Path $dir $name)] = "<fleet:$name>"
    }
  }
}

$retiredPruned = 0
if ($Apply -and $Prune) {
  foreach ($destination in @($retiredDestinations.Keys)) {
    if (-not (Test-Path -LiteralPath $destination)) { continue }
    if ($desired.ContainsKey($destination)) { continue }   # a live skill reclaimed the name
    Remove-Item -LiteralPath $destination -Recurse -Force
    $retiredPruned++
  }
}

$pruned = 0
if ($Apply -and $Prune) {
  foreach ($destination in @($prior.managed.Keys)) {
    if ($desired.ContainsKey($destination) -or -not (Test-Path -LiteralPath $destination)) { continue }
    # Same stored-format rule as the replace guard above.
    $currentHash = if ($priorHashesAreLegacy) { Get-TreeHashLegacy $destination } else { Get-TreeHash $destination }
    if ($currentHash -ne $prior.managed[$destination].hash) {
      $failures.Add("refusing to prune modified managed skill: $destination")
      $refused[$destination] = $true
      continue
    }
    Remove-Item -LiteralPath $destination -Recurse -Force
    $pruned++
  }
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

if ($Apply) {
  New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
  # Not Set-Content -Encoding UTF8: that writes a BOM under Windows PowerShell
  # 5.1 and none under PowerShell 7, so the state file this run leaves behind
  # would differ by shell. The trailing CRLF reproduces what Set-Content
  # appended, keeping the emitted bytes identical to today's PowerShell 7 run.
  $stateJson = @{ schemaVersion=$StateSchemaVersion; updatedAt=(Get-Date).ToUniversalTime().ToString('o'); managed=$managedAfterRun } |
    ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText($statePath, ($stateJson + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
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
Write-Output "PASS: capability parity $($rows.Count) host mappings checked; $($counts -join ', '); pruned=$pruned; retired-pruned=$retiredPruned; apply=$Apply."
