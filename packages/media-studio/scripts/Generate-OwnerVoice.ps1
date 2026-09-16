#Requires -Version 7.0
<#
.SYNOPSIS
  Fail-closed Sarosh (and role) voice for media-studio — batch path.

.DESCRIPTION
  Matches the series recipe that has shipped dozens of films:
    1. Allowlisted style only (default 02_explaining from _identity_probe.json)
    2. qwen-clone-batch — one model load per chunk (not per sentence)
    3. Batch ASR (ai.ps1 transcribe / Qwen3-ASR-1.7B)
    4. Batch identity (ai.ps1 voice score --voice sarosh <dir>)
    5. Select only dual-pass; retry fail set with new seed then --premium
    6. Pronunciation-risk manifest (ai.ps1 voice pronunciation-risk) before generation; a heteronym
       whose reading cannot be inferred stops the run until the writer records an override
    7. Per-scene ai.ps1 listen (Voxtral, local) on the concatenated scene audio with the canonical
       transcript and the scene's slice of the risk manifest; a pronunciation, pacing or artifact
       finding regenerates the localized segment and listens again (ListenMaxRounds)

  Never reuses a WAV that lacks a PASS receipt. Never invents style IDs.
  Canonical narration is never phonetic-respelled.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Job,
  [string]$ScreenplayPath,
  [string]$LocalAi = $(if ($env:LOCAL_AI_ROOT) { Join-Path $env:LOCAL_AI_ROOT 'ai.ps1' } else { 'D:\Local-AI\ai.ps1' }),
  [string]$StylesRoot = 'D:\Local-AI\data\artifacts\media\voice-corpus\voices\sarosh\styles-20260815',
  [string]$DefaultStyle = '02_explaining',
  [string[]]$SceneIds,
  [int]$ChunkSize = 4,
  [int]$MaxRounds = 3,
  [double]$AsrWerMax = 0.38,
  [switch]$SkipAsr,
  [switch]$SkipIdentity,
  [switch]$QuarantineAllAttempts,
  [switch]$SkipPronunciationListen,
  [string]$PronunciationLexicon,
  [string]$PronunciationOverrides,
  [int]$ListenMaxRounds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Split-Sentences([string]$Text) {
  return @([regex]::Split($Text, '(?<=[.!?])\s+') | Where-Object { $_.Trim().Length -gt 2 } | ForEach-Object { $_.Trim() })
}

function Normalize-ForAsr([string]$Text) {
  $t = $Text.ToLowerInvariant()
  # Spelled tip SHA used in #17 narration
  $t = $t.Replace('c-zero-one-b-one-three-five-eight', 'c01b1358')
  $t = $t.Replace('c zero one b one three five eight', 'c01b1358')
  # Brand aliases ASR often invents
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
  foreach ($k in $numberWords.Keys) {
    $t = $t.Replace($k, [string]$numberWords[$k])
  }
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

function Get-RenderText([string]$Canonical) {
  $py = Join-Path (Split-Path $LocalAi -Parent) 'runtimes\media\audio-qa\Scripts\python.exe'
  $script = Join-Path (Split-Path $LocalAi -Parent) 'media\qa\pronounce.py'
  if (-not (Test-Path $py) -or -not (Test-Path $script)) { return $Canonical }
  $tmpIn = [IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmpIn, $Canonical)
    $raw = & $py $script --file $tmpIn --engine qwen-clone 2>&1 | Out-String
    $obj = $raw | ConvertFrom-Json
    if ($obj.applied) { return [string]$obj.applied }
  } catch {
    Write-Warning "pronounce.py apply failed; using canonical text"
  } finally {
    Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue
  }
  return $Canonical
}

