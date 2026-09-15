#Requires -Version 5.1
<#
.SYNOPSIS
Canonical entrypoint for AgentHub mobile development.

.DESCRIPTION
Run without arguments for usage. Product-targeting commands require the first
argument after the command to be a product in registry/mobile-scope.json's
include bucket. The fixed local synthetic fixture used by `test deep` is the
only product-scope exception.
#>

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MobileDevelopment.psm1') -Force

$tokens = [Collections.Generic.List[string]]::new()
foreach ($value in @($args)) { $tokens.Add([string]$value) }
$jsonIndex = $tokens.FindIndex([Predicate[string]] { param($item) $item -ieq '-Json' })
$Json = $jsonIndex -ge 0
while ($jsonIndex -ge 0) {
    $tokens.RemoveAt($jsonIndex)
    $jsonIndex = $tokens.FindIndex([Predicate[string]] { param($item) $item -ieq '-Json' })
}

function Write-Usage {
    @'
mobile.ps1 catalog [query] [-Json]
mobile.ps1 scope <productId> [-Json]
mobile.ps1 check files|runtime [android|ios|both] [-Deep] [-Json]
mobile.ps1 mcp enable|disable <claude|codex> [-Json]
mobile.ps1 start android|ios|both [Start-MobileLab options] [-Json]
mobile.ps1 test deep [-Json]
mobile.ps1 sync <productId> -RepoPath <path> -GuestPath <path> [Sync-RepoToGuest options] [-Json]
mobile.ps1 metro <productId> -ProjectPath <path> [Start-MobileLabMetro options] [-Json]
mobile.ps1 web <productId> -ProjectPath <path> -Url <url> [Open-MobileLabWebTarget options] [-Json]

Use `catalog` to discover the closed primary/specialty surface. Physical
devices, signing, push, deep links, observability, EAS, and stores remain
specialty work behind their recorded gates.
'@ | Write-Host
}

function Write-OutputObject {
    param([Parameter(Mandatory)][object]$Value)
    if ($Json) { Write-Output ($Value | ConvertTo-Json -Depth 20 -Compress) }
    else { $Value | Format-List | Out-Host }
}

function Take-Token([string]$Name) {
    if ($tokens.Count -eq 0) { throw "Missing $Name." }
    $value = $tokens[0]
    $tokens.RemoveAt(0)
    $value
}

function Require-NoTokens {
    if ($tokens.Count -gt 0) { throw "Unexpected argument(s): $($tokens -join ' ')" }
}

function Resolve-ProductForCommand([string]$Verb) {
    $productId = Take-Token "$Verb productId"
    Get-MobileScopeProduct -ProductId $productId -RequireInclude
}

function Get-NamedTokenValue([string]$Name, [switch]$Remove) {
    $indexes = @(for ($i = 0; $i -lt $tokens.Count; $i++) { if ($tokens[$i] -ieq $Name) { $i } })
    if ($indexes.Count -ne 1 -or $indexes[0] + 1 -ge $tokens.Count) { throw "Exactly one $Name value is required." }
    $index = $indexes[0]
    $value = [string]$tokens[$index + 1]
    if ($value.StartsWith('-')) { throw "$Name requires a value." }
    if ($Remove) { $tokens.RemoveAt($index + 1); $tokens.RemoveAt($index) }
    $value
}

function Resolve-ToolPath([string]$Command) {
    $resolved = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { return [string]$resolved.Source }
    $null
}

function Invoke-MobileDelegate([string]$Script, [string[]]$Arguments) {
    # Array splatting into a PowerShell script does not rebind strings such as
    # '-Json' or '-Deep' as named parameters; it passes them positionally. Run
    # the retained script through this process's own PowerShell host so its
    # native command-line binder preserves the public wrapper's named options.
    $hostExe = (Get-Process -Id $PID).Path
    & $hostExe -NoProfile -File $Script @Arguments
    exit $LASTEXITCODE
}

