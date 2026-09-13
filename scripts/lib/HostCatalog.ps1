#Requires -Version 5.1
<#
.SYNOPSIS
    Loads registry/agents.json and binds path-shaped fields once.
#>

. (Join-Path $PSScriptRoot 'PathBinding.ps1')

function Import-AgentHubBoundHostCatalog {
    param(
        [Parameter(Mandatory)]$AgentsDocument,
        [Parameter(Mandatory)]$Context
    )
    $hosts = @()
    if ($AgentsDocument.PSObject.Properties['activeAgents'] -and $AgentsDocument.activeAgents) {
        $hosts += @($AgentsDocument.activeAgents)
    }
    if ($AgentsDocument.PSObject.Properties['inactiveAgents'] -and $AgentsDocument.inactiveAgents) {
        $hosts += @($AgentsDocument.inactiveAgents)
    }
    foreach ($agent in $hosts) {
        if (-not $agent) { continue }
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
