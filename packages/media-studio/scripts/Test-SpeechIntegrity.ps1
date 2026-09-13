#Requires -Version 5.1
<#
.SYNOPSIS
  Fail-closed speech integrity checks (dead air, duration skew, silence).

.DESCRIPTION
  Returns exit 0 and JSON on stdout when the clip is usable.
  Exit 1 when any gate fails. Does not score speaker identity.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string]$Text,
  [double]$MinPeakDb = -40,
  [double]$MinRmsDb = -45,
  [double]$MinDurationFactor = 0.35,
  [double]$MaxDurationFactor = 4.5,
  [double]$WordsPerMinute = 150,
  [double]$MaxInternalSilenceSeconds = 2.5,
  [string]$JsonOut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "Speech file not found: $Path" }

$dur = [double](ffprobe -v error -show_entries format=duration -of csv=p=0 -- $Path)
$vol = ffmpeg -hide_banner -nostats -i $Path -af volumedetect -f null - 2>&1 | Out-String
$max = $null; $mean = $null
if ($vol -match 'max_volume:\s*([-\d.]+)\s*dB') { $max = [double]$Matches[1] }
if ($vol -match 'mean_volume:\s*([-\d.]+)\s*dB') { $mean = [double]$Matches[1] }

$expected = $null
$words = 0
if (-not [string]::IsNullOrWhiteSpace($Text)) {
  $words = @($Text.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)).Count
  if ($words -gt 0) { $expected = ($words / $WordsPerMinute) * 60.0 }
}

$silences = @()
$silReport = ffmpeg -hide_banner -nostats -i $Path -af "silencedetect=noise=-40dB:d=0.4" -f null - 2>&1 | Out-String
$starts = [regex]::Matches($silReport, 'silence_start:\s*([-\d.]+)')
$ends = [regex]::Matches($silReport, 'silence_end:\s*([-\d.]+)')
for ($i = 0; $i -lt [Math]::Min($starts.Count, $ends.Count); $i++) {
  $s = [double]$starts[$i].Groups[1].Value
  $e = [double]$ends[$i].Groups[1].Value
  $len = $e - $s
  # Ignore leading/trailing pad under 0.35s from ends
  $internal = ($s -gt 0.35) -and ($e -lt ($dur - 0.35))
  if ($internal -and $len -gt $MaxInternalSilenceSeconds) {
    $silences += [ordered]@{ start = $s; end = $e; seconds = [Math]::Round($len, 3) }
  }
}

$failures = @()
if ($null -eq $max -or $max -lt $MinPeakDb) { $failures += "peak_too_low:$max" }
if ($null -eq $mean -or $mean -lt $MinRmsDb) { $failures += "rms_too_low:$mean" }
if ($dur -lt 0.35) { $failures += "duration_too_short:$dur" }
if ($null -ne $expected -and $expected -gt 0) {
  $factor = $dur / $expected
  if ($factor -lt $MinDurationFactor -or $factor -gt $MaxDurationFactor) {
    $failures += ("duration_skew:got={0:n2}s expected~{1:n2}s factor={2:n2}" -f $dur, $expected, $factor)
  }
}
if ($silences.Count -gt 0) { $failures += ("internal_silence:{0}" -f ($silences | ConvertTo-Json -Compress)) }

$result = [ordered]@{
  path = $Path
  durationSeconds = [Math]::Round($dur, 3)
  maxVolumeDb = $max
  meanVolumeDb = $mean
  words = $words
  expectedDurationSeconds = $expected
  internalSilences = $silences
  pass = ($failures.Count -eq 0)
  failures = $failures
}

$json = $result | ConvertTo-Json -Depth 6 -Compress
if ($JsonOut) {
  $dir = Split-Path -Parent $JsonOut
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($JsonOut, ($result | ConvertTo-Json -Depth 6))
}
Write-Output $json
if (-not $result.pass) { exit 1 }
exit 0
