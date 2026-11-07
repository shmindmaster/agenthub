#Requires -Version 7
function Invoke-AgentHubPluginChange {
    param(
        [Parameter(Mandatory)][scriptblock]$Install,
        [Parameter(Mandatory)][scriptblock]$Verify,
        [Parameter(Mandatory)][scriptblock]$Rollback
    )
    try {
        & $Install | Out-Null
        if (-not (& $Verify)) { throw 'Installed plugin failed readback.' }
        return 'verified'
    } catch {
        $failure = $_.Exception.Message
        try { & $Rollback | Out-Null }
        catch { throw "Plugin update failed ($failure). Rollback failed ($($_.Exception.Message)). Preserve its deployment receipt." }
        throw "Plugin update failed ($failure). Previous managed content restored."
    }
}