function Invoke-CloneBatch {
  param(
    [string[]]$JsonlLines,
    [string]$Reference,
    [string]$RefText,
    [switch]$Premium,
    [string]$ReceiptPath
  )
  if (@($JsonlLines).Count -eq 0) { return }
  $pendingPath = [IO.Path]::ChangeExtension($ReceiptPath, '.pending.jsonl')
  $enriched = foreach ($line in $JsonlLines) {
    $job = $line | ConvertFrom-Json
    $hash = [ordered]@{}
    foreach ($p in $job.PSObject.Properties) { $hash[$p.Name] = $p.Value }
    $hash['reference'] = $Reference
    $hash['ref_text'] = $RefText
    ConvertTo-Json -Compress $hash
  }
  [System.IO.File]::WriteAllLines($pendingPath, @($enriched), [System.Text.UTF8Encoding]::new($false))

  # Same ProcessStartInfo.ArgumentList pattern as series generate-audio.ps1 —
  # never flatten multi-word args through Start-Process -ArgumentList string.
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = (Get-Process -Id $PID).Path
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  # Replies are UTF-8 JSON lines; the console code page (ibm437) would mangle any non-ASCII in them.
  # The job list goes as a file on purpose: a StandardInput pipe best-fit-maps typographic quotes.
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.RedirectStandardError = $false
  foreach ($a in @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $LocalAi,
      'voice', 'qwen-clone-batch', '--voice', 'sarosh',
      '--batch-jsonl', $pendingPath
    )) {
    [void]$psi.ArgumentList.Add([string]$a)
  }
  if ($Premium) { [void]$psi.ArgumentList.Add('--premium') }

  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $proc.WaitForExit()
  [System.IO.File]::WriteAllText($ReceiptPath, $stdout, [System.Text.UTF8Encoding]::new($false))
  if ($proc.ExitCode -ne 0) {
    throw ("qwen-clone-batch failed exit={0} receipt={1}" -f $proc.ExitCode, $ReceiptPath)
  }
}

function Test-PassReceipt([string]$SegDir) {
  $p = Join-Path $SegDir 'PASS.json'
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  try {
    $o = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return [bool]$o.pass
  } catch { return $false }
}

# --- setup ---
if (-not (Test-Path -LiteralPath $LocalAi)) { throw "Local-AI control not found: $LocalAi" }
$Job = (Resolve-Path -LiteralPath $Job).Path
if (-not $ScreenplayPath) { $ScreenplayPath = Join-Path $Job 'screenplay.json' }
$play = Get-Content -LiteralPath $ScreenplayPath -Raw -Encoding UTF8 | ConvertFrom-Json

$probePath = Join-Path $StylesRoot '_identity_probe.json'
$allow = @($DefaultStyle)
if (Test-Path -LiteralPath $probePath) {
  $probe = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($probe.allowlist) { $allow = @($probe.allowlist) }
  if ($probe.default_style) { $DefaultStyle = [string]$probe.default_style }
}
if ($allow.Count -eq 0) { throw "No allowlisted Sarosh styles. Run style identity probe first." }
if ($allow -notcontains $DefaultStyle) { $DefaultStyle = $allow[0] }

$styleWav = Join-Path $StylesRoot "$DefaultStyle.wav"
$styleTxtPath = Join-Path $StylesRoot "$DefaultStyle.txt"
if (-not (Test-Path $styleWav)) { throw "Missing style wav: $styleWav" }
$styleTxt = (Get-Content -LiteralPath $styleTxtPath -Raw -Encoding UTF8).Trim()

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Integrity = Join-Path $ScriptDir 'Test-SpeechIntegrity.ps1'

$outRoot = Join-Path $Job 'voice\sentences'
$selectedRoot = Join-Path $Job 'voice\selected'
$batchRoot = Join-Path $Job 'voice\batches'
$receiptDir = Join-Path $Job 'voice\receipts'
$ledgerPath = Join-Path $Job 'voice\selection-ledger.json'
New-Item -ItemType Directory -Force -Path $outRoot, $selectedRoot, $batchRoot, $receiptDir | Out-Null

