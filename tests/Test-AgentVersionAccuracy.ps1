#Requires -Version 5.1
<#
Behavior test: registry/agents.json `version` must match what the installed
binary actually reports, not what was true the last time somebody looked.

Why: measured 2026-08-19, the first time this was checked end to end: 18 of
22 active hosts carried a stale `version`, three of them wrong in ways a
simple diff would not catch -- grok's recorded 0.2.114 belonged to a
different product line entirely (every artifact this install owns agrees on
the 1.0.x scheme instead), qoder's recorded 1.1.5 was HIGHER than the
installed 1.0.45 so it was never a real observation, and factory carried a
third number that matched neither the binary's own output nor the app
directory it ships under. Nothing in this repository compared the recorded
string to a live probe, so drift accumulated silently across every upgrade.
That is the same shape of bug Test-DeclaredExecutableAccountability and
Test-DeclaredVsDeployedMcp exist to catch for other fields -- a value written
as a snapshot and read forever after as current fact.

The probe is deliberately keyed by a `versionProbe` field (default 'cli')
rather than one universal strategy, because one strategy is actively unsafe
for part of the fleet:

  - 'cli'          - run `<executable> --version` and substring-match the
                      recorded version against stdout+stderr. This is safe
                      for a true CLI binary or a documented CLI entry point
                      (e.g. cursor.cmd, code-insiders.cmd) that prints and
                      exits without opening a window.
  - 'file-version'  - read the Win32 PE resource via
                      (Get-Item $exe).VersionInfo.FileVersion instead.
                      Required for a GUI app whose declared executable has no
                      separate CLI entry point -- antigravity-desktop,
                      antigravity-ide and warp all launch a window if invoked
                      with an arbitrary flag, so this file must never run
                      them to find out their version.
  - 'winget-package' - query the installed package record through the native
                      Windows Package Manager, in a redirected native process
                      with a fixed deadline and process-tree cleanup. This is
                      for Antigravity's `agy.exe`: its own version command
                      blocks, so it is not a truthful or safely bounded source.
  - 'none'          - there is no installed binary at all (opencode-desktop,
                      hermes, windsurf). The only thing to assert is that the
                      registry's own belief agrees: the declared executable
                      must really be absent, because a 'none' entry whose
                      executable DOES exist on disk means the record drifted
                      in the opposite direction and nobody would otherwise
                      notice a binary appeared.

Substring match, not equality: real CLIs decorate their own version with a
build hash and channel tag (grok: "grok 1.0.5 (5115b46bc9) [stable]"; warp's
FileVersion carries a leading "v" the recorded value omits), so the recorded
value must appear somewhere in the probe output rather than equal it exactly.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom used across this suite -- one PASS/FAIL line per
behavior/agent, exit 1 if anything failed.

Run: pwsh -NoProfile -File tests/Test-AgentVersionAccuracy.ps1
     powershell.exe -NoProfile -File tests/Test-AgentVersionAccuracy.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\PathBinding.ps1')
$executableBinding = New-AgentHubPathBindingContext -TargetUserProfile $env:USERPROFILE

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$activeAgents = @($agents.activeAgents | Where-Object { $_ })

# Bare names are not paths (qwen-code declares the bare command 'qwen'), and
# resolving on PATH is not proof of installation (an orphaned vendor wrapper
# can survive on PATH after an uninstall) -- so this resolver only ever says
# whether a FILE is really there, using Get-Command purely to turn a bare
# name into the absolute path PATH would actually run, per the guidance
# against invoking a bare command name that might resolve to the wrong
# binary, a script, or an alias.
function Resolve-ExecutableState {
    param($Value)
    if ($null -eq $Value) { return [pscustomobject]@{ State = 'Undeclared'; Path = $null } }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return [pscustomobject]@{ State = 'Undeclared'; Path = $null } }
    if ($text -match '[\\/]' -or (Test-AgentHubPathTemplate $text)) {
        if (Test-AgentHubPathTemplate $text) {
            $text = Resolve-AgentHubBoundPath -Declared $text -Context $executableBinding
        }
        if (Test-Path -LiteralPath $text -PathType Leaf) { return [pscustomobject]@{ State = 'Present'; Path = $text } }
        return [pscustomobject]@{ State = 'Absent'; Path = $text }
    }
    # A bare name can match several files across PATHEXT (qwen resolves to
    # qwen.cmd AND qwen.ps1 AND a third qwen.cmd on a second PATH entry).
    # Get-Command returns all of them as an array in that case; taking the
    # array whole and handing it to & later invokes it as multiple
    # positional arguments rather than one path, producing nonsense output.
    # -First 1 pins it to the single entry PATH/PATHEXT precedence would
    # actually run, matching real bare-name invocation.
    $command = Get-Command -Name $text -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return [pscustomobject]@{ State = 'Present'; Path = [string]$command.Source } }
    return [pscustomobject]@{ State = 'Absent'; Path = $text }
}

