$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'validate-plugin.ps1')
& (Join-Path $PSScriptRoot 'validate-runtime.ps1')
& (Join-Path $PSScriptRoot 'validate-demo-readiness.ps1')

'PASS: all Product Experience Engineering plugin tests completed.'
