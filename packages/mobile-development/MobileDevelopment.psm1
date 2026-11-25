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

function Resolve-MobileProductTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Product,
        [Parameter(Mandatory)][ValidateSet('repository', 'project')][string]$TargetKind,
        [Parameter(Mandatory)][string]$Path
    )

    if ([string]$Product.bucket -ne 'include') { throw "Product '$($Product.productId)' is not eligible for mobile work." }
    $repoStandard = Read-AgentHubJson -RelativePath 'registry/repo-standard.json'
    $repoName = ([string]$Product.repository -split '/')[-1]
    $authoritativeRoot = [IO.Path]::GetFullPath((Join-Path (([string]$repoStandard.fleetRoot -replace '/', '\')) $repoName))
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "Target path does not exist: $resolved" }

    $gitRoot = [string](& git -C $resolved rev-parse --show-toplevel 2>$null)
    $origin = [string](& git -C $resolved remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot) -or [string]::IsNullOrWhiteSpace($origin)) {
        throw "Target '$resolved' is not a Git checkout with an origin remote for '$($Product.repository)'."
    }
    $gitRoot = [IO.Path]::GetFullPath($gitRoot.Trim())
    $originIdentity = $origin.Trim() -replace '\\', '/' -replace '^git@[^:]+:', '' -replace '^https?://github\.com/', '' -replace '\.git$', ''
    if ($originIdentity -ine [string]$Product.repository) {
        throw "Product '$($Product.productId)' is bound to '$($Product.repository)', but target '$resolved' belongs to '$originIdentity'."
    }

    if ($TargetKind -eq 'repository') {
        if (-not $resolved.Equals($gitRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "RepoPath must be the checkout root '$gitRoot'; path escape rejected." }
        return [pscustomobject]@{ productId = [string]$Product.productId; repositoryRoot = $gitRoot; authoritativeRoot = $authoritativeRoot; target = $resolved }
    }

    if (-not $Product.PSObject.Properties['mobileIdentity'] -or [string]::IsNullOrWhiteSpace([string]$Product.mobileIdentity.appPath)) {
        throw "Product '$($Product.productId)' has no authoritative mobileIdentity.appPath binding."
    }
    $expectedProject = [IO.Path]::GetFullPath((Join-Path $gitRoot (([string]$Product.mobileIdentity.appPath -replace '/', '\'))))
    if (-not $resolved.Equals($expectedProject, [StringComparison]::OrdinalIgnoreCase)) {
        throw "ProjectPath '$resolved' does not match product '$($Product.productId)' project '$expectedProject'; foreign target or path escape rejected."
    }
    [pscustomobject]@{ productId = [string]$Product.productId; repositoryRoot = $gitRoot; authoritativeRoot = $authoritativeRoot; target = $resolved }
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
    param([Parameter(Mandatory)][ValidateSet('android', 'ios', 'guestAppium', 'xcuitest', 'xcode')][string]$Name)
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

function Get-MobileVmwareServiceState {
    <#
    .SYNOPSIS
        Read-only state of the Windows services the macOS guest depends on.
    .DESCRIPTION
        With these services stopped, vmrun start answers only "Unknown error",
        which names nothing. This reader turns that into named services, their
        status and start type, and the exact commands that fix them. It never
        starts or reconfigures anything; Repair-MobileVmwareServices does that,
        and only when an operator asks for it.
    .PARAMETER Services
        Synthetic service objects (Name, Status, StartType) for tests. When
        omitted, Get-Service is queried for each registry-declared name.
    #>
    [CmdletBinding()]
    param([object[]]$Services)

    $declared = @((Get-MobileDevelopmentResource -Id 'vmware-workstation').discovery.hostServices)
    $rows = foreach ($spec in $declared) {
        $name = [string]$spec.name
        # @() around the whole if: an if-expression unrolls a one-element
        # array, and Windows PowerShell 5.1 gives a bare PSCustomObject no
        # .Count, which would misreport every synthetic service as missing.
        $found = @(if ($PSBoundParameters.ContainsKey('Services')) {
            $Services | Where-Object { [string]$_.Name -eq $name } | Select-Object -First 1
        } else {
            Get-Service -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        })
        $present = ($found.Count -eq 1 -and $null -ne $found[0])
        [pscustomobject]@{
            name = $name
            displayName = [string]$spec.displayName
            role = [string]$spec.role
            present = $present
            status = if ($present) { [string]$found[0].Status } else { 'NotInstalled' }
            startType = if ($present) { [string]$found[0].StartType } else { $null }
        }
    }
    $rows = @($rows)
    $missing = @($rows | Where-Object { -not $_.present } | ForEach-Object name)
    $notRunning = @($rows | Where-Object { $_.present -and $_.status -ne 'Running' } | ForEach-Object name)
    $disabled = @($rows | Where-Object { $_.present -and $_.startType -eq 'Disabled' } | ForEach-Object name)

    $steps = [Collections.Generic.List[string]]::new()
    $fixable = @($rows | Where-Object { $_.present -and $_.status -ne 'Running' -and $_.startType -ne 'Disabled' })
    if ($fixable.Count) {
        $commands = @($fixable | ForEach-Object { "Set-Service -Name '$($_.name)' -StartupType Automatic; Start-Service -Name '$($_.name)'" }) -join '; '
        $steps.Add("From an elevated PowerShell run: $commands -- or rerun 'mobile.ps1 start ios -RepairVmwareServices' from an elevated PowerShell.")
    }
    if ($disabled.Count) {
        $steps.Add("$($disabled -join ', ') is Disabled, which is a deliberate administrator setting; the owner must re-enable it (-RepairVmwareServices will not override Disabled).")
    }
    if ($missing.Count) {
        $steps.Add("$($missing -join ', ') is not registered on this host; run the VMware Workstation installer's Repair option.")
    }

    [pscustomobject]@{
        ready = ($missing.Count -eq 0 -and $notRunning.Count -eq 0)
        services = $rows
        notRunning = $notRunning
        missing = $missing
        disabled = $disabled
        summary = (@($rows | ForEach-Object { if ($_.present) { '{0}={1}/{2}' -f $_.name, $_.status, $_.startType } else { '{0}=NotInstalled' -f $_.name } }) -join ', ')
        remediation = ($steps -join ' ')
    }
}

function Repair-MobileVmwareServices {
    <#
    .SYNOPSIS
        Explicit, bounded repair of the registry-declared VMware host services.
    .DESCRIPTION
        Runs only when an operator passes -RepairVmwareServices to
        Start-MobileLab.ps1. It touches only services that are declared in
        registry/mobile-development.json, installed, and not running. A Manual
        service becomes Automatic so the next host reboot does not reproduce
        the failure; a Disabled service is refused because disabling is an
        administrator decision. It never self-elevates: without an elevated
        session it fails with the commands to run, before changing anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [scriptblock]$IsElevated = {
            ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        },
        [scriptblock]$SetAutomatic = { param($Name) Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop },
        [scriptblock]$StartByName = { param($Name) Start-Service -Name $Name -ErrorAction Stop }
    )

    $declared = @((Get-MobileDevelopmentResource -Id 'vmware-workstation').discovery.hostServices | ForEach-Object { [string]$_.name })
    $targets = @($State.services | Where-Object { $_.name -in $declared -and $_.present -and $_.status -ne 'Running' })
    if ($targets.Count -eq 0) { return @() }

    $disabled = @($targets | Where-Object { $_.startType -eq 'Disabled' } | ForEach-Object name)
    if ($disabled.Count) {
        throw "Refusing to repair: $($disabled -join ', ') is Disabled. Disabling is an administrator decision; the owner must re-enable it. Nothing was changed."
    }
    if (-not [bool](& $IsElevated)) {
        throw "Repairing VMware host services needs an elevated PowerShell, and this one is not elevated. Nothing was changed. Remediation: $($State.remediation)"
    }

    $actions = [Collections.Generic.List[string]]::new()
    foreach ($target in $targets) {
        if ($target.startType -eq 'Manual') {
            & $SetAutomatic $target.name
            $actions.Add("$($target.name): start type Manual -> Automatic")
        }
        & $StartByName $target.name
        $actions.Add("$($target.name): started")
    }
    @($actions)
}

function Get-MobileRuntimeProcessMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('android', 'ios', 'both')][string]$Platform,
        [object[]]$Processes,
        [string]$AndroidSdkRoot,
        [AllowEmptyString()][string]$AvdConfigText,
        [object[]]$VmwareServices
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
        $avdHome = if ($env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android\avd' }
        $avdConfigPath = Join-Path $avdHome "$avdName.avd\config.ini"
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
        # Reported, not gated: a running guest no longer needs vmrun, but a
        # stopped one cannot start while these are down, so the operator sees
        # the cause next to "no VM process" instead of discovering it later.
        $serviceState = if ($PSBoundParameters.ContainsKey('VmwareServices')) { Get-MobileVmwareServiceState -Services $VmwareServices } else { Get-MobileVmwareServiceState }
        $result.ios = [ordered]@{
            ready = ($vm.Count -gt 0)
            vmProcesses = @($vm | ForEach-Object ProcessId)
            canonicalVmxPath = $canonicalVmx
            vmx = $vmxFacts
            vmwareHostServices = $serviceState
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

function Get-MobileRuntimeHealthInvocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('android', 'ios', 'both')][string]$Platform,
        [Parameter(Mandatory)][object]$ProcessCheck
    )

    $arguments = @('-RequireRunningProcesses')
    if ($Platform -eq 'android') { $arguments += '-SkipIos' }
    elseif ($Platform -eq 'ios') { $arguments += '-SkipAndroid' }
    [pscustomobject]@{
        platform = $Platform
        delegate = [bool]$ProcessCheck.ready
        startedResources = $false
        scriptRelativePath = 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
        arguments = $arguments
    }
}

Export-ModuleMember -Function Read-AgentHubJson, Get-MobileDevelopmentContract, Get-MobileScopeContract, Get-MobileScopeProduct, Resolve-MobileProductTarget, Get-AppiumMcpAuthority, Get-MobileDevelopmentRepoRoot, Get-MobileDevelopmentPackageRoot, Get-MobileDevelopmentExpectation, Get-MobileDevelopmentResource, Get-MobileVmxFacts, Get-MobileVmwareServiceState, Repair-MobileVmwareServices, Get-MobileRuntimeProcessMatch, Get-MobileRuntimeHealthInvocation
