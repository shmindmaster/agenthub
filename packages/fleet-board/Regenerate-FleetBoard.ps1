#Requires -Version 5.1
<#
Regenerate-FleetBoard.ps1 -- rebuilds FLEET-BOARD.md from configured sources.

Capability-invoked: run it when a board refresh is wanted. It registers no
scheduled task, Run key, or auto-start service, opens no window, and takes no
keyboard focus.

Sources are configurable parameters. Defaults, when available, are user-local:
  - Program STATUS.md files under $GoalsRuntimeRoot\programs\* and
    $CodexProgramsRoot\* (latest dated heading and its Rung line)
  - Codex rollouts $CodexSessionsRoot\**\*.jsonl (first-line session_meta cwd;
    last assistant output_text)
  - Dispatcher logs $DispatchLogRoot\*.out completed today (host, start, exit
    evidence -- the dispatcher records no exit-code sidecar)
  - `gh pr list --state open` for each repo in $Repositories
  - The heavy-work lease JSON at $LeasePath
  - Running processes named in $ProcessNames, with start times

Output defaults to the AgentHub runtime. Export to another location only by
passing -BoardExportPath explicitly.
#>
[CmdletBinding()]
param(
    [string]$GoalsRuntimeRoot = '',
    [string]$CodexProgramsRoot = '',
    [string]$CodexSessionsRoot = (Join-Path $HOME '.codex\sessions'),
    [string]$DispatchLogRoot = '',
    [string]$LeasePath = '',
    [string]$FleetProfilePath = '',
    [string]$BoardPath = '',
    [string]$BoardExportPath = '',
    [string[]]$Repositories = @(),
    [string[]]$ProcessNames = @('codex', 'claude', 'grok', 'agy', 'droid', 'cline', 'gemini', 'cursor-agent', 'amp', 'copilot'),
    [switch]$SkipGitHub,
    [switch]$SkipProcesses,
    [switch]$SkipMachineState
)
$ErrorActionPreference = 'Stop'

# The AgentHub runtime lives under the OS local-data root: %LOCALAPPDATA% on
# Windows, ~/Library/Application Support on macOS, ~/.local/share on Linux.
$localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
if ([string]::IsNullOrWhiteSpace($localData)) {
    throw 'Could not resolve the OS local-data directory for the default runtime output path.'
}
if ([string]::IsNullOrWhiteSpace($GoalsRuntimeRoot)) { $GoalsRuntimeRoot = Join-Path $localData 'AgentHub\runtime\goals' }
if ([string]::IsNullOrWhiteSpace($DispatchLogRoot)) { $DispatchLogRoot = Join-Path $localData 'AgentHub\runtime\coding-agent-dispatch' }
if ([string]::IsNullOrWhiteSpace($BoardPath)) { $BoardPath = Join-Path $localData 'AgentHub\runtime\fleet-board\FLEET-BOARD.md' }
if ([string]::IsNullOrWhiteSpace($FleetProfilePath)) {
    $candidateRoot = $env:AGENTHUB_ROOT
    if ($candidateRoot -and (Test-Path -LiteralPath (Join-Path $candidateRoot 'registry\fleet-profile.json'))) {
        $FleetProfilePath = Join-Path $candidateRoot 'registry\fleet-profile.json'
    } else {
        $candidateRoot = $PSScriptRoot
        while ($candidateRoot) {
            $candidate = Join-Path $candidateRoot 'registry\fleet-profile.json'
            if (Test-Path -LiteralPath $candidate) { $FleetProfilePath = $candidate; break }
            $parent = Split-Path -Parent $candidateRoot
            if (-not $parent -or $parent -eq $candidateRoot) { break }
            $candidateRoot = $parent
        }
    }
}
$now = Get-Date
$nowUtc = $now.ToUniversalTime()
$today = $now.Date
$offset = $now.ToString('zzz')
$warnings = [Collections.Generic.List[string]]::new()

function Compress-Cell([string]$Text, [int]$Max = 200) {
    if ($null -eq $Text) { return '' }
    $t = ($Text -replace '\s+', ' ').Trim() -replace '\|', '\|'
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 1).TrimEnd() + '…' }
    return $t
}

