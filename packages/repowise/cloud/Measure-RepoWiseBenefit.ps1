#Requires -Version 5.1
<#
.SYNOPSIS
  Compare a "native exploration" run and a "RepoWise context" run over the same
  task list, from recorded transcripts/logs. It never runs agents.

.DESCRIPTION
  Part of the AgentHub RepoWise cloud recipe (SH-4410); see
  docs/runbooks/repowise-cloud.md.

  INPUTS
  - A task list JSON file: three tasks per repository.
      { "repositories": [ { "alias": "<repo-alias>",
          "tasks": [ {"id": "<task-id>", "correctFile": "<path>"} ] } ] }
  - One log per mode (-NativeLogPath, -RepoWiseLogPath), in this JSONL format
    (one JSON object per line, one record per task attempt):
      {"repo":"<alias>","task":"<task-id>","tokensTotal":1234,"tokensCached":567,
       "toolCalls":12,"secondsToCorrectFile":34.5,"indexStale":false}
    tokensTotal INCLUDES cached tokens; tokensCached is reported separately.
    secondsToCorrectFile is null/absent when the run never reached the file.
    indexStale records whether the index was behind the repo's HEAD for that
    task (always false/irrelevant for native logs).

  OUTPUT
  A comparison table on stdout: per task, totals and deltas; optionally the
  same table appended to -OutFile.

.EXAMPLE
  pwsh -NoProfile -File Measure-RepoWiseBenefit.ps1 `
      -TaskListPath .\samples\benchmark\tasks.json `
      -NativeLogPath .\samples\benchmark\native.bench.txt `
      -RepoWiseLogPath .\samples\benchmark\repowise.bench.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskListPath,
    [Parameter(Mandatory)][string]$NativeLogPath,
    [Parameter(Mandatory)][string]$RepoWiseLogPath,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Read-BenchLog([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "log not found: $Path" }
    $records = @{}
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $record = $line | ConvertFrom-Json } catch { throw "log ${Path}:${lineNumber} is not JSON: $line" }
        foreach ($field in 'repo', 'task', 'tokensTotal', 'toolCalls') {
            if ($null -eq $record.$field) { throw "log ${Path}:${lineNumber} missing '$field'" }
        }
        $key = "$($record.repo)|$($record.task)"
        $records[$key] = $record
    }
    return $records
}

$tasksDoc = Get-Content -LiteralPath $TaskListPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $tasksDoc.repositories) { throw "task list has no repositories: $TaskListPath" }
$native = Read-BenchLog $NativeLogPath
$repowise = Read-BenchLog $RepoWiseLogPath

$rows = [Collections.Generic.List[object]]::new()
$missing = [Collections.Generic.List[string]]::new()
foreach ($repo in $tasksDoc.repositories) {
    foreach ($task in $repo.tasks) {
        $key = "$($repo.alias)|$($task.id)"
        $n = $native[$key]; $r = $repowise[$key]
        if (-not $n) { $missing.Add("$key (native)") }
        if (-not $r) { $missing.Add("$key (repowise)") }
        $rows.Add([pscustomobject][ordered]@{
            repo = $repo.alias; task = $task.id
            nativeTokens = if ($n) { [int]$n.tokensTotal } else { $null }
            rwTokens = if ($r) { [int]$r.tokensTotal } else { $null }
            tokensDeltaPct = if ($n -and $r -and $n.tokensTotal -gt 0) {
                [math]::Round((1 - $r.tokensTotal / $n.tokensTotal) * 100, 1) } else { $null }
            nativeCached = if ($n -and $null -ne $n.tokensCached) { [int]$n.tokensCached } else { $null }
            rwCached = if ($r -and $null -ne $r.tokensCached) { [int]$r.tokensCached } else { $null }
            nativeCalls = if ($n) { [int]$n.toolCalls } else { $null }
            rwCalls = if ($r) { [int]$r.toolCalls } else { $null }
            nativeToFileS = if ($n -and $null -ne $n.secondsToCorrectFile) { [double]$n.secondsToCorrectFile } else { 'missed' }
            rwToFileS = if ($r -and $null -ne $r.secondsToCorrectFile) { [double]$r.secondsToCorrectFile } else { 'missed' }
            indexStale = if ($r) { [bool]$r.indexStale } else { $null }
        })
    }
}

$widths = @{ repo = 14; task = 22; nativeTokens = 12; rwTokens = 10; tokensDeltaPct = 7
    nativeCached = 12; rwCached = 9; nativeCalls = 8; rwCalls = 7; nativeToFileS = 12; rwToFileS = 11; indexStale = 6 }
$header = 'repo'.PadRight($widths.repo) + 'task'.PadRight($widths.task) +
    'native tok'.PadLeft($widths.nativeTokens) + 'rw tok'.PadLeft($widths.rwTokens) +
    'delta%'.PadLeft($widths.tokensDeltaPct) + 'native cached'.PadLeft($widths.nativeCached) +
    'rw cached'.PadLeft($widths.rwCached) + 'n calls'.PadLeft($widths.nativeCalls) +
    'rw call'.PadLeft($widths.rwCalls) + 'native t->f'.PadLeft($widths.nativeToFileS) +
    'rw t->file'.PadLeft($widths.rwToFileS) + 'stale'.PadLeft($widths.indexStale)
$lines = [Collections.Generic.List[string]]::new()
$lines.Add($header)
$lines.Add('-' * $header.Length)
$fmt = { param($v, $w) ([string]($(if ($null -eq $v) { 'n/a' } else { $v }))).PadLeft($w) }
foreach ($row in $rows) {
    $lines.Add(
        ([string]$row.repo).PadRight($widths.repo) + ([string]$row.task).PadRight($widths.task) +
        (& $fmt $row.nativeTokens $widths.nativeTokens) + (& $fmt $row.rwTokens $widths.rwTokens) +
        (& $fmt $row.tokensDeltaPct $widths.tokensDeltaPct) + (& $fmt $row.nativeCached $widths.nativeCached) +
        (& $fmt $row.rwCached $widths.rwCached) + (& $fmt $row.nativeCalls $widths.nativeCalls) +
        (& $fmt $row.rwCalls $widths.rwCalls) + (& $fmt $row.nativeToFileS $widths.nativeToFileS) +
        (& $fmt $row.rwToFileS $widths.rwToFileS) + (& $fmt $row.indexStale $widths.indexStale))
}
$lines.Add('-' * $header.Length)
$nTokens = ($rows | Where-Object { $null -ne $_.nativeTokens } | Measure-Object nativeTokens -Sum).Sum
$rTokens = ($rows | Where-Object { $null -ne $_.rwTokens } | Measure-Object rwTokens -Sum).Sum
$lines.Add("TOTAL: native tokens=$nTokens  repowise tokens=$rTokens  delta=" + $(if ($nTokens) { [math]::Round((1 - $rTokens / $nTokens) * 100, 1).ToString() + '%' } else { 'n/a' }))
$staleCount = @($rows | Where-Object { $_.indexStale -eq $true }).Count
if ($staleCount) { $lines.Add("WARNING: $staleCount repowise run(s) ran against a stale index") }
foreach ($m in $missing) { $lines.Add("MISSING RECORD: $m") }
$text = $lines -join "`n"
Write-Host $text
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $text + "`n", [Text.UTF8Encoding]::new($false)) }
exit 0
