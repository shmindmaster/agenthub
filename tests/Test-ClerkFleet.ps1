#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$python = @('python3.13.exe', 'python3', 'python') | ForEach-Object {
    Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue
} | Select-Object -First 1
if (-not $python) { throw 'Python 3.13+ is required for Clerk fleet safety tests.' }
& $python.Source -m unittest discover -s $PSScriptRoot -p test_clerk_fleet.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host 'RESULT: 7 passed, 0 failed'
