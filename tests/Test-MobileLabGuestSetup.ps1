#Requires -Version 5.1
<#
Behavior tests for the canonical guest Appium setup script
(packages/mobile-development/skills/mobile-device-lab/scripts/guest/setup-appium-guest.sh).

The real script runs under Git for Windows' bash against stub `appium`, `npm`,
`xcodebuild`, `xcrun`, `ps`, `pkill`, `killall`, `brew`, and `ffmpeg` binaries
in a throwaway HOME. Nothing reaches the macOS guest, a Simulator, npm, or a
real Appium install. Node is the real host node, which the script uses only to
parse JSON.

Defects these cases pin (found 2026-10-13):
  * `appium driver install ... || appium driver update xcuitest --unsafe || true`
    reported success after a failed install, and `update --unsafe` moves off
    the pin.
  * `wait "$doctor_pid"; doctor_rc=$?` under `set -e` exited on a failing
    doctor before printing its output or a reason.
  * The doctor-timeout remedy was `pkill -f 'xcodebuild.*WebDriverAgent';
    xcrun simctl shutdown all`, which kills other owners' runners.
  * "any WebDriverAgent-* product exists" skipped the WDA build after a driver
    or Xcode change, leaving a product built from another WDA version.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packageRoot = Join-Path $repoRoot 'packages\mobile-development'
$setupScript = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\guest\setup-appium-guest.sh'
$syncScript = Join-Path $packageRoot 'skills\mobile-device-lab\scripts\Sync-MobileLabGuestScripts.ps1'
$failures = [Collections.Generic.List[string]]::new()
$reported = 0

function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

Import-Module (Join-Path $packageRoot 'MobileDevelopment.psm1') -Force
$contract = Get-MobileDevelopmentContract
$appiumPin = [string]$contract.expectations.guestAppium.version
$driverPin = [string]$contract.expectations.xcuitest.version
$xcodeCeiling = [string]$contract.expectations.xcode.maxCompatibleVersion

