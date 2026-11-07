#Requires -Version 5.1
<#
Pins Media Studio 1.4.0 craft machinery: archetype catalog, kit sync, and
Inspect-MediaVisualQuality against generated fixtures.

Run: pwsh -NoProfile -File tests/Test-MediaStudioCraft.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

function Read-LocalAiReference([string]$Name) {
    foreach ($rel in @(
        "overlays\personal\packages\local-ai\skills\local-ai-stack\references\$Name",
        "packages\local-ai\skills\local-ai-stack\references\$Name"
    )) {
        $path = Join-Path $repoRoot $rel
        if (Test-Path -LiteralPath $path) {
            return Get-Content -LiteralPath $path -Raw -Encoding UTF8
        }
    }
    return $null
}
$pkg = Join-Path $repoRoot 'packages\media-studio'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$catalogPath = Join-Path $pkg 'kit\scene-archetypes.json'
Report 'scene-archetypes.json exists' (Test-Path -LiteralPath $catalogPath) 'missing kit/scene-archetypes.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ids = @($catalog.archetypes | ForEach-Object { [string]$_.id })
Report 'archetype catalog has at least 16 ids' ($ids.Count -ge 16) "count=$($ids.Count)"
Report 'catalog contains chapter-card' ($ids -contains 'chapter-card') 'missing chapter-card'
foreach ($need in @('cold-open','kinetic-statement','hero-reveal','cta-end-frame','before-after')) {
    Report "catalog contains $need" ($ids -contains $need) "missing $need"
}

$sync = Join-Path $pkg 'scripts\Sync-MediaStudioKit.ps1'
$inspect = Join-Path $pkg 'scripts\Inspect-MediaVisualQuality.ps1'
Report 'Sync-MediaStudioKit.ps1 exists' (Test-Path -LiteralPath $sync) 'missing kit sync script'
Report 'Inspect-MediaVisualQuality.ps1 exists' (Test-Path -LiteralPath $inspect) 'missing visual inspect script'

