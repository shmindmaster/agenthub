#Requires -Version 5.1
<#
Runs tests/test_clerk_fleet.py, the safety and behavior checks for
scripts/Install-ClerkFleet.py. Credential and sandbox rules live in
tests/lib/PythonUnitTests.ps1.

Run: pwsh -NoProfile -File tests/Test-ClerkFleet.ps1
     powershell.exe -NoProfile -File tests/Test-ClerkFleet.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
exit (Invoke-PythonUnitTests -Directory $PSScriptRoot -Required 'test_clerk_fleet')