# Git for Windows' bash, never System32\bash.exe (WSL), which has neither the
# host PATH translation nor the host node these cases rely on.
$bash = $null
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    # git.exe may resolve from cmd\, bin\, or mingw64\bin\ under the Git root.
    $dir = Split-Path -Parent $git.Source
    for ($i = 0; $i -lt 3 -and $dir -and -not $bash; $i++) {
        $dir = Split-Path -Parent $dir
        foreach ($candidate in @((Join-Path $dir 'bin\bash.exe'), (Join-Path $dir 'usr\bin\bash.exe'))) {
            if (Test-Path -LiteralPath $candidate) { $bash = $candidate; break }
        }
    }
}
if (-not $bash) {
    Report 'Git for Windows bash is available to run the guest setup script' $false "git=$($git.Source)"
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-guest-setup-' + [guid]::NewGuid().ToString('N'))
$stubDir = Join-Path $fixtureRoot 'stubs'
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Lf([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $utf8)
}

$stubs = [ordered]@{
    appium = @'
#!/bin/bash
S="$STUB_STATE"
printf 'appium %s\n' "$*" >>"$S/calls.log"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
case "$1" in
  --version) [ -f "$S/appium_version" ] || exit 127; cat "$S/appium_version" ;;
  driver)
    case "$2" in
      list)
        [ -f "$S/list_fail" ] && { echo "listing exploded" >&2; exit 3; }
        if [ -f "$S/xcuitest_version" ]; then
          printf '{"xcuitest":{"installed":true,"version":"%s","installPath":"%s"}}\n' "$(cat "$S/xcuitest_version")" "$(native "$S/appium-home/node_modules/appium-xcuitest-driver")"
        else
          echo '{}'
        fi ;;
      install)
        [ -f "$S/install_fail" ] && { echo "npm ERR! network unreachable" >&2; exit 1; }
        [ -f "$S/xcuitest_version" ] && { echo 'A driver named "xcuitest" is already installed.' >&2; exit 1; }
        v="${3#xcuitest@}"
        printf '%s\n' "$v" >"$S/xcuitest_version"
        d="$S/appium-home/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent"
        mkdir -p "$d"
        printf '{"version":"%s"}\n' "$(cat "$S/wda_on_install" 2>/dev/null || echo 11.4.0)" >"$d/package.json" ;;
      uninstall)
        [ -f "$S/uninstall_fail" ] && exit 1
        rm -f "$S/xcuitest_version"
        rm -rf "$S/appium-home/node_modules/appium-xcuitest-driver" ;;
      update) echo "appium driver update" >>"$S/violations"; exit 0 ;;
      doctor)
        case "$(cat "$S/doctor_mode" 2>/dev/null || echo ok)" in
          ok) echo "info Doctor ### Starting doctor diagnostics ###"; echo "Everything looks good, bye!" ;;
          optional) echo " ! applesimutils is not installed"; echo "0 required fixes needed, 2 optional fixes possible" ;;
          required) echo " x xcrun is not usable"; echo "12 required fixes needed, 0 optional fixes possible"; echo "Error: Treatment required" >&2; exit 1 ;;
          crash) echo "TypeError: Cannot read properties of undefined" >&2; exit 1 ;;
          nochecks) echo 'The driver "xcuitest" does not export any doctor checks' ;;
          lying) echo "1 required fix needed, 0 optional fixes possible" ;;
          hang) exec sleep 30 ;;
        esac ;;
      run)
        [ -f "$S/build_fail" ] && { echo "xcodebuild: ** BUILD FAILED **" >&2; exit 65; }
        n=$(( $(cat "$S/builds" 2>/dev/null || echo 0) + 1 ))
        echo "$n" >"$S/builds"
        mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/WebDriverAgent-synthetic/Build/Products/Debug-iphonesimulator/WebDriverAgentRunner-Runner.app" ;;
    esac ;;
esac
'@
    npm = @'
#!/bin/bash
S="$STUB_STATE"
printf 'npm %s\n' "$*" >>"$S/calls.log"
[ -f "$S/npm_fail" ] && { echo "npm ERR! 503" >&2; exit 1; }
[ -f "$S/appium_shadowed" ] && exit 0
case "$3" in appium@*) printf '%s\n' "${3#appium@}" >"$S/appium_version" ;; esac
'@
    xcodebuild = @'
#!/bin/bash
printf 'Xcode %s\nBuild version %s\n' "${STUB_XCODE:-26.6}" "${STUB_XCODE_BUILD:-17F100}"
'@
    xcrun = @'
#!/bin/bash
S="$STUB_STATE"
if [ "$1 $2" = "simctl list" ]; then
  [ -f "$S/no_runtime" ] && { echo "== Runtimes =="; exit 0; }
  printf '== Runtimes ==\niOS 26.5 (26.5 - 23F77) - com.apple.CoreSimulator.SimRuntime.iOS-26-5\n'
  exit 0
fi
printf 'xcrun %s\n' "$*" >>"$S/violations"
'@
    ps = @'
#!/bin/bash
# A foreign WebDriverAgent runner owned by someone else's Appium session.
[ -n "${STUB_PS_FAIL:-}" ] && { echo "ps: unknown option" >&2; exit 1; }
case "$*" in
  *-axo*) printf '4242 4200 /Applications/Xcode-26.6.app/Contents/Developer/usr/bin/xcodebuild build-for-testing test-without-building -project /Users/other/.appium/WebDriverAgent.xcodeproj -destination id=11111111-2222-3333-4444-555555555555\n' ;;
  *-p*4200*) echo "node /Users/other/.nvm/bin/appium server --port 4723" ;;
