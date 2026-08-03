#Requires -Version 5.1
<#
.SYNOPSIS
    Central synchronization engine for the AgentHub registry. Self-derives its
    registry root from this script's own on-disk location unless -RegistryRoot
    is passed explicitly.

.DESCRIPTION
    Reads the central registry and deploys real files / native configuration
    entries into each installed coding agent's documented Windows user-level
    folders. Idempotent. Qwen extensions use managed directory junctions so its
    native extension loader can consume the canonical skill sources without
    copying credentials or skill content.

.PARAMETER Audit
    Report drift without making changes.

.PARAMETER Apply
    Deploy managed files and merge native configuration.

.PARAMETER Prune
    With -Apply, remove stale managed files and duplicates.

.PARAMETER Validate
    Validate JSON/JSONC/YAML/TOML/markdown frontmatter and MCP schemas.
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [switch]$Prune,
    [switch]$Validate,
    [ValidateSet('global-default','project','on-demand-desktop','all')]
    [string]$ScopeProfile = 'global-default',
    [switch]$IncludeDeprecated,
    [switch]$IncludeInactiveAgents,
    [string]$RegistryRoot,
    [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
# Self-derive from this script's own on-disk location -- same idiom as
# Validate-AgentHub.ps1 and Sync-Capabilities.ps1. Without this, running from
# a worktree (the normal development path per repository policy) with no
# explicit -RegistryRoot would silently read whatever tree the hardcoded
# default pointed at instead of the tree this invocation actually belongs to.
if ([string]::IsNullOrWhiteSpace($RegistryRoot)) {
    $RegistryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$RegistryRoot = [System.IO.Path]::GetFullPath($RegistryRoot).TrimEnd('\')
$RegistryDir       = Join-Path $RegistryRoot 'registry'
$effectiveLocalAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA)
$invokingUserProfile = if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $null
} else {
    [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
}
$targetUserProfile = [System.IO.Path]::GetFullPath($UserProfile).TrimEnd('\')
if ($invokingUserProfile -and
    -not $targetUserProfile.Equals($invokingUserProfile, [StringComparison]::OrdinalIgnoreCase)) {
    $invokingLocalAppData = [System.IO.Path]::GetFullPath(
        (Join-Path $invokingUserProfile 'AppData\Local')
    ).TrimEnd('\')
    if ($effectiveLocalAppData.TrimEnd('\').Equals(
        $invokingLocalAppData,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        # A synthetic or alternate profile must not contaminate the invoking
        # user's live AgentHub state merely because LOCALAPPDATA was inherited.
        $effectiveLocalAppData = Join-Path $targetUserProfile 'AppData\Local'
    }
}
$RuntimeDir        = Join-Path $effectiveLocalAppData 'AgentHub'
$StateDir          = Join-Path $RuntimeDir 'sync'
$DriftPath         = Join-Path $StateDir 'latest-drift.json'
$StateFile         = Join-Path $StateDir 'sync-state.json'

$AgentsFile        = Join-Path $RegistryDir 'agents.json'
$McpsFile          = Join-Path $RegistryDir 'mcps.json'
$CapabilitiesFile  = Join-Path $RegistryDir 'capabilities.json'
$ConnectorsFile    = Join-Path $RegistryDir 'native-connectors.json'
$GatewaysFile      = Join-Path $RegistryDir 'gateway-profiles.json'

# registry/capabilities.json now stores canonicalSource/hashBasis as
# repo-relative paths (e.g. "packages/clerk"), not paths hardcoded to one
# checkout. This resolves such a value against the repository root this
# process is actually running from. It used to also rewrite paths hardcoded
# to the historical C:\Repos\shmindmaster\agenthub checkout onto whatever
# root was actually running -- that rewrite is now dead for registry data,
# since Validate-AgentHub.ps1 rejects an absolute canonicalSource/hashBasis
# outright. If one somehow still arrives absolute here, that means the
# validator guard was bypassed; fail loudly instead of silently rewriting it.
function Resolve-RegistryOwnedPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        throw "Resolve-RegistryOwnedPath received an absolute/UNC path ('$Path'). Registry-owned paths (canonicalSource/hashBasis) must be repository-relative; fix registry/capabilities.json instead of resolving around it."
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RegistryRoot $Path))
}

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

# ---------------------------------------------------------------------------
# Load registry
# ---------------------------------------------------------------------------
function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )
    # Windows PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM.
    # Qwen Code feeds settings.json directly to JSON.parse(), which rejects
    # that leading character.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$agentsReg = Read-JsonFile $AgentsFile
$mcpsReg   = Read-JsonFile $McpsFile
$capReg    = Read-JsonFile $CapabilitiesFile
$connectorReg = Read-JsonFile $ConnectorsFile
$gatewayReg   = Read-JsonFile $GatewaysFile

if (-not $agentsReg) { throw "Missing $AgentsFile" }
if (-not $mcpsReg)   { throw "Missing $McpsFile" }
if (-not $capReg)    { throw "Missing $CapabilitiesFile" }

# An empty or wrong -RegistryRoot must never be reported as a successful,
# zero-drift run. A directory can pass the file-existence checks above (an
# agents.json/capabilities.json can exist but be empty, or -RegistryRoot can
# point at some other tree entirely) and still not be this registry. Refuse
# to proceed rather than silently completing against an empty work set.
$activeAgentCount = @($agentsReg.activeAgents).Count
if ($activeAgentCount -eq 0) {
    throw "Registry root '$RegistryRoot' resolved to zero active agents in $AgentsFile. Refusing to report success against what looks like an empty or wrong registry tree; pass -RegistryRoot explicitly if this is intentional."
}
$capabilityCount = @($capReg.capabilities).Count
if ($capabilityCount -eq 0) {
    throw "Registry root '$RegistryRoot' resolved to zero capabilities in $CapabilitiesFile. Refusing to report success against what looks like an empty or wrong registry tree; pass -RegistryRoot explicitly if this is intentional."
}

$script:mcpMigrationAliases = @{
    'github-shmindmaster' = 'github'
    'github-sh-pendoah' = 'github'
    'github-sarosh-pendoah' = 'github'
}
if ($mcpsReg.PSObject.Properties['migrationAliases'] -and $mcpsReg.migrationAliases) {
    foreach ($alias in $mcpsReg.migrationAliases.PSObject.Properties) {
        if (-not [string]::IsNullOrWhiteSpace([string]$alias.Name) -and
            -not [string]::IsNullOrWhiteSpace([string]$alias.Value)) {
            $script:mcpMigrationAliases[[string]$alias.Name] = [string]$alias.Value
        }
    }
}

# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------
$state = @{ managedFiles = @{}; lastRun = (Get-Date -Format "o") }
if (Test-Path -LiteralPath $StateFile) {
    $loaded = Read-JsonFile $StateFile
    if ($loaded) {
        if ($loaded.managedFiles -is [hashtable]) {
            $state.managedFiles = $loaded.managedFiles
        } else {
            $mf = @{}
            if ($loaded.managedFiles) {
                foreach ($prop in $loaded.managedFiles.PSObject.Properties) {
                    $mf[$prop.Name] = @{}
                    if ($prop.Value) {
                        foreach ($sub in $prop.Value.PSObject.Properties) {
                            $mf[$prop.Name][$sub.Name] = $sub.Value
                        }
                    }
                }
            }
            $state.managedFiles = $mf
        }
    }
}
if ($Apply) {
    # An apply produces a fresh inventory. Retaining untouched entries turns
    # old destinations and surviving test fixtures into false current owners.
    $state.managedFiles = @{}
}

function Save-State {
    # State is an inventory of current managed files, not an append-only
    # history. Retired destinations and deleted test fixtures must not inflate
    # secret scans or appear to remain managed indefinitely.
    foreach ($managedPath in @($state.managedFiles.Keys)) {
        if (-not (Test-Path -LiteralPath $managedPath)) {
            $state.managedFiles.Remove($managedPath)
        }
    }
    $state.lastRun = (Get-Date -Format "o")
    Write-Utf8NoBom -Path $StateFile -Content ($state | ConvertTo-Json -Depth 6)
}

function Get-FileHash256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
$validationErrors = @()

function Test-JsonParse {
    param([string]$Path)
    try {
        $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return $true
    } catch {
        $script:validationErrors += "$Path : JSON parse failed : $($_.Exception.Message)"
        return $false
    }
}

function Test-TomlParse {
    param([string]$Path)
    try {
        $toml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        # PowerShell 7+ has Invoke-RestMethod or we can use Python tomllib
        $py = @"
import tomllib, sys
with open(r'$Path', 'rb') as f:
    tomllib.load(f)
print('OK')
"@
        $result = & python -c $py 2>&1
        if ($LASTEXITCODE -ne 0) { throw $result }
        return $true
    } catch {
        $script:validationErrors += "$Path : TOML parse failed : $($_.Exception.Message)"
        return $false
    }
}

function Test-MarkdownFrontmatter {
    param([string]$Path)
    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ($content -match '^---\r?\n') {
            $parts = $content -split '^---\r?\n', 3
            if ($parts.Count -ge 3) {
                $null = $parts[1] | ConvertFrom-Yaml -ErrorAction SilentlyContinue
            }
        }
        return $true
    } catch {
        $script:validationErrors += "$Path : frontmatter failed : $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# Generic file deployment
# ---------------------------------------------------------------------------
function Deploy-File {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$OwnerCapability,
        [switch]$WhatIf
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return @{ status = 'source-missing' }
    }

    $sourceHash = Get-FileHash256 $SourcePath
    $destHash   = Get-FileHash256 $DestPath

    if ($sourceHash -eq $destHash) {
        $script:state.managedFiles[$DestPath] = @{ capability=$OwnerCapability; hash=$sourceHash }
        return @{ status = 'unchanged'; hash = $sourceHash }
    }

    # Detect user-owned path conflicts: a file exists at the destination but
    # is not recorded in managed state. In WhatIf mode, report the conflict
    # without mutating or creating directories so the preview is complete.
    $isManaged = $script:state.managedFiles.ContainsKey($DestPath)
    $destExists = Test-Path -LiteralPath $DestPath
    if ($WhatIf) {
        if ($destExists -and -not $isManaged) {
            return @{ status = 'user-owned-conflict'; sourceHash=$sourceHash; destHash=$destHash; path=$DestPath }
        }
        return @{ status = 'drift'; sourceHash=$sourceHash; destHash=$destHash }
    }

    $destDir = Split-Path $DestPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
    $script:state.managedFiles[$DestPath] = @{ capability=$OwnerCapability; hash=$sourceHash }
    return @{ status = 'updated'; hash = $sourceHash }
}

# ---------------------------------------------------------------------------
# JSON -> Hashtable conversion (ConvertFrom-Json returns PSCustomObject)
# ---------------------------------------------------------------------------
function ConvertTo-Hashtable {
    param([object]$InputObject)
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $hash
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $collection = @()
        foreach ($item in $InputObject) { $collection += (ConvertTo-Hashtable $item) }
        return ,$collection
    }
    return $InputObject
}

function ConvertTo-StableJsonObject {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [ValueType]) { return $InputObject }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $InputObject = ConvertTo-Hashtable $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in ($InputObject.Keys | Sort-Object)) {
            $ordered[$key] = ConvertTo-StableJsonObject $InputObject[$key]
        }
        return $ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $arr = @()
        foreach ($item in $InputObject) {
            $arr += (ConvertTo-StableJsonObject $item)
        }
        return ,$arr
    }

    return $InputObject
}

