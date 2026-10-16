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
param(
    # Directory holding Generate-OwnerVoice.ps1, ReGate-OwnerVoice.ps1 and OwnerVoice-TakeReuse.ps1.
    # Defaults to the package; pass another checkout's scripts to run these cases against it.
    [string]$ScriptsDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $ScriptsDir) { $ScriptsDir = Join-Path $repoRoot 'packages\media-studio\scripts' }
$scriptPath = Join-Path $ScriptsDir 'Generate-OwnerVoice.ps1'
$helperPath = Join-Path $ScriptsDir 'OwnerVoice-TakeReuse.ps1'
$regatePath = Join-Path $ScriptsDir 'ReGate-OwnerVoice.ps1'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

# --- load the production functions from the scripts' ASTs ---
# The reuse rules live in OwnerVoice-TakeReuse.ps1; the segment/round logic in Generate-OwnerVoice.ps1; the re-gate
# receipt writer in ReGate-OwnerVoice.ps1. A name is taken from the first file that defines it.
$tokens = $null; $parseErrors = $null
$sources = [ordered]@{}
foreach ($f in @($scriptPath, $helperPath, $regatePath)) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $pe = $null
    $sources[$f] = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$pe)
    Report "$([IO.Path]::GetFileName($f)) parses" ($pe.Count -eq 0) "parse errors: $($pe.Count)"
}
$ast = $sources[$scriptPath]
function Get-FunctionText([string]$Name) {
    foreach ($a in $sources.Values) {
        $fn = $a.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
        if ($fn) { return $fn.Extent.Text }
    }
    return $null
}

$wanted = @('Get-Sha256', 'Get-TextSha256', 'Get-SegmentFingerprint', 'Test-PassReceipt', 'Test-SegmentPass', 'Clear-SegmentTake', 'Invoke-GenerationRounds')
$missing = @()
# Dot-sourced at script scope on purpose: a function-local dot-source would vanish on return.
foreach ($name in $wanted) { $t = Get-FunctionText $name; if ($t) { . ([scriptblock]::Create($t)) } else { $missing += $name } }
# Pending-set builder: Get-PendingSegments (owner and role) after the fix; Get-PendingOwner before it.
$pendingName = $null
foreach ($name in @('Get-PendingSegments', 'Get-PendingOwner')) { $t = Get-FunctionText $name; if (-not $pendingName -and $t) { . ([scriptblock]::Create($t)); $pendingName = $name } }
if (-not $pendingName) { $missing += 'Get-PendingSegments' }
# Optional helpers: their absence fails the cases that need them rather than the whole run.
foreach ($name in @('Set-SegmentRedo', 'Write-RegatePass', 'Get-RenderText', 'Get-OwnerStyleContext', 'Invoke-SceneConcat', 'Resolve-SceneSpeaker', 'Write-TakeRenderRecord', 'Get-TakeRenderRecord', 'Test-TakeRejected', 'Write-TakeRejection')) { $t = Get-FunctionText $name; if ($t) { . ([scriptblock]::Create($t)) } }
Report 'script defines every reuse function' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
$schemaAssign = $null
foreach ($a in $sources.Values) {
    $schemaAssign = $a.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:FingerprintSchema' }, $true)
    if ($schemaAssign) { break }
}
Report 'script defines FingerprintSchema' ($null -ne $schemaAssign) 'assignment missing'
if ($missing.Count -gt 0 -or -not $schemaAssign) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($schemaAssign.Extent.Text))
function Get-Pending([object[]]$All, [int]$Round) { return @(& $pendingName -All $All -Round $Round) }

# --- fixtures ---
$work = Join-Path ([IO.Path]::GetTempPath()) ("ownervoice-reuse-" + [guid]::NewGuid().ToString('N'))
$outRoot = Join-Path $work 'sentences'
$selectedRoot = Join-Path $work 'selected'
New-Item -ItemType Directory -Force -Path $outRoot, $selectedRoot | Out-Null

