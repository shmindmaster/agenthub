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
  * the guest address is *proposed* by four independent sources and *believed*
    only once SSH reaches it, because VMware NAT assigns it by DHCP and the
    guest-tools channel that used to be the single source has been measured
    answering wrong while the guest was perfectly healthy

Waits are generous on purpose. This guest renders in software and is slow
enough that a short timeout reports a false failure.

.PARAMETER Avd
Android virtual device to boot. Must match the canonical registry expectation.

.PARAMETER SkipAndroid
Bring up iOS only; do not inspect or start Android resources.

.PARAMETER SkipIos
Bring up Android only; do not start the macOS guest.

.PARAMETER TimeoutMinutes
Overall budget for each wait phase. Default 15.
#>
[CmdletBinding()]
param(
    [string]$Avd,
    [switch]$SkipAndroid,
    [switch]$SkipIos,
    [switch]$Json,
    [int]$TimeoutMinutes = 15
)

$ErrorActionPreference = 'Stop'

# Shared guest-address resolution. Kept in a module because Start- and Test-
# both need identical semantics; two copies of this logic is how the lab ends up
# with two different answers to 'where is the guest'.
Import-Module (Join-Path $PSScriptRoot 'MobileLabGuest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\..\..\MobileDevelopment.psm1') -Force
$contract = Get-MobileDevelopmentContract
$androidExpectation = $contract.expectations.android
$iosExpectation = $contract.expectations.ios
$guestAppiumExpectation = $contract.expectations.guestAppium
if ($SkipAndroid -and $SkipIos) { throw 'SkipAndroid and SkipIos cannot both be set.' }

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

function Get-CanonicalEmulatorIds {
    param([Parameter(Mandatory)][string]$AdbPath)
    $devicePattern = [string]$androidExpectation.virtualDeviceIdPattern
    $ids = @(& $AdbPath devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -match $devicePattern })
    @($ids | Where-Object {
            $sdk = [string]((& $AdbPath -s $_ shell getprop ro.build.version.sdk 2>$null) | Select-Object -First 1)
            $avd = [string]((& $AdbPath -s $_ emu avd name 2>$null) | Select-Object -First 1)
            $sdk.Trim() -eq [string]$androidExpectation.apiLevel -and $avd.Trim() -eq [string]$androidExpectation.avdName
        })
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

if (-not $SkipAndroid) {
    $androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (-not $androidHome) { throw "ANDROID_HOME is not set; cannot locate the Android SDK." }
    $adb = Join-Path $androidHome 'platform-tools\adb.exe'
    $emulatorExe = Join-Path $androidHome 'emulator\emulator.exe'
    foreach ($required in @($adb, $emulatorExe)) {
        if (-not (Test-Path $required)) { throw "Missing required Android tool: $required" }
    }
    $expectedApi = [string]$androidExpectation.apiLevel
    $expectedAvd = [string]$androidExpectation.avdName
    if ($Avd -and $Avd -ne $expectedAvd) { throw "AVD '$Avd' conflicts with registry/mobile-development.json expectation '$expectedAvd'." }
    $Avd = $expectedAvd

    Say 'Android:'
    $attached = @(Get-CanonicalEmulatorIds -AdbPath $adb)
    if ($attached.Count -gt 0) {
        Say ("  API $expectedApi already attached: {0}" -f ($attached -join ', ')) 'Green'
    }
    else {
        $avds = @(& $emulatorExe -list-avds | Where-Object { $_ -and $_.Trim() })
        if ($avds -notcontains $Avd) { throw "Canonical AVD '$Avd' not found. Available: $($avds -join ', ')" }
        Say "  booting canonical AVD '$Avd'"
        Start-Process -FilePath $emulatorExe -ArgumentList @('-avd', $Avd) -WindowStyle Minimized | Out-Null
        if (-not (Wait-Until -What "emulator '$Avd'" -TimeoutSec $timeoutSec -Condition {
                    @(Get-CanonicalEmulatorIds -AdbPath $adb).Count -gt 0
                })) { throw "Android emulator failed to attach as API $expectedApi. Verify the canonical AVD's system image." }
        $startedAndroidId = [string](@(Get-CanonicalEmulatorIds -AdbPath $adb | Select-Object -First 1))
        if (-not (Wait-Until -What 'android boot completed' -TimeoutSec $timeoutSec -Condition {
                    (& $adb -s $startedAndroidId shell getprop sys.boot_completed 2>$null) -match '1'
                })) { throw "Android did not finish booting." }
    }
    $androidId = @(Get-CanonicalEmulatorIds -AdbPath $adb | Select-Object -First 1)
    $script:Facts.androidDeviceId = if ($androidId.Count) { $androidId[0] } else { $null }
    if (-not $script:Facts.androidDeviceId) { throw "Android emulator enumeration returned no API $expectedApi virtual device ID." }
    Add-Stage 'android' ([bool]$script:Facts.androidDeviceId) "device=$($script:Facts.androidDeviceId); avd=$Avd; api=$expectedApi" "Start canonical AVD '$Avd' and rerun."
}

if ($SkipIos) {
    Write-Host ''
    Say 'ANDROID READY (iOS skipped by -SkipIos)' 'Green'
    Emit-Result -Ready $true
    exit 0
}

# ---------------------------------------------------------------------- iOS

