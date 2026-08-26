#Requires -Version 5.1
<#
Pins the viewer-facing engagement contract in packages/media-studio:

- engagement.md is the single craft home
- producer/writer/director/generate/compose/qa load it
- rapid path no longer skips music for viewer-facing jobs
- job and screenplay schemas carry intent, hook, pauses, musicCue
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
$director = Read-Pkg 'skills\media-director\SKILL.md'
$generate = Read-Pkg 'skills\media-studio-generate\SKILL.md'
$compose = Read-Pkg 'skills\media-studio-compose\SKILL.md'
$qa = Read-Pkg 'skills\media-studio-qa\SKILL.md'
$capture = Read-Pkg 'skills\media-studio-capture\SKILL.md'
$job = Read-Pkg 'schemas\job.schema.json'
$play = Read-Pkg 'schemas\screenplay.schema.json'
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
        @{ Name = 'director'; Text = $director },
        @{ Name = 'generate'; Text = $generate },
        @{ Name = 'compose'; Text = $compose },
        @{ Name = 'qa'; Text = $qa }
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
) 'producer step 7 must run an engagement pass'
Report 'generate makes a viewer-facing bed unless draft or music none' (
    $generate -match 'Viewer-facing' -and $generate -match 'musicCue: bed'
) 'generate must produce the directed bed for viewer-facing jobs'
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

$plugin = $manifest | ConvertFrom-Json
Report 'plugin.json version is 1.3.0 or newer' (
    [version]$plugin.version -ge [version]'1.3.0'
) "plugin.json version is $($plugin.version)"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
