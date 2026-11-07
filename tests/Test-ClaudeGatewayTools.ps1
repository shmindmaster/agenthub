$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
& python -m unittest discover -s (Join-Path $repoRoot 'tests') -p 'test_claude_gateway_*.py'
if ($LASTEXITCODE -ne 0) { throw 'Offline Claude gateway tool-loading regressions failed.' }