if ($QuarantineAllAttempts) {
  Write-Host "Quarantine: wiping prior sentence attempts + selected (no PASS reuse from bad styles)"
  Get-ChildItem -LiteralPath $outRoot -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  Get-ChildItem -LiteralPath $selectedRoot -Filter '*.wav' -ErrorAction SilentlyContinue | Remove-Item -Force
}

# Build segment list
$segments = [System.Collections.Generic.List[object]]::new()
$ids = if ($SceneIds -and $SceneIds.Count) { @($SceneIds) } else { @($play.scenes | ForEach-Object { $_.id }) }
foreach ($id in $ids) {
  $scene = @($play.scenes | Where-Object { $_.id -eq $id })[0]
  if (-not $scene) { throw "Missing scene $id" }
  $speaker = 'sarosh'
  if ($scene.PSObject.Properties.Name -contains 'speaker' -and $scene.speaker) {
    $speaker = [string]$scene.speaker
  }
  $isOwner = $true
  $roleSpeaker = $null
  if ($speaker -eq 'joel') { $isOwner = $false; $roleSpeaker = 'Ryan' }
  elseif ($speaker -in @('Ryan', 'Vivian', 'Aiden', 'ryan', 'vivian', 'aiden')) {
    $isOwner = $false
    $roleSpeaker = (Get-Culture).TextInfo.ToTitleCase($speaker.ToLower())
  }

  $si = 0
  foreach ($text in @(Split-Sentences ([string]$scene.narration))) {
    $si++
    $segId = '{0}_{1:d2}' -f $id, $si
    $segDir = Join-Path $outRoot $segId
    New-Item -ItemType Directory -Force -Path $segDir | Out-Null
    $segments.Add([pscustomobject]@{
        id           = $segId
        sceneId      = $id
        speaker      = $speaker
        isOwner      = $isOwner
        roleSpeaker  = $roleSpeaker
        text         = $text
        renderText   = (Get-RenderText $text)
        dir          = $segDir
        wav          = (Join-Path $segDir 'take.wav')
        seed         = 1000 + $si * 17
      })
  }
}

Write-Host ("Plan: {0} segments  style={1}  chunk={2}" -f $segments.Count, $DefaultStyle, $ChunkSize)

# --- Pronunciation risk (before any audio exists) ---
# The manifest is what `ai.ps1 listen` judges against. Without it the listener hears fluent speech and
# reports nothing, which is how the 2026-08-31 ABACare candidates passed with "record"/"records"
# and "content"/"content-approval" unexamined. Canonical text is never respelled here.
$qaDir = Join-Path $Job 'qa'
New-Item -ItemType Directory -Force -Path $qaDir | Out-Null
$riskSegmentsPath = Join-Path $Job 'voice\narration-segments.json'
@{ segments = @($segments | ForEach-Object { @{ id = $_.id; sceneId = $_.sceneId; speaker = $_.speaker; text = $_.text } }) } |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $riskSegmentsPath -Encoding utf8
$riskPath = Join-Path $qaDir 'pronunciation-risk.json'
$riskArgs = @('voice', 'pronunciation-risk', '--segments', $riskSegmentsPath, '--out', $riskPath, '--script-id', (Split-Path $Job -Leaf), '--fail-on', 'FAIL')
if ($PronunciationLexicon) { $riskArgs += @('--lexicon', $PronunciationLexicon) }
if ($PronunciationOverrides) { $riskArgs += @('--overrides', $PronunciationOverrides) }
& $LocalAi @riskArgs | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $riskPath)) {
  throw "STOP: pronunciation-risk manifest failed ($riskPath). A heteronym reading could not be inferred: add -PronunciationOverrides ({sceneSegmentId:{term:readingId}}) or reword, then rerun."
}
$risk = Get-Content -LiteralPath $riskPath -Raw -Encoding UTF8 | ConvertFrom-Json
$riskySegIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rs in @($risk.segments)) {
  foreach ($o in @($rs.occurrences)) {
    if ($o.riskClass -eq 'heteronym' -or $o.status -ne 'verified') { [void]$riskySegIds.Add([string]$rs.segmentId) }
  }
}
$riskyScenes = @($segments | Where-Object { $riskySegIds.Contains($_.id) } | ForEach-Object { $_.sceneId } | Select-Object -Unique)
Write-Host ("Pronunciation risk: status={0} occurrences={1} unverified={2} listen-scenes={3}" -f $risk.coverage.status, $risk.coverage.occurrenceCount, @($risk.coverage.unverifiedTerms).Count, $riskyScenes.Count)

