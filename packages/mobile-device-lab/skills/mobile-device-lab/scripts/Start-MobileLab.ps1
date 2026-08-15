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
Overall budget for each wait phase. Default 15.
#>
[CmdletBinding()]
param(
    [string]$Avd,
    [string]$Vmx,
    [switch]$SkipIos,
    [switch]$Json,
    [int]$TimeoutMinutes = 15
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

$script:Stages = [System.Collections.Generic.List[object]]::new()
$script:Facts = [ordered]@{}
function Add-Stage {
    param([string]$Name, [bool]$Ready, [string]$Evidence, [string]$Remedy = '')
    $script:Stages.Add([pscustomobject]@{ stage = $Name; ready = $Ready; evidence = $Evidence; remedy = $Remedy })
}
function Emit-Result {
    param([bool]$Ready, [string]$FailedStage = '', [string]$ErrorMessage = '', [string]$Remedy = '')
    if (-not $Json) { return }
    $payload = [ordered]@{
        ready = $Ready
        androidDeviceId = $script:Facts.androidDeviceId
        iosDevice = $script:Facts.iosDevice
        iosDeviceId = $script:Facts.iosDeviceId
        iosRuntime = $script:Facts.iosRuntime
        guestAppiumUrl = $script:Facts.guestAppiumUrl
        guestIp = $script:Facts.guestIp
        failedStage = $FailedStage
        error = $ErrorMessage
        remediation = $Remedy
        stages = $script:Stages
    }
    Write-Output ($payload | ConvertTo-Json -Depth 7 -Compress)
}

$timeoutSec = $TimeoutMinutes * 60
try {
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
$attached = @(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' })
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
                @(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' }).Count -gt 0
            })) { throw "Android emulator failed to attach." }
    $startedAndroidId = [string](@(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1))
    # `adb devices` reports the device before Android has finished booting.
    if (-not (Wait-Until -What 'android boot completed' -TimeoutSec $timeoutSec -Condition {
                (& $adb -s $startedAndroidId shell getprop sys.boot_completed 2>$null) -match '1'
            })) { throw "Android did not finish booting." }
}
$androidId = @(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1)
$script:Facts.androidDeviceId = if ($androidId.Count) { $androidId[0] } else { $null }
Add-Stage 'android' ([bool]$script:Facts.androidDeviceId) "device=$($script:Facts.androidDeviceId)" 'Start an API 36 AVD and rerun.'

if ($SkipIos) {
    Write-Host ''
    Say 'ANDROID READY (iOS skipped by -SkipIos)' 'Green'
    Emit-Result -Ready $true
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

# This macOS guest does not run nested VMs. Workstation cannot expose AMD-V/RVI
# to it while the Windows Hyper-V profile is active, and an accidental TRUE
# makes vmrun abort before macOS starts. Enforce the documented lab invariant.
$vmxText = [IO.File]::ReadAllText($Vmx)
if ($vmxText -match '(?m)^vhv\.enable\s*=\s*"TRUE"') {
    $backup = "$Vmx.pre-mobile-lab-vhv-disable"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $Vmx -Destination $backup }
    $vmxText = $vmxText -replace '(?m)^vhv\.enable\s*=\s*"TRUE"', 'vhv.enable = "FALSE"'
    [IO.File]::WriteAllText($Vmx, $vmxText, [Text.UTF8Encoding]::new($false))
    Say '  repaired vhv.enable=FALSE for Hyper-V compatibility' 'Yellow'
}

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
            # Never pass vmrun -wait here: it can block forever inside this
            # bounded loop and make TimeoutMinutes decorative.
            $candidate = (& $vmrun getGuestIPAddress $Vmx) 2>&1 | Select-Object -First 1
            if ($candidate -match '^\d+\.\d+\.\d+\.\d+$') { $script:guestIp = $candidate; $true } else { $false }
        })) { throw "VMware Tools did not report a guest IP." }
Say "  guest at $script:guestIp"
$script:Facts.guestIp = $script:guestIp
Add-Stage 'macos-guest' $true "vmx=$Vmx; ip=$script:guestIp"

if (-not (Wait-Until -What 'ssh to guest' -TimeoutSec $timeoutSec -Condition {
            $null = & ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o ConnectTimeout=8 -o BatchMode=yes macvm 'true' 2>&1
            $LASTEXITCODE -eq 0
        })) { throw "SSH failed at the dynamically discovered guest address $script:guestIp." }
Add-Stage 'guest-ssh' $true "macvm via $script:guestIp"

$guestSync = Join-Path $PSScriptRoot 'Sync-MobileLabGuestScripts.ps1'
$syncOutput = @(& $guestSync -GuestIp $script:guestIp -Json 2>&1)
$syncExit = $LASTEXITCODE
$syncLine = $syncOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
$syncResult = $null
if ($syncLine) { try { $syncResult = $syncLine | ConvertFrom-Json } catch { } }
if ($syncExit -ne 0 -or -not $syncResult -or -not $syncResult.ok) {
    throw "Guest helper sync failed: $(($syncOutput | Select-Object -Last 4) -join ' ')"
}
Add-Stage 'guest-helper-sync' $true "changed=$($syncResult.changed); appiumRestarted=$($syncResult.appiumRestarted)"

