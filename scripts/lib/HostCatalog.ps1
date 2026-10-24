#Requires -Version 5.1
<#
.SYNOPSIS
    Loads registry/agents.json and binds path-shaped fields once.
#>

. (Join-Path $PSScriptRoot 'PathBinding.ps1')

function Test-AgentHubHostSyncEnabled {
    param([Parameter(Mandatory)]$Agent)
    # Retirement is explicit and is not the historical inactive label. Keep
    # inventory and paths, but never recreate an owner-retired deployment.
    return -not ($Agent.PSObject.Properties['status'] -and [string]$Agent.status -eq 'retired')
}

function Import-AgentHubBoundHostCatalog {
    param(
        [Parameter(Mandatory)]$AgentsDocument,
        [Parameter(Mandatory)]$Context
    )
    $platform = if ($Context.PSObject.Properties['Platform'] -and $Context.Platform) { [string]$Context.Platform } else { 'windows' }
    Use-AgentHubPlatformPaths -AgentsDocument $AgentsDocument -Platform $platform | Out-Null
    $hosts = @()
    if ($AgentsDocument.PSObject.Properties['activeAgents'] -and $AgentsDocument.activeAgents) {
        $hosts += @($AgentsDocument.activeAgents)
    }
    if ($AgentsDocument.PSObject.Properties['inactiveAgents'] -and $AgentsDocument.inactiveAgents) {
        $hosts += @($AgentsDocument.inactiveAgents)
    }
    foreach ($agent in $hosts) {
        if (-not $agent) { continue }
        if ($platform -ne 'windows' -and $agent.PSObject.Properties['executable'] -and $agent.executable -is [string]) {
            $portable = Get-AgentHubPortableCommandName ([string]$agent.executable)
            if ($portable) { $agent.executable = $portable }
        }
        if ($agent.PSObject.Properties['executable'] -and $agent.executable -is [string] -and
            (Test-AgentHubBindablePathValue ([string]$agent.executable))) {
            try {
                $agent.executable = Resolve-AgentHubBoundPath -Declared ([string]$agent.executable) -Context $Context
            } catch {
                if ($_.Exception.Message -notmatch 'windows-only layout') { throw }
                # A Windows install pin (.exe under AppData, WinGet, Programs)
                # is not a Mac or Linux path. Leave it unbound rather than
                # writing a fake destination.
                $agent.executable = $null
            }
        }
        if ($agent.nativePaths) {
            Convert-AgentHubBoundNode -Node $agent.nativePaths -Context $Context
        }
    }
    return $AgentsDocument
}
