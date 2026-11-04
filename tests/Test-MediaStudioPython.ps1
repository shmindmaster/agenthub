#Requires -Version 5.1
<#
Runs the media-studio Python unit tests with `python -m unittest`, one module at
a time so a crash in one cannot hide the others. Run-AllTests.ps1 finds only
PowerShell and Node tests, so without this file packages/media-studio/scripts/
test_*.py never run. Every test_*.py there is picked up, and the four named in
$requiredModules must exist, so the set cannot quietly shrink to nothing.

These suites are synthetic and offline. The child process enforces that rather
than trusting it: credential variables are removed, and LOCALAPPDATA and HOME
point at a throwaway directory so nothing can reach the real content ledger.

A failing test is counted and reported with its cause; a run that produced no
unittest summary, ran zero tests, or timed out counts as a failure.

Run: pwsh -NoProfile -File tests/Test-MediaStudioPython.ps1
     powershell.exe -NoProfile -File tests/Test-MediaStudioPython.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptsDir = Join-Path (Join-Path (Join-Path $repoRoot 'packages') 'media-studio') 'scripts'
$timeoutSeconds = 300
$credentialPattern = '(?i)(api[_-]?key|access[_-]?key|_key$|token|secret|password|credential|connection[_-]?string)'
$requiredModules = @('test_content_host_controls', 'test_content_runtime', 'test_governed_azure_speech', 'test_governed_deepgram')

# A bare python.exe may resolve to the Microsoft Store stub, so resolve a real
# installed interpreter once, as tests/Test-RepoWiseBoundedIndex.ps1 does.
# App aliases resolve to a real interpreter; bundled copies such as LibreOffice's
# do not. CI also runs this file on Linux and macOS, where the name differs.
$pythonNames = if ($IsLinux -or $IsMacOS) { @('python3', 'python') } else { @('python.exe') }
$realPython = Get-Command $pythonNames -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object {
    try { & $_.Source -c 'import sys; print(sys.executable)' 2>$null | Select-Object -Last 1 } catch { }
} | Where-Object { $_ -and $_ -notlike '*\WindowsApps\*' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $realPython) {
    Write-Host "FAIL: no installed (non-Store) interpreter found among: $($pythonNames -join ', ')."
    Write-Host 'RESULT: 0 passed, 1 failed'
    exit 1
}

# Launched through Process, not the call operator: no shell, no window, and the
# test workers Python spawns inherit the hidden console. stderr carries the
# unittest report and is kept apart from stdout, so a test's own print cannot
# pass for the summary.
function Invoke-TestModule([string]$Module, [string]$Sandbox) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $realPython
    $info.Arguments = "-m unittest -v $Module"
    $info.WorkingDirectory = $scriptsDir
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($name in @($info.EnvironmentVariables.Keys)) {
        if ($name -match $credentialPattern) { $info.EnvironmentVariables.Remove($name) }
    }
    $info.EnvironmentVariables['LOCALAPPDATA'] = $Sandbox
    $info.EnvironmentVariables['HOME'] = $Sandbox
    $info.EnvironmentVariables['PYTHONDONTWRITEBYTECODE'] = '1'

    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $finished) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
        }
        $null = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)
        [pscustomobject]@{
            TimedOut = -not $finished
            ExitCode = if ($finished) { $process.ExitCode } else { $null }
            Stdout   = if ($stdout.IsCompleted) { $stdout.Result } else { '' }
            Stderr   = if ($stderr.IsCompleted) { $stderr.Result } else { '' }
        }
    } finally {
        $process.Dispose()
    }
}

function Get-VerdictCount([string]$Verdict, [string]$Label) {
    if ($Verdict -match "\b$Label=(\d+)") { return [int]$Matches[1] }
    return 0
}

# One entry per unittest FAIL:/ERROR: block: the test id and the exception line
# that closes its last traceback.
function Get-FailureCause([string[]]$Lines) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^(FAIL|ERROR): (.+)$') { continue }
        $test = $Matches[2]
        $end = $i + 2
        while ($end -lt $Lines.Count -and $Lines[$end] -notmatch '^(={70}|-{70})$') { $end++ }
        $body = @($Lines[($i + 2)..($end - 1)])
        $start = 0
        for ($j = 0; $j -lt $body.Count; $j++) {
            if ($body[$j] -match '^Traceback \(most recent call last\):') { $start = $j + 1 }
        }
        $cause = $body[$start..($body.Count - 1)] | Where-Object { $_ -match '^\S' } | Select-Object -First 1
        if (-not $cause) { $cause = $body | Where-Object { $_.Trim() } | Select-Object -Last 1 }
        "$test -- $cause"
    }
}

$passed = 0
$failed = 0
$causes = [Collections.Generic.List[string]]::new()
$modules = @(Get-ChildItem -LiteralPath $scriptsDir -File -Filter 'test_*.py' | Sort-Object Name | ForEach-Object BaseName)
foreach ($required in $requiredModules) {
    if ($required -notin $modules) {
        $failed++
        $causes.Add("${required}: test module is missing from $scriptsDir")
    }
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('media-studio-python-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox
try {
    foreach ($module in $modules) {
        Write-Host "--- $module ---"
        $run = Invoke-TestModule $module $sandbox
        if ($run.Stdout.Trim()) { Write-Host $run.Stdout.TrimEnd() }
        if ($run.Stderr.Trim()) { Write-Host $run.Stderr.TrimEnd() }

        $lines = @($run.Stderr -split '\r?\n')
        $ranLine = $lines | Where-Object { $_ -match '^Ran \d+ tests? in ' } | Select-Object -Last 1
        $verdict = $lines | Where-Object { $_ -match '^(OK|FAILED|NO TESTS RAN)\b' } | Select-Object -Last 1
        $ran = if ($ranLine -match '^Ran (\d+) ') { [int]$Matches[1] } else { 0 }

        if ($run.TimedOut) {
            $failed++
            $causes.Add("${module}: did not finish within $timeoutSeconds seconds; the python process was stopped")
        } elseif (-not $ranLine -or -not $verdict) {
            $lastLine = $lines | Where-Object { $_.Trim() } | Select-Object -Last 1
            $failed++
            $causes.Add("${module}: exited $($run.ExitCode) with no unittest summary: $lastLine")
        } elseif ($ran -eq 0) {
            $failed++
            $causes.Add("${module}: ran zero tests (exit $($run.ExitCode))")
        } else {
            $broken = (Get-VerdictCount $verdict 'failures') + (Get-VerdictCount $verdict 'errors') +
                (Get-VerdictCount $verdict 'unexpected successes')
            $skipped = Get-VerdictCount $verdict 'skipped'
            $passed += [Math]::Max(0, $ran - $broken - $skipped)
            $failed += $broken
            foreach ($cause in @(Get-FailureCause $lines)) { $causes.Add("${module}: $cause") }
            if ($broken -eq 0 -and $run.ExitCode -ne 0) {
                $failed++
                $causes.Add("${module}: verdict '$verdict' but python exited $($run.ExitCode)")
            }
            $marker = if ($broken -eq 0 -and $run.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
            Write-Host ("{0}: {1} ran {2}, broken {3}, skipped {4}" -f $marker, $module, $ran, $broken, $skipped)
        }
    }
} finally {
    # This tree contains only what the test processes above wrote into it.
    [IO.Directory]::Delete($sandbox, $true)
}

foreach ($cause in $causes) { Write-Host "FAILED: $cause" }
Write-Host "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