function Get-PendingOwner {
  param([object[]]$All, [int]$Round)
  $pending = @()
  foreach ($s in $All) {
    if (-not $s.isOwner) { continue }
    if (Test-PassReceipt $s.dir) { continue }
    # wipe failed take so batch regenerates
    Remove-Item -LiteralPath $s.wav -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $s.dir 'take.asr.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $s.dir 'take.identity.json') -Force -ErrorAction SilentlyContinue
    $s.seed = 1000 + $Round * 997 + ([int]($s.id -replace '\D', '0') % 900)
    $pending += $s
  }
  return @($pending)
}

function Invoke-GenerationRounds {
for ($round = 1; $round -le $MaxRounds; $round++) {
  $premium = ($round -ge 3)
  $pending = @(Get-PendingOwner -All $segments -Round $round)
  if ($pending.Count -eq 0) {
    Write-Host "All owner segments have PASS receipts"
    break
  }
  Write-Host ("=== ROUND {0}/{1} pending={2} premium={3} ===" -f $round, $MaxRounds, $pending.Count, $premium)

  # --- TTS batch (resident clone) ---
  $jsonlLines = @()
  foreach ($s in $pending) {
    $words = @($s.renderText -split '\s+' | Where-Object { $_ }).Count
    $tokens = [Math]::Min(280, [Math]::Max(96, 40 + ($words * 8)))
    $jsonlLines += (ConvertTo-Json -Compress @{
        text           = $s.renderText
        out            = $s.wav
        language       = 'English'
        seed           = $s.seed
        max_new_tokens = $tokens
        canonical_text = $s.text
      })
  }
  for ($c = 0; $c -lt $jsonlLines.Count; $c += $ChunkSize) {
    $chunk = @($jsonlLines[$c..([Math]::Min($c + $ChunkSize, $jsonlLines.Count) - 1)])
    $receipt = Join-Path $receiptDir ("clone-r{0}-c{1}.stdout.jsonl" -f $round, $c)
    Write-Host ("  TTS chunk {0}..{1} ({2} lines)" -f $c, ($c + $chunk.Count - 1), $chunk.Count)
    Invoke-CloneBatch -JsonlLines $chunk -Reference $styleWav -RefText $styleTxt -Premium:$premium -ReceiptPath $receipt
  }

  # --- Role voices (small; one-shot is fine) ---
  foreach ($s in $segments) {
    if ($s.isOwner) { continue }
    if (Test-PassReceipt $s.dir) { continue }
    Remove-Item -LiteralPath $s.wav -Force -ErrorAction SilentlyContinue
    Write-Host ("  ROLE {0} speaker={1}" -f $s.id, $s.roleSpeaker)
    & $LocalAi voice qwen-role --speaker $s.roleSpeaker --text $s.renderText --out $s.wav 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "role TTS failed $($s.id)" }
  }

  # --- Integrity ---
  foreach ($s in $segments) {
    if (Test-PassReceipt $s.dir) { continue }
    if (-not (Test-Path -LiteralPath $s.wav) -or (Get-Item $s.wav).Length -lt 1000) {
      Write-Warning "Missing/tiny wav $($s.id)"
      continue
    }
    $ij = Join-Path $s.dir 'take.integrity.json'
    & pwsh -NoProfile -File $Integrity -Path $s.wav -Text $s.text -JsonOut $ij 2>$null | Out-Null
  }

  # --- Batch ASR ---
  if (-not $SkipAsr) {
    $asrJobs = @()
    foreach ($s in $segments) {
      if (Test-PassReceipt $s.dir) { continue }
      if (-not (Test-Path -LiteralPath $s.wav)) { continue }
      $asrOut = Join-Path $s.dir 'take.asr.txt'
      Remove-Item -LiteralPath $asrOut -Force -ErrorAction SilentlyContinue
      $asrJobs += @{ source = $s.wav; out = $asrOut }
    }
    if ($asrJobs.Count -gt 0) {
      $manifest = Join-Path $batchRoot ("asr-r{0}.json" -f $round)
      @{ schema = 'local-ai/stt-batch/1'; jobs = $asrJobs } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $manifest -Encoding utf8
      Write-Host ("  ASR batch {0} clips" -f $asrJobs.Count)
      & $LocalAi transcribe $manifest --batch 2>&1 | Tee-Object -FilePath (Join-Path $receiptDir ("asr-r{0}.log" -f $round)) | Out-Null
    }
  }

  # --- Batch identity ---
  $idMap = @{}
  if (-not $SkipIdentity) {
    $scoreDir = Join-Path $batchRoot ("score-r{0}" -f $round)
    if (Test-Path $scoreDir) { Remove-Item -LiteralPath $scoreDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $scoreDir | Out-Null
    foreach ($s in $segments) {
      if (-not $s.isOwner) { continue }
      if (Test-PassReceipt $s.dir) { continue }
      if (-not (Test-Path -LiteralPath $s.wav)) { continue }
      Copy-Item -LiteralPath $s.wav -Destination (Join-Path $scoreDir "$($s.id).wav") -Force
    }
    $scored = @(Get-ChildItem -LiteralPath $scoreDir -Filter '*.wav' -ErrorAction SilentlyContinue)
    if ($scored.Count -gt 0) {
      $idJson = Join-Path $receiptDir ("identity-r{0}.json" -f $round)
      Write-Host ("  IDENTITY batch {0} clips" -f $scored.Count)
      & $LocalAi voice score --voice sarosh --quiet --json $idJson $scoreDir
      if (Test-Path $idJson) {
        $idObj = Get-Content -LiteralPath $idJson -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($rec in @($idObj.records)) {
          $stem = [IO.Path]::GetFileNameWithoutExtension([string]$rec.path)
          $idMap[$stem] = $rec
        }
      }
    }
  }

  # --- Gate + PASS receipts ---
  foreach ($s in $segments) {
    if (Test-PassReceipt $s.dir) { continue }
    $integOk = $false
    $ij = Join-Path $s.dir 'take.integrity.json'
    if (Test-Path $ij) {
      $integOk = [bool](Get-Content $ij -Raw -Encoding UTF8 | ConvertFrom-Json).pass
    }
    $asrOk = $true; $wer = $null
    if (-not $SkipAsr) {
      $asrTxt = Join-Path $s.dir 'take.asr.txt'
      $hyp = if (Test-Path $asrTxt) { (Get-Content $asrTxt -Raw -Encoding UTF8).Trim() } else { '' }
      $wer = Get-Wer $s.text $hyp
      $asrOk = ($wer -le $AsrWerMax)
      $rw = @((Normalize-ForAsr $s.text) -split '\s+' | Where-Object { $_ }).Count
      $hw = @((Normalize-ForAsr $hyp) -split '\s+' | Where-Object { $_ }).Count
      if ($hw -gt (([double]$rw * 1.6) + 4.0)) { $asrOk = $false }
    }
    $idOk = $true; $idScores = $null
    if ($s.isOwner -and -not $SkipIdentity) {
      $rec = $idMap[$s.id]
      if ($null -eq $rec) { $idOk = $false }
      else {
        $idOk = [bool]$rec.pass
        $idScores = $rec.scores
        $rec | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $s.dir 'take.identity.json') -Encoding utf8
      }
    }
    $pass = $integOk -and $asrOk -and $idOk -and (Test-Path $s.wav)
    Write-Host ("  GATE {0} integ={1} asr={2}(wer={3}) id={4} => {5}" -f $s.id, $integOk, $asrOk, $wer, $idOk, $(if ($pass) { 'PASS' } else { 'FAIL' }))
    if ($pass) {
      $dest = Join-Path $selectedRoot "$($s.id).wav"
      Copy-Item -LiteralPath $s.wav -Destination $dest -Force
      [ordered]@{
        pass = $true; id = $s.id; sceneId = $s.sceneId; speaker = $s.speaker
        style = $DefaultStyle; text = $s.text; path = $dest
        sha256 = (Get-Sha256 $dest); round = $round; premium = [bool]$premium
        asrWer = $wer; identityScores = $idScores
      } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $s.dir 'PASS.json') -Encoding utf8
    }
  }
}

}

