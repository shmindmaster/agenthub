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
    'scene-archetypes.json',
    'screencast\compose-screencast.mjs',
    'screencast\render-overlay.mjs',
    'screencast\render-code.mjs',
    'screencast\render-html.mjs',
    'screencast\render-card.mjs',
    'screencast\README.md'
)
foreach ($rel in $files) {
    $from = Join-Path $packageKit $rel
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $RuntimeKit $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
}


# Optional screenplay lint (not a craft pass). Product-screencast still needs product-picture.
$gate = Join-Path $PSScriptRoot 'write-story-review.py'
if (Test-Path -LiteralPath $gate) {
    $sharedTools = Join-Path (Split-Path -Parent $RuntimeKit) '_shared\tools'
    New-Item -ItemType Directory -Force -Path $sharedTools | Out-Null
    Copy-Item -LiteralPath $gate -Destination (Join-Path $sharedTools 'write-story-review.py') -Force
    Write-Host "Synced kit source -> $RuntimeKit (+ write-story-review.py -> $sharedTools)"
} else {
    Write-Host "Synced kit source -> $RuntimeKit"
}
