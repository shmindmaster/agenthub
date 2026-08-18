#Requires -Version 5.1
<#
.SYNOPSIS
Run Metro on the Windows host and make it reachable from both simulators, so a
JavaScript change is a reload instead of a rebuild.

.DESCRIPTION
This is the lever the lab was missing. Every iOS run went through a Release
build in the macOS guest -- roughly forty minutes -- including runs where the
only thing that had changed was a line of TypeScript.

A Debug build carries no JavaScript bundle. React Native's own build script
short-circuits for Debug + simulator ("Skipping bundling in Debug for the
Simulator (since the packager bundles for you)"), so the app fetches its JS
from Metro at runtime. Build the native shell once; after that, editing JS and
reloading is seconds.

Running Metro HERE rather than in the guest matters for two reasons:

  speed     bundling happens on the host's real CPU instead of a
            software-rendered VM, and the files it serves are the ones being
            edited -- so there is no sync step in the loop at all

  config    Metro is what inlines EXPO_PUBLIC_* into the bundle. It was never
            Xcode. A guest that never received the gitignored .env therefore
            produced a *finished* binary with those values baked in as absent
            -- a build that succeeds and cannot work. With Metro on the host,
            .env is read from where it already is, and that whole failure mode
            stops existing rather than being worked around.

Reachability is the part that is easy to get wrong, because "localhost" means
something different in each target:

  Android emulator   the host is 10.0.2.2, and `adb reverse` is better still:
                     it forwards the emulator's own localhost:8081 to the
                     host, so no address rewriting is needed anywhere
  iOS simulator      lives inside the macOS guest, so the host is the Windows
                     VMnet8 adapter address -- 'localhost' there is the guest

So this script resolves the VMnet8 address, starts Metro advertising that
address, sets up `adb reverse`, and then proves the guest can actually reach
it by fetching Metro's status endpoint from inside the guest. A dev server that
is up on the host but unreachable from the device is the single most confusing
failure in this setup, and it presents as an app bug.

.PARAMETER ProjectPath
The Expo app directory (the one with package.json), on the Windows host.

.PARAMETER Port
Metro port. Default 8081.

.PARAMETER SkipAndroid
Do not set up adb reverse.

.PARAMETER SkipIos
Do not resolve or verify the macOS guest.

.PARAMETER Attach
After Metro is serving, point the booted iOS simulator at it via the Expo
development-client deep link.

.EXAMPLE
    .\Start-MobileLabMetro.ps1 -ProjectPath C:\Repos\shmindmaster\abacare\apps\mobile -Attach
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ProjectPath,
    [int] $Port = 8081,
    [switch] $SkipAndroid,
    [switch] $SkipIos,
    [switch] $Attach,
    [switch] $Json,
    [int] $ReadyTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MobileLabGuest.psm1') -Force

function Say { param([string]$Message, [string]$Colour = 'Gray') Write-Host $Message -ForegroundColor $Colour }

$result = [ordered]@{
    ok = $false; projectPath = $null; port = $Port; hostAddress = $null
    metroUrl = $null; guestAddress = $null; guestReachedMetro = $false
    androidReverse = $false; deepLink = $null; error = ''
}

function Emit-Result {
    if ($Json) { Write-Output ([pscustomobject]$result | ConvertTo-Json -Depth 5 -Compress) }
}

try {
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw "ProjectPath does not exist: $ProjectPath" }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $result.projectPath = $ProjectPath
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'package.json'))) {
        throw "No package.json in $ProjectPath. Point -ProjectPath at the app directory, not the repo root."
    }

    # ---------------------------------------------------------------- host address
    # The address the guest must use. Never 'localhost' and never 127.0.0.1:
    # inside the guest both of those are the guest.
    $hostAddress = $null
    try {
        $hostAddress = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.InterfaceAlias -like '*VMnet8*' } |
            Select-Object -First 1 -ExpandProperty IPAddress)
    } catch {
        $hostAddress = $null
    }
    if (-not $hostAddress) {
        # PowerShell 5.1 on a host without the NetTCPIP module still has ipconfig.
        $block = (& ipconfig) -join "`n"
        $m = [regex]::Match($block, '(?ms)VMnet8.*?IPv4 Address[^\d]*(\d+\.\d+\.\d+\.\d+)')
        if ($m.Success) { $hostAddress = $m.Groups[1].Value }
    }
    if (-not $hostAddress -and -not $SkipIos) {
        throw "Could not resolve the VMware VMnet8 host address. The iOS simulator has no way to reach Metro without it. Check that the 'VMware Network Adapter VMnet8' adapter is enabled, or pass -SkipIos to run Android-only."
    }
    $result.hostAddress = $hostAddress
    if ($hostAddress) { Say "host (as the guest sees it): $hostAddress" }

    $metroUrl = "http://${hostAddress}:$Port"
    $result.metroUrl = $metroUrl

    # ---------------------------------------------------------------- start Metro
    $statusUri = "$metroUrl/status"
    $alreadyServing = $false
    try {
        $probe = Invoke-WebRequest -Uri $statusUri -TimeoutSec 5 -UseBasicParsing
        # Metro answers /status with the literal string "packager-status:running".
        $alreadyServing = ($probe.Content -match 'packager-status:running')
    } catch {
        $alreadyServing = $false
    }

    if ($alreadyServing) {
        Say "Metro already serving at $metroUrl -- reusing it" 'Green'
    }
    else {
        Say "starting Metro in $ProjectPath"
        # REACT_NATIVE_PACKAGER_HOSTNAME is what makes the dev server advertise
        # an address the *device* can use. Without it Expo advertises whatever
        # it considers the LAN address, which on a host with several virtual
        # adapters is a coin flip, and the wrong choice fails as a blank app
        # rather than as an error.
        $env:REACT_NATIVE_PACKAGER_HOSTNAME = $hostAddress
        $env:EXPO_PACKAGER_HOSTNAME = $hostAddress

        # A separate window, not a job: Metro is long-lived and its log is the
        # thing you read when a bundle fails to build. Burying it in a
        # background job hides exactly the output that matters.
        $npx = (Get-Command npx -ErrorAction SilentlyContinue)
        if (-not $npx) { throw "npx not found on PATH. Install Node.js." }
        Start-Process -FilePath $npx.Source `
            -ArgumentList @('expo', 'start', '--dev-client', '--host', 'lan', '--port', "$Port") `
            -WorkingDirectory $ProjectPath | Out-Null

        Say "waiting for Metro to answer $statusUri"
        $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
        $serving = $false
        while ((Get-Date) -lt $deadline) {
            try {
                $probe = Invoke-WebRequest -Uri $statusUri -TimeoutSec 5 -UseBasicParsing
                if ($probe.Content -match 'packager-status:running') { $serving = $true; break }
            } catch { }
            Start-Sleep -Seconds 3
        }
        if (-not $serving) {
            throw "Metro did not answer $statusUri within ${ReadyTimeoutSeconds}s. Read the Metro window for the real error -- a failed dependency resolution looks like a hang from out here."
        }
        Say "Metro serving at $metroUrl" 'Green'
    }

    # ---------------------------------------------------------------- Android
    if (-not $SkipAndroid) {
        $androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
        $adb = if ($androidHome) { Join-Path $androidHome 'platform-tools\adb.exe' } else { $null }
        if ($adb -and (Test-Path -LiteralPath $adb)) {
            $devices = @(& $adb devices | Where-Object { $_ -match '^emulator-\d+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
            foreach ($device in $devices) {
                # `adb reverse` beats rewriting the host to 10.0.2.2: it makes
                # the emulator's own localhost:PORT reach the host, so the app
                # needs no special address and the default just works.
                & $adb -s $device reverse "tcp:$Port" "tcp:$Port" | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $result.androidReverse = $true
                    Say "android $device -> localhost:$Port reversed to host" 'Green'
                }
            }
            if ($devices.Count -eq 0) { Say 'android: no emulator attached (skipping reverse)' 'DarkGray' }
        }
        else {
            Say 'android: adb not found (ANDROID_HOME unset?) -- skipping reverse' 'DarkGray'
        }
    }

    # ---------------------------------------------------------------- iOS guest
    if (-not $SkipIos) {
        $guest = Resolve-MobileLabGuestAddress -SshHost 'macvm' -TimeoutSeconds 60
        $result.guestAddress = $guest.address
        Say "guest at $($guest.address) (via $($guest.source))"

        # The decisive check. Metro answering on the host proves nothing about
        # the guest: a dev server bound only to 127.0.0.1 is perfectly healthy
        # from a host browser and completely invisible to the simulator, and
        # that failure shows up as an app that will not load rather than as a
        # network error anyone would think to look for.
        $sshArgs = @('-o', "HostName=$($guest.address)", '-o', 'HostKeyAlias=macvm', '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes', 'macvm', "curl -s -m 8 $statusUri")
        $guestSaw = [string](@(& ssh @sshArgs 2>&1) -join ' ')
        $result.guestReachedMetro = ($guestSaw -match 'packager-status:running')

        if ($result.guestReachedMetro) {
            Say "guest reached Metro at $metroUrl" 'Green'
        }
        else {
            throw ("The guest could not reach Metro at $metroUrl (it saw: '$guestSaw'). " +
                   "Metro is serving on this host, so this is a binding or firewall problem, not an app problem. " +
                   "Check, in order: that Metro is bound to all interfaces rather than 127.0.0.1 (this script passes --host lan for that reason); " +
                   "that Windows Defender Firewall is not blocking inbound $Port on the VMnet8 network; " +
                   "and that $hostAddress is really this host's VMnet8 address.")
        }

        # expo-dev-client accepts its server URL as a deep link, so the same
        # installed build can be pointed at a different Metro without being
        # rebuilt. The scheme defaults to exp+<slug> when the app declares none.
        $scheme = $null
        foreach ($configName in @('app.json', 'app.config.json')) {
            $configPath = Join-Path $ProjectPath $configName
            if (Test-Path -LiteralPath $configPath) {
                try {
                    # -Encoding UTF8 is not decoration: without it Windows
                    # PowerShell 5.1 decodes this file in the ANSI code page, so a
                    # non-ASCII slug or scheme becomes mojibake -- and because the
                    # whole block is wrapped in an empty catch, that surfaces as
                    # "scheme not resolvable" rather than as a decoding error.
                    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($config.expo) {
                        if ($config.expo.scheme) { $scheme = @($config.expo.scheme)[0] }
                        elseif ($config.expo.slug) { $scheme = "exp+$($config.expo.slug)" }
                    }
                } catch { }
            }
            if ($scheme) { break }
        }
        if (-not $scheme) {
            # app.config.ts is executable TypeScript; reading it correctly means
            # running it, which this script will not do. Say so rather than
            # guessing a scheme that silently opens nothing.
            Say 'scheme: not resolvable from static config (app.config.ts is executable) -- use the dev launcher''s "Enter URL manually"' 'Yellow'
        }
        else {
            $encoded = [uri]::EscapeDataString($metroUrl)
            $result.deepLink = "$scheme`://expo-development-client/?url=$encoded"
            Say "deep link: $($result.deepLink)"

            if ($Attach) {
                $openArgs = @('-o', "HostName=$($guest.address)", '-o', 'HostKeyAlias=macvm', '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes', 'macvm', "xcrun simctl openurl booted '$($result.deepLink)'")
                & ssh @openArgs 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Say 'attached the booted simulator to this Metro' 'Green' }
                else { Say "could not open the deep link on the simulator (ssh exit $LASTEXITCODE); open it from the dev launcher instead" 'Yellow' }
            }
        }
    }

    $result.ok = $true
    Write-Host ''
    Say 'Metro ready. Edit JavaScript on this host; reload the app to see it. No rebuild, no sync.' 'Green'
    Say 'Rebuild only when native code changes: a new native dependency, an app.config/plugin change, or anything under ios/.' 'DarkGray'
    Emit-Result
    exit 0
}
catch {
    $result.error = $_.Exception.Message
    Write-Host ''
    Write-Host "FAILED: $($result.error)" -ForegroundColor Red
    Emit-Result
    exit 1
}