# Runs `<Path> --version` in a child job with a hard timeout, so a binary
# that blocks on stdin (some of these CLIs do, when invoked without a TTY)
# or hangs cannot stall this suite forever. Returns $null on timeout so the
# caller can tell "ran and produced no match" apart from "never finished".
function Invoke-VersionProbe {
    param([string]$Path, [int]$TimeoutSec = 30)
    $job = Start-Job -ScriptBlock {
        param($p)
        & $p '--version' 2>&1 | Out-String
    } -ArgumentList $Path
    $done = Wait-Job -Job $job -Timeout $TimeoutSec
    if (-not $done) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $null
    }
    $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if ($null -eq $out) { return '' }
    return ($out | Out-String)
}

# Unlike Stop-Job, taskkill /T terminates the native child process tree that a
# timed-out background job can leave behind. The only caller is winget-package,
# which records a validated package id; no shell is involved and no service is
# started.
function Stop-VersionProbeProcessTree {
    param([Parameter(Mandatory)][Diagnostics.Process]$Process)

    if ($Process.HasExited) { return }
    $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
        & $taskkill '/PID' ([string]$Process.Id) '/T' '/F' *> $null
    }
    if (-not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

# Run a known native executable directly, rather than through Start-Job. That
# avoids a second PowerShell host in the timing budget and preserves separate
# stdout/stderr while keeping the deadline fixed at the call site. Output is
# read asynchronously so an unexpectedly verbose CLI cannot deadlock on a
# redirected pipe before the timeout is evaluated.
function Invoke-BoundedNativeProbe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Arguments,
        [int]$TimeoutSec = 30
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Path
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ State = 'error'; Output = ''; Detail = 'Process.Start returned false.' }
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timeoutMs = [Math]::Max(1, $TimeoutSec * 1000)
        if (-not $process.WaitForExit($timeoutMs)) {
            Stop-VersionProbeProcessTree -Process $process
            $null = $process.WaitForExit(5000)
            return [pscustomobject]@{ State = 'timeout'; Output = ''; Detail = "did not exit within ${TimeoutSec}s; terminated its native process tree." }
        }
        [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr))
        return [pscustomobject]@{ State = 'complete'; Output = ($stdout.Result + $stderr.Result); Detail = $null }
    } catch {
        return [pscustomobject]@{ State = 'error'; Output = ''; Detail = $_.Exception.Message }
    } finally {
        $process.Dispose()
    }
}

$probedCount = 0

