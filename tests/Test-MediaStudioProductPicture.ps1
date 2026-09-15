#Requires -Version 5.1
<#
Pins the product-picture contract: validator fails PNG screen beats, auto-cards,
kind/form mismatch, and sub-70% screen duration; compose-screencast forbids
auto-card on screen; kit does not Ken Burns screen-in-context.

Run: pwsh -NoProfile -File tests/Test-MediaStudioProductPicture.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\media-studio'
$validator = Join-Path $pkg 'scripts\validate-product-picture.mjs'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

Report 'validate-product-picture.mjs exists' (Test-Path -LiteralPath $validator) 'missing scripts/validate-product-picture.mjs'
Report 'capture-plan schema exists' (
    Test-Path -LiteralPath (Join-Path $pkg 'schemas\capture-plan.schema.json')
) 'missing schemas/capture-plan.schema.json'
$jobSchema = Get-Content -LiteralPath (Join-Path $pkg 'schemas\job.schema.json') -Raw -Encoding UTF8
Report 'job schema enumerates technical-story' ($jobSchema -match '"technical-story"') 'job.schema.json still omits technical-story'
$compose = Get-Content -LiteralPath (Join-Path $pkg 'kit\screencast\compose-screencast.mjs') -Raw -Encoding UTF8
Report 'compose-screencast forbids auto-card on screen beats' (
    $compose -match 'Auto-card is forbidden on screen beats' -and
    $compose -match 'isScreenBeat'
) 'compositor still auto-cards missing screen clips'
$visuals = Get-Content -LiteralPath (Join-Path $pkg 'kit\src\Visuals.tsx') -Raw -Encoding UTF8
Report 'screen-in-context does not Ken Burns' (
    $visuals -match 'Recast punch-in is the only zoom on product UI' -and
    $visuals -match 'framed' -and
    $visuals -match 'Ken Burns on screen-in-context'
) 'Visuals.tsx still scale-interpolates product screenshots'
$videoMd = Get-Content -LiteralPath (Join-Path $repoRoot 'packages\local-ai\skills\local-ai-stack\references\video.md') -Raw -Encoding UTF8
Report 'Local-AI video.md refuses Motif of product screenshots' (
    $videoMd -match 'Never Motif / image-to-video a product screenshot'
) 'video.md still allows I2V of product UI'
$policy = Get-Content -LiteralPath (Join-Path $repoRoot 'packages\product-demo-studio\policy\product-video-policy.json') -Raw -Encoding UTF8
Report 'PDS policy requires Recast pointer finishing' (
    $policy -match '"pointerFinishing"\s*:\s*"playwright-recast@0.19.2"' -and
    $policy -notmatch 'windows-spike-blocked'
) 'Recast is still labeled spike-blocked so agents skip cursor/click/zoom'

