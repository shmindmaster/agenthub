#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$test = Join-Path $PSScriptRoot 'test_aws_mcp_headers.py'
& python $test
if ($LASTEXITCODE -ne 0) { throw 'AWS native authentication helper tests failed' }
Write-Output 'RESULT: 7 passed, 0 failed'
