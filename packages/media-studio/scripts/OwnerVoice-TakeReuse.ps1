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
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
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
    if ($probe.allowlist) { $allow = @($probe.allowlist) }
    if ($probe.default_style) { $DefaultStyle = [string]$probe.default_style }
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

# A PASS receipt is reusable only when it provably belongs to this exact content.
#  - current receipt (has a fingerprint): the fingerprint must match.
#  - legacy receipt (no fingerprint: written before this check): it cannot prove the render text or the style
#    reference audio. It is accepted on the canonical sentence text, plus the recorded speaker when one was recorded,
#    plus the recorded style for owner segments. It stays on this weaker rule until the segment is regenerated or
#    re-gated, which writes a fingerprint. With no recorded text the take cannot be verified, so it is stale.
#  - role segments (Joel/Ryan/Vivian/Aiden) have no style reference, but the old writer stamped the owner default
#    style on every segment including role lines. A recorded style is therefore ignored for role segments.
function Test-PassReceipt([string]$SegDir, [string]$Fingerprint, [string]$Text, [string]$Style, [string]$Speaker = '', [bool]$IsOwner = $true) {
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
      if ($Speaker -and $names -contains 'speaker' -and $o.speaker) {
        if (-not ([string]$o.speaker -ieq $Speaker)) { return $false }
      }
      # ReGate-OwnerVoice.ps1 legacy receipts record the text (ASR-verified against it) but no style.
      if ($IsOwner -and $names -contains 'style' -and $o.style) { return ([string]$o.style -ceq $Style) }
      return $true
    }
    return $false
  } catch { return $false }
}
