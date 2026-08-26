#Requires -Version 5.1
<#
.SYNOPSIS
    Two-pass linear loudness finish and optional music duck for media-studio.

.DESCRIPTION
    Canonical delivery helper for media-studio-compose. Default loudness matches
    the Product Demo Studio gate and Apple Podcasts spoken-word guidance:

        I=-16 LUFS, TP=-1.5 dBTP, LRA=7 LU  (ITU-R BS.1770 / EBU loudnorm)

    Apply is always two-pass with linear=true. One-pass loudnorm is dynamic
    processing (pumping) and is refused. Do not use this helper to denoise,
    enhance, or Studio-Sound owner voice; regenerate a bad TTS segment instead.

    measure  - print input loudness JSON (read-only)
    finish   - optional duck, two-pass linear loudnorm, AAC-LC 48 kHz stereo

.PARAMETER Action
    measure or finish.

.PARAMETER Program
    Already-mixed video or audio program.

.PARAMETER Speech
    Narration stem (WAV). Used with -Music to duck the bed.

.PARAMETER Music
    Music-bed stem (WAV). Ducking uses FFmpeg sidechaincompress.

.PARAMETER Video
    Optional picture to stream-copy when finishing from stems.

.PARAMETER Output
    Destination file. Inferred from input if omitted.

.PARAMETER Integrated
    Target integrated loudness. Default -16.

.PARAMETER TruePeak
    Target true-peak ceiling. Default -1.5.

.PARAMETER LoudnessRange
    Target LRA. Default 7.

.PARAMETER AllowDynamic
    Permit loudnorm to fall back to dynamic mode. Default off; that mode
    compresses TTS takes, which the narration contract forbids.