function Get-FailedSegments {
  return @($segments | Where-Object { -not (Test-PassReceipt $_.dir) } | ForEach-Object { $_.id })
}

function Write-Ledger([object]$Listen) {
  $ledgerSegs = @()
  foreach ($s in $segments) {
    if (Test-PassReceipt $s.dir) { $ledgerSegs += (Get-Content (Join-Path $s.dir 'PASS.json') -Raw -Encoding UTF8 | ConvertFrom-Json) }
  }
  [ordered]@{
    job = (Split-Path $Job -Leaf)
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    defaultStyle = $DefaultStyle
    allowlist = $allow
    pronunciationRisk = @{ path = $riskPath; status = $risk.coverage.status; sha256 = (Get-Sha256 $riskPath) }
    pronunciationListen = $Listen
    segments = $ledgerSegs
    failed = @(Get-FailedSegments)
  } | ConvertTo-Json -Depth 8 | Set-Content $ledgerPath -Encoding utf8
}

function Assert-AllPassed([string]$Stage) {
  $failedNow = @(Get-FailedSegments)
  if ($failedNow.Count -gt 0) {
    Write-Ledger $null
    $failLog = Join-Path $Job 'voice\FAILED_SEGMENTS.log'
    $failedNow | Set-Content $failLog
    throw ("STOP+LOG ({0}): {1} segments failed after {2} rounds: {3}" -f $Stage, $failedNow.Count, $MaxRounds, ($failedNow -join ', '))
  }
}

