#Requires -Version 5.1
<#
Behavior tests for packages/media-studio/scripts/Finish-Media.ps1.

Pins the 2026 delivery contract: two-pass linear loudnorm (I=-16, TP=-1.5,
LRA=7), never one-pass dynamic loudnorm, AAC 48 kHz, and a live sine fixture
that must land inside the existing Product Demo Studio loudness gate.

Run: pwsh -NoProfile -File tests/Test-FinishMedia.ps1
     powershell.exe -NoProfile -File tests/Test-FinishMedia.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$helper = Join-Path $repoRoot 'packages\media-studio\scripts\Finish-Media.ps1'
$hostExe = (Get-Process -Id $PID).Path

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

function Invoke-FinishHelper {
    param([string[]]$Arguments)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe -NoProfile -File $helper @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function ConvertFrom-HelperJson {
    param([string]$Output)
    $line = @(
        $Output -split "`r?`n" |
            Where-Object { $_ -match '^\s*\{' } |
            Select-Object -Last 1
    )
    if ($line.Count -eq 0) { return $null }
    return ($line[0] | ConvertFrom-Json)
}

function Test-ApplyIsTwoPassLinear {
    param([string]$Filter)
    if ([string]::IsNullOrWhiteSpace($Filter)) { return $false }
    $onePass = 'loudnorm=I=-16:TP=-1.5:LRA=7'
    $isOnePassOnly = ($Filter -eq $onePass) -or ($Filter -eq ($onePass + ':print_format=json'))
    return (
        -not $isOnePassOnly -and
        $Filter -match 'linear=true' -and
        $Filter -match 'measured_I=' -and
        $Filter -match 'measured_TP=' -and
        $Filter -match 'measured_LRA=' -and
        $Filter -match 'measured_thresh='
    )
}

Report 'Finish-Media.ps1 exists' (Test-Path -LiteralPath $helper) "missing $helper"

$helperText = [IO.File]::ReadAllText($helper)
Report 'helper sets ErrorActionPreference Stop at top level' `
    ($helperText -match '(?m)^\$ErrorActionPreference\s*=\s*''Stop''') `
    'a helper that continues after a failed ffmpeg call would report success with no master'
Report 'helper refuses one-pass apply in Get-ApplyFilter' `
    ($helperText -match 'refusing one-pass' -and $helperText -match 'linear=true') `
    'the apply-filter builder must refuse a graph that only sets I/TP/LRA'

$ffmpeg = Get-Command -Name ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
Report 'ffmpeg is on PATH for live finish tests' ([bool]$ffmpeg) 'Finish-Media cannot be proven without ffmpeg'

$scratch = Join-Path $env:AGENTHUB_TEST_SCRATCH ('agenthub-finish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $sine = Join-Path $scratch 'tone.wav'
    $out = Join-Path $scratch 'tone-finished.m4a'
    if ($ffmpeg) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $ffmpeg.Source -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=3' -ar 48000 -ac 2 -y $sine | Out-Null
        } finally {
            $ErrorActionPreference = $prev
        }
    }

    $missing = Invoke-FinishHelper -Arguments @('-Action', 'finish', '-PlanOnly')
    Report 'finish without Program or stems is rejected' ($missing.ExitCode -ne 0) `
        "exit $($missing.ExitCode): $($missing.Output)"

    if (Test-Path -LiteralPath $sine) {
        $plan = Invoke-FinishHelper -Arguments @(
            '-Action', 'finish', '-Program', $sine, '-Output', $out, '-PlanOnly'
        )
        $json = ConvertFrom-HelperJson -Output $plan.Output
        Report 'PlanOnly finish exits 0 and emits JSON' `
            ($plan.ExitCode -eq 0 -and $null -ne $json) `
            "exit $($plan.ExitCode) output=$($plan.Output)"

        if ($null -ne $json) {
            Report 'PlanOnly apply filter is two-pass linear, not one-pass loudnorm' `
                (Test-ApplyIsTwoPassLinear -Filter ([string]$json.applyFilter)) `
                "applyFilter='$($json.applyFilter)'"
            Report 'PlanOnly measure filter is the analysis pass' `
                ([string]$json.measureFilter -match 'print_format=json' -and [string]$json.measureFilter -notmatch 'linear=true') `
                "measureFilter='$($json.measureFilter)'"
            Report 'PlanOnly default targets are I=-16 TP=-1.5 LRA=7' `
                ([double]$json.targets.I -eq -16 -and [double]$json.targets.TP -eq -1.5 -and [double]$json.targets.LRA -eq 7) `
                "targets=$($json.targets | ConvertTo-Json -Compress)"
            Report 'PlanOnly does not write the finished file' `
                (-not (Test-Path -LiteralPath $out)) `
                "PlanOnly wrote $out"
        } else {
            Report 'PlanOnly apply filter is two-pass linear, not one-pass loudnorm' $false 'no JSON'
            Report 'PlanOnly measure filter is the analysis pass' $false 'no JSON'
            Report 'PlanOnly default targets are I=-16 TP=-1.5 LRA=7' $false 'no JSON'
            Report 'PlanOnly does not write the finished file' $false 'no JSON'
        }

        $speech = Join-Path $scratch 'speech.wav'
        $music = Join-Path $scratch 'music.wav'
        Copy-Item -LiteralPath $sine -Destination $speech -Force
        Copy-Item -LiteralPath $sine -Destination $music -Force
        $duckPlan = Invoke-FinishHelper -Arguments @(
            '-Action', 'finish', '-Speech', $speech, '-Music', $music,
            '-Output', (Join-Path $scratch 'ducked.m4a'), '-PlanOnly'
        )
        $duckJson = ConvertFrom-HelperJson -Output $duckPlan.Output
        $duckFilter = if ($duckJson) { [string]$duckJson.duckFilter } else { '' }
        Report 'PlanOnly stem finish includes sidechain ducking' `
            ($duckPlan.ExitCode -eq 0 -and $duckFilter -match 'sidechaincompress') `
            "exit $($duckPlan.ExitCode) duckFilter=$duckFilter"

        $live = Invoke-FinishHelper -Arguments @(
            '-Action', 'finish', '-Program', $sine, '-Output', $out
        )
        $liveJson = ConvertFrom-HelperJson -Output $live.Output
        $liveOk = $live.ExitCode -eq 0 -and (Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0)
        Report 'live finish writes a non-empty AAC program' `
            $liveOk `
            "exit $($live.ExitCode) output=$($live.Output)"

        if ($liveOk -and $liveJson) {
            Report 'live finish used linear loudnorm' `
                ([string]$liveJson.normalizationType -eq 'linear' -or [string]$liveJson.normalizationType -eq '') `
                "normalizationType='$($liveJson.normalizationType)'"
            $encI = [double]$liveJson.encodedLoudness.input_i
            $encTp = [double]$liveJson.encodedLoudness.input_tp
            Report 'live encoded loudness is -16 LUFS plus or minus 1.5' `
                ($encI -ge -17.5 -and $encI -le -14.5) `
                "encoded I=$encI"
            Report 'live encoded true peak is at or below -1.0 dBTP' `
                ($encTp -le -1.0) `
                "encoded TP=$encTp"
            Report 'live apply filter stayed two-pass linear' `
                (Test-ApplyIsTwoPassLinear -Filter ([string]$liveJson.applyFilter)) `
                "applyFilter='$($liveJson.applyFilter)'"
        } else {
            Report 'live finish used linear loudnorm' $false 'live finish did not produce JSON'
            Report 'live encoded loudness is -16 LUFS plus or minus 1.5' $false 'live finish did not produce JSON'
            Report 'live encoded true peak is at or below -1.0 dBTP' $false 'live finish did not produce JSON'
            Report 'live apply filter stayed two-pass linear' $false 'live finish did not produce JSON'
        }
    } else {
        Report 'PlanOnly finish exits 0 and emits JSON' $false 'sine fixture was not created'
        Report 'PlanOnly apply filter is two-pass linear, not one-pass loudnorm' $false 'no fixture'
        Report 'PlanOnly measure filter is the analysis pass' $false 'no fixture'
        Report 'PlanOnly default targets are I=-16 TP=-1.5 LRA=7' $false 'no fixture'
        Report 'PlanOnly does not write the finished file' $false 'no fixture'
        Report 'PlanOnly stem finish includes sidechain ducking' $false 'no fixture'
        Report 'live finish writes a non-empty AAC program' $false 'no fixture'
        Report 'live finish used linear loudnorm' $false 'no fixture'
        Report 'live encoded loudness is -16 LUFS plus or minus 1.5' $false 'no fixture'
        Report 'live encoded true peak is at or below -1.0 dBTP' $false 'no fixture'
        Report 'live apply filter stayed two-pass linear' $false 'no fixture'
    }
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