function New-Seg([string]$Id, [string]$Text, [string]$Render = $Text, [string]$Voice = 'sarosh', [string]$Style = '02_explaining',
                 [string]$WavSha = 'wavsha-A', [string]$TxtSha = 'txtsha-A', [bool]$Owner = $true, [string]$Speaker = 'sarosh') {
    $dir = Join-Path $outRoot $Id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [pscustomobject]@{
        id = $Id; sceneId = ($Id -replace '_\d+$', ''); isOwner = $Owner; speaker = $Speaker; roleSpeaker = $(if ($Owner) { $null } else { $Voice })
        text = $Text; renderText = $Render; style = $Style; dir = $dir
        wav = (Join-Path $dir 'take.wav'); seed = 1; redo = $false
        fingerprint = (Get-SegmentFingerprint $Text $Render $Voice $Style $WavSha $TxtSha)
    }
}
# A role segment as Generate-OwnerVoice.ps1 builds it: not an owner segment, no style reference (style ''), role voice.
function New-RoleSeg([string]$Id, [string]$Text, [string]$Voice = 'Ryan', [string]$Speaker = 'joel') {
    New-Seg $Id $Text $Text $Voice '' '' '' $false $Speaker
}
function Write-Take([object]$Seg, [string]$Kind) {
    # Lays down the artefacts a finished segment leaves behind. Kind: current | legacy | legacy-notext | legacy-fail | corrupt
    [IO.File]::WriteAllText($Seg.wav, 'audio')
    [IO.File]::WriteAllText((Join-Path $selectedRoot "$($Seg.id).wav"), 'audio')
    [IO.File]::WriteAllText((Join-Path $Seg.dir 'take.asr.txt'), 'asr')
    [IO.File]::WriteAllText((Join-Path $Seg.dir 'take.identity.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $Seg.dir 'take.integrity.json'), '{"pass":true}')
    $p = Join-Path $Seg.dir 'PASS.json'
    switch ($Kind) {
        # The old writer stamped the owner default style on every segment, role lines included, plus the scene speaker.
        'legacy-stamped' { [ordered]@{ pass = $true; id = $Seg.id; speaker = $Seg.speaker; style = '02_explaining'; text = $Seg.text } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'legacy-other-speaker' { [ordered]@{ pass = $true; id = $Seg.id; speaker = 'vivian'; style = $Seg.style; text = $Seg.text } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'current'       { [ordered]@{ pass = $true; id = $Seg.id; style = $Seg.style; text = $Seg.text; fingerprint = $Seg.fingerprint } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'legacy'        { [ordered]@{ pass = $true; id = $Seg.id; style = $Seg.style; text = $Seg.text } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'regate-render-match' { [ordered]@{ pass = $true; id = $Seg.id; text = $Seg.text; renderText = $Seg.renderText; regate = $true } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
        'regate-render-other' { [ordered]@{ pass = $true; id = $Seg.id; text = $Seg.text; renderText = 'A different reading entirely.'; regate = $true } | ConvertTo-Json | Set-Content $p -Encoding utf8 }
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
    $pending = @(Get-Pending @($s1) 1)
    Report 'same text: segment is not queued for regeneration' ($pending.Count -eq 0) "pending=$($pending.Count)"
    Report 'same text: selected take is left in place' (Test-Path (Join-Path $selectedRoot 'W01_L1_01.wav')) 'selected wav was removed'

    # 3. changed text under the same segment id -> regenerate (the W01_L2 case)
    $old = New-Seg 'W01_L2_01' 'Old words that were approved yesterday.'
    Write-Take $old 'current'
    $new = New-Seg 'W01_L2_01' 'New words after the script line changed.'
    Report 'changed text: old PASS receipt is not reused' (-not (Test-SegmentPass $new)) 'stale audio would ship'
    $pending = @(Get-Pending @($new) 1)
    Report 'changed text: segment is queued for regeneration' ($pending.Count -eq 1 -and $pending[0].id -eq 'W01_L2_01') "pending=$($pending.Count)"
    Report 'changed text: stale PASS.json removed' (-not (Test-Path (Join-Path $new.dir 'PASS.json'))) 'PASS.json survived'
    Report 'changed text: stale take.wav removed' (-not (Test-Path $new.wav)) 'take.wav survived'
    Report 'changed text: stale selected wav removed' (-not (Test-Path (Join-Path $selectedRoot 'W01_L2_01.wav'))) 'selected wav survived, concat would use old audio'
    Report 'changed text: stale take.identity.json removed' (-not (Test-Path (Join-Path $new.dir 'take.identity.json'))) 'identity evidence of the old take survived'
    Report 'changed text: stale take.integrity.json removed' (-not (Test-Path (Join-Path $new.dir 'take.integrity.json'))) 'integrity evidence of the old take survived, it could gate the new take'
    Report 'changed text: stale take.asr.txt removed' (-not (Test-Path (Join-Path $new.dir 'take.asr.txt'))) 'asr transcript of the old take survived'

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
    $pending = @(Get-Pending @($l2) 1)
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


    # 6b. legacy receipts for role segments and speaker checks
    $rl = New-RoleSeg 'W05_L1_01' 'Joel says something.'
    Write-Take $rl 'legacy-stamped'
    Report 'legacy role receipt stamped with the owner default style, same text: reused' (Test-SegmentPass $rl) 'an unchanged legacy Joel take is treated as stale'
    Report 'legacy role receipt with a recorded style but changed text: not reused' (-not (Test-SegmentPass (New-RoleSeg 'W05_L1_01' 'Joel says something else.'))) 'stale role audio would ship'
    $ro = New-Seg 'W05_L2_01' 'Owner line with a recorded speaker.'
    Write-Take $ro 'legacy-stamped'
    Report 'legacy owner receipt with matching speaker and style: reused' (Test-SegmentPass $ro) 'verified legacy owner take refused'
    $rs = New-Seg 'W05_L3_01' 'Owner line recorded under another speaker.'
    Write-Take $rs 'legacy-other-speaker'
    Report 'legacy receipt with a different recorded speaker: not reused' (-not (Test-SegmentPass $rs)) 'a take rendered in another voice would ship'
    $rrs = New-RoleSeg 'W05_L4_01' 'Role line recorded under another speaker.'
    Write-Take $rrs 'legacy-other-speaker'
    Report 'legacy role receipt with a different recorded speaker: not reused' (-not (Test-SegmentPass $rrs)) 'a take rendered in another voice would ship'
    $rf = New-RoleSeg 'W05_L5_01' 'Role line with a current receipt.'
    Write-Take $rf 'current'
    Report 'current role receipt (style empty): reused' (Test-SegmentPass $rf) 'role fingerprint round trip failed'
    Report 'current role receipt with a changed role voice: not reused' (-not (Test-SegmentPass (New-RoleSeg 'W05_L5_01' 'Role line with a current receipt.' 'Vivian'))) 'stale'


    # 6c. historical ReGate receipts {pass,id,sceneId,text,path,sha256,asrWer,identityScores,regate}: no speaker, no renderText, no fingerprint
    $pr1 = New-Seg 'W15_L1_01' 'Pronounced differently now.' 'Pronounced diffrently now.'
    Write-Take $pr1 'regate'
    Report 'historical ReGate receipt after a pronunciation-layer change (render text differs from text): not reused' (-not (Test-SegmentPass $pr1)) 'an old reading would ship under a current-looking receipt'
    $pr2 = New-Seg 'W15_L2_01' 'Pronounced differently now.' 'Pronounced diffrently now.'
    Write-Take $pr2 'regate-render-other'
    Report 'legacy receipt whose recorded renderText differs from the current render text: not reused' (-not (Test-SegmentPass $pr2)) 'a take rendered from other text would ship'
    $pr3 = New-Seg 'W15_L3_01' 'Pronounced differently now.' 'Pronounced diffrently now.'
    Write-Take $pr3 'regate-render-match'
    Report 'legacy receipt whose recorded renderText equals the current render text: reused' (Test-SegmentPass $pr3) 'a verified legacy take was refused'
    $pr4 = New-RoleSeg 'W15_L4_01' 'Scene speaker changed from owner to Joel.'
    Write-Take $pr4 'regate'
    Report 'historical ReGate receipt (no speaker) on a role segment: not reused' (-not (Test-SegmentPass $pr4)) 'an owner-voice take would ship as Joel'
    $pr5 = New-Seg 'W15_L5_01' 'Edited canonical sentence, second version.'
    $pr5old = New-Seg 'W15_L5_01' 'Edited canonical sentence.'
    Write-Take $pr5old 'regate'
    Report 'historical ReGate receipt after a canonical edit: not reused' (-not (Test-SegmentPass $pr5)) 'stale audio would ship'
    $pr6 = New-Seg 'W15_L6_01' 'Nothing to substitute here.'
    Write-Take $pr6 'regate'
    Report 'historical ReGate receipt for an owner line with no pronunciation substitution: reused' (Test-SegmentPass $pr6) 'a verified historical take was refused'

    # 6d. the style probe may omit allowlist and default_style (strict mode must not throw)
    if (Get-Command Get-OwnerStyleContext -ErrorAction SilentlyContinue) {
        $stylesDir = Join-Path $work 'styles'
        New-Item -ItemType Directory -Force -Path $stylesDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $stylesDir '02_explaining.wav'), 'wavbytes')
        [IO.File]::WriteAllText((Join-Path $stylesDir '02_explaining.txt'), 'style transcript')
        foreach ($probeJson in @('{}', '{"allowlist":["02_explaining"]}', '{"default_style":"02_explaining"}')) {
            [IO.File]::WriteAllText((Join-Path $stylesDir '_identity_probe.json'), $probeJson)
            $ctxOk = $false; $ctxErr = ''
            try { $c = Get-OwnerStyleContext $stylesDir '02_explaining'; $ctxOk = ($c.DefaultStyle -ceq '02_explaining') } catch { $ctxErr = $_.Exception.Message }
            Report "style probe $probeJson resolves without throwing" $ctxOk $ctxErr
        }
    } else {
        Report 'Get-OwnerStyleContext is defined' $false 'missing'
    }

    # 6e. scene speaker resolution is shared, so ReGate can skip role segments
    if (Get-Command Resolve-SceneSpeaker -ErrorAction SilentlyContinue) {
        $r = Resolve-SceneSpeaker ([pscustomobject]@{ id = 'S1'; narration = 'x' })
        Report 'scene without a speaker resolves to the owner' ($r.IsOwner -and $r.Speaker -ceq 'sarosh') "isOwner=$($r.IsOwner)"
        $r = Resolve-SceneSpeaker ([pscustomobject]@{ id = 'S1'; speaker = 'joel' })
        Report 'joel resolves to a role segment (Ryan)' ((-not $r.IsOwner) -and $r.RoleSpeaker -ceq 'Ryan') "isOwner=$($r.IsOwner) role=$($r.RoleSpeaker)"
        $r = Resolve-SceneSpeaker ([pscustomobject]@{ id = 'S1'; speaker = 'vivian' })
        Report 'vivian resolves to a role segment (Vivian)' ((-not $r.IsOwner) -and $r.RoleSpeaker -ceq 'Vivian') "role=$($r.RoleSpeaker)"
    } else {
        Report 'Resolve-SceneSpeaker is defined' $false 'ReGate has no way to tell role scenes from owner scenes'
    }

    # 8. generation rounds with stubbed synthesis: owner AND role segments are pending, no GPU / TTS / Local-AI involved
    $receiptDir = Join-Path $work 'receipts'; $batchRoot = Join-Path $work 'batches'
    New-Item -ItemType Directory -Force -Path $receiptDir, $batchRoot | Out-Null
    $integStub = Join-Path $work 'Test-SpeechIntegrity.stub.ps1'
    Set-Content -LiteralPath $integStub -Encoding ascii -Value 'param($Path,$Text,$JsonOut) Set-Content -LiteralPath $JsonOut -Value ''{"pass":true}'' -Encoding ascii'
    $Integrity = $integStub
    $LocalAi = {
        $a = @($args)
        $segId = Split-Path (Split-Path $a[7] -Parent) -Leaf
        $script:roleCalls += ,@{ speaker = $a[3]; text = $a[5]; out = $a[7]; selectedExisted = (Test-Path (Join-Path $selectedRoot "$segId.wav")); passExisted = (Test-Path (Join-Path (Split-Path $a[7] -Parent) 'PASS.json')) }
        if (-not $script:failSynth) { [IO.File]::WriteAllText($a[7], ('r' * 2000)) }
        $global:LASTEXITCODE = 0
    }
    function Invoke-CloneBatch {
        param([string[]]$JsonlLines, [string]$Reference, [string]$RefText, [switch]$Premium, [string]$ReceiptPath)
        foreach ($l in $JsonlLines) {
            $j = $l | ConvertFrom-Json
            $id = Split-Path (Split-Path $j.out -Parent) -Leaf
            $script:ownerCalls += ,@{ id = $id; text = $j.canonical_text; selectedExisted = (Test-Path (Join-Path $selectedRoot "$id.wav")); passExisted = (Test-Path (Join-Path (Split-Path $j.out -Parent) 'PASS.json')) }
            if (-not $script:failSynth) { [IO.File]::WriteAllText($j.out, ('o' * 2000)) }
        }
    }
    $MaxRounds = 3; $ChunkSize = 4; $styleWav = 'style.wav'; $styleTxt = 'style text'; $styleWavSha = 'wavsha-A'; $styleTxtSha = 'txtsha-A'; $SkipAsr = $true; $SkipIdentity = $true; $AsrWerMax = 0.38; $DefaultStyle = '02_explaining'
    function Start-Rounds([object[]]$Segs, [bool]$Fail = $false) {
        $script:segments = @($Segs); $script:roleCalls = @(); $script:ownerCalls = @(); $script:failSynth = $Fail
        try { Invoke-GenerationRounds *>&1 | Out-Null } catch { $script:roundsError = $_.Exception.Message }
    }
    function Start-Redo([object]$Seg) {
        # Listen-finding redo: Set-SegmentRedo after the fix; whole-take clearing before it.
        if (Get-Command Set-SegmentRedo -ErrorAction SilentlyContinue) { Set-SegmentRedo $Seg } else { Clear-SegmentTake $Seg }
    }

    # 8a. changed role line while every owner take is reusable (the early-exit bug)
    $o1 = New-Seg 'W06_L1_01' 'Owner line that is unchanged.'
    Write-Take $o1 'current'
    $oldRole = New-RoleSeg 'W06_L1_02' 'Joel line, old wording.'
    Write-Take $oldRole 'current'
    $newRole = New-RoleSeg 'W06_L1_02' 'Joel line, new wording after the edit.'
    Start-Rounds @($o1, $newRole)
    Report 'changed role line, all owner takes reusable: role line is synthesized' ($script:roleCalls.Count -eq 1 -and $script:roleCalls[0].text -ceq 'Joel line, new wording after the edit.') "roleCalls=$($script:roleCalls.Count)"
    Report 'changed role line, all owner takes reusable: owner take is not regenerated' ($script:ownerCalls.Count -eq 0) "ownerCalls=$($script:ownerCalls.Count)"
    Report 'changed role line: new PASS receipt matches the new text' ((Test-Path (Join-Path $newRole.dir 'PASS.json')) -and (Test-SegmentPass $newRole)) 'role line has no valid PASS after the round'
    Report 'changed role line: owner take is left untouched' (Test-SegmentPass $o1) 'owner PASS was lost'

    # 8b. a scene made only of role lines
    $only = New-RoleSeg 'W07_L1_01' 'Only a role speaks here.' 'Aiden' 'aiden'
    Start-Rounds @($only)
    Report 'role-only scene: synthesized' ($script:roleCalls.Count -eq 1 -and $script:roleCalls[0].speaker -ceq 'Aiden') "roleCalls=$($script:roleCalls.Count)"
    Report 'role-only scene: PASS receipt written and valid' (Test-SegmentPass $only) 'role-only scene never passed'

    # 8c. listen-finding redo of a role id and of an owner id while everything else is reusable
    $oa = New-Seg 'W08_L1_01' 'Owner line passes.'
    Write-Take $oa 'current'
    $rb = New-RoleSeg 'W08_L1_02' 'Role line flagged by the listener.'
    Write-Take $rb 'current'
    Start-Redo $rb
    Start-Rounds @($oa, $rb)
    Report 'redo of a role id: role line is regenerated' ($script:roleCalls.Count -eq 1 -and $script:roleCalls[0].text -ceq 'Role line flagged by the listener.') "roleCalls=$($script:roleCalls.Count)"
    Report 'redo of a role id: previous selected take and receipt stay until the replacement passes' ($script:roleCalls.Count -eq 1 -and $script:roleCalls[0].selectedExisted -and $script:roleCalls[0].passExisted) 'the still-valid take was deleted before regeneration'
    Report 'redo of a role id: replacement passes and is valid' (Test-SegmentPass $rb) 'redo never re-passed'
    $oc = New-Seg 'W09_L1_01' 'Owner line flagged by the listener.'
    Write-Take $oc 'current'
    Start-Redo $oc
    Start-Rounds @($oc)
    Report 'redo of an owner id: owner line is regenerated' ($script:ownerCalls.Count -eq 1 -and $script:ownerCalls[0].id -ceq 'W09_L1_01') "ownerCalls=$($script:ownerCalls.Count)"
    Report 'redo of an owner id: previous selected take and receipt stay until the replacement passes' ($script:ownerCalls.Count -eq 1 -and $script:ownerCalls[0].selectedExisted -and $script:ownerCalls[0].passExisted) 'the still-valid take was deleted before regeneration'
    Report 'redo of an owner id: replacement passes and is valid' (Test-SegmentPass $oc) 'redo never re-passed'

    # 8d. a redo whose regeneration fails keeps the previous take on disk and is still reported as not passed
    $of = New-RoleSeg 'W10_L1_01' 'Role line whose regeneration fails.'
    Write-Take $of 'current'
    Start-Redo $of
    Start-Rounds @($of) $true
    Report 'failed redo: previous selected wav is kept' (Test-Path (Join-Path $selectedRoot 'W10_L1_01.wav')) 'the old take was deleted and nothing replaced it'
    Report 'failed redo: segment is not reported as passed' (-not (Test-SegmentPass $of)) 'a flagged take counted as passed'
    Report 'failed redo: round cap holds' (@($script:roleCalls).Count -le $MaxRounds) "roleCalls=$(@($script:roleCalls).Count) cap=$MaxRounds"


    # 8e. a listen rejection survives the process: the next run must not reuse or concatenate the rejected take
    $ffmpegCalls = 0
    function ffprobe { '24000' }
    function ffmpeg { $script:ffmpegCalls++ }
    $Job = $work
    $j1 = New-Seg 'W12_L1_01' 'Rejected by the listener.'
    Write-Take $j1 'current'
    Start-Redo $j1
    $j1b = New-Seg 'W12_L1_01' 'Rejected by the listener.'   # a new process rebuilds every segment from scratch
    Report 'listen rejection survives a new process: rejected take is not passed' (-not (Test-SegmentPass $j1b)) 'the next run would reuse the rejected take'
    Start-Rounds @($j1b) $true
    $j1c = New-Seg 'W12_L1_01' 'Rejected by the listener.'
    Report 'replacement failed: next process still sees the rejection' (-not (Test-SegmentPass $j1c)) 'a failed replacement re-validated the rejected take'
    Report 'replacement failed: previous selected wav is kept' (Test-Path (Join-Path $selectedRoot 'W12_L1_01.wav')) 'old audio deleted with nothing to replace it'
    $script:segments = @($j1c); $ids = @('W12_L1')
    $concatThrew = $false; $ffmpegCalls = 0
    try { Invoke-SceneConcat @() *>&1 | Out-Null } catch { $concatThrew = $true }
    Report 'scene concat refuses a segment that is not passed' ($concatThrew -and $ffmpegCalls -eq 0) "threw=$concatThrew ffmpegCalls=$ffmpegCalls"
    Start-Rounds @($j1c)
    $j1d = New-Seg 'W12_L1_01' 'Rejected by the listener.'
    Report 'replacement passed: segment is passed in the next process' (Test-SegmentPass $j1d) 'replacement never passed'
    Report 'replacement passed: rejection marker is cleared' (-not (Test-Path (Join-Path $j1d.dir 'REJECTED.json'))) 'REJECTED.json survived a passing replacement'
    $script:segments = @($j1d)
    $concatThrew = $false
    try { Invoke-SceneConcat @() *>&1 | Out-Null } catch { $concatThrew = $true }
    Report 'scene concat accepts passed segments' (-not $concatThrew -and $ffmpegCalls -gt 0) "threw=$concatThrew"

    # 8f. Generate records the render text it synthesized from, beside the take
    $sc1 = New-Seg 'W16_L1_01' 'Sidecar owner sentence.' 'Sidecar owner sentance.'
    Start-Rounds @($sc1)
    $sidecar = Join-Path $sc1.dir 'take.render.json'
    Report 'generation records the synthesized render text beside the take' ((Test-Path $sidecar) -and ((Get-Content -LiteralPath $sidecar -Raw -Encoding UTF8 | ConvertFrom-Json).renderText -ceq 'Sidecar owner sentance.')) 'no take.render.json after synthesis'

    # 9. ReGate-OwnerVoice.ps1 receipts
    if ((Get-Command Write-RegatePass -ErrorAction SilentlyContinue) -and (Get-Command Write-TakeRenderRecord -ErrorAction SilentlyContinue)) {
        $LocalAi = Join-Path $work 'no-such-local-ai\ai.ps1'
        $ctx = [pscustomobject]@{ DefaultStyle = '02_explaining'; WavSha = 'wavsha-A'; TextSha = 'txtsha-A' }
        $idRec = [pscustomobject]@{ scores = 1 }
        # 9a. the render text recorded when the take was synthesized is what gets fingerprinted
        $rg = New-Seg 'W11_L1_01' 'Re-gated owner sentence.'
        [IO.File]::WriteAllText($rg.wav, 'audio')
        Write-TakeRenderRecord $rg.dir 'Re-gated owner sentence.' 'Re-gated owner sentance.' 'sarosh' '02_explaining' 'wavsha-A' 'txtsha-A'
        Write-RegatePass $rg $selectedRoot 0.1 $idRec
        $rec = Get-Content -LiteralPath (Join-Path $rg.dir 'PASS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Report 'ReGate receipt records a fingerprint when the synthesized render text is known' ([bool]$rec.fingerprint -and $rec.fingerprintSchema -ceq $script:FingerprintSchema) 'no fingerprint in the re-gate receipt'
        Report 'ReGate receipt records speaker, style and the recorded render text' ($rec.speaker -ceq 'sarosh' -and $rec.style -ceq '02_explaining' -and $rec.renderText -ceq 'Re-gated owner sentance.') 'speaker/style/renderText wrong'
        Report 'ReGate receipt is reused when the current render text equals the recorded one' (Test-SegmentPass (New-Seg 'W11_L1_01' 'Re-gated owner sentence.' 'Re-gated owner sentance.')) 'regated take rejected'
        Report 'ReGate receipt is rejected when the current render text differs from the one synthesized' (-not (Test-SegmentPass (New-Seg 'W11_L1_01' 'Re-gated owner sentence.' 'Re-gated owner sentence.'))) 'today''s render text was stamped onto an older wav'
        Report 'ReGate receipt is rejected after the style reference audio changes' (-not (Test-SegmentPass (New-Seg 'W11_L1_01' 'Re-gated owner sentence.' 'Re-gated owner sentance.' 'sarosh' '02_explaining' 'wavsha-B'))) 'regated take survived a style wav change'
        # 9b. unknown render text: no fingerprint, said so in the receipt, legacy rule applies
        $rg2 = New-Seg 'W11_L2_01' 'Unknown reading sentence.'
        [IO.File]::WriteAllText($rg2.wav, 'audio')
        Write-RegatePass $rg2 $selectedRoot 0.1 $idRec
        $rec2 = Get-Content -LiteralPath (Join-Path $rg2.dir 'PASS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasFp = ($rec2.PSObject.Properties.Name -contains 'fingerprint') -and [bool]$rec2.fingerprint
        Report 'ReGate receipt without a recorded render text carries no fingerprint' (-not $hasFp) 'a fingerprint was invented for an unknown reading'
        Report 'ReGate receipt without a recorded render text says so' (($rec2.PSObject.Properties.Name -contains 'fingerprintNote') -and [bool]$rec2.fingerprintNote) 'no explanation in the receipt'
        Report 'unfingerprinted ReGate receipt is reused only while no pronunciation substitution applies' ((Test-SegmentPass (New-Seg 'W11_L2_01' 'Unknown reading sentence.')) -and -not (Test-SegmentPass (New-Seg 'W11_L2_01' 'Unknown reading sentence.' 'Unknown reeding sentence.'))) 'legacy render rule not applied to ReGate output'
        # 9c. a sidecar written for different text is not evidence for this text
        $rg3 = New-Seg 'W11_L3_01' 'Current text of the line.'
        [IO.File]::WriteAllText($rg3.wav, 'audio')
        Write-TakeRenderRecord $rg3.dir 'Older text of the line.' 'Older text of the line.' 'sarosh' '02_explaining' 'wavsha-A' 'txtsha-A'
        Write-RegatePass $rg3 $selectedRoot 0.1 $idRec
        $rec3 = Get-Content -LiteralPath (Join-Path $rg3.dir 'PASS.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Report 'ReGate ignores a render record written for different text' (-not (($rec3.PSObject.Properties.Name -contains 'fingerprint') -and [bool]$rec3.fingerprint)) 'fingerprinted a take from a sidecar of another sentence'
    } else {
        Report 'ReGate-OwnerVoice.ps1 defines Write-RegatePass and the render record helpers' $false 'ReGate stamps the current render text onto an older wav'
    }

    # 7. wiring: production paths must go through the verified check
    $src = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
    Report 'no call site still keys reuse on the directory alone' ($src -notmatch 'Test-PassReceipt\s+\$\w+\.dir\s*[)\r\n{]') 'a single-argument Test-PassReceipt call remains'
    Report 'PASS receipt writer stores the fingerprint' ($src -match 'fingerprint\s*=\s*\$s\.fingerprint') 'PASS.json no longer records the fingerprint'
    Report 'segments carry a fingerprint' ($src -match 'fingerprint\s*=\s*\(Get-SegmentFingerprint') 'segment objects lack a fingerprint'
    Report 'Generate-OwnerVoice.ps1 shares the reuse helper' ($src -match 'OwnerVoice-TakeReuse\.ps1') 'Generate does not load the shared reuse rules'
    $rgSrc = Get-Content -LiteralPath $regatePath -Raw -Encoding UTF8
    Report 'ReGate-OwnerVoice.ps1 skips non-owner scenes' ($rgSrc -match 'Resolve-SceneSpeaker') 'ReGate would stamp role lines as the owner'
    Report 'ReGate-OwnerVoice.ps1 shares the reuse helper' ($rgSrc -match 'OwnerVoice-TakeReuse\.ps1' -and $rgSrc -match 'Get-SegmentFingerprint') 'ReGate does not use the shared fingerprint rules'
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
