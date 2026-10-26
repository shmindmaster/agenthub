#Requires -Version 5.1
<#
Behavior tests for scripts/Remove-StaleAgentSessions.ps1 against a fixture tree.

Why: the script recycles coding-agent history across every host on the
machine. These tests prove the guards bite: a recent session, a Claude memory
folder, a -KeepPath file and a file held open all survive -Apply, while stale
sessions go to the Recycle Bin and stale SQLite rows are archived (flag set,
row kept, backup written) rather than deleted.

Same accumulate-and-report idiom as the other suites here; exit 1 on failure.
Windows only (Recycle Bin); skipped on other runners via tests/ci-skip.json.

Run: pwsh -NoProfile -File tests/Test-RemoveStaleAgentSessions.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repoRoot 'scripts\Remove-StaleAgentSessions.ps1'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$now = [datetime]'2026-10-26T12:00:00'
$old = $now.AddDays(-30)
$root = Join-Path ([IO.Path]::GetTempPath()) ("stale-sessions-test-" + [guid]::NewGuid().ToString('N'))
$h = Join-Path $root 'home'; $r = Join-Path $root 'roaming'; $l = Join-Path $root 'local'

function New-Fixture([string]$path, [datetime]$when) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    Set-Content -LiteralPath $path -Value 'x' -Encoding UTF8
    (Get-Item -LiteralPath $path).LastWriteTime = $when
}

$proj = "$h\.claude\projects\C--Repos-demo"
New-Fixture "$proj\aaaa.jsonl" $old
New-Fixture "$proj\aaaa\subagents\agent-1.jsonl" $old
New-Fixture "$proj\aaaa.desktop-released.json" $old
New-Fixture "$proj\bbbb.jsonl" $now.AddHours(-2)
New-Fixture "$proj\memory\MEMORY.md" $old
New-Fixture "$proj\memory\note.md" $old
New-Fixture "$h\.grok\sessions\C%3A%5CRepos\old-session\chat_history.jsonl" $old
New-Fixture "$h\.grok\sessions\C%3A%5CRepos\kept-session\updates.jsonl" $old
New-Fixture "$h\.grok\sessions\C%3A%5CRepos\locked-session\chat_history.jsonl" $old
New-Fixture "$h\.grok\sessions\C%3A%5CRepos\mixed-session\old.jsonl" $old
New-Fixture "$h\.grok\sessions\C%3A%5CRepos\mixed-session\new.jsonl" $now.AddDays(-1)
New-Fixture "$r\Code - Insiders\User\workspaceStorage\ws1\chatSessions\c1.json" $old
New-Fixture "$h\.claude\settings.json" $old
Get-ChildItem -LiteralPath $root -Recurse -Directory | ForEach-Object { $_.LastWriteTime = $old }
(Get-Item -LiteralPath $proj).LastWriteTime = $now

$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$db = "$h\.local\share\opencode\opencode.db"
if ($python) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $db) | Out-Null
    $oldMs = [int64]([DateTimeOffset]$old).ToUnixTimeMilliseconds()
    $newMs = [int64]([DateTimeOffset]$now).ToUnixTimeMilliseconds()
    $seed = "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('create table session(id text primary key, time_created int, time_updated int, time_archived int)'); c.executemany('insert into session values(?,?,?,null)', [('old',$oldMs,$oldMs),('new',$newMs,$newMs)]); c.commit()"
    & $python.Source -I -c $seed $db
}

