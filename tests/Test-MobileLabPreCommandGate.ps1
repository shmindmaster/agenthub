#Requires -Version 5.1
<#
Behavior tests for the worker's pre_command_gate (SH-4390): a pre-command that
dies right after start must fail the run (on a shared host its port may already
be taken, and the flow would otherwise talk to whatever else holds the port),
while a live service or a successful one-shot passes. The function is extracted
verbatim from mobile-lab.sh and exercised under bash, so the test covers the
shipped code, not a copy. Local and non-mutating; starts nothing lasting.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$worker = Join-Path $repoRoot 'packages\mobile-development\skills\mobile-device-lab\scripts\worker\mobile-lab.sh'

$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name -- $Detail" }
}

# bash: Git for Windows first (WSL's System32 bash mangles Windows paths),
# then whatever bash is on PATH (native on Linux/macOS runners).
$bash = $null
if ($env:ProgramFiles) {
    $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    if (Test-Path $gitBash) { $bash = $gitBash }
}
if (-not $bash) { $bash = (Get-Command bash -ErrorAction SilentlyContinue).Source }
if (-not $bash -or -not (Test-Path $bash)) {
    Report 'bash is available to run the worker gate' $false 'no Git bash and no bash on PATH'
    Write-Output "RESULT: $passed passed, $failed failed"
    exit 1
}
# Paths handed to bash must match the bash we picked: WSL mounts Windows
# drives under /mnt; Git bash and native bash take forward slashes.
function ConvertTo-BashPath([string]$Path) {
    if ($bash -match 'System32\\bash\.exe$') {
        $full = [IO.Path]::GetFullPath($Path)
        return ('/mnt/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/'))
    }
    return ($Path -replace '\\', '/')
}

$script = Get-Content -Raw -Encoding UTF8 $worker
$match = [regex]::Match($script, '(?ms)^pre_command_gate\(\) \{.*?^\}')
Report 'mobile-lab.sh defines pre_command_gate' $match.Success
Report 'run() wires the gate to the pre-command pid and log' `
    ($script -match 'pre_command_gate "\$PRE_PID" "\$out/pre-command\.log"')
if (-not $match.Success) {
    Write-Output "RESULT: $passed passed, $failed failed"
    exit 1
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('sh4390-gate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    $log = Join-Path $temp 'pre-command.log'
    $harness = @'
set -uo pipefail
die() { printf 'DIE: %s\n' "$*" >&2; exit 1; }
'@ + "`n" + $match.Value + "`n" + @'
scenario="$1"; logfile="$2"
case "$scenario" in
  alive)   sleep 30 & pid=$! ;;
  fail)    bash -c 'echo rig-boom >&2; exit 7' > "$logfile" 2>&1 & pid=$! ;;
  oneshot) bash -c 'exit 0' & pid=$! ;;
esac
pre_command_gate "$pid" "$logfile" 1
rc=$?
kill "$pid" 2>/dev/null || true
exit $rc
'@
    # bash needs LF line endings regardless of this file's own endings.
    $harness = $harness -replace "`r`n", "`n"
    $harnessPath = Join-Path $temp 'harness.sh'
    [IO.File]::WriteAllText($harnessPath, $harness)

    function Invoke-Scenario([string]$Name) {
        $err = Join-Path $temp "$Name.err"
        $out = Join-Path $temp "$Name.out"
        $p = Start-Process -FilePath $bash -ArgumentList @((ConvertTo-BashPath $harnessPath), $Name, (ConvertTo-BashPath $log)) `
            -NoNewWindow -Wait -PassThru -RedirectStandardError $err -RedirectStandardOutput $out
        return @{ Exit = $p.ExitCode; Err = (Get-Content -Raw -Encoding UTF8 $err -ErrorAction SilentlyContinue) }
    }

    $alive = Invoke-Scenario 'alive'
    Report 'a live pre-command passes the gate' ($alive.Exit -eq 0) "exit $($alive.Exit): $($alive.Err)"

    $fail = Invoke-Scenario 'fail'
    Report 'a pre-command that exits non-zero fails the gate with its code and log' `
        (($fail.Exit -eq 1) -and ($fail.Err -match 'pre-command exited with 7') -and ($fail.Err -match 'rig-boom')) `
        "exit $($fail.Exit): $($fail.Err)"

    $oneshot = Invoke-Scenario 'oneshot'
    Report 'a one-shot pre-command that exits 0 passes the gate' ($oneshot.Exit -eq 0) "exit $($oneshot.Exit): $($oneshot.Err)"
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
