#Requires -Version 5.1
<#
Shared helpers for tests that must hold on Windows, macOS and Linux.
Dot-source from a test: . (Join-Path $PSScriptRoot 'lib\TestPlatform.ps1')
#>

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\lib\PathBinding.ps1')

# Where the sync engine keeps local data (AgentHub runtime state, staged
# instructions) for a synthetic -UserProfile on this OS: AppData\Local on
# Windows, Library/Application Support on macOS, .local/share on Linux.
function Get-TestProfileLocalData {
    param([Parameter(Mandatory)][string]$UserProfile)
    return (Get-AgentHubPlatformDataRoots -Platform (Get-AgentHubHostPlatformId) -UserHome $UserProfile).LocalData
}

# The OS user-config root for a synthetic -UserProfile: AppData\Roaming on
# Windows, Library/Application Support on macOS, .config on Linux.
function Get-TestProfileRoamingConfig {
    param([Parameter(Mandatory)][string]$UserProfile)
    return (Get-AgentHubPlatformDataRoots -Platform (Get-AgentHubHostPlatformId) -UserHome $UserProfile).RoamingConfig
}

# Creates a directory link the way the sync engine does on this OS: a
# junction on Windows, a symbolic link on macOS and Linux.
function New-TestDirectoryLink {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target)
    $type = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
    return New-Item -ItemType $type -Path $Path -Target $Target
}
