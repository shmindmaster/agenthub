#Requires -Version 7.0
<#
.SYNOPSIS
  Fail-closed Sarosh (and role) voice for media-studio — batch path.

.DESCRIPTION
  Matches the series recipe that has shipped dozens of films:
    1. Allowlisted style only (default 02_explaining from _identity_probe.json)
    2. qwen-clone-batch — one model load per chunk (not per sentence)
    3. Batch ASR (ai.ps1 transcribe / Qwen3-ASR-1.7B)
    4. Speaker identity is ADVISORY ONLY and off by default (owner direction 2026-10-27: "identity is advisory
       only; never fail, block or re-voice on speaker similarity"). -AdvisoryIdentity runs ai.ps1 voice score
       --voice sarosh <dir> after the gate and records the numbers in the receipt for information. A low or
       missing score, or a scoring error, never fails a take, never blocks a release, never triggers a re-voice.
    5. Select on integrity + ASR only (real defects: dead air, clipping/level, truncation, wrong words); retry
       the fail set with a new seed then --premium
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
  # Retained so existing callers keep working. Speaker identity no longer gates anything (see .DESCRIPTION step 4),
  # so this switch has no effect.
  [switch]$SkipIdentity,
  # Opt-in: score owner takes with ai.ps1 voice score and record the numbers in the PASS receipt. Advisory only.
  [switch]$AdvisoryIdentity,
  [switch]$QuarantineAllAttempts,
  [switch]$SkipPronunciationListen,
  [string]$PronunciationLexicon,
  [string]$PronunciationOverrides,
  [int]$ListenMaxRounds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-Gpu([string]$Stage, [int]$MaxMinutes = 40, [int]$BusyMiB = 512) {
  # The TTS, ASR, identity and listen lanes each want the card to themselves; a Voxtral listen or a Remotion render
  # from another job makes ASR return nothing (every segment "wer=1") and would send a clean round back to TTS.
  # Key on VRAM, not on the compute-app count. The resident Local-AI retrieve service holds a CUDA context for the
  # life of the box, so "zero compute apps" never arrives and the wait deadlocks on an idle card. A real generation
  # lane takes gigabytes; a card carrying only resident services sits at a few hundred MiB.
  # BusyMiB matches the platform's unmanaged-observer ceiling in registry.json. That is deliberate: the platform
  # refuses a job with GPU_OCCUPIED_UNKNOWN whenever an unmanaged context is present AND the whole card is above
  # that ceiling, so a looser number here would report "free" and then hand off to a call certain to be refused --
  # which is exactly what happened when a TTS worker lingered at 4 GB and every listen came back with no report.
  $deadline = (Get-Date).AddMinutes($MaxMinutes)
  while ((Get-Date) -lt $deadline) {
    $usedMiB = $null
    try {
      $raw = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
      if ($raw) { $usedMiB = [int]($raw.ToString().Trim()) }
    } catch { return }
    if ($null -eq $usedMiB) { return }
    if ($usedMiB -lt $BusyMiB) { return }
    Write-Host ("  gpu busy before {0} ({1} MiB in use; free below {2} MiB); waiting" -f $Stage, $usedMiB, $BusyMiB)
    Start-Sleep -Seconds 15
  }
  throw ("STOP+LOG ({0}): the GPU never freed within {1} minutes (still above {2} MiB)" -f $Stage, $MaxMinutes, $BusyMiB)
}

# Shared with ReGate-OwnerVoice.ps1: hashing, render text, style reference, fingerprint, PASS-receipt reuse rule.
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'OwnerVoice-TakeReuse.ps1')

function Split-Sentences([string]$Text) {
  return @([regex]::Split($Text, '(?<=[.!?])\s+') | Where-Object { $_.Trim().Length -gt 2 } | ForEach-Object { $_.Trim() })
}

function Apply-AsrBrandAliases([string]$Text) {
  $path = Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\private\asr-brand-aliases.json'
  if (-not (Test-Path -LiteralPath $path)) { return $Text }
  $t = $Text
  foreach ($entry in @(Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)) {
    foreach ($variant in @($entry.variants)) { $t = $t.Replace([string]$variant, [string]$entry.canonical) }
  }
  return $t
}

