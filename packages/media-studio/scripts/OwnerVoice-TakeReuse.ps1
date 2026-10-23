#Requires -Version 7.0
<#
.SYNOPSIS
  Shared take-reuse rules for Generate-OwnerVoice.ps1 and ReGate-OwnerVoice.ps1.

.DESCRIPTION
  Dot-source this file; it only defines functions and one schema constant, and runs nothing.
  A PASS receipt is reusable only when it provably belongs to the exact content now being spoken, so both writers
  of PASS.json (generation and re-gate) must record the same fingerprint and both readers must judge it the same way.
  Get-RenderText expects the caller's $LocalAi (path to ai.ps1) in scope.
#>

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextSha256([string]$Text) {
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
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

# Resolve the owner style reference: allowlist and default from the identity probe, then the wav/transcript the
# fingerprint covers. Throws when no allowlisted style or no wav exists.
function Get-OwnerStyleContext([string]$StylesRoot, [string]$DefaultStyle) {
  $probePath = Join-Path $StylesRoot '_identity_probe.json'
  $allow = @($DefaultStyle)
  if (Test-Path -LiteralPath $probePath) {
    $probe = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8 | ConvertFrom-Json
    # Optional members: a bare property read throws under strict mode when the probe omits them.
    $probeNames = @($probe.PSObject.Properties | ForEach-Object { $_.Name })
    if ($probeNames -contains 'allowlist' -and $probe.allowlist) { $allow = @($probe.allowlist) }
    if ($probeNames -contains 'default_style' -and $probe.default_style) { $DefaultStyle = [string]$probe.default_style }
  }
  if ($allow.Count -eq 0) { throw "No allowlisted Sarosh styles. Run style identity probe first." }
  if ($allow -notcontains $DefaultStyle) { $DefaultStyle = $allow[0] }

  $styleWav = Join-Path $StylesRoot "$DefaultStyle.wav"
  $styleTxtPath = Join-Path $StylesRoot "$DefaultStyle.txt"
  if (-not (Test-Path $styleWav)) { throw "Missing style wav: $styleWav" }
  $styleTxt = (Get-Content -LiteralPath $styleTxtPath -Raw -Encoding UTF8).Trim()
  return [pscustomobject]@{
    DefaultStyle = $DefaultStyle
    Allow        = $allow
    Wav          = $styleWav
    Text         = $styleTxt
    WavSha       = (Get-Sha256 $styleWav)
    TextSha      = (Get-TextSha256 $styleTxt)
  }
}

# A scene may ask for an allowlisted style. voiceStyle wins over style. Anything else is the default.
# An unlisted name throws: a quiet line must not be rendered on the explaining reference.
function Resolve-RequestedStyle([object]$Scene, [string]$DefaultStyle, [string[]]$Allow) {
  $style = $DefaultStyle
  if ($null -ne $Scene) {
    $names = @($Scene.PSObject.Properties.Name)
    foreach ($key in @('voiceStyle', 'style')) {
      if ($names -contains $key -and $Scene.$key) { $style = [string]$Scene.$key; break }
    }
  }
  if ($Allow -notcontains $style) { throw "Style '$style' is not allowlisted ($($Allow -join ', '))." }
  return $style
}

function Get-CachedStyle([string]$StylesRoot, [string]$Style) {
  $wav = Join-Path $StylesRoot "$Style.wav"
  $txtPath = Join-Path $StylesRoot "$Style.txt"
  if (-not (Test-Path -LiteralPath $wav)) { throw "Missing style wav: $wav" }
  if (-not (Test-Path -LiteralPath $txtPath)) { throw "Missing style transcript: $txtPath" }
  $text = (Get-Content -LiteralPath $txtPath -Raw -Encoding UTF8).Trim()
  return [pscustomobject]@{
    Style   = $Style
    Wav     = $wav
    Text    = $text
    WavSha  = (Get-Sha256 $wav)
    TextSha = (Get-TextSha256 $text)
  }
}

# Fingerprint of everything that decides what a take sounds like: the canonical sentence, the exact text sent to the
# engine (after Get-RenderText normalisation), the voice, and the style reference (name, wav bytes, transcript).
# Seed, round and premium are deliberately excluded: they vary between retries of the same content.
# Reuse is keyed on this, never on the segment id, so a changed script line cannot ship old audio.
$script:FingerprintSchema = 'owner-voice-take/1'
function Get-SegmentFingerprint([string]$Text, [string]$RenderText, [string]$Voice, [string]$Style, [string]$StyleWavSha, [string]$StyleTextSha) {
  $canon = @(
    "schema=$script:FingerprintSchema", "voice=$Voice", "style=$Style", "styleWav=$StyleWavSha", "styleText=$StyleTextSha",
    "text=$Text", "render=$RenderText"
  ) -join "`n"
  return (Get-TextSha256 $canon)
}

# Scene speaker -> owner or role voice. Shared so ReGate-OwnerVoice.ps1 (which scores owner identity only) can skip
# role scenes instead of stamping them as the owner.
function Resolve-SceneSpeaker([object]$Scene) {
  $speaker = 'sarosh'
  if (@($Scene.PSObject.Properties.Name) -contains 'speaker' -and $Scene.speaker) { $speaker = [string]$Scene.speaker }
  $isOwner = $true
  $roleSpeaker = $null
  if ($speaker -eq 'joel') { $isOwner = $false; $roleSpeaker = 'Ryan' }
  elseif ($speaker -in @('Ryan', 'Vivian', 'Aiden', 'ryan', 'vivian', 'aiden')) {
    $isOwner = $false
    $roleSpeaker = (Get-Culture).TextInfo.ToTitleCase($speaker.ToLower())
  }
  return [pscustomobject]@{ Speaker = $speaker; IsOwner = $isOwner; RoleSpeaker = $roleSpeaker }
}

# What a take was synthesized from, written beside it before synthesis starts. A later re-gate fingerprints with this
# record, because the current render text may differ from the one an older wav was made with.
function Write-TakeRenderRecord([string]$Dir, [string]$Text, [string]$RenderText, [string]$Voice, [string]$Style, [string]$StyleWavSha, [string]$StyleTextSha) {
  $rec = [ordered]@{
    schema = 'owner-voice-render/1'; text = $Text; renderText = $RenderText; voice = $Voice
    style = $Style; styleWavSha = $StyleWavSha; styleTextSha = $StyleTextSha
  }
  [System.IO.File]::WriteAllText((Join-Path $Dir 'take.render.json'), ($rec | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}

function Get-TakeRenderRecord([string]$Dir) {
  $p = Join-Path $Dir 'take.render.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try {
    $o = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($o.PSObject.Properties.Name)
    foreach ($n in @('text', 'renderText', 'voice', 'style', 'styleWavSha', 'styleTextSha')) {
      if ($names -notcontains $n) { return $null }
    }
    return $o
  } catch { return $null }
}

# A listen rejection is persisted beside PASS.json so it outlives the process. While REJECTED.json exists the take is
# not passed, whatever its receipt says; it is cleared only when a replacement passes the gate.
function Test-TakeRejected([string]$SegDir) {
  return (Test-Path -LiteralPath (Join-Path $SegDir 'REJECTED.json'))
}

function Write-TakeRejection([string]$SegDir, [string]$Id, [string]$Reason, [int]$Round) {
  $rec = [ordered]@{ rejected = $true; id = $Id; reason = $Reason; round = $Round; rejectedAt = (Get-Date).ToUniversalTime().ToString('o') }
  [System.IO.File]::WriteAllText((Join-Path $SegDir 'REJECTED.json'), ($rec | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}

# A PASS receipt is reusable only when it provably belongs to this exact content.
#  - a persisted listen rejection (REJECTED.json) makes the take not passed.
#  - current receipt (has a fingerprint): the fingerprint must match.
#  - legacy receipt (no fingerprint: written before this check, or by ReGate when the synthesized render text was
#    unknown): it cannot prove the style reference audio, so it is accepted only when all of these hold:
#      * the recorded canonical text matches;
#      * the recorded speaker matches the segment speaker. A role segment needs a recorded speaker; a receipt
#        without one counts only for owner segments (old ReGate scored owner identity only);
#      * the current render text equals the canonical text (no pronunciation substitution applies), or the receipt
#        recorded the render text and it equals the current one;
#      * for owner segments, the recorded style when one was recorded.
#    It stays on this weaker rule until the segment is regenerated or re-gated with a render record.
#  - role segments (Joel/Ryan/Vivian/Aiden) have no style reference, but the old writer stamped the owner default
#    style on every segment including role lines. A recorded style is therefore ignored for role segments.
function Test-PassReceipt([string]$SegDir, [string]$Fingerprint, [string]$Text, [string]$Style, [string]$Speaker = '', [bool]$IsOwner = $true, [string]$RenderText = '') {
  if (-not $PSBoundParameters.ContainsKey('RenderText')) { $RenderText = $Text }
  if (Test-TakeRejected $SegDir) { return $false }
  $p = Join-Path $SegDir 'PASS.json'
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  try {
    $o = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$o.pass) { return $false }
    $names = @($o.PSObject.Properties.Name)
    if ($names -contains 'fingerprint' -and $o.fingerprint) {
      return ([string]$o.fingerprint -ceq $Fingerprint)
    }
    if ($names -contains 'text' -and $o.text) {
      if (-not ([string]$o.text -ceq $Text)) { return $false }
      $hasSpeaker = ($names -contains 'speaker' -and $o.speaker)
      if (-not $IsOwner -and -not $hasSpeaker) { return $false }
      if ($Speaker -and $hasSpeaker -and -not ([string]$o.speaker -ieq $Speaker)) { return $false }
      if (-not ($RenderText -ceq $Text)) {
        if (-not ($names -contains 'renderText' -and $o.renderText)) { return $false }
        if (-not ([string]$o.renderText -ceq $RenderText)) { return $false }
      }
      if ($IsOwner -and $names -contains 'style' -and $o.style) { return ([string]$o.style -ceq $Style) }
      return $true
    }
    return $false
  } catch { return $false }
}