Invoke-GenerationRounds
Assert-AllPassed 'generate'

# Concat per scene
function Invoke-SceneConcat([string[]]$Only) {
foreach ($id in $ids) {
  if ($Only -and $Only.Count -and ($Only -notcontains $id)) { continue }
  $parts = @($segments | Where-Object { $_.sceneId -eq $id } | ForEach-Object { Join-Path $selectedRoot "$($_.id).wav" })
  if ($parts.Count -eq 0) { continue }
  $sr = ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 -- $parts[0]
  $gap = Join-Path $outRoot '_gap.wav'
  ffmpeg -y -hide_banner -loglevel error -f lavfi -i "anullsrc=r=${sr}:cl=mono" -t 0.18 $gap
  $list = Join-Path $outRoot "$id.concat.txt"
  $lines = @()
  for ($p = 0; $p -lt $parts.Count; $p++) {
    $lines += "file '$($parts[$p].Replace('\', '/'))'"
    if ($p -lt $parts.Count - 1) { $lines += "file '$($gap.Replace('\', '/'))'" }
  }
  $lines | Set-Content -Encoding ascii $list
  $sceneWav = Join-Path $Job "voice\$id.wav"
  ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i $list $sceneWav
  Write-Host "wrote $sceneWav"
}
}
Invoke-SceneConcat @()

# --- Pronunciation listen per scene (local Voxtral, grounded in transcript + risk slice) ---
function Get-WavSeconds([string]$Path) {
  return [double](ffprobe -v error -show_entries format=duration -of csv=p=0 -- $Path)
}