# Appium runs as a launchd agent (RunAtLoad), so it comes back with the guest.
# Cold start is minutes here, hence the generous budget.
$appiumUrl = "http://$($script:guestIp):4723"
$script:Facts.guestAppiumUrl = $appiumUrl
if (-not (Wait-Until -What "appium at $appiumUrl" -TimeoutSec $timeoutSec -Condition {
            try { [bool](Invoke-RestMethod -Uri "$appiumUrl/status" -TimeoutSec 10).value.ready } catch { $false }
        })) {
    Say '  Appium did not answer. Is the launchd agent installed?' 'Yellow'
    Say "    ssh macvm 'bash ~/mobile-lab/start-appium-guest.sh'" 'Cyan'
    throw "Guest Appium did not become ready at $appiumUrl. Remediation: ssh -o HostName=$script:guestIp -o HostKeyAlias=macvm macvm 'bash ~/mobile-lab/start-appium-guest.sh'."
}
Add-Stage 'guest-appium' $true $appiumUrl

# A booted simulator is what iOS sessions attach to. Booting is slow, so do it
# here rather than making the first session pay for it.
$booted = @(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices booted | grep Booted | head -1' 2>&1)
$bootedText = [string]($booted | Where-Object { $_ -match 'Booted' } | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($bootedText)) {
    Say '  no simulator booted; booting iPhone 17'
    $availableJson = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices available -j' 2>&1) -join "`n")
    try { $availableDevices = $availableJson | ConvertFrom-Json }
    catch { throw "Could not parse simctl device inventory JSON: $($_.Exception.Message)" }
    $flatDevices = @(
        foreach ($runtimeProperty in @($availableDevices.devices.PSObject.Properties)) {
            @($runtimeProperty.Value)
        }
    )
    $targetSimulator = @($flatDevices | Where-Object { $_.name -eq 'iPhone 17' } | Select-Object -First 1)
    if ($targetSimulator.Count -ne 1 -or -not $targetSimulator[0].udid) { throw 'Could not resolve exactly one available iPhone 17 Simulator UDID.' }
    $targetSimulatorUdid = [string]$targetSimulator[0].udid
    $script:Facts.iosDeviceId = $targetSimulatorUdid
    $script:lastSimulatorBootEvidence = ''
    if (-not (Wait-Until -What 'simulator boot' -TimeoutSec $timeoutSec -Condition {
                $currentState = @(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices booted' 2>&1)
                if ($currentState -match 'Booted') { return $true }
                # CoreSimulator can reject the first boot request immediately
                # after a cold guest boot. Keep the request inside the same
                # bounded loop, and route remote stderr to stdout so Windows
                # PowerShell 5.1 does not promote it to a terminating record.
                $script:lastSimulatorBootEvidence = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm "xcrun simctl boot $targetSimulatorUdid 2>&1 || true") -join ' ')
                return $false
            })) { throw "iPhone 17 Simulator did not boot. Last boot response: $script:lastSimulatorBootEvidence" }
    $booted = @(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices booted | grep Booted | head -1' 2>&1)
    $bootedText = [string]($booted | Where-Object { $_ -match 'Booted' } | Select-Object -First 1)
}
else {
    Say ("  simulator already booted: {0}" -f $bootedText.Trim()) 'Green'
}
if ([string]::IsNullOrWhiteSpace($bootedText)) { throw 'Simulator boot reported success without an enumerated Booted device.' }
$script:Facts.iosDevice = if ($bootedText -match '^\s*([^\(]+)') { $Matches[1].Trim() } else { 'iPhone 17' }
$script:Facts.iosDeviceId = if ($bootedText -match '\(([0-9A-Fa-f-]{36})\)\s+\(Booted\)') { $Matches[1] } else { $null }
if (-not $script:Facts.iosDeviceId) { throw "Could not resolve a Simulator UDID from: $bootedText" }
$runtimeLine = & ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list runtimes | grep iOS | head -1' 2>&1
$runtimeText = [string]($runtimeLine | Where-Object { $_ -match 'iOS\s+26\.5' } | Select-Object -First 1)
$script:Facts.iosRuntime = if ($runtimeText -match 'iOS\s+([0-9.]+)') { "iOS $($Matches[1])" } else { $runtimeText }
Add-Stage 'ios-simulator' ($bootedText -match 'Booted') $bootedText 'Boot iPhone 17 in the macOS guest.'

Write-Host ''
Say 'MOBILE LAB READY' 'Green'
Say ("  remote : {0}   <- remoteServerUrl for iOS sessions" -f $appiumUrl)
Say '  verify : Test-MobileLab.ps1'
Write-Host ''
Emit-Result -Ready $true
exit 0
}
catch {
    $message = $_.Exception.Message
    $stage = if ($script:Stages.Count) { $script:Stages[$script:Stages.Count - 1].stage } else { 'startup' }
    $remedy = if ($message -match 'Remediation:\s*(.+)$') { $Matches[1] } else { 'Run Test-MobileLab.ps1 -Json to identify the first broken layer, apply its remediation, and rerun startup.' }
    Add-Stage $stage $false $message $remedy
    Say "MOBILE LAB START FAILED: $message" 'Red'
    Emit-Result -Ready $false -FailedStage $stage -ErrorMessage $message -Remedy $remedy
    exit 1
}
