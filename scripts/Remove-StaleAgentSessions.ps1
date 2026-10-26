#Requires -Version 5.1
<#
.SYNOPSIS
Find, and with -Apply recycle, coding-agent sessions whose last activity is
older than -Days, across every agent host installed on this machine.

.DESCRIPTION
Owner direction 2026-10-26: sessions older than seven days are not reused, so
they are removed from every coding agent. This script runs on demand only. It
registers no scheduled task and must not be scheduled (no repeating jobs).

A session is a "unit": one session directory, or the files that share a
session id stem (for example `<id>.jsonl`, `<id>/` and `<id>.settings.json`).
Its last activity is the newest write time of anything inside it. A unit is
removed only when all of the following hold:

  * last activity is older than the cutoff (now minus -Days);
  * no file in it is held open by a running process (exclusive-open probe);
  * it contains no protected path (Claude `memory\` folders, any MEMORY.md,
    and every -KeepPath).

Removal of files goes to the Windows Recycle Bin, never a permanent erase.
Sessions that are rows in a SQLite store (Cursor composers, OpenCode, Codex
threads) are never deleted: when the owning app is not running, the rows are
backed up to JSON next to the manifest and the app's own archived flag is set
(scripts/agent_session_db.py). When the app is running they are skipped.

Settings, auth, credentials, config, skills, plugins and MCP configuration are
never scanned: only the session roots listed in Get-SessionStores are.

Without -Apply the run is a dry run. Either way a JSON manifest of every unit
and its decision is written under %LOCALAPPDATA%\AgentHub\session-cleanup.

.EXAMPLE
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1            # dry run, 7 days
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1 -Apply     # recycle / archive
pwsh -NoProfile -File scripts\Remove-StaleAgentSessions.ps1 -Days 14 -Agent cursor,opencode
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)][int]$Days = 7,
    [switch]$Apply,
    [string[]]$Agent,
    [string]$ManifestPath,
    [string[]]$KeepPath = @(
        (Join-Path $env:LOCALAPPDATA 'AgentHub\takeover-20261026\grok-sessions\01a175ab-89e6-75b0-8e60-a2d5d9b4922b\updates.jsonl')
    ),
    # Test seams: point the stores at a fixture tree and pin the clock.
    [string]$UserProfile = $env:USERPROFILE,
    [string]$AppData = $env:APPDATA,
    [string]$LocalAppData = $env:LOCALAPPDATA,
    [datetime]$Now = (Get-Date),
    [switch]$IgnoreRunningApps
)

$ErrorActionPreference = 'Stop'
$cutoff = $Now.AddDays(-$Days)
$cutoffMs = [int64]([DateTimeOffset]$cutoff).ToUnixTimeMilliseconds()
$stamp = $Now.ToString('yyyyMMdd-HHmmss')
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $LocalAppData "AgentHub\session-cleanup\manifest-$stamp.json"
}
$outDir = Split-Path -Parent $ManifestPath
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Get-SessionStores {
    $h = $UserProfile; $r = $AppData
    $codeFlavors = @('Code', 'Code - Insiders', 'Cursor', 'Windsurf', 'Antigravity', 'VSCodium')
    $stores = [Collections.Generic.List[object]]::new()
    function Add([string]$a, [string]$label, [string]$containers, [string[]]$exclude = @()) {
        $stores.Add([pscustomobject]@{ Agent = $a; Store = $label; Kind = 'files'; Containers = $containers; Exclude = $exclude })
    }
    function AddDb([string]$a, [string]$label, [string]$store, [string]$db, [string[]]$process) {
        $stores.Add([pscustomobject]@{ Agent = $a; Store = $label; Kind = 'sqlite'; DbStore = $store; Db = $db; Process = $process })
    }

    # Claude Code CLI. Claude Desktop's session list is app-managed: archive it there.
    Add 'claude-code' 'projects transcripts' "$h\.claude\projects\*" @('memory', 'MEMORY.md')
    foreach ($s in 'file-history', 'session-env', 'shell-snapshots', 'todos', 'debug') {
        Add 'claude-code' $s "$h\.claude\$s"
    }
    Add 'codex' 'rollouts' "$h\.codex\sessions\*\*\*"
    Add 'codex' 'archived rollouts' "$h\.codex\archived_sessions"
    AddDb 'codex' 'threads (state_5.sqlite)' 'codex' "$h\.codex\state_5.sqlite" @('codex')
    Add 'grok' 'sessions' "$h\.grok\sessions\*"
    Add 'cursor' 'agent transcripts' "$h\.cursor\projects\*\agent-transcripts"
    Add 'cursor' 'agent tool output' "$h\.cursor\projects\*\agent-tools"
    Add 'cursor' 'cli chats' "$h\.cursor\chats\*"
    AddDb 'cursor' 'composers (state.vscdb)' 'cursor' "$r\Cursor\User\globalStorage\state.vscdb" @('Cursor')
    foreach ($f in $codeFlavors) {
        $id = ($f -replace '[^A-Za-z]', '').ToLowerInvariant()
        Add $id 'chat sessions' "$r\$f\User\workspaceStorage\*\chatSessions"
        Add $id 'chat editing sessions' "$r\$f\User\workspaceStorage\*\chatEditingSessions"
        Add $id 'empty-window chat sessions' "$r\$f\User\globalStorage\emptyWindowChatSessions"
        foreach ($ext in 'saoudrizwan.claude-dev', 'rooveterinaryinc.roo-cline', 'kilocode.kilo-code') {
            $a = @{ 'saoudrizwan.claude-dev' = 'cline'; 'rooveterinaryinc.roo-cline' = 'roo'; 'kilocode.kilo-code' = 'kilo' }[$ext]
            Add $a "tasks ($f)" "$r\$f\User\globalStorage\$ext\tasks"
            Add $a "checkpoints ($f)" "$r\$f\User\globalStorage\$ext\checkpoints"
        }
    }
    Add 'cline' 'cli sessions' "$h\.cline\data\sessions"
    Add 'cline' 'cli tasks' "$h\.cline\tasks"
    Add 'copilot-cli' 'session-state' "$h\.copilot\session-state" @('.session-operation-locks')
    Add 'factory-droid' 'sessions' "$h\.factory\sessions\*"
    Add 'opencode' 'tool output' "$h\.local\share\opencode\tool-output"
    AddDb 'opencode' 'sessions (opencode.db)' 'opencode' "$h\.local\share\opencode\opencode.db" @('opencode')
    Add 'gemini-cli' 'chats' "$h\.gemini\tmp\*\chats"
    Add 'gemini-cli' 'tool outputs' "$h\.gemini\tmp\*\tool-outputs"
    foreach ($g in 'antigravity', 'antigravity-cli', 'antigravity-ide') {
        foreach ($s in 'conversations', 'brain', 'annotations', 'browser_recordings', 'html_artifacts') {
            Add 'antigravity' "$g $s" "$h\.gemini\$g\$s"
        }
    }
    Add 'windsurf' 'cascade' "$h\.codeium\windsurf\cascade"
    Add 'windsurf' 'brain' "$h\.codeium\windsurf\brain"
    Add 'amp' 'thread pointers' "$h\.local\share\amp\last-threads"
    Add 'qwen-code' 'chats' "$h\.qwen\tmp\*\chats"
    Add 'continue' 'sessions' "$h\.continue\sessions"
    return $stores
}

function Test-Protected([string]$path) {
    if ($path -match '\\\.claude\\projects\\[^\\]+\\memory(\\|$)') { return $true }
    if ((Split-Path -Leaf $path) -ieq 'MEMORY.md') { return $true }
    foreach ($k in $KeepPath) {
        if ($k -and ($path -ieq $k -or $k.StartsWith($path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase))) { return $true }
    }
    return $false
}

function Test-InUse([IO.FileInfo[]]$files) {
    foreach ($f in $files) {
        try { $s = [IO.File]::Open($f.FullName, 'Open', 'Read', 'None'); $s.Dispose() }
        catch [IO.IOException] { return $true }
        catch { }
    }
    return $false
}

function Get-FileUnits($store) {
    $containers = @(Get-Item -Path $store.Containers -Force -ErrorAction SilentlyContinue | Where-Object PSIsContainer)
    foreach ($c in $containers) {
        $children = Get-ChildItem -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue |
            Where-Object { $store.Exclude -notcontains $_.Name }
        foreach ($g in ($children | Group-Object { ($_.Name -split '\.', 2)[0] })) {
            $items = @($g.Group)
            $files = @($items | ForEach-Object {
                if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue } else { $_ }
            })
            $stamps = @($items | ForEach-Object LastWriteTime) + @($files | ForEach-Object LastWriteTime)
            [pscustomobject]@{
                Unit         = Join-Path $c.FullName $g.Name
                Paths        = @($items | ForEach-Object FullName)
                Files        = $files
                LastActivity = ($stamps | Measure-Object -Maximum).Maximum
                Bytes        = [int64](($files | Measure-Object Length -Sum).Sum)
            }
        }
    }
}

function Send-ToRecycleBin([string]$path) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    if (Test-Path -LiteralPath $path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
    elseif (Test-Path -LiteralPath $path) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

function Get-Python {
    foreach ($n in 'python', 'python3', 'py') {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

$helper = Join-Path $PSScriptRoot 'agent_session_db.py'
$python = Get-Python
$records = [Collections.Generic.List[object]]::new()
$stores = Get-SessionStores | Where-Object { -not $Agent -or $Agent -contains $_.Agent }

foreach ($store in $stores) {
    if ($store.Kind -eq 'files') {
        foreach ($u in @(Get-FileUnits $store)) {
            $action = 'keep-recent'
            if ($u.LastActivity -lt $cutoff) {
                if (@($u.Paths | Where-Object { Test-Protected $_ }).Count -or @($u.Files | Where-Object { Test-Protected $_.FullName }).Count) { $action = 'skip-protected' }
                elseif (Test-InUse $u.Files) { $action = 'skip-in-use' }
                else { $action = 'recycle' }
            }
            $result = $null
            if ($Apply -and $action -eq 'recycle') {
                try { foreach ($p in $u.Paths) { Send-ToRecycleBin $p }; $result = 'recycled' }
                catch { $result = "error: $($_.Exception.Message)" }
            }
            $records.Add([pscustomobject]@{
                agent = $store.Agent; store = $store.Store; kind = 'files'; unit = $u.Unit; paths = $u.Paths
                lastActivity = $u.LastActivity.ToString('o'); bytes = $u.Bytes; files = $u.Files.Count
                action = $action; result = $result
            })
        }
        continue
    }

    # SQLite row store.
    $rec = [ordered]@{ agent = $store.Agent; store = $store.Store; kind = 'sqlite'; unit = $store.Db; rows = $null; staleRows = $null; action = $null; result = $null; backup = $null }
    if (-not (Test-Path -LiteralPath $store.Db)) { continue }
    if (-not $python) { $rec.action = 'skip-no-python'; $records.Add([pscustomobject]$rec); continue }
    $running = @(Get-Process -Name $store.Process -ErrorAction SilentlyContinue)
    $count = & $python -I $helper --store $store.DbStore --db $store.Db --cutoff-ms $cutoffMs | ConvertFrom-Json
    $rec.rows = $count.total; $rec.staleRows = $count.stale
    if ($count.stale -eq 0) { $rec.action = 'keep-recent' }
    elseif ($running.Count -and -not $IgnoreRunningApps) { $rec.action = 'skip-app-running' }
    else { $rec.action = 'archive-rows' }
    if ($Apply -and $rec.action -eq 'archive-rows') {
        $rec.backup = Join-Path $outDir "$($store.DbStore)-rows-backup-$stamp.json"
        $done = & $python -I $helper --store $store.DbStore --db $store.Db --cutoff-ms $cutoffMs --apply --backup $rec.backup | ConvertFrom-Json
        $rec.result = if ($LASTEXITCODE -eq 0) { "archived $($done.archived) rows" } else { "error: helper exit $LASTEXITCODE" }
    }
    $records.Add([pscustomobject]$rec)
}

$summary = foreach ($g in ($records | Group-Object agent | Sort-Object Name)) {
    $files = @($g.Group | Where-Object kind -eq 'files')
    $old = @($files | Where-Object action -ne 'keep-recent')
    $gone = @($files | Where-Object result -eq 'recycled')
    $db = @($g.Group | Where-Object kind -eq 'sqlite')
    [pscustomobject]@{
        Agent        = $g.Name
        Sessions     = $files.Count
        Older        = $old.Count
        MB           = [math]::Round((($files | Measure-Object bytes -Sum).Sum) / 1MB, 1)
        OlderMB      = [math]::Round((($old | Measure-Object bytes -Sum).Sum) / 1MB, 1)
        Recycled     = $gone.Count
        Skipped      = @($old | Where-Object { $_.action -like 'skip-*' -or $_.result -like 'error*' }).Count
        DbRows       = ($db | Measure-Object rows -Sum).Sum
        DbStaleRows  = ($db | Measure-Object staleRows -Sum).Sum
        DbAction     = (@($db | ForEach-Object { if ($_.result) { $_.result } else { $_.action } }) -join '; ')
    }
}

$manifest = [ordered]@{
    generatedAt = $Now.ToString('o'); days = $Days; cutoff = $cutoff.ToString('o'); apply = [bool]$Apply
    summary = @($summary); units = $records
} | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($ManifestPath, $manifest, [Text.UTF8Encoding]::new($false))

$summary | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
Write-Host ("{0}: manifest {1}" -f $(if ($Apply) { 'APPLIED' } else { 'DRY RUN (pass -Apply to recycle/archive)' }), $ManifestPath)
