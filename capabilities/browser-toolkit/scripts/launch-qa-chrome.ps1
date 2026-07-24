[CmdletBinding()]
param(
    [ValidateSet('Persistent', 'Clean')]
    [string]$Mode = 'Persistent',

    [ValidateRange(1024, 65535)]
    [int]$Port = 9333,

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Instance = 'shared',

    [string]$StartUrl = 'about:blank'
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$stateRoot = Join-Path $env:LOCALAPPDATA 'browser-toolkit'
$persistentProfile = if ($Instance -eq 'shared') {
    Join-Path $stateRoot 'chrome-qa-profile'
} else {
    Join-Path (Join-Path $stateRoot 'chrome-qa-profiles') $Instance
}
$profile = if ($Mode -eq 'Clean') {
    Join-Path (Join-Path $stateRoot 'ephemeral-profiles') ([guid]::NewGuid().ToString('N'))
} else {
    $persistentProfile
}

$resolvedStateRoot = [IO.Path]::GetFullPath($stateRoot)
$resolvedProfile = [IO.Path]::GetFullPath($profile)
if (-not $resolvedProfile.StartsWith($resolvedStateRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Resolved profile path escaped the toolkit state root: $resolvedProfile"
}
New-Item -ItemType Directory -Path $resolvedProfile -Force | Out-Null

$existingQaChrome = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine.Contains("--remote-debugging-port=$Port") -and
        $_.CommandLine.Contains("--user-data-dir=$resolvedProfile")
    } |
    Select-Object -First 1
if ($existingQaChrome) {
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 | Out-Null
        Write-Host "Reusing dedicated QA Chrome profile: $resolvedProfile"
        Write-Host "CDP endpoint: http://127.0.0.1:$Port"
        return
    } catch {
        throw "A QA Chrome process exists for $resolvedProfile but its CDP endpoint is unavailable. Close that exact QA process before retrying."
    }
}

$chromeCandidates = @(@(
    (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

if (-not $chromeCandidates) {
    throw 'Google Chrome was not found in the standard Windows locations.'
}
$chrome = $chromeCandidates[0]
$arguments = @(
    "--remote-debugging-address=127.0.0.1",
    "--remote-debugging-port=$Port",
    "--user-data-dir=$resolvedProfile",
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-sync',
    '--window-size=1440,1000',
    $StartUrl
)

Write-Warning @"
The connected agent can see every tab and the DOM, accessibility tree, cookies,
storage, console, and network activity available to this dedicated QA profile.
Use synthetic identities and data. Do not sign into personal services.
"@
Start-Process -FilePath $chrome -ArgumentList $arguments -WindowStyle Normal
Write-Host "Started dedicated QA Chrome profile: $resolvedProfile"
Write-Host "CDP endpoint: http://127.0.0.1:$Port"
if ($Mode -eq 'Clean') {
    Write-Host 'This profile is not automatically deleted. Close Chrome, verify the path, then remove it manually when evidence retention permits.'
}
