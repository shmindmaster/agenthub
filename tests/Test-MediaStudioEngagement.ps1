#Requires -Version 5.1
<#
Pins the viewer-facing engagement contract in packages/media-studio:

- engagement.md is the diagnose/tools/ownership home; story-craft and archetypes are catalogs
- producer/writer/storyboard/visuals/director/generate/compose/qa/critic load it
- rapid path is writer → storyboard → visuals → director → generate → compose → critic → QA
- schemas carry story roles, shot plan, sound, delivery profile, craftScoreMin
- product-screencast stays on the PDS rubric, not a second overlay stack

Run: pwsh -NoProfile -File tests/Test-MediaStudioEngagement.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\media-studio'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Read-Pkg([string]$Relative) {
    $path = Join-Path $pkg $Relative
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return [IO.File]::ReadAllText($path)
}

$engagement = Read-Pkg 'skills\media-studio\references\engagement.md'
$producer = Read-Pkg 'skills\media-studio\SKILL.md'
$writer = Read-Pkg 'skills\media-writer\SKILL.md'
$storyboard = Read-Pkg 'skills\media-storyboard\SKILL.md'
$visuals = Read-Pkg 'skills\media-studio-visuals\SKILL.md'
$director = Read-Pkg 'skills\media-director\SKILL.md'
$generate = Read-Pkg 'skills\media-studio-generate\SKILL.md'
$compose = Read-Pkg 'skills\media-studio-compose\SKILL.md'
$qa = Read-Pkg 'skills\media-studio-qa\SKILL.md'
$critic = Read-Pkg 'skills\media-story-experience-reviewer\SKILL.md'
$capture = Read-Pkg 'skills\media-studio-capture\SKILL.md'
$job = Read-Pkg 'schemas\job.schema.json'
$play = Read-Pkg 'schemas\screenplay.schema.json'
$board = Read-Pkg 'schemas\storyboard.schema.json'
$bible = Read-Pkg 'schemas\visual-bible.schema.json'
$review = Read-Pkg 'schemas\story-experience-review.schema.json'
$craft = Read-Pkg 'skills\media-studio\references\story-craft.md'
$archetypes = Read-Pkg 'skills\media-studio\references\scene-archetypes.md'
$rubric = Read-Pkg 'skills\media-studio\references\story-review-rubric.md'
$manifest = Read-Pkg 'plugin.json'

Report 'engagement.md exists' (-not [string]::IsNullOrWhiteSpace($engagement)) 'missing skills/media-studio/references/engagement.md'
Report 'engagement.md diagnoses wall-to-wall speech and static picture' (
    $engagement -match 'Wall-to-wall speech' -and $engagement -match 'One visual held'
) 'Diagnose first must name those failure modes'
Report 'engagement.md maps music to ai.ps1 music and Finish-Media duck' (
    $engagement -match 'ai\.ps1 music' -and $engagement -match 'Finish-Media'
) 'Tools table must name the actual providers'
Report 'engagement.md sends product-screencast to the PDS killer-demo guide' (
    $engagement -match 'killer-demo-production-guide' -and $engagement -match 'Do not invent another overlay stack'
) 'Screencasts must not grow a parallel overlay stack'

foreach ($pair in @(
        @{ Name = 'producer'; Text = $producer },
        @{ Name = 'writer'; Text = $writer },
        @{ Name = 'storyboard'; Text = $storyboard },
        @{ Name = 'visuals'; Text = $visuals },
        @{ Name = 'director'; Text = $director },
        @{ Name = 'generate'; Text = $generate },
        @{ Name = 'compose'; Text = $compose },
        @{ Name = 'qa'; Text = $qa },
        @{ Name = 'critic'; Text = $critic }
    )) {
    Report "$($pair.Name) loads engagement.md" (
        $pair.Text -match 'engagement\.md'
    ) "$($pair.Name) SKILL.md does not name engagement.md"
}

