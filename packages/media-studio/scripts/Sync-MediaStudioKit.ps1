#Requires -Version 5.1
<#
Copy packages/media-studio/kit source into the runtime briefing kit.
Does not copy node_modules. Does not touch product repositories.
#>
[CmdletBinding()]
param(
    [string]$RuntimeKit = (Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\briefing-kit'),
    # Sync even while an mvg job is running from the target marketing directory.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$packageKit = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\kit'))
if (-not (Test-Path -LiteralPath (Join-Path $packageKit 'src\Visuals.tsx'))) {
    throw "Canonical kit source missing: $packageKit\src"
}

# Refuse before touching anything while an mvg job runs from the deployed marketing tree: the mirror below rewrites
# files that job has open. A job started as a bare `node mvg.mjs` from inside the tree (the run-mvg.sh runners do
# this) shows no directory on its command line, so a bare mvg.mjs counts as running from here too.
# Command lines are compared with forward slashes folded to backslashes (Git Bash runners pass C:/.../mvg.mjs).
# An unavailable process list is a warning, not a stop.
$marketingTarget = [IO.Path]::GetFullPath((Join-Path $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RuntimeKit) 'marketing'))
if (-not $Force -and (Test-Path -LiteralPath $marketingTarget)) {
    $running = @()
    try {
        $candidates = if ($env:OS -eq 'Windows_NT') {
            Get-CimInstance -ClassName Win32_Process -Filter "CommandLine LIKE '%mvg.mjs%'" -ErrorAction Stop
        } else {
            # macOS and Linux: ps lists every process with its full command line.
            $psLines = @(& ps -axo 'pid=,command=' 2>$null)
            if ($LASTEXITCODE -ne 0) { throw 'ps could not list processes' }
            foreach ($line in $psLines) {
                if ($line -match '^\s*(\d+)\s+(.*mvg\.mjs.*)$') { [pscustomobject]@{ ProcessId = [int]$Matches[1]; CommandLine = $Matches[2] } }
            }
        }
        $running = @($candidates |
            Where-Object {
                if ($_.ProcessId -eq $PID -or -not $_.CommandLine) { return $false }
                $commandLine = $_.CommandLine.Replace('/', '\')
                $commandLine.IndexOf($marketingTarget.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    $commandLine -match '(?:^|[\s"''])(?:\.\\)?mvg\.mjs(?=$|[\s"''])'
            })
    } catch {
        Write-Warning "Could not list processes to check for a running mvg job: $($_.Exception.Message)"
    }
    if ($running.Count -gt 0) {
        throw ("An mvg job is running from {0} (PID {1}). Wait for it to finish, or pass -Force to sync anyway." -f $marketingTarget, (($running | ForEach-Object { $_.ProcessId }) -join ', '))
    }
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
    'package-lock.json',
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
    'code-stage\README.md',
    # Shared cloud render path (Azure Container Apps job): upload -> render -> download.
    'cloud\cloud-render.mjs',
    'cloud\blob.mjs',
    'cloud\worker.mjs',
    'cloud\recast-run.mjs',
    'cloud\cloud-ai.mjs',
    'cloud\chunk-render.mjs',
    'cloud\Provision-CloudRender.ps1',
    'cloud\README.md'
)
foreach ($rel in $files) {
    $from = Join-Path $packageKit $rel
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $RuntimeKit $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to -Force
}

# Marketing video generator (mvg): the whole kit\marketing tree is managed, so the runtime copy is mirrored, not merged
# (a deleted module must not survive as a stale file). The mirror runs in place: the target directory is never
# deleted or emptied, so a running pipeline never sees the tree disappear. The ElevenLabs adapter stays in the AgentHub checkout.
$marketingSource = Join-Path $packageKit 'marketing'
if (Test-Path -LiteralPath $marketingSource) {
    New-Item -ItemType Directory -Force -Path $marketingTarget | Out-Null
    if ($env:OS -eq 'Windows_NT') {
        # Robocopy exit codes 0-7 are success (bit flags for what was copied/extra); 8 and above is failure. A caller with
        # PSNativeCommandUseErrorActionPreference set would otherwise turn a success code into a terminating error here.
        $PSNativeCommandUseErrorActionPreference = $false
        $robocopyOutput = @(& robocopy.exe $marketingSource $marketingTarget /MIR /NJH /NJS /NDL /NP /R:2 /W:1 2>&1)
        $robocopyExit = $LASTEXITCODE
        $global:LASTEXITCODE = 0
        if ($robocopyExit -ge 8) {
            throw ("Marketing kit mirror failed: robocopy exit code {0} ({1} -> {2}): {3}" -f $robocopyExit, $marketingSource, $marketingTarget, (($robocopyOutput | Select-Object -Last 5) -join ' | '))
        }
    } else {
        # Same in-place mirror without robocopy: copy new or changed files (an unchanged file is never rewritten, so a
        # running pipeline holding it open is undisturbed), then remove destination entries the source no longer has.
        # The target directory itself is never deleted.
        $sourceRoot = (Get-Item -LiteralPath $marketingSource).FullName.TrimEnd('/')
        $targetRoot = (Get-Item -LiteralPath $marketingTarget).FullName.TrimEnd('/')
        $keep = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force) {
            $relative = $item.FullName.Substring($sourceRoot.Length + 1)
            [void]$keep.Add($relative)
            $destination = Join-Path $targetRoot $relative
            if ($item.PSIsContainer) { New-Item -ItemType Directory -Force -Path $destination | Out-Null; continue }
            $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            if ($existing -and -not $existing.PSIsContainer -and $existing.Length -eq $item.Length -and
                (Get-FileHash -LiteralPath $existing.FullName).Hash -eq (Get-FileHash -LiteralPath $item.FullName).Hash) { continue }
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $targetRoot -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)) {
            if (-not $keep.Contains($item.FullName.Substring($targetRoot.Length + 1))) { Remove-Item -LiteralPath $item.FullName -Recurse -Force }
        }
    }
}

# Capture and product-picture gates travel with the compositor so each host resolves the same scripts.
# A missing validator is a hard stop, never a silent skip. The existing scripts are copied
# beside the kit's screencast tools; _shared\tools gets the same canonical compositor so no stale copy survives.
$gateScripts = @('hosted-alignment-clock.mjs', 'validate-edit-map.mjs', 'edit-map-clock.mjs', 'validate-word-sync.mjs', 'validate-storyboard.mjs', 'validate-capture-manifest.mjs', 'backfill-capture-receipt.mjs', 'validate-demo-scenario.mjs', 'validate-product-picture.mjs', 'validate-encoded-picture.mjs', 'validate-sync.mjs', 'build-cue-sheet.mjs', 'backfill-head-trim.mjs', 'validate-viewer-release.mjs',
    # video standard (2026-10-20): record-job.mjs resolves validate-capture-preflight.mjs from _shared\tools; the rest are the release gates the skills cite
    'validate-narration.mjs', 'validate-capture-preflight.mjs', 'validate-pointer-path.mjs', 'validate-frame-integrity.mjs', 'validate-picture-integrity.mjs', 'validate-marketing-readiness.mjs', 'build-contact-sheet.mjs',
    'picture-gates.mjs', 'validate-picture-inputs.mjs', 'render-program.mjs', 'lock-facts.mjs', 'write-captions.mjs', 'merge-designed-cuts.mjs')
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
foreach ($name in @('Finish-Media.ps1', 'Finish-BriefingStems.ps1', 'Generate-OwnerVoice.ps1', 'ReGate-OwnerVoice.ps1', 'OwnerVoice-TakeReuse.ps1', 'Test-SpeechIntegrity.ps1')) {
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
    'Finish-Media.ps1', 'Finish-BriefingStems.ps1', 'Generate-OwnerVoice.ps1', 'ReGate-OwnerVoice.ps1', 'OwnerVoice-TakeReuse.ps1', 'Test-SpeechIntegrity.ps1',
    'Inspect-MediaVisualQuality.ps1', 'scaffold-video-workspace.mjs', 'demo-stack.mjs', 'plugin.json', 'RELEASE-EVIDENCE.md', 'write-story-review.py',
    'node_modules')  # node_modules is the capture-lib dependency link the screencast tools resolve from, not a script
$unmanaged = @(Get-ChildItem -LiteralPath $sharedTools -Force | Where-Object { $_.Name -notin $managedTools } | ForEach-Object Name)
if ($unmanaged.Count -gt 0) {
    Write-Warning ("_shared\tools holds {0} unmanaged entries (not in the deploy list; move each to its job folder after a hash check): {1}" -f $unmanaged.Count, ($unmanaged -join ', '))
} else {
    Write-Host "_shared\tools matches the deploy list ($($managedTools.Count) managed entries)"
}
