#Requires -Version 5.1
[CmdletBinding()]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$Prune,
  [switch]$AdoptExisting,
  [string]$RepositoryRoot,
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
if (-not $Apply) { $Audit = $true }
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
$runtimeRoot = Join-Path $env:LOCALAPPDATA 'AgentHub\sync'
$statePath = Join-Path $runtimeRoot 'managed-skills.json'
$capabilities = Get-Content (Join-Path $root 'registry\capabilities.json') -Raw | ConvertFrom-Json
$agentsDocument = Get-Content (Join-Path $root 'registry\agents.json') -Raw | ConvertFrom-Json
$agents = @($agentsDocument.activeAgents) + @($agentsDocument.inactiveAgents)

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
  $sourceRoot = [IO.Path]::GetFullPath([string]$capability.canonicalSource)
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
    $skillsDir = [string]$agent.nativePaths.skillsDir
    if ([string]::IsNullOrWhiteSpace($skillsDir) -or $skills.Count -eq 0) { continue }
    foreach ($skill in $skills) {
      $destination = Join-Path $skillsDir $skill.Name
      $sourceHash = Get-TreeHash $skill.FullName
      $desired[$destination] = @{ capability=$capability.id; skill=$skill.Name; hash=$sourceHash }
      $currentHash = if (Test-Path -LiteralPath $destination) { Get-TreeHash $destination } else { $null }
      $status = if ($currentHash -eq $sourceHash) { 'current' } elseif ($currentHash) { 'drift' } else { 'missing' }
      $rows.Add([pscustomobject]@{ capability=$capability.id; host=$agent.id; mode='loose-skill'; skill=$skill.Name; status=$status })
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

if ($Apply -and $Prune) {
  foreach ($destination in @($prior.managed.Keys)) {
    if ($desired.ContainsKey($destination) -or -not (Test-Path -LiteralPath $destination)) { continue }
    $currentHash = Get-TreeHash $destination
    if ($currentHash -ne $prior.managed[$destination].hash) {
      $failures.Add("refusing to prune modified managed skill: $destination")
      continue
    }
    Remove-Item -LiteralPath $destination -Recurse -Force
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
$counts = $rows | Group-Object status | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Output "PASS: capability parity $($rows.Count) host mappings checked; $($counts -join ', '); apply=$Apply."