# --- STATUS.md programs -------------------------------------------------
$ownerGatePattern = 'owner|sarosh|blocked|go-ahead|go or no-go|authoriz|needs his|waiting on owner'
$statusRows = [Collections.Generic.List[object]]::new()
foreach ($root in @((Join-Path $GoalsRuntimeRoot 'programs'), $CodexProgramsRoot) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($statusFile in Get-ChildItem -LiteralPath $root -Recurse -Filter STATUS.md -File) {
        $program = Split-Path -Leaf (Split-Path -Parent $statusFile.FullName)
        $lines = @(Get-Content -Encoding UTF8 -LiteralPath $statusFile.FullName)
        $headingIdx = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^#{2,4}\s.*20\d\d-\d\d-\d\d') { $headingIdx += $i }
        }
        $heading = if ($headingIdx.Count) { ($lines[$headingIdx[-1]] -replace '^#+\s*', '').Trim() } else { 'no dated heading' }
        if ($headingIdx.Count) {
            $start = $headingIdx[-1] + 1
            $block = if ($start -lt $lines.Count) { @($lines[$start..($lines.Count - 1)]) } else { @() }
        } else {
            $block = @($lines)
        }
        $rung = ($block | Where-Object { $_ -match 'Rung' } | Select-Object -First 1)
        $status = ($block | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        $gates = @($block | Where-Object {
            $_ -match $ownerGatePattern -and
            $_ -notmatch '(?i)owner gate\s*:\s*(none|resolved|complete|completed)\b|^\s*[-*]\s*(none|resolved|complete|completed)\b'
        } | Select-Object -First 3)
        $statusRows.Add([pscustomobject]@{
            Agent   = $program
            Task    = "STATUS.md program '$program'"
            Id      = 'not recorded'
            Status  = Compress-Cell $status 160
            Rung    = Compress-Cell $rung 160
            Updated = $heading
            LogPath = $statusFile.FullName
            Gates   = Compress-Cell ($gates -join ' / ') 220
        })
    }
}

# --- Codex rollouts -------------------------------------------------------
$sessionCwd = @{}
$rolloutRows = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $CodexSessionsRoot) {
    $rollouts = @(Get-ChildItem -LiteralPath $CodexSessionsRoot -Recurse -Filter *.jsonl -File |
        Where-Object { $_.LastWriteTime -ge $today })
    foreach ($file in $rollouts) {
        $sessionId = if ($file.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $Matches[1] } else { $file.BaseName }
        $cwd = ''; $lastAssistant = ''
        try {
            $first = Get-Content -Encoding UTF8 -LiteralPath $file.FullName -TotalCount 1
            $meta = $first | ConvertFrom-Json
            $cwd = [string]$meta.payload.cwd
        } catch {
            $warnings.Add("Unreadable Codex rollout metadata in $($file.Name).")
        }
        $reader = [IO.StreamReader]::new($file.FullName)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                try {
                    $item = $line | ConvertFrom-Json
                    if ($item.payload.role -eq 'assistant') {
                        $text = @($item.payload.content | Where-Object { $_.type -eq 'output_text' } | ForEach-Object { [string]$_.text }) -join ' '
                        if ($text) { $lastAssistant = $text }
                    }
                } catch {
                    $warnings.Add("Unreadable Codex rollout record in $($file.Name).")
                }
            }
        } finally {
            $reader.Dispose()
        }
        if ($cwd) { $sessionCwd[$sessionId] = $cwd }
        $rolloutRows.Add([pscustomobject]@{
            Agent   = 'Codex (recent)'
            Task    = "Recent session $sessionId; cwd $cwd"
            Id      = "session $sessionId"
            Status  = Compress-Cell ("Not confirmed running; last response: " + $lastAssistant) 160
            Rung    = ''
            Updated = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ' local'
            LogPath = $file.FullName
            Gates   = ''
        })
    }
}