function Get-StableJsonString {
    param([object]$InputObject)
    return (ConvertTo-StableJsonObject $InputObject | ConvertTo-Json -Depth 12 -Compress)
}

# ---------------------------------------------------------------------------
# MCP merge helpers
# ---------------------------------------------------------------------------
function Contains-UnresolvedPlaceholder {
    param([string]$Value)
    if (-not $Value) { return $false }
    return $Value -match '\$\{env:[^}]+\}|\$\{[A-Z_][A-Z0-9_]*\}|\{env:[A-Z_][A-Z0-9_]*\}|\$[A-Z_][A-Z0-9_]*'
}

function Resolve-McpAliasKey {
    param([string]$Key)
    if ($script:mcpMigrationAliases.ContainsKey($Key)) {
        return [string]$script:mcpMigrationAliases[$Key]
    }
    return $Key
}

function Get-McpAliasesForCanonicalKey {
    param([string]$Key)
    return @($script:mcpMigrationAliases.Keys | Where-Object {
        [string]$script:mcpMigrationAliases[$_] -eq $Key
    })
}

function Normalize-McpTargetKeys {
    param([hashtable]$Target)

    $aliases = @()
    foreach ($k in @($Target.Keys)) {
        $resolved = Resolve-McpAliasKey $k
        if ($resolved -ne $k) {
            $aliases += [pscustomobject]@{ from=$k; to=$resolved }
        }
    }

    foreach ($a in $aliases) {
        $source = $Target[$a.from]
        if ($Target.ContainsKey($a.to)) {
            $dest = $Target[$a.to]
            if (-not ($dest -is [hashtable])) {
                $dest = ConvertTo-Hashtable $dest
                $Target[$a.to] = $dest
            }
            if (-not ($source -is [hashtable])) {
                $source = ConvertTo-Hashtable $source
            }
            foreach ($f in @('env','headers','enabled','environment')) {
                if ($source.ContainsKey($f) -and -not $dest.ContainsKey($f)) {
                    $dest[$f] = $source[$f]
                }
            }
            $Target.Remove($a.from)
            continue
        }
        $Target[$a.to] = $source
        $Target.Remove($a.from)
    }

    return $Target
}

function Remove-McpTargetKeys {
    param(
        [hashtable]$Target,
        [string[]]$Keys = @()
    )

    foreach ($key in @($Keys)) {
        $resolved = Resolve-McpAliasKey $key
        foreach ($candidate in @($resolved) + @(Get-McpAliasesForCanonicalKey $resolved)) {
            if ($Target.ContainsKey($candidate)) { $Target.Remove($candidate) }
        }
    }
    return $Target
}

function Merge-McpServers {
    param(
        [hashtable]$Target,
        [hashtable]$Additions,
        [string[]]$PreserveKeys = @('env','headers'),
        [switch]$PruneUnknown
    )
    $Target = Normalize-McpTargetKeys -Target $Target

    $canonicalKeys = @{}
    foreach ($k in $Additions.Keys) {
        $canonicalKeys[(Resolve-McpAliasKey $k)] = $true
    }

    foreach ($key in $Additions.Keys) {
        $targetKey = Resolve-McpAliasKey $key
        $canonical = $Additions[$key]
        if (-not ($canonical -is [hashtable])) {
            $canonical = ConvertTo-Hashtable $canonical
        }
        if (-not $Target.ContainsKey($targetKey)) {
            $Target[$targetKey] = $canonical
        } else {
            $existing = $Target[$targetKey]
            if (-not ($existing -is [hashtable])) {
                $existing = ConvertTo-Hashtable $existing
                $Target[$targetKey] = $existing
            }
            # Remove stale transport-specific fields before applying canonical structure.
            if ($canonical.ContainsKey('type')) {
                if ($canonical.type -eq 'http') {
                    foreach ($legacyField in @('command','args','cwd')) {
                        if ($existing.ContainsKey($legacyField)) {
                            $existing.Remove($legacyField)
                        }
                    }
                } elseif ($canonical.type -eq 'stdio') {
                    if ($existing.ContainsKey('url')) {
                        $existing.Remove('url')
                    }
                    if ($existing.ContainsKey('headers')) {
                        $existing.Remove('headers')
                    }
                }
            }
            # Update canonical structural fields; skip canonical values that contain
            # unresolved env placeholders when an existing real value is present.
            foreach ($field in @('type','command','args','url','cwd')) {
                if ($canonical.ContainsKey($field)) {
                    $candidate = $canonical[$field]
                    if ($existing.ContainsKey($field) -and (Contains-UnresolvedPlaceholder $candidate)) {
                        continue
                    }
                    $existing[$field] = $candidate
                }
            }
            # Preserve existing secret-bearing fields unless canonical explicitly supplies real values.
            foreach ($field in $PreserveKeys) {
                if ($canonical.ContainsKey($field)) {
                    $candidate = $canonical[$field]
                    if (-not $existing.ContainsKey($field)) {
                        $existing[$field] = $candidate
                    } elseif (-not (Contains-UnresolvedPlaceholder ($candidate | ConvertTo-Json -Depth 3 -Compress))) {
                        $existing[$field] = $candidate
                    }
                }
            }
            if ($PruneUnknown) {
                foreach ($field in $PreserveKeys) {
                    if (-not $canonical.ContainsKey($field) -and $existing.ContainsKey($field)) {
                        $existing.Remove($field)
                    }
                }
            }
        }
    }

    if ($PruneUnknown) {
        foreach ($k in @($Target.Keys)) {
            if (-not $canonicalKeys.ContainsKey((Resolve-McpAliasKey $k))) {
                $Target.Remove($k)
            }
        }
    }

    return $Target
}

function Get-CanonicalMcpEntry {
    param([pscustomobject]$Mcp)
    $entry = @{}
    switch ($Mcp.transport) {
        'stdio' {
            $entry.type = 'stdio'
            $entry.command = $Mcp.command
            $entry.args = @($Mcp.args)
            if ($Mcp.env) { $entry.env = ConvertTo-Hashtable $Mcp.env }
        }
        'http' {
            $entry.type = 'http'
            $entry.url = $Mcp.url
            if ($Mcp.headers) { $entry.headers = ConvertTo-Hashtable $Mcp.headers }
            if ($Mcp.credentialPolicy -eq 'oauth') { $entry.auth = 'oauth' }
        }
    }
    return $entry
}

function Get-McpCandidatesForScope {
    param(
        [object[]]$Servers,
        [string]$Scope,
        [switch]$AllowDeprecated
    )

    if ($Scope -eq 'all') {
        if ($AllowDeprecated) { return @($Servers) }
        return @($Servers | Where-Object { $_.scope -ne 'deprecated' })
    }

    $filtered = @($Servers | Where-Object {
        if (-not $_.scope) { return $Scope -eq 'global-default' }
        return $_.scope -eq $Scope
    })

    if ($AllowDeprecated) {
        $filtered += @($Servers | Where-Object { $_.scope -eq 'deprecated' })
    }

    return $filtered
}

function Get-PluginProvidedMcpKeysByHost {
    param(
        [object]$CapabilitiesRegistry,
        [object]$McpRegistry,
        [object]$ConnectorRegistry
    )

    $result = @{}

    # Some native plugins are not represented by a capability package in this
    # repository (for example Claude's official Notion plugin).  The MCP
    # registry can still record the host-local plugin owner so the global MCP
    # writer does not create a second active registration.
    if ($McpRegistry -and $McpRegistry.mcpServers) {
        foreach ($mcp in $McpRegistry.mcpServers) {
            $ownersProperty = $mcp.PSObject.Properties['pluginOwnersByHost']
            if (-not $ownersProperty -or $null -eq $ownersProperty.Value) { continue }
            foreach ($owner in $ownersProperty.Value.PSObject.Properties) {
                $hostId = [string]$owner.Name
                if (-not $hostId -or [string]::IsNullOrWhiteSpace([string]$owner.Value)) { continue }
                if (-not $result.ContainsKey($hostId)) { $result[$hostId] = @{} }
                $result[$hostId][(Resolve-McpAliasKey $mcp.id)] = $true
            }
        }
    }

    if ($CapabilitiesRegistry -and $CapabilitiesRegistry.capabilities) {
        foreach ($cap in $CapabilitiesRegistry.capabilities) {
            if (-not $cap.hostMappings) { continue }

            $sourceRoot = Resolve-RegistryOwnedPath ([string]$cap.canonicalSource)
            if (-not $sourceRoot) { continue }

            $mcpManifest = Join-Path $sourceRoot '.mcp.json'
            if (-not (Test-Path -LiteralPath $mcpManifest)) { continue }

            try {
                $manifestJson = Get-Content -LiteralPath $mcpManifest -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                continue
            }

            if (-not $manifestJson.mcpServers) { continue }
            $serverKeys = @($manifestJson.mcpServers.PSObject.Properties.Name | ForEach-Object { Resolve-McpAliasKey $_ })

            foreach ($mapping in $cap.hostMappings) {
                $deploymentStatus = [string]$mapping.deploymentStatus
                if ($deploymentStatus -notin @(
                    'plugin-owned',
                    'native-plugin-installed',
                    'native-local-plugin',
                    'native-extension-junction'
                )) {
                    continue
                }
                # Some hosts load the capability through a native plugin
                # adapter while intentionally keeping MCP ownership in the
                # shared registry. Copilot's Product Demo Studio adapter is
                # one example: its generated plugin tree strips .mcp.json so
                # the shared Descript registration remains the only owner.
                if ([string]$mapping.mcpOwnership -eq 'shared-registry') {
                    continue
                }
                $hostId = [string]$mapping.hostId
                if (-not $hostId) { continue }
                if (-not $result.ContainsKey($hostId)) { $result[$hostId] = @{} }
                foreach ($k in $serverKeys) {
                    $result[$hostId][$k] = $true
                }
            }
        }
    }

    if ($ConnectorRegistry -and $ConnectorRegistry.hosts) {
        foreach ($connectorHost in @($ConnectorRegistry.hosts)) {
            try {
                $effective = Get-ConnectorHostRow -HostId ([string]$connectorHost.hostId) -ConnectorRegistry $ConnectorRegistry
                if (-not $effective -or
                    [bool]$effective.providerHeld -or
                    -not $effective.exposures) {
                    continue
                }
                $classified = @()
                $validExposureRow = $true
                foreach ($mode in @('plugin-owned', 'native-connector', 'shared-gateway', 'local-only')) {
                    $property = $effective.exposures.PSObject.Properties[$mode]
                    if (-not $property) {
                        $validExposureRow = $false
                        break
                    }
                    $classified += @($property.Value | ForEach-Object {
                        Resolve-McpAliasKey ([string]$_)
                    })
                }
                if (-not $validExposureRow -or
                    @($classified | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9._-]*$' }).Count -gt 0 -or
                    @($classified | Sort-Object -Unique).Count -ne $classified.Count) {
                    continue
                }
            } catch {
                # A malformed connector registry must never suppress direct MCPs.
                continue
            }
            $hostId = [string]$connectorHost.hostId
            if (-not $result.ContainsKey($hostId)) { $result[$hostId] = @{} }
            foreach ($mode in @('plugin-owned', 'native-connector')) {
                $property = $effective.exposures.PSObject.Properties[$mode]
                if (-not $property) { continue }
                foreach ($mcpId in @($property.Value)) {
                    $result[$hostId][(Resolve-McpAliasKey ([string]$mcpId))] = $true
                }
            }
        }
    }

    return $result
}

