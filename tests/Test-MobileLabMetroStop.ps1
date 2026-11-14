#Requires -Version 5.1
<#
Behavior tests for the worker's metro_stop (SH-4390): pkill is asynchronous,
so metro_stop must wait until the old Metro actually releases port 8081 before
the next Expo starts; otherwise Expo's port check refuses the new Metro
(measured on sh-forge). The function is extracted verbatim from mobile-lab.sh
and exercised under bash against a real TCP listener with a delayed graceful
shutdown - against the old fire-and-forget pkill this test fails (STILL-BOUND).
Local and non-mutating; the listener is killed and self-exits after 30 s.
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
    Report 'bash is available to run metro_stop' $false 'no Git bash and no bash on PATH'
    Write-Output "RESULT: $passed passed, $failed failed"
    exit 1
}
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
    Report 'node is available for the TCP listener' $false 'node not on PATH'
    Write-Output "RESULT: $passed passed, $failed failed"
    exit 1
}
function ConvertTo-BashPath([string]$Path) {
    if ($bash -match 'System32\\bash\.exe$') {
        $full = [IO.Path]::GetFullPath($Path)
        return ('/mnt/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/'))
    }
    return ($Path -replace '\\', '/')
}

$script = Get-Content -Raw -Encoding UTF8 $worker
$match = [regex]::Match($script, '(?ms)^metro_stop\(\) \{.*?^\}')
Report 'mobile-lab.sh defines metro_stop' $match.Success
Report 'run() stops Metro before starting the new one' ($script -match '(?m)^\s*metro_stop\s*$')
if (-not $match.Success) {
    Write-Output "RESULT: $passed passed, $failed failed"
    exit 1
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('sh4390-metro-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
    $harness = @'
set -uo pipefail
die() { printf 'DIE: %s\n' "$*" >&2; exit 1; }
log() { :; }
'@ + "`n" + $match.Value + "`n" + @'
scenario="$1"; port="$2"
listener=""
trap 'kill "$listener" 2>/dev/null || true' EXIT
pkill() { :; }
if [ "$scenario" = bound ]; then
  # A listener that takes 1.5 s to release its socket after SIGTERM, like a
  # graceful Metro shutdown: the old fire-and-forget pkill returns while the
  # port is still bound.
  node -e 'const s=require("net").createServer();s.listen('"$port"',"127.0.0.1");process.on("SIGTERM",()=>{setTimeout(()=>{s.close(()=>process.exit(0))},1500)});setTimeout(()=>process.exit(0),30000)' &
  listener=$!
  up=false
  for i in $(seq 1 50); do
    if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then up=true; break; fi
    sleep 0.2
  done
  [ "$up" = true ] || { echo LISTENER-NEVER-BOUND; exit 1; }
  pkill() { kill "$listener" 2>/dev/null || true; }
fi
start=$(date +%s)
metro_stop "$port"
elapsed=$(( $(date +%s) - start ))
if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then echo STILL-BOUND; exit 1; fi
echo "PORT-FREE ELAPSED=$elapsed"
'@
    $harness = $harness -replace "`r`n", "`n"
    $harnessPath = Join-Path $temp 'harness.sh'
    [IO.File]::WriteAllText($harnessPath, $harness)
    $port = Get-Random -Minimum 20000 -Maximum 40000

    function Invoke-Scenario([string]$Name, [int]$Port) {
        $err = Join-Path $temp "$Name.err"
        $out = Join-Path $temp "$Name.out"
        $p = Start-Process -FilePath $bash -ArgumentList @((ConvertTo-BashPath $harnessPath), $Name, "$Port") `
            -NoNewWindow -Wait -PassThru -RedirectStandardError $err -RedirectStandardOutput $out
        return @{ Exit = $p.ExitCode; Out = (Get-Content -Raw -Encoding UTF8 $out -ErrorAction SilentlyContinue); Err = (Get-Content -Raw -Encoding UTF8 $err -ErrorAction SilentlyContinue) }
    }

    $bound = Invoke-Scenario 'bound' $port
    $boundElapsed = if ($bound.Out -match 'ELAPSED=(\d+)') { [int]$Matches[1] } else { -1 }
    Report 'metro_stop waits for a dying Metro to release the port, then returns' `
        (($bound.Exit -eq 0) -and ($bound.Out -match 'PORT-FREE') -and ($boundElapsed -ge 1) -and ($boundElapsed -lt 12)) `
        "exit $($bound.Exit), metro_stop took ${boundElapsed}s: $($bound.Out) $($bound.Err)"

    $free = Invoke-Scenario 'free' $port
    $freeElapsed = if ($free.Out -match 'ELAPSED=(\d+)') { [int]$Matches[1] } else { -1 }
    Report 'metro_stop returns promptly when nothing holds the port' `
        (($free.Exit -eq 0) -and ($free.Out -match 'PORT-FREE') -and ($freeElapsed -ge 0) -and ($freeElapsed -lt 3)) `
        "exit $($free.Exit), metro_stop took ${freeElapsed}s: $($free.Out) $($free.Err)"
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
