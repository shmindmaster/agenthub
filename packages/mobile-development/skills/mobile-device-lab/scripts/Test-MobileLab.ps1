#Requires -Version 5.1
<#
.SYNOPSIS
Stage gate for the mobile device lab. Reports PASS/FAIL per layer, stops at the
first broken one, and exits non-zero.

.DESCRIPTION
The point of this script is to name the ONE layer that is broken, so nobody
debugs several at once. Layers are checked in dependency order and the run
stops at the first failure.

Two rules this file exists to enforce, both learned here the hard way:

  1. A pipeline's exit code is the LAST command's. `xcodebuild ... | tail` once
     reported PASS on a failed build. Every remote check below inspects the
     real command's status, never a pipeline tail.
  2. This guest renders in software and is slow. A short timeout reports a
     false hang. Timeouts here are deliberately generous and the toolchain is
     warmed before anything is timed.

.PARAMETER SkipIos
Check only the Android half. Does not wake or require the macOS VM.

.PARAMETER SkipAndroid
Check only the iOS half. Does not inspect or invoke adb.

.PARAMETER RequireRunningProcesses
Fail before any tool or network probe unless the registry-backed canonical
runtime processes are already present. This mode never starts a resource.

.PARAMETER Json
Emit a machine-readable result object as the final line, for agent use.

.PARAMETER Deep
Build and install the local synthetic fixture, initialize the Appium MCP pin
resolved from registry/mcps.json,
verify its catalog, exercise concurrent Android/iOS sessions, and capture
screenshots and page-source evidence.
#>
[CmdletBinding()]
param(
    [switch]$SkipAndroid,
    [switch]$SkipIos,
    [switch]$RequireRunningProcesses,
    [switch]$Deep,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ($SkipAndroid -and $SkipIos) { throw 'SkipAndroid and SkipIos cannot both be set.' }
if ($Deep -and ($SkipAndroid -or $SkipIos)) { throw 'Deep validation requires both platforms.' }

# Shared guest-address resolution. Kept in a module because Start- and Test-
# both need identical semantics; two copies of this logic is how the lab ends up
# with two different answers to 'where is the guest'.
Import-Module (Join-Path $PSScriptRoot 'MobileLabGuest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\..\..\MobileDevelopment.psm1') -Force
$contract = Get-MobileDevelopmentContract
$androidExpectation = $contract.expectations.android
$iosExpectation = $contract.expectations.ios
$guestAppiumExpectation = $contract.expectations.guestAppium
$xcuitestExpectation = $contract.expectations.xcuitest
$appiumMcp = Get-AppiumMcpAuthority

$script:Results = [System.Collections.Generic.List[object]]::new()
$script:Facts = [ordered]@{}

function Write-Stage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Evidence,
        [string]$Remedy
    )
    $script:Results.Add([pscustomobject]@{
            Stage    = $Name
            Passed   = $Passed
            Evidence = $Evidence
            Remedy   = $Remedy
        })
    if ($Passed) {
        Write-Host ("PASS  {0}" -f $Name) -ForegroundColor Green
        if ($Evidence) { Write-Host ("      {0}" -f $Evidence) -ForegroundColor DarkGray }
    }
    else {
        Write-Host ("FAIL  {0}" -f $Name) -ForegroundColor Red
        if ($Evidence) { Write-Host ("      {0}" -f $Evidence) -ForegroundColor Yellow }
        if ($Remedy) { Write-Host ("      fix: {0}" -f $Remedy) -ForegroundColor Cyan }
    }
}

function Stop-Gate {
    param([string]$Layer)
    Write-Host ''
    Write-Host ("STOPPED at: {0}" -f $Layer) -ForegroundColor Red
    Write-Host 'Fix this layer before checking the ones after it.' -ForegroundColor Red
    if ($Json) { Emit-Json -Ok $false }
    exit 1
}

