#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
    [string]$UserProfile = 'C:\Users\SaroshHussain'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Audit -and $Apply) { throw 'Choose either -Audit or -Apply.' }
if (-not $Audit -and -not $Apply) { $Audit = $true }

$syncScript = Join-Path $RegistryRoot 'scripts\Sync-AgentCapabilities.ps1'
$registryDir = Join-Path $RegistryRoot 'registry'
$agents = Get-Content -Raw -LiteralPath (Join-Path $registryDir 'agents.json') | ConvertFrom-Json
$mcps = Get-Content -Raw -LiteralPath (Join-Path $registryDir 'mcps.json') | ConvertFrom-Json
$capabilities = Get-Content -Raw -LiteralPath (Join-Path $registryDir 'capabilities.json') | ConvertFrom-Json

$repoContextMcp = @($mcps.mcpServers | Where-Object id -eq 'repocontext')
$repoContextCapability = @($capabilities.capabilities | Where-Object id -eq 'repocontext')
if ($repoContextMcp.Count -ne 1) { throw 'Expected exactly one repocontext MCP registration.' }
if ($repoContextCapability.Count -ne 1) { throw 'Expected exactly one repocontext capability.' }

# Cursor remains excluded until Sarosh explicitly re-enables it.
$targetAgents = @($agents.activeAgents | Where-Object id -ne 'cursor')
$temporaryRoot = Join-Path $env:TEMP "agenthub-repocontext-$([guid]::NewGuid().ToString('N'))"
$temporaryRegistry = Join-Path $temporaryRoot 'registry'
New-Item -ItemType Directory -Path $temporaryRegistry -Force | Out-Null

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, "$json`n", [System.Text.UTF8Encoding]::new($false))
}

try {
    Write-JsonFile -Path (Join-Path $temporaryRegistry 'agents.json') -Value @{
        activeAgents = $targetAgents
        inactiveAgents = @()
    }
    Write-JsonFile -Path (Join-Path $temporaryRegistry 'mcps.json') -Value @{
        mcpServers = $repoContextMcp
    }
    Write-JsonFile -Path (Join-Path $temporaryRegistry 'capabilities.json') -Value @{
        capabilities = $repoContextCapability
    }

    if ($Apply) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupRoot = Join-Path $env:LOCALAPPDATA "AgentCapabilities\backups\repocontext-$stamp"
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $manifest = @()
        foreach ($agent in $targetAgents) {
            if (-not $agent.nativePaths) { continue }
            foreach ($property in $agent.nativePaths.PSObject.Properties) {
                $path = [string]$property.Value
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
                $safeName = "$($agent.id)--$($property.Name)--$([System.IO.Path]::GetFileName($path))"
                $destination = Join-Path $backupRoot $safeName
                Copy-Item -LiteralPath $path -Destination $destination
                $manifest += [pscustomobject]@{ agent = $agent.id; property = $property.Name; source = $path; backup = $destination }
            }
        }
        Write-JsonFile -Path (Join-Path $backupRoot 'manifest.json') -Value @{ files = $manifest }
        Write-Host "Backups: $backupRoot"
    }

    $mode = if ($Apply) { '-Apply' } else { '-Audit' }
    & pwsh -NoLogo -NoProfile -File $syncScript $mode -Validate -RegistryRoot $temporaryRoot -UserProfile $UserProfile
    if ($LASTEXITCODE -ne 0) { throw "RepoContext host sync failed with exit code $LASTEXITCODE." }
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    $resolvedTarget = [System.IO.Path]::GetFullPath($temporaryRoot)
    if (
        $resolvedTarget.StartsWith("$resolvedTemp\", [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedTarget).StartsWith('agenthub-repocontext-')
    ) {
        Remove-Item -LiteralPath $resolvedTarget -Recurse -Force -ErrorAction SilentlyContinue
    }
}