$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ("ms-craft-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
try {
    $runtime = Join-Path $scratchRoot 'briefing-kit'
    & pwsh -NoProfile -File $sync -RuntimeKit $runtime
    Report 'kit sync copies Visuals.tsx' (
        (Test-Path -LiteralPath (Join-Path $runtime 'src\Visuals.tsx')) -and
        (Select-String -LiteralPath (Join-Path $runtime 'src\Visuals.tsx') -Pattern 'kind: "cta"' -Quiet)
    ) 'synced kit missing new archetype visuals'
    Report 'kit sync copies Briefing archetype field' (
        Select-String -LiteralPath (Join-Path $runtime 'src\Briefing.tsx') -Pattern 'SceneArchetype' -Quiet
    ) 'synced Briefing.tsx missing SceneArchetype'

    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
    if (-not $ffmpeg -or -not $ffprobe) {
        Report 'ffmpeg/ffprobe available for inspect fixtures' $false 'ffmpeg/ffprobe not on PATH; inspect cannot be proven'
    } else {
        $staticMp4 = Join-Path $scratchRoot 'static.mp4'
        $cutMp4 = Join-Path $scratchRoot 'cut.mp4'
        & $ffmpeg.Source -hide_banner -loglevel error -y -f lavfi -i color=c=red:s=320x180:d=8 $staticMp4
        Report 'static fixture rendered' ((Test-Path -LiteralPath $staticMp4) -and $LASTEXITCODE -eq 0) "ffmpeg static exit $LASTEXITCODE"
        $a = Join-Path $scratchRoot 'a.mp4'
        $b = Join-Path $scratchRoot 'b.mp4'
        & $ffmpeg.Source -hide_banner -loglevel error -y -f lavfi -i color=c=red:s=320x180:d=2 $a
        & $ffmpeg.Source -hide_banner -loglevel error -y -f lavfi -i color=c=blue:s=320x180:d=2 $b
        & $ffmpeg.Source -hide_banner -loglevel error -y -i $a -i $b -filter_complex '[0:v][1:v]concat=n=2:v=1:a=0' $cutMp4
        Report 'cut fixture rendered' (Test-Path -LiteralPath $cutMp4) 'ffmpeg concat failed'

        $staticReport = Join-Path $scratchRoot 'static.json'
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & pwsh -NoProfile -File $inspect -Video $staticMp4 -Output $staticReport -StaticSeconds 2
        $staticCode = $LASTEXITCODE
        $ErrorActionPreference = $prev
        $staticJson = if (Test-Path -LiteralPath $staticReport) {
            Get-Content -LiteralPath $staticReport -Raw -Encoding UTF8 | ConvertFrom-Json
        } else { $null }
        Report 'static fixture is flagged' (
            $staticCode -eq 2 -and $staticJson -and -not $staticJson.pass -and
            @($staticJson.suspects | ForEach-Object kind) -contains 'static-stretch'
        ) "exit=$staticCode pass=$($staticJson.pass) suspects=$($staticJson.suspects | ConvertTo-Json -Compress)"

        $cutReport = Join-Path $scratchRoot 'cut.json'
        & pwsh -NoProfile -File $inspect -Video $cutMp4 -Output $cutReport -StaticSeconds 6
        $cutCode = $LASTEXITCODE
        $cutJson = Get-Content -LiteralPath $cutReport -Raw -Encoding UTF8 | ConvertFrom-Json
        Report 'short changing fixture is not a 6s static fail' (
            $cutCode -eq 0 -and $cutJson.pass -eq $true -and [int]$cutJson.metrics.shotChanges -ge 1
        ) "exit=$cutCode pass=$($cutJson.pass) shots=$($cutJson.metrics.shotChanges) suspects=$($cutJson.suspects | ConvertTo-Json -Compress)"

        $stillPng = Join-Path $scratchRoot 'pattern.png'
        & $ffmpeg.Source -hide_banner -loglevel error -y -f lavfi -i testsrc=s=320x180:d=1 -frames:v 1 $stillPng
        $kenMp4 = Join-Path $scratchRoot 'kenburns.mp4'
        & $ffmpeg.Source -hide_banner -loglevel error -y -loop 1 -i $stillPng -vf "zoompan=z='min(zoom+0.0015,1.4)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=320x180:fps=20" -t 8 $kenMp4
        $kenReport = Join-Path $scratchRoot 'ken.json'
        $ErrorActionPreference = 'Continue'
        & pwsh -NoProfile -File $inspect -Video $kenMp4 -Output $kenReport -StaticSeconds 2
        $kenCode = $LASTEXITCODE
        $ErrorActionPreference = $prev
        $kenJson = if (Test-Path -LiteralPath $kenReport) {
            Get-Content -LiteralPath $kenReport -Raw -Encoding UTF8 | ConvertFrom-Json
        } else { $null }
        $kenKinds = @($kenJson.suspects | ForEach-Object kind)
        Report 'ken-burns fixture is flagged' (
            $kenCode -eq 2 -and $kenJson -and -not $kenJson.pass -and
            ($kenKinds -contains 'ken-burns-on-still' -or $kenKinds -contains 'static-stretch')
        ) "exit=$kenCode pass=$($kenJson.pass) suspects=$($kenJson.suspects | ConvertTo-Json -Compress)"
    }
}
finally {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# The explainer path and technical-story beat map live in story.md; direction and archetypes in scenes.md;
# forms, delivery profiles and series methodology in forms.md.
$producer = Get-Content -LiteralPath (Join-Path $pkg 'skills\video\SKILL.md') -Raw -Encoding UTF8
$producer += [Environment]::NewLine + [IO.File]::ReadAllText((Join-Path $pkg 'skills\video\references\workflow-detail.md'))
$explainer = Get-Content -LiteralPath (Join-Path $pkg 'skills\video\references\story.md') -Raw -Encoding UTF8
$visualizer = Get-Content -LiteralPath (Join-Path $pkg 'skills\video\references\scenes.md') -Raw -Encoding UTF8
$series = Get-Content -LiteralPath (Join-Path $pkg 'skills\video\references\forms.md') -Raw -Encoding UTF8
Report 'story.md carries the explainer comprehension block inside the dramatic spine' (
    $explainer -match 'Question' -and $explainer -match '(?i)core idea' -and $explainer -match '(?i)misconception'
) 'explainer comprehension block was lost in the fold or still ships as slides'
Report 'scenes.md maintains attention' (
    $visualizer -match 'maintains attention'
) 'scenes reference still says cheapest truthful visual'
$music = Read-LocalAiReference 'music.md'
$image = Read-LocalAiReference 'image.md'
if ($null -eq $music -or $null -eq $image) {
    Write-Host 'SKIP: Local-AI music.md/image.md (private local-ai package is not in this checkout)'
} else {
    Report 'music.md maps bed, sting, and silence' (
        $music -match 'felt not heard' -and $music -match 'musicCue: sting' -and $music -match 'silenceOnReveal'
    ) 'music.md still only describes a generic bed'
    Report 'image.md has visual-bible path and refuses fake product UI' (
        $image -match 'visual-bible' -and $image -match 'product UI'
    ) 'image.md has no film B-roll contract'
}
Report 'video skill routes script, scenes, forms and product picture' (
    $producer -match 'references/story\.md' -and $producer -match 'references/scenes\.md' -and
    $producer -match 'references/forms\.md' -and $producer -match 'references/product-picture\.md' -and
    $producer -match 'product-screencast'
) 'video skill does not route every step to its reference'
Report 'forms.md runs series through the same crew' (
    $series -match '## Series' -and $series -match '`generate`' -and $series -match '`compose`' -and $series -match '`review`'
) 'series assembly does not run the shared crew'

# Technical-story format: story.md owns the beat map and markup rules.
$techStory = $explainer
Report 'story.md carries the beat map, markup rules, and the guiding principle' (
    $techStory -match 'Show me what happened' -and
    $techStory -match '0:00' -and $techStory -match '6:00' -and
    $techStory -match 'Code reveal' -and $techStory -match 'before/after' -and
    $techStory -match 'Never make an addendum' -and
    $techStory -match 'render-overlay\.mjs'
) 'story.md is missing the owner-directed structure or rules'
Report 'video skill names the technical-story form' (
    $producer -match 'programForm: technical-story'
) 'video skill does not route technical stories'

# Screencast compositor and annotation layer ship with the kit and document
# every manifest hint the compositor honors.
$screencastReadme = Get-Content -LiteralPath (Join-Path $pkg 'kit\screencast\README.md') -Raw -Encoding UTF8
Report 'kit/screencast README documents the manifest hints and overlay spec' (
    $screencastReadme -match 'trimStart' -and $screencastReadme -match 'trimEnd' -and
    $screencastReadme -match '`speed`' -and $screencastReadme -match '`skip`' -and
    $screencastReadme -match 'fitpad' -and $screencastReadme -match '`overlay`' -and
    $screencastReadme -match '\.recast-tmp'
) 'screencast README does not document the compositor contract'
$composeSource = Get-Content -LiteralPath (Join-Path $pkg 'kit\screencast\compose-screencast.mjs') -Raw -Encoding UTF8
Report 'compose-screencast honors the overlay hint and carries no product-specific strings' (
    $composeSource -match 'g\.clip\.overlay' -and
    $composeSource -match "'fitpad'" -and
    $composeSource -notmatch 'Duckie' -and $composeSource -notmatch 'prod-sim'
) 'compositor lost the overlay path or still carries a product name'
Report 'compose-screencast fails closed on screen stills' (
    $composeSource -match 'product-picture' -and
    $composeSource -match 'isScreenBeat' -and
    $composeSource -match 'validate-product-picture'
) 'compositor does not fail closed on PNG screen beats or skip the validator'
$kitPackage = Get-Content -LiteralPath (Join-Path $pkg 'kit\package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Report 'kit package.json declares playwright for the screencast renderers' (
    $null -ne $kitPackage.dependencies.playwright
) 'runtime kit cannot resolve playwright for render-*.mjs'
$compose = Get-Content -LiteralPath (Join-Path $pkg 'skills\compose\SKILL.md') -Raw -Encoding UTF8
$compose += [Environment]::NewLine + [IO.File]::ReadAllText((Join-Path $pkg 'skills\compose\references\workflow-detail.md'))
Report 'compose skill documents the hints and the delivery naming rule' (
    $compose -match 'fit: cut\|hold\|fit\|fitpad' -and
    $compose -match 'NN - Title\.mp4' -and
    $compose -match 'archive folders'
) 'compose skill does not carry the compositor contract or delivery rules'
$capture = Get-Content -LiteralPath (Join-Path $pkg 'skills\capture\SKILL.md') -Raw -Encoding UTF8
$capture += [Environment]::NewLine + [IO.File]::ReadAllText((Join-Path $pkg 'skills\capture\references\workflow-detail.md'))
Report 'capture skill resolves the browser provider from hostSurfaces and records the Recast limits' (
    $capture -match 'hostSurfaces' -and
    $capture -match '\.recast-tmp' -and $capture -match 'autoZoom'
) 'capture skill names a host tool or lost the measured Recast notes'
Report 'capture skill keeps the synthetic-only capture boundary' (
    $capture -match 'owner-authorized synthetic tenant' -and $capture -notmatch '(?i)duckie'
) 'capture skill lost the synthetic-only rule or names a client product'
Report 'capture references carry no client capture note' (
    -not (Test-Path -LiteralPath (Join-Path $pkg 'skills\capture\references\duckie-capture.md'))
) 'a client capture note is present in the public package'

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
