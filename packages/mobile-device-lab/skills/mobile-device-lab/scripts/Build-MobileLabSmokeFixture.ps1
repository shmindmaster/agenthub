#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GuestIp,
    [string]$SshHost = 'macvm',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$fixtureSource = Join-Path $packageRoot 'fixtures\smoke-app'
$syncScript = Join-Path $PSScriptRoot 'Sync-RepoToGuest.ps1'
# Native CMake object paths exceed Windows' practical limit under the user
# profile. Keep this disposable build root intentionally short.
$cacheRoot = 'C:\Temp\mlab'
$runRoot = Join-Path $cacheRoot 'smoke'
$guestPath = '~/mobile-lab/smoke-fixture'
$androidPackage = 'test.agenthub.mobilelab.smoke'
$iosBundleId = 'test.agenthub.mobilelab.smoke'

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$FilePath exited $LASTEXITCODE" }
}

try {
    if (-not (Test-Path -LiteralPath $fixtureSource)) { throw "Synthetic fixture missing: $fixtureSource" }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureSource '*') -Destination $runRoot -Recurse -Force
    Invoke-Checked git @('-C', $runRoot, 'init', '--quiet')
    Invoke-Checked git @('-C', $runRoot, 'add', '--all')
    Invoke-Checked git @('-C', $runRoot, '-c', 'user.name=AgentHub Mobile Lab', '-c', 'user.email=mobile-lab@localhost', 'commit', '--allow-empty', '--quiet', '-m', 'Synthetic fixture payload')

    Push-Location $runRoot
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $runRoot 'node_modules'))) {
            Invoke-Checked npm @('ci', '--no-audit', '--no-fund')
        }
        Invoke-Checked npx @('expo', 'prebuild', '--platform', 'android', '--no-install')
        $priorTemp = $env:TEMP
        $priorTmp = $env:TMP
        $env:TEMP = 'C:\Temp'
        $env:TMP = 'C:\Temp'
        New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
        try {
            Push-Location (Join-Path $runRoot 'android')
            try {
                Invoke-Checked (Join-Path $runRoot 'android\gradlew.bat') @(':app:assembleRelease', '-PreactNativeArchitectures=x86_64')
            }
            finally { Pop-Location }
        }
        finally {
            $env:TEMP = $priorTemp
            $env:TMP = $priorTmp
        }
    }
    finally { Pop-Location }

    $apk = Get-ChildItem -LiteralPath (Join-Path $runRoot 'android\app\build\outputs\apk\release') -Filter '*.apk' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $apk) { throw 'Android build completed without a release APK.' }

    & $syncScript -RepoPath $runRoot -GuestPath $guestPath -SshHost $SshHost -SshHostName $GuestIp
    $sshBase = @('-o', "HostName=$GuestIp", '-o', "HostKeyAlias=$SshHost", '-o', 'BatchMode=yes', $SshHost)
    $activeGuestBuilds = @(& ssh @sshBase "ps ax -o command= | grep -E '[x]codebuild|[p]od install|[e]xpo prebuild'" 2>$null)
    $foreignBuilds = @($activeGuestBuilds | Where-Object { $_ -notmatch '/mobile-lab/smoke-fixture/' })
    if ($foreignBuilds.Count) {
        throw "Another guest build is active; wait for it instead of competing for the software-rendered VM: $($foreignBuilds -join ' | ')"
    }
    & ssh @sshBase "bash ~/mobile-lab/run-smoke-fixture-build.sh start $guestPath"
    if ($LASTEXITCODE -ne 0) { throw "Could not start the guest-owned iOS fixture build (ssh exit $LASTEXITCODE)." }
    $deadline = (Get-Date).AddMinutes(45)
    $guestBuildExit = $null
    while ((Get-Date) -lt $deadline) {
        $guestState = [string](& ssh @sshBase 'bash ~/mobile-lab/run-smoke-fixture-build.sh status' 2>$null)
        if ($guestState -match 'DONE:(\d+)') { $guestBuildExit = [int]$Matches[1]; break }
        if ($guestState -notmatch 'RUNNING|STARTED') { throw "Unexpected guest build state: $guestState" }
        Start-Sleep -Seconds 15
    }
    $guestLog = @(& ssh @sshBase 'bash ~/mobile-lab/run-smoke-fixture-build.sh log' 2>$null)
    $guestLog | ForEach-Object { Write-Host $_ }
    if ($null -eq $guestBuildExit) { throw 'Guest iOS fixture build timed out after 45 minutes.' }
    if ($guestBuildExit -ne 0) { throw "Guest iOS fixture build exited $guestBuildExit." }

    $result = [ordered]@{
        ok = $true
        androidApk = $apk
        androidPackage = $androidPackage
        iosBundleId = $iosBundleId
        guestPath = $guestPath
        localBuildRoot = $runRoot
    }
    if ($Json) { Write-Output ($result | ConvertTo-Json -Compress) }
    else { $result }
}
catch {
    $failure = [ordered]@{
        ok = $false
        stage = 'synthetic-fixture-build'
        error = $_.Exception.Message
        remedy = 'Verify Node/Expo/Android SDK, guest SSH, Xcode, and the booted simulator, then rerun Test-MobileLab.ps1 -Deep -Json.'
        localBuildRoot = $runRoot
    }
    if ($Json) { Write-Output ($failure | ConvertTo-Json -Compress) }
    else { Write-Error $failure.error }
    exit 1
}