$vmwareResource = Get-MobileDevelopmentResource -Id 'vmware-workstation'
$vmrun = @($vmwareResource.discovery.vmrunPaths | ForEach-Object { ([string]$_) -replace '/', '\' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if ($vmrun.Count) { $vmrun = [string]$vmrun[0] } else { $vmrun = $null }
if (-not (Test-Path $vmrun)) { throw "vmrun not found. Install VMware Workstation, or pass -SkipIos." }

Say 'macOS guest:'
$Vmx = (Get-MobileVmxFacts).path
if (-not (Test-Path -LiteralPath $Vmx -PathType Leaf)) { throw "Canonical VMX authority is missing: $Vmx" }
Say "  vmx: $Vmx"

# This macOS guest does not run nested VMs. Workstation cannot expose AMD-V/RVI
# to it while the Windows Hyper-V profile is active, and an accidental TRUE
# makes vmrun abort before macOS starts. Enforce the documented lab invariant.
$vmxText = [IO.File]::ReadAllText($Vmx)
if ($vmxText -match '(?m)^vhv\.enable\s*=\s*"TRUE"') {
    throw "Canonical VMX has vhv.enable=TRUE. Nested virtualization is out of scope; stop and obtain owner approval before changing the VM configuration."
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

# One resolution step, not two. `getGuestIPAddress` used to answer this alone
# and then SSH separately confirmed its answer -- which meant a wrong answer
# from VMware Tools failed the run outright, with no second candidate to try.
# Resolve-MobileLabGuestAddress proposes from four sources and believes only
# what SSH reaches, so "the address moved" and "VMware Tools is broken" both
# recover instead of stopping the lab. See MobileLabGuest.psm1.
$guest = Resolve-MobileLabGuestAddress -Vmx $Vmx -VmrunPath $vmrun -SshHost 'macvm' -TimeoutSeconds $timeoutSec
$script:guestIp = $guest.address
Say "  guest at $script:guestIp (via $($guest.source), $($guest.elapsedSeconds)s)"
$script:Facts.guestIp = $script:guestIp
$script:Facts.guestAddressSource = $guest.source
Add-Stage 'macos-guest' $true "vmx=$Vmx; ip=$script:guestIp; source=$($guest.source)"
# SSH is not re-tested here: the resolver returns only an address it has
# already connected to, so a separate probe would restate a settled fact.
Add-Stage 'guest-ssh' $true "macvm via $script:guestIp (proven during address resolution)"

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
$appiumUrl = "http://$($script:guestIp):$($guestAppiumExpectation.port)"
$script:Facts.guestAppiumUrl = $appiumUrl
if (-not (Wait-Until -What "appium at $appiumUrl" -TimeoutSec $timeoutSec -Condition {
            try { [bool](Invoke-RestMethod -Uri "$appiumUrl$($guestAppiumExpectation.statusPath)" -TimeoutSec 10).value.ready } catch { $false }
        })) {
    Say '  Appium did not answer. Is the launchd agent installed?' 'Yellow'
    Say "    ssh macvm 'bash ~/mobile-lab/start-appium-guest.sh'" 'Cyan'
    throw "Guest Appium did not become ready at $appiumUrl. Remediation: ssh -o HostName=$script:guestIp -o HostKeyAlias=macvm macvm 'bash ~/mobile-lab/start-appium-guest.sh'."
}
Add-Stage 'guest-appium' $true $appiumUrl

# Resolve the exact configured device from the runtime-keyed JSON inventory.
$availableJson = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices available -j' 2>&1) -join "`n")
try { $availableDevices = $availableJson | ConvertFrom-Json }
catch { throw "Could not parse simctl device inventory JSON: $($_.Exception.Message)" }
$targetSimulator = $null
foreach ($runtimeProperty in @($availableDevices.devices.PSObject.Properties)) {
    if ($runtimeProperty.Name -notmatch ([regex]::Escape([string]$iosExpectation.runtimeKeySuffix) + '$')) { continue }
    $matches = @($runtimeProperty.Value | Where-Object name -eq ([string]$iosExpectation.deviceName))
    if ($matches.Count -ne 1) { throw "Expected exactly one $($iosExpectation.deviceName) under iOS $($iosExpectation.platformVersion), found $($matches.Count)." }
    $targetSimulator = $matches[0]
    break
}
if (-not $targetSimulator -or -not $targetSimulator.udid) { throw "Could not resolve the $($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator UDID." }
$targetSimulatorUdid = [string]$targetSimulator.udid
$script:Facts.iosDevice = [string]$iosExpectation.deviceName
$script:Facts.iosDeviceId = $targetSimulatorUdid
$script:Facts.iosRuntime = "iOS $($iosExpectation.platformVersion)"
$script:lastSimulatorBootEvidence = ''
if ($targetSimulator.state -ne 'Booted') {
    Say "  exact $($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator is shutdown; booting it"
    if (-not (Wait-Until -What "$($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator boot" -TimeoutSec $timeoutSec -Condition {
                $currentState = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices booted' 2>&1) -join "`n")
                if ($currentState -match [regex]::Escape($targetSimulatorUdid)) { return $true }
                $script:lastSimulatorBootEvidence = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm "xcrun simctl boot $targetSimulatorUdid 2>&1 || true") -join ' ')
                return $false
            })) { throw "$($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator did not boot. Last boot response: $script:lastSimulatorBootEvidence" }
}
$bootedText = [string](@(& ssh -o "HostName=$script:guestIp" -o "HostKeyAlias=macvm" -o "LogLevel=ERROR" -o BatchMode=yes macvm 'xcrun simctl list devices booted' 2>&1) -join "`n")
if ($bootedText -notmatch [regex]::Escape($targetSimulatorUdid)) { throw "Exact Simulator $targetSimulatorUdid is not booted." }
Say ("  exact simulator ready: {0} ({1}) / iOS {2}" -f $iosExpectation.deviceName, $targetSimulatorUdid, $iosExpectation.platformVersion) 'Green'
Add-Stage 'ios-simulator' $true "$($iosExpectation.deviceName) ($targetSimulatorUdid) (Booted); runtime=iOS $($iosExpectation.platformVersion)" "Boot the exact $($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator."

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