function Get-ConnectorHostRow {
    param(
        [string]$HostId,
        [object]$ConnectorRegistry,
        [string[]]$Visited = @()
    )

    if (-not $ConnectorRegistry -or -not $ConnectorRegistry.hosts) { return $null }
    if ($HostId -in $Visited) { throw "Connector host inheritance cycle at '$HostId'." }
    $row = @($ConnectorRegistry.hosts | Where-Object hostId -eq $HostId)
    if ($row.Count -ne 1) { return $null }
    if ($row[0].PSObject.Properties['inheritsHostId'] -and $row[0].inheritsHostId) {
        return Get-ConnectorHostRow -HostId ([string]$row[0].inheritsHostId) -ConnectorRegistry $ConnectorRegistry -Visited (@($Visited) + $HostId)
    }
    return $row[0]
}

function Get-GatewayPlanForHost {
    param(
        [string]$HostId,
        [object]$GatewayRegistry,
        [object]$ConnectorRegistry
    )

    try {
        if (-not $GatewayRegistry -or
            [string]::IsNullOrWhiteSpace([string]$GatewayRegistry.selectedCandidateId)) {
            return $null
        }

        $candidate = @($GatewayRegistry.candidates | Where-Object {
            [string]$_.id -ceq [string]$GatewayRegistry.selectedCandidateId
        })
        if ($candidate.Count -ne 1 -or
            [string]$candidate[0].activationState -cne 'validated' -or
            -not [bool]$candidate[0].generationEnabled) {
            return $null
        }

        $selectedProfileId = [string]$candidate[0].selectedProfileId
        if ($selectedProfileId -notmatch '^[a-z0-9][a-z0-9._-]*$') { return $null }
        $profiles = @($candidate[0].profiles | Where-Object {
            [string]$_.id -ceq $selectedProfileId
        })
        if ($profiles.Count -ne 1 -or
            [string]$profiles[0].activationState -cne 'validated') {
            return $null
        }
        $profile = $profiles[0]

        $endpoint = $candidate[0].endpoint
        if (-not $endpoint -or
            [string]$endpoint.boundProfileId -cne $selectedProfileId -or
            [string]$endpoint.transport -cne 'streaming' -or
            [string]$endpoint.authScheme -cne 'bearer' -or
            [string]$endpoint.id -notmatch '^[a-z0-9][a-z0-9._-]*$' -or
            [string]$endpoint.authTokenEnvironment -notmatch '^[A-Z_][A-Z0-9_]*$') {
            return $null
        }
        $endpointUri = [Uri]::new([string]$endpoint.url, [UriKind]::Absolute)
        $declaredBindAddress = [string]$endpoint.bindAddress
        $declaredPort = [int]$endpoint.port
        $declaredPath = [string]$endpoint.path
        $normalizedUriHost = $endpointUri.Host.Trim('[', ']')
        $normalizedBindAddress = $declaredBindAddress.Trim('[', ']')
        if ($endpointUri.Scheme -notin @('http', 'https') -or
            -not $endpointUri.IsLoopback -or
            -not [string]::IsNullOrEmpty($endpointUri.UserInfo) -or
            [string]::IsNullOrWhiteSpace($declaredBindAddress) -or
            -not $normalizedUriHost.Equals(
                $normalizedBindAddress,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -or
            $declaredPort -lt 1 -or
            $declaredPort -gt 65535 -or
            $endpointUri.Port -ne $declaredPort -or
            $declaredPath -notmatch '^/[^?#]*$' -or
            $endpointUri.AbsolutePath -cne $declaredPath -or
            -not [string]::IsNullOrEmpty($endpointUri.Query) -or
            -not [string]::IsNullOrEmpty($endpointUri.Fragment)) {
            return $null
        }

        $connectorRow = Get-ConnectorHostRow -HostId $HostId -ConnectorRegistry $ConnectorRegistry
        if (-not $connectorRow -or
            [bool]$connectorRow.providerHeld -or
            -not $connectorRow.exposures) {
            return $null
        }
        $shared = @($connectorRow.exposures.'shared-gateway' | ForEach-Object {
            Resolve-McpAliasKey ([string]$_)
        })
        $pluginOwned = @($connectorRow.exposures.'plugin-owned' | ForEach-Object {
            Resolve-McpAliasKey ([string]$_)
        })
        $nativeOwned = @($connectorRow.exposures.'native-connector' | ForEach-Object {
            Resolve-McpAliasKey ([string]$_)
        })

        $mapping = @($profile.hostMappings | Where-Object {
            [string]$_.hostId -ceq $HostId -and [string]$_.state -ceq 'enabled'
        })
        if ($mapping.Count -ne 1) { return $null }

        $managedKeys = @($profile.mcpServerIds | ForEach-Object {
            Resolve-McpAliasKey ([string]$_)
        })
        if ($managedKeys.Count -eq 0 -or
            @($managedKeys | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9._-]*$' }).Count -gt 0 -or
            @($managedKeys | Sort-Object -Unique).Count -ne $managedKeys.Count -or
            @($managedKeys | Where-Object { $_ -notin $shared }).Count -gt 0 -or
            @($managedKeys | Where-Object { $_ -in $pluginOwned -or $_ -in $nativeOwned }).Count -gt 0) {
            return $null
        }

        return @{
            entryKey = [string]$endpoint.id
            entry = @{
                type = 'http'
                url = $endpointUri.AbsoluteUri
                headers = @{
                    Authorization = 'Bearer ${env:' + [string]$endpoint.authTokenEnvironment + '}'
                }
            }
            managedKeys = @($managedKeys)
            profileId = $selectedProfileId
        }
    } catch {
        # Registry drift must never suppress a direct MCP registration.
        return $null
    }
}

function Get-HostMcpEntries {
    param(
        [string]$HostId,
        [hashtable]$BaseEntries,
        [hashtable]$HostAllowlist,
        [hashtable]$HostConfigOverrides,
        [hashtable]$PluginProvidedByHost,
        [object]$GatewayPlan
    )

    $filtered = @{}
    foreach ($key in $BaseEntries.Keys) {
        $resolved = Resolve-McpAliasKey $key
        if ($HostAllowlist.ContainsKey($resolved) -and $HostId -notin $HostAllowlist[$resolved]) { continue }
        if ($PluginProvidedByHost.ContainsKey($HostId) -and $PluginProvidedByHost[$HostId].ContainsKey($resolved)) { continue }
        if ($GatewayPlan -and $resolved -in @($GatewayPlan.managedKeys)) { continue }
        $entry = ConvertTo-Hashtable $BaseEntries[$key]
        if ($HostConfigOverrides.ContainsKey($HostId) -and
            $HostConfigOverrides[$HostId].ContainsKey($resolved)) {
            foreach ($override in $HostConfigOverrides[$HostId][$resolved].GetEnumerator()) {
                $entry[$override.Key] = ConvertTo-Hashtable $override.Value
            }
        }
        $filtered[$key] = $entry
    }
    if ($GatewayPlan) {
        $filtered[[string]$GatewayPlan.entryKey] = ConvertTo-Hashtable $GatewayPlan.entry
    }
    return $filtered
}

# ---------------------------------------------------------------------------
# Host adapters
# ---------------------------------------------------------------------------
$driftReport = @{
    generatedAt = (Get-Date -Format "o")
    auditMode   = $Audit.IsPresent
    hosts       = @()
}

function Sync-HostMcp-Claude {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$PluginOwnedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )
    $path = $Agent.nativePaths.mcpUser
    if (-not $path) { return @{ status='unsupported' } }

    $json = @{}
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $json = ConvertTo-Hashtable $existing
    }
    if (-not $json.ContainsKey('mcpServers')) { $json.mcpServers = @{} }
    elseif (-not ($json.mcpServers -is [hashtable])) { $json.mcpServers = ConvertTo-Hashtable $json.mcpServers }

    # Plugin-owned and lifecycle-suppressed MCPs must be removed even when
    # broad pruning is disabled. Remove canonical keys and declared migration
    # aliases narrowly; unrelated user registrations remain intact.
    $json.mcpServers = Remove-McpTargetKeys `
        -Target $json.mcpServers `
        -Keys $PluginOwnedKeys

    $claudeEntries = @{}
    foreach ($key in @($McpEntries.Keys | Sort-Object)) {
        $entry = ConvertTo-Hashtable $McpEntries[$key]
        if ($entry.headers) {
            $headers = @{}
            foreach ($header in (ConvertTo-Hashtable $entry.headers).GetEnumerator()) {
                # Claude resolves ${NAME}; the registry intentionally uses the
                # host-neutral ${env:NAME} spelling.
                $headers[$header.Key] = [regex]::Replace(
                    [string]$header.Value,
                    '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
                    { param($match) '$' + '{' + $match.Groups[1].Value + '}' }
                )
            }
            $entry.headers = $headers
        }
        $claudeEntries[$key] = $entry
    }

    $json.mcpServers = Merge-McpServers -Target $json.mcpServers -Additions $claudeEntries -PruneUnknown:$Prune
    # Merge-McpServers deliberately preserves secret-bearing headers. These
    # values are environment references rather than secrets, so normalize the
    # host syntax to prevent a stale cross-host placeholder from lingering.
    foreach ($key in $claudeEntries.Keys) {
        if ($claudeEntries[$key].headers -and $json.mcpServers.ContainsKey($key)) {
            $json.mcpServers[$key].headers = $claudeEntries[$key].headers
        }
    }

    $stableNewJson = Get-StableJsonString $json
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path $path) {
            Get-StableJsonString (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } else {
            Get-StableJsonString @{ mcpServers = @{} }
        }
        $status = if ($stableExistingJson -ne $stableNewJson) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$path }
    }

    Write-Utf8NoBom -Path $path -Content $stableNewJson
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function Get-CodexMcpSectionPattern {
    param([string]$Key)
    $escapedKey = [regex]::Escape($Key)
    # Include nested sections owned by this MCP server (for example `.env`),
    # but stop at every unrelated TOML section. This prevents the final MCP
    # entry from consuming plugin/marketplace settings appended after it.
    return '(?ms)^\[mcp_servers\.' + $escapedKey + '\]\r?\n.*?(?=^\[(?!mcp_servers\.' + $escapedKey + '\.)[^\]]+\]\r?$|\z)'
}

function Set-CodexManagedMarketplaceSources {
    param(
        [string]$Toml,
        [object]$ConnectorRegistry
    )

    if (-not $ConnectorRegistry -or
        -not $ConnectorRegistry.PSObject.Properties['managedMarketplaces']) {
        return $Toml
    }

    $agentHubRows = @($ConnectorRegistry.managedMarketplaces | Where-Object {
        $_.hostId -eq 'codex' -and
        [string]$_.name -eq 'agenthub' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.sourcePath)
    })
    if ($agentHubRows.Count -eq 0) { return $Toml }
    if ($agentHubRows.Count -ne 1) {
        throw "Expected one managed Codex AgentHub marketplace; found $($agentHubRows.Count)."
    }

    $expectedSource = '\\?\' + [IO.Path]::GetFullPath(
        ([string]$agentHubRows[0].sourcePath).Replace('/', '\')
    ).TrimEnd('\')
    $sourceLine = "source = '$expectedSource'"
    $sectionPattern = '(?ms)^\[marketplaces\.agenthub\]\s*$.*?(?=^\[|\z)'
    if ($Toml -match $sectionPattern) {
        $section = $Matches[0]
        if ($section -match '(?m)^source\s*=') {
            $newSection = $section -replace '(?m)^source\s*=.*$', $sourceLine
        } else {
            $newSection = $section.TrimEnd() + [Environment]::NewLine +
                $sourceLine + [Environment]::NewLine
        }
        $Toml = [regex]::Replace(
            $Toml,
            $sectionPattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                return $newSection
            },
            1
        )
        foreach ($legacyName in @('handoff', 'portfolio')) {
            $legacyPattern = '(?ms)^\[marketplaces\.' +
                [regex]::Escape($legacyName) + '\]\s*$.*?(?=^\[|\z)'
            $Toml = [regex]::Replace($Toml, $legacyPattern, '')
        }
        return $Toml
    }

    throw 'Codex AgentHub marketplace is missing while the connector registry records an installed AgentHub plugin. Restore it through Codex plugin management before synchronizing.'
}

