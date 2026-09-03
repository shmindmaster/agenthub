#Requires -Version 5.1
<#
Copy packages/media-studio/kit source into the runtime briefing kit.
Does not copy node_modules. Does not touch product repositories.
#>
[CmdletBinding()]
param(
    [string]$RuntimeKit = (Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit')
)

$ErrorActionPreference = 'Stop'
$packageKit = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\kit'))
if (-not (Test-Path -LiteralPath (Join-Path $packageKit 'src\Visuals.tsx'))) {
    throw "Canonical kit source missing: $packageKit\src"
}

New-Item -ItemType Directory -Force -Path (Join-Path $RuntimeKit 'src') | Out-Null
$files = @(
    'src\Visuals.tsx',
    'src\Briefing.tsx',
    'src\Root.tsx',
    'src\Composition.tsx',
    'src\index.ts',
    'src\index.css',
    'package.json',
    'tsconfig.json',
    'remotion.config.ts',
    'README.md',
    'scene-archetypes.json'
)
foreach ($rel in $files) {
    $from = Join-Path $packageKit $rel
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $RuntimeKit $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
}

Write-Host "Synced kit source -> $RuntimeKit"
