#Requires -Version 5.1
<#
Runs Python unittest modules for a suite test and reports in the RESULT format
Run-AllTests.ps1 parses. Dot-source from a test, then exit with what it returns:

    . (Join-Path $PSScriptRoot 'lib\PythonUnitTests.ps1')
    exit (Invoke-PythonUnitTests -Directory $dir -Required 'test_x')

Modules run one at a time so a crash in one cannot hide the others. -Required
modules must exist; -Discover also runs every other test_*.py in -Directory, so
a new file there is picked up without an edit.

The suites are synthetic and offline. The child process enforces that rather
than trusting it: credential variables are removed, and LOCALAPPDATA and HOME
point at a throwaway directory so nothing can reach real runtime state.

A failing test is counted and reported with its cause; a run that produced no
unittest summary, ran zero tests, or timed out counts as a failure.
#>

# A bare python.exe may resolve to the Microsoft Store stub, so resolve a real
# installed interpreter, as tests/Test-RepoWiseBoundedIndex.ps1 does. App aliases
# resolve to a real interpreter; bundled copies such as LibreOffice's do not. CI
# also runs these tests on Linux and macOS, where the name differs.
function Resolve-RealPython {
    $names = if ($IsLinux -or $IsMacOS) { @('python3', 'python') } else { @('python.exe') }
    Get-Command $names -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object {
        try { & $_.Source -c 'import sys; print(sys.executable)' 2>$null | Select-Object -Last 1 } catch { }
    } | Where-Object { $_ -and $_ -notlike '*\WindowsApps\*' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

# Launched through Process, not the call operator: no shell, no window, and the
# test workers Python spawns inherit the hidden console. stderr carries the
# unittest report and is kept apart from stdout, so a test's own print cannot
# pass for the summary.
function Invoke-PythonTestModule {
    param([string]$Python, [string]$Directory, [string]$Module, [string]$Sandbox, [int]$TimeoutSeconds)
    $credentialPattern = '(?i)(api[_-]?key|access[_-]?key|_key$|token|secret|password|credential|connection[_-]?string)'
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Python
    $info.Arguments = "-m unittest -v $Module"
    $info.WorkingDirectory = $Directory
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
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
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

function Get-UnittestCount([string]$Verdict, [string]$Label) {
    if ($Verdict -match "\b$Label=(\d+)") { return [int]$Matches[1] }
    return 0
}

# One entry per unittest FAIL:/ERROR: block: the test id and the exception line
# that closes its last traceback.
function Get-UnittestFailureCause([string[]]$Lines) {
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

function Invoke-PythonUnitTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string[]]$Required = @(),
        [switch]$Discover,
        [string]$Python,
        [int]$TimeoutSeconds = 300
    )
    if (-not $Python) { $Python = Resolve-RealPython }
    if (-not $Python -or -not (Test-Path -LiteralPath $Python -PathType Leaf)) {
        Write-Host "FAILED: no usable Python interpreter$(if ($Python) { " at $Python" } else { ' (non-Store) found' })."
        Write-Host 'RESULT: 0 passed, 1 failed'
        return 1
    }

    $passed = 0
    $failed = 0
    $causes = [Collections.Generic.List[string]]::new()
    $present = @(Get-ChildItem -LiteralPath $Directory -File -Filter 'test_*.py' | Sort-Object Name | ForEach-Object BaseName)
    foreach ($module in $Required) {
        if ($module -notin $present) {
            $failed++
            $causes.Add("${module}: test module is missing from $Directory")
        }
    }
    $modules = if ($Discover) { $present } else { @($Required | Where-Object { $_ -in $present }) }

    $sandbox = Join-Path ([IO.Path]::GetTempPath()) ('python-unit-tests-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $sandbox
    try {
        foreach ($module in $modules) {
            Write-Host "--- $module ---"
            $run = Invoke-PythonTestModule $Python $Directory $module $sandbox $TimeoutSeconds
            if ($run.Stdout.Trim()) { Write-Host $run.Stdout.TrimEnd() }
            if ($run.Stderr.Trim()) { Write-Host $run.Stderr.TrimEnd() }

            $lines = @($run.Stderr -split '\r?\n')
            $ranLine = $lines | Where-Object { $_ -match '^Ran \d+ tests? in ' } | Select-Object -Last 1
            $verdict = $lines | Where-Object { $_ -match '^(OK|FAILED|NO TESTS RAN)\b' } | Select-Object -Last 1
            $ran = if ($ranLine -match '^Ran (\d+) ') { [int]$Matches[1] } else { 0 }

            if ($run.TimedOut) {
                $failed++
                $causes.Add("${module}: did not finish within $TimeoutSeconds seconds; the python process was stopped")
            } elseif (-not $ranLine -or -not $verdict) {
                $lastLine = $lines | Where-Object { $_.Trim() } | Select-Object -Last 1
                $failed++
                $causes.Add("${module}: exited $($run.ExitCode) with no unittest summary: $lastLine")
            } elseif ($ran -eq 0) {
                $failed++
                $causes.Add("${module}: ran zero tests (exit $($run.ExitCode))")
            } else {
                $broken = (Get-UnittestCount $verdict 'failures') + (Get-UnittestCount $verdict 'errors') +
                    (Get-UnittestCount $verdict 'unexpected successes')
                $skipped = Get-UnittestCount $verdict 'skipped'
                $passed += [Math]::Max(0, $ran - $broken - $skipped)
                $failed += $broken
                foreach ($cause in @(Get-UnittestFailureCause $lines)) { $causes.Add("${module}: $cause") }
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
    if ($failed -gt 0) { return 1 }
    return 0
}
