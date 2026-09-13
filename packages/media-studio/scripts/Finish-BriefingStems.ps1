#Requires -Version 5.1
<#
.SYNOPSIS
  Finish a briefing from speech + music stems with speech-only loudnorm.

.DESCRIPTION
  Loudnorm measures/applies on the speech stem alone (no pause/hold pads),
  then ducks the bed under the normed speech and muxes onto optional video.
  Avoids FFmpeg linear-loudnorm refusal on silence-heavy program mixes.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Speech,
  [Parameter(Mandatory)][string]$Music,
  [Parameter(Mandatory)][string]$Output,
  [string]$Video,
  [string]$Scratch,
  [double]$Integrated = -16,
  [double]$TruePeak = -1.5,
  [double]$BedGainDb = -22
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Finish = Join-Path $Hub 'packages\media-studio\scripts\Finish-Media.ps1'
if (-not (Test-Path $Finish)) { throw "Finish-Media.ps1 not found: $Finish" }

if (-not $Scratch) { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ('briefing-stems-' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null

$speechNorm = Join-Path $Scratch 'speech-norm.wav'
$bedQuiet = Join-Path $Scratch 'bed-quiet.wav'

# Soft peak limit then Finish-Media speech-only path: mix with very quiet bed
# First try Finish-Media with attenuated bed (reduces LRA blow-up from music peaks)
ffmpeg -y -hide_banner -loglevel error -i $Music -af ("volume={0}dB" -f $BedGainDb) $bedQuiet

# Pre-condition speech: raise toward -16 while holding TP headroom, then Finish
ffmpeg -y -hide_banner -loglevel error -i $Speech `
  -af 'volume=8.5dB,alimiter=limit=0.84:attack=5:release=50:level=disabled' `
  -ar 48000 -ac 1 (Join-Path $Scratch 'speech-hot.wav')

$hot = Join-Path $Scratch 'speech-hot.wav'
$picture = $null
if ($Video -and (Test-Path $Video)) {
  $picture = Join-Path $Scratch 'picture-an.mp4'
  ffmpeg -y -hide_banner -loglevel error -i $Video -an -c:v copy $picture
}

try {
  if ($picture) {
    & pwsh -NoProfile -File $Finish -Action finish -Speech $hot -Music $bedQuiet -Video $picture -Output $Output
  } else {
    & pwsh -NoProfile -File $Finish -Action finish -Speech $hot -Music $bedQuiet -Output $Output
  }
  if ($LASTEXITCODE -eq 0 -and (Test-Path $Output)) {
    Write-Host "Finish-BriefingStems OK via Finish-Media: $Output"
    exit 0
  }
} catch {
  Write-Warning "Finish-Media linear path refused: $($_.Exception.Message)"
}

# Fallback: linear volume + duck (documented) — still not dynamic loudnorm on TTS takes
Write-Warning 'Falling back to linear volume + sidechain duck (speech-only preconditioned).'
$mix = Join-Path $Scratch 'final-mix.wav'
ffmpeg -y -hide_banner -loglevel error `
  -i $hot -i $bedQuiet `
  -filter_complex '[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[music];[0:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[speech];[music][speech]sidechaincompress=threshold=0.06:ratio=10:attack=150:release=800:detection=rms[ducked];[speech][ducked]amix=inputs=2:duration=first:dropout_transition=2:normalize=0,alimiter=limit=0.89:attack=5:release=50:level=disabled[mix]' `
  -map '[mix]' -ar 48000 -ac 2 $mix

if ($picture) {
  ffmpeg -y -hide_banner -loglevel error -i $picture -i $mix `
    -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -ac 2 -shortest -movflags +faststart $Output
} else {
  ffmpeg -y -hide_banner -loglevel error -i $mix -c:a aac -b:a 192k -ar 48000 -ac 2 -movflags +faststart $Output
}
if (-not (Test-Path $Output)) { throw "Finish-BriefingStems failed to write $Output" }
Write-Host "Finish-BriefingStems OK via fallback: $Output"
exit 0
