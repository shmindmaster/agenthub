#Requires -Version 5.1
<#
.SYNOPSIS
    Sole path materializer for the AgentHub control plane.

.DESCRIPTION
    Expands path templates and rebases absolute destinations onto the target
    home. Sync scripts must not grow a second rebase. {{globalPolicy}} is not
    a path token.

    Platforms are windows, darwin, and linux -- the three operating systems
    coding agents actually ship for. Templates are stored with / separators.
    {userHome} (alias {userProfile}) is the home directory on every platform.
    {localData} (alias {localAppData}) and {roamingConfig} are the OS user
    data and config roots, which are the only layouts that actually split:
      windows  %LOCALAPPDATA% and %APPDATA%
      darwin   ~/Library/Application Support (no Local/Roaming split)
      linux    $XDG_DATA_HOME (~/.local/share) and $XDG_CONFIG_HOME (~/.config)
    A vendor path that is ~/.foo on every OS stays {userHome}/.foo. An
    AppData segment left in a template is a Windows install pin and is
    refused on darwin and linux rather than written as a fake path.

    Runtime is PowerShell 7+ on macOS and Linux. Windows PowerShell 5.1
    remains supported on Windows. This module does not invent iOS or
    Android host paths.

    Safety history: an unrebased absolute destination under -UserProfile
    wrote live host files. UNC and forward-slash drive paths are refused
    because they used to skip the drive-letter rebase.
#>

function Get-AgentHubHostPlatformId {
    if ($env:OS -eq 'Windows_NT') { return 'windows' }
    $mac = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue
    if ($mac -and $mac.Value) { return 'darwin' }
    $linux = Get-Variable -Name IsLinux -ErrorAction SilentlyContinue
    if ($linux -and $linux.Value) { return 'linux' }
    throw 'could not detect platform; pass -Platform windows, darwin, or linux'
}

function Get-AgentHubPlatformId {
    param([string]$Platform)
    if ([string]::IsNullOrWhiteSpace($Platform)) {
        return Get-AgentHubHostPlatformId
    }
    $id = $Platform.ToLowerInvariant()
    if ($id -notin @('windows', 'darwin', 'linux')) {
        throw "unsupported platform '$Platform'. Coding-agent hosts are windows, darwin, and linux."
    }
    return $id
}

