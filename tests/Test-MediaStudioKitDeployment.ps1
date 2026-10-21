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
    foreach ($name in @('validate-storyboard.mjs','validate-capture-manifest.mjs','backfill-capture-receipt.mjs','validate-demo-scenario.mjs','validate-product-picture.mjs','validate-encoded-picture.mjs','validate-sync.mjs','build-cue-sheet.mjs','validate-viewer-release.mjs','validate-narration.mjs','validate-capture-preflight.mjs','validate-pointer-path.mjs','validate-frame-integrity.mjs','validate-picture-integrity.mjs','validate-marketing-readiness.mjs','build-contact-sheet.mjs')) {
        $source = Join-Path (Join-Path $package 'scripts') $name
        foreach ($destination in @((Join-Path (Join-Path $runtimeKit 'screencast') $name), (Join-Path $shared $name))) {
            if (-not (Test-Path -LiteralPath $destination)) { throw "Missing runtime gate: $destination" }
            if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale runtime gate: $destination" }
            $checks++
        }
    }
    foreach ($name in @('compose-screencast.mjs','render-overlay.mjs','render-code.mjs','render-html.mjs','render-card.mjs','record-job.mjs','record-lib.mjs','sync-lib.mjs')) {
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
    foreach ($name in @('Inspect-MediaVisualQuality.ps1','scaffold-video-workspace.mjs')) {
        $source = Join-Path (Join-Path $package 'scripts') $name
        $destination = Join-Path $shared $name
        if (-not (Test-Path -LiteralPath $destination)) { throw "Missing cited tool: $destination" }
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale cited tool: $destination" }
        $checks++
    }
    # demo-stack.mjs is product-experience-engineering's; the capture skill cites it from the deployed tools.
    $demoStackSource = Join-Path $repoRoot 'packages\product-experience-engineering\scripts\demo-stack.mjs'
    $demoStackDeployed = Join-Path $shared 'demo-stack.mjs'
    if (-not (Test-Path -LiteralPath $demoStackDeployed)) { throw "Missing demo-stack runner: $demoStackDeployed" }
    if ((Get-FileHash -LiteralPath $demoStackSource).Hash -ne (Get-FileHash -LiteralPath $demoStackDeployed).Hash) { throw "Stale demo-stack runner: $demoStackDeployed" }
    $checks++
    if ((Get-FileHash -LiteralPath (Join-Path $package 'plugin.json')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $shared 'plugin.json')).Hash) { throw 'Shared tools release manifest is stale' }
    $checks++
    $stemsHelper = Get-Content -LiteralPath (Join-Path $shared 'Finish-BriefingStems.ps1') -Raw -Encoding utf8
    if ($stemsHelper -notmatch '\$PSScriptRoot.+Finish-Media.ps1' -or $stemsHelper -match 'AGENTHUB_ROOT') { throw 'Briefing stem helper does not resolve its adjacent finishing dependency' }
    $checks++
    $packageVersion = (Get-Content -LiteralPath (Join-Path $package 'plugin.json') -Raw -Encoding utf8 | ConvertFrom-Json).version
    $runtimeVersion = (Get-Content -LiteralPath (Join-Path $runtimeKit 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json).version
    if ($runtimeVersion -ne $packageVersion) { throw "Runtime kit version $runtimeVersion does not match package $packageVersion" }
    $checks++
    $composeGuide = Get-Content -LiteralPath (Join-Path $package 'skills\media-studio-compose\SKILL.md') -Raw -Encoding utf8
    if ($composeGuide -match 'C:\\Repos\\shmindmaster\\agenthub' -or $composeGuide -notmatch 'MEDIA_STUDIO_PACKAGE_ROOT' -or $composeGuide -notmatch 'Finish-Media.ps1' -or $composeGuide -notmatch [regex]::Escape("'$packageVersion'")) {
        throw 'Compose guide does not describe verified package and deployed finishing paths'
    }
    $checks++
    $generateGuide = Get-Content -LiteralPath (Join-Path $package 'skills\media-studio-generate\SKILL.md') -Raw -Encoding utf8
    if ($generateGuide -match 'C:\\Repos\\shmindmaster\\agenthub' -or $generateGuide -notmatch 'Generate-OwnerVoice.ps1' -or $generateGuide -notmatch 'Test-SpeechIntegrity.ps1' -or $generateGuide -notmatch [regex]::Escape("'$packageVersion'")) {
        throw 'Generate guide does not describe deployed owner-voice helpers'
    }
    $checks++
    if ((Get-FileHash -LiteralPath (Join-Path $package 'RELEASE-EVIDENCE.md')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $shared 'RELEASE-EVIDENCE.md')).Hash) { throw 'Release evidence contract not deployed' }
    $checks++
    if (Get-ChildItem -LiteralPath $runtimeKit -File -Filter 'screencastvalidate-*') { throw 'Gate path lost its directory separator' }
    $checks++
    # mvg: the whole kit\marketing tree and the MarketingAd composition are deployed byte-for-byte.
    $marketingSource = Join-Path $package 'kit\marketing'
    $marketingSourceFiles = @(Get-ChildItem -LiteralPath $marketingSource -Recurse -File)
    if ($marketingSourceFiles.Count -lt 20) { throw 'Canonical marketing kit is missing files' }
    foreach ($file in $marketingSourceFiles) {
        $relative = $file.FullName.Substring($marketingSource.Length).TrimStart('')
        $destination = Join-Path (Join-Path $runtimeKit 'marketing') $relative
        if (-not (Test-Path -LiteralPath $destination)) { throw "Missing marketing kit file: $destination" }
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Stale marketing kit file: $destination" }
        $checks++
    }
    if ((Get-FileHash -LiteralPath (Join-Path $package 'kit\src\MarketingAd.tsx')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $runtimeKit 'src\MarketingAd.tsx')).Hash) { throw 'MarketingAd composition not deployed' }
    $checks++
    # Replace, never merge: a file deleted from the source must not survive in the runtime copy.
    $stale = Join-Path (Join-Path $runtimeKit 'marketing') 'stale-removed-module.mjs'
    Set-Content -LiteralPath $stale -Value '// stale' -Encoding ascii
    & (Join-Path $package 'scripts\Sync-MediaStudioKit.ps1') -RuntimeKit $runtimeKit | Out-Null
    if (Test-Path -LiteralPath $stale) { throw 'Marketing kit sync merged instead of replacing' }
    $checks++
    Write-Host "PASS: $checks runtime gate/tool deployment checks"
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch cleanup escaped temporary root' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