# --- Dispatcher logs from today -------------------------------------------
$dispatchRows = [Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $DispatchLogRoot) {
    $outs = @(Get-ChildItem -LiteralPath $DispatchLogRoot -Filter '*.out' -File |
        Where-Object { $_.LastWriteTime -ge $today })
    foreach ($f in $outs) {
        if ($f.BaseName -notmatch '^(?<date>\d{8})-(?<time>\d{6})-(?<id>[0-9a-fA-F]{8})-(?<host>.+)$') {
            $warnings.Add("Unrecognized dispatcher log filename: $($f.Name).")
            continue
        }
        $dispatchHost = $Matches.host
        $start = '{0}:{1}' -f $f.Name.Substring(9, 2), $f.Name.Substring(11, 2)
        $errPath = [IO.Path]::ChangeExtension($f.FullName, '.err')
        $errSize = if (Test-Path -LiteralPath $errPath) { (Get-Item -LiteralPath $errPath).Length } else { 0 }
        $exit = if ($errSize -gt 0) { "stderr written ($errSize bytes); exit code not recorded" } else { 'no stderr; exit code not recorded' }
        $dispatchRows.Add([pscustomobject]@{
            Start = $start; Host = $dispatchHost; Task = 'not recorded'
            Output = Compress-Cell (Get-Content -Encoding UTF8 -LiteralPath $f.FullName -TotalCount 4 -ErrorAction SilentlyContinue | Out-String) 140
            Exit = $exit
        })
    }
}