function ConvertTo-HostEnvironmentReference {
    param(
        [string]$Value,
        [string]$TargetHost
    )

    if ($TargetHost -in @('grok', 'hermes')) {
        return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', {
            param($match)
            return '${' + $match.Groups[1].Value + '}'
        })
    }
    return $Value
}

function Sync-HostMcp-Codex {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$PluginOwnedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )
    $path = $Agent.nativePaths.config
    if (-not (Test-Path -LiteralPath $path)) { return @{ status='config-missing' } }

    $toml = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $newToml = $toml

    # Remove only entries with an explicit native-plugin owner or lifecycle
    # suppression, including their declared migration aliases. Keep all other
    # unregistered TOML sections intact unless broad prune is requested.
    foreach ($key in $PluginOwnedKeys) {
        $resolved = Resolve-McpAliasKey $key
        foreach ($candidate in @($resolved) + @(Get-McpAliasesForCanonicalKey $resolved)) {
            $newToml = [regex]::Replace(
                $newToml,
                (Get-CodexMcpSectionPattern $candidate),
                ''
            )
        }
    }

    foreach ($key in $McpEntries.Keys) {
        $entry = $McpEntries[$key]
        foreach ($alias in @(Get-McpAliasesForCanonicalKey $key)) {
            $newToml = [regex]::Replace($newToml, (Get-CodexMcpSectionPattern $alias), '')
        }
        $sectionLines = @("[mcp_servers.$key]")
        if ($entry.type -eq 'http' -and $entry.url) {
            $sectionLines += "url = `"$($entry.url)`""

            # Codex natively supports a bearer-token environment variable for
            # remote MCPs, but not arbitrary request headers. Convert the
            # canonical header reference without ever resolving its secret.
            if ($entry.headers -and $entry.headers.Authorization -match '^Bearer \$\{env:([A-Za-z_][A-Za-z0-9_]*)\}$') {
                $sectionLines += "bearer_token_env_var = `"$($Matches[1])`""
            }
        } elseif ($entry.command) {
            $sectionLines += "command = `"$($entry.command)`""
            $argsStr = ($entry.args | ForEach-Object { '"' + (($_ -replace '\\','\\\\') -replace '"','\"') + '"' }) -join ', '
            $sectionLines += "args = [$argsStr]"
            if ($entry.ContainsKey('startup_timeout_ms')) {
                $sectionLines += "startup_timeout_ms = $([int]$entry.startup_timeout_ms)"
            }
            if ($entry.env -and $entry.env.Count -gt 0) {
                $sectionLines += "[mcp_servers.$key.env]"
                foreach ($e in @($entry.env.GetEnumerator() | Sort-Object Key)) {
                    $escapedValue = ([string]$e.Value).Replace('\', '\\').Replace('"', '\"')
                    $sectionLines += "$($e.Key) = `"$escapedValue`""
                }
            }
        }

        $sectionText = ($sectionLines -join [Environment]::NewLine) + [Environment]::NewLine
        $sectionPattern = Get-CodexMcpSectionPattern $key
        if ($newToml -match $sectionPattern) {
            $newToml = [regex]::Replace($newToml, $sectionPattern, $sectionText)
        } else {
            if ($newToml.Length -gt 0 -and -not $newToml.EndsWith("`n")) { $newToml += [Environment]::NewLine }
            $newToml += [Environment]::NewLine + $sectionText
        }
    }

    if ($Prune) {
        $keep = @{}
        foreach ($k in $McpEntries.Keys) {
            $keep[(Resolve-McpAliasKey $k)] = $true
        }

        # Remove non-canonical top-level mcp_servers sections.
        $topLevelMatches = [regex]::Matches($newToml, '(?m)^\[mcp_servers\.([^\].]+)\]$')
        $topLevelKeys = @()
        foreach ($m in $topLevelMatches) { $topLevelKeys += $m.Groups[1].Value }
        $topLevelKeys = $topLevelKeys | Sort-Object -Unique
        foreach ($k in $topLevelKeys) {
            $resolved = Resolve-McpAliasKey $k
            if ($resolved -ne $k) {
                $sectionPattern = Get-CodexMcpSectionPattern $k
                $newToml = [regex]::Replace($newToml, $sectionPattern, '')
                continue
            }
            if ($keep.ContainsKey($resolved)) { continue }
            $sectionPattern = Get-CodexMcpSectionPattern $k
            $newToml = [regex]::Replace($newToml, $sectionPattern, '')
        }
    }

    $newToml = Set-CodexManagedMarketplaceSources `
        -Toml $newToml `
        -ConnectorRegistry $connectorReg

    if ($WhatIf) {
        $status = if ($toml -ne $newToml) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$path }
    }

    [System.IO.File]::WriteAllText($path, $newToml, [System.Text.UTF8Encoding]::new($false))
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function Sync-HostMcp-Grok {
    param(
        [Parameter(Mandatory)]$Agent,
        [Parameter(Mandatory)][hashtable]$Mcps,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )

    # Grok CLI uses TOML sections compatible with Codex's mcp_servers shape,
    # but environment interpolation is ${NAME}, not ${env:NAME}.
    $path = $Agent.nativePaths.config
    $existing = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { '' }
    $original = $existing
    $blocks = [System.Collections.Generic.List[string]]::new()

    foreach ($name in @($SuppressedKeys)) {
        $existing = [regex]::Replace($existing, (Get-CodexMcpSectionPattern -Key $name), '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($alias in @(Get-McpAliasesForCanonicalKey $name)) {
            $existing = [regex]::Replace($existing, (Get-CodexMcpSectionPattern -Key $alias), '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        }
    }

    foreach ($name in @($Mcps.Keys | Sort-Object)) {
        $mcp = $Mcps[$name]
        $sectionPattern = Get-CodexMcpSectionPattern -Key $name
        $existing = [regex]::Replace($existing, $sectionPattern, '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($alias in @(Get-McpAliasesForCanonicalKey $name)) {
            $existing = [regex]::Replace($existing, (Get-CodexMcpSectionPattern -Key $alias), '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $null = $lines.Add("[mcp_servers.$name]")
        if ($mcp.ContainsKey('enabled')) {
            $enabled = if ([bool]$mcp.enabled) { 'true' } else { 'false' }
            $null = $lines.Add("enabled = $enabled")
        }
        if ($mcp.type -eq 'http') {
            $url = ConvertTo-HostEnvironmentReference -Value $mcp.url -TargetHost 'grok'
            $null = $lines.Add("url = `"$url`"")
            if ($mcp.headers) {
                $pairs = @($mcp.headers.GetEnumerator() | Sort-Object Key | ForEach-Object {
                    $headerValue = ConvertTo-HostEnvironmentReference -Value ([string]$_.Value) -TargetHost 'grok'
                    "`"$($_.Key)`" = `"$headerValue`""
                })
                if ($pairs.Count -gt 0) { $null = $lines.Add("headers = { $($pairs -join ', ') }") }
            }
        }
        else {
            $null = $lines.Add("command = `"$($mcp.command)`"")
            if ($mcp.args) {
                $args = @($mcp.args | ForEach-Object { "`"$_`"" })
                $null = $lines.Add("args = [$($args -join ', ')]")
            }
            if ($mcp.env) {
                foreach ($property in @($mcp.env.GetEnumerator() | Sort-Object Key)) {
                    $value = ConvertTo-HostEnvironmentReference -Value ([string]$property.Value) -TargetHost 'grok'
                    $null = $lines.Add("[mcp_servers.$name.env]")
                    $null = $lines.Add("$($property.Key) = `"$value`"")
                }
            }
        }
        $null = $blocks.Add(($lines -join "`n"))
    }

    if ($Prune) {
        foreach ($name in @('context7', 'firecrawl', 'tavily', 'exa', 'linear', 'notion', 'brave-search', 'playwright')) {
            $sectionPattern = Get-CodexMcpSectionPattern -Key $name
            $existing = [regex]::Replace($existing, $sectionPattern, '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        }
    }

    $updated = $existing.TrimEnd()
    if ($updated) { $updated += "`n`n" }
    $updated += ($blocks -join "`n`n") + "`n"
    if ($WhatIf) {
        $status = if ($original.TrimEnd() -eq $updated.TrimEnd()) { 'unchanged' } else { 'drift' }
        return @{ status = $status; path = $path }
    }
    Write-Utf8NoBom -Path $path -Content $updated
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function Sync-HostMcp-Hermes {
    param(
        [Parameter(Mandatory)]$Agent,
        [Parameter(Mandatory)][hashtable]$Mcps,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf
    )

    # Hermes has a root-level YAML mcp_servers mapping. Replace fleet-managed
    # entries while preserving unregistered user MCP entries and all other YAML.
    $path = $Agent.nativePaths.config
    if (-not (Test-Path -LiteralPath $path)) {
        return @{ status='not-verified'; path=$path; reason='Hermes is absent; discovery skipped' }
    }
    $existing = Get-Content -LiteralPath $path -Raw
    $original = $existing
    $lines = [System.Collections.Generic.List[string]]::new()
    $null = $lines.Add('mcp_servers:')
    foreach ($name in @($Mcps.Keys | Sort-Object)) {
        $mcp = $Mcps[$name]
        $null = $lines.Add("  ${name}:")
        if ($mcp.type -eq 'http') {
            $url = ConvertTo-HostEnvironmentReference -Value $mcp.url -TargetHost 'hermes'
            $null = $lines.Add("    url: `"$url`"")
            if ($mcp.auth) { $null = $lines.Add("    auth: $($mcp.auth)") }
            if ($mcp.headers) {
                $null = $lines.Add('    headers:')
                foreach ($property in @($mcp.headers.GetEnumerator() | Sort-Object Key)) {
                    $value = ConvertTo-HostEnvironmentReference -Value ([string]$property.Value) -TargetHost 'hermes'
                    $null = $lines.Add("      $($property.Key): `"$value`"")
                }
            }
        }
        else {
            $null = $lines.Add("    command: `"$($mcp.command)`"")
            if ($mcp.args) {
                $args = @($mcp.args | ForEach-Object { "`"$_`"" })
                $null = $lines.Add("    args: [$($args -join ', ')]")
            }
            if ($mcp.env) {
                $null = $lines.Add('    env:')
                foreach ($property in @($mcp.env.GetEnumerator() | Sort-Object Key)) {
                    $value = ConvertTo-HostEnvironmentReference -Value ([string]$property.Value) -TargetHost 'hermes'
                    $null = $lines.Add("      $($property.Key): `"$value`"")
                }
            }
        }
    }
    $mcpBlock = ($lines -join "`n") + "`n"
    $sectionPattern = '(?ms)^mcp_servers:\s*(?:\r?\n.*?)*(?=^[A-Za-z_][A-Za-z0-9_-]*:\s*(?:#.*)?\r?$|\z)'
    if ($existing -match '(?m)^mcp_servers:\s*$') {
        $sectionMatch = [regex]::Match($existing, $sectionPattern)
        $managedNames = @{}
        foreach ($name in $Mcps.Keys) { $managedNames[(Resolve-McpAliasKey $name)] = $true }
        foreach ($name in $SuppressedKeys) { $managedNames[(Resolve-McpAliasKey $name)] = $true }
        $preservedEntries = [System.Collections.Generic.List[string]]::new()
        # Determine the existing direct-child indentation dynamically, then
        # accept normal YAML keys (including dotted, spaced, and quoted names).
        $anyChildPattern = '(?m)^(?<indent>[ \t]+)(?<key>"(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*''|[^\s:\r\n][^:\r\n]*):(?:\s|$)'
        $firstChild = [regex]::Match($sectionMatch.Value, $anyChildPattern)
        if ($firstChild.Success) {
            $existingIndent = $firstChild.Groups['indent'].Value
            $escapedIndent = [regex]::Escape($existingIndent)
            $entryPattern = '(?m)^' + $escapedIndent + '(?<key>"(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*''|[^\s:\r\n][^:\r\n]*):(?:\s|$)'
            $entryMatches = [regex]::Matches($sectionMatch.Value, $entryPattern)
            for ($index = 0; $index -lt $entryMatches.Count; $index++) {
                $entry = $entryMatches[$index]
                $entryName = $entry.Groups['key'].Value.Trim()
                if (($entryName.StartsWith('"') -and $entryName.EndsWith('"')) -or ($entryName.StartsWith("'") -and $entryName.EndsWith("'"))) {
                    $entryName = $entryName.Substring(1, $entryName.Length - 2)
                }
                $entryEnd = if ($index + 1 -lt $entryMatches.Count) { $entryMatches[$index + 1].Index } else { $sectionMatch.Value.Length }
                if (-not $managedNames.ContainsKey((Resolve-McpAliasKey $entryName))) {
                    $rawEntry = $sectionMatch.Value.Substring($entry.Index, $entryEnd - $entry.Index).TrimEnd()
                    $normalizedEntry = [regex]::Replace($rawEntry, '(?m)^' + $escapedIndent, '  ')
                    $null = $preservedEntries.Add($normalizedEntry)
                }
            }
        }
        if ($preservedEntries.Count -gt 0) {
            $mcpBlock = $mcpBlock.TrimEnd() + "`n" + ($preservedEntries -join "`n") + "`n"
        }
        $updated = $existing.Substring(0, $sectionMatch.Index) + $mcpBlock + $existing.Substring($sectionMatch.Index + $sectionMatch.Length)
    }
    else {
        $updated = $mcpBlock + $(if ($existing) { "`n$existing" } else { '' })
    }
    if ($WhatIf) {
        $status = if ($original.TrimEnd() -eq $updated.TrimEnd()) { 'unchanged' } else { 'drift' }
        return @{ status = $status; path = $path }
    }
    Write-Utf8NoBom -Path $path -Content $updated
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function ConvertTo-QwenMcpEntry {
    param([hashtable]$Canonical)
    $entry = @{}
    if ($Canonical.type -eq 'http') {
        $entry.httpUrl = $Canonical.url
        if ($Canonical.headers) {
            # The shared registry uses the host-neutral ${env:NAME} notation.
            # Qwen resolves string values using $NAME / ${NAME}; translate only
            # the reference syntax and never resolve or serialize its value.
            $headers = @{}
            foreach ($header in (ConvertTo-Hashtable $Canonical.headers).GetEnumerator()) {
                $headers[$header.Key] = [regex]::Replace(
                    [string]$header.Value,
                    '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
                    { param($match) '$' + '{' + $match.Groups[1].Value + '}' }
                )
            }
            $entry.headers = $headers
        }
    } elseif ($Canonical.type -eq 'stdio') {
        $entry.command = $Canonical.command
        $entry.args = @($Canonical.args)
        if ($Canonical.env) {
            $environment = @{}
            foreach ($variable in (ConvertTo-Hashtable $Canonical.env).GetEnumerator()) {
                $environment[$variable.Key] = [regex]::Replace(
                    [string]$variable.Value,
                    '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
                    { param($match) '$' + '{' + $match.Groups[1].Value + '}' }
                )
            }
            $entry.env = $environment
        }
    }
    return $entry
}

function Sync-HostMcp-Qwen {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )
    $path = $Agent.nativePaths.settings
    $json = @{}
    if (Test-Path -LiteralPath $path) {
        $json = ConvertTo-Hashtable (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    if (-not $json.ContainsKey('mcpServers')) { $json.mcpServers = @{} }
    elseif (-not ($json.mcpServers -is [hashtable])) { $json.mcpServers = ConvertTo-Hashtable $json.mcpServers }
    $json.mcpServers = Normalize-McpTargetKeys -Target $json.mcpServers
    $json.mcpServers = Remove-McpTargetKeys -Target $json.mcpServers -Keys $SuppressedKeys

    $canonicalKeys = @{}
    foreach ($key in $McpEntries.Keys) {
        $resolved = Resolve-McpAliasKey $key
        $canonicalKeys[$resolved] = $true
        $canonical = $McpEntries[$key]
        if (-not ($canonical -is [hashtable])) { $canonical = ConvertTo-Hashtable $canonical }
        $json.mcpServers[$resolved] = ConvertTo-QwenMcpEntry $canonical
    }

    # Qwen treats mcp.allowed as an explicit connection allowlist when it is
    # present. Keep the user's existing allowlist, retire known aliases, and
    # add every registry-managed server so a successfully rendered definition
    # is not silently blocked at runtime.
    if ($json.ContainsKey('mcp')) {
        if (-not ($json.mcp -is [hashtable])) { $json.mcp = ConvertTo-Hashtable $json.mcp }
        if ($json.mcp.ContainsKey('allowed') -and $null -ne $json.mcp.allowed) {
            $suppressedLookup = @{}
            foreach ($suppressedKey in $SuppressedKeys) {
                $suppressedLookup[(Resolve-McpAliasKey ([string]$suppressedKey))] = $true
            }
            $allowed = @($json.mcp.allowed | ForEach-Object {
                Resolve-McpAliasKey ([string]$_)
            } | Where-Object { -not $suppressedLookup.ContainsKey([string]$_) })
            $allowed += @($canonicalKeys.Keys)
            $json.mcp.allowed = @($allowed | Sort-Object -Unique)
        }
    }

    if ($Prune) {
        foreach ($key in @($json.mcpServers.Keys)) {
            if (-not $canonicalKeys.ContainsKey((Resolve-McpAliasKey $key))) { $json.mcpServers.Remove($key) }
        }
    }

    $stableNewJson = Get-StableJsonString $json
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path -LiteralPath $path) { Get-StableJsonString (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } else { Get-StableJsonString @{} }
        $status = if ($stableExistingJson -ne $stableNewJson) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$path }
    }

    Write-Utf8NoBom -Path $path -Content $stableNewJson
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function Sync-QwenCapabilityExtensions {
    param(
        [pscustomobject]$Agent,
        [pscustomobject]$CapabilitiesRegistry,
        [switch]$WhatIf,
        [switch]$Prune
    )

    $extensionsRoot = $Agent.nativePaths.extensionsDir
    if (-not $extensionsRoot) { return @{ status='unsupported-path'; note='Qwen extensions path missing' } }

    $adapterRoot = Join-Path $RuntimeDir 'runtime\qwen-code\extensions'
    $expected = @()
    foreach ($capability in @($CapabilitiesRegistry.capabilities)) {
        $mapping = @($capability.hostMappings | Where-Object {
            $_.hostId -eq 'qwen-code' -and $_.deploymentStatus -in @('managed','native-extension-junction')
        })
        if ($mapping.Count -eq 0) { continue }

        $sourceSkills = Join-Path (
            Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
        ) 'skills'
        if (-not (Test-Path -LiteralPath $sourceSkills)) { continue }
        $sourceAgents = Join-Path (
            Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
        ) 'agents'
        $hasSourceAgents = Test-Path -LiteralPath $sourceAgents -PathType Container
        $extensionName = 'agenthub-' + [string]$capability.id
        $expected += $extensionName
        $adapterPath = Join-Path $adapterRoot $extensionName
        $manifestPath = Join-Path $adapterPath 'qwen-extension.json'
        $skillsLink = Join-Path $adapterPath 'skills'
        $agentsLink = Join-Path $adapterPath 'agents'
        $userLink = Join-Path $extensionsRoot $extensionName
        $manifest = @{ name=$extensionName; version='1.0.0'; description="Registry adapter for $($capability.id)"; skills='skills' }
        if ($hasSourceAgents) { $manifest.agents = 'agents' }
        $manifestJson = Get-StableJsonString $manifest

        $skillsItem = Get-Item -LiteralPath $skillsLink -Force -ErrorAction SilentlyContinue
        $agentsItem = Get-Item -LiteralPath $agentsLink -Force -ErrorAction SilentlyContinue
        $userItem = Get-Item -LiteralPath $userLink -Force -ErrorAction SilentlyContinue
        $skillsTarget = if ($skillsItem -and $skillsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [string]$skillsItem.Target
        } else { '' }
        $agentsTarget = if ($agentsItem -and $agentsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [string]$agentsItem.Target
        } else { '' }
        $userTarget = if ($userItem -and $userItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [string]$userItem.Target
        } else { '' }
        $agentsReady = if ($hasSourceAgents) {
            $agentsTarget -and
            [IO.Path]::GetFullPath($agentsTarget) -eq [IO.Path]::GetFullPath($sourceAgents)
        } else {
            -not $agentsItem
        }
        $adapterReady = (
            (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
            ((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8) -eq $manifestJson) -and
            $skillsTarget -and
            [IO.Path]::GetFullPath($skillsTarget) -eq [IO.Path]::GetFullPath($sourceSkills) -and
            $agentsReady
        )
        $userReady = (
            $userTarget -and
            [IO.Path]::GetFullPath($userTarget) -eq [IO.Path]::GetFullPath($adapterPath)
        )
        if ($WhatIf) {
            if (-not ($adapterReady -and $userReady)) { return @{ status='drift'; path=$extensionsRoot } }
            continue
        }

        if (-not (Test-Path -LiteralPath $adapterPath)) { New-Item -ItemType Directory -Path $adapterPath -Force | Out-Null }
        $manifestJson | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -NoNewline
        if ($skillsItem -and -not $skillsTarget) {
            throw "Refusing to replace non-junction Qwen adapter path: $skillsLink"
        }
        if ($skillsItem -and -not $adapterReady) {
            Remove-Item -LiteralPath $skillsLink -Force
            $skillsItem = $null
        }
        if (-not $skillsItem) {
            New-Item -ItemType Junction -Path $skillsLink -Target $sourceSkills | Out-Null
        }
        if ($agentsItem -and -not $agentsTarget) {
            throw "Refusing to replace non-junction Qwen adapter path: $agentsLink"
        }
        if ($agentsItem -and -not $agentsReady) {
            Remove-Item -LiteralPath $agentsLink -Force
            $agentsItem = $null
        }
        if ($hasSourceAgents -and -not $agentsItem) {
            New-Item -ItemType Junction -Path $agentsLink -Target $sourceAgents | Out-Null
        } elseif (-not $hasSourceAgents -and $agentsItem) {
            Remove-Item -LiteralPath $agentsLink -Force
        }
        if (-not (Test-Path -LiteralPath $extensionsRoot)) { New-Item -ItemType Directory -Path $extensionsRoot -Force | Out-Null }
        if ($userItem -and -not $userTarget) {
            throw "Refusing to replace non-junction Qwen extension path: $userLink"
        }
        if ($userItem -and -not $userReady) {
            Remove-Item -LiteralPath $userLink -Force
            $userItem = $null
        }
        if (-not $userItem) {
            New-Item -ItemType Junction -Path $userLink -Target $adapterPath | Out-Null
        }
    }

    if ($Prune -and -not $WhatIf) {
        foreach ($userPath in @(Get-ChildItem -LiteralPath $extensionsRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'agenthub-*' -and $_.Name -notin $expected })) {
            if (-not ($userPath.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing to prune non-junction Qwen extension path: $($userPath.FullName)"
            }
            Remove-Item -LiteralPath $userPath.FullName -Force
        }
        foreach ($adapterPath in @(Get-ChildItem -LiteralPath $adapterRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'agenthub-*' -and $_.Name -notin $expected })) {
            $resolvedAdapter = [IO.Path]::GetFullPath($adapterPath.FullName)
            $resolvedRoot = [IO.Path]::GetFullPath($adapterRoot).TrimEnd('\') + '\'
            if (-not $resolvedAdapter.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to prune Qwen adapter outside managed runtime: $resolvedAdapter"
            }
            Remove-Item -LiteralPath $resolvedAdapter -Recurse -Force
        }
    }
    $status = if ($WhatIf) { 'unchanged' } else { 'updated' }
    return @{ status=$status; path=$extensionsRoot; count=$expected.Count }
}

function Sync-HostMcp-JsonFile {
    param(
        [string]$Path,
        [hashtable]$McpEntries,
        [string]$JsonProperty = 'mcpServers',
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )
    $json = @{}
    if ($JsonProperty -eq 'mcpServers') { $json.mcpServers = @{} }
    elseif ($JsonProperty -eq 'servers') { $json.servers = @{} }
    elseif ($JsonProperty -eq 'amp.mcpServers') { $json.'amp.mcpServers' = @{} }

    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $json = @{}
        $existing.PSObject.Properties | ForEach-Object { $json[$_.Name] = (ConvertTo-Hashtable $_.Value) }
        if (-not $json[$JsonProperty]) { $json[$JsonProperty] = @{} }
    }

    $json[$JsonProperty] = Remove-McpTargetKeys -Target $json[$JsonProperty] -Keys $SuppressedKeys
    $json[$JsonProperty] = Merge-McpServers -Target $json[$JsonProperty] -Additions $McpEntries -PruneUnknown:$Prune

    $stableNewJson = Get-StableJsonString $json
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path $Path) {
            Get-StableJsonString (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } else {
            Get-StableJsonString @{}
        }
        $status = if ($stableExistingJson -ne $stableNewJson) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$Path }
    }

    $destDir = Split-Path $Path -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Utf8NoBom -Path $Path -Content $stableNewJson
    $script:state.managedFiles[$Path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $Path) }
    return @{ status='updated'; path=$Path }
}

function Convert-McpEnvironmentReference {
    param(
        [string]$Value,
        [ValidateSet('braced','dollar')]
        [string]$Style
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    return [regex]::Replace(
        $Value,
        '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
        {
            param($match)
            if ($Style -eq 'dollar') { return '$' + $match.Groups[1].Value }
            return '$' + '{' + $match.Groups[1].Value + '}'
        }
    )
}

function Convert-McpStringMapEnvironmentReferences {
    param(
        [object]$Map,
        [ValidateSet('braced','dollar')]
        [string]$Style
    )

    $converted = @{}
    foreach ($property in (ConvertTo-Hashtable $Map).GetEnumerator()) {
        $converted[$property.Key] = Convert-McpEnvironmentReference -Value ([string]$property.Value) -Style $Style
    }
    return $converted
}

function Sync-HostMcp-ConvertedJsonFile {
    param(
        [string]$Path,
        [hashtable]$McpEntries,
        [scriptblock]$Converter,
        [string]$JsonProperty = 'mcpServers',
        [string[]]$SuppressedKeys = @(),
        [switch]$ReplaceExistingEntries,
        [switch]$WhatIf,
        [switch]$Prune
    )

    if (-not $Path) { return @{ status='unsupported-path'; note='MCP path missing' } }

    $root = @{}
    if (Test-Path -LiteralPath $Path) {
        $root = ConvertTo-Hashtable (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    if (-not $root.ContainsKey($JsonProperty)) { $root[$JsonProperty] = @{} }
    elseif (-not ($root[$JsonProperty] -is [hashtable])) { $root[$JsonProperty] = ConvertTo-Hashtable $root[$JsonProperty] }

    $servers = Normalize-McpTargetKeys -Target $root[$JsonProperty]
    $servers = Remove-McpTargetKeys -Target $servers -Keys $SuppressedKeys
    $canonicalKeys = @{}
    foreach ($key in $McpEntries.Keys) {
        $targetKey = Resolve-McpAliasKey $key
        $canonicalKeys[$targetKey] = $true
        $canonical = $McpEntries[$key]
        if (-not ($canonical -is [hashtable])) { $canonical = ConvertTo-Hashtable $canonical }
        $target = & $Converter $canonical
        if (-not $servers.ContainsKey($targetKey)) {
            $servers[$targetKey] = $target
            continue
        }
        if ($ReplaceExistingEntries) {
            # Some host parsers reject an otherwise-valid configuration when
            # a managed entry retains an unknown historical field. For these
            # strict schemas, canonical ownership means replacing the whole
            # managed entry rather than preserving vendor-invalid residue.
            $servers[$targetKey] = $target
            continue
        }

        $existing = $servers[$targetKey]
        if (-not ($existing -is [hashtable])) { $existing = ConvertTo-Hashtable $existing }
        foreach ($field in @('type','url','httpUrl','serverUrl','command','args','cwd','working_directory','env','environment','headers','auth')) {
            if ($existing.ContainsKey($field)) { $existing.Remove($field) }
        }
        foreach ($field in $target.Keys) { $existing[$field] = $target[$field] }
        $servers[$targetKey] = $existing
    }

    if ($Prune) {
        foreach ($key in @($servers.Keys)) {
            if (-not $canonicalKeys.ContainsKey((Resolve-McpAliasKey $key))) { $servers.Remove($key) }
        }
    }

    $root[$JsonProperty] = $servers
    $stableNewJson = Get-StableJsonString $root
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path -LiteralPath $Path) {
            Get-StableJsonString (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } else {
            Get-StableJsonString @{}
        }
        return @{ status = if ($stableExistingJson -eq $stableNewJson) { 'unchanged' } else { 'drift' }; path = $Path }
    }

    $destDir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Utf8NoBom -Path $Path -Content $stableNewJson
    $script:state.managedFiles[$Path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $Path) }
    return @{ status='updated'; path=$Path }
}

function ConvertTo-GeminiMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.httpUrl = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.headers -Style braced
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.env -Style braced
        }
    }
    return $entry
}

function ConvertTo-AntigravityMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.serverUrl = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.headers -Style dollar
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.env -Style dollar
        }
    }
    return $entry
}

function ConvertTo-CopilotMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.type = 'http'
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.headers -Style braced
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.type = 'stdio'
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.env -Style braced
        }
    }
    return $entry
}

function ConvertTo-WarpMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.headers -Style braced
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.env -Style braced
        }
    }
    return $entry
}

