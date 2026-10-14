#Requires -Version 5.1
<#
Behavior tests for scripts/Update-RepoWise.ps1. The live PyPI/uv path is not
the test: injected versions prove behind/current/missing verdicts, and Apply
must call the upgrade command rather than report success while still behind.

Run: pwsh -NoProfile -File tests/Test-UpdateRepoWise.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repoRoot 'scripts\Update-RepoWise.ps1'
$hostExe = (Get-Process -Id $PID).Path

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

$stateFile = Join-Path $env:TEMP ('repowise-cli-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
function Invoke-Updater {
    param([string[]]$UpdaterArgs)
    $all = @('-StateFile', $stateFile) + $UpdaterArgs
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe -NoProfile -File $script @all 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

Report 'updater-script-exists' (Test-Path -LiteralPath $script) $script
$raw = Get-Content -LiteralPath $script -Raw -Encoding UTF8
Report 'sets-stop-eap' ($raw -match '(?m)^\$ErrorActionPreference\s*=\s*''Stop''') 'missing top-level Stop'

$behind = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', '0.39.0', '-LatestVersion', '0.44.0')
Report 'audit-behind-exits-1' ($behind.ExitCode -eq 1) "exit=$($behind.ExitCode) output=$($behind.Output)"
Report 'audit-behind-names-versions' (
    $behind.Output -match 'installed=0\.39\.0' -and $behind.Output -match 'latest=0\.44\.0' -and $behind.Output -match 'status=behind'
) $behind.Output

$current = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', '0.44.0', '-LatestVersion', '0.44.0')
Report 'audit-current-exits-0' ($current.ExitCode -eq 0) "exit=$($current.ExitCode) output=$($current.Output)"
Report 'audit-current-pass-line' ($current.Output -match 'PASS: RepoWise CLI is the PyPI latest') $current.Output

$missing = Invoke-Updater -UpdaterArgs @('-Audit', '-InstalledVersion', 'none', '-LatestVersion', '0.44.0')
Report 'audit-missing-exits-1' ($missing.ExitCode -eq 1) "exit=$($missing.ExitCode) output=$($missing.Output)"
Report 'audit-missing-status' ($missing.Output -match 'status=missing') $missing.Output

$scratch = Join-Path $env:TEMP ('repowise-uv-stub-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $scratch | Out-Null
$stub = Join-Path $scratch 'uv.cmd'
$log = Join-Path $scratch 'uv.log'
@(
    '@echo off'
    "echo uv-stub %*>> `"$log`""
    'exit /b 1'
) | Set-Content -LiteralPath $stub -Encoding ASCII

$applyBehind = Invoke-Updater -UpdaterArgs @(
    '-Apply', '-InstalledVersion', '0.39.0', '-LatestVersion', '0.44.0', '-UvExe', $stub
)
Report 'apply-behind-invokes-uv' (Test-Path -LiteralPath $log) 'uv stub was not executed'
$uvLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw -Encoding UTF8 } else { '' }
Report 'apply-behind-upgrade-not-install' ($uvLog -match 'tool upgrade repowise') $uvLog
Report 'apply-behind-fails-if-uv-fails' ($applyBehind.ExitCode -ne 0) "exit=$($applyBehind.ExitCode) output=$($applyBehind.Output)"
Report 'apply-behind-does-not-claim-current' ($applyBehind.Output -notmatch 'PASS: RepoWise CLI is now') $applyBehind.Output

Report 'does-not-pin-a-version-in-the-script' ($raw -notmatch '0\.44\.0') 'script hardcodes 0.44.0; latest must come from PyPI'
Report 'uses-uv-tool-upgrade' ($raw -match 'tool'', ''upgrade'', ''repowise') 'missing uv tool upgrade'

# Owner direction 2026-10-13: no scheduled agent jobs. The updater may only
# delete its retired task, never create one.
Report 'never-creates-a-scheduled-task' ($raw -notmatch '/Create|Register-ScheduledTask') 'updater still contains a task-creation path'
$register = Invoke-Updater -UpdaterArgs @('-RegisterSchedule')
Report 'register-schedule-is-refused' ($register.ExitCode -ne 0 -and $register.Output -match 'retired') "exit=$($register.ExitCode) output=$($register.Output)"

$schLog = Join-Path $scratch 'schtasks.log'
$schPresent = Join-Path $scratch 'schtasks-present.cmd'
$presenceFile = Join-Path $scratch 'present.flag'
Set-Content -LiteralPath $presenceFile -Value 'present' -Encoding ASCII
@(
    '@echo off'
    "echo %*>> `"$schLog`""
    "if not exist `"$presenceFile`" goto absent"
    "if /I `"%1`"==`"/Delete`" del `"$presenceFile`""
    'exit /b 0'
    ':absent'
    'echo ERROR: The system cannot find the file specified.'
    'exit /b 1'
) | Set-Content -LiteralPath $schPresent -Encoding ASCII
$removed = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schPresent)
$schText = if (Test-Path -LiteralPath $schLog) { Get-Content -LiteralPath $schLog -Raw -Encoding UTF8 } else { '' }
Report 'remove-schedule-deletes-named-task' ($removed.ExitCode -eq 0 -and $schText -match '/Delete /TN AgentHub-Update-RepoWise /F') "exit=$($removed.ExitCode) log=$schText output=$($removed.Output)"
Report 'remove-schedule-does-not-probe-pypi' ($removed.Output -notmatch 'installed=') $removed.Output

Remove-Item -LiteralPath $schLog -Force -ErrorAction SilentlyContinue
$schAbsent = Join-Path $scratch 'schtasks-absent.cmd'
@(
    '@echo off'
    "echo %*>> `"$schLog`""
    'echo ERROR: The system cannot find the file specified.'
    'exit /b 1'
) | Set-Content -LiteralPath $schAbsent -Encoding ASCII
$absent = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schAbsent)
$schText = if (Test-Path -LiteralPath $schLog) { Get-Content -LiteralPath $schLog -Raw -Encoding UTF8 } else { '' }
Report 'remove-schedule-absent-is-pass' ($absent.ExitCode -eq 0 -and $absent.Output -match 'absent') "exit=$($absent.ExitCode) output=$($absent.Output)"
Report 'remove-schedule-absent-skips-delete' ($schText -notmatch '/Delete') $schText

Remove-Item -LiteralPath $schLog -Force -ErrorAction SilentlyContinue
$schDenied = Join-Path $scratch 'schtasks-denied.cmd'
@('@echo off', "echo %*>> `"$schLog`"", 'echo ERROR: Access is denied.', 'exit /b 1') |
    Set-Content -LiteralPath $schDenied -Encoding ASCII
$denied = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schDenied)
Report 'query-access-denied-fails' ($denied.ExitCode -ne 0) $denied.Output
Report 'query-access-denied-never-claims-absent' ($denied.Output -notmatch 'PASS:.*absent') $denied.Output
$deniedLog = Get-Content -LiteralPath $schLog -Raw -Encoding UTF8
Report 'query-access-denied-skips-delete' ($deniedLog -notmatch '/Delete') $deniedLog

$notRemoved = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $stub)
Report 'query-unclassified-failure-is-not-absence' ($notRemoved.ExitCode -ne 0 -and $notRemoved.Output -notmatch 'PASS:.*absent') $notRemoved.Output

$schUnchanged = Join-Path $scratch 'schtasks-unchanged.cmd'
@('@echo off', 'exit /b 0') | Set-Content -LiteralPath $schUnchanged -Encoding ASCII
$unchanged = Invoke-Updater -UpdaterArgs @('-RemoveSchedule', '-SchtasksExe', $schUnchanged)
Report 'delete-success-with-task-still-present-fails' ($unchanged.ExitCode -ne 0 -and $unchanged.Output -notmatch 'PASS:.*removed') $unchanged.Output

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f ($reported - $failures.Count), $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
