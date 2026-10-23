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
    # Capture warnings and host output: a deployed helper missing from the managed list is reported as unmanaged.
    $firstSync = (& (Join-Path $package 'scripts\Sync-MediaStudioKit.ps1') -RuntimeKit $runtimeKit 3>&1 6>&1 | Out-String)
    if ($firstSync -match 'unmanaged entries[^
]*OwnerVoice-TakeReuse\.ps1') { throw "OwnerVoice-TakeReuse.ps1 is deployed but reported unmanaged: $firstSync" }
    $checks++
    foreach ($name in @('validate-word-sync.mjs','validate-storyboard.mjs','validate-capture-manifest.mjs','backfill-capture-receipt.mjs','validate-demo-scenario.mjs','validate-product-picture.mjs','validate-encoded-picture.mjs','validate-sync.mjs','build-cue-sheet.mjs','validate-viewer-release.mjs','validate-narration.mjs','validate-capture-preflight.mjs','validate-pointer-path.mjs','validate-frame-integrity.mjs','validate-picture-integrity.mjs','validate-marketing-readiness.mjs','build-contact-sheet.mjs')) {
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
    foreach ($name in @('Finish-Media.ps1','Finish-BriefingStems.ps1','Generate-OwnerVoice.ps1','ReGate-OwnerVoice.ps1','OwnerVoice-TakeReuse.ps1','Test-SpeechIntegrity.ps1')) {
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
        $relative = $file.FullName.Substring($marketingSource.Length).TrimStart('\')
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
    & (Join-Path $package 'scripts\Sync-MediaStudioKit.ps1') -RuntimeKit $runtimeKit -Force | Out-Null
    if (Test-Path -LiteralPath $stale) { throw 'Marketing kit sync merged instead of replacing' }
    $checks++
    # Mirror in place: stale files and stale directories go, but the target directory is the same object (never emptied or recreated).
    $marketingTarget = Join-Path $runtimeKit 'marketing'
    $syncScript = Join-Path $package 'scripts\Sync-MediaStudioKit.ps1'
    $staleDir = Join-Path $marketingTarget 'stale-removed-dir\nested'
    New-Item -ItemType Directory -Force -Path $staleDir | Out-Null
    Set-Content -LiteralPath (Join-Path $staleDir 'old.mjs') -Value '// stale' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs') -Value '// stale' -Encoding ascii
    $createdBefore = (Get-Item -LiteralPath $marketingTarget).CreationTimeUtc
    # Robocopy keeps source timestamps, so a rewrite would not show in LastWriteTime. Hold an unchanged file open
    # without write sharing instead: a rewrite fails with a sharing violation (exit 8, the sync throws); a skip passes.
    $keepFile = Join-Path $marketingTarget (Get-ChildItem -LiteralPath $marketingSource -File | Select-Object -First 1).Name
    Start-Sleep -Milliseconds 1100
    $held = [IO.File]::Open($keepFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        try { & $syncScript -RuntimeKit $runtimeKit -Force | Out-Null } catch { throw "An unchanged marketing file was rewritten during sync: $($_.Exception.Message)" }
    } finally { $held.Dispose() }
    $checks++
    if (Test-Path -LiteralPath (Join-Path $marketingTarget 'stale-removed-dir')) { throw 'Marketing kit sync left a stale directory behind' }
    $checks++
    if (Test-Path -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs')) { throw 'Marketing kit sync left a stale top-level file behind' }
    $checks++
    if ((Get-Item -LiteralPath $marketingTarget).CreationTimeUtc -ne $createdBefore) { throw 'Marketing target directory was deleted and recreated during sync' }
    $checks++
    # A successful robocopy (exit codes 1-7) must not leak as a failing script exit code.
    $pwshExe = (Get-Process -Id $PID).Path
    Set-Content -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs') -Value '// stale' -Encoding ascii
    & $pwshExe -NoProfile -File $syncScript -RuntimeKit $runtimeKit -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Sync exited $LASTEXITCODE after a successful mirror" }
    $checks++
    # Refuse while an mvg job runs from the target; -Force overrides.
    $node = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $helper = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $node
        $psi.Arguments = '-e "setTimeout(()=>{},60000)" "' + (Join-Path $marketingTarget 'mvg.mjs') + '"'
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $helper = [Diagnostics.Process]::Start($psi)
        Start-Sleep -Milliseconds 800
        Set-Content -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs') -Value '// stale' -Encoding ascii
        $refusal = $null
        try { & $syncScript -RuntimeKit $runtimeKit | Out-Null } catch { $refusal = $_.Exception.Message }
        if (-not $refusal -or $refusal -notmatch 'mvg' -or $refusal -notmatch [string]$helper.Id) { throw "Sync did not refuse while an mvg job was running (message: $refusal)" }
        $checks++
        if (-not (Test-Path -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs')) -or -not (Test-Path -LiteralPath (Join-Path $marketingTarget 'mvg.mjs'))) { throw 'Refused sync still touched the marketing directory' }
        $checks++
        & $syncScript -RuntimeKit $runtimeKit -Force 3>$null | Out-Null
        if (Test-Path -LiteralPath (Join-Path $marketingTarget 'stale-top.mjs')) { throw '-Force did not complete the mirror' }
        $checks++
    } finally {
        if ($helper -and -not $helper.HasExited) { $helper.Kill(); $helper.WaitForExit(5000) | Out-Null }
        if ($helper) { $helper.Dispose() }
    }
    # The run-mvg.sh runners start `node mvg.mjs` from inside the tree, so the command line carries no directory;
    # Git Bash runners may also pass ./mvg.mjs or a forward-slash absolute path.
    foreach ($scriptArg in @('mvg.mjs', '.\mvg.mjs', './mvg.mjs', ((Join-Path $marketingTarget 'mvg.mjs').Replace('\', '/')))) {
        $helper = $null
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $node
            $psi.Arguments = '-e "setTimeout(()=>{},60000)" "' + $scriptArg + '"'
            $psi.WorkingDirectory = $marketingTarget
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $helper = [Diagnostics.Process]::Start($psi)
            Start-Sleep -Milliseconds 500
            $refusal = $null
            try { & $syncScript -RuntimeKit $runtimeKit | Out-Null } catch { $refusal = $_.Exception.Message }
            if (-not $refusal -or $refusal -notmatch [string]$helper.Id) { throw "Sync did not refuse a 'node $scriptArg' job (message: $refusal)" }
            $checks++
        } finally {
            if ($helper -and -not $helper.HasExited) { $helper.Kill(); $helper.WaitForExit(5000) | Out-Null }
            if ($helper) { $helper.Dispose() }
        }
    }
    Write-Host "PASS: $checks runtime gate/tool deployment checks"
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch cleanup escaped temporary root' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
