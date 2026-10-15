$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
& python (Join-Path $packageRoot 'scripts/validate_package.py')
if ($LASTEXITCODE -ne 0) { throw 'ElevenLabs package validation failed' }
& python (Join-Path $packageRoot 'scripts/test_elevenlabs_cli.py')
if ($LASTEXITCODE -ne 0) { throw 'ElevenLabs CLI safety tests failed' }
Write-Host 'PASS: ElevenLabs package and CLI safety checks'
