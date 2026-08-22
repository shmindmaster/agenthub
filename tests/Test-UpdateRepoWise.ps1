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
Report 'registers-named-task' ($raw -match 'AgentHub-Update-RepoWise') 'missing scheduled task name'

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f ($reported - $failures.Count), $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
