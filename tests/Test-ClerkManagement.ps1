#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
exit (Invoke-PythonUnitTests -Directory $PSScriptRoot -Required 'test_clerk_management')