function Normalize-ForAsr([string]$Text) {
  $t = $Text.ToLowerInvariant()
  # Spelled tip SHA used in #17 narration
  $t = $t.Replace('c-zero-one-b-one-three-five-eight', 'c01b1358')
  $t = $t.Replace('c zero one b one three five eight', 'c01b1358')
  # Brand aliases ASR often invents. Client brand names are private, so the
  # list lives outside the repo (runtime\private\asr-brand-aliases.json);
  # list possessive/plural variants first so a trailing s does not stick.
  $t = Apply-AsrBrandAliases $t
  $t = $t.Replace('field op slack', 'field ops slack')
  $t = $t.Replace('exclude tag', 'exclude-tag')
  # Spoken decimals ASR often emits as digits (normalize both sides before punctuation strip)
  foreach ($pair in @(
      @('twenty-two point nine percent', '22 9'),
      @('twenty two point nine percent', '22 9'),
      @('thirty-eight point two percent', '38 2'),
      @('thirty eight point two percent', '38 2'),
      @('eighty-one point six percent', '81 6'),
      @('eighty one point six percent', '81 6'),
      @('22.9%', '22 9'),
      @('22.9 percent', '22 9'),
      @('38.2%', '38 2'),
      @('38.2 percent', '38 2'),
      @('81.6%', '81 6'),
      @('81.6 percent', '81 6')
    )) {
    $t = $t.Replace($pair[0], $pair[1])
  }
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
    'thirty eight' = '38'
    'thirty-eight' = '38'
    'thirty two' = '32'
    'thirty-two' = '32'
    'twenty three' = '23'
    'twenty-three' = '23'
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
    'thirteenth' = '13'
    'fourteenth' = '14'
    'fifteenth' = '15'
    '15th' = '15'
    'eighth' = '8'
    '8th' = '8'
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

function Test-SegmentPass([object]$Segment) {
  # A persisted listen rejection (REJECTED.json) is honoured inside Test-PassReceipt, so it survives the process.
  return (Test-PassReceipt $Segment.dir $Segment.fingerprint $Segment.text $Segment.style $Segment.speaker ([bool]$Segment.isOwner) $Segment.renderText)
}

# Drop every artefact of a take that no longer matches its segment so it cannot be selected or concatenated.
function Clear-SegmentTake([object]$Segment) {
  foreach ($f in @('PASS.json', 'REJECTED.json', 'take.wav', 'take.render.json', 'take.asr.txt', 'take.identity.json', 'take.integrity.json')) {
    Remove-Item -LiteralPath (Join-Path $Segment.dir $f) -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath (Join-Path $selectedRoot "$($Segment.id).wav") -Force -ErrorAction SilentlyContinue
}

# Reject a still-valid take after a listen finding and queue it for regeneration, without deleting it. REJECTED.json is
# written first and persists, so a failed, interrupted or restarted run cannot reuse or concatenate the rejected take.
# The previous PASS.json and selected wav stay until the replacement passes the gate (which clears the rejection). Only
# the working files go, so the old evidence cannot gate the new take.
function Set-SegmentRedo([object]$Segment, [string]$Reason = 'pronunciation listen finding', [int]$Round = 0) {
  Write-TakeRejection $Segment.dir $Segment.id $Reason $Round
  foreach ($f in @('take.wav', 'take.render.json', 'take.asr.txt', 'take.identity.json', 'take.integrity.json')) {
    Remove-Item -LiteralPath (Join-Path $Segment.dir $f) -Force -ErrorAction SilentlyContinue
  }
}

# --- setup ---
if (-not (Test-Path -LiteralPath $LocalAi)) { throw "Local-AI control not found: $LocalAi" }
$Job = (Resolve-Path -LiteralPath $Job).Path
if (-not $ScreenplayPath) { $ScreenplayPath = Join-Path $Job 'screenplay.json' }
$play = Get-Content -LiteralPath $ScreenplayPath -Raw -Encoding UTF8 | ConvertFrom-Json

$styleCtx = Get-OwnerStyleContext $StylesRoot $DefaultStyle
$DefaultStyle = $styleCtx.DefaultStyle
$allow = $styleCtx.Allow
$script:StyleCache = @{}
function Get-StyleBundle([string]$Style) {
  if (-not $script:StyleCache.ContainsKey($Style)) { $script:StyleCache[$Style] = Get-CachedStyle $StylesRoot $Style }
  return $script:StyleCache[$Style]
}

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
  $sp = Resolve-SceneSpeaker $scene
  $speaker = $sp.Speaker
  $isOwner = $sp.IsOwner
  $roleSpeaker = $sp.RoleSpeaker

  $si = 0
  foreach ($text in @(Split-Sentences ([string]$scene.narration))) {
    $si++
    $segId = '{0}_{1:d2}' -f $id, $si
    $segDir = Join-Path $outRoot $segId
    $renderText = (Get-RenderText $text)
    $segStyle = ''
    $segStyleWav = ''
    $segStyleText = ''
    $segStyleWavSha = ''
    $segStyleTextSha = ''
    if ($isOwner) {
      $segStyle = Resolve-RequestedStyle $scene $DefaultStyle $allow
      $bundle = Get-StyleBundle $segStyle
      $segStyleWav = $bundle.Wav
      $segStyleText = $bundle.Text
      $segStyleWavSha = $bundle.WavSha
      $segStyleTextSha = $bundle.TextSha
    }
    New-Item -ItemType Directory -Force -Path $segDir | Out-Null
    $segments.Add([pscustomobject]@{
        id           = $segId
        sceneId      = $id
        speaker      = $speaker
        isOwner      = $isOwner
        roleSpeaker  = $roleSpeaker
        text         = $text
        renderText   = $renderText
        style        = $segStyle
        styleWav     = $segStyleWav
        styleText    = $segStyleText
        styleWavSha  = $segStyleWavSha
        styleTextSha = $segStyleTextSha
        fingerprint  = (Get-SegmentFingerprint $text $renderText $(if ($isOwner) { 'sarosh' } else { $roleSpeaker }) $segStyle $segStyleWavSha $segStyleTextSha)
        dir          = $segDir
        wav          = (Join-Path $segDir 'take.wav')
        seed         = 1000 + $si * 17
      })
  }
}

$stylesUsed = (@($segments | Where-Object { $_.isOwner } | ForEach-Object { $_.style } | Select-Object -Unique) -join ',')
Write-Host ("Plan: {0} segments  styles={1}  chunk={2}" -f $segments.Count, $stylesUsed, $ChunkSize)

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

# Segments (owner and role) that still need a take this round. A role segment is pending exactly like an owner one:
# gating only on owner segments left a changed Joel/Ryan/Vivian/Aiden line with stale or no audio.
function Get-PendingSegments {
  param([object[]]$All, [int]$Round)
  $pending = @()
  foreach ($s in $All) {
    if (Test-SegmentPass $s) { continue }
    # A rejected take keeps its old PASS receipt and selected wav until the new take passes (Set-SegmentRedo already
    # cleared the working files). Anything else failing the reuse rule is stale or failed: wipe it all so the batch
    # regenerates it.
    if (-not (Test-TakeRejected $s.dir)) { Clear-SegmentTake $s }
    $s.seed = 1000 + $Round * 997 + ([int]($s.id -replace '\D', '0') % 900)
    $pending += $s
  }
  return @($pending)
}

function Invoke-GenerationRounds {
for ($round = 1; $round -le $MaxRounds; $round++) {
  $premium = ($round -ge 3)
  $pendingAll = @(Get-PendingSegments -All $segments -Round $round)
  if ($pendingAll.Count -eq 0) {
    Write-Host "All segments have PASS receipts"
    break
  }
  # Record what each take is synthesized from, so a later re-gate can fingerprint the reading actually used.
  foreach ($s in $pendingAll) {
    Write-TakeRenderRecord $s.dir $s.text $s.renderText $(if ($s.isOwner) { 'sarosh' } else { $s.roleSpeaker }) $s.style $s.styleWavSha $s.styleTextSha
  }
  $pending = @($pendingAll | Where-Object { $_.isOwner })
  $pendingRole = @($pendingAll | Where-Object { -not $_.isOwner })
  Write-Host ("=== ROUND {0}/{1} pending={2} (owner={3} role={4}) premium={5} ===" -f $round, $MaxRounds, $pendingAll.Count, $pending.Count, $pendingRole.Count, $premium)

  # --- TTS batch (resident clone). One reference per style, so a quiet line is not fingerprinted as explaining.
  foreach ($group in @($pending | Group-Object -Property style)) {
    $members = @($group.Group)
    $sample = $members[0]
    if (-not $sample.styleWav -or -not $sample.styleText) { throw "Style '$($sample.style)' has no reference wav or transcript." }
    $jsonlLines = @()
    foreach ($s in $members) {
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
      $receipt = Join-Path $receiptDir ("clone-r{0}-{1}-c{2}.stdout.jsonl" -f $round, $sample.style, $c)
      Write-Host ("  TTS {0} {1}..{2} ({3} lines)" -f $sample.style, $c, ($c + $chunk.Count - 1), $chunk.Count)
      Invoke-CloneBatch -JsonlLines $chunk -Reference $sample.styleWav -RefText $sample.styleText -Premium:$premium -ReceiptPath $receipt
    }
  }

  # --- Role voices (small; one-shot is fine) ---
  foreach ($s in $pendingRole) {
    Write-Host ("  ROLE {0} speaker={1}" -f $s.id, $s.roleSpeaker)
    & $LocalAi voice qwen-role --speaker $s.roleSpeaker --text $s.renderText --out $s.wav 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "role TTS failed $($s.id)" }
  }

  # --- Integrity ---
  foreach ($s in $segments) {
    if (Test-SegmentPass $s) { continue }
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
      if (Test-SegmentPass $s) { continue }
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
      $asrAttempt = 0
      do {
        $asrAttempt++
        Wait-Gpu -Stage 'ASR'
        & $LocalAi transcribe $manifest --batch 2>&1 | Tee-Object -FilePath (Join-Path $receiptDir ("asr-r{0}-a{1}.log" -f $round, $asrAttempt)) | Out-Null
        $asrWritten = @($asrJobs | Where-Object { Test-Path -LiteralPath $_.out }).Count
        if ($asrWritten -eq 0) { Write-Warning ("ASR batch wrote no transcripts ({0} clips, attempt {1}); the ASR lane failed, this is not a speech verdict" -f $asrJobs.Count, $asrAttempt); Start-Sleep -Seconds 20 }
      } while ($asrWritten -eq 0 -and $asrAttempt -lt 2)
      if ($asrWritten -eq 0) { throw ("STOP+LOG (asr): the ASR lane returned nothing for {0} clips after {1} attempts; fix the lane (GPU, runtime) instead of regenerating speech" -f $asrJobs.Count, $asrAttempt) }
    }
  }

  # --- Batch identity (ADVISORY ONLY: opt-in, recorded for information, never gates a take) ---
  $idMap = @{}
  if ($AdvisoryIdentity) {
    try {
    $scoreDir = Join-Path $batchRoot ("score-r{0}" -f $round)
    if (Test-Path $scoreDir) { Remove-Item -LiteralPath $scoreDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $scoreDir | Out-Null
    foreach ($s in $segments) {
      if (-not $s.isOwner) { continue }
      if (Test-SegmentPass $s) { continue }
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
    } catch {
      Write-Warning ("advisory identity scoring failed ({0}); ignored, identity never gates a take" -f $_.Exception.Message)
    }
  }

  # --- Gate + PASS receipts ---
  foreach ($s in $segments) {
    if (Test-SegmentPass $s) { continue }
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
    # Identity is advisory: the numbers (when -AdvisoryIdentity scored them) are written down and never read back
    # into the verdict. A missing record, a low score or a scoring error leaves $pass untouched.
    $idScores = $null; $idAdvisory = $null
    if ($s.isOwner -and $AdvisoryIdentity -and $idMap.ContainsKey($s.id)) {
      $rec = $idMap[$s.id]
      $idScores = $rec.scores
      $idAdvisory = $rec.pass
      $rec | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $s.dir 'take.identity.json') -Encoding utf8
    }
    $pass = $integOk -and $asrOk -and (Test-Path $s.wav)
    Write-Host ("  GATE {0} integ={1} asr={2}(wer={3}) id=advisory({4}) => {5}" -f $s.id, $integOk, $asrOk, $wer, $(if ($null -eq $idAdvisory) { 'n/a' } else { $idAdvisory }), $(if ($pass) { 'PASS' } else { 'FAIL' }))
    if ($pass) {
      $dest = Join-Path $selectedRoot "$($s.id).wav"
      Copy-Item -LiteralPath $s.wav -Destination $dest -Force
      [ordered]@{
        pass = $true; id = $s.id; sceneId = $s.sceneId; speaker = $s.speaker
        style = $s.style; text = $s.text; renderText = $s.renderText; fingerprint = $s.fingerprint
        fingerprintSchema = $script:FingerprintSchema; path = $dest
        sha256 = (Get-Sha256 $dest); round = $round; premium = [bool]$premium
        asrWer = $wer; identityScores = $idScores; identityAdvisory = $true
      } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $s.dir 'PASS.json') -Encoding utf8
      Remove-Item -LiteralPath (Join-Path $s.dir 'REJECTED.json') -Force -ErrorAction SilentlyContinue
    }
  }
}

}

