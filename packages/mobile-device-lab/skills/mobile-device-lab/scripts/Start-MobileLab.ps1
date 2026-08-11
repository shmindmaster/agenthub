#Requires -Version 5.1
<#
.SYNOPSIS
Bring the mobile device lab up from cold. Idempotent -- safe to run when parts
are already running.

.DESCRIPTION
A host reboot takes the whole Windows half of the lab down: the macOS guest and
the Android emulator both stop, and nothing restarts them. (Appium inside the
guest does come back on its own -- it runs as a launchd agent with RunAtLoad --
but only once the guest is booted.) This script closes that gap so the lab does
not need a human after every reboot.

Nothing here is discovered by guessing a path:
  * the .vmx comes from VMware's own inventory, so a moved VM still resolves
  * the guest IP comes from `vmrun getGuestIPAddress`, because VMware NAT
    assigns it by DHCP and a hardcoded address goes stale silently

Waits are generous on purpose. This guest renders in software and is slow
enough that a short timeout reports a false failure.

.PARAMETER Avd
Android virtual device to boot. Defaults to the first one listed.

.PARAMETER SkipIos
Bring up Android only; do not start the macOS guest.

.PARAMETER TimeoutMinutes
Overall budget for each wait phase. Default 10.
#>
[CmdletBinding()]
param(
    [string]$Avd,
    [string]$Vmx,
    [switch]$SkipIos,
    [int]$TimeoutMinutes = 10
)

$ErrorActionPreference = 'Stop'

function Say {
    param([string]$Message, [string]$Colour = 'Gray')
    Write-Host $Message -ForegroundColor $Colour
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$What,
        [int]$TimeoutSec = 600,
        [int]$PollSec = 10
    )
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        $ok = $false
        try { $ok = [bool](& $Condition) } catch { $ok = $false }
        if ($ok) {
            Say ("  ready: {0} ({1}s)" -f $What, [int]((Get-Date) - $start).TotalSeconds) 'Green'
            return $true
        }
        Start-Sleep -Seconds $PollSec
    }
    Say ("  TIMEOUT waiting for {0} after {1}s" -f $What, $TimeoutSec) 'Red'
    return $false
}

$timeoutSec = $TimeoutMinutes * 60
Write-Host ''
Say '=== Starting mobile device lab ===' 'White'

# ------------------------------------------------------------------ Android

$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
if (-not $androidHome) { throw "ANDROID_HOME is not set; cannot locate the Android SDK." }
$adb = Join-Path $androidHome 'platform-tools\adb.exe'
$emulatorExe = Join-Path $androidHome 'emulator\emulator.exe'
foreach ($required in @($adb, $emulatorExe)) {
    if (-not (Test-Path $required)) { throw "Missing required Android tool: $required" }
}

Say 'Android:'
$attached = @(& $adb devices | Where-Object { $_ -match '\sdevice$' })
if ($attached.Count -gt 0) {
    Say ("  already attached: {0}" -f (($attached | ForEach-Object { ($_ -split '\s+')[0] }) -join ', ')) 'Green'
}
else {
    $avds = @(& $emulatorExe -list-avds | Where-Object { $_ -and $_.Trim() })
    if ($avds.Count -eq 0) { throw "No Android virtual devices exist. Create one in Android Studio first." }
    if (-not $Avd) { $Avd = $avds[0] }
    if ($avds -notcontains $Avd) { throw "AVD '$Avd' not found. Available: $($avds -join ', ')" }
    Say "  booting AVD '$Avd' (available: $($avds -join ', '))"
    Start-Process -FilePath $emulatorExe -ArgumentList @('-avd', $Avd) -WindowStyle Minimized | Out-Null
    if (-not (Wait-Until -What "emulator '$Avd'" -TimeoutSec $timeoutSec -Condition {
                @(& $adb devices | Where-Object { $_ -match '\sdevice$' }).Count -gt 0
            })) { exit 1 }
    # `adb devices` reports the device before Android has finished booting.
    if (-not (Wait-Until -What 'android boot completed' -TimeoutSec $timeoutSec -Condition {
                (& $adb shell getprop sys.boot_completed 2>$null) -match '1'
            })) { exit 1 }
}

