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
    $board = Join-Path $fixture 'out\FLEET-BOARD.md'
    $copy = Join-Path $fixture 'out\copy\FLEET-BOARD.md'
    foreach ($dir in @("$goals\programs\P-one", "$codexPrograms\Q-two", "$sessions\2026\10\21", "$dispatch\briefs", (Split-Path -Parent $leasePath))) {
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

    $rollout = Join-Path $sessions '2026\10\21\rollout-2026-10-21T00-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl'
    @(
        '{"timestamp":"2026-10-21T00:00:00Z","type":"session_meta","payload":{"session_id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","cwd":"C:\\fixture\\repo"}}',
        '{"timestamp":"2026-10-21T00:01:00Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture last answer"}]}}'
    ) | Set-Content -LiteralPath $rollout -Encoding UTF8
    (Get-Item -LiteralPath $rollout).LastWriteTime = Get-Date

    "fixture stdout`nsecond line" | Set-Content -LiteralPath (Join-Path $dispatch "$stamp-deadbeef-testhost.out") -Encoding UTF8
    '' | Set-Content -LiteralPath (Join-Path $dispatch "$stamp-deadbeef-testhost.err") -Encoding UTF8
    'fixture brief' | Set-Content -LiteralPath (Join-Path $dispatch 'briefs\2099-01-02-testhost-thing.txt') -Encoding UTF8

    '{"task":"fixture lease","chat":"fixture-chat","acquiredUtc":"2099-01-02T03:04:05Z","operation":"fixture op"}' |
        Set-Content -LiteralPath $leasePath -Encoding UTF8

    $args = @(
        '-NoProfile', '-File', $ScriptPath,
        '-GoalsRuntimeRoot', $goals, '-CodexProgramsRoot', $codexPrograms,
        '-CodexSessionsRoot', $sessions, '-DispatchLogRoot', $dispatch,
        '-LeasePath', $leasePath, '-BoardPath', $board, '-BoardCopyPath', $copy,
        '-SkipGitHub', '-SkipProcesses', '-SkipMachineState'
    )
    $out = & pwsh @args 2>&1
    Check 'script exits 0' ($LASTEXITCODE -eq 0) ($out | Out-String)
    Check 'board written' (Test-Path -LiteralPath $board)
    Check 'copy written' (Test-Path -LiteralPath $copy)
    $text = Get-Content -LiteralPath $board -Raw
    Check 'copy matches board' ((Get-Content -LiteralPath $copy -Raw) -eq $text)
    Check 'header timestamp' ($text -match '\*\*Generated:\*\*')
    Check 'machine state section' ($text -match '## Machine state')
    Check 'lease holder in board' ($text -match 'fixture-chat')
    Check 'board table header' ($text -match '\| Agent/host \| Program or task \| Session or process id \| Status \| Rung \| Last update \| Log path \| Owner gates \|')
    Check 'latest heading wins' ($text -match '2099-01-02 03:04Z' -and $text -match 'DONE: fixture step complete')
    Check 'stale entry absent' ($text -notmatch 'stale entry, must not win')
    Check 'rung line carried' ($text -match 'tested, not merged')
    Check 'owner gate carried' ($text -match 'needs Sarosh go-ahead')
    Check 'second program row' ($text -match 'Q-two')
    Check 'rollout cwd row' ($text -match 'fixture.last.answer' -and $text -match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
    Check 'dispatch row' ($text -match 'testhost')
    Check 'exit honesty' ($text -match 'exit code not recorded')
    Check 'finished today section' ($text -match '## Finished today')
    Check 'owner actions section' ($text -match '## Owner actions pending')
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "RESULT: $($checked - $failed) passed, $failed failed"
exit ($failed -eq 0 ? 0 : 1)
