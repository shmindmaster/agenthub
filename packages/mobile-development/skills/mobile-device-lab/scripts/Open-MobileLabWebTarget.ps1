#Requires -Version 5.1
<#
.SYNOPSIS
Open a Windows-host dev server URL in Mobile Safari (iOS Simulator, inside the
macOS guest) and/or Chrome (local Android emulator).

.DESCRIPTION
"localhost" means something different inside every namespace this lab spans:
the Windows host, the Android emulator, and the macOS guest each resolve it to
themselves, not to the machine actually running the dev server. A URL that
opens fine in the host browser is meaningless handed unmodified to a device --
each one needs the host portion rewritten to how IT reaches this machine:

  Android emulator   10.0.2.2             the standard emulator-to-host NAT alias
  iOS Simulator       <VMnet8 host addr>   VMware's NAT gateway back to Windows

The VMnet8 address is resolved at runtime, never hardcoded. It is a
DHCP-managed adapter address that VMware can and does reassign -- the same
class of value that MobileLabGuest.psm1 exists to stop this lab from trusting
as a constant. A resolution failure throws rather than falling back to
localhost, because a silent fallback would open a URL that is guaranteed
wrong: the device would show a plain connection error indistinguishable from
an actual app bug, and nothing here would have said why.

Before opening anything, the script checks that the dev server is reachable
on the VMnet8 address, not just on localhost. Vite, Next.js, and Create React
App all default to binding 127.0.0.1, which answers the Windows browser and
nothing else. From a device that failure looks identical to a dead network --
this check exists to name the real cause (a loopback bind) instead of leaving
it to be rediscovered by someone staring at a blank Safari tab.

.PARAMETER Url
The dev server URL exactly as it works from the Windows host, e.g.
http://localhost:5173/dashboard. Must include an explicit or scheme-default
port.

.PARAMETER Platform
Which target(s) to open the URL on: 'ios', 'android', or 'both'. Default
'both'.

.PARAMETER IosUdid
Simulator UDID to target. Default 'booted', simctl's own alias for whichever
simulator is currently booted.

.PARAMETER AndroidDeviceId
adb device serial to target. Default: the first device 'adb devices' reports
in 'device' state matching emulator-<port>.

.PARAMETER Json
Emit one compressed JSON object as the final line, for agent use.

.PARAMETER SkipReachabilityCheck
Skip the pre-flight port check and open the URL unconditionally. The check is
the most useful thing this script does; skip it only when it is already known
to be wrong for your setup.

.EXAMPLE
Open-MobileLabWebTarget.ps1 -Url http://localhost:5173/dashboard

.EXAMPLE
Open-MobileLabWebTarget.ps1 -Url http://localhost:3000 -Platform android -Json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Url,
    [ValidateSet('ios', 'android', 'both')][string]$Platform = 'both',
    [string]$IosUdid = 'booted',
    [string]$AndroidDeviceId,
    [string]$LeaseId,
    [switch]$Json,
    [switch]$SkipReachabilityCheck
)

$ErrorActionPreference = 'Stop'
$ownedLeaseId = $null

# Shared guest-address resolution. Kept in a module because Start- and Test-
# both need identical semantics; two copies of this logic is how the lab ends
# up with two different answers to 'where is the guest'.
Import-Module (Join-Path $PSScriptRoot 'MobileLabGuest.psm1') -Force

function Say {
    param([string]$Message, [string]$Colour = 'Gray')
    Write-Host $Message -ForegroundColor $Colour
}