function ConvertTo-CursorMcpEntry {
    param([hashtable]$CanonicalEntry)

    # Cursor Agent validates every entry in ~/.cursor/mcp.json as one schema.
    # A single unsupported field makes its parser discard the entire file. Its
    # remote transport accepts url and headers (with optional structured OAuth),
    # but not a generic string `auth` field or an `env` map. Keep secrets as
    # unresolved references and emit only Cursor-supported fields.
    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.headers -Style braced
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-McpStringMapEnvironmentReferences -Map $CanonicalEntry.env -Style braced
        }
        if ($CanonicalEntry.ContainsKey('cwd')) {
            $entry.cwd = $CanonicalEntry.cwd
        }
    }
    return $entry
}

function ConvertTo-ClineMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        # Cline's current runtime uses the documented Streamable HTTP transport
        # name. Keep the shared registry's environment references untouched so
        # no secret is resolved or serialized by this adapter.
        $entry.type = 'streamableHttp'
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = ConvertTo-Hashtable $CanonicalEntry.headers
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.type = 'stdio'
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('cwd')) { $entry.cwd = $CanonicalEntry.cwd }
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = ConvertTo-Hashtable $CanonicalEntry.env
        }
    }
    # Cline's default is enabled with no per-server auto-approval. YOLO is a
    # launch/profile concern and must not be persisted into MCP registrations.
    $entry.disabled = $false
    $entry.autoApprove = @()
    return $entry
}

