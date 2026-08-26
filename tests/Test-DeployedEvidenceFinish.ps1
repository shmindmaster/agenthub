#Requires -Version 5.1
<#
Live fleet check: capture and finish skills on this workstation's agent homes
must name the helpers, and the helpers must still run from the skill-documented
package paths.

This is a host-profile check (same class as Test-SharedSkillsDeployment's live
shadow scan). It skips missing skill directories. It fails if a directory that
exists carries a stale compose or desktop-evidence copy, or if no copy of
either skill is found at all.

Run: pwsh -NoProfile -File tests/Test-DeployedEvidenceFinish.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
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

function Expand-HomePath([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $x = if ($Raw.StartsWith('~')) { $env:USERPROFILE + $Raw.Substring(1) } else { $Raw }
    $x = $x -replace '/', '\'
    return [Environment]::ExpandEnvironmentVariables($x)
}

$caps = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$staleCompose = [Collections.Generic.List[string]]::new()
$staleDesktop = [Collections.Generic.List[string]]::new()
$composeHits = 0
$desktopHits = 0
foreach ($a in @($agents.activeAgents)) {
    $dirs = [Collections.Generic.List[string]]::new()
    $own = Expand-HomePath ([string]$a.nativePaths.skillsDir)
    $shared = Expand-HomePath ([string]$a.nativePaths.sharedSkillsDir)
    if ($own) { $dirs.Add($own) }
    if ($shared -and $shared -ne $own) { $dirs.Add($shared) }
    foreach ($d in @($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $compose = Join-Path $d 'media-studio-compose\SKILL.md'
        if (Test-Path -LiteralPath $compose) {
            $composeHits++
            $text = [IO.File]::ReadAllText($compose)
            if ($text -notmatch 'Finish-Media') {
                $staleCompose.Add("$($a.id): $compose")
            }
        }
        $desktop = Join-Path $d 'desktop-evidence\SKILL.md'
        if (Test-Path -LiteralPath $desktop) {
            $desktopHits++
            $text = [IO.File]::ReadAllText($desktop)
            if ($text -notmatch 'Capture-Screen') {
                $staleDesktop.Add("$($a.id): $desktop")
            }
        }
    }
}

Report 'at least one deployed media-studio-compose copy exists on this workstation' ($composeHits -gt 0) `
    'No agent skillsDir contained media-studio-compose; the deploy check would pass over nothing.'
Report 'deployed media-studio-compose copies name Finish-Media' ($staleCompose.Count -eq 0) `
    ($staleCompose -join '; ')
Report 'at least one deployed desktop-evidence copy exists on this workstation' ($desktopHits -gt 0) `
    'No agent skillsDir contained desktop-evidence; Cursor/Qoder would be invisible to this check.'
Report 'deployed desktop-evidence copies name Capture-Screen' ($staleDesktop.Count -eq 0) `
    ($staleDesktop -join '; ')

$cursorDesktop = Join-Path $env:USERPROFILE '.cursor\skills\desktop-evidence\SKILL.md'
Report 'Cursor skillsDir has desktop-evidence (cursor-agent reads this path, not only the plugin junction)' `
    (Test-Path -LiteralPath $cursorDesktop) `
    "missing $cursorDesktop"

$pluginFinish = [Collections.Generic.List[string]]::new()
foreach ($cacheRoot in @(
        (Join-Path $env:USERPROFILE '.claude\plugins\cache\agenthub\media-studio'),
        (Join-Path $env:USERPROFILE '.codex\plugins\cache\agenthub\media-studio')
    )) {
    if (-not (Test-Path -LiteralPath $cacheRoot)) { continue }
    Get-ChildItem -LiteralPath $cacheRoot -Recurse -Filter 'Finish-Media.ps1' -File -ErrorAction SilentlyContinue |
        ForEach-Object { $pluginFinish.Add($_.FullName) }
}
Report 'Claude or Codex plugin cache ships Finish-Media.ps1' ($pluginFinish.Count -gt 0) `
    "checked under ~/.claude and ~/.codex plugins/cache/agenthub/media-studio (any version)"

$finish = Join-Path $repoRoot 'packages\media-studio\scripts\Finish-Media.ps1'
$capture = Join-Path $repoRoot 'packages\browser-toolkit\scripts\Capture-Screen.ps1'
Report 'skill-documented Finish-Media.ps1 exists in the package' (Test-Path -LiteralPath $finish) $finish
Report 'skill-documented Capture-Screen.ps1 exists in the package' (Test-Path -LiteralPath $capture) $capture

$ffmpeg = Get-Command -Name ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ffmpeg -and (Test-Path -LiteralPath $finish)) {
    if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
        $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
    }
    $scratch = Join-Path $env:AGENTHUB_TEST_SCRATCH ('deployed-finish-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $sine = Join-Path $scratch 'tone.wav'
        $out = Join-Path $scratch 'tone-finished.m4a'
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $ffmpeg.Source -hide_banner -loglevel error -f lavfi -i 'sine=frequency=440:duration=2' -ar 48000 -ac 2 -y $sine | Out-Null
        } finally {
            $ErrorActionPreference = $prev
        }
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $hostExe -NoProfile -File $finish -Action finish -Program $sine -Output $out 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prev
        }
        $line = @($output -split "`r?`n" | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
        $json = if ($line.Count -gt 0) { $line[0] | ConvertFrom-Json } else { $null }
        $ok = $code -eq 0 -and $json -and [string]$json.normalizationType -eq 'linear' -and (Test-Path -LiteralPath $out)
        Report 'skill-documented Finish-Media path produces a linear -16 LUFS program' $ok `
            "exit=$code output=$output"
    } finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Report 'skill-documented Finish-Media path produces a linear -16 LUFS program' $false `
        'ffmpeg or Finish-Media.ps1 missing; live agent invocation could not be proven'
}

$bt = @($caps.capabilities | Where-Object { [string]$_.id -eq 'browser-toolkit' })[0]
$cursorMap = @($bt.hostMappings | Where-Object { [string]$_.hostId -eq 'cursor' })[0]
$qoderMap = @($bt.hostMappings | Where-Object { [string]$_.hostId -eq 'qoder' })[0]
Report 'cursor browser-toolkit skills deploy as managed-loose-skills' `
    ($cursorMap -and [string]$cursorMap.deploymentStatus -eq 'managed-loose-skills') `
    "cursor mapping is '$($cursorMap.deploymentStatus)'; cursor-agent would miss desktop-evidence"
Report 'qoder browser-toolkit skills deploy as managed-loose-skills' `
    ($qoderMap -and [string]$qoderMap.deploymentStatus -eq 'managed-loose-skills') `
    "qoder mapping is '$($qoderMap.deploymentStatus)'"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
