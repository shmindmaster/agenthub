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

# Product-picture gates travel with the compositor so compose-screencast.mjs can always resolve them
# (a missing validator is a hard stop, never a silent skip). The plan gate and the encoded gate are copied
# beside the kit's screencast tools; _shared	ools gets the same canonical compositor so no stale copy survives.
$gateScripts = @('validate-product-picture.mjs', 'validate-encoded-picture.mjs')
$sharedTools = Join-Path (Split-Path -Parent $RuntimeKit) '_shared	ools'
New-Item -ItemType Directory -Force -Path $sharedTools | Out-Null
foreach ($name in $gateScripts) {
    $from = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Canonical gate missing: $from" }
    Copy-Item -LiteralPath $from -Destination (Join-Path $RuntimeKit ('screencast' + $name)) -Force
    Copy-Item -LiteralPath $from -Destination (Join-Path $sharedTools $name) -Force
}
foreach ($name in @('compose-screencast.mjs', 'render-overlay.mjs', 'render-code.mjs', 'render-html.mjs', 'render-card.mjs', 'record-job.mjs', 'record-lib.mjs')) {
    $from = Join-Path $packageKit ('screencast' + $name)
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $sharedTools $name) -Force }
}
# animate-stills.mjs turned screenshots into "footage" for the 2026-08/09 ABACare cuts. It has no place in a
# product-screencast; the receipt requirement already rejects its output, and the file is removed from the kit.
$stills = Join-Path $sharedTools 'animate-stills.mjs'
if (Test-Path -LiteralPath $stills) { Remove-Item -LiteralPath $stills -Force; Write-Host "Removed $stills (stills animation is not product footage)" }


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
