#Requires -Version 5.1
<#
Regenerate-FleetBoard.ps1 -- rebuilds FLEET-BOARD.md from live sources.

Capability-invoked: run it when a board refresh is wanted. It registers no
scheduled task, Run key, or auto-start service, opens no window, and takes no
keyboard focus.

Sources (all roots are parameters; defaults are the live fleet paths):
  - Program STATUS.md files under $GoalsRuntimeRoot\programs\* and
    $CodexProgramsRoot\* (latest dated heading and its Rung line)
  - Codex rollouts $CodexSessionsRoot\**\*.jsonl (first-line session_meta cwd;
    last assistant output_text)
  - Dispatcher logs $DispatchLogRoot\*.out written today (host, start, exit
    evidence -- the dispatcher records no exit-code sidecar)
  - `gh pr list --state open` for each repo in $Repositories
  - The heavy-work lease JSON at $LeasePath
  - Running processes named in $ProcessNames, with start times

Outputs: $BoardPath and a copy at $BoardCopyPath (default:
$GoalsRuntimeRoot\FLEET-BOARD.md).
#>
[CmdletBinding()]
param(
    [string]$GoalsRuntimeRoot = 'C:\Users\SaroshHussain\AppData\Local\AgentHub\runtime\goals\relaunch-2026-10-21',
    [string]$CodexProgramsRoot = 'D:\OneDrive - MahumTech\Documents\Codex\2026-10-21\programs',
    [string]$CodexSessionsRoot = 'C:\Users\SaroshHussain\.codex\sessions',
    [string]$DispatchLogRoot = 'C:\Users\SaroshHussain\AppData\Local\AgentHub\runtime\coding-agent-dispatch',
    [string]$LeasePath = 'D:\OneDrive - MahumTech\Documents\Codex\2026-10-21\can\outputs\claude-takeover\heavy-work.lease.json',
    [string]$BoardPath = 'D:\OneDrive - MahumTech\Documents\06_Research_and_Knowledge_Base\FLEET-BOARD.md',
    [string]$BoardCopyPath = '',
    [string[]]$Repositories = @(
        'shmindmaster/agenthub', 'shmindmaster/local-ai-platform',
        'shmindmaster/abacare', 'shmindmaster/rexa', 'shmindmaster/saroshhussain',
        'musa-dev-team/duckie-app', 'musa-dev-team/duckie-deploy'
    ),
    [string[]]$ProcessNames = @('codex', 'claude', 'grok', 'agy', 'droid', 'cline', 'gemini', 'python'),
    [switch]$SkipGitHub,
    [switch]$SkipProcesses,
    [switch]$SkipMachineState
)
$ErrorActionPreference = 'Stop'

if (-not $BoardCopyPath) { $BoardCopyPath = Join-Path $GoalsRuntimeRoot 'FLEET-BOARD.md' }
$now = Get-Date
$nowUtc = $now.ToUniversalTime()
$today = $now.Date
$offset = $now.ToString('zzz')

function Compress-Cell([string]$Text, [int]$Max = 200) {
    if ($null -eq $Text) { return '' }
    $t = ($Text -replace '\s+', ' ').Trim() -replace '\|', '\|'
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 1).TrimEnd() + '…' }
    return $t
}

