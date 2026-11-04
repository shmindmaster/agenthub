#Requires -Version 5.1
<#
Pins the viewer-facing engagement contract in packages/media-studio:

- story.md is the diagnose/tools home; scenes.md holds the archetype catalog
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

$engagement = Read-Pkg 'skills\video\references\story.md'
$producer = Read-Pkg 'skills\video\SKILL.md'
# The script craft is one reference (story.md), storyboard, visuals and direction are one reference (scenes.md), and
# the story-experience critic is a section of the review skill.
$writer = $engagement
$storyboard = Read-Pkg 'skills\video\references\scenes.md'
$visuals = $storyboard
$director = $storyboard
$generate = Read-Pkg 'skills\generate\SKILL.md'
$compose = Read-Pkg 'skills\compose\SKILL.md'
$qa = Read-Pkg 'skills\review\SKILL.md'
$critic = $qa
$capture = Read-Pkg 'skills\capture\SKILL.md'
$job = Read-Pkg 'schemas\job.schema.json'
$play = Read-Pkg 'schemas\screenplay.schema.json'
$board = Read-Pkg 'schemas\storyboard.schema.json'
$bible = Read-Pkg 'schemas\visual-bible.schema.json'
$review = Read-Pkg 'schemas\story-experience-review.schema.json'
$craft = $engagement
$archetypes = $storyboard
$rubric = Read-Pkg 'skills\review\references\story-review-rubric.md'
$manifest = Read-Pkg 'plugin.json'

Report 'story.md exists' (-not [string]::IsNullOrWhiteSpace($engagement)) 'missing skills/video/references/story.md'
Report 'story.md diagnoses wall-to-wall speech and static picture' (
    $engagement -match 'Wall-to-wall speech' -and $engagement -match 'One visual held'
) 'Diagnose first must name those failure modes'
Report 'story.md maps music to accepted assets and Finish-Media duck' (
    $engagement -match 'Accepted, licensed bed asset' -and $engagement -match 'Finish-Media'
) 'Tools table must name the actual providers'
Report 'story.md keeps product-screencast off a parallel overlay stack' (
    $engagement -match 'Do not invent another overlay stack'
) 'Screencasts must not grow a parallel overlay stack'

Report 'producer loads story.md and scenes.md' (
    $producer -match 'references/story\.md' -and $producer -match 'references/scenes\.md'
) 'video SKILL.md does not name story.md and scenes.md'
Report 'review walks Diagnose first in story.md' (
    $qa -match 'references/story\.md' -and $qa -match 'Diagnose first'
) 'review SKILL.md does not name the Diagnose first table'

Report 'producer no longer skips music as the rapid default' (
    $producer -notmatch 'Skip Motif/lipsync/music unless needed'
) 'rapid path still tells the crew to skip music'
Report 'producer defaults intent to viewer-facing' (
    $producer -match 'intent: viewer-facing'
) 'producer must default viewer-facing'
Report 'producer pipeline ends in review of the encoded file' (
    $producer -match 'Review the encoded file'
) 'producer must review the encoded file'
Report 'producer crew includes storyboard then visuals then critic' (
    $producer -match 'storyboard, visual bible, direction' -and
    $producer -match 'Review the encoded file'
) 'rapid path must insert storyboard, visuals, and craft critic'
Report 'producer requires Remotion for viewer-facing briefing/training/explainer/series-episode' (
    $producer -match 'requires Remotion' -and $producer -match 'intent: draft'
) 'viewer-facing motion jobs must not silently fall back to static slides'
Report 'producer runs the script before the beat sheet' (
    $producer -match '(?s)2\. Script.*3\. Beat sheet'
) 'pipeline must not skip the beat sheet'
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
    $capture -match 'product-picture\.md' -and $capture -match 'story-experience' -and $capture -match 'not a second overlay stack'
) 'capture must not add a second overlay stack'

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
Report 'story and scene-archetype catalogs exist' (
    $craft -match 'Question' -and $craft -match 'Reveal' -and
    $archetypes -match 'kinetic-statement' -and $archetypes -match 'hero-reveal'
) 'missing story or scene-archetype library'
Report 'job schema has deliveryProfile and craftScoreMin' (
    $job -match '"deliveryProfile"' -and $job -match '"craftScoreMin"'
) 'job.schema.json missing delivery or craft gate'
Report 'job schema has programForm and webcast/teaser kinds' (
    $job -match '"programForm"' -and $job -match '"outcome-workflow"' -and $job -match '"webcast"' -and $job -match '"teaser"'
) 'job.schema.json missing library forms or broadcast kinds'
$picture = Read-Pkg 'skills\video\references\product-picture.md'
$forms = Read-Pkg 'skills\video\references\forms.md'
$studio = $storyboard
Report 'product-picture.md is the single interaction contract' (
    $picture -match 'start → locator → pointer lead → action → visible product response → result hold' -and
    $picture -match 'validate-product-picture' -and
    $picture -match 'defaults to `screen`' -and
    $producer -match 'product-picture.md' -and
    $capture -match 'product-picture.md' -and
    $compose -match 'product-picture.md' -and
    $qa -match 'validate-product-picture' -and
    $qa -notmatch 'Inspect-MediaVisualQuality.ps1 on the encoded file \(`ken-burns-on-still`' -and
    $critic -match 'MALFORMED_INPUT'
) 'product-picture contract missing from the crew or the critic still scores screencasts from text'
Report 'feature-tutorial and onboarding default to product-screencast' (
    $forms -match '`feature-tutorial`[^\n]+`product-screencast`' -and
    $forms -match '`onboarding`[^\n]+`product-screencast`'
) 'forms.md still defaults tutorials to Remotion training'
Report 'forms catalog exists' (
    $forms -match 'outcome-workflow' -and $forms -match 'ai-trust' -and $forms -match 'One promise'
) 'missing forms.md library'
Report 'scenes.md keeps studio craft' (
    $studio -match 'felt not heard' -and $studio -match 'Coverage'
) 'scenes.md lost studio craft'
Report 'producer infers programForm' (
    $producer -match 'programForm' -and $producer -match 'references/forms\.md'
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