Report 'producer no longer skips music as the rapid default' (
    $producer -notmatch 'Skip Motif/lipsync/music unless needed'
) 'rapid path still tells the crew to skip music'
Report 'producer defaults intent to viewer-facing' (
    $producer -match 'intent: viewer-facing'
) 'producer must default viewer-facing'
Report 'producer QA step includes an engagement pass for non-screencast kinds' (
    $producer -match 'engagement pass'
) 'producer must run an engagement pass'
Report 'producer crew includes storyboard then visuals then critic' (
    $producer -match 'media-storyboard' -and
    $producer -match 'media-studio-visuals' -and
    $producer -match 'media-story-experience-reviewer'
) 'rapid path must insert storyboard, visuals, and craft critic'
Report 'producer requires Remotion for viewer-facing briefing/training/explainer/series-episode' (
    $producer -match 'requires Remotion' -and $producer -match 'intent: draft'
) 'viewer-facing motion jobs must not silently fall back to static slides'
Report 'writer hands off to storyboard' (
    $writer -match 'media-storyboard'
) 'writer must not skip to director'
Report 'director prefers simplest truthful visual that maintains attention' (
    $director -match 'simplest truthful visual that maintains attention'
) 'director still prefers cheapest still'
Report 'visuals writes visual-bible.json' (
    $visuals -match 'visual-bible\.json'
) 'visuals must be art direction, not only a B-roll warning'
Report 'critic fail-closed threshold is 85' (
    $critic -match '85' -and $rubric -match 'Below 85'
) 'story-experience reviewer must fail below 85'
Report 'generate makes a viewer-facing bed unless draft or music none' (
    $generate -match 'Viewer-facing' -and $generate -match 'musicCue: bed'
) 'generate must produce the directed bed for viewer-facing jobs'
Report 'generate consumes storyboard, visual bible, and per-beat register' (
    $generate -match 'storyboard\.json' -and
    $generate -match 'visual-bible\.json' -and
    $generate -match 'direction\.register' -and
    $generate -match 'silence'
) 'generate still only knows TTS + a generic bed'
Report 'compose requires stem finish when a bed exists' (
    $compose -match '-Speech -Music' -and $compose -match 'must' -and $compose -match 'ducks'
) 'compose must refuse an unducked bed'
Report 'qa engagement pass inspects the encoded file' (
    $qa -match 'encoded' -and $qa -match 'Diagnose first'
) 'non-screencast QA must walk the encoded file against Diagnose first'
Report 'capture keeps screencast engagement on the PDS gate' (
    $capture -match 'PDS story-experience' -and $capture -match 'not `engagement.md`'
) 'capture must not apply engagement.md as a second overlay stack'

Report 'job schema has intent draft|viewer-facing' (
    $job -match '"intent"' -and $job -match '"viewer-facing"' -and $job -match '"draft"'
) 'job.schema.json missing intent'
Report 'job schema has emotionalTarget and music' (
    $job -match '"emotionalTarget"' -and $job -match '"music"'
) 'job.schema.json missing emotionalTarget or music'
Report 'screenplay schema has hook and emotionalTarget' (
    $play -match '"hook"' -and $play -match '"emotionalTarget"'
) 'screenplay.schema.json missing hook or emotionalTarget'
Report 'screenplay scenes have pause, hold, emphasis, musicCue' (
    $play -match '"pauseBeforeSeconds"' -and
    $play -match '"holdAfterSeconds"' -and
    $play -match '"emphasis"' -and
    $play -match '"musicCue"'
) 'screenplay scene properties missing timing/music fields'
Report 'screenplay scenes carry story and archetype fields' (
    $play -match '"sceneRole"' -and
    $play -match '"wiifm"' -and
    $play -match '"visualArchetype"' -and
    $play -match '"shotPlan"' -and
    $play -match '"sfxCue"'
) 'screenplay cannot express storyboard-grade beats'
Report 'storyboard schema requires shotPlan, archetype, sound, chosenHook' (
    $board -match '"shotPlan"' -and
    $board -match '"visualArchetype"' -and
    $board -match '"chosenHook"' -and
    $board -match '"protectedHeroBeatId"'
) 'storyboard.schema.json missing timed-craft fields'
Report 'visual-bible and story-experience-review schemas exist' (
    $bible -match '"motif"' -and $review -match '"reviseSceneIds"' -and $review -match '"pass"'
) 'missing visual-bible or review schema'
Report 'story-craft and scene-archetype catalogs exist' (
    $craft -match 'Question' -and $craft -match 'Reveal' -and
    $archetypes -match 'kinetic-statement' -and $archetypes -match 'hero-reveal'
) 'missing story-craft or scene-archetype library'
Report 'job schema has deliveryProfile and craftScoreMin' (
    $job -match '"deliveryProfile"' -and $job -match '"craftScoreMin"'
) 'job.schema.json missing delivery or craft gate'
Report 'job schema has programForm and webcast/teaser kinds' (
    $job -match '"programForm"' -and $job -match '"outcome-workflow"' -and $job -match '"webcast"' -and $job -match '"teaser"'
) 'job.schema.json missing library forms or broadcast kinds'
$forms = Read-Pkg 'skills\media-studio\references\program-forms.md'
$studio = Read-Pkg 'skills\media-studio\references\studio-craft.md'
Report 'program-forms catalog exists' (
    $forms -match 'outcome-workflow' -and $forms -match 'ai-trust' -and $forms -match 'One promise'
) 'missing program-forms.md library'
Report 'studio-craft exists' (
    $studio -match 'felt not heard' -and $studio -match 'Coverage'
) 'missing studio-craft.md'
Report 'producer infers programForm' (
    $producer -match 'programForm' -and $producer -match 'program-forms.md'
) 'producer does not infer library form'

$plugin = $manifest | ConvertFrom-Json
Report 'plugin.json version is 1.4.0 or newer' (
    [version]$plugin.version -ge [version]'1.4.0'
) "plugin.json version is $($plugin.version)"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
