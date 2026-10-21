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
    'src\MarketingAd.tsx',
    'src\index.ts',
    'src\index.css',
    'package.json',
    'tsconfig.json',
    'remotion.config.ts',
    'README.md',
    'scene-archetypes.json',
    'screencast\compose-screencast.mjs',
    'screencast\campaign-contract.mjs',
    'screencast\render-overlay.mjs',
    'screencast\render-code.mjs',
    'screencast\render-html.mjs',
    'screencast\render-card.mjs',
    'screencast\record-job.mjs',
    'screencast\record-lib.mjs',
    'screencast\sync-lib.mjs',
    'screencast\README.md',
    'code-stage\shotlist.mjs',
    'code-stage\source.mjs',
    'code-stage\driver.mjs',
    'code-stage\build-stage.mjs',
    'code-stage\verify-receipt.mjs',
    'code-stage\editor.html',
    'code-stage\diagram.html',
    'code-stage\README.md'
)
foreach ($rel in $files) {
    $from = Join-Path $packageKit $rel
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $RuntimeKit $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
}

# Marketing video generator (mvg): the whole kit\marketing tree is managed, so the runtime copy is replaced, not merged
# (a deleted module must not survive as a stale file). The ElevenLabs adapter stays in the AgentHub checkout.
$marketingSource = Join-Path $packageKit 'marketing'
if (Test-Path -LiteralPath $marketingSource) {
    $marketingTarget = Join-Path $RuntimeKit 'marketing'
    if (Test-Path -LiteralPath $marketingTarget) { Remove-Item -LiteralPath $marketingTarget -Recurse -Force }
    Copy-Item -LiteralPath $marketingSource -Destination $marketingTarget -Recurse -Force
}

# Capture and product-picture gates travel with the compositor so each host resolves the same scripts.
# A missing validator is a hard stop, never a silent skip. The existing scripts are copied
# beside the kit's screencast tools; _shared\tools gets the same canonical compositor so no stale copy survives.
$gateScripts = @('validate-storyboard.mjs', 'validate-capture-manifest.mjs', 'backfill-capture-receipt.mjs', 'validate-demo-scenario.mjs', 'validate-product-picture.mjs', 'validate-encoded-picture.mjs', 'validate-sync.mjs', 'build-cue-sheet.mjs', 'backfill-head-trim.mjs', 'validate-viewer-release.mjs')
$sharedTools = Join-Path (Join-Path (Split-Path -Parent $RuntimeKit) '_shared') 'tools'
New-Item -ItemType Directory -Force -Path $sharedTools | Out-Null
foreach ($name in $gateScripts) {
    $from = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Canonical gate missing: $from" }
    Copy-Item -LiteralPath $from -Destination (Join-Path (Join-Path $RuntimeKit 'screencast') $name) -Force
    Copy-Item -LiteralPath $from -Destination (Join-Path $sharedTools $name) -Force
}
foreach ($name in @('compose-screencast.mjs', 'campaign-contract.mjs', 'render-overlay.mjs', 'render-code.mjs', 'render-html.mjs', 'render-card.mjs', 'record-job.mjs', 'record-lib.mjs', 'sync-lib.mjs')) {
    $from = Join-Path (Join-Path $packageKit 'screencast') $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Canonical screencast tool missing: $from" }
    Copy-Item -LiteralPath $from -Destination (Join-Path $sharedTools $name) -Force
}
Copy-Item -LiteralPath (Join-Path $packageKit 'screencast\campaign-contract.mjs') -Destination (Join-Path $sharedTools 'campaign-contract.mjs') -Force
foreach ($name in @('Finish-Media.ps1', 'Finish-BriefingStems.ps1', 'Generate-OwnerVoice.ps1', 'ReGate-OwnerVoice.ps1', 'Test-SpeechIntegrity.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $sharedTools $name) -Force
}
# Skills cite these by name from the deployed shared tools: the visual-quality inspector (media-studio-qa, the story
# reviewer, engagement.md) and the workspace scaffold (media-studio-capture). A missing script is a hard stop.
foreach ($name in @('Inspect-MediaVisualQuality.ps1', 'scaffold-video-workspace.mjs')) {
    $from = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $from)) { throw "Canonical tool missing: $from" }
    Copy-Item -LiteralPath $from -Destination (Join-Path $sharedTools $name) -Force
}
# demo-stack.mjs is owned by product-experience-engineering (registry/capabilities.json). The capture skill starts a
# product's demo harness with it before recording, and loose-skill hosts have no package checkout, so the canonical
# file is copied beside the capture tools rather than re-implemented here. The copy is read-only output of that owner.
$demoStack = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\product-experience-engineering\scripts\demo-stack.mjs'))
if (-not (Test-Path -LiteralPath $demoStack)) { throw "Canonical demo-stack runner missing: $demoStack" }
Copy-Item -LiteralPath $demoStack -Destination (Join-Path $sharedTools 'demo-stack.mjs') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\plugin.json') -Destination (Join-Path $sharedTools 'plugin.json') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\RELEASE-EVIDENCE.md') -Destination (Join-Path $sharedTools 'RELEASE-EVIDENCE.md') -Force
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

# The deploy list above is the whole managed content of _shared\tools. Anything else there is a one-off script,
# backup or working copy that belongs in its job folder. It is reported, never deleted: an unmatched file may be the
# only copy, so the move is a reviewed step (global policy: delete nothing unmatched), not a sync side effect.
$managedTools = @($gateScripts) + @('compose-screencast.mjs', 'campaign-contract.mjs', 'render-overlay.mjs', 'render-code.mjs', 'render-html.mjs', 'render-card.mjs', 'record-job.mjs', 'record-lib.mjs', 'sync-lib.mjs',
    'Finish-Media.ps1', 'Finish-BriefingStems.ps1', 'Generate-OwnerVoice.ps1', 'ReGate-OwnerVoice.ps1', 'Test-SpeechIntegrity.ps1',
    'Inspect-MediaVisualQuality.ps1', 'scaffold-video-workspace.mjs', 'demo-stack.mjs', 'plugin.json', 'RELEASE-EVIDENCE.md', 'write-story-review.py',
    'node_modules')  # node_modules is the capture-lib dependency link the screencast tools resolve from, not a script
$unmanaged = @(Get-ChildItem -LiteralPath $sharedTools -Force | Where-Object { $_.Name -notin $managedTools } | ForEach-Object Name)
if ($unmanaged.Count -gt 0) {
    Write-Warning ("_shared\tools holds {0} unmanaged entries (not in the deploy list; move each to its job folder after a hash check): {1}" -f $unmanaged.Count, ($unmanaged -join ', '))
} else {
    Write-Host "_shared\tools matches the deploy list ($($managedTools.Count) managed entries)"
}
