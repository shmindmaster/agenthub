#Requires -Version 5.1
<#
.SYNOPSIS
    Resolves the effective capability set from the core registry plus overlay.

Public-first layout:
  - Tracked packages live under packages/<id>.
  - Private packages live under overlays/personal/packages/<id> (gitignored).
  - Private capability rows live in overlays/personal/capabilities.json and
    load only when the personal overlay is present and lists their ids.
  - RepoWise and other public packages stay under packages/ — never disable
    them as part of overlay migration.
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

function Get-AgentHubOverlayCapabilitiesDocument {
    param([string]$OverlayRoot)
    if (-not $OverlayRoot) { return $null }
    $path = Join-Path $OverlayRoot 'capabilities.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-AgentHubCapabilityPrivate {
    param($Capability)
    if (-not $Capability.PSObject.Properties['visibility']) { return $false }
    return [string]$Capability.visibility -eq 'private'
}

function Get-AgentHubMergedCapabilitiesDocument {
    param(
        [Parameter(Mandatory)]$CapabilitiesDocument,
        [string]$OverlayRoot
    )
    $merged = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($capability in @($CapabilitiesDocument.capabilities)) {
        if (-not $capability) { continue }
        $id = [string]$capability.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($seen.ContainsKey($id)) {
            throw "Duplicate capability id in core registry: $id"
        }
        $seen[$id] = $true
        $merged.Add($capability)
    }
    $overlayDoc = Get-AgentHubOverlayCapabilitiesDocument -OverlayRoot $OverlayRoot
    if ($overlayDoc) {
        foreach ($capability in @($overlayDoc.capabilities)) {
            if (-not $capability) { continue }
            $id = [string]$capability.id
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if ($seen.ContainsKey($id)) {
                throw "Overlay capability id '$id' collides with a core registry id."
            }
            if (-not (Test-AgentHubCapabilityPrivate $capability)) {
                throw "Overlay capability '$id' must set visibility: private."
            }
            $seen[$id] = $true
            $merged.Add($capability)
        }
    }
    $clone = [pscustomobject]@{}
    foreach ($prop in $CapabilitiesDocument.PSObject.Properties) {
        if ($prop.Name -eq 'capabilities') { continue }
        $clone | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
    $clone | Add-Member -NotePropertyName 'capabilities' -NotePropertyValue @($merged.ToArray())
    return $clone
}

function Get-AgentHubEffectiveCapabilities {
    param(
        [Parameter(Mandatory)]$CapabilitiesDocument,
        [string]$OverlayRoot
    )
    $mergedDoc = Get-AgentHubMergedCapabilitiesDocument `
        -CapabilitiesDocument $CapabilitiesDocument `
        -OverlayRoot $OverlayRoot
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
    foreach ($capability in @($mergedDoc.capabilities)) {
        if (-not $capability) { continue }
        if (Test-AgentHubCapabilityPrivate $capability) {
            $id = [string]$capability.id
            if (-not $enabled.ContainsKey($id)) { continue }
        }
        $selected.Add($capability)
    }
    return $selected
}

function Resolve-AgentHubPackageRoot {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Capability,
        [string]$OverlayRoot
    )
    $id = [string]$Capability.id
    $source = [string]$Capability.canonicalSource
    if ([string]::IsNullOrWhiteSpace($source)) {
        $source = if (Test-AgentHubCapabilityPrivate $Capability) {
            "overlays/personal/packages/$id"
        } else {
            "packages/$id"
        }
    }
    $resolved = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($source -replace '/', '\')))
    $rootFull = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $sep = [IO.Path]::DirectorySeparatorChar
    $rootPrefix = $rootFull + $sep
    if (-not ($resolved.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
        $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "canonicalSource for '$id' escapes the repository root: $source"
    }
    if (Test-AgentHubCapabilityPrivate $Capability) {
        $publicTwin = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot "packages\$id"))
        if (Test-Path -LiteralPath $publicTwin) {
            throw "Private capability '$id' still has a tracked packages/$id tree. Move it to overlays/personal/packages/$id."
        }
        $expectedPrefix = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'overlays\personal\packages')) + $sep
        if (-not $resolved.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Private capability '$id' canonicalSource must be under overlays/personal/packages/ (got '$source')."
        }
        if (-not $OverlayRoot) {
            throw "Private capability '$id' requires overlays/personal (or AGENTHUB_OVERLAY)."
        }
    } else {
        $expectedPrefix = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'packages')) + $sep
        $expectedExact = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'packages'))
        if (-not ($resolved.Equals($expectedExact, [StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase))) {
            throw "Public capability '$id' canonicalSource must be under packages/ (got '$source')."
        }
    }
    return $resolved
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