function Get-AgentHubPlatformSeparator {
    param([string]$Platform)
    if ((Get-AgentHubPlatformId $Platform) -eq 'windows') { return '\' }
    return '/'
}

function Get-AgentHubDefaultHome {
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
    if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
    return $null
}

function Join-AgentHubPlatformPath {
    param(
        [string]$Platform,
        [string]$Base,
        [string]$Child
    )
    $platformId = Get-AgentHubPlatformId $Platform
    if ([string]::IsNullOrWhiteSpace($Child)) { return $Base.TrimEnd('\', '/') }
    if ($platformId -eq 'windows') {
        $relative = $Child.TrimStart('\', '/').Replace('/', '\')
        return Join-Path ($Base.TrimEnd('\')) $relative
    }
    $relative = $Child.TrimStart('\', '/').Replace('\', '/')
    return ($Base.TrimEnd('/') + '/' + $relative)
}

function Get-AgentHubPlatformDataRoots {
    param(
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][string]$UserHome
    )
    $platformId = Get-AgentHubPlatformId $Platform
    $root = $UserHome.TrimEnd('\', '/')
    switch ($platformId) {
        'windows' {
            return [pscustomobject]@{
                LocalData     = Join-Path $root 'AppData\Local'
                RoamingConfig = Join-Path $root 'AppData\Roaming'
            }
        }
        'darwin' {
            $support = $root + '/Library/Application Support'
            return [pscustomobject]@{
                LocalData     = $support
                RoamingConfig = $support
            }
        }
        'linux' {
            return [pscustomobject]@{
                LocalData     = $root + '/.local/share'
                RoamingConfig = $root + '/.config'
            }
        }
    }
}

function Convert-AgentHubPathSeparators {
    param(
        [string]$Path,
        [string]$Platform
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ((Get-AgentHubPlatformId $Platform) -eq 'windows') {
        return $Path.Replace('/', '\')
    }
    return $Path.Replace('\', '/')
}

function Get-AgentHubProfileSettings {
    param([string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { return $null }
    $path = Join-Path $RepositoryRoot 'agenthub.profile.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-AgentHubNormalizedDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $trimmed = $Path.TrimEnd('\', '/')
    # A POSIX absolute must not pass through Windows GetFullPath; that
    # rewrites /Users/synth onto the current drive.
    if ($trimmed.StartsWith('/') -and -not $trimmed.StartsWith('//')) {
        return $trimmed
    }
    return ([System.IO.Path]::GetFullPath($trimmed)).TrimEnd('\', '/')
}

function Get-AgentHubRequestedPlatform {
    param([string]$RepositoryRoot)
    $profile = Get-AgentHubProfileSettings -RepositoryRoot $RepositoryRoot
    if (-not $profile) { return $null }
    if (-not $profile.PSObject.Properties['platform']) { return $null }
    $value = [string]$profile.platform
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return (Get-AgentHubPlatformId $value)
}

function Resolve-AgentHubTargetUserProfile {
    param(
        [string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$RequestedUserProfile,
        [string]$InvokingUserProfile = $(Get-AgentHubDefaultHome)
    )
    $requested = Get-AgentHubNormalizedDirectory $RequestedUserProfile
    $invoking = Get-AgentHubNormalizedDirectory $InvokingUserProfile
    if ($invoking -and $requested -and -not $requested.Equals($invoking, [StringComparison]::OrdinalIgnoreCase)) {
        return $requested
    }
    $profile = Get-AgentHubProfileSettings -RepositoryRoot $RepositoryRoot
    if ($profile -and $profile.PSObject.Properties['userProfile'] -and
        -not [string]::IsNullOrWhiteSpace([string]$profile.userProfile) -and
        -not ([string]$profile.userProfile).Contains('{')) {
        return Get-AgentHubNormalizedDirectory ([string]$profile.userProfile)
    }
    return $requested
}

function Get-AgentHubRecordedUserProfile {
    param($AgentsDocument)
    if (-not $AgentsDocument) { return $null }
    if (-not $AgentsDocument.PSObject.Properties['userProfile']) { return $null }
    $raw = [string]$AgentsDocument.userProfile
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    if ($raw.Contains('{')) { return $null }
    return Get-AgentHubNormalizedDirectory $raw
}

function Resolve-AgentHubWindowsDataRoot {
    param(
        [string]$Target,
        [string]$Invoking,
        [string]$Inherited,
        [string]$LayoutRoot,
        [string]$InvokingLayoutName
    )
    $value = if ([string]::IsNullOrWhiteSpace($Inherited)) { $null } else { Get-AgentHubNormalizedDirectory $Inherited }
    $overridden = $Invoking -and -not $Target.Equals($Invoking, [StringComparison]::OrdinalIgnoreCase)
    if ($overridden -and $value -and $Invoking) {
        $invokingDefault = Get-AgentHubNormalizedDirectory (Join-Path $Invoking $InvokingLayoutName)
        if ($value.Equals($invokingDefault, [StringComparison]::OrdinalIgnoreCase)) {
            $value = $LayoutRoot
        }
    }
    if (-not $value) { return $LayoutRoot }
    return $value
}

function New-AgentHubPathBindingContext {
    param(
        [Parameter(Mandatory)][string]$TargetUserProfile,
        [string]$InvokingUserProfile = $(Get-AgentHubDefaultHome),
        [string]$RegistryUserProfile,
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$RoamingConfig = $env:APPDATA,
        [string]$Platform
    )
    $platformId = Get-AgentHubPlatformId $Platform
    $hostPlatform = Get-AgentHubHostPlatformId
    $foreign = $platformId -ne $hostPlatform

    if ($foreign) {
        $target = $TargetUserProfile.TrimEnd('\', '/')
        if (-not $target) {
            throw 'PathBinding requires a target user profile. Pass -UserProfile explicitly.'
        }
        $invoking = if ([string]::IsNullOrWhiteSpace($InvokingUserProfile)) { $null } else { $InvokingUserProfile.TrimEnd('\', '/') }
        $recorded = if ([string]::IsNullOrWhiteSpace($RegistryUserProfile)) { $null } else { $RegistryUserProfile.TrimEnd('\', '/') }
        $roots = Get-AgentHubPlatformDataRoots -Platform $platformId -UserHome $target
        return [pscustomobject]@{
            Platform              = $platformId
            TargetUserProfile     = $target
            InvokingUserProfile   = $invoking
            RegistryUserProfile   = $recorded
            EffectiveLocalAppData = $roots.LocalData
            EffectiveRoamingConfig = $roots.RoamingConfig
            ProfileOverridden     = [bool]($invoking -and -not $target.Equals($invoking, [StringComparison]::Ordinal))
        }
    }

    $target = Get-AgentHubNormalizedDirectory $TargetUserProfile
    if (-not $target) {
        throw 'PathBinding requires a target user profile. Pass -UserProfile explicitly.'
    }
    $invoking = Get-AgentHubNormalizedDirectory $InvokingUserProfile
    $recorded = Get-AgentHubNormalizedDirectory $RegistryUserProfile
    $layout = Get-AgentHubPlatformDataRoots -Platform $platformId -UserHome $target
    if ($platformId -eq 'windows') {
        $localApp = Resolve-AgentHubWindowsDataRoot -Target $target -Invoking $invoking -Inherited $LocalAppData -LayoutRoot $layout.LocalData -InvokingLayoutName 'AppData\Local'
        $roaming = Resolve-AgentHubWindowsDataRoot -Target $target -Invoking $invoking -Inherited $RoamingConfig -LayoutRoot $layout.RoamingConfig -InvokingLayoutName 'AppData\Roaming'
    } else {
        $overridden = $invoking -and -not $target.Equals($invoking, [StringComparison]::Ordinal)
        $localApp = $layout.LocalData
        $roaming = $layout.RoamingConfig
        if (-not $overridden -and -not [string]::IsNullOrWhiteSpace($env:XDG_DATA_HOME)) {
            $localApp = Get-AgentHubNormalizedDirectory $env:XDG_DATA_HOME
        }
        if (-not $overridden -and -not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
            $roaming = Get-AgentHubNormalizedDirectory $env:XDG_CONFIG_HOME
        }
    }
    return [pscustomobject]@{
        Platform              = $platformId
        TargetUserProfile     = $target
        InvokingUserProfile   = $invoking
        RegistryUserProfile   = $recorded
        EffectiveLocalAppData = $localApp
        EffectiveRoamingConfig = $roaming
        ProfileOverridden     = [bool]($invoking -and -not $target.Equals($invoking, [StringComparison]::OrdinalIgnoreCase))
    }
}

function Get-AgentHubIsolatedLocalData {
    param(
        [Parameter(Mandatory)][string]$TargetUserProfile,
        [string]$InvokingUserProfile = $(Get-AgentHubDefaultHome),
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [switch]$AlwaysIsolateOnOverride,
        [string]$Platform
    )
    $platformId = Get-AgentHubPlatformId $Platform
    $hostPlatform = Get-AgentHubHostPlatformId
    if ($platformId -ne $hostPlatform) {
        return (Get-AgentHubPlatformDataRoots -Platform $platformId -UserHome $TargetUserProfile.TrimEnd('\', '/')).LocalData
    }
    $target = Get-AgentHubNormalizedDirectory $TargetUserProfile
    $invoking = Get-AgentHubNormalizedDirectory $InvokingUserProfile
    $layout = Get-AgentHubPlatformDataRoots -Platform $platformId -UserHome $target
    if ($platformId -ne 'windows') { return $layout.LocalData }
    $overridden = $invoking -and -not $target.Equals($invoking, [StringComparison]::OrdinalIgnoreCase)
    if ($overridden -and $AlwaysIsolateOnOverride) { return $layout.LocalData }
    return Resolve-AgentHubWindowsDataRoot -Target $target -Invoking $invoking -Inherited $LocalAppData -LayoutRoot $layout.LocalData -InvokingLayoutName 'AppData\Local'
}

function Test-AgentHubPathTemplate {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim() -match '^\{(userHome|userProfile|localData|localAppData|roamingConfig)\}'
}

function Test-AgentHubWindowsOnlyTemplate {
    param([string]$Value)
    if (-not (Test-AgentHubPathTemplate $Value)) { return $false }
    return $Value -match '(?i)(^|[\\/])AppData([\\/]|$)'
}

function Test-AgentHubBindablePathValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if (Test-AgentHubPathTemplate $Value) { return $true }
    if ($Value -match '^[A-Za-z]:\\') { return $true }
    if ($Value -match '^\\\\') { return $true }
    if ($Value -match '^[A-Za-z]:/') { return $true }
    if ($Value.StartsWith('/') -and -not $Value.StartsWith('//')) { return $true }
    return $false
}

function Expand-AgentHubPathTemplate {
    param(
        [string]$Value,
        $Context,
        [hashtable]$ExtraTokens
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $platform = if ($Context.PSObject.Properties['Platform'] -and $Context.Platform) {
        [string]$Context.Platform
    } else {
        'windows'
    }
    $expanded = $Value.Replace('{userHome}', [string]$Context.TargetUserProfile)
    $expanded = $expanded.Replace('{userProfile}', [string]$Context.TargetUserProfile)
    $expanded = $expanded.Replace('{localData}', [string]$Context.EffectiveLocalAppData)
    $expanded = $expanded.Replace('{localAppData}', [string]$Context.EffectiveLocalAppData)
    $roaming = if ($Context.PSObject.Properties['EffectiveRoamingConfig']) {
        [string]$Context.EffectiveRoamingConfig
    } else {
        [string]$Context.EffectiveLocalAppData
    }
    $expanded = $expanded.Replace('{roamingConfig}', $roaming)
    if ($ExtraTokens) {
        foreach ($key in $ExtraTokens.Keys) {
            $token = '{' + $key + '}'
            $expanded = $expanded.Replace($token, [string]$ExtraTokens[$key])
        }
    }
    return Convert-AgentHubPathSeparators -Path $expanded -Platform $platform
}

function Resolve-AgentHubPrefixRebase {
    param(
        [string]$Full,
        [string]$Recorded,
        [string]$Target,
        [string]$Platform
    )
    $platformId = Get-AgentHubPlatformId $Platform
    $comparison = if ($platformId -eq 'windows') {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $full = $Full.TrimEnd('\', '/')
    $target = $Target.TrimEnd('\', '/')
    if ($full.Equals($target, $comparison)) { return $target }
    if ($full.StartsWith($target + '\', $comparison) -or $full.StartsWith($target + '/', $comparison)) {
        return Convert-AgentHubPathSeparators -Path $full -Platform $platformId
    }
    if ([string]::IsNullOrWhiteSpace($Recorded)) {
        return Convert-AgentHubPathSeparators -Path $full -Platform $platformId
    }
    $recorded = $Recorded.TrimEnd('\', '/')
    if ($full.Equals($recorded, $comparison)) { return $target }
    if ($full.StartsWith($recorded + '\', $comparison) -or $full.StartsWith($recorded + '/', $comparison)) {
        return Join-AgentHubPlatformPath -Platform $platformId -Base $target -Child $full.Substring($recorded.Length + 1)
    }
    return Convert-AgentHubPathSeparators -Path $full -Platform $platformId
}

function Resolve-AgentHubBoundPath {
    param(
        [string]$Declared,
        $Context
    )
    if ([string]::IsNullOrWhiteSpace($Declared)) { return $Declared }
    $platform = if ($Context.PSObject.Properties['Platform'] -and $Context.Platform) {
        [string]$Context.Platform
    } else {
        'windows'
    }
    if ((Test-AgentHubWindowsOnlyTemplate $Declared) -and $platform -ne 'windows') {
        throw "PathBinding refuses '$Declared': windows-only layout cannot be bound onto '$platform'. Refusing to run rather than write a fake AppData path."
    }
    if (Test-AgentHubPathTemplate $Declared) {
        return Expand-AgentHubPathTemplate -Value $Declared -Context $Context
    }
    if ($Declared -match '^(\\\\|[A-Za-z]:/)') {
        throw "PathBinding refuses '$Declared': rebasing does not support UNC or forward-slash absolute paths. Refusing to run rather than write them unrebased."
    }
    if ($Declared.StartsWith('/') -and -not $Declared.StartsWith('//')) {
        $recorded = if ($Context.RegistryUserProfile) { [string]$Context.RegistryUserProfile } else { [string]$Context.InvokingUserProfile }
        return Resolve-AgentHubPrefixRebase -Full $Declared -Recorded $recorded -Target ([string]$Context.TargetUserProfile) -Platform $platform
    }
    if ($Declared.Length -lt 3 -or $Declared[1] -ne ':' -or $Declared[2] -ne '\') {
        return $Declared
    }
    if ($platform -ne 'windows') {
        $recorded = if ($Context.RegistryUserProfile) { [string]$Context.RegistryUserProfile } else { [string]$Context.InvokingUserProfile }
        return Resolve-AgentHubPrefixRebase -Full $Declared -Recorded $recorded -Target ([string]$Context.TargetUserProfile) -Platform $platform
    }

    $full = Get-AgentHubNormalizedDirectory $Declared
    $target = [string]$Context.TargetUserProfile
    if ($full.Equals($target, [StringComparison]::OrdinalIgnoreCase)) { return $target }
    if ($full.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) { return $full }

    $recorded = if ($Context.RegistryUserProfile) {
        [string]$Context.RegistryUserProfile
    } else {
        [string]$Context.InvokingUserProfile
    }
    if (-not $recorded) { return $full }
    if ($full.Equals($recorded, [StringComparison]::OrdinalIgnoreCase)) { return $target }
    $prefix = $recorded + '\'
    if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $target $full.Substring($recorded.Length + 1)
    }
    return $full
}

function Convert-AgentHubBoundNode {
    param(
        $Node,
        $Context
    )
    if ($null -eq $Node) { return }
    foreach ($property in @($Node.PSObject.Properties)) {
        $value = $property.Value
        if ($value -is [string]) {
            if (-not (Test-AgentHubBindablePathValue $value)) { continue }
            try {
                $property.Value = Resolve-AgentHubBoundPath -Declared $value -Context $Context
            } catch {
                if ($_.Exception.Message -match 'windows-only layout') {
                    $property.Value = $null
                } else {
                    throw
                }
            }
        } elseif ($value -is [pscustomobject]) {
            Convert-AgentHubBoundNode -Node $value -Context $Context
        } elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            foreach ($element in $value) {
                if ($element -is [pscustomobject]) {
                    Convert-AgentHubBoundNode -Node $element -Context $Context
                }
            }
        }
    }
}