# --- Lease -----------------------------------------------------------------
$leaseLine = 'not checked (no lease path configured)'
if (-not [string]::IsNullOrWhiteSpace($LeasePath) -and (Test-Path -LiteralPath $LeasePath)) {
    try {
        $lease = Get-Content -Encoding UTF8 -LiteralPath $LeasePath -Raw | ConvertFrom-Json
        $acquired = [string]$lease.acquiredUtc
        $acquiredLocal = try { ([DateTimeOffset]::Parse($acquired)).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } catch { '' }
        $acquired = try { ([DateTimeOffset]::Parse($acquired, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime.ToString('yyyy-MM-dd HH:mm\Z') } catch { $acquired }
        $leaseLine = "``$($lease.chat)``, task `"$($lease.task)`", acquired $acquired ($acquiredLocal local). Operation: $($lease.operation)"
    } catch {
        $leaseLine = "lease file unreadable: $($_.Exception.Message)"
        $warnings.Add('The configured heavy-work lease could not be read.')
    }
} elseif (-not [string]::IsNullOrWhiteSpace($LeasePath)) {
    $leaseLine = 'checked absent'
}

# --- Machine state -----------------------------------------------------------
$ramLine = 'not checked (SkipMachineState)'
$gpuLine = 'not checked (SkipMachineState)'
$procLine = 'not checked (SkipProcesses)'
if (-not $SkipMachineState) {
    if ($env:OS -eq 'Windows_NT') {
        $os = Get-CimInstance Win32_OperatingSystem
        $freeGiB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $totalGiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $ramSource = 'Win32_OperatingSystem'
    } elseif (Test-Path -LiteralPath '/proc/meminfo') {
        $meminfo = @{}
        foreach ($line in [IO.File]::ReadAllLines('/proc/meminfo')) {
            if ($line -match '^(\w+):\s+(\d+)\s+kB') { $meminfo[$Matches[1]] = [double]$Matches[2] }
        }
        $freeGiB = [math]::Round($meminfo['MemAvailable'] / 1MB, 2)
        $totalGiB = [math]::Round($meminfo['MemTotal'] / 1MB, 2)
        $ramSource = '/proc/meminfo MemAvailable'
    } else {
        # macOS: free + inactive pages from vm_stat, total from sysctl.
        $pageSize = 4096; $pages = 0
        foreach ($line in @(& vm_stat 2>$null)) {
            if ($line -match 'page size of (\d+) bytes') { $pageSize = [int]$Matches[1] }
            if ($line -match '^Pages (free|inactive|speculative):\s+(\d+)') { $pages += [double]$Matches[2] }
        }
        $freeGiB = [math]::Round($pages * $pageSize / 1GB, 2)
        $totalGiB = [math]::Round([double](& sysctl -n hw.memsize 2>$null) / 1GB, 2)
        $ramSource = 'vm_stat free+inactive'
    }
    $ramLine = "Free RAM: $freeGiB GiB of $totalGiB GiB ($ramSource). The heavy-work gate is 4 GiB."
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        $raw = & $smi.Source --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>$null
        $gpuLine = "GPU: $raw"
    } else { $gpuLine = 'GPU: nvidia-smi not found' }
}
if (-not $SkipProcesses) {
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $ProcessNames -contains $_.ProcessName.ToLowerInvariant() })
    if ($procs.Count) {
        $parts = @($procs | Sort-Object ProcessName, Id | ForEach-Object {
            $started = try { $_.StartTime.ToString('HH:mm') } catch { 'unknown' }
            "$($_.ProcessName) (PID $($_.Id), started $started)"
        })
        $procLine = $parts -join '; '
    } else { $procLine = 'none of the watched process names are running' }
}

# --- Open PRs ---------------------------------------------------------------
$prLines = [Collections.Generic.List[string]]::new()
if (-not $SkipGitHub -and $Repositories.Count -gt 0) {
    foreach ($repo in $Repositories) {
        $json = gh pr list --repo $repo --state open --json number,title,isDraft,updatedAt --limit 50 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { $prLines.Add("- ${repo}: gh query failed"); continue }
        $prs = @($json | ConvertFrom-Json)
        if ($prs.Count -eq 0) { $prLines.Add("- ${repo}: none") }
        else {
            $items = @($prs | ForEach-Object { "#{0} ({1}{2})" -f $_.number, $(if ($_.isDraft) { 'draft, ' } else { '' }), (Compress-Cell $_.title 60) })
            $prLines.Add("- ${repo}: " + ($items -join ', '))
        }
    }
}

# --- Dispatcher policy -------------------------------------------------------
$enabledHosts = [Collections.Generic.List[string]]::new()
$disabledHosts = [Collections.Generic.List[string]]::new()
$policyOwnerActions = [Collections.Generic.List[string]]::new()
$failureNotes = [Collections.Generic.List[string]]::new()
$fleetPolicyState = 'not checked (fleet profile not found)'
if ($FleetProfilePath -and (Test-Path -LiteralPath $FleetProfilePath -PathType Leaf)) {
    try {
        $fleetProfile = Get-Content -LiteralPath $FleetProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $fleetProfile.dispatchPolicy.PSObject.Properties) {
            $id = [string]$property.Name
            $entry = $property.Value
            if ($entry.enabled -eq $true) {
                $enabledHosts.Add($id)
            } elseif ($entry.enabled -eq $false) {
                $disabledHosts.Add($id)
                if ($entry.ownerAction) { $policyOwnerActions.Add("$id`: $($entry.ownerAction)") }
            } else {
                $disabledHosts.Add("$id (enabled state not established)")
            }
            if ($entry.knownIssue) { $failureNotes.Add("$id`: $($entry.knownIssue)") }
            elseif ($entry.reason -match '(?i)failed|quota|paused|timed out|no response') {
                $failureNotes.Add("$id`: $($entry.reason)")
            }
        }
        $fleetPolicyState = 'loaded'
    } catch {
        $fleetPolicyState = 'unreadable'
        $warnings.Add("Could not read dispatcher policy from $([IO.Path]::GetFileName($FleetProfilePath)).")
    }
}

# --- Owner actions -----------------------------------------------------------
$ownerActions = [Collections.Generic.List[string]]::new()
foreach ($row in $statusRows) {
    if ($row.Gates) { $ownerActions.Add(("{0}: {1}" -f $row.Agent, $row.Gates)) }
}
foreach ($action in $policyOwnerActions) { $ownerActions.Add($action) }
if (-not $SkipGitHub -and $Repositories.Count -gt 0) {
    $openCount = @($prLines | Where-Object { $_ -match '#' }).Count
    if ($openCount) { $ownerActions.Add('Open PRs awaiting merge/review decisions; see the Open PRs section.') }
}
if ($ownerActions.Count -eq 0) { $ownerActions.Add('none detected in sources') }
foreach ($row in $statusRows) {
    if ($row.Status -match '(?i)failed|quota|paused|blocked') {
        $failureNotes.Add("$($row.Agent): $($row.Status)")
    }
}
if ($failureNotes.Count -eq 0) { $failureNotes.Add('none recorded in configured sources') }