function Test-IsLoopbackHost {
    <#
    .SYNOPSIS
        Is this host name a reference to "the machine I am typing on"?
    .DESCRIPTION
        This is the precondition for every rewrite in this script, and it was
        missing. Translating `localhost` is the script's whole purpose: the name
        resolves to a different machine inside the emulator and inside the
        guest, so it has to be replaced with an address that means "the Windows
        host" from there.

        A name that is NOT loopback needs no translation -- and must not get
        one. `staging.example.com` already means the same thing everywhere;
        rewriting its host sends the device to this workstation instead, which
        looks like it worked. Measured 2026-08-18: `-Url https://example.com`
        opened `https://10.0.2.2/` on the emulator.
    #>
    param([Parameter(Mandatory)][string]$HostName)

    $bare = $HostName.Trim('[', ']')
    if ($bare -in @('localhost', '::1', '0.0.0.0')) { return $true }
    if ($bare -like '*.localhost') { return $true }

    $parsedAddress = [System.Net.IPAddress]::Any
    if ([System.Net.IPAddress]::TryParse($bare, [ref]$parsedAddress)) {
        return [System.Net.IPAddress]::IsLoopback($parsedAddress)
    }
    return $false
}

function New-RewrittenUrl {
    <#
    .SYNOPSIS
        Same URL, host swapped for how the target namespace reaches this box.
    .DESCRIPTION
        UriBuilder touches only the host component, so path, query, and
        fragment survive untouched -- a hand-rolled string replace would risk
        matching the wrong substring if the port or a path segment happened to
        look like the hostname.
    #>
    param([Parameter(Mandatory)][Uri]$Source, [Parameter(Mandatory)][string]$NewHost)
    $builder = [UriBuilder]$Source
    $builder.Host = $NewHost
    return $builder.Uri.AbsoluteUri
}

