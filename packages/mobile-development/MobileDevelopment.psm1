#Requires -Version 5.1

$script:PackageRoot = $PSScriptRoot
$script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $script:PackageRoot '..\..'))

function Read-AgentHubJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $script:RepoRoot ($RelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "AgentHub authority is missing: $path"
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-MobileDevelopmentContract {
    [CmdletBinding()]
    param()
    Read-AgentHubJson -RelativePath 'registry/mobile-development.json'
}

function Get-MobileScopeContract {
    [CmdletBinding()]
    param()
    Read-AgentHubJson -RelativePath 'registry/mobile-scope.json'
}

function Get-MobileScopeProduct {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [switch]$RequireInclude
    )

    $scope = Get-MobileScopeContract
    $matches = @($scope.products | Where-Object { [string]$_.productId -eq $ProductId })
    if ($matches.Count -ne 1) {
        throw "Product '$ProductId' is absent from registry/mobile-scope.json. Absence never means eligible; ask the owner to classify it."
    }
    $product = $matches[0]
    if ($RequireInclude -and [string]$product.bucket -ne 'include') {
        $detail = switch ([string]$product.bucket) {
            'evaluateLater' { 'Native value is unproven; no mobile identifier may be reserved.' }
            'excludedPendingReposition' { 'Mobile identity is frozen until the recorded owner-only exit condition is met.' }
            'noNative' { 'This product has no intended native mobile surface.' }
            default { 'The product is not in the include bucket.' }
        }
        throw "Product '$ProductId' is classified '$($product.bucket)', not 'include'. $detail"
    }
    $product
}

function Get-AppiumMcpAuthority {
    [CmdletBinding()]
    param()

    $mcps = Read-AgentHubJson -RelativePath 'registry/mcps.json'
    $matches = @($mcps.mcpServers | Where-Object { [string]$_.id -eq 'appium-mobile' })
    if ($matches.Count -ne 1) { throw "Expected exactly one registry/mcps.json server with id 'appium-mobile'; found $($matches.Count)." }
    $server = $matches[0]
    $packageArgs = @($server.args | Where-Object { [string]$_ -match '^appium-mcp@[^@]+$' })
    if ([string]$server.command -ne 'npx' -or $packageArgs.Count -ne 1) {
        throw "registry/mcps.json#appium-mobile must declare exactly one pinned appium-mcp@<version> argument invoked by npx."
    }
    [pscustomobject]@{
        Server = $server
        Package = [string]$packageArgs[0]
        Version = ([string]$packageArgs[0]).Substring('appium-mcp@'.Length)
    }
}

function Get-MobileDevelopmentRepoRoot {
    [CmdletBinding()]
    param()
    $script:RepoRoot
}

function Get-MobileDevelopmentPackageRoot {
    [CmdletBinding()]
    param()
    $script:PackageRoot
}

function Get-MobileDevelopmentExpectation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('android', 'ios', 'guestAppium', 'xcuitest')][string]$Name)
    (Get-MobileDevelopmentContract).expectations.$Name
}