foreach ($agent in $activeAgents) {
    $id = [string]$agent.id
    $recordedVersion = [string]$agent.version

    $probeProperty = $agent.PSObject.Properties['versionProbe']
    $probe = if ($probeProperty -and -not [string]::IsNullOrWhiteSpace([string]$probeProperty.Value)) {
        [string]$probeProperty.Value
    } else {
        'cli'
    }

    $execProperty = $agent.PSObject.Properties['executable']
    $execValue = if ($execProperty) { $execProperty.Value } else { $null }
    $resolved = Resolve-ExecutableState -Value $execValue

    if ($probe -eq 'none') {
        # The record claims nothing is installed. If a real binary now
        # resolves, the record went stale in the OTHER direction -- a
        # product appeared and nobody updated versionProbe back to 'cli'.
        $passed = ($resolved.State -ne 'Present')
        Report "id=$id (versionProbe=none): declared executable is really absent" $passed `
            "executable '$execValue' resolved to State=$($resolved.State), Path=$($resolved.Path) -- versionProbe says 'none' (no binary to check) but a file DOES exist on disk at that resolved path, so the record is stale."
        $probedCount++
        continue
    }

    if ($probe -eq 'file-version') {
        if ($resolved.State -eq 'Undeclared') {
            Report "id=$id (versionProbe=file-version): executable is declared" $false `
                "versionProbe is 'file-version' but no executable is declared at all (null or blank), so there is nothing to read FileVersion from."
            $probedCount++
            continue
        }
        if ($resolved.State -ne 'Present') {
            Report "id=$id (versionProbe=file-version): declared executable exists on disk" $false `
                "declared executable path '$($resolved.Path)' does not exist on this machine."
            $probedCount++
            continue
        }
        try {
            $fileVersion = (Get-Item -LiteralPath $resolved.Path).VersionInfo.FileVersion
        } catch {
            Report "id=$id (versionProbe=file-version): FileVersion is readable" $false `
                "reading (Get-Item '$($resolved.Path)').VersionInfo.FileVersion threw: $($_.Exception.Message)"
            $probedCount++
            continue
        }
        $fileVersionText = if ($null -eq $fileVersion) { '' } else { [string]$fileVersion }
        $matched = $fileVersionText.Contains($recordedVersion)
        Report "id=${id}: recorded version appears in PE FileVersion (never launched)" $matched `
            "recorded version.json value was '$recordedVersion'; actual (Get-Item).VersionInfo.FileVersion was '$fileVersionText'."
        $probedCount++
        continue
    }

    if ($probe -eq 'winget-package') {
        $packageProperty = $agent.PSObject.Properties['versionPackageId']
        $packageId = if ($packageProperty) { [string]$packageProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($packageId) -or $packageId -notmatch '^[A-Za-z0-9.-]+$') {
            Report "id=$id (versionProbe=winget-package): package id is safe and declared" $false `
                "versionProbe is 'winget-package' but versionPackageId was '$packageId'; it must be a non-empty WinGet identifier using only letters, digits, dots, and hyphens."
            $probedCount++
            continue
        }
        $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winget) {
            Report "id=$id (versionProbe=winget-package): WinGet is available" $false `
                "the authoritative package query cannot run because winget.exe is unavailable on PATH."
            $probedCount++
            continue
        }
        $arguments = "list --id $packageId --exact --accept-source-agreements --disable-interactivity"
        $bounded = Invoke-BoundedNativeProbe -Path ([string]$winget.Source) -Arguments $arguments -TimeoutSec 30
        if ($bounded.State -eq 'timeout') {
            Report "id=${id}: WinGet package query completed within bounded timeout" $false `
                "the probe $($bounded.Detail) Recorded version was '$recordedVersion'."
            $probedCount++
            continue
        }
        if ($bounded.State -ne 'complete') {
            Report "id=${id}: WinGet package query launched" $false `
                "the bounded probe could not run: $($bounded.Detail)"
            $probedCount++
            continue
        }
        $packageLines = @($bounded.Output -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($packageId) })
        $matched = @($packageLines | Where-Object { $_ -match ('(?<!\S)' + [regex]::Escape($recordedVersion) + '(?!\S)') }).Count -eq 1
        Report "id=${id}: recorded version appears in bounded WinGet installed-package output" $matched `
            "recorded version.json value was '$recordedVersion'; package '$packageId' output was: $($packageLines -join ' | ')"
        $probedCount++
        continue
    }

    # Default: 'cli'.
    if ($resolved.State -eq 'Undeclared') {
        Report "id=$id (versionProbe=cli): executable is declared" $false `
            "versionProbe is 'cli' (the default) but no executable is declared at all (null or blank), so there is no binary to run --version against."
        $probedCount++
        continue
    }
    if ($resolved.State -ne 'Present') {
        Report "id=$id (versionProbe=cli): declared executable exists on disk" $false `
            "declared executable path '$($resolved.Path)' does not exist on this machine."
        $probedCount++
        continue
    }
    $output = Invoke-VersionProbe -Path $resolved.Path -TimeoutSec 30
    if ($null -eq $output) {
        Report "id=${id}: '$($resolved.Path) --version' completed within timeout" $false `
            "the probe did not return within 30s and was terminated; recorded version was '$recordedVersion'."
        $probedCount++
        continue
    }
    $matched = $output.Contains($recordedVersion)
    Report "id=${id}: recorded version appears in '--version' output" $matched `
        "recorded version.json value was '$recordedVersion'; actual '$($resolved.Path) --version' output was: $($output.Trim())"
    $probedCount++
}

# Without this, a shape change to activeAgents (renamed key, restructured
# entries, an exception swallowed before the first Report call) would empty
# the loop above and leave the file green having verified nothing -- the
# same vacuous-pass shape tests/Test-DeclaredVsDeployedMcp.ps1 guards against
# with its own '$checked -gt 0' assertion at the bottom of that file.
Report 'at least one agent version was actually probed' ($probedCount -gt 0) `
    'No agent was evaluated. If activeAgents changed shape or the field names this loop reads were renamed, every check above silently vanished.'

Write-Host ''
Write-Host "SCOPE: $($activeAgents.Count) active agent(s), $probedCount probed"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
