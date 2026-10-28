#Requires -Version 5.1
<#
.SYNOPSIS
Reports RAM per coding-agent host, duplicate MCP/helper processes and
leftovers, for the moment the machine feels slow.

.DESCRIPTION
Owner direction 2026-10-28: memory problems keep coming back, and the cause is
process sprawl, not one bad process. Measured that day (docs/ops/
host-memory-audit-2026-10-28.md): five Claude Code CLIs at about 650 MB private
each, a Codex desktop app that grew from 5.3 to 8.8 GB working set in 20
minutes because every loaded thread and every nested app-server started its own
copy of every stdio MCP server, and Playwright CLI daemons that outlived the
commands that started them.

Check-LocalMcpInstancing.ps1 covers servers registered in registry/mcps.json.
This script covers what that one cannot see: host totals, unregistered
helpers started per session (aws-mcp, Codex plugin servers, Desktop Commander),
processes whose launcher has exited, and the headroom left for the macOS VM.

Read-only. It runs on demand only: no scheduled task, no Run key, no service.
Command lines are never printed, only the class each one matched.

.EXAMPLE
pwsh -NoProfile -File scripts\Get-HostMemoryReport.ps1
pwsh -NoProfile -File scripts\Get-HostMemoryReport.ps1 -VmGuestMB 10240 -Json
#>
[CmdletBinding()]
param(
    # Guest RAM of the VM the owner wants to start next; 0 skips the headroom line.
    [int]$VmGuestMB = 10240,
    # VMware overhead plus a host floor, added on top of the guest size.
    [int]$VmReserveMB = 1800,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# (command-line regex, class). First match wins; order matters.
$classes = @(
    @('repowise_bridge\.py', 'mcp:repowise-bridge'),
    @('shared_server\.py|repowise.* --port 7339', 'shared:repowise-server'),
    @('uvicorn service:app .*8790', 'shared:local-ai-retrieve'),
    @('desktop-commander', 'mcp:desktop-commander'),
    @('mcp-proxy-for-aws', 'mcp:aws-mcp-proxy'),
    @('data-analytics|\./mcp/launch\.mjs', 'mcp:codex-data-analytics'),
    @('launch_codex_app_tools_mcp|\./server\.mjs', 'mcp:codex-app-tools'),
    @('unified-computer-use|node_repl\.exe|codex-computer-use', 'mcp:codex-computer-use'),
    @('codex\.exe.*app-server', 'codex:app-server'),
    @('cliDaemon\.js', 'leftover-candidate:playwright-cli-daemon'),
    @('claude-code\\[\d.]+\\[0-9a-f]+\\claude\.exe', 'claude:cli-session'),
    @('-NoExit -Command "try \{ if \(\$ExecutionContext', 'claude:terminal-panel-shell'),
    @('windows-mcp', 'mcp:windows-mcp'),
    @('copilot\.exe', 'copilot:cli'),
    @('vmware-vmx', 'vm:vmware-vmx')
)

function Get-Class([string]$text) {
    foreach ($c in $classes) { if ($text -match $c[0]) { return $c[1] } }
    return $null
}

$procs = @{}
foreach ($w in Get-CimInstance Win32_Process) {
    $procs[[int]$w.ProcessId] = $w
}

function Get-OwningHost([int]$procId) {
    $seen = 0
    while ($procs.ContainsKey($procId) -and $seen -lt 40) {
        $w = $procs[$procId]
        $t = "$($w.ExecutablePath) $($w.CommandLine)"
        if ($t -match 'WindowsApps\\Claude_') { return 'Claude desktop' }
        if ($t -match 'OpenAI\.Codex_') { return 'Codex desktop' }
        if ($w.Name -match '^(copilot|WindowsTerminal)\.exe$') { return 'Copilot CLI / Terminal' }
        if ($w.Name -eq 'Cursor.exe') { return 'Cursor' }
        if ($w.Name -eq 'Code - Insiders.exe') { return 'VS Code Insiders' }
        if ($w.Name -eq 'chrome.exe' -and $t -notmatch '--type=') {
            return $(if ($t -match '--user-data-dir') { 'Chrome (automation)' } else { 'Chrome' })
        }
        if ($w.Name -eq 'vmware-authd.exe') { return 'VMware' }
        if ([int]$w.ParentProcessId -eq $procId) { break }
        $procId = [int]$w.ParentProcessId; $seen++
    }
    return $null
}

$rows = foreach ($w in $procs.Values) {
    $cls = Get-Class "$($w.ExecutablePath) $($w.CommandLine)"
    $hostName = Get-OwningHost ([int]$w.ProcessId)
    if ($cls -like 'shared:*') { $hostName = 'Shared (detached by design)' }
    [pscustomobject]@{
        Pid = [int]$w.ProcessId; Name = $w.Name; Class = $cls
        Host = $(if ($hostName) { $hostName } else { 'other/system' })
        WsMB = [math]::Round($w.WorkingSetSize / 1MB, 1)
        PrivMB = [math]::Round(([double]$w.PrivatePageCount) / 1MB, 1)
        Orphan = -not $procs.ContainsKey([int]$w.ParentProcessId)
        Session = [int]$w.SessionId
    }
}

$mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
$summary = [ordered]@{
    taken = (Get-Date).ToString('s')
    processes = @($rows).Count
    availableMB = [int]$mem.AvailableMBytes
    committedMB = [math]::Round($mem.CommittedBytes / 1MB)
    commitLimitMB = [math]::Round($mem.CommitLimit / 1MB)
}

$byHost = $rows | Group-Object Host | ForEach-Object {
    [pscustomobject]@{ Host = $_.Name; Count = $_.Count
        WsMB = [math]::Round(($_.Group | Measure-Object WsMB -Sum).Sum)
        PrivMB = [math]::Round(($_.Group | Measure-Object PrivMB -Sum).Sum) }
} | Sort-Object WsMB -Descending

# A class is a duplicate when more than one top-level instance runs. Launcher
# chains (uvx -> uv -> python) count once: only processes whose parent is not
# in the same class are instances.
$byClass = $rows | Where-Object Class | Group-Object Class | ForEach-Object {
    $members = $_.Group
    $pids = @{}; foreach ($m in $members) { $pids[$m.Pid] = $true }
    $instances = @($members | Where-Object { -not $pids.ContainsKey([int]$procs[$_.Pid].ParentProcessId) }).Count
    [pscustomobject]@{ Class = $_.Name; Instances = $instances; Processes = $_.Count
        WsMB = [math]::Round(($members | Measure-Object WsMB -Sum).Sum)
        PrivMB = [math]::Round(($members | Measure-Object PrivMB -Sum).Sum) }
} | Sort-Object WsMB -Descending

$singleExpected = 'shared:repowise-server', 'shared:local-ai-retrieve', 'mcp:desktop-commander'
$flags = @()
foreach ($c in $byClass) {
    if ($c.Class -like 'mcp:*' -and $c.Class -ne 'mcp:repowise-bridge' -and $c.Instances -gt 1) {
        $flags += "DUPLICATE  $($c.Class): $($c.Instances) instances, $($c.WsMB) MB WS (policy: one shared process, started on demand)"
    }
    if ($c.Class -in $singleExpected -and $c.Instances -gt 1) {
        $flags += "DUPLICATE  $($c.Class): $($c.Instances) instances of a single-process server"
    }
    if ($c.Class -eq 'codex:app-server' -and $c.Instances -gt 1) {
        $flags += "SPRAWL     Codex has $($c.Instances) app-servers; each starts its own MCP set"
    }
    if ($c.Class -eq 'claude:cli-session' -and $c.Instances -gt 2) {
        $flags += "SESSIONS   $($c.Instances) Claude Code CLIs resident ($($c.WsMB) MB WS); archive finished sessions"
    }
}
$hosts = @($byHost | Where-Object { $_.Host -in 'Claude desktop', 'Codex desktop', 'Copilot CLI / Terminal', 'Cursor', 'VS Code Insiders' })
if ($hosts.Count -gt 1) {
    $flags += "HOSTS      $($hosts.Count) coding hosts running ($((($hosts | ForEach-Object Host) -join ', '))); policy is one at a time"
}
foreach ($r in $rows | Where-Object { $_.Orphan -and $_.Session -ne 0 -and $_.Class -and $_.Class -notlike 'shared:*' }) {
    $flags += "LEFTOVER   $($r.Class) pid $($r.Pid): launcher exited, $($r.WsMB) MB WS"
}
if ($VmGuestMB -gt 0) {
    $need = $VmGuestMB + $VmReserveMB
    $vmUp = [bool]($rows | Where-Object Class -eq 'vm:vmware-vmx')
    if (-not $vmUp) {
        $verdict = $(if ($summary.availableMB -ge $need) { 'OK to start' } else { "short by $($need - $summary.availableMB) MB" })
        $flags += "VM         need $need MB available to start a $VmGuestMB MB guest; have $($summary.availableMB) MB: $verdict"
    }
}

if ($Json) {
    [ordered]@{ summary = $summary; hosts = $byHost; classes = $byClass; flags = $flags } | ConvertTo-Json -Depth 4
    return
}
"Available {0} MB · committed {1}/{2} MB · {3} processes · {4}" -f $summary.availableMB, $summary.committedMB, $summary.commitLimitMB, $summary.processes, $summary.taken
''
$byHost | Format-Table -AutoSize | Out-String -Width 160
$byClass | Format-Table -AutoSize | Out-String -Width 160
if ($flags) { $flags } else { 'No duplicates, leftovers or extra hosts found.' }