function Get-MobileDevelopmentResource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $matches = @((Get-MobileDevelopmentContract).resources | Where-Object { [string]$_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Expected exactly one mobile-development resource '$Id'; found $($matches.Count)." }
    $matches[0]
}

function Get-MobileVmxFacts {
    [CmdletBinding()]
    param()

    $contract = Get-MobileDevelopmentContract
    $vmx = ([string]$contract.authorities.vmx) -replace '/', '\'
    if (-not (Test-Path -LiteralPath $vmx -PathType Leaf)) {
        return [pscustomobject]@{ path = $vmx; exists = $false; vcpu = $null; memoryMb = $null }
    }
    $text = Get-Content -LiteralPath $vmx -Raw -Encoding UTF8
    $vcpu = if ($text -match '(?m)^numvcpus\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
    $memory = if ($text -match '(?m)^memsize\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
    [pscustomobject]@{ path = $vmx; exists = $true; vcpu = $vcpu; memoryMb = $memory }
}

function Get-MobileRuntimeProcessMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('android', 'ios', 'both')][string]$Platform,
        [object[]]$Processes,
        [string]$AndroidSdkRoot,
        [AllowEmptyString()][string]$AvdConfigText
    )

    if (-not $PSBoundParameters.ContainsKey('Processes')) {
        $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object Name, ProcessId, ExecutablePath, CommandLine)
    }
    $result = [ordered]@{ kind = 'runtime'; platform = $Platform; startedResources = $false }

    if ($Platform -in @('android', 'both')) {
        $expectation = Get-MobileDevelopmentExpectation -Name android
        $toolchain = Get-MobileDevelopmentResource -Id 'windows-mobile-toolchain'
        if (-not $AndroidSdkRoot) {
            foreach ($name in @($toolchain.discovery.androidSdkEnvironment)) {
                $candidate = [Environment]::GetEnvironmentVariable([string]$name)
                if ($candidate) { $AndroidSdkRoot = $candidate; break }
            }
        }
        $sdkRoot = if ($AndroidSdkRoot) { [IO.Path]::GetFullPath($AndroidSdkRoot) } else { $null }
        $adbPath = if ($sdkRoot) { [IO.Path]::GetFullPath((Join-Path $sdkRoot (([string]$toolchain.discovery.adbRelativePath) -replace '/', '\'))) } else { $null }
        $emulatorRoot = if ($sdkRoot) { [IO.Path]::GetFullPath((Join-Path $sdkRoot 'emulator')) } else { $null }
        $avdName = [string]$expectation.avdName
        $avdPattern = '(?i)(?:^|\s)-avd(?:\s+|=)"?' + [regex]::Escape($avdName) + '"?(?:\s|$)'
        $adb = @($Processes | Where-Object {
            [string]$_.Name -ieq 'adb.exe' -and $adbPath -and [string]$_.ExecutablePath -and
            [IO.Path]::GetFullPath([string]$_.ExecutablePath).Equals($adbPath, [StringComparison]::OrdinalIgnoreCase)
        })
        $emulator = @($Processes | Where-Object {
            $nameMatches = [string]$_.Name -match '^emulator(64-[A-Za-z]+)?\.exe$|^qemu-system-.*\.exe$'
            $pathMatches = $false
            if ($nameMatches -and $emulatorRoot -and [string]$_.ExecutablePath) {
                $candidatePath = [IO.Path]::GetFullPath([string]$_.ExecutablePath)
                $pathMatches = $candidatePath.StartsWith(($emulatorRoot.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)
            }
            $nameMatches -and $pathMatches -and [string]$_.CommandLine -match $avdPattern
        })
        $avdConfigPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) ".android\avd\$avdName.avd\config.ini"
        if (-not $PSBoundParameters.ContainsKey('AvdConfigText')) {
            $AvdConfigText = if (Test-Path -LiteralPath $avdConfigPath -PathType Leaf) { Get-Content -LiteralPath $avdConfigPath -Raw -Encoding UTF8 } else { '' }
        }
        $apiPattern = '(?im)^\s*(?:target|image\.sysdir(?:\.\d+)?)\s*=.*android-' + [regex]::Escape([string]$expectation.apiLevel) + '(?:[\\/]|$)'
        $apiMatches = [bool]($AvdConfigText -match $apiPattern)
        $result.android = [ordered]@{
            ready = ($adb.Count -gt 0 -and $emulator.Count -gt 0 -and $apiMatches)
            adbServerProcesses = @($adb | ForEach-Object ProcessId)
            emulatorProcesses = @($emulator | ForEach-Object ProcessId)
            canonicalAdbPath = $adbPath
            canonicalAvd = $avdName
            canonicalApiLevel = [int]$expectation.apiLevel
            avdConfigPath = $avdConfigPath
            avdConfigMatchesApi = $apiMatches
            expectation = $expectation
        }
    }

    if ($Platform -in @('ios', 'both')) {
        $vmxFacts = Get-MobileVmxFacts
        $canonicalVmx = ([IO.Path]::GetFullPath([string]$vmxFacts.path)).Replace('/', '\')
        $escapedVmx = [regex]::Escape($canonicalVmx)
        $vmxTokenPattern = '(?i)(?:^|\s)(?:"' + $escapedVmx + '"|' + $escapedVmx + ')(?=\s|$)'
        $vm = @($Processes | Where-Object {
            if ([string]$_.Name -ine 'vmware-vmx.exe' -or -not [string]$_.CommandLine) { return $false }
            ([string]$_.CommandLine).Replace('/', '\') -match $vmxTokenPattern
        })
        $result.ios = [ordered]@{
            ready = ($vm.Count -gt 0)
            vmProcesses = @($vm | ForEach-Object ProcessId)
            canonicalVmxPath = $canonicalVmx
            vmx = $vmxFacts
            expectation = Get-MobileDevelopmentExpectation -Name ios
            note = 'Guest SSH, Simulator, and Appium readiness require a non-starting network probe after the canonical guest is already running.'
        }
    }

    $selected = @()
    if ($result.android) { $selected += [bool]$result.android.ready }
    if ($result.ios) { $selected += [bool]$result.ios.ready }
    $result.ready = ($selected.Count -gt 0 -and @($selected | Where-Object { -not $_ }).Count -eq 0)
    [pscustomobject]$result
}

Export-ModuleMember -Function Read-AgentHubJson, Get-MobileDevelopmentContract, Get-MobileScopeContract, Get-MobileScopeProduct, Get-AppiumMcpAuthority, Get-MobileDevelopmentRepoRoot, Get-MobileDevelopmentPackageRoot, Get-MobileDevelopmentExpectation, Get-MobileDevelopmentResource, Get-MobileVmxFacts, Get-MobileRuntimeProcessMatch
