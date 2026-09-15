#Requires -Version 5.1
<#
.SYNOPSIS
    Names the validate-then-sync step list. Writers stay in the Sync-* scripts.
#>

function Get-AgentHubSyncStepDefinitions {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$UserProfile,
        [switch]$ApplyMode
    )
    $modeArg = if ($ApplyMode) { '-Apply' } else { '-Audit' }
    return @(
        @{ Name = 'Sync-Instructions.ps1'; Relative = 'Sync-Instructions.ps1'; Args = @($modeArg, '-RepositoryRoot', $RepositoryRoot, '-UserProfile', $UserProfile) }
        @{ Name = 'Sync-Subagents.ps1'; Relative = 'Sync-Subagents.ps1'; Args = @($modeArg, '-RepositoryRoot', $RepositoryRoot, '-UserProfile', $UserProfile) }
        @{ Name = 'Sync-Capabilities.ps1'; Relative = 'Sync-Capabilities.ps1'; Args = @($modeArg, '-RepositoryRoot', $RepositoryRoot, '-UserProfile', $UserProfile) }
        @{ Name = 'Sync-AgentHub.ps1'; Relative = 'Sync-AgentHub.ps1'; Args = @($modeArg, '-RegistryRoot', $RepositoryRoot, '-UserProfile', $UserProfile) }
    )
}
