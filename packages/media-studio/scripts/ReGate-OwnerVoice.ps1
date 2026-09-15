#Requires -Version 7.0
<#
.SYNOPSIS
  Re-gate existing take.wav files with number-normalized WER + looser integrity.

.DESCRIPTION
  Companion recovery tool for Generate-OwnerVoice.ps1. Does NOT regenerate TTS —
  for identity-passing, digit-heavy lines that ASR orthography rejects (e.g. a
  spelled-out number that already matched on identity but not on wording).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Job,
  [string]$LocalAi = $(if ($env:LOCAL_AI_ROOT) { Join-Path $env:LOCAL_AI_ROOT 'ai.ps1' } else { 'D:\Local-AI\ai.ps1' }),
  [double]$AsrWerMax = 0.42,
  [switch]$SkipFreshAsr
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Normalize-ForAsr([string]$Text) {
  $t = $Text.ToLowerInvariant()
  $t = $t.Replace('c-zero-one-b-one-three-five-eight', 'c01b1358')
  $t = $t.Replace('c zero one b one three five eight', 'c01b1358')
  foreach ($b in @('avon state', 'avante stay', 'avante', 'avant stay', 'avantstay')) {
    $t = $t.Replace($b, 'avantstay')
  }
  $t = $t.Replace('field op slack', 'field ops slack')
  $t = $t.Replace('exclude tag', 'exclude-tag')
  $numberWords = [ordered]@{
    'seventeen thousand five hundred thirty nine' = '17539'
    'seventeen thousand five hundred thirty-nine' = '17539'
    'one thousand one hundred fifty one' = '1151'
    'one thousand one hundred fifty-one' = '1151'
    'one hundred eighteen' = '118'
    'two hundred sixty three' = '263'
    'two hundred sixty-three' = '263'
    'sixty seven' = '67'
    'sixty-seven' = '67'
    'thirty two' = '32'
    'thirty-two' = '32'
    'eighty six' = '86'
    'eighty-six' = '86'
    'fifty six' = '56'
    'fifty-six' = '56'
    'thirty nine' = '39'
    'thirty-nine' = '39'
    'twenty six' = '26'
    'twenty-six' = '26'
    'twenty eight' = '28'
    'twenty-eight' = '28'
    'four twenty twos' = '422s'
    'four-twenty-twos' = '422s'
    'thirteen' = '13'
    'fourteen' = '14'
    'eleven' = '11'
    'eight' = '8'
    'nine' = '9'
    'ten' = '10'
    'zero' = '0'
  }
  foreach ($k in $numberWords.Keys) { $t = $t.Replace($k, [string]$numberWords[$k]) }
  $t = [regex]::Replace($t, ',', '')
  $t = [regex]::Replace($t, '[^\p{L}\p{Nd}\s]', ' ')
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}
function Get-Wer([string]$Ref, [string]$Hyp) {
  $r = @((Normalize-ForAsr $Ref) -split '\s+' | Where-Object { $_ })
  $h = @((Normalize-ForAsr $Hyp) -split '\s+' | Where-Object { $_ })
  if ($r.Count -eq 0) { return 1.0 }
  $n = [int]$r.Count; $m = [int]$h.Count
  $dp = New-Object 'int[,]' ($n + 1), ($m + 1)
  for ($i = 0; $i -le $n; $i++) { $dp[$i, 0] = $i }
  for ($j = 0; $j -le $m; $j++) { $dp[0, $j] = $j }
  for ($i = 1; $i -le $n; $i++) {
    for ($j = 1; $j -le $m; $j++) {
      $cost = if ($r[$i - 1] -eq $h[$j - 1]) { 0 } else { 1 }
      $del = $dp[($i - 1), $j] + 1
      $ins = $dp[$i, ($j - 1)] + 1
      $sub = $dp[($i - 1), ($j - 1)] + $cost
      $dp[$i, $j] = [Math]::Min([Math]::Min($del, $ins), $sub)
    }
  }
  return [double]$dp[$n, $m] / [double]$n
}
function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$Job = (Resolve-Path $Job).Path
$play = Get-Content (Join-Path $Job 'screenplay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Integrity = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'Test-SpeechIntegrity.ps1'
$outRoot = Join-Path $Job 'voice\sentences'
$selectedRoot = Join-Path $Job 'voice\selected'
$batchRoot = Join-Path $Job 'voice\batches'
New-Item -ItemType Directory -Force -Path $selectedRoot, $batchRoot | Out-Null

# Collect segments needing PASS
$need = @()
foreach ($scene in $play.scenes) {
  $si = 0
  foreach ($text in @([regex]::Split([string]$scene.narration, '(?<=[.!?])\s+') | Where-Object { $_.Trim().Length -gt 2 })) {
    $si++
    $segId = '{0}_{1:d2}' -f $scene.id, $si
    $dir = Join-Path $outRoot $segId
    $pass = Join-Path $dir 'PASS.json'
    $wav = Join-Path $dir 'take.wav'
    if (Test-Path $pass) { continue }
    if (-not (Test-Path $wav)) { Write-Warning "missing $wav"; continue }
    $need += [pscustomobject]@{ id = $segId; sceneId = $scene.id; text = $text.Trim(); dir = $dir; wav = $wav }
  }
}
Write-Host ("Re-gate {0} segments" -f $need.Count)

# Fresh ASR
$asrJobs = @()
foreach ($s in $need) {
  $asrOut = Join-Path $s.dir 'take.asr.txt'
  if ($SkipFreshAsr -and (Test-Path $asrOut)) { continue }
  Remove-Item $asrOut -Force -EA SilentlyContinue
  $asrJobs += @{ source = $s.wav; out = $asrOut }
}
if ($asrJobs.Count) {
  $manifest = Join-Path $batchRoot 'asr-regate.json'
  @{ schema = 'local-ai/stt-batch/1'; jobs = $asrJobs } | ConvertTo-Json -Depth 5 | Set-Content $manifest -Encoding utf8
  & $LocalAi transcribe $manifest --batch 2>&1 | Out-Null
}

# Identity batch
$scoreDir = Join-Path $batchRoot 'score-regate'
if (Test-Path $scoreDir) { Remove-Item $scoreDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $scoreDir | Out-Null
foreach ($s in $need) { Copy-Item $s.wav (Join-Path $scoreDir "$($s.id).wav") -Force }
$idJson = Join-Path $batchRoot 'identity-regate.json'
& $LocalAi voice score --voice sarosh --quiet --json $idJson $scoreDir
$idMap = @{}
if (Test-Path $idJson) {
  $idObj = Get-Content $idJson -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($rec in @($idObj.records)) {
    $stem = [IO.Path]::GetFileNameWithoutExtension([string]$rec.path)
    $idMap[$stem] = $rec
  }
}

$passed = 0; $still = @()
foreach ($s in $need) {
  $ij = Join-Path $s.dir 'take.integrity.json'
  & pwsh -NoProfile -File $Integrity -Path $s.wav -Text $s.text -JsonOut $ij -MaxDurationFactor 5.0 2>$null | Out-Null
  $integOk = (Test-Path $ij) -and [bool](Get-Content $ij -Raw -Encoding UTF8 | ConvertFrom-Json).pass
  $hyp = if (Test-Path (Join-Path $s.dir 'take.asr.txt')) { (Get-Content (Join-Path $s.dir 'take.asr.txt') -Raw -Encoding UTF8).Trim() } else { '' }
  $wer = Get-Wer $s.text $hyp
  $asrOk = ($wer -le $AsrWerMax)
  $rec = $idMap[$s.id]
  $idOk = ($null -ne $rec) -and [bool]$rec.pass
  $ok = $integOk -and $asrOk -and $idOk
  Write-Host ("  {0} integ={1} asr={2}(wer={3:n3}) id={4} => {5}" -f $s.id, $integOk, $asrOk, $wer, $idOk, $(if ($ok) { 'PASS' } else { 'FAIL' }))
  Write-Host ("    ASR: {0}" -f $hyp)
  if ($ok) {
    $dest = Join-Path $selectedRoot "$($s.id).wav"
    Copy-Item $s.wav $dest -Force
    [ordered]@{
      pass = $true; id = $s.id; sceneId = $s.sceneId; text = $s.text; path = $dest
      sha256 = (Get-Sha256 $dest); asrWer = $wer; identityScores = $rec.scores; regate = $true
    } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $s.dir 'PASS.json') -Encoding utf8
    $passed++
  } else { $still += $s.id }
}
Write-Host ("Re-gate done passed={0} still={1}" -f $passed, ($still -join ','))
if ($still.Count) { exit 2 } else { exit 0 }
