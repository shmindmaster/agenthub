#Requires -Version 5.1
<#
Runs tests/test_agent_context.py, the unit tests for Measure-AgentContext.py and
Optimize-AgentContext.py. Credential and sandbox rules live in
tests/lib/PythonUnitTests.ps1.

Run: pwsh -NoProfile -File tests/Test-AgentContextPython.ps1
     powershell.exe -NoProfile -File tests/Test-AgentContextPython.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
exit (Invoke-PythonUnitTests -Directory $PSScriptRoot -Required 'test_agent_context')
