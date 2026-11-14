#Requires -Version 5.1
<#
Behavior tests for the sh-forge build-lane files in ci/do-runner (SH-4524):
the Android lane (android-build.sh, android-setup.sh, android-builder.Dockerfile)
and the jobs dashboard (jobs-dashboard.py, forge-jobs-dashboard.service).

Local and non-mutating: bash syntax checks through Git for Windows, python
fixture checks through the local interpreter, and consistency checks against
the runbook. Nothing here talks to sh-forge, docker, or a device.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$ciDir = Join-Path $repoRoot 'ci\do-runner'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

function Read-Utf8([string]$Path) {
    (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

# --- lane files exist -------------------------------------------------------
$laneFiles = @('android-build.sh', 'android-setup.sh', 'android-builder.Dockerfile', 'jobs-dashboard.py', 'forge-jobs-dashboard.service')
$missing = @($laneFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ciDir $_)) })
Report 'ci/do-runner carries every forge lane file' ($missing.Count -eq 0) "missing: $($missing -join ', ')"

# --- bash syntax (Git for Windows bash, never WSL) ---------------------------
$bashCandidates = @()
if ($env:ProgramFiles) { $bashCandidates += "$env:ProgramFiles\Git\bin\bash.exe" }
if (${env:ProgramFiles(x86)}) { $bashCandidates += "${env:ProgramFiles(x86)}\Git\bin\bash.exe" }
if ($env:LOCALAPPDATA) { $bashCandidates += "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe" }
$gitBash = $bashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $gitBash) {
    Report 'Git for Windows bash is available for syntax checks' $false 'no bash.exe found under Program Files'
} else {
    foreach ($script in @('android-build.sh', 'android-setup.sh')) {
        $path = (Join-Path $ciDir $script) -replace '\\', '/'
        & $gitBash -n $path 2>&1 | Out-Null
        Report "$script passes bash -n" ($LASTEXITCODE -eq 0) "bash -n exit=$LASTEXITCODE"
    }
    # The lane must refuse a missing repo before touching docker or the network.
    & $gitBash ((Join-Path $ciDir 'android-build.sh') -replace '\\', '/') '/nonexistent-repo.git' 'somebranch' 2>&1 | Out-Null
    Report 'android-build.sh refuses a missing repo with exit 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
}

# --- Dockerfile pins match the ABACare engines and the RN 0.86 toolchain -----
$dockerfile = Read-Utf8 (Join-Path $ciDir 'android-builder.Dockerfile')
Report 'android-builder.Dockerfile pins Node 24.22 (engines >=24.20)' ($dockerfile -match 'node-v24\.22\.\d+-linux-x64') 'Node 24.22.x tarball not pinned'
Report 'android-builder.Dockerfile pins pnpm 11.15 (packageManager pnpm@11.15.0)' ($dockerfile -match 'pnpm@11\.15\.0') 'pnpm@11.15.0 not pinned'
Report 'android-builder.Dockerfile installs the RN 0.86 SDK set' (
    ($dockerfile -match 'platforms;android-36') -and
    ($dockerfile -match 'build-tools;36\.0\.0') -and
    ($dockerfile -match 'ndk;27\.1\.12297006')
) 'SDK 36 / build-tools 36.0.0 / NDK 27.1.12297006 must all be baked in'

# --- python dashboard: compile, then fixture-driven collect/render -----------
$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) {
    Report 'python is available for the dashboard checks' $false 'python not on PATH'
} else {
    $dash = Join-Path $ciDir 'jobs-dashboard.py'
    & $python.Source -m py_compile $dash 2>&1 | Out-Null
    Report 'jobs-dashboard.py compiles' ($LASTEXITCODE -eq 0) "py_compile exit=$LASTEXITCODE"

    $fixture = Join-Path ([IO.Path]::GetTempPath()) ("forge-lanes-test-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fixture 'jobs\older-job') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixture 'jobs\newer-job') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'jobs\newer-job\plan.json') -Value '{}'
        (Get-Item (Join-Path $fixture 'jobs\older-job')).LastWriteTime = (Get-Date).AddDays(-2)
        New-Item -ItemType Directory -Path (Join-Path $fixture 'artifacts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture 'artifacts\abacare-x-00000000.apk') -Value 'not-a-real-apk'
        Set-Content -LiteralPath (Join-Path $fixture 'artifacts\abacare-x-00000000.log') -Value 'log'
        $check = @'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("dash", sys.argv[1])
dash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dash)
jobs = dash.collect_dirs(os.environ["FORGE_JOBS_DIR"], __import__("time").time())
assert [j["name"] for j in jobs] == ["newer-job", "older-job"], jobs
arts = dash.collect_files(os.environ["FORGE_ANDROID_ARTIFACTS"], __import__("time").time(), suffixes=(".apk",))
assert [a["name"] for a in arts] == ["abacare-x-00000000.apk"], arts
assert arts[0]["size"].endswith("B"), arts
data = dash.collect()
page = dash.render_html(data)
assert "newer-job" in page and "sh-forge" in page
assert json.dumps(data)
print("FIXTURE-OK")
'@
        $checkFile = Join-Path $fixture 'check.py'
        Set-Content -LiteralPath $checkFile -Value $check -Encoding UTF8
        $env:FORGE_JOBS_DIR = Join-Path $fixture 'jobs'
        $env:FORGE_ANDROID_ARTIFACTS = Join-Path $fixture 'artifacts'
        $env:FORGE_MAC_LEASES = Join-Path $fixture 'leases'
        $env:FORGE_DASHBOARD_NO_DOCKER = '1'
        $out = & $python.Source $checkFile $dash 2>&1
        Report 'dashboard collect/render works against a fixture tree' ("$out" -match 'FIXTURE-OK') "output: $out"
    } finally {
        Remove-Item Env:FORGE_JOBS_DIR, Env:FORGE_ANDROID_ARTIFACTS, Env:FORGE_MAC_LEASES, Env:FORGE_DASHBOARD_NO_DOCKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- service unit and runbook agree with the deployed layout -----------------
$unit = Read-Utf8 (Join-Path $ciDir 'forge-jobs-dashboard.service')
Report 'the service unit runs the installed dashboard path' ($unit -match 'ExecStart=/usr/bin/python3 /opt/forge/jobs-dashboard/jobs-dashboard\.py') 'ExecStart path drifted from the install location'
$dashSource = Read-Utf8 (Join-Path $ciDir 'jobs-dashboard.py')
Report 'the dashboard binds loopback 8790, the port the Caddyfile proxies' (($dashSource -match '"JOBS_DASHBOARD_PORT", "8790"') -and ($dashSource -match '127\.0\.0\.1')) 'bind address or default port changed without the Caddyfile'
$runbook = Read-Utf8 (Join-Path $repoRoot 'docs\runbooks\do-interim-release.md')
Report 'the runbook documents the Android lane and the jobs dashboard' (
    ($runbook -match 'android-build') -and
    ($runbook -match 'jobs\.forge\.shtrial\.com') -and
    ($runbook -match 'forge/android-builder:2')
) 'docs/runbooks/do-interim-release.md must document both lanes'

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