function Invoke-PronunciationListen([string[]]$Scenes, [int]$Round) {
  $listenDir = Join-Path $Job 'voice\listen'
  New-Item -ItemType Directory -Force -Path $listenDir | Out-Null
  $redo = [System.Collections.Generic.List[string]]::new()
  $results = @()
  foreach ($sceneId in $Scenes) {
    $sceneSegs = @($segments | Where-Object { $_.sceneId -eq $sceneId })
    if ($sceneSegs.Count -eq 0) { continue }
    $sceneWav = Join-Path $Job "voice\$sceneId.wav"
    if (-not (Test-Path -LiteralPath $sceneWav)) { continue }
    # Offsets of each segment inside the scene concat (0.18 s gap between segments).
    $cursor = 0.0
    $spans = @()
    foreach ($sg in $sceneSegs) {
      $d = Get-WavSeconds (Join-Path $selectedRoot "$($sg.id).wav")
      $spans += [pscustomobject]@{ id = $sg.id; start = $cursor; end = ($cursor + $d); text = $sg.text }
      $cursor += $d + 0.18
    }
    $transcriptPath = Join-Path $listenDir "$sceneId.transcript.txt"
    [IO.File]::WriteAllText($transcriptPath, (($sceneSegs | ForEach-Object { $_.text }) -join "`n"), [Text.UTF8Encoding]::new($false))
    $segIdSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($sceneSegs | ForEach-Object { $_.id }), [StringComparer]::OrdinalIgnoreCase)
    $sliceSegments = @($risk.segments | Where-Object { $segIdSet.Contains([string]$_.segmentId) })
    $bases = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rs in $sliceSegments) { foreach ($o in @($rs.occurrences)) { [void]$bases.Add([string]$o.dictionaryBase) } }
    $slice = [ordered]@{
      schemaVersion = $risk.schemaVersion; generator = $risk.generator; scriptId = $risk.scriptId; sceneId = $sceneId
      dictionary = @($risk.dictionary | Where-Object { $bases.Contains([string]$_.term) })
      segments = $sliceSegments
    }
    $slicePath = Join-Path $listenDir "$sceneId.pronunciation-manifest.json"
    $slice | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $slicePath -Encoding utf8
    $timelinePath = Join-Path $listenDir "$sceneId.timeline.json"
    @{ segments = @($spans | ForEach-Object { @{ id = $_.id; text = $_.text; audioStartSeconds = $_.start; audioEndSeconds = $_.end } }) } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $timelinePath -Encoding utf8
    $reportPath = Join-Path $listenDir ("{0}.listen-r{1}.json" -f $sceneId, $Round)
    Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
    Write-Host ("  LISTEN {0} ({1:n1}s, {2} segments, {3} risk rows)" -f $sceneId, $cursor, $sceneSegs.Count, $bases.Count)
    # ai.ps1 takes the audio path as the positional target and prepends --input itself.
    $listenArgs = @('listen', $sceneWav, '--output', $reportPath, '--candidate-id', "$sceneId-r$Round", '--transcript', $transcriptPath, '--pronunciation-manifest', $slicePath)
    if ($cursor -gt 90) { $listenArgs += @('--timeline', $timelinePath) }
    & $LocalAi @listenArgs 2>&1 | Tee-Object -FilePath (Join-Path $listenDir ("{0}.listen-r{1}.log" -f $sceneId, $Round)) | Out-Null
    if (-not (Test-Path -LiteralPath $reportPath)) {
      Write-Warning "listen produced no report for $sceneId (see log); treating every segment as failed"
      foreach ($sg in $sceneSegs) { $redo.Add($sg.id) }
      $results += [ordered]@{ scene = $sceneId; round = $Round; status = 'NO_REPORT'; report = $null; redo = @($sceneSegs | ForEach-Object { $_.id }) }
      continue
    }
    $rep = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sceneRedo = @()
    if ($rep.status -ne 'PASS') {
      foreach ($f in @($rep.findings)) {
        $hit = $null
        if ($null -ne $f.startSeconds) {
          $t = [double]$f.startSeconds
          $hit = @($spans | Where-Object { $t -ge ($_.start - 0.25) -and $t -le ($_.end + 0.25) } | Select-Object -First 1)[0]
        }
        if ($hit) { $sceneRedo += $hit.id } else { $sceneRedo += @($spans | ForEach-Object { $_.id }) }
      }
      $sceneRedo = @($sceneRedo | Select-Object -Unique)
      foreach ($x in $sceneRedo) { $redo.Add($x) }
    }
    $results += [ordered]@{ scene = $sceneId; round = $Round; status = $rep.status; report = $reportPath; reportSha256 = (Get-Sha256 $reportPath); findings = @($rep.findings | ForEach-Object { [ordered]@{ checkId = $_.checkId; severity = $_.severity; startSeconds = $_.startSeconds; description = $_.description } }); redo = $sceneRedo }
    Write-Host ("    {0} -> {1}{2}" -f $sceneId, $rep.status, $(if ($sceneRedo.Count) { "  redo: " + ($sceneRedo -join ',') } else { '' }))
  }
  return [pscustomobject]@{ redo = @($redo | Select-Object -Unique); results = $results }
}

