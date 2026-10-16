#Requires -Version 7.0
<#
Pins take reuse in packages/media-studio/scripts/Generate-OwnerVoice.ps1.

A previously PASSed take is reusable only when it provably belongs to the exact content now being spoken. Before
this check, reuse was keyed on the segment id, so a changed script line kept its old audio (seen: W01_L2).

The script's real functions are extracted from its AST and run against temp directories. No TTS, ASR, GPU,
Local-AI call or ffmpeg is involved.

Run: pwsh -NoProfile -File tests/Test-OwnerVoiceTakeReuse.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $repoRoot 'packages\media-studio\scripts\Generate-OwnerVoice.ps1'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

# --- load the production functions from the script's AST ---
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
Report 'Generate-OwnerVoice.ps1 parses' ($parseErrors.Count -eq 0) "parse errors: $($parseErrors.Count)"

$wanted = @('Get-Sha256', 'Get-TextSha256', 'Get-SegmentFingerprint', 'Test-PassReceipt', 'Test-SegmentPass', 'Clear-SegmentTake', 'Get-PendingOwner')
$missing = @()
foreach ($name in $wanted) {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { $missing += $name; continue }
    . ([scriptblock]::Create($fn.Extent.Text))
}
Report 'script defines every reuse function' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
$schemaAssign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:FingerprintSchema' }, $true)
Report 'script defines FingerprintSchema' ($null -ne $schemaAssign) 'assignment missing'
if ($missing.Count -gt 0 -or -not $schemaAssign) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($schemaAssign.Extent.Text))

# --- fixtures ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("ownervoice-reuse-" + [guid]::NewGuid().ToString('N'))
$outRoot = Join-Path $work 'sentences'
$selectedRoot = Join-Path $work 'selected'
New-Item -ItemType Directory -Force -Path $outRoot, $selectedRoot | Out-Null