esac
'@
    pkill = "#!/bin/bash`nprintf 'pkill %s\n' `"`$*`" >>`"`$STUB_STATE/violations`"`n"
    killall = "#!/bin/bash`nprintf 'killall %s\n' `"`$*`" >>`"`$STUB_STATE/violations`"`n"
    brew = "#!/bin/bash`nprintf 'brew %s\n' `"`$*`" >>`"`$STUB_STATE/calls.log`"`n"
    ffmpeg = "#!/bin/bash`necho 'ffmpeg version 8.0-synthetic'`n"
}

function New-Case {
    param([string]$Name)
    $root = Join-Path $fixtureRoot $Name
    $home_ = Join-Path $root 'home'
    $state = Join-Path $root 'state'
    New-Item -ItemType Directory -Force -Path (Join-Path $home_ 'mobile-lab'), $state | Out-Null
    Write-Lf (Join-Path $home_ 'mobile-lab\mobile-development.env') (@(
        "APPIUM_VERSION='$appiumPin'"
        "XCUITEST_VERSION='$driverPin'"
        "XCODE_MAX_COMPATIBLE='$xcodeCeiling'"
        "XCODE_CEILING_REASON='synthetic ceiling reason'"
        "APPIUM_PORT='4723'"
        "APPIUM_BIND_ADDRESS='0.0.0.0'"
    ) -join "`n")
    [pscustomobject]@{ Root = $root; Home = $home_; State = $state }
}

function Set-State($Case, [string]$Name, [string]$Value = '') { Write-Lf (Join-Path $Case.State $Name) $Value }
function Get-State($Case, [string]$Name) {
    $path = Join-Path $Case.State $Name
    if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim() } else { '' }
}
function Get-Stamp($Case) {
    $path = Join-Path $Case.Home 'mobile-lab\state\wda-build.key'
    if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim() } else { '' }
}

function Invoke-Setup {
    param($Case, [hashtable]$Env = @{}, [string[]]$Arguments = @())
    $saved = @{}
    $vars = @{ HOME = $Case.Home; STUB_STATE = $Case.State; STUB_BIN = $stubDir; DOCTOR_POLL = '1' } + $Env
    foreach ($key in $vars.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key, $vars[$key]) }
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Stubs go first INSIDE bash: Git bash puts /usr/bin (its own ps)
        # ahead of anything prepended on the Windows side.
        $output = @(& $bash --noprofile --norc -c 'PATH="$(cygpath -u "$STUB_BIN"):$PATH"; export PATH; exec bash "$@"' setup $setupScript @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $old
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    }
    [pscustomobject]@{ ExitCode = $code; Text = ($output -join "`n") }
}