$listenSummary = [ordered]@{ skipped = [bool]$SkipPronunciationListen; rounds = @(); finalStatus = $null }
if (-not $SkipPronunciationListen -and $riskyScenes.Count -gt 0) {
  $scenesToListen = @($riskyScenes)
  for ($lr = 1; $lr -le $ListenMaxRounds; $lr++) {
    $lres = Invoke-PronunciationListen -Scenes $scenesToListen -Round $lr
    $listenSummary.rounds += [ordered]@{ round = $lr; scenes = $scenesToListen; results = $lres.results; redo = $lres.redo }
    if ($lres.redo.Count -eq 0) { $listenSummary.finalStatus = 'PASS'; break }
    if ($lr -eq $ListenMaxRounds) {
      $listenSummary.finalStatus = 'FAIL'
      $listenSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $qaDir 'pronunciation-listen.json') -Encoding utf8
      Write-Ledger $listenSummary
      throw ("STOP+LOG (listen): pronunciation/delivery findings persist after {0} listen rounds in segments: {1}. Reword, add a dictionary entry, or record an override; do not ship." -f $ListenMaxRounds, ($lres.redo -join ', '))
    }
    Write-Host ("  regenerating {0} segments after listen findings: {1}" -f $lres.redo.Count, ($lres.redo -join ', '))
    foreach ($segId in $lres.redo) {
      $sg = @($segments | Where-Object { $_.id -eq $segId })[0]
      Remove-Item -LiteralPath (Join-Path $sg.dir 'PASS.json') -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $sg.wav -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath (Join-Path $selectedRoot "$($sg.id).wav") -Force -ErrorAction SilentlyContinue
      $sg.seed = 5000 + $lr * 331 + ([int]($sg.id -replace '\D', '0') % 900)
    }
    Invoke-GenerationRounds
    Assert-AllPassed "regenerate-after-listen-r$lr"
    $scenesToListen = @($segments | Where-Object { $lres.redo -contains $_.id } | ForEach-Object { $_.sceneId } | Select-Object -Unique)
    Invoke-SceneConcat $scenesToListen
  }
} elseif ($riskyScenes.Count -eq 0) {
  $listenSummary.finalStatus = 'NOT_NEEDED'
}
$listenSummary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $qaDir 'pronunciation-listen.json') -Encoding utf8
Write-Ledger $listenSummary

Write-Host ("Generate-OwnerVoice complete ledger={0} segments={1} pronunciationListen={2}" -f $ledgerPath, $segments.Count, $listenSummary.finalStatus)
