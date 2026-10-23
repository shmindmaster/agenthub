#Requires -Version 5.1
<# Synthetic fixtures only. No installed agent, login, gh call, or OneDrive
   write: every source root and both output paths point into a temp fixture,
   and -SkipGitHub -SkipProcesses -SkipMachineState keep the run offline. #>
[CmdletBinding()]
param([string]$ScriptPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ScriptPath) { $ScriptPath = Join-Path $repoRoot 'packages\fleet-board\Regenerate-FleetBoard.ps1' }
$failed = 0; $checked = 0
function Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:checked++
    if ($Passed) { Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name -- $Detail" }
}

$fixture = Join-Path $env:TEMP ('fleetboard fixture ' + [guid]::NewGuid().ToString('n'))
try {
    $goals = Join-Path $fixture 'goals\relaunch-2026-10-21'
    $codexPrograms = Join-Path $fixture 'codex\programs'
    $sessions = Join-Path $fixture 'codex-sessions'
    $dispatch = Join-Path $fixture 'dispatch'
    $leasePath = Join-Path $fixture 'lease\heavy-work.lease.json'
    $fleetProfilePath = Join-Path $fixture 'fleet-profile.json'
    $board = Join-Path $fixture 'out\FLEET-BOARD.md'
    $copy = Join-Path $fixture 'out\copy\FLEET-BOARD.md'
    foreach ($dir in @("$goals\programs\P-one", "$goals\programs\R-gated", "$goals\programs\S-empty", "$codexPrograms\Q-two", "$sessions\2026\10\21", $dispatch, (Split-Path -Parent $leasePath))) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    @'
# Program P-one STATUS
## 2099-01-01 00:00Z (TestBot)
- stale entry, must not win
## 2099-01-02 03:04Z (TestBot)
- DONE: fixture step complete.
- Rung: tested, not merged.
- Owner gate: needs Sarosh go-ahead to ship.
'@ | Set-Content -LiteralPath "$goals\programs\P-one\STATUS.md" -Encoding UTF8
    @'
# Program Q-two STATUS
## 2099-01-02 05:00Z (Codex)
- working on fixture.
- Rung: proposed.
'@ | Set-Content -LiteralPath "$codexPrograms\Q-two\STATUS.md" -Encoding UTF8
    @'
## 2099-01-01 00:00Z (TestBot)
- Owner gate: old gate must not appear.
## 2099-01-02 03:04Z (TestBot)
- Current status is ready.
- Owner gate: none.
'@ | Set-Content -LiteralPath "$goals\programs\R-gated\STATUS.md" -Encoding UTF8
    @'
## 2099-01-01 00:00Z (TestBot)
- Old status must not appear.
## 2099-01-02 03:04Z (TestBot)
'@ | Set-Content -LiteralPath "$goals\programs\S-empty\STATUS.md" -Encoding UTF8

    $rollout = Join-Path $sessions '2026\10\21\rollout-2026-10-21T00-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl'
    $rolloutLines = [Collections.Generic.List[string]]::new()
    $rolloutLines.Add('{"timestamp":"2026-10-21T00:00:00Z","type":"session_meta","payload":{"session_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","cwd":"C:\\fixture\\repo"}}')
    $rolloutLines.Add('{"timestamp":"2026-10-21T00:01:00Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture last answer"}]}}')
    for ($i = 0; $i -lt 65; $i++) {
        $rolloutLines.Add('{"timestamp":"2026-10-21T00:02:00Z","type":"event","payload":{"type":"tool_call"}}')
    }
    $rolloutLines | Set-Content -LiteralPath $rollout -Encoding UTF8
    (Get-Item -LiteralPath $rollout).LastWriteTime = Get-Date

    "fixture stdout`nsecond line" | Set-Content -LiteralPath (Join-Path $dispatch "$stamp-deadbeef-testhost.out") -Encoding UTF8
    '' | Set-Content -LiteralPath (Join-Path $dispatch "$stamp-deadbeef-testhost.err") -Encoding UTF8
    "cursor output" | Set-Content -LiteralPath (Join-Path $dispatch "$stamp-deadbeef-cursor-agent.out") -Encoding UTF8
    $yesterdayStamp = (Get-Date).AddDays(-1).ToString('yyyyMMdd-HHmmss')
    "completed after midnight" | Set-Content -LiteralPath (Join-Path $dispatch "$yesterdayStamp-cafebabe-qwen-code.out") -Encoding UTF8
    (Get-Item -LiteralPath (Join-Path $dispatch "$yesterdayStamp-cafebabe-qwen-code.out")).LastWriteTime = Get-Date

    '{"task":"fixture lease","chat":"fixture-chat","acquiredUtc":"2099-01-02T03:04:05Z","operation":"fixture op"}' |
        Set-Content -LiteralPath $leasePath -Encoding UTF8
    '{"dispatchPolicy":{"fixture-enabled":{"enabled":true},"fixture-disabled":{"enabled":false,"ownerAction":"fixture owner action","knownIssue":"fixture quota issue"}}}' |
        Set-Content -LiteralPath $fleetProfilePath -Encoding UTF8

    $args = @(
        '-NoProfile', '-File', $ScriptPath,
        '-GoalsRuntimeRoot', $goals, '-CodexProgramsRoot', $codexPrograms,
        '-CodexSessionsRoot', $sessions, '-DispatchLogRoot', $dispatch,
        '-LeasePath', $leasePath, '-FleetProfilePath', $fleetProfilePath,
        '-BoardPath', $board, '-BoardExportPath', $copy,
        '-SkipGitHub', '-SkipProcesses', '-SkipMachineState'
    )
    $out = & pwsh @args 2>&1
    Check 'script exits 0' ($LASTEXITCODE -eq 0) ($out | Out-String)
    Check 'board written' (Test-Path -LiteralPath $board)
    Check 'copy written' (Test-Path -LiteralPath $copy)
    $text = Get-Content -Encoding UTF8 -LiteralPath $board -Raw
    Check 'copy matches board' ((Get-Content -Encoding UTF8 -LiteralPath $copy -Raw) -eq $text)
    Check 'UTC and local header timestamps' ($text -match 'Header \(UTC\):' -and $text -match 'Header \(local\):')
    Check 'host snapshot section' ($text -match '## Host snapshot')
    Check 'lease holder in board' ($text -match 'fixture-chat')
    Check 'board table matches fleet-board format' ($text -match '\| Agent/host \| Program or task \| Status \| Rung \| Last update \| Log or status path \| Owner gate \|')
    Check 'latest heading wins' ($text -match '2099-01-02 03:04Z' -and $text -match 'DONE: fixture step complete')
    Check 'stale entry absent' ($text -notmatch 'stale entry, must not win')
    $emptyRow = @($text -split "`r?`n" | Where-Object { $_ -match '\| S-empty \|' })
    Check 'empty latest block has no invented status' ($emptyRow.Count -eq 1 -and $emptyRow[0] -match '\|  \|  \|')
    Check 'rung line carried' ($text -match 'tested, not merged')
    Check 'owner gate carried' ($text -match 'needs Sarosh go-ahead')
    Check 'resolved owner gate omitted' ($text -notmatch 'old gate must not appear' -and $text -notmatch '^\d+\. R-gated' )
    Check 'second program row' ($text -match 'Q-two')
    Check 'last rollout answer read beyond 60 records' ($text -match 'fixture last answer' -and $text -match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
    Check 'rollout is labelled recent, not active' ($text -match 'Not confirmed running; last response')
    Check 'dispatch row' ($text -match 'testhost')
    Check 'hyphenated dispatcher host preserved' ($text -match 'cursor-agent' -and $text -match 'qwen-code')
    Check 'dispatch completion date includes overnight run' ($text -match 'qwen-code')
    Check 'exit honesty' ($text -match 'exit code not recorded')
    Check 'dispatch policy section' ($text -match '## Dispatch policy' -and $text -match 'fixture-enabled' -and $text -match 'fixture-disabled')
    Check 'owner items section' ($text -match '## Owner items' -and $text -match 'fixture owner action')
    Check 'quota issue section' ($text -match '## Failed, quota-blocked, or paused' -and $text -match 'fixture quota issue')
    Check 'notes and row count sections' ($text -match '## Notes' -and $text -match 'Row count:')
    $scriptText = Get-Content -Encoding UTF8 -LiteralPath $ScriptPath -Raw
    Check 'no owner-specific OneDrive or profile paths' ($scriptText -notmatch 'D:\\OneDrive -|C:\\Users\\SaroshHussain' -and $scriptText -notmatch "'python'")
    Check 'default output stays in the local AgentHub runtime' ($scriptText -match 'AgentHub\\runtime\\fleet-board\\FLEET-BOARD\.md')
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "RESULT: $($checked - $failed) passed, $failed failed"
if ($failed -eq 0) { exit 0 }
exit 1