try {
    New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
    foreach ($name in $stubs.Keys) { Write-Lf (Join-Path $stubDir $name) $stubs[$name] }

    # -------------------------------------------------------------- happy path
    $fresh = New-Case 'fresh'
    $first = Invoke-Setup $fresh
    $second = Invoke-Setup $fresh
    Report 'fresh guest installs both pins, passes doctor, builds WDA once, and stamps the build key' (
        $first.ExitCode -eq 0 -and (Get-State $fresh 'appium_version') -eq $appiumPin -and
        (Get-State $fresh 'xcuitest_version') -eq $driverPin -and (Get-State $fresh 'builds') -eq '1' -and
        (Get-Stamp $fresh) -eq "xcuitest=$driverPin;wda=11.4.0;xcode=17F100" -and
        $first.Text -match 'doctor: 0 required fixes'
    ) "exit=$($first.ExitCode) stamp=$(Get-Stamp $fresh) out=$($first.Text)"
    Report 'a re-run with nothing changed installs nothing and does not rebuild WDA' (
        $second.ExitCode -eq 0 -and (Get-State $fresh 'builds') -eq '1' -and
        $second.Text -match 'already built for' -and
        @((Get-State $fresh 'calls.log') -split "`n" | Where-Object { $_ -match '^(npm install|appium driver (install|uninstall))' }).Count -eq 2
    ) "exit=$($second.ExitCode) builds=$(Get-State $fresh 'builds') out=$($second.Text)"

    # ---------------------------------------------- pin move is version-aware
    $moved = New-Case 'pin-move'
    Set-State $moved 'appium_version' $appiumPin
    Set-State $moved 'xcuitest_version' '12.3.1'
    $oldWda = Join-Path $moved.State 'appium-home\node_modules\appium-xcuitest-driver\node_modules\appium-webdriveragent'
    New-Item -ItemType Directory -Force -Path $oldWda | Out-Null
    Write-Lf (Join-Path $oldWda 'package.json') '{"version":"9.15.0"}'
    New-Item -ItemType Directory -Force -Path (Join-Path $moved.Home 'Library\Developer\Xcode\DerivedData\WebDriverAgent-old\Build\Products\Debug-iphonesimulator\WebDriverAgentRunner-Runner.app') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $moved.Home 'mobile-lab\state') | Out-Null
    Write-Lf (Join-Path $moved.Home 'mobile-lab\state\wda-build.key') "xcuitest=12.3.1;wda=9.15.0;xcode=17F100`n"
    Set-State $moved 'wda_on_install' '11.4.0'
    $move = Invoke-Setup $moved
    Report 'an off-pin driver is uninstalled and the pin installed, never updated past it' (
        $move.ExitCode -eq 0 -and (Get-State $moved 'xcuitest_version') -eq $driverPin -and
        (Get-State $moved 'calls.log') -match 'appium driver uninstall xcuitest' -and
        -not (Get-State $moved 'violations')
    ) "exit=$($move.ExitCode) violations=$(Get-State $moved 'violations') out=$($move.Text)"
    Report 'a WDA product built for the old driver and WDA is rebuilt, not reused' (
        $move.ExitCode -eq 0 -and (Get-State $moved 'builds') -eq '1' -and
        $move.Text -match "built for 'xcuitest=12\.3\.1;wda=9\.15\.0" -and
        (Get-Stamp $moved) -eq "xcuitest=$driverPin;wda=11.4.0;xcode=17F100"
    ) "builds=$(Get-State $moved 'builds') stamp=$(Get-Stamp $moved) out=$($move.Text)"

    $xcodeMoved = Invoke-Setup $fresh -Env @{ STUB_XCODE_BUILD = '17F200' }
    Report 'an Xcode build change rebuilds WDA even with the driver unchanged' (
        $xcodeMoved.ExitCode -eq 0 -and (Get-State $fresh 'builds') -eq '2' -and
        (Get-Stamp $fresh) -eq "xcuitest=$driverPin;wda=11.4.0;xcode=17F200"
    ) "builds=$(Get-State $fresh 'builds') out=$($xcodeMoved.Text)"

    $unknown = New-Case 'wda-unknown'
    Set-State $unknown 'appium_version' $appiumPin
    Set-State $unknown 'xcuitest_version' $driverPin
    New-Item -ItemType Directory -Force -Path (Join-Path $unknown.Home 'Library\Developer\Xcode\DerivedData\WebDriverAgent-x\Build\Products\Debug-iphonesimulator\WebDriverAgentRunner-Runner.app') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $unknown.Home 'mobile-lab\state') | Out-Null
    Write-Lf (Join-Path $unknown.Home 'mobile-lab\state\wda-build.key') "xcuitest=$driverPin;wda=unknown;xcode=17F100`n"
    $unknownRun = Invoke-Setup $unknown
    Report 'an unknown WDA source version never matches an existing product' (
        $unknownRun.ExitCode -eq 0 -and (Get-State $unknown 'builds') -eq '1' -and $unknownRun.Text -match 'cannot be matched'
    ) "builds=$(Get-State $unknown 'builds') out=$($unknownRun.Text)"

    # npm may hoist appium-webdriveragent beside the driver instead of nesting it.
    $hoisted = New-Case 'wda-hoisted'
    Set-State $hoisted 'appium_version' $appiumPin
    Set-State $hoisted 'xcuitest_version' $driverPin
    New-Item -ItemType Directory -Force -Path (Join-Path $hoisted.State 'appium-home\node_modules\appium-xcuitest-driver') | Out-Null
    $hoistedWda = Join-Path $hoisted.State 'appium-home\node_modules\appium-webdriveragent'
    New-Item -ItemType Directory -Force -Path $hoistedWda | Out-Null
    Write-Lf (Join-Path $hoistedWda 'package.json') '{"version":"11.5.2"}'
    $hoistedRun = Invoke-Setup $hoisted
    Report 'a hoisted appium-webdriveragent version is found and keys the WDA build' (
        $hoistedRun.ExitCode -eq 0 -and (Get-Stamp $hoisted) -eq "xcuitest=$driverPin;wda=11.5.2;xcode=17F100"
    ) "stamp=$(Get-Stamp $hoisted) out=$($hoistedRun.Text)"

    $buildFail = New-Case 'build-fail'
    Set-State $buildFail 'build_fail'
    $bf = Invoke-Setup $buildFail
    Remove-Item -LiteralPath (Join-Path $buildFail.State 'build_fail')
    $bfRetry = Invoke-Setup $buildFail
    Report 'a failed WDA build exits non-zero, leaves no stamp, and the next run rebuilds' (
        $bf.ExitCode -ne 0 -and $bf.Text -match 'FATAL: appium driver run xcuitest build-wda failed' -and
        $bfRetry.ExitCode -eq 0 -and (Get-State $buildFail 'builds') -eq '1' -and (Get-Stamp $buildFail) -match '^xcuitest='
    ) "first=$($bf.ExitCode) retry=$($bfRetry.ExitCode) out=$($bf.Text)"

    # ------------------------------------------------------- fail-closed setup
    $installFail = New-Case 'install-fail'
    Set-State $installFail 'install_fail'
    $if_ = Invoke-Setup $installFail
    Report 'a failed driver install exits non-zero before doctor, never falls back to update' (
        $if_.ExitCode -ne 0 -and $if_.Text -match "FATAL: appium driver install xcuitest@$([regex]::Escape($driverPin)) failed" -and
        (Get-State $installFail 'calls.log') -notmatch 'driver doctor' -and -not (Get-State $installFail 'violations') -and
        -not (Get-Stamp $installFail)
    ) "exit=$($if_.ExitCode) calls=$(Get-State $installFail 'calls.log') out=$($if_.Text)"

    $listFail = New-Case 'list-fail'
    Set-State $listFail 'appium_version' $appiumPin
    Set-State $listFail 'list_fail'
    $lf = Invoke-Setup $listFail
    Report 'an unreadable driver listing fails closed instead of reading as not installed' (
        $lf.ExitCode -ne 0 -and $lf.Text -match 'cannot tell which driver is installed' -and $lf.Text -match 'listing exploded' -and
        (Get-State $listFail 'calls.log') -notmatch 'driver install'
    ) "exit=$($lf.ExitCode) out=$($lf.Text)"

    $uninstallFail = New-Case 'uninstall-fail'
    Set-State $uninstallFail 'appium_version' $appiumPin
    Set-State $uninstallFail 'xcuitest_version' '12.3.1'
    Set-State $uninstallFail 'uninstall_fail'
    $uf = Invoke-Setup $uninstallFail
    Report 'a failed uninstall of an off-pin driver stops before any install' (
        $uf.ExitCode -ne 0 -and $uf.Text -match 'uninstall xcuitest failed' -and (Get-State $uninstallFail 'calls.log') -notmatch 'driver install'
    ) "exit=$($uf.ExitCode) out=$($uf.Text)"

    $npmFail = New-Case 'npm-fail'
    Set-State $npmFail 'npm_fail'
    $nf = Invoke-Setup $npmFail
    $shadow = New-Case 'shadowed'
    Set-State $shadow 'appium_version' '2.19.0'
    Set-State $shadow 'appium_shadowed'
    $sh = Invoke-Setup $shadow
    Report 'appium install failure and a post-install version mismatch both fail closed' (
        $nf.ExitCode -ne 0 -and $nf.Text -match "npm install -g appium@$([regex]::Escape($appiumPin)) failed" -and
        $sh.ExitCode -ne 0 -and $sh.Text -match "reports '2\.19\.0', not $([regex]::Escape($appiumPin))"
    ) "npm=$($nf.ExitCode) shadow=$($sh.ExitCode) out=$($sh.Text)"

    # ---------------------------------------------------- doctor is unambiguous
    function Invoke-Doctor([string]$Mode, [hashtable]$Env = @{}) {
        $c = New-Case "doctor-$Mode"
        Set-State $c 'appium_version' $appiumPin
        Set-State $c 'doctor_mode' $Mode
        $r = Invoke-Setup $c -Env $Env
        [pscustomobject]@{ Case = $c; Run = $r }
    }
    $required = Invoke-Doctor 'required'
    Report 'doctor required fixes are reported with the count and the doctor output, and stop setup' (
        $required.Run.ExitCode -ne 0 -and $required.Run.Text -match 'FATAL: driver doctor reported 12 required fix' -and
        $required.Run.Text -match 'xcrun is not usable' -and -not (Get-State $required.Case 'builds')
    ) "exit=$($required.Run.ExitCode) out=$($required.Run.Text)"
    $crash = Invoke-Doctor 'crash'
    Report 'a doctor that crashes is reported as a doctor error, not as required fixes or health' (
        $crash.Run.ExitCode -ne 0 -and $crash.Run.Text -match 'failed to run \(exit 1\)' -and
        $crash.Run.Text -match 'not a clean bill of health' -and $crash.Run.Text -match 'TypeError'
    ) "exit=$($crash.Run.ExitCode) out=$($crash.Run.Text)"
    $noChecks = Invoke-Doctor 'nochecks'
    $lying = Invoke-Doctor 'lying'
    Report 'exit 0 without running checks, or with a nonzero required count, is not health' (
        $noChecks.Run.ExitCode -ne 0 -and $noChecks.Run.Text -match 'did not run its checks' -and
        $lying.Run.ExitCode -ne 0 -and $lying.Run.Text -match 'exited 0 but reported 1 required fix'
    ) "nochecks=$($noChecks.Run.ExitCode) lying=$($lying.Run.ExitCode) out=$($lying.Run.Text)"
    $optional = Invoke-Doctor 'optional'
    Report 'optional-only doctor findings pass' ($optional.Run.ExitCode -eq 0 -and $optional.Run.Text -match 'doctor: 0 required fixes') "exit=$($optional.Run.ExitCode) out=$($optional.Run.Text)"

    $hang = Invoke-Doctor 'hang' @{ DOCTOR_TIMEOUT = '2' }
    Report 'a doctor timeout names owners read-only and kills or shuts down nothing it did not start' (
        $hang.Run.ExitCode -ne 0 -and $hang.Run.Text -match 'timed out; this is not a required-fix report' -and
        $hang.Run.Text -match 'pid=4242 ppid=4200 parent=node /Users/other' -and
        $hang.Run.Text -match 'cleanup-wda-guest\.sh <simulator-udid>' -and
        -not (Get-State $hang.Case 'violations')
    ) "exit=$($hang.Run.ExitCode) violations=$(Get-State $hang.Case 'violations') out=$($hang.Run.Text)"

    $hangNoPs = Invoke-Doctor 'hang' @{ DOCTOR_TIMEOUT = '2'; STUB_PS_FAIL = '1' }
    Report 'a failing process listing cannot swallow the doctor-timeout reason' (
        $hangNoPs.Run.ExitCode -ne 0 -and $hangNoPs.Run.Text -match '\(process listing unavailable\)' -and
        $hangNoPs.Run.Text -match 'FATAL: driver doctor did not finish within 2s'
    ) "exit=$($hangNoPs.Run.ExitCode) out=$($hangNoPs.Run.Text)"

    # ------------------------------------------------------------- Xcode facts
    $oldXcode = Invoke-Setup (New-Case 'xcode-older') -Env @{ STUB_XCODE = '26.5' }
    Report 'an Xcode below the x86_64 ceiling is reported, not fatal' (
        $oldXcode.ExitCode -eq 0 -and $oldXcode.Text -match "NOTE: guest runs Xcode 26\.5; the newest Xcode this .+ guest can run is $([regex]::Escape($xcodeCeiling))"
    ) "exit=$($oldXcode.ExitCode) out=$($oldXcode.Text)"
    $noRuntimeCase = New-Case 'no-runtime'
    Set-State $noRuntimeCase 'no_runtime'
    $noRuntime = Invoke-Setup $noRuntimeCase
    Report 'a missing iOS runtime fails before any install' (
        $noRuntime.ExitCode -ne 0 -and $noRuntime.Text -match 'no iOS simulator runtime installed' -and -not (Get-State $noRuntimeCase 'calls.log')
    ) "exit=$($noRuntime.ExitCode) out=$($noRuntime.Text)"

    # ---------------------------------------------------------- static guards
    $text = Get-Content -LiteralPath $setupScript -Raw -Encoding UTF8
    $code = @($text -split "`n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*"' }) -join "`n"
    # Every `kill -<signal>` must target the script's own doctor child or that
    # child's direct children; a kill of any other pid is a regression.
    $killLines = @($code -split "`n" | Where-Object { $_ -match '\bkill\s+-' })
    $foreignKills = @($killLines | Where-Object { $_ -notmatch 'kill\s+-[0-9A-Z]+\s+"\$(doctor_pid|doctor_child)"' })
    Report 'setup script has no swallowed install, update fallback, or generic process kill' (
        $code -notmatch 'driver update' -and $code -notmatch 'install[^\n]*\|\|\s*true' -and
        $code -notmatch '\bpkill\b|\bkillall\b' -and $code -notmatch 'simctl shutdown' -and
        $killLines.Count -ge 3 -and $foreignKills.Count -eq 0 -and
        $code -notmatch 'wait "\$doctor_pid"; doctor_rc=\$\?'
    ) "kill lines=$($killLines.Count) foreign=$($foreignKills -join ' | ')"
    $probe = $code + "`n  kill -9 `"`$wda_pid`" 2>/dev/null || true"
    $probeForeign = @($probe -split "`n" | Where-Object { $_ -match '\bkill\s+-' -and $_ -notmatch 'kill\s+-[0-9A-Z]+\s+"\$(doctor_pid|doctor_child)"' })
    Report 'the foreign-kill guard itself detects a kill of another pid' ($probeForeign.Count -eq 1) "probe=$($probeForeign -join ' | ')"
    $registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mobile-development.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Report 'registry records the x86_64 Xcode ceiling with its primary source, and guest sync ships it' (
        $registry.expectations.xcode.guestArchitecture -eq 'x86_64' -and
        $registry.expectations.xcode.maxCompatibleVersion -match '^26\.' -and
        $registry.expectations.xcode.source -like 'https://developer.apple.com/*xcode-27-release-notes*' -and
        (Get-Content -LiteralPath $syncScript -Raw -Encoding UTF8) -match 'XCODE_MAX_COMPATIBLE=.+expectations\.xcode\.maxCompatibleVersion'
    ) "xcode=$($registry.expectations.xcode | ConvertTo-Json -Compress)"
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) {
    Write-Host "`nRESULT: $($reported - $failures.Count) passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