$keep = "$h\.grok\sessions\C%3A%5CRepos\kept-session\updates.jsonl"
$common = @{ UserProfile = $h; AppData = $r; LocalAppData = $l; Now = $now; KeepPath = @($keep) }
$lock = $null
try {
    $dryManifest = Join-Path $root 'dry.json'
    & $script @common -ManifestPath $dryManifest *> $null
    $dry = Get-Content -LiteralPath $dryManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $byUnit = @{}; foreach ($u in $dry.units) { $byUnit[[string]$u.unit] = $u }
    Report 'dry run changes nothing' ((Test-Path "$proj\aaaa.jsonl") -and -not $dry.apply) 'dry run removed a file'
    Report 'stem grouping folds <id>.jsonl, <id>/ and <id>.*.json into one unit' (@($byUnit["$proj\aaaa"].paths).Count -eq 3) "paths: $($byUnit["$proj\aaaa"].paths -join ', ')"
    Report 'a stale unit is marked recycle' ($byUnit["$proj\aaaa"].action -eq 'recycle') $byUnit["$proj\aaaa"].action
    Report 'a recent unit is kept' ($byUnit["$proj\bbbb"].action -eq 'keep-recent') $byUnit["$proj\bbbb"].action
    Report 'Claude memory folders are never scanned' (-not $byUnit.ContainsKey("$proj\memory")) 'memory appeared as a unit'
    Report 'a -KeepPath inside a unit protects it' ($byUnit["$h\.grok\sessions\C%3A%5CRepos\kept-session"].action -eq 'skip-protected') 'kept-session not protected'
    Report 'one recent file keeps a whole session' ($byUnit["$h\.grok\sessions\C%3A%5CRepos\mixed-session"].action -eq 'keep-recent') 'mixed-session not kept'
    Report 'agent settings are outside every scanned root' (-not ($dry.units | Where-Object { $_.unit -like '*settings.json' })) 'settings.json was scanned'

    $lock = [IO.File]::Open("$h\.grok\sessions\C%3A%5CRepos\locked-session\chat_history.jsonl", 'Open', 'Read', 'None')
    $applyManifest = Join-Path $root 'apply.json'
    & $script @common -ManifestPath $applyManifest -Apply *> $null
    $lock.Dispose(); $lock = $null
    $applied = Get-Content -LiteralPath $applyManifest -Raw -Encoding UTF8 | ConvertFrom-Json

    Report 'apply recycles the stale Claude session and its folder' (-not (Test-Path "$proj\aaaa.jsonl") -and -not (Test-Path "$proj\aaaa")) 'aaaa survived'
    Report 'apply keeps the recent Claude session' (Test-Path "$proj\bbbb.jsonl") 'bbbb was removed'
    Report 'apply keeps MEMORY.md and the memory folder' ((Test-Path "$proj\memory\MEMORY.md") -and (Test-Path "$proj\memory\note.md")) 'memory touched'
    Report 'apply keeps the -KeepPath file' (Test-Path $keep) 'keep path removed'
    Report 'apply skips a session with a file held open' ((Test-Path "$h\.grok\sessions\C%3A%5CRepos\locked-session") -and @($applied.units | Where-Object { $_.action -eq 'skip-in-use' }).Count -eq 1) 'locked session removed or not reported'
    Report 'apply recycles a stale VS Code chat session' (-not (Test-Path "$r\Code - Insiders\User\workspaceStorage\ws1\chatSessions\c1.json")) 'chat session survived'
    Report 'apply leaves agent settings alone' (Test-Path "$h\.claude\settings.json") 'settings.json removed'

    if ($python) {
        $q = "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('select count(*), sum(time_archived is not null), sum(time_archived is null and time_updated >= $newMs) from session').fetchone())"
        $state = & $python.Source -I -c $q $db
        Report 'stale SQLite rows are archived, not deleted; recent rows untouched' ($state -eq '(2, 1, 1)') "state: $state"
        $rec = $applied.units | Where-Object { $_.kind -eq 'sqlite' }
        Report 'row archive writes a backup first' ($rec.backup -and (Test-Path -LiteralPath $rec.backup)) "backup: $($rec.backup)"
    }
    else { Write-Host 'SKIP: python not found; SQLite assertions not run' -ForegroundColor Yellow }

    $text = Get-Content -LiteralPath $script -Raw -Encoding UTF8
    Report 'the script never schedules itself' ($text -notmatch 'Register-ScheduledTask|schtasks') 'scheduling call found'
    Report 'the script never erases permanently' ($text -notmatch 'Remove-Item|DeletePermanently|\.Delete\(') 'permanent delete call found'
}
finally {
    if ($lock) { $lock.Dispose() }
    if (Test-Path -LiteralPath $root) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($root, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

Write-Host ''
Write-Host "RESULT: $passed passed, $($failures.Count) failed"
if ($failures.Count) { exit 1 }
exit 0
