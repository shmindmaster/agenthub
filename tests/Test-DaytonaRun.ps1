# Runs the Node tests for scripts/daytona-run.mjs (argument rules and image naming; no network).
$ErrorActionPreference = 'Stop'
& node --test (Join-Path $PSScriptRoot 'daytona-run.test.mjs')
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL: daytona-run tests'; exit 1 }
Write-Host 'PASS: daytona-run tests'
