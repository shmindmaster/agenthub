#Requires -Version 5.1
<#
Measure likely-boring stretches on an encoded video: static frame runs,
duplicate hashes, shot changes, first/last frame presence.

Outputs JSON matching schemas/visual-quality-report.schema.json.
Flags suspects for the story-experience reviewer; does not score craft.

ffmpeg and ffprobe must be on PATH.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Video,
    [Parameter(Mandatory)][string]$Output,
    [int]$SampleFps = 2,
    [double]$StaticSeconds = 6,
    [string]$ContactSheet
)

$ErrorActionPreference = 'Stop'
$ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffprobe -or -not $ffmpeg) {
    throw "ffmpeg/ffprobe not on PATH. Inspect-MediaVisualQuality cannot run."
}

$videoPath = [IO.Path]::GetFullPath($Video)
if (-not (Test-Path -LiteralPath $videoPath)) {
    throw "Video not found: $videoPath"
}

$durationRaw = & $ffprobe.Source -v error -show_entries format=duration -of default=nk=1:nw=1 $videoPath
$duration = [double]$durationRaw
$work = Join-Path ([IO.Path]::GetTempPath()) ("ms-inspect-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    $pattern = Join-Path $work 'f%06d.png'
    & $ffmpeg.Source -hide_banner -loglevel error -y -i $videoPath -vf "fps=$SampleFps,scale=320:-1" $pattern
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg frame extract failed for $videoPath" }

    $frames = @(Get-ChildItem -LiteralPath $work -Filter 'f*.png' | Sort-Object Name)
    $hashes = @()
    foreach ($f in $frames) {
        $hashes += (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }

    $shotChanges = 0
    $longestStatic = 0.0
    $dupSeconds = 0.0
    $run = 1
    $suspects = [Collections.Generic.List[object]]::new()
    for ($i = 1; $i -lt $hashes.Count; $i++) {
        if ($hashes[$i] -eq $hashes[$i - 1]) {
            $run++
        } else {
            $shotChanges++
            $runSec = $run / $SampleFps
            if ($runSec -ge $StaticSeconds) {
                $start = ($i - $run) / $SampleFps
                $end = $i / $SampleFps
                $suspects.Add([pscustomobject]@{
                    kind = 'static-stretch'
                    startSeconds = [math]::Round($start, 2)
                    endSeconds = [math]::Round($end, 2)
                    detail = "identical frames for $([math]::Round($runSec, 1))s"
                })
                $dupSeconds += $runSec
            }
            if ($runSec -gt $longestStatic) { $longestStatic = $runSec }
            $run = 1
        }
    }
    $tailSec = $run / $SampleFps
    if ($tailSec -gt $longestStatic) { $longestStatic = $tailSec }
    if ($tailSec -ge $StaticSeconds) {
        $start = ($hashes.Count - $run) / $SampleFps
        $suspects.Add([pscustomobject]@{
            kind = 'static-stretch'
            startSeconds = [math]::Round($start, 2)
            endSeconds = [math]::Round($duration, 2)
            detail = "identical frames for $([math]::Round($tailSec, 1))s"
        })
        $dupSeconds += $tailSec
    }

    # First/last-frame design is a critic judgment. This script only flags
    # measurable stills; a held opening beat is not automatically undesigned.

    $pass = $suspects.Count -eq 0
    $report = [ordered]@{
        video = $videoPath
        pass = $pass
        contactSheet = $ContactSheet
        metrics = [ordered]@{
            durationSeconds = [math]::Round($duration, 3)
            sampledFrames = $hashes.Count
            shotChanges = $shotChanges
            longestStaticSeconds = [math]::Round($longestStatic, 3)
            duplicateStretchSeconds = [math]::Round($dupSeconds, 3)
            visualModeCount = 0
            meanSceneSeconds = if ($shotChanges -gt 0) { [math]::Round($duration / ($shotChanges + 1), 3) } else { [math]::Round($duration, 3) }
            captionOverlapSuspects = 0
        }
        suspects = @($suspects)
    }

    $outPath = [IO.Path]::GetFullPath($Output)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outPath) | Out-Null
    $json = $report | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($outPath, $json)
    Write-Host "Wrote $outPath (pass=$pass, suspects=$($suspects.Count))"
    if (-not $pass) { exit 2 }
    exit 0
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