function New-Seg([string]$Id, [string]$Text, [string]$Render = $Text, [string]$Voice = 'sarosh', [string]$Style = '02_explaining',
                 [string]$WavSha = 'wavsha-A', [string]$TxtSha = 'txtsha-A', [bool]$Owner = $true) {
    $dir = Join-Path $outRoot $Id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [pscustomobject]@{
        id = $Id; isOwner = $Owner; text = $Text; renderText = $Render; style = $Style; dir = $dir
        wav = (Join-Path $dir 'take.wav'); seed = 1
        fingerprint = (Get-SegmentFingerprint $Text $Render $Voice $Style $WavSha $TxtSha)
    }
}
function Write-Take([object]$Seg, [string]$Kind) {
    # Lays down the artefacts a finished segment leaves behind. Kind: current | legacy | legacy-notext | legacy-fail | corrupt
    [IO.File]::WriteAllText($Seg.wav, 'audio')
    [IO.File]::WriteAllText((Join-Path $selectedRoot "$($Seg.id).wav"), 'audio')
    [IO.File]::WriteAllText((Join-Path $Seg.dir 'take.asr.txt'), 'asr')
    $p = Join-Path $Seg.dir 'PASS.json'
    switch ($Kind) {
        'current'       { [ordered]@{ pass = $true; id = $Seg.id; style = $Seg.style; text = $Seg.text; fingerprint = $Seg.fingerprint } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'legacy'        { [ordered]@{ pass = $true; id = $Seg.id; style = $Seg.style; text = $Seg.text } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'regate'        { [ordered]@{ pass = $true; id = $Seg.id; text = $Seg.text; regate = $true } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'legacy-notext' { [ordered]@{ pass = $true; id = $Seg.id } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'legacy-fail'   { [ordered]@{ pass = $false; id = $Seg.id; style = $Seg.style; text = $Seg.text } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'corrupt'       { Set-Content $p -Value '{ not json' -Encoding utf8 }
    }
}

try {
    # Strict mode is what the production script runs under; run every case under it too.
    Set-StrictMode -Version Latest

    # 1. fingerprint properties
    $a = Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'sarosh' '02_explaining' 'w' 't'
    Report 'fingerprint is stable for identical inputs' ($a -ceq (Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'sarosh' '02_explaining' 'w' 't')) 'not deterministic'
    Report 'fingerprint is a 64-char sha256 hex' ($a -match '^[0-9a-f]{64}$') $a
    $variants = @{
        text   = (Get-SegmentFingerprint 'Hello there!' 'Hello there.' 'sarosh' '02_explaining' 'w' 't')
        render = (Get-SegmentFingerprint 'Hello there.' 'Hello thare.' 'sarosh' '02_explaining' 'w' 't')
        voice  = (Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'Ryan' '02_explaining' 'w' 't')
        style  = (Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'sarosh' '03_warm' 'w' 't')
        wav    = (Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'sarosh' '02_explaining' 'w2' 't')
        txt    = (Get-SegmentFingerprint 'Hello there.' 'Hello there.' 'sarosh' '02_explaining' 'w' 't2')
    }
    foreach ($k in $variants.Keys) {
        Report "fingerprint changes when $k changes" ($variants[$k] -cne $a) 'fingerprint unchanged'
    }

    # 2. same text -> reuse
    $s1 = New-Seg 'W01_L1_01' 'The registry is the source of truth.'
    Write-Take $s1 'current'
    Report 'same text: PASS receipt is reused' (Test-SegmentPass $s1) 'reuse refused for identical content'
    $pending = @(Get-PendingOwner -All @($s1) -Round 1)
    Report 'same text: segment is not queued for regeneration' ($pending.Count -eq 0) "pending=$($pending.Count)"
    Report 'same text: selected take is left in place' (Test-Path (Join-Path $selectedRoot 'W01_L1_01.wav')) 'selected wav was removed'

    # 3. changed text under the same segment id -> regenerate (the W01_L2 case)
    $old = New-Seg 'W01_L2_01' 'Old words that were approved yesterday.'
    Write-Take $old 'current'
    $new = New-Seg 'W01_L2_01' 'New words after the script line changed.'
    Report 'changed text: old PASS receipt is not reused' (-not (Test-SegmentPass $new)) 'stale audio would ship'
    $pending = @(Get-PendingOwner -All @($new) -Round 1)
    Report 'changed text: segment is queued for regeneration' ($pending.Count -eq 1 -and $pending[0].id -eq 'W01_L2_01') "pending=$($pending.Count)"
    Report 'changed text: stale PASS.json removed' (-not (Test-Path (Join-Path $new.dir 'PASS.json'))) 'PASS.json survived'
    Report 'changed text: stale take.wav removed' (-not (Test-Path $new.wav)) 'take.wav survived'
    Report 'changed text: stale selected wav removed' (-not (Test-Path (Join-Path $selectedRoot 'W01_L2_01.wav'))) 'selected wav survived, concat would use old audio'

    # 4. other content changes under the same text
    $base = New-Seg 'W02_L1_01' 'Same sentence.' 'Same sentence.'
    Write-Take $base 'current'
    Report 'changed render text (pronunciation layer): not reused' (-not (Test-SegmentPass (New-Seg 'W02_L1_01' 'Same sentence.' 'Same sentance.'))) 'stale'
    Report 'changed style reference audio: not reused' (-not (Test-SegmentPass (New-Seg 'W02_L1_01' 'Same sentence.' 'Same sentence.' 'sarosh' '02_explaining' 'wavsha-B'))) 'stale'
    Report 'changed style name: not reused' (-not (Test-SegmentPass (New-Seg 'W02_L1_01' 'Same sentence.' 'Same sentence.' 'sarosh' '03_warm'))) 'stale'
    Report 'changed voice: not reused' (-not (Test-SegmentPass (New-Seg 'W02_L1_01' 'Same sentence.' 'Same sentence.' 'Ryan'))) 'stale'

    # 5. legacy receipts (written before fingerprints existed)
    $l1 = New-Seg 'W03_L1_01' 'Legacy sentence.'
    Write-Take $l1 'legacy'
    Report 'legacy receipt with matching recorded text and style: reused' (Test-SegmentPass $l1) 'verified legacy take refused'
    $l1changed = New-Seg 'W03_L1_01' 'Legacy sentence, edited.'
    Report 'legacy receipt with different recorded text: not reused' (-not (Test-SegmentPass $l1changed)) 'stale legacy audio would ship'
    $l1style = New-Seg 'W03_L1_01' 'Legacy sentence.' 'Legacy sentence.' 'sarosh' '03_warm'
    Report 'legacy receipt with different recorded style: not reused' (-not (Test-SegmentPass $l1style)) 'stale legacy audio would ship'
    $r1 = New-Seg 'W03_R1_01' 'Regated sentence.'
    Write-Take $r1 'regate'
    Report 'ReGate receipt (text, no style) with matching text: reused' (Test-SegmentPass $r1) 'regate receipts would be discarded'
    Report 'ReGate receipt with changed text: not reused' (-not (Test-SegmentPass (New-Seg 'W03_R1_01' 'Regated sentence, edited.'))) 'stale regate audio would ship'
    $l2 = New-Seg 'W03_L2_01' 'No text recorded.'
    Write-Take $l2 'legacy-notext'
    Report 'legacy receipt with no recorded text: not blindly reused' (-not (Test-SegmentPass $l2)) 'unverifiable take reused'
    $pending = @(Get-PendingOwner -All @($l2) -Round 1)
    Report 'legacy receipt with no recorded text: queued for regeneration' ($pending.Count -eq 1) "pending=$($pending.Count)"
    $l3 = New-Seg 'W03_L3_01' 'Failed legacy.'
    Write-Take $l3 'legacy-fail'
    Report 'receipt with pass=false: not reused' (-not (Test-SegmentPass $l3)) 'failed take reused'

    # 6. damaged or missing receipts
    $c1 = New-Seg 'W04_L1_01' 'Corrupt receipt.'
    Write-Take $c1 'corrupt'
    Report 'unreadable PASS.json: not reused' (-not (Test-SegmentPass $c1)) 'corrupt receipt reused'
    $n1 = New-Seg 'W04_L2_01' 'No receipt at all.'
    Report 'missing PASS.json: not reused' (-not (Test-SegmentPass $n1)) 'reuse without receipt'

    # 7. wiring: production paths must go through the verified check
    $src = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    Report 'no call site still keys reuse on the directory alone' ($src -notmatch 'Test-PassReceipt\s+\$\w+\.dir\s*[)\r\n{]') 'a single-argument Test-PassReceipt call remains'
    Report 'PASS receipt writer stores the fingerprint' ($src -match 'fingerprint\s*=\s*\$s\.fingerprint') 'PASS.json no longer records the fingerprint'
    Report 'segments carry a fingerprint' ($src -match 'fingerprint\s*=\s*\(Get-SegmentFingerprint') 'segment objects lack a fingerprint'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
