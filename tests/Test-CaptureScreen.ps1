#Requires -Version 5.1
<#
Behavior tests for packages/browser-toolkit/scripts/Capture-Screen.ps1.

The helper is the fleet desktop-capture provider. These checks pin the
evidence-root contract, slug validation, FFmpeg argument construction, and
a live one-frame screenshot into scratch -- not into the live evidence
directory and not into the repository.

Run: pwsh -NoProfile -File tests/Test-CaptureScreen.ps1
     powershell.exe -NoProfile -File tests/Test-CaptureScreen.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$helper = Join-Path $repoRoot 'packages\browser-toolkit\scripts\Capture-Screen.ps1'
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

function Invoke-CaptureHelper {
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

Report 'Capture-Screen.ps1 exists' (Test-Path -LiteralPath $helper) "missing $helper"

$helperText = [IO.File]::ReadAllText($helper)
Report 'helper sets ErrorActionPreference Stop at top level' `
    ($helperText -match '(?m)^\$ErrorActionPreference\s*=\s*''Stop''') `
    'a helper that continues after a failed ffmpeg/native call would report success with no file'

$badSlug = Invoke-CaptureHelper -Arguments @('-Action', 'resolve-dir', '-Task', 'Not A Slug', '-PlanOnly')
Report 'invalid task slug is rejected' ($badSlug.ExitCode -ne 0) `
    "uppercase/spaced slug exited $($badSlug.ExitCode): $($badSlug.Output)"

$scratch = Join-Path $env:AGENTHUB_TEST_SCRATCH ('agenthub-capture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $planShot = Invoke-CaptureHelper -Arguments @(
        '-Action', 'screenshot', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch, '-PlanOnly'
    )
    $shot = ConvertFrom-HelperJson -Output $planShot.Output
    Report 'PlanOnly screenshot exits 0 and emits JSON' `
        ($planShot.ExitCode -eq 0 -and $null -ne $shot) `
        "exit $($planShot.ExitCode) json=$(if ($shot) { 'yes' } else { 'no' }) output=$($planShot.Output)"

    if ($null -ne $shot) {
        $cmd = @($shot.command)
        $cmdLine = ($cmd -join ' ')
        Report 'PlanOnly screenshot uses gdigrab desktop and one frame' `
            ($cmdLine -match 'gdigrab' -and $cmdLine -match '-i desktop' -and $cmdLine -match '-frames:v 1') `
            "command: $cmdLine"
        $expectedDir = Join-Path $scratch 'fixture-capture'
        Report 'PlanOnly screenshot directory is under the evidence root override' `
            ([string]$shot.directory -eq $expectedDir) `
            "directory='$($shot.directory)' expected='$expectedDir'"
        Report 'PlanOnly does not create the output file' `
            (-not (Test-Path -LiteralPath ([string]$shot.output))) `
            "PlanOnly wrote $($shot.output)"
    } else {
        Report 'PlanOnly screenshot uses gdigrab desktop and one frame' $false 'no JSON to inspect'
        Report 'PlanOnly screenshot directory is under the evidence root override' $false 'no JSON to inspect'
        Report 'PlanOnly does not create the output file' $false 'no JSON to inspect'
    }

    $planRec = Invoke-CaptureHelper -Arguments @(
        '-Action', 'record', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch, '-Duration', '20', '-PlanOnly'
    )
    $rec = ConvertFrom-HelperJson -Output $planRec.Output
    $recCmd = if ($rec) { @($rec.command) -join ' ' } else { '' }
    Report 'PlanOnly record includes duration and gdigrab' `
        ($planRec.ExitCode -eq 0 -and $recCmd -match 'gdigrab' -and $recCmd -match '-t 20') `
        "exit $($planRec.ExitCode) command: $recCmd"

    $planTitle = Invoke-CaptureHelper -Arguments @(
        '-Action', 'screenshot', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch, '-Title', 'Example Domain', '-PlanOnly'
    )
    $title = ConvertFrom-HelperJson -Output $planTitle.Output
    $titleCmd = if ($title) { @($title.command) -join ' ' } else { '' }
    Report 'PlanOnly window capture uses title= input' `
        ($planTitle.ExitCode -eq 0 -and $titleCmd -match 'title=Example Domain') `
        "exit $($planTitle.ExitCode) command: $titleCmd"

    $tooLong = Invoke-CaptureHelper -Arguments @(
        '-Action', 'record', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch, '-Duration', '121', '-PlanOnly'
    )
    Report 'duration above 120 seconds is rejected' ($tooLong.ExitCode -ne 0) `
        "duration 121 exited $($tooLong.ExitCode): $($tooLong.Output)"

    $resolved = Invoke-CaptureHelper -Arguments @(
        '-Action', 'resolve-dir', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch
    )
    $dirJson = ConvertFrom-HelperJson -Output $resolved.Output
    $created = Join-Path $scratch 'fixture-capture'
    Report 'resolve-dir creates the task evidence directory' `
        ($resolved.ExitCode -eq 0 -and (Test-Path -LiteralPath $created) -and $null -ne $dirJson) `
        "exit $($resolved.ExitCode) pathExists=$(Test-Path -LiteralPath $created) output=$($resolved.Output)"

    $defaultPlan = Invoke-CaptureHelper -Arguments @(
        '-Action', 'screenshot', '-Task', 'fixture-capture', '-PlanOnly'
    )
    $defaultJson = ConvertFrom-HelperJson -Output $defaultPlan.Output
    $localEvidence = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AgentHub\evidence\fixture-capture'
    Report 'default evidence root is LocalAppData\AgentHub\evidence\<task>' `
        ($defaultPlan.ExitCode -eq 0 -and $null -ne $defaultJson -and [string]$defaultJson.directory -eq $localEvidence) `
        "directory='$($defaultJson.directory)' expected='$localEvidence'"
    if ($defaultJson -and (Test-Path -LiteralPath ([string]$defaultJson.output))) {
        Report 'default PlanOnly did not write into the live evidence root' $false `
            "PlanOnly created $($defaultJson.output)"
    } else {
        Report 'default PlanOnly did not write into the live evidence root' $true $null
    }

    $live = Invoke-CaptureHelper -Arguments @(
        '-Action', 'screenshot', '-Task', 'fixture-capture',
        '-EvidenceRoot', $scratch, '-Name', 'live-still'
    )
    $liveJson = ConvertFrom-HelperJson -Output $live.Output
    $livePath = if ($liveJson) { [string]$liveJson.output } else { '' }
    $liveOk = $live.ExitCode -eq 0 -and $livePath -and (Test-Path -LiteralPath $livePath) -and ((Get-Item -LiteralPath $livePath).Length -gt 0)
    Report 'live one-frame screenshot writes a non-empty PNG under the scratch evidence root' `
        $liveOk `
        "exit $($live.ExitCode) path='$livePath' output=$($live.Output)"
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
