#Requires -Version 5.1
<#
.SYNOPSIS
  Bump a package version with root plugin.json as the single authority.

.DESCRIPTION
  AgentHub treats packages/<id>/plugin.json as the portable Agent Plugins floor
  and the version authority. Host projections (.claude-plugin, .codex-plugin,
  .cursor-plugin, .qoder-plugin) must carry the same version string.

  This script updates those manifests together. It does not recompute
  contentHash or edit registry/capabilities.json — run RegistryContentHash.ps1
  and update the capability entry after content changes, as today.

.EXAMPLE
  pwsh -NoProfile -File scripts/Bump-PackageVersion.ps1 -Package media-studio -Version 1.5.7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Version,
    [string]$RepositoryRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$packageRoot = Join-Path $root "packages/$Package"
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Package directory not found: $packageRoot"
}
if ($Version -notmatch '^\d+\.\d+\.\d+([.-][0-9A-Za-z.-]+)?$') {
    throw "Version '$Version' is not a simple semver-like string (expected N.N.N)."
}

$hostDirs = @('.claude-plugin', '.codex-plugin', '.cursor-plugin', '.qoder-plugin')
$schema = 'https://agentplugins.org/schemas/1.0.0/plugin.schema.json'
$rootManifestPath = Join-Path $packageRoot 'plugin.json'

function Read-JsonFile([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 20
    # PowerShell's ConvertTo-Json is lossy for property order; acceptable for bumps.
    [IO.File]::WriteAllText($Path, ($json.TrimEnd() + "`n"))
}

# Build / update portable root first — it is the authority.
if (Test-Path -LiteralPath $rootManifestPath) {
    $rootManifest = Read-JsonFile -Path $rootManifestPath
} else {
    $rootManifest = [pscustomobject]@{ name = $Package }
}
$rootHash = @{}
foreach ($p in $rootManifest.PSObject.Properties) { $rootHash[$p.Name] = $p.Value }
$rootHash['$schema'] = $schema
if (-not $rootHash.ContainsKey('name') -or [string]::IsNullOrWhiteSpace([string]$rootHash['name'])) {
    $rootHash['name'] = $Package
}
$rootHash['version'] = $Version
if (-not $rootHash.ContainsKey('description')) {
    foreach ($hostDir in $hostDirs) {
        $hostPath = Join-Path $packageRoot "$hostDir/plugin.json"
        if (Test-Path -LiteralPath $hostPath) {
            $hostObj = Read-JsonFile -Path $hostPath
            if ($hostObj.description) { $rootHash['description'] = [string]$hostObj.description; break }
        }
    }
}
# Ordered portable fields first.
$portable = [ordered]@{
    '$schema'   = $schema
    name        = [string]$rootHash['name']
    version     = $Version
    description = [string]$rootHash['description']
}
foreach ($extra in @('author', 'license', 'keywords', 'homepage', 'repository')) {
    if ($rootHash.ContainsKey($extra) -and $null -ne $rootHash[$extra]) {
        $portable[$extra] = $rootHash[$extra]
    }
}
Write-JsonFile -Path $rootManifestPath -Object ([pscustomobject]$portable)
Write-Host "updated $Package/plugin.json -> $Version"

$updated = @('plugin.json')
foreach ($hostDir in $hostDirs) {
    $hostPath = Join-Path $packageRoot "$hostDir/plugin.json"
    if (-not (Test-Path -LiteralPath $hostPath)) { continue }
    $hostObj = Read-JsonFile -Path $hostPath
    $hostObj | Add-Member -NotePropertyName version -NotePropertyValue $Version -Force
    Write-JsonFile -Path $hostPath -Object $hostObj
    $updated += "$hostDir/plugin.json"
    Write-Host "updated $Package/$hostDir/plugin.json -> $Version"
}

Write-Host ""
Write-Host "Version authority is packages/$Package/plugin.json ($Version)."
Write-Host "Updated: $($updated -join ', ')"
Write-Host "Next: recompute contentHash if package content changed, then Validate-AgentHub.ps1."
