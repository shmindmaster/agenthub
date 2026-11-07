#Requires -Version 7
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'test_key_selection.py')
if ($LASTEXITCODE -ne 0) { throw 'Daytona offline routing and reference tests failed' }
Write-Host 'PASS: Daytona offline credential routing and reference coverage'