function Get-FailedSegments {
  return @($segments | Where-Object { -not (Test-SegmentPass $_) } | ForEach-Object { $_.id })
}

function Write-Ledger([object]$Listen) {
  $ledgerSegs = @()
  foreach ($s in $segments) {
    if (Test-SegmentPass $s) { $ledgerSegs += (Get-Content (Join-Path $s.dir 'PASS.json') -Raw -Encoding UTF8 | ConvertFrom-Json) }
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
  # Never concatenate a take that is not passed (a persisted listen rejection, a stale or missing receipt).
  $notPassed = @($segments | Where-Object { $_.sceneId -eq $id -and -not (Test-SegmentPass $_) } | ForEach-Object { $_.id })
  if ($notPassed.Count -gt 0) { throw ("STOP+LOG (concat): scene {0} has segments that are not passed: {1}" -f $id, ($notPassed -join ', ')) }
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
    # A fresh run reuses the same report name per scene and round; audio_review refuses to overwrite a stale
    # model-response sidecar from an earlier run, which read as "listen produced no report" and failed every segment.
    foreach ($stale in @($reportPath, "$reportPath.model-response.txt")) { Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue }
    Write-Host ("  LISTEN {0} ({1:n1}s, {2} segments, {3} risk rows)" -f $sceneId, $cursor, $sceneSegs.Count, $bases.Count)
    # ai.ps1 takes the audio path as the positional target and prepends --input itself.
    $listenArgs = @('listen', $sceneWav, '--output', $reportPath, '--candidate-id', "$sceneId-r$Round", '--transcript', $transcriptPath, '--pronunciation-manifest', $slicePath)
    # Always ground the listen with the timeline. audio_review gates its long-form chunking on the decoded
    # DURATION, not on this flag, so a short scene is unaffected by passing it -- but without it the listener's
    # claims cannot be checked against what the script actually says at the moment they point to, and a claim
    # naming a phrase from a later sentence blocks the release with nothing to contradict it.
    $listenArgs += @('--timeline', $timelinePath)
    # A listen that never ran is not a verdict on the speech. The lane fails for its own reasons
    # -- GPU_OCCUPIED_UNKNOWN while another lane holds the card, a crashed adapter -- and treating
    # that as "every segment failed" sends good takes back to TTS and burns the round budget, the
    # same way an empty ASR batch used to. Wait for the card and retry; only then give up, and give
    # up as a lane failure rather than a speech verdict.
    $listenLog = Join-Path $listenDir ("{0}.listen-r{1}.log" -f $sceneId, $Round)
    $listenAttempt = 0
    do {
      $listenAttempt++
      if ($listenAttempt -gt 1) { Wait-Gpu -Stage ("listen {0}" -f $sceneId) }
      & $LocalAi @listenArgs 2>&1 | Tee-Object -FilePath $listenLog | Out-Null
      if (-not (Test-Path -LiteralPath $reportPath)) {
        $whyMatch = Select-String -LiteralPath $listenLog -Pattern '"code":\s*"([A-Z_]+)"' -ErrorAction SilentlyContinue |
                Select-Object -Last 1
        $why = if ($whyMatch) { $whyMatch.Matches.Groups[1].Value } else { $null }
        Write-Warning ("listen produced no report for {0} (attempt {1}{2}); this is a lane failure, not a speech verdict" -f `
          $sceneId, $listenAttempt, $(if ($why) { ", $why" } else { "" }))
        # The sidecar from the failed attempt would be read as stale on the retry.
        foreach ($stale in @($reportPath, "$reportPath.model-response.txt")) { Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 20
      }
    } while (-not (Test-Path -LiteralPath $reportPath) -and $listenAttempt -lt 3)
    if (-not (Test-Path -LiteralPath $reportPath)) {
      throw ("STOP+LOG (listen): the listen lane returned no report for {0} after {1} attempts; fix the lane (GPU, runtime) instead of regenerating speech. Log: {2}" -f `
        $sceneId, $listenAttempt, $listenLog)
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
      if ($sg) { Set-SegmentRedo $sg ("pronunciation listen round {0}" -f $lr) $lr }
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