function Get-AndroidFilesCheck {
    $resource = Get-MobileDevelopmentResource -Id 'windows-mobile-toolchain'
    $sdkRoot = $null
    foreach ($name in @($resource.discovery.androidSdkEnvironment)) {
        $candidate = [Environment]::GetEnvironmentVariable([string]$name)
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $sdkRoot = $candidate; break }
    }
    $adb = if ($sdkRoot) { Join-Path $sdkRoot (([string]$resource.discovery.adbRelativePath) -replace '/', '\') } else { $null }
    $emulator = if ($sdkRoot) { Join-Path $sdkRoot (([string]$resource.discovery.emulatorRelativePath) -replace '/', '\') } else { $null }
    $node = Resolve-ToolPath ([string]$resource.discovery.nodeCommand)
    $javaHome = [Environment]::GetEnvironmentVariable([string]$resource.discovery.javaEnvironment)
    $java = if ($javaHome) { Join-Path $javaHome (([string]$resource.discovery.javaRelativePath) -replace '/', '\') } else { Resolve-ToolPath ([string]$resource.discovery.javaFallbackCommand) }
    [pscustomobject]@{
        platform = 'android'
        ready = [bool]($sdkRoot -and (Test-Path -LiteralPath $adb -PathType Leaf) -and (Test-Path -LiteralPath $emulator -PathType Leaf) -and $node -and $java -and (Test-Path -LiteralPath $java -PathType Leaf))
        androidSdk = $sdkRoot
        adb = $adb
        adbExists = [bool]($adb -and (Test-Path -LiteralPath $adb -PathType Leaf))
        emulator = $emulator
        emulatorExists = [bool]($emulator -and (Test-Path -LiteralPath $emulator -PathType Leaf))
        node = $node
        java = $java
        startedResources = $false
    }
}

function Get-IosFilesCheck {
    $vmware = Get-MobileDevelopmentResource -Id 'vmware-workstation'
    $vmrun = @($vmware.discovery.vmrunPaths | ForEach-Object { ([string]$_) -replace '/', '\' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    $backup = Get-MobileDevelopmentResource -Id 'macos-guest-known-good-backup'
    $vmxFacts = Get-MobileVmxFacts
    $ssh = Resolve-ToolPath 'ssh'
    $guestScripts = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\guest'
    [pscustomobject]@{
        platform = 'ios'
        ready = [bool]($vmrun.Count -eq 1 -and $vmxFacts.exists -and $vmxFacts.vcpu -and $vmxFacts.memoryMb -and $ssh -and (Test-Path -LiteralPath (([string]$backup.path) -replace '/', '\') -PathType Container) -and (Test-Path -LiteralPath $guestScripts -PathType Container))
        vmrun = if ($vmrun.Count) { $vmrun[0] } else { $null }
        vmx = $vmxFacts
        knownGoodBackup = ([string]$backup.path) -replace '/', '\'
        knownGoodBackupExists = Test-Path -LiteralPath (([string]$backup.path) -replace '/', '\') -PathType Container
        ssh = $ssh
        guestScripts = $guestScripts
        startedResources = $false
    }
}

function Get-MobileRuntimeCheck([string]$Platform) {
    # This is deliberately process-table-only. Invoking `adb devices` starts
    # an adb server, and invoking a lab starter or vmrun start would turn a
    # read-only health check into a mutation. Deep readiness belongs to
    # `test deep`; this command reports only what is already running.
    Get-MobileRuntimeProcessMatch -Platform $Platform
}

function Invoke-MobileRuntimeHealthCheck([string]$Platform) {
    # Fail closed on the exact registry-backed process identities before any
    # adb, SSH, vmrun, Simulator, Xcode, or Appium probe can run. The retained
    # health gate repeats the same preflight so direct invocation is safe too.
    $processCheck = Get-MobileRuntimeCheck -Platform $Platform
    $invocation = Get-MobileRuntimeHealthInvocation -Platform $Platform -ProcessCheck $processCheck
    if (-not $invocation.delegate) {
        $result = [pscustomobject]@{
            kind = 'runtime'
            platform = $Platform
            mode = 'deep-health'
            ready = $false
            startedResources = $false
            delegated = $false
            processCheck = $processCheck
        }
        Write-OutputObject $result
        exit 1
    }

    $script = Join-Path $PSScriptRoot $invocation.scriptRelativePath
    $forward = @($invocation.arguments)
    if ($Json) { $forward += '-Json' }
    Invoke-MobileDelegate -Script $script -Arguments $forward
}

try {
    if ($tokens.Count -eq 0) { Write-Usage; exit 0 }
    $command = (Take-Token 'command').ToLowerInvariant()
    switch ($command) {
        'catalog' {
            $contract = Get-MobileDevelopmentContract
            $appium = Get-AppiumMcpAuthority
            $resolved = [ordered]@{
                appiumMcpServerId = [string]$appium.Server.id
                appiumMcpPackage = $appium.Package
                appiumMcpHosts = @($appium.Server.hosts)
                vmxHardware = Get-MobileVmxFacts
            }
            if ($tokens.Count -eq 0) {
                Write-OutputObject ([pscustomobject]@{ contract = $contract; resolved = $resolved })
                exit 0
            }
            $query = Take-Token 'catalog query'
            Require-NoTokens
            $matches = @($contract.agentSurface.primary) + @($contract.agentSurface.specialty) + @($contract.resources) + @($contract.services) + @($contract.taskMap.outOfScope) |
                Where-Object { ($_ | ConvertTo-Json -Depth 10 -Compress) -match [regex]::Escape($query) }
            if ($matches.Count -eq 0) { throw "Catalog query '$query' matched no canonical mobile record." }
            Write-OutputObject ([pscustomobject]@{ query = $query; matches = @($matches); resolved = $resolved })
            exit 0
        }
        'scope' {
            $product = Get-MobileScopeProduct -ProductId (Take-Token 'productId')
            Require-NoTokens
            $eligible = [string]$product.bucket -eq 'include'
            $result = [pscustomobject]@{
                productId = [string]$product.productId
                repository = [string]$product.repository
                bucket = [string]$product.bucket
                eligible = $eligible
                healthSensitive = [bool]$product.healthSensitive
                mobileIdentity = $product.mobileIdentity
                note = [string]$product.note
                decision = if ($eligible) { 'Proceed only within the canonical contract.' } elseif ([string]$product.bucket -eq 'noNative') { 'Stop: no native mobile surface is intended.' } else { 'Stop: this product is not eligible for native mobile work.' }
            }
            Write-OutputObject $result
            exit 0
        }
        'check' {
            $kind = (Take-Token 'check kind (files|runtime)').ToLowerInvariant()
            if ($kind -notin @('files', 'runtime')) { throw "Unknown check kind '$kind'. Expected files or runtime." }
            $deepIndex = $tokens.FindIndex([Predicate[string]] { param($item) $item -ieq '-Deep' })
            $deepRuntime = $deepIndex -ge 0
            while ($deepIndex -ge 0) {
                $tokens.RemoveAt($deepIndex)
                $deepIndex = $tokens.FindIndex([Predicate[string]] { param($item) $item -ieq '-Deep' })
            }
            $platform = if ($tokens.Count) { (Take-Token 'platform').ToLowerInvariant() } else { 'both' }
            if ($platform -notin @('android', 'ios', 'both')) { throw "Unknown platform '$platform'. Expected android, ios, or both." }
            Require-NoTokens
            if ($deepRuntime -and $kind -ne 'runtime') { throw '-Deep is valid only with check runtime.' }
            if ($deepRuntime) { Invoke-MobileRuntimeHealthCheck -Platform $platform }
            if ($kind -eq 'files') {
                $checks = @()
                if ($platform -in @('android', 'both')) { $checks += Get-AndroidFilesCheck }
                if ($platform -in @('ios', 'both')) { $checks += Get-IosFilesCheck }
                $result = [pscustomobject]@{ kind = 'files'; platform = $platform; ready = (@($checks | Where-Object { -not $_.ready }).Count -eq 0); startedResources = $false; checks = $checks }
            } else { $result = Get-MobileRuntimeCheck -Platform $platform }
            Write-OutputObject $result
            if ($result.ready) { exit 0 } else { exit 1 }
        }
        'mcp' {
            $action = (Take-Token 'MCP action (enable|disable)').ToLowerInvariant()
            $hostName = (Take-Token 'MCP host (claude|codex)').ToLowerInvariant()
            Require-NoTokens
            if ($action -notin @('enable', 'disable')) { throw "Unknown MCP action '$action'. Expected enable or disable." }
            if ($hostName -notin @('claude', 'codex')) { throw "Unknown MCP host '$hostName'. Appium is on demand for claude and codex only." }
            $plugin = 'mobile-development@agenthub'
            $executable = Resolve-ToolPath $hostName
            if (-not $executable) { throw "The native '$hostName' management CLI is not available on PATH." }
            $invokeNative = $true
            if ($hostName -eq 'claude') {
                $inventoryJson = (@(& $executable plugin list --json 2>$null) -join [Environment]::NewLine)
                $installed = @($inventoryJson | ConvertFrom-Json | Where-Object { [string]$_.id -eq $plugin })
                if ($action -eq 'enable' -and $installed.Count -eq 0) {
                    & $executable plugin install $plugin
                    if ($LASTEXITCODE -ne 0) { throw "claude native plugin install failed with exit $LASTEXITCODE." }
                    # Claude installs marketplace plugins enabled. Treat that
                    # resulting state as the requested enable; a redundant
                    # native enable exits non-zero and would make clean-state
                    # activation fail after a successful install.
                    $nativeArgs = @('plugin', 'install', $plugin)
                    $invokeNative = $false
                }
                else {
                    $nativeArgs = @('plugin', $action, $plugin)
                    if ($action -eq 'enable' -and [bool]$installed[0].enabled) { $invokeNative = $false }
                }
            } else {
                $nativeArgs = @('plugin', $(if ($action -eq 'enable') { 'add' } else { 'remove' }), $plugin)
            }
            if ($invokeNative) {
                & $executable @nativeArgs
                if ($LASTEXITCODE -ne 0) { throw "$hostName native plugin management failed with exit $LASTEXITCODE." }
            }
            $message = if ($action -eq 'enable') {
                "Appium was enabled for $hostName. Plugin/MCP loading is task-scoped: open a new $hostName task before using Appium. Disable it after mobile work so later tasks do not start an idle MCP process."
            } else {
                if ($hostName -eq 'claude') { "Appium was disabled for Claude. The canonical plugin remains installed-disabled for on-demand reuse. Existing tasks may retain what they loaded; open a new task to observe the disabled state." }
                else { "Appium was removed for Codex. Existing tasks may retain what they loaded; open a new task to observe the disabled state." }
            }
            Write-OutputObject ([pscustomobject]@{ ok = $true; host = $hostName; action = $action; nativeCommand = "$hostName $($nativeArgs -join ' ')"; newTaskRequired = $true; message = $message })
            exit 0
        }
        'start' {
            $platform = (Take-Token 'platform').ToLowerInvariant()
            if ($platform -notin @('android', 'ios', 'both')) { throw "Unknown platform '$platform'. Expected android, ios, or both." }
            $script = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\Start-MobileLab.ps1'
            $forward = @($tokens)
            if ($platform -eq 'android') { $forward += '-SkipIos' }
            elseif ($platform -eq 'ios') { $forward += '-SkipAndroid' }
            if ($Json) { $forward += '-Json' }
            Invoke-MobileDelegate -Script $script -Arguments $forward
        }
        'test' {
            $mode = (Take-Token 'test mode').ToLowerInvariant()
            if ($mode -ne 'deep') { throw "Unknown test mode '$mode'. The canonical infrastructure test is 'deep'." }
            Require-NoTokens
            $script = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\Test-MobileLab.ps1'
            $forward = @('-Deep')
            if ($Json) { $forward += '-Json' }
            Invoke-MobileDelegate -Script $script -Arguments $forward
        }
        'sync' {
            $product = Resolve-ProductForCommand 'sync'
            $repoPath = Get-NamedTokenValue -Name '-RepoPath'
            $null = Resolve-MobileProductTarget -Product $product -TargetKind repository -Path $repoPath
            $script = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1'
            $forward = @($tokens)
            if ($Json) { $forward += '-Json' }
            Invoke-MobileDelegate -Script $script -Arguments $forward
        }
        'metro' {
            $product = Resolve-ProductForCommand 'metro'
            $projectPath = Get-NamedTokenValue -Name '-ProjectPath'
            $null = Resolve-MobileProductTarget -Product $product -TargetKind project -Path $projectPath
            $script = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\Start-MobileLabMetro.ps1'
            $forward = @($tokens)
            if ($Json) { $forward += '-Json' }
            Invoke-MobileDelegate -Script $script -Arguments $forward
        }
        'web' {
            $product = Resolve-ProductForCommand 'web'
            $projectPath = Get-NamedTokenValue -Name '-ProjectPath' -Remove
            $null = Resolve-MobileProductTarget -Product $product -TargetKind project -Path $projectPath
            $url = [Uri](Get-NamedTokenValue -Name '-Url')
            if (-not $url.IsAbsoluteUri) { throw '-Url must be absolute.' }
            $script = Join-Path $PSScriptRoot 'skills\mobile-device-lab\scripts\Open-MobileLabWebTarget.ps1'
            $forward = @($tokens)
            if ($Json) { $forward += '-Json' }
            Invoke-MobileDelegate -Script $script -Arguments $forward
        }
        default { throw "Unknown command '$command'." }
    }
}
catch {
    $message = $_.Exception.Message
    if ($Json) { Write-Output ([pscustomobject]@{ ok = $false; error = $message } | ConvertTo-Json -Compress) }
    else {
        Write-Host "ERROR: $message" -ForegroundColor Red
        Write-Usage
    }
    exit 1
}
