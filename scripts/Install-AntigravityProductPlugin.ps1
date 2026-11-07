#Requires -Version 7.0
[CmdletBinding()]
param([switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
$package = Join-Path (Split-Path -Parent $PSScriptRoot) 'packages/product'
$scratch = [IO.Directory]::CreateTempSubdirectory('agenthub-antigravity-product-')
$projection = $scratch.FullName

try {
    # Antigravity discovers agents implicitly and cannot load the shared reviewer.
    # Its projection carries the five skills and their complete package resources.
    foreach ($item in '.antigravity-plugin', 'assets', 'kits', 'references', 'scripts', 'skills', 'README.md') {
        Copy-Item -LiteralPath (Join-Path $package $item) -Destination $projection -Recurse -Force
    }
    & agy plugin validate $projection --strict
    if ($LASTEXITCODE -ne 0) { throw 'Antigravity rejected the AH-Product projection.' }
    if ($ValidateOnly) { return }

    $installed = Join-Path $HOME '.gemini/config/plugins/ah-product'
    if (Test-Path -LiteralPath $installed -PathType Container) {
        & agy plugin uninstall ah-product
        if ($LASTEXITCODE -ne 0) { throw 'Antigravity could not remove the prior AH-Product copy.' }
    }
    & agy plugin install $projection
    if ($LASTEXITCODE -ne 0) { throw 'Antigravity could not install the validated AH-Product projection.' }
} finally {
    $resolved = (Resolve-Path -LiteralPath $projection).Path
    if ($resolved -eq $projection -and (Split-Path -Parent $resolved) -eq $scratch.Parent.FullName) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
