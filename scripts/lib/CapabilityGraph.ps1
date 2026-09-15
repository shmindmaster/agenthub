#Requires -Version 5.1
<#
.SYNOPSIS
    Resolves the effective capability set from the core registry plus overlay.
#>

function Get-AgentHubOverlayRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    if ($env:AGENTHUB_OVERLAY -eq 'off') { return $null }
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_OVERLAY)) {
        $explicit = [System.IO.Path]::GetFullPath($env:AGENTHUB_OVERLAY).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $explicit)) {
            throw "AGENTHUB_OVERLAY is '$explicit' but that directory does not exist. Pass a real overlay or AGENTHUB_OVERLAY=off."
        }
        return $explicit
    }
    $default = Join-Path $RepositoryRoot 'overlays\personal'
    if (Test-Path -LiteralPath $default) { return $default }
    return $null
}

function Get-AgentHubOverlayManifest {
    param([string]$OverlayRoot)
    if (-not $OverlayRoot) { return $null }
    $path = Join-Path $OverlayRoot 'overlay.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Overlay root '$OverlayRoot' has no overlay.json."
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-AgentHubCapabilityPrivate {
    param($Capability)
    if (-not $Capability.PSObject.Properties['visibility']) { return $false }
    return [string]$Capability.visibility -eq 'private'
}

function Get-AgentHubEffectiveCapabilities {
    param(
        [Parameter(Mandatory)]$CapabilitiesDocument,
        [string]$OverlayRoot
    )
    $enabled = @{}
    if ($OverlayRoot) {
        $manifest = Get-AgentHubOverlayManifest -OverlayRoot $OverlayRoot
        foreach ($id in @($manifest.enabledCapabilityIds)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) {
                $enabled[[string]$id] = $true
            }
        }
    }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($capability in @($CapabilitiesDocument.capabilities)) {
        if (-not $capability) { continue }
        if (Test-AgentHubCapabilityPrivate $capability) {
            $id = [string]$capability.id
            if (-not $enabled.ContainsKey($id)) { continue }
        }
        $selected.Add($capability)
    }
    return $selected
}

function Resolve-AgentHubPolicyPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $compiled = Join-Path $RepositoryRoot 'global-agent-policy.md'
    $core = Join-Path $RepositoryRoot 'policy-core.md'
    $overlay = Get-AgentHubOverlayRoot -RepositoryRoot $RepositoryRoot
    if ($overlay -and (Test-Path -LiteralPath $compiled)) { return $compiled }
    if (Test-Path -LiteralPath $core) { return $core }
    if (Test-Path -LiteralPath $compiled) { return $compiled }
    throw "No policy file under '$RepositoryRoot'. Expected policy-core.md or global-agent-policy.md."
}
