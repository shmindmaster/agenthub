#Requires -Version 5.1
<#
Runs every test_*.py in packages/media-studio/scripts. The six named below must
exist, so the set cannot quietly shrink to nothing. Credential and sandbox rules
live in tests/lib/PythonUnitTests.ps1.

Run: pwsh -NoProfile -File tests/Test-MediaStudioPython.ps1
     powershell.exe -NoProfile -File tests/Test-MediaStudioPython.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptsDir = Join-Path (Join-Path (Join-Path $repoRoot 'packages') 'media-studio') 'scripts'
exit (Invoke-PythonUnitTests -Directory $scriptsDir -Discover -Required @(
    'test_content_host_controls', 'test_content_runtime', 'test_elevenlabs_cli', 'test_governed_azure_speech',
    'test_governed_deepgram', 'test_governed_elevenlabs'))
