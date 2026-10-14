#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$package = Join-Path $repoRoot 'packages\media-studio'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('media-kit-test-' + [guid]::NewGuid().ToString('N'))
$runtimeKit = Join-Path $scratch 'briefing-kit'
$shared = Join-Path $scratch '_shared\tools'
$checks = 0
try {
    & (Join-Path $package 'scripts\Sync-MediaStudioKit.ps1') -RuntimeKit $runtimeKit
    foreach ($name in @('validate-storyboard.mjs','validate-capture-manifest.mjs','backfill-capture-receipt.mjs','validate-demo-scenario.mjs','validate-product-picture.mjs','validate-encoded-picture.mjs','validate-viewer-release.mjs')) {
        $source = Join-Path (Join-Path $package 'scripts') $name
        foreach ($destination in @((Join-Path (Join-Path $runtimeKit 'screencast') $name), (Join-Path $shared $name))) {
            if (-not (Test-Path -LiteralPath $destination)) { throw "Missing runtime gate: $destination" }
            if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale runtime gate: $destination" }
            $checks++
        }
    }
    foreach ($name in @('compose-screencast.mjs','render-overlay.mjs','render-code.mjs','render-html.mjs','render-card.mjs','record-job.mjs','record-lib.mjs')) {
        $source = Join-Path (Join-Path $package 'kit\screencast') $name
        $destination = Join-Path $shared $name
        if (-not (Test-Path -LiteralPath $destination)) { throw "Missing shared tool: $destination" }
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale shared tool: $destination" }
        $checks++
    }
    $helperSource = Join-Path $package 'kit\screencast\campaign-contract.mjs'
    foreach ($destination in @((Join-Path (Join-Path $runtimeKit 'screencast') 'campaign-contract.mjs'), (Join-Path $shared 'campaign-contract.mjs'))) {
        if (-not (Test-Path -LiteralPath $destination)) { throw "Missing campaign helper: $destination" }
        if ((Get-FileHash -LiteralPath $helperSource).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale campaign helper: $destination" }
        $checks++
    }
    foreach ($name in @('Finish-Media.ps1','Finish-BriefingStems.ps1','Generate-OwnerVoice.ps1','ReGate-OwnerVoice.ps1','Test-SpeechIntegrity.ps1')) {
        $source = Join-Path (Join-Path $package 'scripts') $name
        $destination = Join-Path $shared $name
        if (-not (Test-Path -LiteralPath $destination)) { throw "Missing shared media helper: $destination" }
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale shared media helper: $destination" }
        $checks++
    }
    if ((Get-FileHash -LiteralPath (Join-Path $package 'plugin.json')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $shared 'plugin.json')).Hash) { throw 'Shared tools release manifest is stale' }
    $checks++
    $stemsHelper = Get-Content -LiteralPath (Join-Path $shared 'Finish-BriefingStems.ps1') -Raw
    if ($stemsHelper -notmatch '\$PSScriptRoot.+Finish-Media.ps1' -or $stemsHelper -match 'AGENTHUB_ROOT') { throw 'Briefing stem helper does not resolve its adjacent finishing dependency' }
    $checks++
    $packageVersion = (Get-Content -LiteralPath (Join-Path $package 'plugin.json') -Raw | ConvertFrom-Json).version
    $runtimeVersion = (Get-Content -LiteralPath (Join-Path $runtimeKit 'package.json') -Raw | ConvertFrom-Json).version
    if ($runtimeVersion -ne $packageVersion) { throw "Runtime kit version $runtimeVersion does not match package $packageVersion" }
    $checks++
    $composeGuide = Get-Content -LiteralPath (Join-Path $package 'skills\media-studio-compose\SKILL.md') -Raw
    if ($composeGuide -match 'C:\\Repos\\shmindmaster\\agenthub' -or $composeGuide -notmatch 'MEDIA_STUDIO_PACKAGE_ROOT' -or $composeGuide -notmatch 'Finish-Media.ps1' -or $composeGuide -notmatch [regex]::Escape("'$packageVersion'")) {
        throw 'Compose guide does not describe verified package and deployed finishing paths'
    }
    $checks++
    $generateGuide = Get-Content -LiteralPath (Join-Path $package 'skills\media-studio-generate\SKILL.md') -Raw
    if ($generateGuide -match 'C:\\Repos\\shmindmaster\\agenthub' -or $generateGuide -notmatch 'Generate-OwnerVoice.ps1' -or $generateGuide -notmatch 'Test-SpeechIntegrity.ps1' -or $generateGuide -notmatch [regex]::Escape("'$packageVersion'")) {
        throw 'Generate guide does not describe deployed owner-voice helpers'
    }
    $checks++
    if ((Get-FileHash -LiteralPath (Join-Path $package 'RELEASE-EVIDENCE.md')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $shared 'RELEASE-EVIDENCE.md')).Hash) { throw 'Release evidence contract not deployed' }
    $checks++
    if (Get-ChildItem -LiteralPath $runtimeKit -File -Filter 'screencastvalidate-*') { throw 'Gate path lost its directory separator' }
    $checks++
    Write-Host "PASS: $checks runtime gate/tool deployment checks"
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch cleanup escaped temporary root' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