$scratch = Join-Path $env:TEMP ("ms-picture-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    function Write-Job([string]$Dir, [string]$Kind, [string]$Form, $Board, $Manifest, $Timeline, $Plan) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'story'), (Join-Path $Dir 'capture') | Out-Null
        @{
            kind = $Kind
            title = 't'
            workspace = $Dir
            repositoryWritePolicy = 'read-only'
            programForm = $Form
            intent = 'viewer-facing'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Dir 'job.json') -Encoding utf8
        $Board | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Dir 'story\storyboard.json') -Encoding utf8
        $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Dir 'capture\manifest.json') -Encoding utf8
        if ($null -ne $Timeline) {
            $Timeline | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Dir 'story\narration-timeline.json') -Encoding utf8
        }
        if ($null -ne $Plan) {
            $Plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Dir 'story\capture-plan.json') -Encoding utf8
        }
    }

    $okDir = Join-Path $scratch 'ok'
    Write-Job $okDir 'product-screencast' 'role-demo' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hook'; narration = 'n'; visualMode = 'slide'; visualArchetype = 'kinetic-statement'; durationSeconds = 6; shotPlan = @{ framing = 'wide'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 0.5; visualRefreshTarget = 4 }; sound = @{ musicCue = 'silence' } }
            @{ id = 'S02'; order = 2; sceneRole = 'hero'; narration = 'n'; visualMode = 'screen'; visualArchetype = 'screen-in-context'; durationSeconds = 20; shotPlan = @{ framing = 'medium'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 1; visualRefreshTarget = 4 }; sound = @{ musicCue = 'bed' } }
        )
    } @{
        clips = @(@{ id = 'S02'; file = 'clips/S02.webm'; segments = @('S02') })
    } @{
        durationSeconds = 26
        segments = @(
            @{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 6 }
            @{ id = 'S02'; scene = 'S02'; text = 'n'; startSeconds = 6; durationSeconds = 20 }
        )
    } @{
        scenes = @(
            @{ sceneId = 'S01'; kind = 'card' }
            @{ sceneId = 'S02'; kind = 'interaction'; action = 'click Submit'; expectedResult = 'toast appears'; clip = 'clips/S02.webm' }
        )
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $okOut = & node $validator $okDir 2>&1 | Out-String
    $okCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'passing product-screencast job is accepted' (
        $okCode -eq 0 -and $okOut -match '"ok"\s*:\s*true'
    ) "exit=$okCode out=$okOut"

    $pngDir = Join-Path $scratch 'png'
    Write-Job $pngDir 'product-screencast' 'role-demo' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hero'; narration = 'n'; visualMode = 'screen'; visualArchetype = 'screen-in-context'; durationSeconds = 20; shotPlan = @{ framing = 'medium'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 1; visualRefreshTarget = 4 }; sound = @{ musicCue = 'bed' } }
        )
    } @{
        clips = @(@{ id = 'S01'; file = 'clips/S01.png'; segments = @('S01') })
    } @{
        durationSeconds = 20
        segments = @(@{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 20 })
    } $null
    $ErrorActionPreference = 'Continue'
    $pngOut = & node $validator $pngDir 2>&1 | Out-String
    $pngCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'PNG screen beat fails' (
        $pngCode -ne 0 -and $pngOut -match 'still'
    ) "exit=$pngCode out=$pngOut"

    $cardDir = Join-Path $scratch 'card'
    Write-Job $cardDir 'product-screencast' 'role-demo' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hero'; narration = 'n'; visualArchetype = 'screen-in-context'; durationSeconds = 20; shotPlan = @{ framing = 'medium'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 1; visualRefreshTarget = 4 }; sound = @{ musicCue = 'bed' } }
        )
    } @{
        clips = @()
    } @{
        durationSeconds = 20
        segments = @(@{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 20 })
    } $null
    $ErrorActionPreference = 'Continue'
    $cardOut = & node $validator $cardDir 2>&1 | Out-String
    $cardCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'missing screen clip fails (default visualMode=screen)' (
        $cardCode -ne 0 -and $cardOut -match 'no captured clip'
    ) "exit=$cardCode out=$cardOut"

    $kindDir = Join-Path $scratch 'kind'
    Write-Job $kindDir 'briefing' 'technical-story' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hook'; narration = 'n'; visualMode = 'slide'; visualArchetype = 'kinetic-statement'; durationSeconds = 8; shotPlan = @{ framing = 'wide'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 0.5; visualRefreshTarget = 4 }; sound = @{ musicCue = 'silence' } }
        )
    } @{ clips = @() } @{
        durationSeconds = 8
        segments = @(@{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 8 })
    } $null
    $ErrorActionPreference = 'Continue'
    $kindOut = & node $validator $kindDir 2>&1 | Out-String
    $kindCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'technical-story as briefing fails' (
        $kindCode -ne 0 -and $kindOut -match 'product-screencast'
    ) "exit=$kindCode out=$kindOut"

    $briefDir = Join-Path $scratch 'brief'
    Write-Job $briefDir 'briefing' $null @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @()
    } @{ clips = @() } $null $null
    $ErrorActionPreference = 'Continue'
    $briefOut = & node $validator $briefDir 2>&1 | Out-String
    $briefCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'true briefing is skipped' (
        $briefCode -eq 0 -and $briefOut -match 'skipped'
    ) "exit=$briefCode out=$briefOut"

    $longCardDir = Join-Path $scratch 'longcard'
    Write-Job $longCardDir 'product-screencast' 'role-demo' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hook'; narration = 'n'; visualMode = 'slide'; visualArchetype = 'kinetic-statement'; durationSeconds = 9; shotPlan = @{ framing = 'wide'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 0.5; visualRefreshTarget = 4 }; sound = @{ musicCue = 'silence' } }
            @{ id = 'S02'; order = 2; sceneRole = 'hero'; narration = 'n'; visualMode = 'screen'; visualArchetype = 'screen-in-context'; durationSeconds = 80; shotPlan = @{ framing = 'medium'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 1; visualRefreshTarget = 4 }; sound = @{ musicCue = 'bed' } }
        )
    } @{
        clips = @(@{ id = 'S02'; file = 'clips/S02.webm'; segments = @('S02') })
    } @{
        durationSeconds = 89
        segments = @(
            @{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 9 }
            @{ id = 'S02'; scene = 'S02'; text = 'n'; startSeconds = 9; durationSeconds = 80 }
        )
    } $null
    $ErrorActionPreference = 'Continue'
    $longOut = & node $validator $longCardDir 2>&1 | Out-String
    $longCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'card longer than 8s on a screencast fails' (
        $longCode -ne 0 -and $longOut -match '8s'
    ) "exit=$longCode out=$longOut"

    $holdDir = Join-Path $scratch 'hold'
    Write-Job $holdDir 'product-screencast' 'role-demo' @{
        title = 't'
        chosenHook = @{ id = 'h'; narration = 'n'; visualArchetype = 'cold-open'; score = 90; why = 'w' }
        beats = @(
            @{ id = 'S01'; order = 1; sceneRole = 'hero'; narration = 'n'; visualMode = 'screen'; visualArchetype = 'screen-in-context'; durationSeconds = 20; shotPlan = @{ framing = 'medium'; subject = 's'; movement = 'cut'; focalPoint = 'f' }; rhythm = @{ energy = 0.5; pauseBefore = 0; holdAfter = 1; visualRefreshTarget = 4 }; sound = @{ musicCue = 'bed' } }
        )
    } @{
        clips = @(@{ id = 'S01'; file = 'clips/S01.webm'; segments = @('S01') })
    } @{
        durationSeconds = 20
        segments = @(@{ id = 'S01'; scene = 'S01'; text = 'n'; startSeconds = 0; durationSeconds = 20 })
    } @{
        scenes = @(
            @{ sceneId = 'S01'; kind = 'hold'; plateName = 'clips/S01.png' }
        )
    }
    $ErrorActionPreference = 'Continue'
    $holdOut = & node $validator $holdDir 2>&1 | Out-String
    $holdCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Report 'PNG hold on a screen beat fails' (
        $holdCode -ne 0 -and $holdOut -match 'hold is a still'
    ) "exit=$holdCode out=$holdOut"
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