if ($SkipIos) {
    Write-Host ''
    Say 'ANDROID READY (iOS skipped by -SkipIos)' 'Green'
    exit 0
}

# ---------------------------------------------------------------------- iOS

$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
if (-not (Test-Path $vmrun)) { $vmrun = 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe' }
if (-not (Test-Path $vmrun)) { throw "vmrun not found. Install VMware Workstation, or pass -SkipIos." }

Say 'macOS guest:'
if (-not $Vmx) {
    # VMware's own inventory, so a moved or renamed VM still resolves. Explicit
    # UTF-8: a BOM-less file decodes differently in 5.1 and 7.
    $inventory = Join-Path $env:APPDATA 'VMware\inventory.vmls'
    if (Test-Path $inventory) {
        $Vmx = Get-Content $inventory -Encoding UTF8 -ErrorAction SilentlyContinue |
            Select-String -Pattern '^\s*vmlist\d+\.config\s*=\s*"(.+\.vmx)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
    }
}
if (-not $Vmx) { throw "Could not resolve a .vmx from VMware's inventory. Pass -Vmx explicitly." }
Say "  vmx: $Vmx"

$running = @(& $vmrun list)
if ($running -contains $Vmx) {
    Say '  already running' 'Green'
}
else {
    Say '  starting (headless)'
    & $vmrun -T ws start $Vmx nogui | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "vmrun start failed with exit $LASTEXITCODE" }
}

$guestIp = $null
if (-not (Wait-Until -What 'guest IP' -TimeoutSec $timeoutSec -Condition {
            $candidate = (& $vmrun getGuestIPAddress $Vmx -wait) 2>&1 | Select-Object -First 1
            if ($candidate -match '^\d+\.\d+\.\d+\.\d+$') { $script:guestIp = $candidate; $true } else { $false }
        })) { exit 1 }
Say "  guest at $script:guestIp"

if (-not (Wait-Until -What 'ssh to guest' -TimeoutSec $timeoutSec -Condition {
            $null = & ssh -o ConnectTimeout=8 -o BatchMode=yes macvm 'true' 2>&1
            $LASTEXITCODE -eq 0
        })) { exit 1 }

# Appium runs as a launchd agent (RunAtLoad), so it comes back with the guest.
# Cold start is minutes here, hence the generous budget.
$appiumUrl = "http://$($script:guestIp):4723"
if (-not (Wait-Until -What "appium at $appiumUrl" -TimeoutSec $timeoutSec -Condition {
            try { [bool](Invoke-RestMethod -Uri "$appiumUrl/status" -TimeoutSec 10).value.ready } catch { $false }
        })) {
    Say '  Appium did not answer. Is the launchd agent installed?' 'Yellow'
    Say "    ssh macvm 'bash ~/mobile-lab/start-appium-guest.sh'" 'Cyan'
    exit 1
}

# A booted simulator is what iOS sessions attach to. Booting is slow, so do it
# here rather than making the first session pay for it.
$booted = & ssh -o BatchMode=yes macvm 'xcrun simctl list devices booted | grep Booted | head -1' 2>&1
if ($booted -notmatch 'Booted') {
    Say '  no simulator booted; booting iPhone 17'
    & ssh -o BatchMode=yes macvm 'xcrun simctl boot "iPhone 17" 2>/dev/null || true' | Out-Null
    if (-not (Wait-Until -What 'simulator boot' -TimeoutSec $timeoutSec -Condition {
                (& ssh -o BatchMode=yes macvm 'xcrun simctl list devices booted' 2>&1) -match 'Booted'
            })) { exit 1 }
}
else {
    Say ("  simulator already booted: {0}" -f $booted.Trim()) 'Green'
}

Write-Host ''
Say 'MOBILE LAB READY' 'Green'
Say ("  remote : {0}   <- remoteServerUrl for iOS sessions" -f $appiumUrl)
Say '  verify : Test-MobileLab.ps1'
Write-Host ''
exit 0