function Sync-HostMcp-Cline {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )

    $path = $Agent.nativePaths.mcp
    if (-not $path) { return @{ status='unsupported-path'; note='Cline MCP path missing' } }

    $root = @{ mcpServers = @{} }
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $root = ConvertTo-Hashtable $existing
        if (-not $root.ContainsKey('mcpServers')) { $root.mcpServers = @{} }
    }

    $servers = Normalize-McpTargetKeys -Target (ConvertTo-Hashtable $root.mcpServers)
    $servers = Remove-McpTargetKeys -Target $servers -Keys $SuppressedKeys
    $canonicalKeys = @{}
    foreach ($key in $McpEntries.Keys) {
        $targetKey = Resolve-McpAliasKey $key
        $canonicalKeys[$targetKey] = $true
        $target = ConvertTo-ClineMcpEntry (ConvertTo-Hashtable $McpEntries[$key])

        if (-not $servers.ContainsKey($targetKey)) {
            $servers[$targetKey] = $target
            continue
        }

        $existingServer = ConvertTo-Hashtable $servers[$targetKey]
        $servers[$targetKey] = $existingServer
        foreach ($field in @('type','command','args','cwd','url','disabled','autoApprove')) {
            if ($target.ContainsKey($field)) { $existingServer[$field] = $target[$field] }
        }
        if ($target.ContainsKey('url')) {
            foreach ($field in @('command','args','cwd','env')) {
                if ($existingServer.ContainsKey($field)) { $existingServer.Remove($field) }
            }
        } else {
            if ($existingServer.ContainsKey('url')) { $existingServer.Remove('url') }
            if ($existingServer.ContainsKey('headers')) { $existingServer.Remove('headers') }
        }

        # Keep existing OAuth/secret-bearing fields unless the registry contains
        # a resolved value. Registry placeholders never overwrite user state.
        foreach ($field in @('headers','env')) {
            if (-not $target.ContainsKey($field)) { continue }
            if (-not $existingServer.ContainsKey($field)) {
                $existingServer[$field] = $target[$field]
            } elseif (-not (Contains-UnresolvedPlaceholder ($target[$field] | ConvertTo-Json -Depth 5 -Compress))) {
                $existingServer[$field] = $target[$field]
            }
        }
    }

    if ($Prune) {
        foreach ($key in @($servers.Keys)) {
            if (-not $canonicalKeys.ContainsKey((Resolve-McpAliasKey $key))) {
                $servers.Remove($key)
            }
        }
    }

    $root.mcpServers = $servers
    $stableNewJson = Get-StableJsonString $root
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path -LiteralPath $path) {
            Get-StableJsonString (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } else { Get-StableJsonString @{} }
        return @{ status = if ($stableExistingJson -eq $stableNewJson) { 'unchanged' } else { 'drift' }; path = $path }
    }

    $destDir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Utf8NoBom -Path $path -Content $stableNewJson
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

