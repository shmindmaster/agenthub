#Requires -Version 5.1
<#
Behavior tests for scripts/AgentHubDemoProfile.ps1 (the throwaway profile the
AgentHub film records audit -> apply -> audit in) and scripts/lib/DisplayPath.ps1
(the '~' cropping that makes that output publishable).

Every profile lives under AGENTHUB_TEST_SCRATCH. The test also proves the real
fleet is untouched: the invoking user's ~/.claude/CLAUDE.md and the live
instruction staging directory keep their timestamps across the whole run.

Run: pwsh -NoProfile -File tests/Test-AgentHubDemoProfile.ps1
     powershell.exe -NoProfile -File tests/Test-AgentHubDemoProfile.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$demoScript = Join-Path $repoRoot 'scripts\AgentHubDemoProfile.ps1'
. (Join-Path $repoRoot 'scripts\lib\DisplayPath.ps1')
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

function Invoke-Demo([string[]]$DemoArgs) {
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe -NoProfile -File $demoScript @DemoArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-StateLine([string]$Output, [string]$HostId) {
    $m = [regex]::Match($Output, "(?m)^$([regex]::Escape($HostId))\s+(\S+)\s+(\S+)")
    if (-not $m.Success) { return $null }
    return "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
}

# --- 1. Cropping replaces only a whole home segment, in both slash styles. ---
$homeSample = 'C:\Users\Alex'
$cropOk = (Format-AgentHubDisplayText -Text 'C:\Users\Alex\.claude\CLAUDE.md' -HomePath $homeSample) -ceq '~\.claude\CLAUDE.md' -and
    (Format-AgentHubDisplayText -Text 'c:/users/alex/.codex/AGENTS.md' -HomePath $homeSample) -ceq '~/.codex/AGENTS.md' -and
    (Format-AgentHubDisplayText -Text 'C:\Users\Alexis\x' -HomePath $homeSample) -ceq 'C:\Users\Alexis\x' -and
    (Format-AgentHubDisplayText -Text "root=C:\Users\Alex`nnext C:\Users\Alex" -HomePath $homeSample) -ceq "root=~`nnext ~"
Report 'display cropping replaces the home directory with ~ and only at a path boundary' $cropOk `
    'Format-AgentHubDisplayText cropped the wrong span or missed a spelling'

$realClaude = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'
$realClaudeStamp = if (Test-Path -LiteralPath $realClaude) { (Get-Item -LiteralPath $realClaude).LastWriteTimeUtc } else { $null }
$liveStaging = Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\instructions\claude'
$liveStagingStamp = if (Test-Path -LiteralPath $liveStaging) { (Get-ChildItem -LiteralPath $liveStaging -File | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum } else { $null }

$root = Join-Path $env:AGENTHUB_TEST_SCRATCH ('agenthub-demo-profile-' + [guid]::NewGuid().ToString('N'))
try {
    # --- 2. The full on-camera sequence. ---
    $new = Invoke-Demo @('-Action', 'New', '-Root', $root)
    Report 'New creates a marked profile with a registry snapshot and the public policy' (
        $new.ExitCode -eq 0 -and
        (Test-Path -LiteralPath (Join-Path $root '.agenthub-demo-profile.json')) -and
        (Test-Path -LiteralPath (Join-Path $root 'repo\registry\agents.json')) -and
        (Test-Path -LiteralPath (Join-Path $root 'repo\policy-core.md')) -and
        -not (Test-Path -LiteralPath (Join-Path $root 'repo\global-agent-policy.md'))
    ) "exit=$($new.ExitCode) output=$($new.Output)"

    $a1 = Invoke-Demo @('-Action', 'Audit', '-Root', $root)
    $p1 = Invoke-Demo @('-Action', 'Apply', '-Root', $root)
    $a2 = Invoke-Demo @('-Action', 'Audit', '-Root', $root)
    $e1 = Invoke-Demo @('-Action', 'EditPolicy', '-Root', $root)
    $e2 = Invoke-Demo @('-Action', 'EditPolicy', '-Root', $root)
    $a3 = Invoke-Demo @('-Action', 'Audit', '-Root', $root)
    $p2 = Invoke-Demo @('-Action', 'Apply', '-Root', $root)
    $a4 = Invoke-Demo @('-Action', 'Audit', '-Root', $root)
    $states = @(
        (Get-StateLine $a1.Output 'claude'), (Get-StateLine $p1.Output 'claude'),
        (Get-StateLine $a2.Output 'claude'), (Get-StateLine $a3.Output 'claude'),
        (Get-StateLine $p2.Output 'claude'), (Get-StateLine $a4.Output 'claude')
    ) -join ' -> '
    $expectedStates = 'missing/none -> missing/updated -> current/none -> drift/none -> drift/updated -> current/none'
    Report 'audit -> apply -> audit -> one-line edit -> audit -> apply -> audit walks missing, current, drift, current' (
        $states -eq $expectedStates -and
        @($a1, $p1, $a2, $a3, $p2, $a4 | Where-Object { $_.ExitCode -ne 0 }).Count -eq 0
    ) "claude states were [$states], expected [$expectedStates]"

    $profilePolicy = [IO.File]::ReadAllText((Join-Path $root 'repo\policy-core.md'))
    $checkoutPolicy = [IO.File]::ReadAllText((Join-Path $repoRoot 'policy-core.md'))
    $editLines = @($profilePolicy -split "`n" | Where-Object { $_ -like '- Demo profile rule:*' })
    Report 'EditPolicy adds exactly one line, only in the profile, and is idempotent' (
        $e1.ExitCode -eq 0 -and $e2.ExitCode -eq 0 -and $editLines.Count -eq 1 -and
        $checkoutPolicy -notmatch 'Demo profile rule:' -and
        $e2.Output -match 'already present'
    ) "lines=$($editLines.Count) e1=$($e1.Output) e2=$($e2.Output)"

    $deployed = Join-Path $root 'home\.claude\CLAUDE.md'
    Report 'the edited line reaches the profile host file and nothing private does' (
        (Test-Path -LiteralPath $deployed) -and
        ([IO.File]::ReadAllText($deployed) -match 'Demo profile rule:') -and
        ([IO.File]::ReadAllText($deployed) -notmatch 'sarosh-communication')
    ) 'profile CLAUDE.md lacks the edit or carries private-overlay policy'

    $allOutput = ($new, $a1, $p1, $a2, $e1, $a3, $p2, $a4 | ForEach-Object { $_.Output }) -join "`n"
    Report 'every printed line is cropped: the invoking home never appears' (
        $allOutput.IndexOf($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase) -lt 0 -and
        ($root.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase) -eq ($allOutput -match '~[\\/]'))
    ) 'output still contains the real home directory'

    $realStampAfter = if (Test-Path -LiteralPath $realClaude) { (Get-Item -LiteralPath $realClaude).LastWriteTimeUtc } else { $null }
    $liveStagingAfter = if (Test-Path -LiteralPath $liveStaging) { (Get-ChildItem -LiteralPath $liveStaging -File | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum } else { $null }
    Report 'the real fleet is untouched: real CLAUDE.md and live staging keep their timestamps' (
        $realStampAfter -eq $realClaudeStamp -and $liveStagingAfter -eq $liveStagingStamp
    ) "real CLAUDE.md $realClaudeStamp -> $realStampAfter; live staging $liveStagingStamp -> $liveStagingAfter"

    # --- 3. Refusals. ---
    $realRoot = Invoke-Demo @('-Action', 'New', '-Root', $env:USERPROFILE)
    $fleetRoot = Invoke-Demo @('-Action', 'New', '-Root', (Join-Path $env:USERPROFILE '.claude\agenthub-demo'))
    $repoInside = Invoke-Demo @('-Action', 'New', '-Root', (Join-Path $repoRoot 'demo-profile'))
    Report 'New refuses the real profile, a real host config root, and the checkout' (
        $realRoot.ExitCode -ne 0 -and $realRoot.Output -match 'real user profile' -and
        $fleetRoot.ExitCode -ne 0 -and $fleetRoot.Output -match 'real host configuration root' -and
        -not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude\agenthub-demo')) -and
        $repoInside.ExitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $repoRoot 'demo-profile'))
    ) "real=$($realRoot.ExitCode) fleet=$($fleetRoot.ExitCode) repo=$($repoInside.ExitCode)"

    $unmarked = Join-Path $env:AGENTHUB_TEST_SCRATCH ('agenthub-demo-unmarked-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $unmarked -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $unmarked 'keep.txt') -Value 'not a demo profile' -Encoding ASCII
    try {
        $rmUnmarked = Invoke-Demo @('-Action', 'Remove', '-Root', $unmarked)
        $newUnmarked = Invoke-Demo @('-Action', 'New', '-Root', $unmarked)
        $syncUnmarked = Invoke-Demo @('-Action', 'Apply', '-Root', $unmarked)
        Report 'Remove, New, and Apply refuse a directory this script did not create' (
            $rmUnmarked.ExitCode -ne 0 -and $newUnmarked.ExitCode -ne 0 -and $syncUnmarked.ExitCode -ne 0 -and
            (Test-Path -LiteralPath (Join-Path $unmarked 'keep.txt'))
        ) "remove=$($rmUnmarked.ExitCode) new=$($newUnmarked.ExitCode) apply=$($syncUnmarked.ExitCode)"
    } finally {
        Remove-Item -LiteralPath $unmarked -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- 4. One command resets, one command destroys. ---
    $reset = Invoke-Demo @('-Action', 'New', '-Root', $root)
    $afterReset = Invoke-Demo @('-Action', 'Audit', '-Root', $root)
    Report 'New on an existing profile resets it to the deterministic starting state' (
        $reset.ExitCode -eq 0 -and (Get-StateLine $afterReset.Output 'claude') -eq 'missing/none' -and
        [IO.File]::ReadAllText((Join-Path $root 'repo\policy-core.md')) -notmatch 'Demo profile rule:'
    ) "after reset: $(Get-StateLine $afterReset.Output 'claude')"

    $remove = Invoke-Demo @('-Action', 'Remove', '-Root', $root)
    Report 'Remove deletes exactly the marked profile' (
        $remove.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $root)
    ) "exit=$($remove.ExitCode) output=$($remove.Output)"
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'SCOPE: display cropping, demo profile lifecycle, audit/apply/audit around a one-line edit, refusals, real-fleet isolation'
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
