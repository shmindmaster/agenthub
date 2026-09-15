#Requires -Version 5.1
<#
Aggregate test runner: discovers and runs every tests/Test-*.ps1 file, every
packages/*/tests/*.ps1 package validator, and every packages/**/*.test.mjs
Node test file with node --test. It aggregates their results and exits
non-zero if any of them fail.

Fails loudly if it discovers zero test files -- a green runner that ran
nothing is precisely the failure mode this task exists to prevent (this
project's defining defect, restated one level up).

Each tests/Test-*.ps1 file follows the accumulate-and-report idiom (ends
with "RESULT: N passed, M failed" and a matching exit code); each
packages/*/tests/*.ps1 validator ends with a single PASS: line and exit 0,
or throws and exits non-zero. Node test files are run with `node --test`
and report an N-passed/M-failed summary on stdout. All are run as child
processes under the appropriate executable, so `pwsh tests/Run-AllTests.ps1`
runs PowerShell tests under pwsh and Node tests under node.

Run: pwsh -NoProfile -File tests/Run-AllTests.ps1
     powershell.exe -NoProfile -File tests/Run-AllTests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testsDir = Join-Path $repoRoot 'tests'
$packagesDir = Join-Path $repoRoot 'packages'
$hostExe = (Get-Process -Id $PID).Path

$testFiles = @(
    Get-ChildItem -LiteralPath $testsDir -File -Filter 'Test-*.ps1' |
        Sort-Object Name |
        ForEach-Object FullName
)
$validatorFiles = @(
    Get-ChildItem -LiteralPath $packagesDir -Recurse -File -Filter 'validate-plugin.ps1' -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object FullName
)
$nodeTestFiles = @(
    Get-ChildItem -LiteralPath $packagesDir -Recurse -File -Filter '*.test.mjs' -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object FullName
)
$allFiles = @($testFiles + $validatorFiles + $nodeTestFiles)

if ($allFiles.Count -eq 0) {
    Write-Host 'FAIL: Run-AllTests.ps1 discovered zero test files under tests/Test-*.ps1, packages/*/tests/validate-plugin.ps1, or packages/**/*.test.mjs. A runner that ran nothing is not a passing test suite.' -ForegroundColor Red
    exit 1
}

Write-Host "Discovered $($testFiles.Count) test file(s), $($validatorFiles.Count) package validator(s), and $($nodeTestFiles.Count) Node test file(s)."
Write-Host ''

$results = [Collections.Generic.List[object]]::new()
$totalPassed = 0
$totalFailed = 0

foreach ($file in $allFiles) {
    $relative = $file.Substring($repoRoot.Length).TrimStart('\', '/')
    Write-Host "=== $relative ===" -ForegroundColor Cyan
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($file -like '*.test.mjs') {
            $output = & node --test $file 2>&1 | Out-String
        } else {
            $output = & $hostExe -NoProfile -File $file 2>&1 | Out-String
        }
    } finally {
        $ErrorActionPreference = $previousEap
    }
    $exitCode = $LASTEXITCODE
    Write-Host $output.TrimEnd()

    $filePassed = 0
    $fileFailed = 0
    if ($output -match 'RESULT:\s*(\d+)\s*passed,\s*(\d+)\s*failed') {
        $filePassed = [int]$Matches[1]
        $fileFailed = [int]$Matches[2]
    } elseif ($output -match '(?m)^\s*(?:\S{1,4}\s+)?pass\s+(\d+)\s*$') {
        # Node test runner summary line only ("ℹ pass N" spec reporter or "# pass N"
        # TAP reporter; the glyph may arrive re-encoded), anchored to the line so a
        # test name such as "bypass 10" cannot be mistaken for the total.
        $filePassed = [int]$Matches[1]
        if ($output -match '(?m)^\s*(?:\S{1,4}\s+)?fail\s+(\d+)\s*$') {
            $fileFailed = [int]$Matches[1]
        }
    } elseif ($exitCode -eq 0) {
        # Package validators (validate-plugin.ps1) report a single PASS: line
        # and exit 0/1 rather than an N-passed/M-failed summary; treat the
        # whole file as one assertion.
        $filePassed = 1
    } else {
        $fileFailed = 1
    }

    $totalPassed += $filePassed
    $totalFailed += $fileFailed
    $ok = ($exitCode -eq 0)
    $results.Add([pscustomobject]@{ File = $relative; ExitCode = $exitCode; Passed = $filePassed; Failed = $fileFailed; Ok = $ok })
    Write-Host ''
}

Write-Host '=== Summary ===' -ForegroundColor Cyan
foreach ($r in $results) {
    $marker = if ($r.Ok) { 'PASS' } else { 'FAIL' }
    $color = if ($r.Ok) { 'Green' } else { 'Red' }
    Write-Host ("{0}: {1} (exit={2}, passed={3}, failed={4})" -f $marker, $r.File, $r.ExitCode, $r.Passed, $r.Failed) -ForegroundColor $color
}

$failedFiles = @($results | Where-Object { -not $_.Ok })
Write-Host ''
Write-Host "TOTAL: $totalPassed passed, $totalFailed failed across $($allFiles.Count) file(s) ($($failedFiles.Count) file(s) exited non-zero)." -ForegroundColor $(if ($failedFiles.Count -gt 0) { 'Red' } else { 'Green' })

if ($failedFiles.Count -gt 0) {
    exit 1
}
exit 0