function Resolve-Vmnet8Address {
    <#
    .SYNOPSIS
        The Windows-side IPv4 address of the VMware Network Adapter VMnet8.
    .DESCRIPTION
        Get-NetIPAddress is the documented, non-parsing way to ask Windows
        what is on this adapter. ipconfig text-scraping is only the fallback,
        for a box where the NetTCPIP module happens not to be loaded -- it is
        bundled with Windows but not guaranteed present in every profile.
        There is no further fallback: a caller that cannot resolve this
        address must be told so, not handed localhost, which would send every
        device down a network path that provably cannot reach this machine.
    #>
    [CmdletBinding()]
    param()

    $adapterAddress = $null
    if (Get-Command -Name Get-NetIPAddress -ErrorAction SilentlyContinue) {
        $candidates = @(
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceAlias -match 'VMnet8' }
        )
        if ($candidates.Count -gt 0) { $adapterAddress = $candidates[0].IPAddress }
        if ($candidates.Count -gt 1) {
            Say ("  note: multiple IPv4 addresses on VMnet8 ({0}); using {1}" -f `
                    (($candidates | ForEach-Object IPAddress) -join ', '), $adapterAddress) 'Yellow'
        }
    }

    if (-not $adapterAddress) {
        $ipconfigText = (& ipconfig) -join "`n"
        $blockMatch = [regex]::Match($ipconfigText, '(?ms)VMnet8:.*?(?=\r?\n\r?\n|\z)')
        if ($blockMatch.Success) {
            $ipMatch = [regex]::Match($blockMatch.Value, 'IPv4 Address[^\:]*:\s*([\d\.]+)')
            if ($ipMatch.Success) { $adapterAddress = $ipMatch.Groups[1].Value }
        }
    }

    if (-not $adapterAddress) {
        throw ('Could not resolve the VMware Network Adapter VMnet8 IPv4 address via ' +
            'Get-NetIPAddress or ipconfig. Not falling back to localhost: that would open ' +
            'a URL the iOS guest cannot reach, and the resulting Safari error looks like a ' +
            'broken app rather than a broken network path. Confirm VMware Workstation is ' +
            'installed and its VMnet8 (NAT) virtual network is enabled.')
    }
    return $adapterAddress
}

function Get-Ipv4Slash24 {
    param([string]$Address)
    $parts = $Address -split '\.'
    if ($parts.Count -ne 4) { return $null }
    return ($parts[0..2] -join '.')
}

function Test-DevServerPort {
    <#
    .SYNOPSIS
        True only if a real TCP connection to $ComputerName:$Port completes.
    #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 5
    )
    if (Get-Command -Name Test-NetConnection -ErrorAction SilentlyContinue) {
        try {
            return [bool](Test-NetConnection -ComputerName $ComputerName -Port $Port `
                    -WarningAction SilentlyContinue -InformationLevel Quiet)
        } catch {
            return $false
        }
    }
    # Test-NetConnection ships in the NetTCPIP module, which is not guaranteed
    # present -- the fallback is a real probe, not skipping the check.
    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connectTask = $client.ConnectAsync($ComputerName, $Port)
        $completed = $connectTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))
        return [bool]($completed -and $client.Connected)
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Open-AndroidUrl {
    param([Parameter(Mandatory)][string]$TargetUrl, [string]$DeviceId)

    $androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (-not $androidHome) { throw 'ANDROID_HOME (or ANDROID_SDK_ROOT) is not set; cannot locate adb.' }
    $adb = Join-Path $androidHome 'platform-tools\adb.exe'
    if (-not (Test-Path $adb)) { throw "adb not found at $adb." }

    $resolvedDeviceId = $DeviceId
    if (-not $resolvedDeviceId) {
        $devices = @(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
        if ($devices.Count -eq 0) { throw "No attached Android emulator ('adb devices' returned none in 'device' state). Start the emulator first." }
        $resolvedDeviceId = $devices[0]
    }
    elseif ($resolvedDeviceId -notmatch '^emulator-\d+$') {
        # Auto-selection already filters to `emulator-<port>`; an explicit
        # -AndroidDeviceId must not be the way around that filter.
        #
        # This workstation does have a physical handset attached (observed
        # 2026-08-18: serial 47181FDAS00A0D, alongside emulator-5554), so the
        # unsafe value is one paste away rather than hypothetical. The lab
        # drives health-sensitive products whose capture tools are screenshots
        # and full element trees, and it may only ever point those at synthetic
        # fixtures on a simulator -- which is also why nothing here is allowed
        # to claim "verified on device".
        throw ("Refusing to drive '$resolvedDeviceId': it is not an Android emulator. " +
               "This lab targets emulators and simulators only, and the same tools that open a URL " +
               "also capture screenshots and page source from whatever is on screen. " +
               "Pass an 'emulator-<port>' serial from 'adb devices', or start an emulator.")
    }

    # `| Out-Null` here is safe: Out-Null consumes pipeline objects, and
    # $LASTEXITCODE is set only by the native adb process, so the exit code
    # below is adb's, never a pipeline tail's.
    & $adb -s $resolvedDeviceId shell am start -a android.intent.action.VIEW -d "$TargetUrl" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "adb shell am start failed with exit $LASTEXITCODE on device $resolvedDeviceId." }
    return $resolvedDeviceId
}

function Open-IosUrl {
    param(
        [Parameter(Mandatory)][string]$TargetUrl,
        [Parameter(Mandatory)][string]$GuestAddress,
        [string]$Udid = 'booted'
    )

    # The whole command travels as one argument; ssh hands it verbatim to the
    # guest's shell, which is what re-splits and re-quotes it. Local
    # PowerShell quoting around $TargetUrl is irrelevant here.
    $remoteCommand = "xcrun simctl openurl $Udid '$TargetUrl'"
    $output = & ssh -o "HostName=$GuestAddress" -o 'HostKeyAlias=macvm' -o 'LogLevel=ERROR' -o 'BatchMode=yes' macvm $remoteCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ssh/simctl openurl failed (exit $LASTEXITCODE) targeting '$Udid': $($output -join ' ')"
    }
}

$script:Facts = [ordered]@{
    url                 = $Url
    platform            = $Platform
    vmnet8Address       = $null
    guestAddress        = $null
    reachabilityChecked = -not $SkipReachabilityCheck
    android             = $null
    ios                 = $null
}

function Emit-Result {
    param([bool]$Ok)
    if (-not $Json) { return }
    $payload = [ordered]@{
        ok            = $Ok
        url           = $script:Facts.url
        platform      = $script:Facts.platform
        vmnet8Address = $script:Facts.vmnet8Address
        guestAddress  = $script:Facts.guestAddress
        android       = $script:Facts.android
        ios           = $script:Facts.ios
    }
    Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
}

try {
    $leaseScript = Join-Path $PSScriptRoot 'Enter-MobileLabLease.ps1'
    $idleScript = Join-Path $PSScriptRoot 'Test-MobileLabIdle.ps1'
    if ([string]::IsNullOrWhiteSpace($LeaseId)) {
        $leaseOutput = @(& (Get-Process -Id $PID).Path -NoProfile -File $leaseScript -Action Acquire -Json 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not acquire the canonical mobile-lab foreground lease: $($leaseOutput -join ' ')" }
        $lease = $leaseOutput | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1 | ConvertFrom-Json
        $LeaseId = [string]$lease.leaseId
        $ownedLeaseId = $LeaseId
    }
    $idleOutput = @(& (Get-Process -Id $PID).Path -NoProfile -File $idleScript -HostOnly -LeaseId $LeaseId -Json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "The canonical mobile-lab idle probe refused web foreground mutation: $($idleOutput -join ' ')" }

    Write-Host ''
    Say '=== Opening web target in mobile lab ===' 'White'

    try {
        $parsedUrl = [Uri]$Url
    } catch {
        throw "Could not parse -Url '$Url' as a URI: $($_.Exception.Message)"
    }
    if (-not $parsedUrl.IsAbsoluteUri) { throw "-Url must be absolute (include a scheme), e.g. http://localhost:5173. Got: '$Url'" }
    if ($parsedUrl.Port -lt 0) { throw "-Url must resolve to an explicit port. Got: '$Url'" }
    $devServerPort = $parsedUrl.Port

    $wantsIos = ($Platform -eq 'ios' -or $Platform -eq 'both')
    $wantsAndroid = ($Platform -eq 'android' -or $Platform -eq 'both')

    # Only a loopback host is ambiguous across these namespaces, so only a
    # loopback host gets translated. Everything else is already the same
    # machine from every device, and rewriting it would quietly substitute this
    # workstation for the server the caller named.
    $needsTranslation = Test-IsLoopbackHost -HostName $parsedUrl.Host
    $script:Facts.hostTranslated = $needsTranslation
    if (-not $needsTranslation) {
        Say "  '$($parsedUrl.Host)' is not a loopback host: opening it unchanged on every target." 'DarkGray'
    }

    # The VMnet8 address is needed to build the iOS URL, and it is also the
    # address the reachability check probes against regardless of platform --
    # the loopback-bind failure mode it is looking for is a host-side
    # property of the dev server, not something specific to one device.
    $needsVmnet8 = $needsTranslation -and ($wantsIos -or -not $SkipReachabilityCheck)
    $vmnet8Address = $null
    if ($needsVmnet8) {
        $vmnet8Address = Resolve-Vmnet8Address
        $script:Facts.vmnet8Address = $vmnet8Address
        Say "  VMnet8 host address: $vmnet8Address"
    }

    $guest = $null
    if ($wantsIos) {
        $guest = Resolve-MobileLabGuestAddress -SshHost 'macvm' -TimeoutSeconds 60
        $script:Facts.guestAddress = $guest.address
        Say "  guest at $($guest.address) (via $($guest.source))"

        $fullIdleOutput = @(& (Get-Process -Id $PID).Path -NoProfile -File $idleScript -GuestIp $guest.address -LeaseId $LeaseId -Json 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "The full mobile-lab idle probe refused iOS web foreground mutation: $($fullIdleOutput -join ' ')" }

        $hostPrefix = Get-Ipv4Slash24 -Address $vmnet8Address
        $guestPrefix = Get-Ipv4Slash24 -Address $guest.address
        if ($hostPrefix -and $guestPrefix -and $hostPrefix -ne $guestPrefix) {
            Say ("  WARNING: VMnet8 host address {0} and guest address {1} are not on the same /24. " -f $vmnet8Address, $guest.address) 'Yellow'
            Say '  That usually means a non-default VMware NAT layout; the iOS open below may still fail.' 'Yellow'
        }
    }

    # The check below diagnoses one specific failure: a dev server bound to
    # loopback only. That failure cannot apply to a host this script is not
    # translating, and probing the VMnet8 address for a remote site would just
    # invent a problem.
    if (-not $SkipReachabilityCheck -and $needsTranslation) {
        Say "  checking dev server reachability on port $devServerPort..."
        $reachableOnVmnet8 = Test-DevServerPort -ComputerName $vmnet8Address -Port $devServerPort
        if (-not $reachableOnVmnet8) {
            $reachableOnOriginalHost = Test-DevServerPort -ComputerName $parsedUrl.Host -Port $devServerPort
            if ($reachableOnOriginalHost) {
                throw (
                    "Dev server on port $devServerPort answers on '$($parsedUrl.Host)' but NOT on " +
                    "$vmnet8Address (the VMware VMnet8 address the iOS guest reaches this machine " +
                    "through, and the address the Android emulator's 10.0.2.2 alias resolves to as " +
                    "well). This is the default loopback-bind behaviour of most dev servers -- fix by " +
                    "binding to all interfaces, not just 127.0.0.1: " +
                    "Vite -> 'vite --host 0.0.0.0' (or 'server: { host: true }' in vite.config); " +
                    "Next.js -> 'next dev -H 0.0.0.0'; " +
                    'Create React App / most others -> "host": "0.0.0.0" in the dev-server config, ' +
                    "or HOST=0.0.0.0 in the environment. " +
                    'Pass -SkipReachabilityCheck once that is fixed, or if this diagnosis is wrong for your setup.'
                )
            }
            throw (
                "Nothing answers on port $devServerPort, on '$($parsedUrl.Host)' or on $vmnet8Address. " +
                'Start the dev server, or confirm the port in -Url, before opening it in the lab. ' +
                'Pass -SkipReachabilityCheck to bypass this check.'
            )
        }
        Say "  dev server reachable on ${vmnet8Address}:${devServerPort}" 'Green'
    }

    $overallOk = $true

    if ($wantsAndroid) {
        $androidUrl = if ($needsTranslation) { New-RewrittenUrl -Source $parsedUrl -NewHost '10.0.2.2' } else { $Url }
        Say "Android: $androidUrl"
        try {
            $deviceId = Open-AndroidUrl -TargetUrl $androidUrl -DeviceId $AndroidDeviceId
            Say "  opened on $deviceId" 'Green'
            $script:Facts.android = [ordered]@{ url = $androidUrl; deviceId = $deviceId; ok = $true; error = $null }
        } catch {
            $overallOk = $false
            $script:Facts.android = [ordered]@{ url = $androidUrl; deviceId = $AndroidDeviceId; ok = $false; error = $_.Exception.Message }
            Say "  FAILED: $($_.Exception.Message)" 'Red'
        }
    }

    if ($wantsIos) {
        $iosUrl = if ($needsTranslation) { New-RewrittenUrl -Source $parsedUrl -NewHost $vmnet8Address } else { $Url }
        Say "iOS: $iosUrl"
        try {
            Open-IosUrl -TargetUrl $iosUrl -GuestAddress $guest.address -Udid $IosUdid
            Say "  opened on simulator '$IosUdid'" 'Green'
            $script:Facts.ios = [ordered]@{ url = $iosUrl; udid = $IosUdid; ok = $true; error = $null }
        } catch {
            $overallOk = $false
            $script:Facts.ios = [ordered]@{ url = $iosUrl; udid = $IosUdid; ok = $false; error = $_.Exception.Message }
            Say "  FAILED: $($_.Exception.Message)" 'Red'
        }
    }

    Write-Host ''
    if ($overallOk) { Say 'DONE' 'Green' } else { Say 'DONE WITH FAILURES' 'Red' }
    Emit-Result -Ok $overallOk
    if ($overallOk) { exit 0 } else { exit 1 }
}
catch {
    $message = $_.Exception.Message
    Say "OPEN FAILED: $message" 'Red'
    Emit-Result -Ok $false
    exit 1
}
finally {
    if ($ownedLeaseId) {
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'Enter-MobileLabLease.ps1') -Action Release -LeaseId $ownedLeaseId -Json | Out-Null
    }
}
