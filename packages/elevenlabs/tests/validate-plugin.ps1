$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
& python (Join-Path $packageRoot 'scripts/validate_package.py')
if ($LASTEXITCODE -ne 0) { throw 'ElevenLabs package validation failed' }
& python (Join-Path $packageRoot 'scripts/test_elevenlabs_cli.py')
if ($LASTEXITCODE -ne 0) { throw 'ElevenLabs CLI safety tests failed' }
& python (Join-Path $packageRoot 'scripts/test_governed_processes.py')
if ($LASTEXITCODE -ne 0) { throw 'ElevenLabs HTTP/process governance tests failed' }
$mediaScripts = Join-Path (Split-Path -Parent $packageRoot) 'media-studio/scripts'
& python (Join-Path $mediaScripts 'test_content_runtime.py')
if ($LASTEXITCODE -ne 0) { throw 'Shared content ledger safety tests failed' }
& python (Join-Path $mediaScripts 'test_content_host_controls.py')
if ($LASTEXITCODE -ne 0) { throw 'Native connector block tests failed' }
Write-Host 'PASS: ElevenLabs package and CLI safety checks'
