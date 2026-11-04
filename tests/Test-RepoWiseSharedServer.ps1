#Requires -Version 5.1
<#
Runs packages/repowise/tests/test_shared_server.py against the real MCP SDK ASGI
transport. It imports repowise, mcp and starlette, so it runs under the
interpreter the shared server itself uses (the uv tool environment, the same
default as Start-RepoWiseShared.ps1), and a missing environment fails here.
tests/ci-skip.json lists this file because CI runners do not install that tool.
Credential and sandbox rules live in tests/lib/PythonUnitTests.ps1.

Run: pwsh -NoProfile -File tests/Test-RepoWiseSharedServer.ps1
     powershell.exe -NoProfile -File tests/Test-RepoWiseSharedServer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$testsDir = Join-Path (Join-Path (Join-Path $repoRoot 'packages') 'repowise') 'tests'
$toolPython = Join-Path $env:APPDATA 'uv\tools\repowise\Scripts\python.exe'
exit (Invoke-PythonUnitTests -Directory $testsDir -Python $toolPython -Required 'test_shared_server')