function ConvertTo-QoderMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        # Qoder's documented CLI/IDE schema uses http/sse/ws transport values
        # and does not accept the registry's host-neutral auth marker.
        $entry.type = 'http'
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $headers = @{}
            foreach ($header in (ConvertTo-Hashtable $CanonicalEntry.headers).GetEnumerator()) {
                # Qoder expands ${NAME} from the process environment. The
                # host-neutral ${env:NAME} spelling is otherwise sent
                # literally and the remote rejects the request.
                $headers[$header.Key] = [regex]::Replace(
                    [string]$header.Value,
                    '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
                    { param($match) '$' + '{' + $match.Groups[1].Value + '}' }
                )
            }
            $entry.headers = $headers
        }
    } elseif ($CanonicalEntry.type -eq 'stdio') {
        $entry.command = $CanonicalEntry.command
        $entry.args = @($CanonicalEntry.args)
        if ($CanonicalEntry.ContainsKey('env')) { $entry.env = ConvertTo-Hashtable $CanonicalEntry.env }
    }
    return $entry
}

function Sync-HostMcp-Qoder {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )

    $qoderEntries = @{}
    foreach ($key in $McpEntries.Keys) {
        $qoderEntries[$key] = ConvertTo-QoderMcpEntry (ConvertTo-Hashtable $McpEntries[$key])
    }
    $result = Sync-HostMcp-JsonFile -Path $Agent.nativePaths.mcp -McpEntries $qoderEntries -JsonProperty 'mcpServers' -SuppressedKeys $SuppressedKeys -WhatIf:$WhatIf -Prune:$Prune
    if (-not $WhatIf -and (Test-Path -LiteralPath $Agent.nativePaths.mcp -PathType Leaf)) {
        $json = ConvertTo-Hashtable (Get-Content -LiteralPath $Agent.nativePaths.mcp -Raw -Encoding UTF8 | ConvertFrom-Json)
        $changed = $false
        foreach ($key in $qoderEntries.Keys) {
            $targetKey = Resolve-McpAliasKey $key
            if (-not $json.mcpServers.ContainsKey($targetKey)) { continue }
            $server = ConvertTo-Hashtable $json.mcpServers[$targetKey]
            if ($server.ContainsKey('auth')) {
                $server.Remove('auth')
                $changed = $true
            }
            if ($qoderEntries[$key].ContainsKey('headers')) {
                $targetHeaders = ConvertTo-Hashtable $qoderEntries[$key].headers
                $currentHeaders = if ($server.ContainsKey('headers')) {
                    ConvertTo-Hashtable $server.headers
                } else { @{} }
                if ((Get-StableJsonString $currentHeaders) -ne (Get-StableJsonString $targetHeaders)) {
                    $server.headers = $targetHeaders
                    $changed = $true
                }
            }
            $json.mcpServers[$targetKey] = $server
        }
        if ($changed) {
            Write-Utf8NoBom -Path $Agent.nativePaths.mcp -Content (Get-StableJsonString $json)
            $script:state.managedFiles[$Agent.nativePaths.mcp] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $Agent.nativePaths.mcp) }
            $result.status = 'updated'
        }
    }
    return $result
}

function ConvertTo-OpenCodeMcpEntry {
    param([hashtable]$CanonicalEntry)

    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.type = 'remote'
        $entry.url = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $headers = @{}
            foreach ($header in (ConvertTo-Hashtable $CanonicalEntry.headers).GetEnumerator()) {
                # OpenCode expands {env:NAME}, not the shared ${env:NAME}
                # notation. Keep the secret in the process environment.
                $headers[$header.Key] = [regex]::Replace(
                    [string]$header.Value,
                    '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}',
                    { param($match) '{env:' + $match.Groups[1].Value + '}' }
                )
            }
            $entry.headers = $headers
            if ($headers.ContainsKey('Authorization')) { $entry.oauth = $false }
        }
    } else {
        $entry.type = 'local'
        $cmd = @()
        if ($CanonicalEntry.command) { $cmd += $CanonicalEntry.command }
        if ($CanonicalEntry.args) { $cmd += @($CanonicalEntry.args) }
        $entry.command = $cmd
        if ($CanonicalEntry.ContainsKey('env')) { $entry.environment = ConvertTo-Hashtable $CanonicalEntry.env }
    }
    return $entry
}

function Sync-HostMcp-OpenCode {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune
    )

    $basePath = $Agent.nativePaths.config
    if (-not $basePath) { return @{ status='unsupported-path'; note='OpenCode config path missing' } }

    $path = if ($basePath -like '*.json') { $basePath } else { Join-Path $basePath 'opencode.json' }
    if (-not (Test-Path -LiteralPath $path)) { return @{ status='config-missing'; path=$path } }

    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $root = ConvertTo-Hashtable $json
    if (-not $root.ContainsKey('mcp')) { $root.mcp = @{} }

    # Normalize known aliases before merge.
    foreach ($k in @($root.mcp.Keys)) {
        $resolved = Resolve-McpAliasKey $k
        if ($resolved -eq $k) { continue }
        if ($root.mcp.ContainsKey($resolved)) {
            $root.mcp.Remove($k)
            continue
        }
        $root.mcp[$resolved] = $root.mcp[$k]
        $root.mcp.Remove($k)
    }
    $root.mcp = Remove-McpTargetKeys -Target $root.mcp -Keys $SuppressedKeys

    foreach ($key in $McpEntries.Keys) {
        $canonical = $McpEntries[$key]
        $target = ConvertTo-OpenCodeMcpEntry $canonical

        if (-not $root.mcp.ContainsKey($key)) {
            $root.mcp[$key] = $target
            if (-not $root.mcp[$key].ContainsKey('enabled')) { $root.mcp[$key].enabled = $true }
            continue
        }

        $existing = $root.mcp[$key]
        if (-not ($existing -is [hashtable])) { $existing = ConvertTo-Hashtable $existing; $root.mcp[$key] = $existing }

        if ($target.type -eq 'local') {
            foreach ($staleField in @('url','headers','args','env','oauth')) {
                if ($existing.ContainsKey($staleField)) { $existing.Remove($staleField) }
            }
        } elseif ($target.type -eq 'remote') {
            foreach ($staleField in @('command','args','env','environment')) {
                if ($existing.ContainsKey($staleField)) { $existing.Remove($staleField) }
            }
        }

        foreach ($field in @('type','url','command','oauth')) {
            if ($target.ContainsKey($field)) {
                $candidate = $target[$field]
                if ($field -eq 'url' -and $existing.ContainsKey('url') -and (Contains-UnresolvedPlaceholder $candidate)) { continue }
                $existing[$field] = $candidate
            }
        }

        if ($target.ContainsKey('headers')) {
            if (-not $existing.ContainsKey('headers')) { $existing.headers = $target.headers }
        }
        if ($target.ContainsKey('environment')) {
            if (-not $existing.ContainsKey('environment')) { $existing.environment = $target.environment }
        }
        if (-not $existing.ContainsKey('enabled')) { $existing.enabled = $true }
    }

    if ($Prune) {
        $keep = @{}
        foreach ($k in $McpEntries.Keys) { $keep[(Resolve-McpAliasKey $k)] = $true }
        foreach ($k in @($root.mcp.Keys)) {
            if (-not $keep.ContainsKey((Resolve-McpAliasKey $k))) {
                $root.mcp.Remove($k)
            }
        }
    }

    $stableNewJson = Get-StableJsonString $root
    if ($WhatIf) {
        $stableExistingJson = Get-StableJsonString (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        $status = if ($stableExistingJson -ne $stableNewJson) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$path }
    }

    Write-Utf8NoBom -Path $path -Content $stableNewJson
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

# ---------------------------------------------------------------------------
# Windsurf / Devin desktop adapter
#
# Windsurf (Cognition's Devin desktop app) reads ~/.codeium/windsurf/mcp_config.json
# with a STRICT schema that differs from the Cursor/VSCode generic writer:
#   - remote servers use `serverUrl` (NOT `url`); `type` and `disabled` are invalid keys
#   - placeholders must be `${env:VAR}` (Windsurf does not expand bare `${VAR}`)
# Emitting the generic schema makes Cascade throw
# "Invalid argument: an internal error occurred" on every request. This adapter
# translates canonical entries into Windsurf's schema. `ProtectKeys` may name
# host-owned servers to preserve under prune; it is empty by default (the `devin`
# MCP server is intentionally NOT protected — it is removed from all agents).
# ---------------------------------------------------------------------------
function Convert-ToWindsurfPlaceholders {
    param([object]$Value)
    if ($null -eq $Value) { return $Value }
    if ($Value -is [string]) {
        # ${VAR} -> ${env:VAR}, but leave ${env:...} and ${file:...} untouched.
        return [regex]::Replace($Value, '\$\{(?!env:|file:)([A-Za-z_][A-Za-z0-9_]*)\}', '${env:$1}')
    }
    if ($Value -is [hashtable]) {
        $out = @{}
        foreach ($k in $Value.Keys) { $out[$k] = Convert-ToWindsurfPlaceholders $Value[$k] }
        return $out
    }
    return $Value
}

function ConvertTo-WindsurfMcpEntry {
    param([hashtable]$CanonicalEntry)
    $entry = @{}
    if ($CanonicalEntry.type -eq 'http') {
        $entry.serverUrl = $CanonicalEntry.url
        if ($CanonicalEntry.ContainsKey('headers')) {
            $entry.headers = Convert-ToWindsurfPlaceholders (ConvertTo-Hashtable $CanonicalEntry.headers)
        }
    } else {
        if ($CanonicalEntry.command) { $entry.command = $CanonicalEntry.command }
        if ($CanonicalEntry.args)    { $entry.args = @($CanonicalEntry.args) }
        if ($CanonicalEntry.ContainsKey('env')) {
            $entry.env = Convert-ToWindsurfPlaceholders (ConvertTo-Hashtable $CanonicalEntry.env)
        }
    }
    return $entry
}

