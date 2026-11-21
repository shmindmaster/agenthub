#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'The standalone ZCode desktop bundle route is supported on Windows.' }
$node = Get-Command node -CommandType Application | Select-Object -First 1
& $node.Source -e "if (typeof require('node:module').registerHooks !== 'function') process.exit(1)"
if ($LASTEXITCODE -ne 0) { throw 'ZCode Browser Use requires Node with node:module registerHooks support.' }

$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json
$version = $manifest.dependencies.'playwright-core'
$runtime = Join-Path $env:LOCALAPPDATA "AgentHub/runtime/coding-agent-dispatch/zcode/playwright-$version"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
foreach ($file in @('package.json', 'package-lock.json')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $runtime
}
$npm = Get-Command npm.cmd -CommandType Application | Select-Object -First 1
# npm ci must run from the real path when the runtime root is a junction.
$realRuntime = & $node.Source -p "require('node:fs').realpathSync(process.argv[1])" $runtime
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the ZCode browser runtime directory.' }
Push-Location -LiteralPath $realRuntime
try {
    & $npm.Source ci --ignore-scripts --no-audit --no-fund --registry https://registry.npmjs.org
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0) { throw 'Installation of the pinned ZCode Playwright runtime failed.' }
Write-Output "Installed ZCode Playwright Core $version under the AgentHub runtime."