function Emit-Json {
    param([bool]$Ok)
    $payload = [ordered]@{
        kind = 'runtime'
        platform = if ($SkipAndroid) { 'ios' } elseif ($SkipIos) { 'android' } else { 'both' }
        mode = if ($Deep) { 'synthetic-smoke' } else { 'deep-health' }
        ready = $Ok
        startedResources = [bool]$Deep
        androidDeviceId = $script:Facts.androidDeviceId
        iosDevice = $script:Facts.iosDevice
        iosDeviceId = $script:Facts.iosDeviceId
        iosRuntime = $script:Facts.iosRuntime
        guestAppiumUrl = $script:Facts.guestAppiumUrl
        facts = $script:Facts
        stages = $script:Results
    }
    Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
}

# Run a command in the guest and return its REAL exit code, never a pipeline's.
function Invoke-Guest {
    param(
        [Parameter(Mandatory)][string]$Command,
        [int]$TimeoutSec = 120
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'ssh'
    $hostOverride = if ($script:GuestIp) { "-o HostName=$($script:GuestIp) -o HostKeyAlias=macvm " } else { '' }
    $psi.Arguments = "${hostOverride}-o ConnectTimeout=10 -o BatchMode=yes macvm `"$Command`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    # Drain both redirected pipes while the child runs. Waiting first can
    # deadlock once a large simctl JSON response fills the OS pipe buffer: the
    # child cannot exit until Windows reads, while Windows waits for it to exit.
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        # Kill() with no argument: the entire-process-tree overload is .NET Core
        # only and would throw under Windows PowerShell 5.1.
        try { $p.Kill() } catch { }
        try { $p.WaitForExit() } catch { }
        return [pscustomobject]@{ ExitCode = 124; Stdout = ''; Stderr = "timed out after ${TimeoutSec}s" }
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout   = $stdout.Trim()
        Stderr   = $stderr.Trim()
    }
}

Write-Host ''
Write-Host '=== Mobile device lab gate ===' -ForegroundColor White
Write-Host ''

if ($RequireRunningProcesses) {
    $runtimePlatform = if ($SkipAndroid) { 'ios' } elseif ($SkipIos) { 'android' } else { 'both' }
    $processCheck = Get-MobileRuntimeProcessMatch -Platform $runtimePlatform
    $script:Facts['runtimeProcessCheck'] = $processCheck
    Write-Stage 'runtime: canonical processes already running' ([bool]$processCheck.ready) ($processCheck | ConvertTo-Json -Depth 6 -Compress) 'Run mobile.ps1 start for the required platform, then repeat this non-starting health check.'
    if (-not $processCheck.ready) { Stop-Gate 'canonical runtime processes' }
}

# ---------------------------------------------------------------- Windows side

if (-not $SkipAndroid) {
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) {
    Write-Stage 'windows: node present' $false 'node not on PATH' 'Install Node >= 22 (appium-mcp engines.node = >=22).'
    Stop-Gate 'Windows toolchain'
}
$nodeVersion = (& node --version).Trim()
$nodeMajor = [int]($nodeVersion -replace '^v(\d+)\..*$', '$1')
$script:Facts['nodeVersion'] = $nodeVersion
Write-Stage 'windows: node >= 22' ($nodeMajor -ge 22) "node $nodeVersion (appium-mcp requires >=22)" 'Install Node >= 22.'
if ($nodeMajor -lt 22) { Stop-Gate 'Windows toolchain' }

$androidHome = $env:ANDROID_HOME
if (-not $androidHome) { $androidHome = $env:ANDROID_SDK_ROOT }
$adbOk = $androidHome -and (Test-Path (Join-Path $androidHome 'platform-tools\adb.exe'))
$script:Facts['androidHome'] = $androidHome
Write-Stage 'windows: ANDROID_HOME resolves an adb' $adbOk "ANDROID_HOME=$androidHome" 'Set ANDROID_HOME to the SDK root containing platform-tools\adb.exe.'
if (-not $adbOk) { Stop-Gate 'Android SDK' }

$adb = Join-Path $androidHome 'platform-tools\adb.exe'
$existingServerArgs = if ($RequireRunningProcesses) { @('-H', '127.0.0.1', '-P', '5037') } else { @() }
# With an explicit server host/port adb acts only as a client of the server
# whose canonical process was proven above. It cannot launch a replacement
# server through the default local-server discovery path.
$attachedDevices = @((& $adb @existingServerArgs devices) 2>&1 | Where-Object { $_ -match '\sdevice$' })
$emulatorDetails = @(
    foreach ($line in @($attachedDevices | Where-Object { $_ -match '^emulator-\d+\s+device$' })) {
        $id = [string](($line -split '\s+')[0])
        $sdk = [string]((& $adb @existingServerArgs -s $id shell getprop ro.build.version.sdk 2>$null) | Select-Object -First 1)
        $avd = [string]((& $adb @existingServerArgs -s $id emu avd name 2>$null) | Select-Object -First 1)
        [pscustomobject]@{ Id = $id; Sdk = $sdk.Trim(); Avd = $avd.Trim() }
    }
)
$devices = @($emulatorDetails | Where-Object { $_.Sdk -eq ([string]$androidExpectation.apiLevel) -and $_.Avd -eq ([string]$androidExpectation.avdName) })
$haveEmulator = ($devices.Count -gt 0)
$script:Facts['androidAttachedDeviceIds'] = @($attachedDevices | ForEach-Object { ($_ -split '\s+')[0] })
$script:Facts['androidDevices'] = @($devices | ForEach-Object Id)
$script:Facts['androidDeviceId'] = @($script:Facts['androidDevices'])[0]
Write-Stage "android: canonical $($androidExpectation.avdName) API $($androidExpectation.apiLevel) emulator is attached" $haveEmulator (($emulatorDetails | ForEach-Object { "$($_.Id):$($_.Avd):API-$($_.Sdk)" }) -join '; ') "Start canonical AVD '$($androidExpectation.avdName)': & `"$androidHome\emulator\emulator.exe`" -avd $($androidExpectation.avdName). Physical devices, other AVDs, and other API levels are deliberately excluded."
if (-not $haveEmulator) { Stop-Gate 'Android emulator' }
}

if ($SkipIos) {
    Write-Host ''
    Write-Host 'ANDROID READY (iOS skipped by -SkipIos)' -ForegroundColor Green
    if ($Json) { Emit-Json -Ok $true }
    exit 0
}

# -------------------------------------------------------------------- iOS side

$vmwareResource = Get-MobileDevelopmentResource -Id 'vmware-workstation'
$vmrun = @($vmwareResource.discovery.vmrunPaths | ForEach-Object { ([string]$_) -replace '/', '\' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if ($vmrun.Count) { $vmrun = [string]$vmrun[0] } else { $vmrun = $null }
$vmrunOk = Test-Path $vmrun
Write-Stage 'vmware: vmrun present' $vmrunOk $vmrun 'Install VMware Workstation, or pass -SkipIos.'
if (-not $vmrunOk) { Stop-Gate 'VMware' }

$running = & $vmrun list
$listedVmx = $running | Select-Object -Skip 1 | Where-Object { $_ -match '\.vmx$' } | Select-Object -First 1
$vmxFacts = Get-MobileVmxFacts
$vmx = $vmxFacts.path
$script:Facts['vmx'] = $vmx
# Written long-hand rather than with `??`: that operator is PowerShell 7 only,
# and this file declares 5.1 so it runs under either shell.
$vmEvidence = if ($listedVmx) { "vmrun listed $listedVmx; authority=$vmx" } else { "authority=$vmx; vmrun=$($running -join ' ')" }

# `vmrun list` is a *report about* the guest, not the guest. On 2026-08-17 it
# said "Total running VMs: 0" while that guest was four hours into an uptime
# and serving SSH and Appium normally -- the host-to-guest control channel had
# degraded, and nothing else had. Gating here on its word would have stopped
# the run at stage one and named the wrong component, which is exactly what
# happened for an hour.
#
# So its answer is recorded, and then the question that actually matters is
# asked directly: can SSH reach the guest?
$reachable = $null
$resolveError = ''
try {
    $reachable = Resolve-MobileLabGuestAddress -Vmx $vmx -VmrunPath $vmrun -SshHost 'macvm' -TimeoutSeconds 45
} catch {
    $resolveError = $_.Exception.Message
}

$vmUp = [bool]$reachable
if ($reachable -and -not $listedVmx) {
    $vmEvidence = "vmrun list reported no running VM, but the guest answered SSH at $($reachable.address) (via $($reachable.source)). Trusting SSH: the VMX control channel is degraded, the guest is not."
}
elseif (-not $reachable) {
    # Both signals failed, which is the case where the guest really is down.
    # Carry the resolver's account of what it probed, so the operator is not
    # left with "not running" and no idea which addresses were ruled out.
    $vmEvidence = "vmrun evidence: $vmEvidence -- and no address was SSH-reachable. $resolveError"
}
Write-Stage 'vmware: the macOS guest is running' $vmUp $vmEvidence "Start it: & `"$vmrun`" -T ws start <path\to\macos.vmx> nogui"
if (-not $vmUp) { Stop-Gate 'macOS VM' }

$guestIp = $reachable.address
$script:GuestIp = $guestIp
$script:Facts['guestIp'] = $guestIp
$script:Facts['guestAddressSource'] = $reachable.source
Write-Stage 'vmware: guest address resolved and reached' $true "guest at $guestIp via $($reachable.source) in $($reachable.elapsedSeconds)s" ''

# Not a second opinion -- the resolver returns only an address it has already
# connected to. This runs a real command so the stage records what the guest
# actually said, rather than that a TCP handshake completed.
$ssh = Invoke-Guest -Command 'echo GUEST-UP' -TimeoutSec 30
$sshOk = ($ssh.ExitCode -eq 0 -and $ssh.Stdout -match 'GUEST-UP')
Write-Stage 'ssh: guest executes commands' $sshOk "macvm via $guestIp; exit=$($ssh.ExitCode) $($ssh.Stderr)" 'Verify the macvm identity/user/key; the HostName is overridden with the current DHCP address.'
if (-not $sshOk) { Stop-Gate 'ssh to guest' }

# The ssh alias carries a hardcoded HostName. If the lease moved, ssh still
# works only by luck; say so before it becomes a confusing failure later.
$configuredHost = (Get-Content "$HOME\.ssh\config" -Encoding UTF8 -ErrorAction SilentlyContinue |
        Select-String -Pattern '^\s*HostName\s+(\S+)' -Context 2, 0 |
        Where-Object { $_.Context.PreContext -match 'Host\s+macvm' } |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)
if ($configuredHost -and $configuredHost -ne $guestIp) {
    Write-Host ("WARN  ssh config HostName ({0}) != discovered guest IP ({1}). Update ~/.ssh/config." -f $configuredHost, $guestIp) -ForegroundColor Yellow
}

if ($Deep) {
    $guestSync = Join-Path $PSScriptRoot 'Sync-MobileLabGuestScripts.ps1'
    $syncOutput = @(& $guestSync -GuestIp $guestIp -Json 2>&1)
    $syncExit = $LASTEXITCODE
    $syncLine = $syncOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $syncResult = $null
    if ($syncLine) { try { $syncResult = $syncLine | ConvertFrom-Json } catch { } }
    $syncOk = ($syncExit -eq 0 -and $syncResult -and $syncResult.ok)
    Write-Stage 'guest: versioned lab helpers synchronized' $syncOk (($syncOutput | Select-Object -Last 4) -join ' ') 'Rerun Start-MobileLab.ps1 -Json; never hand-edit ~/mobile-lab copies.'
    if (-not $syncOk) { Stop-Gate 'guest helper sync' }
}

# Ask the toolchain, never a path: xcodes installs /Applications/Xcode-<ver>.app,
# so a literal /Applications/Xcode.app test is false on a good install.
$xcode = Invoke-Guest -Command 'xcodebuild -version' -TimeoutSec 120
$xcodeOk = ($xcode.ExitCode -eq 0)
$script:Facts['xcode'] = ($xcode.Stdout -split "`n")[0]
Write-Stage 'guest: Xcode usable' $xcodeOk (($xcode.Stdout -split "`n")[0]) 'Run: ssh macvm "sudo xcodebuild -runFirstLaunch"'
if (-not $xcodeOk) { Stop-Gate 'Xcode in guest' }

# Three outcomes, not two. "simctl answered and listed no runtime" and "simctl
# did not answer" are different facts, and collapsing them sends the operator
# to a multi-gigabyte download to fix a problem they do not have.
#
# Observed 2026-08-18, immediately after a hard power-off: the guest was at load
# average 18.5 reindexing, this command exceeded its timeout, and the gate
# reported "an iOS simulator runtime is installed: FAIL -- iOS runtimes: " with
# the download remediation. The runtime was installed the whole time
# (the configured runtime was present and healthy).
$runtime = Invoke-Guest -Command 'xcrun simctl list runtimes -j' -TimeoutSec 120
if ($runtime.ExitCode -ne 0) {
    Write-Stage 'guest: an iOS simulator runtime is installed' $false `
        "could not determine: simctl did not answer (exit=$($runtime.ExitCode)) $($runtime.Stderr)" `
        'The guest did not answer in time -- this is NOT evidence the runtime is missing. It is usually load right after a boot or a hard power-off (check `uptime`); retry once it settles. Only if simctl answers with zero iOS runtimes should you run: ssh macvm "sudo xcodebuild -downloadPlatform iOS -architectureVariant universal"'
    Stop-Gate 'iOS runtime (undetermined)'
}
$runtimeInventory = $null
try { $runtimeInventory = $runtime.Stdout | ConvertFrom-Json } catch { }
$runtimeMatches = @($runtimeInventory.runtimes | Where-Object { [string]$_.identifier -match ([regex]::Escape([string]$iosExpectation.runtimeKeySuffix) + '$') -and $_.isAvailable -ne $false })
$runtimeOk = ($runtime.ExitCode -eq 0 -and $runtimeMatches.Count -eq 1)
Write-Stage "guest: iOS $($iosExpectation.platformVersion) simulator runtime is installed" $runtimeOk "matches=$($runtimeMatches.Count)" 'Run: ssh macvm "sudo xcodebuild -downloadPlatform iOS -architectureVariant universal"'
if (-not $runtimeOk) { Stop-Gate 'iOS runtime' }

$deviceInventory = Invoke-Guest -Command 'xcrun simctl list devices available -j' -TimeoutSec 120
$deviceJson = $null
try { $deviceJson = $deviceInventory.Stdout | ConvertFrom-Json } catch { }
$runtimeProperty = if ($deviceJson -and $deviceJson.devices) { @($deviceJson.devices.PSObject.Properties | Where-Object { $_.Name -match ([regex]::Escape([string]$iosExpectation.runtimeKeySuffix) + '$') } | Select-Object -First 1) } else { @() }
$targetMatches = if ($runtimeProperty.Count) { @($runtimeProperty[0].Value | Where-Object { [string]$_.name -eq [string]$iosExpectation.deviceName }) } else { @() }
$target = if ($targetMatches.Count -eq 1) { $targetMatches[0] } else { $null }
$targetUdid = if ($target) { [string]$target.udid } else { $null }
$targetState = if ($target) { [string]$target.state } else { $null }
$bootedOk = ($deviceInventory.ExitCode -eq 0 -and $targetUdid -and $targetState -eq 'Booted' -and $targetMatches.Count -eq 1)
# Same distinction as the runtime check above: a command that never answered
# has not established that the simulator is absent.
$bootedEvidence = if ($deviceInventory.ExitCode -ne 0) {
    "could not determine: simctl did not answer (exit=$($deviceInventory.ExitCode)) $($deviceInventory.Stderr) -- not evidence the simulator is missing; retry once guest load settles"
} elseif ($targetUdid) {
    "$($iosExpectation.deviceName) ($targetUdid) ($targetState); runtime=iOS $($iosExpectation.platformVersion)"
} else {
    $deviceInventory.Stdout
}
$script:Facts['bootedSimulator'] = $bootedEvidence
$script:Facts['iosDevice'] = [string]$iosExpectation.deviceName
$script:Facts['iosDeviceId'] = $targetUdid
Write-Stage "guest: $($iosExpectation.deviceName) / iOS $($iosExpectation.platformVersion) Simulator is booted" $bootedOk $bootedEvidence 'Run mobile.ps1 start ios -Json to boot the exact configured Simulator.'
if (-not $bootedOk) { Stop-Gate 'booted simulator' }
if (-not $script:Facts['iosDeviceId']) {
    Write-Stage 'guest: booted simulator has an explicit UDID' $false $booted.Stdout 'Boot exactly one Simulator and rerun; deep validation never targets a physical iPhone or an ambiguous device name.'
    Stop-Gate 'simulator identity'
}

$guestAppium = Invoke-Guest -Command 'appium --version' -TimeoutSec 120
$guestAppiumOk = ($guestAppium.ExitCode -eq 0 -and $guestAppium.Stdout.Trim() -eq [string]$guestAppiumExpectation.version)
Write-Stage "guest: Appium $($guestAppiumExpectation.version) installed" $guestAppiumOk $guestAppium.Stdout 'Run the registry-driven guest setup script.'
if (-not $guestAppiumOk) { Stop-Gate 'guest Appium version' }
$driver = Invoke-Guest -Command 'appium driver list --installed 2>&1' -TimeoutSec 300
$driverOk = ($driver.ExitCode -eq 0 -and $driver.Stdout -match ('xcuitest@' + [regex]::Escape([string]$xcuitestExpectation.version) + '\b'))
Write-Stage "guest: XCUITest $($xcuitestExpectation.version) installed" $driverOk $driver.Stdout 'Run the registry-driven guest setup script.'
if (-not $driverOk) { Stop-Gate 'Appium drivers' }

$appiumUrl = "http://${guestIp}:$($guestAppiumExpectation.port)"
$script:Facts['appiumUrl'] = $appiumUrl
$script:Facts['guestAppiumUrl'] = $appiumUrl
$statusOk = $false
$statusEvidence = ''
try {
    $status = Invoke-RestMethod -Uri "$appiumUrl$($guestAppiumExpectation.statusPath)" -TimeoutSec 30
    $statusOk = [bool]$status.value.ready
    $statusEvidence = "$appiumUrl -- ready=$($status.value.ready) v$($status.value.build.version)"
}
catch {
    $statusEvidence = "$appiumUrl -- $($_.Exception.Message)"
}
Write-Stage 'appium: server reachable from Windows' $statusOk $statusEvidence 'Start it in the guest (see scripts/guest/), then allow up to ~6 min for cold start.'
if (-not $statusOk) { Stop-Gate 'Appium server' }

$script:Facts['iosRuntime'] = "iOS $($iosExpectation.platformVersion)"

if ($Deep) {
    if ($SkipIos) {
        Write-Stage 'deep: cross-platform fixture' $false '-Deep requires the iOS guest' 'Remove -SkipIos and rerun.'
        Stop-Gate 'deep validation'
    }
    $deepLease = [Threading.Mutex]::new($false, 'Global\AgentHub.MobileDeviceLab.ForegroundMutation')
    $deepLeaseAcquired = $false
    try { $deepLeaseAcquired = $deepLease.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $deepLeaseAcquired = $true }
    Write-Stage 'deep: exclusive foreground lease acquired' $deepLeaseAcquired 'Global\AgentHub.MobileDeviceLab.ForegroundMutation' 'Wait for the owning mobile run to finish; never terminate it merely to make this gate pass.'
    if (-not $deepLeaseAcquired) { Stop-Gate 'deep exclusivity lease' }

    $idleProbe = Join-Path $PSScriptRoot 'Test-MobileLabIdle.ps1'
    $idleOutput = @(& $idleProbe -GuestIp $guestIp -AppiumUrl $appiumUrl -IgnoreLabLease -Json 2>&1)
    $idleExit = $LASTEXITCODE
    $idleLine = $idleOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $idleResult = $null
    if ($idleLine) { try { $idleResult = $idleLine | ConvertFrom-Json } catch { } }
    $idleOk = ($idleExit -eq 0 -and $idleResult -and $idleResult.idle)
    Write-Stage 'deep: simulators are idle and unclaimed' $idleOk (($idleOutput | Select-Object -Last 4) -join ' ') 'Wait for the reported build, Maestro run, simulator mutation, or Appium session to finish. Never terminate another task merely to make this gate pass.'
    if (-not $idleOk) { Stop-Gate 'deep exclusivity' }

    $builder = Join-Path $PSScriptRoot 'Build-MobileLabSmokeFixture.ps1'
    $buildOutput = @(& $builder -GuestIp $guestIp -IosUdid $script:Facts['iosDeviceId'] -Json 2>&1)
    $buildExit = $LASTEXITCODE
    $buildLine = $buildOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $buildResult = $null
    if ($buildLine) { try { $buildResult = $buildLine | ConvertFrom-Json } catch { } }
    $buildOk = ($buildExit -eq 0 -and $buildResult -and $buildResult.ok)
    Write-Stage 'deep: synthetic fixture built' $buildOk (($buildOutput | Select-Object -Last 8) -join ' ') 'Inspect localBuildRoot, verify Expo/Gradle/Xcode, then rerun -Deep.'
    if (-not $buildOk) { Stop-Gate 'synthetic fixture build' }

    # Building is non-foreground work. Re-enumerate immediately before Appium
    # installs or launches either fixture, while the cross-process lease still
    # excludes every other AgentHub mobile run.
    $preLaunchOutput = @(& $idleProbe -GuestIp $guestIp -AppiumUrl $appiumUrl -IgnoreLabLease -Json 2>&1)
    $preLaunchExit = $LASTEXITCODE
    $preLaunchLine = $preLaunchOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $preLaunchResult = $null
    if ($preLaunchLine) { try { $preLaunchResult = $preLaunchLine | ConvertFrom-Json } catch { } }
    $preLaunchOk = ($preLaunchExit -eq 0 -and $preLaunchResult -and $preLaunchResult.idle)
    Write-Stage 'deep: final pre-launch exclusivity check' $preLaunchOk (($preLaunchOutput | Select-Object -Last 4) -join ' ') 'A competing Maestro, build, Simulator mutation, or Appium session started during the build; wait for it and rerun.'
    if (-not $preLaunchOk) { Stop-Gate 'deep pre-launch exclusivity' }

    $evidenceRoot = Join-Path $env:LOCALAPPDATA ('AgentHub\mobile-lab\evidence\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $mcpClient = Join-Path $PSScriptRoot 'Invoke-AppiumMcpSmoke.mjs'
    $mcpOutput = @(& node $mcpClient --remote-url $appiumUrl --android-udid $script:Facts['androidDeviceId'] --ios-udid $script:Facts['iosDeviceId'] --android-app $buildResult.androidApk --ios-app $buildResult.iosApp --ios-bundle-id $buildResult.iosBundleId --output-dir $evidenceRoot --appium-package $appiumMcp.Package --ios-device-name $iosExpectation.deviceName --ios-platform-version $iosExpectation.platformVersion 2>&1)
    $mcpExit = $LASTEXITCODE
    $mcpLine = $mcpOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1
    $mcpResult = $null
    if ($mcpLine) { try { $mcpResult = $mcpLine | ConvertFrom-Json } catch { } }
    $reportedSessionsCleaned = ($mcpResult -and [bool]$mcpResult.sessionsCleaned)
    $sessionDiscoveryOk = $false
    $remainingAppiumSessions = @()
    try {
        $remainingAppiumSessions = @((Invoke-RestMethod -Uri "$appiumUrl$($guestAppiumExpectation.sessionDiscoveryPath)" -TimeoutSec 20).value)
        $sessionDiscoveryOk = $true
    }
    catch { }
    $sessionsGone = ($sessionDiscoveryOk -and $remainingAppiumSessions.Count -eq 0)
    $mcpSessionsCleaned = ($reportedSessionsCleaned -and $sessionsGone)
    $mcpOk = ($mcpExit -eq 0 -and $mcpResult -and $mcpResult.ok -and $mcpSessionsCleaned)
    $script:Facts['deepEvidenceRoot'] = $evidenceRoot
    $script:Facts['appiumMcpVersion'] = $appiumMcp.Version
    $script:Facts['appiumMcpToolCount'] = if ($null -ne $mcpResult) { [int]$mcpResult.toolCount } else { 0 }
    Write-Stage 'deep: pinned Appium MCP cross-platform interaction' $mcpOk (($mcpOutput | Select-Object -Last 6) -join ' ') 'Open appium-mcp-smoke.json in deepEvidenceRoot, apply the reported error, and rerun -Deep.'
    # Appium/XCUITest can leave its xcodebuild WebDriverAgent runner alive after
    # both protocol sessions have been deleted. That runner is able to mutate
    # the Simulator later and makes the next exclusivity probe fail forever.
    # Retire only the exact WDA process for the enumerated Simulator when its
    # parent is this lab's Appium server; never target arbitrary xcodebuild work.
    $wdaCleanup = if ($sessionsGone) { Invoke-Guest -Command "~/mobile-lab/cleanup-wda-guest.sh '$($script:Facts['iosDeviceId'])'" -TimeoutSec 30 } else { [pscustomobject]@{ ExitCode = 1; Stdout = ''; Stderr = 'skipped because one or more Appium sessions remain active or session discovery failed' } }
    $wdaCleanupOk = ($sessionsGone -and $wdaCleanup.ExitCode -eq 0 -and $wdaCleanup.Stdout -match '"ok":true')
    $script:Facts['wdaCleanup'] = $wdaCleanup.Stdout
    Write-Stage 'deep: Appium-owned WDA runner retired' $wdaCleanupOk "$($wdaCleanup.Stdout) $($wdaCleanup.Stderr)" 'Inspect only Appium-owned WebDriverAgent processes for the reported Simulator UDID; do not terminate unrelated Xcode work.'
    if (-not $mcpOk) { Stop-Gate 'Appium MCP deep smoke' }
    if (-not $wdaCleanupOk) { Stop-Gate 'WDA cleanup' }

    $androidAfter = @(& $adb devices | Where-Object { $_ -match ('^' + [regex]::Escape([string]$script:Facts['androidDeviceId']) + '\s+device$') })
    $simulatorAfter = Invoke-Guest -Command 'xcrun simctl list devices booted | grep Booted | head -1' -TimeoutSec 120
    $appiumAfter = $false
    try { $appiumAfter = [bool](Invoke-RestMethod -Uri "$appiumUrl$($guestAppiumExpectation.statusPath)" -TimeoutSec 15).value.ready } catch { }
    $postDeepReady = ($androidAfter.Count -gt 0 -and $simulatorAfter.ExitCode -eq 0 -and $simulatorAfter.Stdout -match [regex]::Escape([string]$script:Facts['iosDeviceId']) -and $appiumAfter -and $mcpSessionsCleaned)
    Write-Stage 'deep: lab remains ready after session cleanup' $postDeepReady "android=$($androidAfter -join '; '); ios=$($simulatorAfter.Stdout); appium=$appiumAfter; sessionsCleaned=$($mcpResult.sessionsCleaned)" 'Rerun Start-MobileLab.ps1 -Json, then repeat -Deep; inspect host memory pressure if the emulator exited.'
    if (-not $postDeepReady) { Stop-Gate 'post-deep readiness' }
    try { $deepLease.ReleaseMutex() } catch { }
    $deepLease.Dispose()
}

Write-Host ''
Write-Host 'MOBILE LAB READY' -ForegroundColor Green
if (-not $SkipAndroid) { Write-Host ("  android : {0}" -f (($script:Facts['androidDevices']) -join ', ')) -ForegroundColor Gray }
if (-not $SkipIos) {
    Write-Host ("  ios     : {0}" -f $script:Facts['bootedSimulator']) -ForegroundColor Gray
    Write-Host ("  remote  : {0}   <- pass as remoteServerUrl for iOS sessions" -f $appiumUrl) -ForegroundColor Gray
}
Write-Host ''
if ($Json) { Emit-Json -Ok $true }
exit 0
