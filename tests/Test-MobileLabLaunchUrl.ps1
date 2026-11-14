#Requires -Version 5.1
<#
Behavior tests for Test-MobileLabLaunchUrl (SH-4390): the development-client
deep link a lab profile uses to open the Metro bundle must be well-formed,
and a health-sensitive app may only point it at the worker itself. Local and
non-mutating; starts nothing.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
Import-Module (Join-Path $repoRoot 'packages\mobile-development\MobileDevelopment.psm1') -Force

$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name -- $Detail" }
}
function Throws([scriptblock]$Block) {
    try { & $Block | Out-Null; return $false } catch { return $true }
}

$rigLink = 'exp+abacare://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A8081'

Report 'the ABACare rig link passes the health-sensitive fence' `
    (Test-MobileLabLaunchUrl -LaunchUrl $rigLink -HealthSensitive)

# The driver passes the switch with a colon and an explicit value; a space
# there leaves $true positional and fails binding. Lock the driver's form.
Report 'the driver call form (-HealthSensitive:$true) binds and passes' `
    (Test-MobileLabLaunchUrl -LaunchUrl $rigLink -HealthSensitive:$true)

Report 'localhost and loopback Metro addresses pass the fence' `
    ((Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8081' -HealthSensitive) -and `
     (Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?url=http%3A%2F%2F127.0.0.1%3A8081' -HealthSensitive))

Report 'a non-local Metro address is refused for a health-sensitive app' `
    (Throws { Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?url=http%3A%2F%2F192.168.1.5%3A8081' -HealthSensitive })

Report 'a non-local Metro address is allowed when the app is not health-sensitive' `
    (Test-MobileLabLaunchUrl -LaunchUrl 'exp+other://expo-development-client/?url=https%3A%2F%2Fstaging.example.com%3A8081')

Report 'a link without a url= parameter is refused' `
    (Throws { Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/' })

Report 'an ordinary app deep link is refused' `
    (Throws { Test-MobileLabLaunchUrl -LaunchUrl 'abacare://conversations' })

Report 'a non-http Metro protocol is refused' `
    (Throws { Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?url=ftp%3A%2F%2F10.0.2.2%3A8081' })

# The rig link carries Expo dev-menu flags beside url= (SH-4390): the fence
# must parse the query, not swallow the flags into the Metro address.
Report 'a link with dev-menu flags beside url= passes the health-sensitive fence' `
    (Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A8081&disableOnboarding=1&disableFab=1&disableAutoLaunch=1' -HealthSensitive)

Report 'query parameter order does not matter (flags before url=)' `
    (Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?disableOnboarding=1&url=http%3A%2F%2F10.0.2.2%3A8081' -HealthSensitive)

Report 'a query string without url= is refused' `
    (Throws { Test-MobileLabLaunchUrl -LaunchUrl 'exp+abacare://expo-development-client/?disableOnboarding=1' })

# The committed profile must satisfy the same fence the driver applies.
$contract = Get-MobileDevelopmentContract
$profile = $contract.remoteAndroid.apps | Where-Object { $_.productId -eq 'abacare' } |
    ForEach-Object { $_.profiles.'preview-rig' }
Report 'the committed preview-rig profile carries a launchUrl that passes the fence' `
    ((-not [string]::IsNullOrWhiteSpace([string]$profile.launchUrl)) -and `
     (Test-MobileLabLaunchUrl -LaunchUrl ([string]$profile.launchUrl) -HealthSensitive))

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