# --- Compose -----------------------------------------------------------------
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('# FLEET BOARD')
$lines.Add('')
$lines.Add("Header (UTC): $($nowUtc.ToString('yyyy-MM-dd HH:mm'))")
$lines.Add("Header (local): $($now.ToString('yyyy-MM-dd HH:mm')) (UTC$offset)")
$lines.Add('Regenerated by: packages/fleet-board/Regenerate-FleetBoard.ps1.')
$lines.Add('')
$lines.Add('## Host snapshot')
$lines.Add('')
$lines.Add("- $ramLine")
$lines.Add("- $gpuLine")
$lines.Add("- Heavy-work lease: $leaseLine")
$lines.Add("- Running coding-host processes: $procLine")
$lines.Add('')
$lines.Add('## Agent table')
$lines.Add('')
$lines.Add('| Agent/host | Program or task | Status | Rung | Last update | Log or status path | Owner gate |')
$lines.Add('|---|---|---|---|---|---|---|')
foreach ($row in @($statusRows) + @($rolloutRows)) {
    $lines.Add("| $($row.Agent) | $($row.Task) | $($row.Status) | $($row.Rung) | $($row.Updated) | ``$($row.LogPath)`` | $($row.Gates) |")
}
$lines.Add('')
$lines.Add('## Dispatch policy (registry: fleet-profile.json -> dispatchPolicy)')
$lines.Add('')
$enabledText = if ($enabledHosts.Count) { $enabledHosts -join ', ' } else { 'none' }
$disabledText = if ($disabledHosts.Count) { $disabledHosts -join ', ' } else { 'none' }
$lines.Add("- Enabled: $enabledText")
$lines.Add("- Disabled: $disabledText")
$lines.Add("- Policy source: $fleetPolicyState")
$lines.Add('')
$lines.Add('## Finished today')
$lines.Add('')
$lines.Add('| Dispatch start (local) | Host | Task | Output head | Exit evidence |')
$lines.Add('|---|---|---|---|---|')
if ($dispatchRows.Count -eq 0) { $lines.Add('| none today | | | | |') }
foreach ($d in $dispatchRows) { $lines.Add("| $($d.Start) | $($d.Host) | $(Compress-Cell $d.Task 60) | $($d.Output) | $($d.Exit) |") }
$lines.Add('')
$lines.Add('## Open PRs (GitHub)')
$lines.Add('')
foreach ($l in $prLines) { $lines.Add($l) }
if ($prLines.Count -eq 0) {
    $lines.Add($(if ($SkipGitHub -or $Repositories.Count -eq 0) { '(not checked: no repositories configured or GitHub skipped)' } else { '(none found)' }))
}
$lines.Add('')
$lines.Add('## Owner items')
$lines.Add('')
$i = 0
foreach ($a in $ownerActions) { $i++; $lines.Add("$i. $a") }
$lines.Add('')
$lines.Add('## Failed, quota-blocked, or paused')
$lines.Add('')
foreach ($note in $failureNotes) { $lines.Add("- $note") }
$lines.Add('')
$lines.Add('## Notes')
$lines.Add('')
if ($warnings.Count) {
    foreach ($warning in $warnings) { $lines.Add("- $warning") }
} else {
    $lines.Add('- No source-read warnings.')
}
$lines.Add('')
$lines.Add("Row count: $(@($statusRows).Count + @($rolloutRows).Count).")

$text = ($lines -join "`r`n")
$targets = [Collections.Generic.List[string]]::new()
$targets.Add($BoardPath)
if (-not [string]::IsNullOrWhiteSpace($BoardExportPath) -and
    [IO.Path]::GetFullPath($BoardExportPath) -ne [IO.Path]::GetFullPath($BoardPath)) {
    $targets.Add($BoardExportPath)
}
foreach ($target in $targets) {
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    [IO.File]::WriteAllText($target, $text, [Text.UTF8Encoding]::new($false))
}
foreach ($target in $targets) { Write-Output "wrote $target" }