function Sync-HostMcp-Windsurf {
    param(
        [pscustomobject]$Agent,
        [hashtable]$McpEntries,
        [string[]]$SuppressedKeys = @(),
        [switch]$WhatIf,
        [switch]$Prune,
        [string[]]$ProtectKeys = @()
    )
    $path = $Agent.nativePaths.mcp
    if (-not $path) { return @{ status='unsupported-path'; note='Windsurf mcp path missing' } }

    $root = @{ mcpServers = @{} }
    if (Test-Path -LiteralPath $path) {
        $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $root = ConvertTo-Hashtable $existing
        if (-not $root.ContainsKey('mcpServers')) { $root.mcpServers = @{} }
    }
    $servers = Normalize-McpTargetKeys -Target $root.mcpServers
    $servers = Remove-McpTargetKeys -Target $servers -Keys $SuppressedKeys

    # Normalize any existing entries into valid Windsurf schema.
    foreach ($k in @($servers.Keys)) {
        $e = $servers[$k]
        if (-not ($e -is [hashtable])) { $e = ConvertTo-Hashtable $e; $servers[$k] = $e }
        if ($e.ContainsKey('disabled')) {
            $wasDisabled = [bool]$e['disabled']
            $e.Remove('disabled')
            if ($wasDisabled) { $servers.Remove($k); continue }   # omit = disabled in Windsurf
        }
        if ($e.ContainsKey('type')) { $e.Remove('type') }
        if ($e.ContainsKey('url')) {
            if (-not $e.ContainsKey('serverUrl')) { $e['serverUrl'] = $e['url'] }
            $e.Remove('url')
        }
        if ($e.ContainsKey('headers')) { $e['headers'] = Convert-ToWindsurfPlaceholders $e['headers'] }
        if ($e.ContainsKey('env'))     { $e['env']     = Convert-ToWindsurfPlaceholders $e['env'] }
    }

    # Windsurf previously carried a host-prefixed Context7 alias alongside the
    # canonical entry. Remove it only when the canonical entry is present;
    # otherwise preserve the user-owned server instead of guessing ownership.
    if ($servers.ContainsKey('devin/context7') -and $servers.ContainsKey('context7')) {
        $servers.Remove('devin/context7')
    }

    # Merge canonical registry entries in Windsurf schema.
    $canonKeys = @{}
    foreach ($key in $McpEntries.Keys) {
        $targetKey = Resolve-McpAliasKey $key
        $canonKeys[$targetKey] = $true
        $target = ConvertTo-WindsurfMcpEntry $McpEntries[$key]

        if (-not $servers.ContainsKey($targetKey)) { $servers[$targetKey] = $target; continue }

        $existingE = $servers[$targetKey]
        if (-not ($existingE -is [hashtable])) { $existingE = ConvertTo-Hashtable $existingE; $servers[$targetKey] = $existingE }

        foreach ($field in @('serverUrl','command','args')) {
            if ($target.ContainsKey($field)) { $existingE[$field] = $target[$field] }
        }
        # Clean up fields from the other transport.
        if ($target.ContainsKey('serverUrl')) {
            foreach ($lf in @('command','args','env')) { if ($existingE.ContainsKey($lf)) { $existingE.Remove($lf) } }
        } elseif ($target.ContainsKey('command')) {
            if ($existingE.ContainsKey('serverUrl')) { $existingE.Remove('serverUrl') }
        }
        # Preserve existing secret-bearing headers/env unless canonical supplies resolved values.
        foreach ($field in @('headers','env')) {
            if ($target.ContainsKey($field)) {
                if (-not $existingE.ContainsKey($field)) { $existingE[$field] = $target[$field] }
                elseif (-not (Contains-UnresolvedPlaceholder ($target[$field] | ConvertTo-Json -Depth 5 -Compress))) { $existingE[$field] = $target[$field] }
            }
        }
    }

    if ($Prune) {
        foreach ($k in @($servers.Keys)) {
            $rk = Resolve-McpAliasKey $k
            if ($ProtectKeys -contains $k) { continue }          # never drop host-owned servers (devin)
            if (-not $canonKeys.ContainsKey($rk)) { $servers.Remove($k) }
        }
    }

    $root.mcpServers = $servers
    $stableNewJson = Get-StableJsonString $root
    if ($WhatIf) {
        $stableExistingJson = if (Test-Path $path) {
            Get-StableJsonString (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } else { Get-StableJsonString @{} }
        $status = if ($stableExistingJson -ne $stableNewJson) { 'drift' } else { 'unchanged' }
        return @{ status=$status; path=$path }
    }
    $destDir = Split-Path $path -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Write-Utf8NoBom -Path $path -Content $stableNewJson
    $script:state.managedFiles[$path] = @{ capability='mcp-registry'; hash=(Get-FileHash256 $path) }
    return @{ status='updated'; path=$path }
}

# ---------------------------------------------------------------------------
# Main sync loop
# ---------------------------------------------------------------------------
$whatIfMode = $Audit -or (-not $Apply -and -not $Validate)

$onDemandLocalMcpKeys = @($mcpsReg.mcpServers | Where-Object {
    [string]$_.activationMode -eq 'on-demand-local'
} | ForEach-Object {
    Resolve-McpAliasKey ([string]$_.id)
} | Sort-Object -Unique)

# Fleet synchronization omits on-demand local launchers. A registry entry with
# the distinct host-configured-local lifecycle is an explicit fleet exception
# requested by the owner and is emitted through each reviewed native adapter.
$candidateServers = @(Get-McpCandidatesForScope `
    -Servers $mcpsReg.mcpServers `
    -Scope $ScopeProfile `
    -AllowDeprecated:$IncludeDeprecated | Where-Object {
        [string]$_.activationMode -ne 'on-demand-local'
    })

$allMcpEntries = @{}
$mcpHostAllowlist = @{}
$mcpHostConfigOverrides = @{}
foreach ($mcp in $candidateServers) {
    $allMcpEntries[$mcp.id] = Get-CanonicalMcpEntry $mcp
    if ($mcp.PSObject.Properties.Match('hosts').Count -gt 0 -and $mcp.hosts) { $mcpHostAllowlist[$mcp.id] = @($mcp.hosts) }
    $overridesProperty = $mcp.PSObject.Properties['hostConfigOverrides']
    if ($overridesProperty -and $overridesProperty.Value) {
        foreach ($hostOverride in $overridesProperty.Value.PSObject.Properties) {
            $hostId = [string]$hostOverride.Name
            if (-not $mcpHostConfigOverrides.ContainsKey($hostId)) {
                $mcpHostConfigOverrides[$hostId] = @{}
            }
            $mcpHostConfigOverrides[$hostId][(Resolve-McpAliasKey ([string]$mcp.id))] =
                ConvertTo-Hashtable $hostOverride.Value
        }
    }
}

$pluginProvidedByHost = Get-PluginProvidedMcpKeysByHost -CapabilitiesRegistry $capReg -McpRegistry $mcpsReg -ConnectorRegistry $connectorReg

$agentsToSync = @($agentsReg.activeAgents)
if ($IncludeInactiveAgents) { $agentsToSync += @($agentsReg.inactiveAgents) }

foreach ($agent in $agentsToSync) {
    $hostDrift = @{ host=$agent.id; mcp=@(); files=@(); status='ok' }
    $gatewayPlan = Get-GatewayPlanForHost -HostId $agent.id -GatewayRegistry $gatewayReg -ConnectorRegistry $connectorReg
    $hostMcpEntries = Get-HostMcpEntries -HostId $agent.id -BaseEntries $allMcpEntries -HostAllowlist $mcpHostAllowlist -HostConfigOverrides $mcpHostConfigOverrides -PluginProvidedByHost $pluginProvidedByHost -GatewayPlan $gatewayPlan
    $pluginOwnedKeys = if ($pluginProvidedByHost.ContainsKey($agent.id)) { @($pluginProvidedByHost[$agent.id].Keys) } else { @() }
    # Remove stale local registrations narrowly even without -Prune so an
    # older sync or a broad scope cannot recreate process-fanout entries.
    $suppressedKeys = @($pluginOwnedKeys) + @($onDemandLocalMcpKeys)
    if ($gatewayPlan) { $suppressedKeys += @($gatewayPlan.managedKeys) }
    $suppressedKeys = @($suppressedKeys | Sort-Object -Unique)

    switch ($agent.id) {
        'claude' {
            $r = Sync-HostMcp-Claude -Agent $agent -McpEntries $hostMcpEntries -PluginOwnedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'codex' {
            $r = Sync-HostMcp-Codex -Agent $agent -McpEntries $hostMcpEntries -PluginOwnedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'grok' {
            $r = Sync-HostMcp-Grok -Agent $agent -Mcps $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'hermes' {
            $r = Sync-HostMcp-Hermes -Agent $agent -Mcps $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode
            $hostDrift.mcp += $r
        }
        'warp' {
            $r = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-WarpMcpEntry} -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'cursor' {
            $r = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-CursorMcpEntry} -SuppressedKeys $suppressedKeys -ReplaceExistingEntries -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'vscode-insiders' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'servers' -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'factory' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'qwen-code' {
            $r = Sync-HostMcp-Qwen -Agent $agent -McpEntries $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
            $hostDrift.files += Sync-QwenCapabilityExtensions -Agent $agent -CapabilitiesRegistry $capReg -WhatIf:$whatIfMode -Prune:$Prune
        }
        'devin' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.config -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'amp' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.settings -McpEntries $hostMcpEntries -JsonProperty 'amp.mcpServers' -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'windsurf' {
            $r = Sync-HostMcp-Windsurf -Agent $agent -McpEntries $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'opencode' {
            $r = Sync-HostMcp-OpenCode -Agent $agent -McpEntries $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'gemini' {
            $r = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.settings -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-GeminiMcpEntry} -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'antigravity' {
            $r = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-AntigravityMcpEntry} -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
            if ($agent.nativePaths.legacyMcp -and $agent.nativePaths.legacyMcp -ne $agent.nativePaths.mcp) {
                $legacy = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.legacyMcp -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-AntigravityMcpEntry} -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
                $hostDrift.mcp += $legacy
            }
        }
        'copilot' {
            $r = Sync-HostMcp-ConvertedJsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -Converter ${function:ConvertTo-CopilotMcpEntry} -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'cline' {
            $r = Sync-HostMcp-Cline -Agent $agent -McpEntries $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'qoder' {
            $r = Sync-HostMcp-Qoder -Agent $agent -McpEntries $hostMcpEntries -SuppressedKeys $suppressedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
    }


    $driftReport.hosts += $hostDrift
}

# ---------------------------------------------------------------------------
# Validation pass
# ---------------------------------------------------------------------------
if ($Validate -or $Apply -or $Audit) {
    $configFiles = @(
        $UserProfile + '\.claude.json',
        $UserProfile + '\.cursor\mcp.json',
        $UserProfile + '\AppData\Roaming\Code - Insiders\User\mcp.json',
        $UserProfile + '\.factory\mcp.json',
        $UserProfile + '\.qwen\settings.json',
        $UserProfile + '\AppData\Roaming\devin\config.json',
        $UserProfile + '\.config\amp\settings.json',
        $UserProfile + '\.config\opencode\opencode.json',
        $UserProfile + '\.gemini\settings.json',
        $UserProfile + '\.gemini\antigravity\mcp_config.json',
        $UserProfile + '\.gemini\config\mcp_config.json',
        $UserProfile + '\.copilot\mcp-config.json',
        $UserProfile + '\.codeium\windsurf\mcp_config.json',
        $UserProfile + '\.warp\.mcp.json',
        $UserProfile + '\.cline\data\settings\cline_mcp_settings.json',
        $UserProfile + '\.qoder\settings.json'
    )
    foreach ($f in $configFiles) {
        if (Test-Path -LiteralPath $f) { Test-JsonParse -Path $f }
    }

    $tomlFiles = @($UserProfile + '\.codex\config.toml', $UserProfile + '\.grok\config.toml')
    foreach ($f in $tomlFiles) {
        if (Test-Path -LiteralPath $f) { Test-TomlParse -Path $f }
    }
}

# ---------------------------------------------------------------------------
# Save state and report
# ---------------------------------------------------------------------------
if ($Apply) { Save-State }

$driftReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $DriftPath -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "=== Sync complete ==="
Write-Host "Mode: $(if($Audit){'Audit'}elseif($Apply){'Apply'}elseif($Validate){'Validate'}else{'Audit(default)'})"
Write-Host "Drift report: $DriftPath"
if ($validationErrors.Count -gt 0) {
    Write-Host "Validation errors: $($validationErrors.Count)" -ForegroundColor Red
    $validationErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
    Write-Host "Validation: OK" -ForegroundColor Green
}

$driftReport.hosts | ForEach-Object {
    $mcpStatus = ($_.mcp | ForEach-Object { $_.status }) -join ', '
    Write-Host "[$($_.host)] mcp=$mcpStatus"
}

if ($validationErrors.Count -gt 0) { exit 1 }
