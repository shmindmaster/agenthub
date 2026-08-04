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

$runtimeRoot = if ($profileIsOverridden) {
  Join-Path $UserProfile 'AppData\Local\AgentHub\sync'
} else {
  Join-Path $env:LOCALAPPDATA 'AgentHub\sync'
}
$statePath = Join-Path $runtimeRoot 'managed-skills.json'
$capabilities = Get-Content (Join-Path $root 'registry\capabilities.json') -Raw | ConvertFrom-Json
$agentsDocument = Get-Content (Join-Path $root 'registry\agents.json') -Raw | ConvertFrom-Json

# Inactive hosts are retained as inventory, not as deployment targets. A host
# the fleet profile never dispatches to still costs one full skill copy per
# mapping: 33 of the registry's capability->host mappings point at amp, devin,
# factory, vscode-insiders and windsurf. Skipping them by default matches the
# -IncludeInactiveAgents switch Sync-AgentHub.ps1 already exposes for MCP, so
# the fleet has one convention rather than two. The mappings stay in
# capabilities.json: this narrows what is deployed, not what is recorded.
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

function Get-TreeHash([string]$Path) {
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

$prior = if (Test-Path -LiteralPath $statePath) {
  $stateDocument = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  $managed = @{}
  foreach ($property in @($stateDocument.managed.PSObject.Properties)) {
    $managed[$property.Name] = $property.Value
  }
  @{ managed = $managed }
} else { @{ managed = @{} } }
if (-not $prior.ContainsKey('managed')) { $prior.managed = @{} }
$desired = @{}
$rows = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[string]]::new()

foreach ($capability in $capabilities.capabilities) {
  # canonicalSource is repo-relative (e.g. "packages/clerk"); resolve it
  # against the repository root this script is actually running from, not
  # the process's current working directory.
  $sourceRoot = [IO.Path]::GetFullPath((Join-Path $root ([string]$capability.canonicalSource)))
  $skillsRoot = Join-Path $sourceRoot 'skills'
  $skills = if (Test-Path -LiteralPath $skillsRoot) { @(Get-ChildItem -LiteralPath $skillsRoot -Directory) } else { @() }
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
    if ([string]::IsNullOrWhiteSpace($skillsDir) -or $skills.Count -eq 0) { continue }
    $deployMode = if ($usesSharedDir) { 'shared-loose-skill' } else { 'loose-skill' }
    foreach ($skill in $skills) {
      $destination = Join-Path $skillsDir $skill.Name
      $sourceHash = Get-TreeHash $skill.FullName
      $desired[$destination] = @{ capability=$capability.id; skill=$skill.Name; hash=$sourceHash }
      $currentHash = if (Test-Path -LiteralPath $destination) { Get-TreeHash $destination } else { $null }
      $status = if ($currentHash -eq $sourceHash) { 'current' } elseif ($currentHash) { 'drift' } else { 'missing' }
      $rows.Add([pscustomobject]@{ capability=$capability.id; host=$agent.id; mode=$deployMode; skill=$skill.Name; status=$status })
      if (-not $Apply -or $status -eq 'current') { continue }
      if ($currentHash -and -not $prior.managed.ContainsKey($destination) -and -not $AdoptExisting) {
        $failures.Add("refusing to replace unowned skill: $destination")
        continue
      }
      if ($currentHash -and $prior.managed.ContainsKey($destination) -and
          $prior.managed[$destination].hash -ne $currentHash -and -not $AdoptExisting) {
        $failures.Add("refusing to replace user-modified managed skill: $destination")
        continue
      }
      if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
      New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
      Copy-Item -LiteralPath $skill.FullName -Destination $destination -Recurse
    }
  }
}

$pruned = 0
if ($Apply -and $Prune) {
  foreach ($destination in @($prior.managed.Keys)) {
    if ($desired.ContainsKey($destination) -or -not (Test-Path -LiteralPath $destination)) { continue }
    $currentHash = Get-TreeHash $destination
    if ($currentHash -ne $prior.managed[$destination].hash) {
      $failures.Add("refusing to prune modified managed skill: $destination")
      continue
    }
    Remove-Item -LiteralPath $destination -Recurse -Force
    $pruned++
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
  exit 1
}

if ($Apply) {
  New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
  @{ schemaVersion=1; updatedAt=(Get-Date).ToUniversalTime().ToString('o'); managed=$desired } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

if ($VerbosePreference -eq 'Continue') { $rows | Sort-Object capability,host,skill | Format-Table -AutoSize }

# Zero evaluated rows means no (capability, host) pair was even considered.
# That is a broken configuration, not parity. A prune-only run is the one
# legitimate way to do real work with no rows, so it does not trip this.
if ($rows.Count -eq 0 -and $pruned -eq 0) {
  throw "Zero (capability, host) rows were evaluated at all. Refusing to report success against an empty work set."
}

$counts = $rows | Group-Object status | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Output "PASS: capability parity $($rows.Count) host mappings checked; $($counts -join ', '); pruned=$pruned; apply=$Apply."
