#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('inventory', 'evaluate', 'generate', 'sync', 'validate', 'drift', 'cleanup')]
  [string]$Command,

  [string]$RegistryRoot = 'C:\Repos\agent-capabilities',

  [switch]$Apply,

  [switch]$WriteReport
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$registryPath = Join-Path $RegistryRoot 'registry\installations.json'
$reportsRoot = Join-Path $RegistryRoot 'reports'
$generatedRoot = Join-Path $RegistryRoot 'generated'

function Read-Json([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON file: $Path" }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

. (Join-Path $PSScriptRoot 'AgentCtl.CursorReadiness.ps1')

function Write-Text([string]$Path, [string]$Text) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Write-Json([string]$Path, $Value) {
  Write-Text $Path (($Value | ConvertTo-Json -Depth 40) + "`n")
}

function Resolve-ControlPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Replace('/', '\'))
  if ([System.IO.Path]::IsPathRooted($expanded)) { return [System.IO.Path]::GetFullPath($expanded) }
  return [System.IO.Path]::GetFullPath((Join-Path $RegistryRoot $expanded))
}

function Get-Digest([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-WslDistributions {
  if (!(Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return @() }
  return @(
    wsl.exe --list --quiet 2>$null |
      ForEach-Object { ($_ -replace "`0", '').Trim() } |
      Where-Object { $_ } |
      Sort-Object -Unique
  )
}

function Get-Installations {
  return Read-Json $registryPath
}

function Get-InventoryRows {
  $registry = Get-Installations
  return @(
    foreach ($surface in $registry.surfaces) {
      $exe = Resolve-ControlPath ([string]$surface.executable)
      $configHomeResolved = Resolve-ControlPath ([string]$surface.configHome)
      $instruction = Resolve-ControlPath ([string]$surface.instructionPath)
      [pscustomobject][ordered]@{
        id = [string]$surface.id
        agentId = [string]$surface.agentId
        name = [string]$surface.name
        kind = [string]$surface.kind
        version = [string]$surface.version
        platform = [string]$surface.platform
        lifecycle = [string]$surface.lifecycle
        readiness = [string]$surface.readiness
        classification = [string]$surface.classification
        executable = $exe
        executablePresent = if ($exe) { Test-Path -LiteralPath $exe -PathType Leaf } else { $false }
        expectedInstalled = [bool]$surface.installed
        configHome = $configHomeResolved
        configHomePresent = if ($configHomeResolved) { Test-Path -LiteralPath $configHomeResolved } else { $false }
        expectedConfigured = [bool]$surface.configured
        instructionPath = $instruction
        instructionPresent = if ($instruction) { Test-Path -LiteralPath $instruction -PathType Leaf } else { $null }
        authoritative = [bool]$surface.authoritative
        notes = [string]$surface.notes
      }
    }
  )
}

function Get-TreeSummary([string]$Path, [string]$Kind) {
  if (!(Test-Path -LiteralPath $Path -PathType Container)) { return $null }
  $files = @(Get-ChildItem -LiteralPath $Path -File -Force -Recurse -ErrorAction SilentlyContinue)
  return [pscustomobject]@{
    kind = $Kind
    path = $Path
    files = $files.Count
    bytes = ($files | Measure-Object Length -Sum).Sum
  }
}

function Get-EnvironmentInventory {
  $pathEntries = @()
  foreach ($scope in @('User', 'Machine')) {
    foreach ($entry in @([Environment]::GetEnvironmentVariable('Path', $scope) -split ';' | Where-Object { $_ })) {
      $expanded = [Environment]::ExpandEnvironmentVariables($entry)
      $pathEntries += [pscustomobject]@{ scope = $scope; path = $entry; present = (Test-Path -LiteralPath $expanded) }
    }
  }

  $wrappers = @()
  $wrapperRoot = 'C:\Users\SaroshHussain\bin'
  if (Test-Path -LiteralPath $wrapperRoot) {
    $wrappers = @(Get-ChildItem -LiteralPath $wrapperRoot -File -Force | Where-Object { $_.Name -match '^(agy|claude|codex|copilot|cursor-agent|devin|droid|gemini|grok|hermes|jules|opencode|qwen|warp)' } | ForEach-Object { [pscustomobject]@{ name = $_.Name; path = $_.FullName; bytes = $_.Length } })
  }

  $npmPackages = @()
  $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npmCommand) {
    try {
      $npmJson = & $npmCommand.Source ls -g --depth=0 --json 2>$null | Out-String | ConvertFrom-Json
      $npmPackages = @($npmJson.dependencies.PSObject.Properties | Where-Object { $_.Name -match 'claude|codex|qwen|opencode|gemini|copilot|amp|warp|jules|grok|devin|factory' } | ForEach-Object { [pscustomobject]@{ name = $_.Name; version = [string]$_.Value.version } })
    } catch {}
  }

  $scheduledTasks = @()
  if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    try {
      $scheduledTasks = @(Get-ScheduledTask | Where-Object { ($_.TaskName + $_.TaskPath) -match 'agent|codex|claude|cursor|qwen|opencode|gemini|copilot|antigravity|devin|factory|warp|jules|hermes|windsurf' } | ForEach-Object { [pscustomobject]@{ taskName = $_.TaskName; taskPath = $_.TaskPath; state = [string]$_.State } })
    } catch {}
  }

  $startupItems = @()
  foreach ($startupRoot in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
    if (Test-Path -LiteralPath $startupRoot) {
      $startupItems += @(Get-ChildItem -LiteralPath $startupRoot -Force | Where-Object { $_.Name -match 'agent|codex|claude|cursor|qwen|opencode|gemini|copilot|antigravity|devin|factory|warp|jules|hermes|windsurf' } | ForEach-Object { [pscustomobject]@{ name = $_.Name; path = $_.FullName } })
    }
  }

  $editorExtensions = @()
  foreach ($extensionRoot in @('C:\Users\SaroshHussain\.vscode\extensions', 'C:\Users\SaroshHussain\.vscode-insiders\extensions')) {
    if (Test-Path -LiteralPath $extensionRoot) {
      $editorExtensions += @(Get-ChildItem -LiteralPath $extensionRoot -Directory -Force | ForEach-Object { [pscustomobject]@{ host = Split-Path (Split-Path $extensionRoot -Parent) -Leaf; id = $_.Name; path = $_.FullName } })
    }
  }

  $stateTrees = @()
  foreach ($entry in @(
    @('C:\Users\SaroshHussain\.codex\agents', 'agents'), @('C:\Users\SaroshHussain\.codex\skills', 'skills'), @('C:\Users\SaroshHussain\.codex\plugins', 'plugins'), @('C:\Users\SaroshHussain\.codex\sessions', 'sessions'), @('C:\Users\SaroshHussain\.claude\agents', 'agents'), @('C:\Users\SaroshHussain\.claude\skills', 'skills'), @('C:\Users\SaroshHussain\.claude\plugins', 'plugins'), @('C:\Users\SaroshHussain\.claude\hooks', 'hooks'), @('C:\Users\SaroshHussain\.qwen\agents', 'agents'), @('C:\Users\SaroshHussain\.qwen\skills', 'skills'), @('C:\Users\SaroshHussain\.qwen\extensions', 'extensions'), @('C:\Users\SaroshHussain\.gemini\skills', 'skills'), @('C:\Users\SaroshHussain\.factory\droids', 'agents'), @('C:\Users\SaroshHussain\.factory\skills', 'skills'), @('C:\Users\SaroshHussain\.factory\plugins', 'plugins'), @('C:\Users\SaroshHussain\AppData\Local\hermes\skills', 'skills'), @('C:\Users\SaroshHussain\AppData\Local\hermes\hooks', 'hooks'), @('C:\Users\SaroshHussain\AppData\Local\hermes\memories', 'memories'), @('C:\Users\SaroshHussain\AppData\Local\hermes\sessions', 'sessions')
  )) {
    $summary = Get-TreeSummary ([string]$entry[0]) ([string]$entry[1])
    if ($summary) { $stateTrees += $summary }
  }

  $terminalSettings = @(
    'C:\Users\SaroshHussain\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
    'C:\Users\SaroshHussain\AppData\Local\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
  ) | ForEach-Object { [pscustomobject]@{ path = $_; present = (Test-Path -LiteralPath $_ -PathType Leaf) } }

  return [pscustomobject]@{
    pathEntries = $pathEntries
    wrappers = $wrappers
    npmGlobalAgentPackages = $npmPackages
    scheduledTasks = $scheduledTasks
    startupItems = $startupItems
    editorExtensions = $editorExtensions
    stateTrees = $stateTrees
    powershellProfiles = @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost | ForEach-Object { [pscustomobject]@{ path = $_; present = (Test-Path -LiteralPath $_ -PathType Leaf) } })
    windowsTerminalSettings = $terminalSettings
  }
}

function Save-InventoryReport {
  $registry = Get-Installations
  $rows = Get-InventoryRows
  $report = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    policy = $registry.policy
    wslDistributions = @(Get-WslDistributions)
    surfaces = $rows
    environment = Get-EnvironmentInventory
  }
  if ($WriteReport) {
    Write-Json (Join-Path $reportsRoot 'fleet-inventory.json') $report
  }

  $lines = @(
    '# Coding-Agent Fleet Inventory',
    '',
    ('Generated: `{0}`' -f $report.generatedAt),
    '',
    '| Surface | Kind | Version | Lifecycle | Readiness | Installed | Configured | Classification |',
    '|---|---|---:|---|---|---:|---:|---|'
  )
  foreach ($row in $rows) {
    $lines += '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f $row.name, $row.kind, $row.version, $row.lifecycle, $row.readiness, $row.executablePresent, $row.configHomePresent, $row.classification
  }
  $lines += ''
  $lines += '## Executable and configuration locations'
  $lines += ''
  $lines += '| Surface | Executable | Configuration home | Native instruction file |'
  $lines += '|---|---|---|---|'
  foreach ($row in $rows) {
    $executable = if ($row.executable) { '`{0}`' -f $row.executable } else { 'not installed' }
    $configHome = if ($row.configHome) { '`{0}`' -f $row.configHome } else { 'not configured' }
    $instruction = if ($row.instructionPath) { '`{0}`' -f $row.instructionPath } else { 'host settings/config only' }
    $lines += '| {0} | {1} | {2} | {3} |' -f $row.name, $executable, $configHome, $instruction
  }
  $lines += ''
  $lines += 'WSL distributions: ' + (($report.wslDistributions | ForEach-Object { '`{0}`' -f $_ }) -join ', ')
  $lines += ''
  $lines += 'Authentication files, credential values, sessions, memories, caches, and runtime databases were not read into this report.'
  if ($WriteReport) {
    Write-Text (Join-Path $reportsRoot 'fleet-inventory.md') (($lines -join "`n") + "`n")
  }
  return $report
}

function New-EvaluationReport {
  $instructionPaths = @(
    'C:\Users\SaroshHussain\.codex\AGENTS.md',
    'C:\Users\SaroshHussain\.claude\CLAUDE.md',
    'C:\Users\SaroshHussain\.qwen\QWEN.md',
    'C:\Users\SaroshHussain\.gemini\GEMINI.md',
    'C:\Users\SaroshHussain\.config\amp\AGENTS.md',
    'C:\Users\SaroshHussain\AppData\Local\hermes\SOUL.md'
  )
  $lines = @(
    '# Configuration Evaluation',
    '',
    '## Selected canonical elements',
    '',
    '- Client/personal boundary and capability ownership from the prior Codex and Claude policies.',
    '- Inspect-first, preserve-work, root-cause, repository-native verification behavior from the prior Claude policy.',
    '- Repository `AGENTS.md` precedence from Qwen and Gemini.',
    '- Autonomous routine work plus concise evidence handoff from Gemini.',
    '- Host-native adapter and shared MCP/API ownership policy from Amp and the repository charter.',
    '- Hermes direct, efficient personality retained as a host-specific preamble.',
    '',
    '## Replaced or rejected elements',
    '',
    '- Stale claims about installed reviewers, versions, or billing state: time-sensitive facts belong in skills and live inventory, not global policy.',
    '- Mandatory worktrees for every implementation: worktrees are conditional and governed by one lifecycle policy.',
    '- Independent always-approve or bypass language as policy: host flags now map to explicit autonomy profiles.',
    '- Duplicated global policy prose maintained separately in each agent home.',
    '',
    '## Source instruction snapshots',
    '',
    '| Path | Present | Bytes | SHA-256 |',
    '|---|---:|---:|---|'
  )
  foreach ($path in $instructionPaths) {
    $present = Test-Path -LiteralPath $path -PathType Leaf
    $length = if ($present) { (Get-Item -LiteralPath $path).Length } else { 0 }
    $hash = if ($present) { Get-Digest $path } else { 'missing' }
    $lines += '| `{0}` | {1} | {2} | `{3}` |' -f $path, $present, $length, $hash
  }
  $lines += ''
  $lines += 'Canonical result: `standards/global-agent-policy.md`, autonomy profiles under `profiles/`, common roles under `roles/`, and generated host-native instructions under `generated/`.'
  if ($WriteReport) {
    Write-Text (Join-Path $reportsRoot 'configuration-evaluation.md') (($lines -join "`n") + "`n")
  }
  return $lines
}

function New-GeneratedInstructions {
  $registry = Get-Installations
  $policyPath = Join-Path $RegistryRoot 'standards\global-agent-policy.md'
  $policy = Get-Content -LiteralPath $policyPath -Raw
  foreach ($target in $registry.managedInstructionTargets) {
    $generatedPath = Resolve-ControlPath ([string]$target.generatedPath)
    if ($target.PSObject.Properties.Match('preambleTemplate').Count -gt 0 -and $target.preambleTemplate) {
      $templatePath = Resolve-ControlPath ([string]$target.preambleTemplate)
      $content = (Get-Content -LiteralPath $templatePath -Raw).Replace('{{globalPolicy}}', $policy.Trim())
      if ($content -notmatch 'agent-capabilities:managed') {
        $content = $content.TrimEnd() + "`n`n<!-- agent-capabilities:managed -->`n"
      }
    } else {
      $content = '# ' + [string]$target.title + "`n`n<!-- agent-capabilities:managed -->`n`n" + $policy.Trim() + "`n"
    }
    Write-Text $generatedPath $content
  }
}

function Get-DriftRows {
  $registry = Get-Installations
  return @(
    foreach ($target in $registry.managedInstructionTargets) {
      $generatedPath = Resolve-ControlPath ([string]$target.generatedPath)
      $destination = Resolve-ControlPath ([string]$target.destination)
      $generatedHash = Get-Digest $generatedPath
      $destinationHash = Get-Digest $destination
      [pscustomobject][ordered]@{
        id = [string]$target.id
        generatedPath = $generatedPath
        destination = $destination
        generatedPresent = [bool]$generatedHash
        destinationPresent = [bool]$destinationHash
        inSync = [bool]($generatedHash -and $destinationHash -and $generatedHash -eq $destinationHash)
        generatedHash = $generatedHash
        destinationHash = $destinationHash
      }
    }
  )
}

function Save-DriftReport {
  $rows = Get-DriftRows
  if ($WriteReport) {
    Write-Json (Join-Path $reportsRoot 'configuration-drift.json') ([pscustomobject]@{ generatedAt = (Get-Date).ToString('o'); targets = $rows })
  }
  $lines = @('# Configuration Drift', '', '| Host | In sync | Generated | Destination |', '|---|---:|---|---|')
  foreach ($row in $rows) { $lines += '| {0} | {1} | `{2}` | `{3}` |' -f $row.id, $row.inSync, $row.generatedPath, $row.destination }
  if ($WriteReport) {
    Write-Text (Join-Path $reportsRoot 'configuration-drift.md') (($lines -join "`n") + "`n")
  }
  return $rows
}

function Sync-Instructions {
  New-GeneratedInstructions
  $rows = Get-DriftRows
  foreach ($row in $rows | Where-Object { -not $_.inSync }) {
    if (!$Apply) {
      Write-Host "WOULD SYNC $($row.id): $($row.destination)"
      continue
    }
    $content = Get-Content -LiteralPath $row.generatedPath -Raw
    Write-Text $row.destination $content
    Write-Host "SYNCED $($row.id): $($row.destination)" -ForegroundColor Green
  }
  if (!$Apply) { Write-Host 'Dry run only. Re-run with -Apply to deploy generated instruction files.' -ForegroundColor Yellow }
  Save-DriftReport | Out-Null
}

function Get-CleanupCandidates {
  $candidates = @()
  $desired = @((Get-Installations).policy.desiredWslDistributions)
  foreach ($distro in Get-WslDistributions) {
    if ($distro -notin $desired) {
      $candidates += [pscustomobject]@{ classification = 'duplicate-or-unknown'; path = "wsl:$distro"; bytes = $null; reason = 'WSL distribution is outside the desired set'; action = 'manual-review' }
    }
  }

  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ }
  foreach ($entry in $userPath) {
    $expanded = [Environment]::ExpandEnvironmentVariables($entry)
    if (!(Test-Path -LiteralPath $expanded)) {
      $candidates += [pscustomobject]@{ classification = 'broken'; path = $entry; bytes = $null; reason = 'User PATH entry does not exist'; action = 'review-path-removal' }
    }
  }

  $knownRoots = @(
    'C:\Users\SaroshHussain\.cursor',
    'C:\Users\SaroshHussain\.factory',
    'C:\Users\SaroshHussain\AppData\Local\hermes'
  )
  foreach ($root in $knownRoots) {
    if (!(Test-Path -LiteralPath $root)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(\.bad$|\.bak-pre|\.bak\.20\d{6}|\.old$)' }) {
      $candidates += [pscustomobject]@{ classification = 'outdated'; path = $file.FullName; bytes = $file.Length; reason = 'Superseded backup or failed configuration copy'; action = 'safe-after-current-config-validation' }
    }
  }

  $oldAgy = 'C:\Users\SaroshHussain\AppData\Local\agy'
  $wingetAgy = 'C:\Users\SaroshHussain\AppData\Local\Microsoft\WinGet\Links\agy.exe'
  if ((Test-Path -LiteralPath $oldAgy) -and (Test-Path -LiteralPath $wingetAgy -PathType Leaf)) {
    $bytes = (Get-ChildItem -LiteralPath $oldAgy -File -Force -Recurse | Measure-Object Length -Sum).Sum
    $candidates += [pscustomobject]@{ classification = 'duplicate'; path = $oldAgy; bytes = $bytes; reason = 'Older private Antigravity CLI copy superseded by WinGet installation'; action = 'safe-after-wrapper-and-version-validation' }
  }

  $trash = 'C:\Users\SaroshHussain\.agent-cleanup-trash'
  if (Test-Path -LiteralPath $trash -PathType Container) {
    $bytes = (Get-ChildItem -LiteralPath $trash -File -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    $hasProjectState = [bool](Get-ChildItem -LiteralPath $trash -Directory -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\.cursor\\projects($|\\)' } | Select-Object -First 1)
    if ($hasProjectState) {
      $candidates += [pscustomobject]@{ classification = 'protected-recoverable-state'; path = $trash; bytes = $bytes; reason = 'Prior cleanup quarantine contains project/session state; disposition belongs to the separate portfolio-alignment effort'; action = 'defer-to-portfolio-alignment' }
    } else {
      $candidates += [pscustomobject]@{ classification = 'recoverable-cleanup-trash'; path = $trash; bytes = $bytes; reason = 'Prior cleanup quarantine; inspect manifest before removal'; action = 'manual-review' }
    }
  }

  $sharedSkills = 'C:\Users\SaroshHussain\.agents\skills'
  $geminiSkills = 'C:\Users\SaroshHussain\.gemini\skills'
  if ((Test-Path $sharedSkills) -and (Test-Path $geminiSkills)) {
    $sharedNames = @(Get-ChildItem -LiteralPath $sharedSkills -Directory | ForEach-Object Name)
    foreach ($duplicate in Get-ChildItem -LiteralPath $geminiSkills -Directory | Where-Object { $_.Name -in $sharedNames }) {
      $bytes = (Get-ChildItem -LiteralPath $duplicate.FullName -File -Force -Recurse | Measure-Object Length -Sum).Sum
      $candidates += [pscustomobject]@{ classification = 'duplicate'; path = $duplicate.FullName; bytes = $bytes; reason = 'Gemini also loads the shared skill with the same name'; action = 'safe-after-skill-load-validation' }
    }
  }
  return @($candidates | Sort-Object classification, path)
}

function Save-CleanupReport {
  $candidates = Get-CleanupCandidates
  if ($WriteReport) {
    Write-Json (Join-Path $reportsRoot 'cleanup-candidates.json') ([pscustomobject]@{ generatedAt = (Get-Date).ToString('o'); mode = 'report-only'; candidates = $candidates })
  }
  $lines = @('# Cleanup Candidates', '', 'This command is report-only. It never uninstalls an agent or deletes configuration.', '', '| Classification | Path | Bytes | Reason | Action |', '|---|---|---:|---|---|')
  foreach ($item in $candidates) { $lines += '| {0} | `{1}` | {2} | {3} | {4} |' -f $item.classification, $item.path, $item.bytes, $item.reason, $item.action }
  if ($WriteReport) {
    Write-Text (Join-Path $reportsRoot 'cleanup-candidates.md') (($lines -join "`n") + "`n")
  }
  if ($Apply) { Write-Warning 'cleanup remains report-only even with -Apply; approve exact candidates in a separate maintenance task.' }
  return $candidates
}

function Invoke-Validation {
  $validationResults = New-Object System.Collections.Generic.List[object]
  function Add-Check([string]$Status, [string]$Check, [string]$Detail) {
    $validationResults.Add([pscustomobject]@{ status = $Status; check = $Check; detail = $Detail }) | Out-Null
  }

  $jsonFiles = Get-ChildItem -LiteralPath (Join-Path $RegistryRoot 'registry') -Filter '*.json' -File
  foreach ($file in $jsonFiles) {
    try { Read-Json $file.FullName | Out-Null; Add-Check 'PASS' "json:$($file.Name)" 'valid JSON' }
    catch { Add-Check 'FAIL' "json:$($file.Name)" $_.Exception.Message }
  }

  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $RegistryRoot 'profiles') -Filter '*.json' -File) {
    try { Read-Json $file.FullName | Out-Null; Add-Check 'PASS' "profile-json:$($file.Name)" 'valid JSON' }
    catch { Add-Check 'FAIL' "profile-json:$($file.Name)" $_.Exception.Message }
  }

  $registry = Get-Installations
  $surfaceIds = @($registry.surfaces | ForEach-Object id)
  if (($surfaceIds | Sort-Object -Unique).Count -eq $surfaceIds.Count) { Add-Check 'PASS' 'installation-ids' "$($surfaceIds.Count) unique surfaces" }
  else { Add-Check 'FAIL' 'installation-ids' 'duplicate surface IDs' }

  foreach ($row in Get-InventoryRows) {
    if ($row.expectedInstalled -eq $row.executablePresent) { Add-Check 'PASS' "installed:$($row.id)" ([string]$row.executablePresent) }
    else { Add-Check 'FAIL' "installed:$($row.id)" "expected=$($row.expectedInstalled) actual=$($row.executablePresent)" }
    if ($row.expectedConfigured -eq $row.configHomePresent) { Add-Check 'PASS' "configured:$($row.id)" ([string]$row.configHomePresent) }
    else { Add-Check 'FAIL' "configured:$($row.id)" "expected=$($row.expectedConfigured) actual=$($row.configHomePresent)" }
  }

  $desiredWsl = @($registry.policy.desiredWslDistributions | Sort-Object)
  $actualWsl = @(Get-WslDistributions | Sort-Object)
  if (($desiredWsl -join '|') -ieq ($actualWsl -join '|')) { Add-Check 'PASS' 'wsl-distributions' ($actualWsl -join ', ') }
  else { Add-Check 'FAIL' 'wsl-distributions' "desired=$($desiredWsl -join ',') actual=$($actualWsl -join ',')" }

  foreach ($row in Get-DriftRows) {
    if ($row.inSync) { Add-Check 'PASS' "managed-instruction:$($row.id)" 'in sync' }
    else { Add-Check 'FAIL' "managed-instruction:$($row.id)" 'generated and native files differ' }
  }

  $modelChecks = @(
    @{ id = 'codex'; path = 'C:\Users\SaroshHussain\.codex\config.toml'; pattern = '(?m)^model\s*=\s*"gpt-5\.6-sol"\s*$' },
    @{ id = 'qwen-code'; path = 'C:\Users\SaroshHussain\.qwen\settings.json'; json = 'qwen' },
    @{ id = 'opencode'; path = 'C:\Users\SaroshHussain\.config\opencode\opencode.json'; json = 'opencode' },
    @{ id = 'gemini'; path = 'C:\Users\SaroshHussain\.gemini\settings.json'; json = 'gemini' }
  )
  foreach ($modelCheck in $modelChecks) {
    try {
      if ($modelCheck.pattern) {
        $ok = (Get-Content -LiteralPath $modelCheck.path -Raw) -match $modelCheck.pattern
      } else {
        $settings = Read-Json $modelCheck.path
        switch ($modelCheck.json) {
          'qwen' { $ok = $settings.model.name -eq 'qwen3.8-max-preview' }
          'opencode' { $ok = $settings.model -eq 'qwen-cloud/qwen3.8-max-preview' }
          'gemini' {
            $alias = $settings.modelConfigs.customAliases.'gemini-3.6-flash-high'
            $ok = $settings.model.name -eq 'gemini-3.6-flash-high' -and $settings.experimental.dynamicModelConfiguration -eq $true -and $alias.modelConfig.model -eq 'gemini-3.6-flash' -and $alias.modelConfig.generateContentConfig.thinkingConfig.thinkingLevel -eq 'HIGH'
          }
        }
      }
      if ($ok) { Add-Check 'PASS' "model:$($modelCheck.id)" 'matches canonical model profile' }
      else { Add-Check 'FAIL' "model:$($modelCheck.id)" 'model configuration drift' }
    } catch { Add-Check 'FAIL' "model:$($modelCheck.id)" $_.Exception.Message }
  }

  foreach ($mcpPath in @(
    'C:\Users\SaroshHussain\.cursor\mcp.json',
    'C:\Users\SaroshHussain\.qwen\settings.json',
    'C:\Users\SaroshHussain\.gemini\settings.json',
    'C:\Users\SaroshHussain\.copilot\mcp-config.json',
    'C:\Users\SaroshHussain\.factory\mcp.json',
    'C:\Users\SaroshHussain\.warp\.mcp.json'
  )) {
    try { Read-Json $mcpPath | Out-Null; Add-Check 'PASS' ('mcp-json:' + (Split-Path $mcpPath -Leaf)) 'valid JSON' }
    catch { Add-Check 'FAIL' ('mcp-json:' + (Split-Path $mcpPath -Leaf)) $_.Exception.Message }
  }

  $fleetProfile = Read-Json (Join-Path $RegistryRoot 'registry\fleet-profile.json')
  $cursorDispatch = $fleetProfile.dispatchPolicy.cursor
  $cursorReadiness = Invoke-CursorCloudReadinessForPolicy -DispatchPolicy $cursorDispatch
  if ($cursorReadiness.policyDisabled) {
    $holdReason = [string]$cursorReadiness.policyReason
    Add-Check 'WARN' 'cursor-api-auth' "disabled by owner policy; no API request attempted: $holdReason"
    Add-Check 'WARN' 'cursor-models-list' 'disabled by owner policy; model availability was not checked'
    Add-Check 'WARN' 'cursor-background-launch' 'disabled by owner policy; do not launch or probe Cursor'
    Add-Check 'WARN' 'cursor-background-setup' 'disabled by owner policy; setup/run state was not checked'
  } else {
    if ($cursorReadiness.auth) {
      Add-Check 'PASS' 'cursor-api-auth' ('authenticated via ' + $cursorReadiness.keySource)
    } elseif ($cursorReadiness.keySource -eq 'missing') {
      Add-Check 'WARN' 'cursor-api-auth' 'Cursor API key is not present; live readiness checks were skipped'
    } else {
      Add-Check 'FAIL' 'cursor-api-auth' ($cursorReadiness.errors -join '; ')
    }
    if ($cursorReadiness.models.reachable) {
      Add-Check 'PASS' 'cursor-models-list' ('models endpoint reachable: ' + $cursorReadiness.models.endpoint + '; sample=' + $cursorReadiness.models.sampleCount)
    } elseif ($cursorReadiness.keySource -eq 'missing') {
      Add-Check 'WARN' 'cursor-models-list' 'Cursor API key is not present; model availability was not checked'
    } else {
      Add-Check 'FAIL' 'cursor-models-list' 'models endpoint unreachable'
    }
    if ($cursorReadiness.models.reachable) {
      Add-Check 'WARN' 'cursor-background-launch' 'Cursor does not expose documented spend headroom through the read-only API; launch readiness requires account billing evidence or a real authorized run'
    } elseif ($cursorReadiness.keySource -eq 'missing') {
      Add-Check 'WARN' 'cursor-background-launch' 'live launch readiness was not checked'
    } else {
      Add-Check 'FAIL' 'cursor-background-launch' 'models endpoint unavailable; launch headroom cannot be evaluated'
    }
    Add-Check 'WARN' 'cursor-background-setup' $cursorReadiness.setupReason
  }

  foreach ($wrapperTarget in @(
    'C:\Users\SaroshHussain\AppData\Local\Microsoft\WinGet\Links\agy.exe',
    'C:\Users\SaroshHussain\AppData\Local\cursor-agent\cursor-agent.cmd',
    'C:\Users\SaroshHussain\AppData\Local\devin\cli\bin\devin.exe',
    'C:\Users\SaroshHussain\AppData\Roaming\npm\copilot.cmd',
    'C:\Users\SaroshHussain\AppData\Roaming\npm\gemini.cmd'
  )) {
    if (Test-Path -LiteralPath $wrapperTarget -PathType Leaf) { Add-Check 'PASS' ('wrapper-target:' + (Split-Path $wrapperTarget -Leaf)) 'present' }
    else { Add-Check 'FAIL' ('wrapper-target:' + (Split-Path $wrapperTarget -Leaf)) $wrapperTarget }
  }

  $forbiddenFiles = @(Get-ChildItem -LiteralPath $RegistryRoot -File -Force -Recurse | Where-Object { $_.Name -match '^(\.env|auth\.json|secrets?\.json|credentials?\.json)$' })
  if ($forbiddenFiles.Count -eq 0) { Add-Check 'PASS' 'central-secrets' 'no secret-state filenames found' }
  else { Add-Check 'FAIL' 'central-secrets' ($forbiddenFiles.FullName -join ', ') }

  if ($WriteReport) {
    Write-Json (Join-Path $reportsRoot 'fleet-validation.json') ([pscustomobject]@{ generatedAt = (Get-Date).ToString('o'); results = $validationResults })
  }
  $validationResults | Format-Table -AutoSize
  $failures = @($validationResults | Where-Object status -eq 'FAIL')
  $warnings = @($validationResults | Where-Object status -eq 'WARN')
  Write-Host ("Validation summary: pass={0} warn={1} fail={2}" -f @($validationResults | Where-Object status -eq 'PASS').Count, $warnings.Count, $failures.Count)
  if ($failures.Count) { exit 1 }
}

switch ($Command) {
  'inventory' {
    $report = Save-InventoryReport
    $report.surfaces | Select-Object name, kind, version, lifecycle, readiness, executablePresent, configHomePresent | Format-Table -AutoSize
  }
  'evaluate' {
    New-EvaluationReport | Out-Null
    if ($WriteReport) { Write-Host "Wrote $(Join-Path $reportsRoot 'configuration-evaluation.md')" }
    else { Write-Host 'Evaluation completed. Re-run with -WriteReport to persist the report.' }
  }
  'generate' {
    New-GeneratedInstructions
    Get-DriftRows | Select-Object id, generatedPresent, destinationPresent, inSync | Format-Table -AutoSize
  }
  'sync' { Sync-Instructions }
  'validate' { Invoke-Validation }
  'drift' { Save-DriftReport | Select-Object id, inSync, destination | Format-Table -AutoSize }
  'cleanup' {
    $items = @(Save-CleanupReport)
    $items | Format-Table classification, path, bytes, action -AutoSize
    Write-Host "Cleanup candidates: $($items.Count); no files were deleted."
  }
}