# --- STATUS.md programs -------------------------------------------------
$ownerGatePattern = 'owner|sarosh|blocked|go-ahead|go or no-go|authoriz|needs his|waiting on owner'
$statusRows = [Collections.Generic.List[object]]::new()
foreach ($root in @((Join-Path $GoalsRuntimeRoot 'programs'), $CodexProgramsRoot)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($statusFile in Get-ChildItem -LiteralPath $root -Recurse -Filter STATUS.md -File) {
        $program = Split-Path -Leaf (Split-Path -Parent $statusFile.FullName)
        $lines = @(Get-Content -LiteralPath $statusFile.FullName)
        $headingIdx = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^#{2,4}\s.*20\d\d-\d\d-\d\d') { $headingIdx += $i }
        }
        $heading = if ($headingIdx.Count) { ($lines[$headingIdx[-1]] -replace '^#+\s*', '').Trim() } else { 'no dated heading' }
        $end = if ($headingIdx.Count) { $lines.Count } else { 0 }
        $start = if ($headingIdx.Count) { $headingIdx[-1] + 1 } else { 0 }
        $block = @($lines[$start..($end - 1)])
        $rung = ($block | Where-Object { $_ -match 'Rung' } | Select-Object -First 1)
        $status = ($block | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        $gates = @($lines | Where-Object { $_ -match $ownerGatePattern } | Select-Object -First 3)
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
            $first = Get-Content -LiteralPath $file.FullName -TotalCount 1
            $meta = $first | ConvertFrom-Json
            $cwd = [string]$meta.payload.cwd
        } catch { }
        try {
            foreach ($line in @(Get-Content -LiteralPath $file.FullName -Tail 60)) {
                $item = $line | ConvertFrom-Json
                if ($item.payload.role -eq 'assistant') {
                    $text = @($item.payload.content | Where-Object { $_.type -eq 'output_text' } | ForEach-Object { [string]$_.text }) -join ' '
                    if ($text) { $lastAssistant = $text }
                }
            }
        } catch { }
        if ($cwd) { $sessionCwd[$sessionId] = $cwd }
        $rolloutRows.Add([pscustomobject]@{
            Agent   = 'Codex (rollout)'
            Task    = "cwd $cwd"
            Id      = "session $sessionId"
            Status  = Compress-Cell $lastAssistant 160
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
        Where-Object { $_.Name -match ('^' + $today.ToString('yyyyMMdd') + '-') })
    foreach ($f in $outs) {
        $dispatchHost = ($f.BaseName -split '-')[-1]
        $start = '{0}:{1}' -f $f.Name.Substring(9, 2), $f.Name.Substring(11, 2)
        $errPath = [IO.Path]::ChangeExtension($f.FullName, '.err')
        $errSize = if (Test-Path -LiteralPath $errPath) { (Get-Item -LiteralPath $errPath).Length } else { 0 }
        $exit = if ($errSize -gt 0) { "stderr written ($errSize bytes); exit code not recorded" } else { 'no stderr; exit code not recorded' }
        $briefGuess = ''
        $briefDir = Join-Path $DispatchLogRoot 'briefs'
        if (Test-Path -LiteralPath $briefDir) {
            $briefGuess = @(Get-ChildItem -LiteralPath $briefDir -File | Where-Object { $_.Name -match $today.ToString('yyyy-MM-dd') -and $_.Name -match $dispatchHost } | Select-Object -First 1 -ExpandProperty Name)
        }
        $dispatchRows.Add([pscustomobject]@{
            Start = $start; Host = $dispatchHost; Task = [string]$briefGuess
            Output = Compress-Cell (Get-Content -LiteralPath $f.FullName -TotalCount 4 -ErrorAction SilentlyContinue | Out-String) 140
            Exit = $exit
        })
    }
}

# --- Lease -----------------------------------------------------------------
$leaseLine = 'no lease file found'
if (Test-Path -LiteralPath $LeasePath) {
    try {
        $lease = Get-Content -LiteralPath $LeasePath -Raw | ConvertFrom-Json
        $acquired = [string]$lease.acquiredUtc
        $acquiredLocal = try { ([DateTimeOffset]::Parse($acquired)).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } catch { '' }
        $acquired = try { ([DateTimeOffset]::Parse($acquired, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)).UtcDateTime.ToString('yyyy-MM-dd HH:mm\Z') } catch { $acquired }
        $leaseLine = "``$($lease.chat)``, task `"$($lease.task)`", acquired $acquired ($acquiredLocal local). Operation: $($lease.operation)"
    } catch { $leaseLine = "lease file unreadable: $($_.Exception.Message)" }
}

# --- Machine state -----------------------------------------------------------
$ramLine = 'not checked (SkipMachineState)'
$gpuLine = 'not checked (SkipMachineState)'
$procLine = 'not checked (SkipProcesses)'
if (-not $SkipMachineState) {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeGiB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $totalGiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $ramLine = "Free RAM: $freeGiB GiB of $totalGiB GiB (Win32_OperatingSystem). The heavy-work gate is 4 GiB."
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        $raw = & $smi.Source --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>$null
        $gpuLine = "GPU: $raw"
    } else { $gpuLine = 'GPU: nvidia-smi not found' }
}
if (-not $SkipProcesses) {
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $ProcessNames -contains $_.ProcessName.ToLowerInvariant() })
    if ($procs.Count) {
        $parts = @($procs | Group-Object { $_.ProcessName.ToLowerInvariant() } | Sort-Object Name | ForEach-Object {
            $g = $_.Group
            $pids = ($g | ForEach-Object Id | Sort-Object) -join ', '
            $starts = @($g | Where-Object StartTime | ForEach-Object { $_.StartTime } | Sort-Object)
            $started = if ($starts.Count) { '{0} to {1}' -f $starts[0].ToString('HH:mm'), $starts[-1].ToString('HH:mm') } else { 'unknown' }
            "$($_.Name) x$($g.Count) (PIDs $pids, started $started)"
        })
        $procLine = $parts -join '; '
    } else { $procLine = 'none of the watched process names are running' }
}

# --- Open PRs ---------------------------------------------------------------
$prLines = [Collections.Generic.List[string]]::new()
if (-not $SkipGitHub) {
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

# --- Owner actions -----------------------------------------------------------
$ownerActions = [Collections.Generic.List[string]]::new()
foreach ($row in $statusRows) {
    if ($row.Gates) { $ownerActions.Add(("{0}: {1}" -f $row.Agent, $row.Gates)) }
}
if (-not $SkipGitHub) {
    $openCount = @($prLines | Where-Object { $_ -match '#' }).Count
    if ($openCount) { $ownerActions.Add('Open PRs awaiting merge/review decisions; see the Open PRs section.') }
}
if ($ownerActions.Count -eq 0) { $ownerActions.Add('none detected in sources') }

# --- Compose -----------------------------------------------------------------
$lines = [Collections.Generic.List[string]]::new()
$lines.Add("# FLEET BOARD: agents working for Sarosh, $($now.ToString('yyyy-MM-dd'))")
$lines.Add('')
$lines.Add("**Generated:** $($now.ToString('yyyy-MM-dd HH:mm')) (UTC$offset; $($nowUtc.ToString('HH:mm'))Z). Regenerated by packages/fleet-board/Regenerate-FleetBoard.ps1.")
$lines.Add('')
$lines.Add('**Rule:** every program appends to its own STATUS.md after each step; this board is regenerated from those files.')
$lines.Add('')
$lines.Add('**Rung ladder:** merged to dev, then in main, then deployed, then production-verified. "Proposed" and "tested" sit below the ladder.')
$lines.Add('')
$lines.Add("## Machine state ($($now.ToString('HH:mm')))")
$lines.Add('')
$lines.Add("- **$ramLine**")
$lines.Add("- **$gpuLine**")
$lines.Add("- **Heavy lease:** $leaseLine. File: ``$LeasePath``.")
$lines.Add("- **Processes:** $procLine")
$lines.Add('')
$lines.Add('## Agent board')
$lines.Add('')
$lines.Add('| Agent/host | Program or task | Session or process id | Status | Rung | Last update | Log path | Owner gates |')
$lines.Add('|---|---|---|---|---|---|---|---|')
foreach ($row in @($statusRows) + @($rolloutRows)) {
    $lines.Add("| $($row.Agent) | $($row.Task) | $($row.Id) | $($row.Status) | $($row.Rung) | $($row.Updated) | ``$($row.LogPath)`` | $($row.Gates) |")
}
$lines.Add('')
$lines.Add('## Finished today')
$lines.Add('')
$lines.Add('### Fleet dispatches (local start; output; exit)')
$lines.Add('')
$lines.Add('| Dispatch (local) | Host | Task | Output head | Exit |')
$lines.Add('|---|---|---|---|---|')
if ($dispatchRows.Count -eq 0) { $lines.Add('| none today | | | | |') }
foreach ($d in $dispatchRows) { $lines.Add("| $($d.Start) | $($d.Host) | $(Compress-Cell $d.Task 60) | $($d.Output) | $($d.Exit) |") }
$lines.Add('')
$lines.Add('## Open PRs (GitHub)')
$lines.Add('')
foreach ($l in $prLines) { $lines.Add($l) }
if ($prLines.Count -eq 0) { $lines.Add('(skipped)') }
$lines.Add('')
$lines.Add('## Owner actions pending')
$lines.Add('')
$i = 0
foreach ($a in $ownerActions) { $i++; $lines.Add("$i. $a") }
$lines.Add('')

$text = ($lines -join "`r`n")
foreach ($target in @($BoardPath, $BoardCopyPath)) {
    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    [IO.File]::WriteAllText($target, $text, [Text.UTF8Encoding]::new($false))
}
Write-Output "wrote $BoardPath"
Write-Output "wrote $BoardCopyPath"