.PARAMETER PlanOnly
    Print the JSON plan. Pass 1 still runs when an input exists (read-only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('measure', 'finish')]
    [string]$Action,

    [string]$Program,

    [string]$Speech,

    [string]$Music,

    [string]$Video,

    [string]$Output,

    [double]$Integrated = -16,

    [double]$TruePeak = -1.5,

    [double]$LoudnessRange = 7,

    [switch]$AllowDynamic,

    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeFfmpeg {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Get-FfmpegPath {
    $cmd = Get-Command -Name ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    return $null
}

function Get-FfprobePath {
    $cmd = Get-Command -Name ffprobe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    return $null
}

function ConvertFrom-LoudnormOutput {
    param([string[]]$Lines)
    $text = $Lines -join "`n"
    $found = [regex]::Matches($text, '(?s)\{[^{}]*"input_i"\s*:\s*"[^"]+"[^{}]*\}')
    if ($found.Count -eq 0) {
        throw "loudnorm JSON was not found in FFmpeg output.`n$($Lines -join "`n")"
    }
    return ($found[$found.Count - 1].Value | ConvertFrom-Json)
}

function Get-MeasureFilter {
    param([double]$I, [double]$Tp, [double]$Lra)
    return ('loudnorm=I={0}:TP={1}:LRA={2}:print_format=json' -f $I, $Tp, $Lra)
}

function Get-ApplyFilter {
    param(
        [double]$I,
        [double]$Tp,
        [double]$Lra,
        $Measured
    )
    if ($null -eq $Measured) {
        throw 'Apply filter requires pass-1 measurements; refusing one-pass loudnorm.'
    }
    $measuredI = [string]$Measured.input_i
    $measuredTp = [string]$Measured.input_tp
    $measuredThresh = [string]$Measured.input_thresh
    $offset = [string]$Measured.target_offset
    if ([string]::IsNullOrWhiteSpace($measuredI) -or [string]::IsNullOrWhiteSpace($measuredTp) -or
        [string]::IsNullOrWhiteSpace($measuredThresh) -or
        [string]::IsNullOrWhiteSpace($offset)) {
        throw 'Pass-1 loudnorm JSON is missing measured_I/TP/thresh/offset; refusing one-pass apply.'
    }
    # Linear mode cannot expand or compress LRA. Asking for LRA=7 on a
    # near-zero-LRA TTS/sine take forces dynamic pumping. FFmpeg's LRA floor
    # is 1.0; measured_LRA must match that floor or pass 2 stays dynamic.
    $applyLra = [Math]::Max(1.0, [double]$Measured.input_lra)
    $measuredLra = ('{0:F2}' -f $applyLra)
    $filter = 'loudnorm=I={0}:TP={1}:LRA={2}:measured_I={3}:measured_TP={4}:measured_LRA={5}:measured_thresh={6}:offset={7}:linear=true:print_format=json' -f `
        $I, $Tp, $applyLra, $measuredI, $measuredTp, $measuredLra, $measuredThresh, $offset
    if ($filter -notmatch 'linear=true' -or $filter -notmatch 'measured_I=') {
        throw 'Internal error: apply filter omitted linear=true or measured_I.'
    }
    return $filter
}

function Test-HasVideoStream {
    param([string]$Ffprobe, [string]$Path)
    if (-not $Ffprobe -or [string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $run = Invoke-NativeFfmpeg -FilePath $Ffprobe -Arguments @(
        '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_type', '-of', 'csv=p=0',
        $Path
    )
    return ($run.ExitCode -eq 0 -and ($run.Output -join '').Trim().Length -gt 0)
}

function Write-PlanJson {
    param([Parameter(Mandatory)]$Plan)
    Write-Output ($Plan | ConvertTo-Json -Compress -Depth 8)
}

function Get-ScratchWav {
    param([string]$Directory, [string]$Name)
    return Join-Path $Directory ($Name + '-' + [guid]::NewGuid().ToString('N') + '.wav')
}

$ffmpeg = Get-FfmpegPath
if (-not $ffmpeg) { throw 'FFmpeg is required for Finish-Media and was not found on PATH.' }
$ffprobe = Get-FfprobePath

$measureFilter = Get-MeasureFilter -I $Integrated -Tp $TruePeak -Lra $LoudnessRange
$duckFilter = '[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[music];[0:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[speech];[music][speech]sidechaincompress=threshold=0.05:ratio=8:attack=200:release=800:detection=rms[ducked];[speech][ducked]amix=inputs=2:duration=first:dropout_transition=2:normalize=0[mix]'

$useStems = -not [string]::IsNullOrWhiteSpace($Speech) -or -not [string]::IsNullOrWhiteSpace($Music)
if ($useStems) {
    if ([string]::IsNullOrWhiteSpace($Speech) -or [string]::IsNullOrWhiteSpace($Music)) {
        throw 'Duck/finish from stems requires both -Speech and -Music.'
    }
    if (-not (Test-Path -LiteralPath $Speech)) { throw "Speech file not found: $Speech" }
    if (-not (Test-Path -LiteralPath $Music)) { throw "Music file not found: $Music" }
}

$programPath = $Program
if (-not $useStems) {
    if ([string]::IsNullOrWhiteSpace($Program)) { throw '-Program is required unless -Speech and -Music are both set.' }
    if (-not (Test-Path -LiteralPath $Program)) { throw "Program file not found: $Program" }
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $base = if ($useStems) { $Speech } else { $Program }
    $dir = Split-Path -Parent $base
    $stem = [IO.Path]::GetFileNameWithoutExtension($base)
    $hasPicture = (Test-HasVideoStream -Ffprobe $ffprobe -Path $Program) -or
        (-not [string]::IsNullOrWhiteSpace($Video) -and (Test-Path -LiteralPath $Video))
    $ext = if ($hasPicture) { '.mp4' } else { '.m4a' }
    $Output = Join-Path $dir ($stem + '-finished' + $ext)
} else {
    $Output = [IO.Path]::GetFullPath($Output)
}

$pass1Args = $null
$pass1Source = $null
if ($useStems) {
    $pass1Source = '<ducked-mix.wav>'
} else {
    $pass1Source = $programPath
    $pass1Args = @(
        '-hide_banner', '-nostats', '-i', $programPath,
        '-af', $measureFilter, '-f', 'null', '-'
    )
}

$plan = [ordered]@{
    action           = $Action
    targets          = [ordered]@{ I = $Integrated; TP = $TruePeak; LRA = $LoudnessRange }
    duck             = $useStems
    duckFilter       = if ($useStems) { $duckFilter } else { $null }
    measureFilter    = $measureFilter
    applyFilter      = $null
    pass1            = $pass1Args
    linear           = $true
    allowDynamic     = [bool]$AllowDynamic
    output           = $Output
    executed         = $false
    measured         = $null
    encodedLoudness  = $null
    normalizationType = $null
}

if ($Action -eq 'measure') {
    if ($useStems) { throw 'measure requires a mixed -Program; duck then finish instead.' }
    if ($PlanOnly -and -not $pass1Args) {
        Write-PlanJson -Plan $plan
        return
    }
    $run = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $pass1Args
    if ($run.ExitCode -ne 0) {
        throw "FFmpeg measure failed (exit $($run.ExitCode)): $($run.Output -join ' ')"
    }
    $measured = ConvertFrom-LoudnormOutput -Lines $run.Output
    $plan.measured = $measured
    $plan.executed = -not $PlanOnly
    Write-PlanJson -Plan $plan
    return
}

$scratchDir = [IO.Path]::GetTempPath()
$mixWav = $null
$normWav = $null
try {
    $sourceForLoudnorm = $programPath
    if ($useStems) {
        $mixWav = Get-ScratchWav -Directory $scratchDir -Name 'media-studio-mix'
        $duckArgs = @(
            '-hide_banner', '-nostats',
            '-i', $Speech, '-i', $Music,
            '-filter_complex', $duckFilter,
            '-map', '[mix]', '-ar', '48000', '-ac', '2',
            '-y', $mixWav
        )
        $plan.duckCommand = @($ffmpeg) + $duckArgs
        if (-not $PlanOnly) {
            $duckRun = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $duckArgs
            if ($duckRun.ExitCode -ne 0) {
                throw "FFmpeg duck failed (exit $($duckRun.ExitCode)): $($duckRun.Output -join ' ')"
            }
        }
        $sourceForLoudnorm = $mixWav
        $pass1Args = @(
            '-hide_banner', '-nostats', '-i', $sourceForLoudnorm,
            '-af', $measureFilter, '-f', 'null', '-'
        )
        $plan.pass1 = $pass1Args
    }

    $measured = $null
    if ($PlanOnly -and $useStems -and -not (Test-Path -LiteralPath $sourceForLoudnorm)) {
        $plan.applyFilter = 'loudnorm=I={0}:TP={1}:LRA={2}:measured_I=<pass1.input_i>:measured_TP=<pass1.input_tp>:measured_LRA=<pass1.input_lra>:measured_thresh=<pass1.input_thresh>:offset=<pass1.target_offset>:linear=true:print_format=json' -f $Integrated, $TruePeak, $LoudnessRange
        Write-PlanJson -Plan $plan
        return
    }

    $measureRun = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $pass1Args
    if ($measureRun.ExitCode -ne 0) {
        throw "FFmpeg loudnorm pass 1 failed (exit $($measureRun.ExitCode)): $($measureRun.Output -join ' ')"
    }
    $measured = ConvertFrom-LoudnormOutput -Lines $measureRun.Output
    $plan.measured = $measured
    $applyFilter = Get-ApplyFilter -I $Integrated -Tp $TruePeak -Lra $LoudnessRange -Measured $measured
    $plan.applyFilter = $applyFilter

    if ($PlanOnly) {
        Write-PlanJson -Plan $plan
        return
    }

    $normWav = Get-ScratchWav -Directory $scratchDir -Name 'media-studio-norm'
    $pass2Args = @(
        '-hide_banner', '-nostats', '-i', $sourceForLoudnorm,
        '-af', $applyFilter,
        '-ar', '48000', '-ac', '2',
        '-y', $normWav
    )
    $pass2 = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $pass2Args
    if ($pass2.ExitCode -ne 0) {
        throw "FFmpeg loudnorm pass 2 failed (exit $($pass2.ExitCode)): $($pass2.Output -join ' ')"
    }
    $pass2Json = ConvertFrom-LoudnormOutput -Lines $pass2.Output
    $plan.normalizationType = [string]$pass2Json.normalization_type
    if ($plan.normalizationType -and $plan.normalizationType -ne 'linear' -and -not $AllowDynamic) {
        throw "loudnorm pass 2 used normalization_type='$($plan.normalizationType)' rather than linear. Refusing dynamic compression of the program. Pass -AllowDynamic only for a non-TTS live mix that cannot linear-scale."
    }

    $outDir = Split-Path -Parent $Output
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $picture = $null
    if (-not [string]::IsNullOrWhiteSpace($Video) -and (Test-Path -LiteralPath $Video)) {
        $picture = $Video
    } elseif (Test-HasVideoStream -Ffprobe $ffprobe -Path $Program) {
        $picture = $Program
    }

    $encodeArgs = @('-hide_banner', '-nostats')
    if ($picture) {
        $encodeArgs += @('-i', $picture, '-i', $normWav, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy', '-shortest')
    } else {
        $encodeArgs += @('-i', $normWav)
    }
    $encodeArgs += @(
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
        '-movflags', '+faststart',
        '-y', $Output
    )
    $encode = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $encodeArgs
    if ($encode.ExitCode -ne 0) {
        throw "FFmpeg encode failed (exit $($encode.ExitCode)): $($encode.Output -join ' ')"
    }

    $gateArgs = @(
        '-hide_banner', '-nostats', '-i', $Output,
        '-af', $measureFilter, '-f', 'null', '-'
    )
    $gate = Invoke-NativeFfmpeg -FilePath $ffmpeg -Arguments $gateArgs
    if ($gate.ExitCode -ne 0) {
        throw "FFmpeg post-encode loudness measure failed (exit $($gate.ExitCode)): $($gate.Output -join ' ')"
    }
    $encoded = ConvertFrom-LoudnormOutput -Lines $gate.Output
    $plan.encodedLoudness = $encoded
    $integratedOut = [double]$encoded.input_i
    $truePeakOut = [double]$encoded.input_tp
    if ($integratedOut -lt ($Integrated - 1.5) -or $integratedOut -gt ($Integrated + 1.5)) {
        throw "Encoded integrated loudness $integratedOut LUFS is outside $Integrated ± 1.5."
    }
    if ($truePeakOut -gt -1.0) {
        throw "Encoded true peak $truePeakOut dBTP exceeds -1.0 (target TP=$TruePeak)."
    }

    $plan.executed = $true
    $plan.length = (Get-Item -LiteralPath $Output).Length
    Write-PlanJson -Plan $plan
} finally {
    foreach ($temp in @($mixWav, $normWav)) {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
}
