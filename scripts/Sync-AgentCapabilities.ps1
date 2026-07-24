#Requires -Version 5.1
<#
.SYNOPSIS
    Central synchronization engine for the C:\Repos\agent-capabilities registry.

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
    [string]$RegistryRoot = "C:\Repos\agent-capabilities",
    [string]$UserProfile = "C:\Users\SaroshHussain"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$RegistryDir       = Join-Path $RegistryRoot 'registry'
$RuntimeDir        = Join-Path $env:LOCALAPPDATA 'AgentCapabilities'
$StateDir          = Join-Path $RuntimeDir 'sync'
$DriftDir          = Join-Path $StateDir 'drift-reports'
$StateFile         = Join-Path $StateDir 'sync-state.json'

$AgentsFile        = Join-Path $RegistryDir 'agents.json'
$McpsFile          = Join-Path $RegistryDir 'mcps.json'
$CapabilitiesFile  = Join-Path $RegistryDir 'capabilities.json'

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
New-Item -ItemType Directory -Path $DriftDir -Force | Out-Null

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

if (-not $agentsReg) { throw "Missing $AgentsFile" }
if (-not $mcpsReg)   { throw "Missing $McpsFile" }

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

function Save-State {
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

    $destDir = Split-Path $DestPath -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $sourceHash = Get-FileHash256 $SourcePath
    $destHash   = Get-FileHash256 $DestPath

    if ($sourceHash -eq $destHash) {
        $script:state.managedFiles[$DestPath] = @{ capability=$OwnerCapability; hash=$sourceHash }
        return @{ status = 'unchanged'; hash = $sourceHash }
    }

    if ($WhatIf) {
        return @{ status = 'drift'; sourceHash=$sourceHash; destHash=$destHash }
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestPath -Force
    $script:state.managedFiles[$DestPath] = @{ capability=$OwnerCapability; hash=$sourceHash }
    return @{ status = 'updated'; hash = $sourceHash }
}

function Sync-ShwikiContextSkill {
    param(
        [pscustomobject]$Agent,
        [object]$CapabilitiesRegistry,
        [switch]$WhatIf
    )

    if ($Agent.id -eq 'qwen-code') {
        return @{ status='extension-managed'; capability='shwiki-context' }
    }
    if (-not $CapabilitiesRegistry -or -not $CapabilitiesRegistry.capabilities) {
        return @{ status='registry-missing'; capability='shwiki-context' }
    }

    $capability = $CapabilitiesRegistry.capabilities | Where-Object id -eq 'shwiki-context' | Select-Object -First 1
    if (-not $capability) { return @{ status='capability-missing'; capability='shwiki-context' } }
    $mapping = $capability.hostMappings | Where-Object hostId -eq $Agent.id | Select-Object -First 1
    if (-not $mapping -or $mapping.deploymentStatus -ne 'managed') {
        return @{ status='not-mapped'; capability='shwiki-context' }
    }
    if (-not $Agent.nativePaths -or $Agent.nativePaths.PSObject.Properties.Match('skillsDir').Count -eq 0) {
        return @{ status='skills-path-unavailable'; capability='shwiki-context' }
    }

    $source = Join-Path ([string]$capability.canonicalSource) 'skills\shwiki-context\SKILL.md'
    $destination = Join-Path ([string]$Agent.nativePaths.skillsDir) 'shwiki-context\SKILL.md'
    $result = Deploy-File -SourcePath $source -DestPath $destination -OwnerCapability 'shwiki-context' -WhatIf:$WhatIf
    $result.capability = 'shwiki-context'
    $result.path = $destination
    return $result
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
    return $Value -match '\$\{env:[^}]+\}|\$\{[A-Z_][A-Z0-9_]*\}'
}

function Resolve-McpAliasKey {
    param([string]$Key)
    switch ($Key) {
        'shwiki' { return 'shwiki-context' }
        'shwiki-context-remote' { return 'shwiki-context' }
        'sh-knowledge' { return 'shwiki-context' }
        default { return $Key }
    }
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
        [object]$McpRegistry
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

    if (-not $CapabilitiesRegistry -or -not $CapabilitiesRegistry.capabilities) { return $result }

    foreach ($cap in $CapabilitiesRegistry.capabilities) {
        if (-not $cap.hostMappings) { continue }

        $sourceRoot = [string]$cap.canonicalSource
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
            if ([string]$mapping.deploymentStatus -ne 'plugin-owned') { continue }
            $hostId = [string]$mapping.hostId
            if (-not $hostId) { continue }
            if (-not $result.ContainsKey($hostId)) { $result[$hostId] = @{} }
            foreach ($k in $serverKeys) {
                $result[$hostId][$k] = $true
            }
        }
    }

    return $result
}

function Get-HostMcpEntries {
    param(
        [string]$HostId,
        [hashtable]$BaseEntries,
        [hashtable]$HostAllowlist,
        [hashtable]$PluginProvidedByHost
    )

    $filtered = @{}
    foreach ($key in $BaseEntries.Keys) {
        $resolved = Resolve-McpAliasKey $key
        if ($HostAllowlist.ContainsKey($resolved) -and $HostId -notin $HostAllowlist[$resolved]) { continue }
        if ($PluginProvidedByHost.ContainsKey($HostId) -and $PluginProvidedByHost[$HostId].ContainsKey($resolved)) { continue }
        $filtered[$key] = $BaseEntries[$key]
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

    # A plugin-owned MCP must be removed even when broad pruning is disabled.
    # This is a narrow ownership cleanup, not permission to delete unrelated
    # user registrations.
    foreach ($key in $PluginOwnedKeys) {
        if ($json.mcpServers.ContainsKey($key)) { $json.mcpServers.Remove($key) }
    }

    $claudeEntries = @{}
    foreach ($key in $McpEntries.Keys) {
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

    # Remove only entries with an explicit native-plugin owner. Keep all other
    # unregistered TOML sections intact unless the caller requests broad prune.
    foreach ($key in $PluginOwnedKeys) {
        $newToml = [regex]::Replace($newToml, (Get-CodexMcpSectionPattern $key), '')
    }

    foreach ($key in $McpEntries.Keys) {
        $entry = $McpEntries[$key]
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
            if ($entry.env) {
                $sectionLines += "[mcp_servers.$key.env]"
                foreach ($e in $entry.env.GetEnumerator()) {
                    $sectionLines += "$($e.Key) = `"$($e.Value)`""
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

        # Fold known aliases into canonical names when present.
        if ($newToml -match '(?m)^\[mcp_servers\.shwiki-context-remote\]') {
            if ($newToml -match '(?m)^\[mcp_servers\.shwiki-context\]') {
                $newToml = [regex]::Replace(
                    $newToml,
                    (Get-CodexMcpSectionPattern 'shwiki-context-remote'),
                    ''
                )
            } else {
                $newToml = $newToml -replace '(?m)^\[mcp_servers\.shwiki-context-remote\]$', '[mcp_servers.shwiki-context]'
            }
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
        [switch]$WhatIf,
        [switch]$Prune
    )

    # Grok CLI uses TOML sections compatible with Codex's mcp_servers shape,
    # but environment interpolation is ${NAME}, not ${env:NAME}.
    $path = $Agent.nativePaths.config
    $existing = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { '' }
    $original = $existing
    $blocks = [System.Collections.Generic.List[string]]::new()

    foreach ($name in @($Mcps.Keys | Sort-Object)) {
        $mcp = $Mcps[$name]
        $sectionPattern = Get-CodexMcpSectionPattern -Key $name
        $existing = [regex]::Replace($existing, $sectionPattern, '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($alias in @('shwiki', 'shwiki-context-remote', 'sh-knowledge')) {
            if ((Resolve-McpAliasKey $alias) -eq $name) {
                $existing = [regex]::Replace($existing, (Get-CodexMcpSectionPattern -Key $alias), '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            }
        }
        $lines = [System.Collections.Generic.List[string]]::new()
        $null = $lines.Add("[mcp_servers.$name]")
        if ($mcp.type -eq 'http') {
            $url = ConvertTo-HostEnvironmentReference -Value $mcp.url -TargetHost 'grok'
            $null = $lines.Add("url = `"$url`"")
            if ($mcp.headers) {
                $pairs = @($mcp.headers.GetEnumerator() | ForEach-Object {
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
                foreach ($property in $mcp.env.GetEnumerator()) {
                    $value = ConvertTo-HostEnvironmentReference -Value ([string]$property.Value) -TargetHost 'grok'
                    $null = $lines.Add("[mcp_servers.$name.env]")
                    $null = $lines.Add("$($property.Key) = `"$value`"")
                }
            }
        }
        $null = $blocks.Add(($lines -join "`n"))
    }

    if ($Prune) {
        foreach ($name in @('context7', 'firecrawl', 'tavily', 'exa', 'linear', 'notion', 'shwiki-context', 'brave-search', 'playwright')) {
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
        [switch]$WhatIf
    )

    # Hermes has a root-level YAML mcp_servers mapping. Replace fleet-managed
    # entries while preserving unregistered user MCP entries and all other YAML.
    $path = $Agent.nativePaths.config
    $existing = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { '' }
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
                foreach ($property in $mcp.headers.GetEnumerator()) {
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
                foreach ($property in $mcp.env.GetEnumerator()) {
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
    param([pscustomobject]$Agent, [hashtable]$McpEntries, [switch]$WhatIf, [switch]$Prune)
    $path = $Agent.nativePaths.settings
    $json = @{}
    if (Test-Path -LiteralPath $path) {
        $json = ConvertTo-Hashtable (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    if (-not $json.ContainsKey('mcpServers')) { $json.mcpServers = @{} }
    elseif (-not ($json.mcpServers -is [hashtable])) { $json.mcpServers = ConvertTo-Hashtable $json.mcpServers }

    $canonicalKeys = @{}
    foreach ($key in $McpEntries.Keys) {
        $resolved = Resolve-McpAliasKey $key
        $canonicalKeys[$resolved] = $true
        $canonical = $McpEntries[$key]
        if (-not ($canonical -is [hashtable])) { $canonical = ConvertTo-Hashtable $canonical }
        $json.mcpServers[$resolved] = ConvertTo-QwenMcpEntry $canonical
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

    $adapterRoot = Join-Path $PSScriptRoot '..\adapters\qwen-code\extensions'
    $expected = @()
    foreach ($capability in @($CapabilitiesRegistry.capabilities)) {
        $mapping = @($capability.hostMappings | Where-Object {
            $_.hostId -eq 'qwen-code' -and $_.deploymentStatus -in @('managed','native-extension-junction')
        })
        if ($mapping.Count -eq 0) { continue }

        $sourceSkills = Join-Path ([string]$capability.canonicalSource) 'skills'
        if (-not (Test-Path -LiteralPath $sourceSkills)) { continue }
        $extensionName = 'agent-capabilities-' + [string]$capability.id
        $expected += $extensionName
        $adapterPath = Join-Path $adapterRoot $extensionName
        $manifestPath = Join-Path $adapterPath 'qwen-extension.json'
        $skillsLink = Join-Path $adapterPath 'skills'
        $userLink = Join-Path $extensionsRoot $extensionName
        $manifest = @{ name=$extensionName; version='1.0.0'; description="Registry adapter for $($capability.id)"; skills='skills' }
        $manifestJson = Get-StableJsonString $manifest

        $adapterReady = (Test-Path -LiteralPath $manifestPath) -and ((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8) -eq $manifestJson) -and (Test-Path -LiteralPath $skillsLink)
        $userReady = Test-Path -LiteralPath $userLink
        if ($WhatIf) {
            if (-not ($adapterReady -and $userReady)) { return @{ status='drift'; path=$extensionsRoot } }
            continue
        }

        if (-not (Test-Path -LiteralPath $adapterPath)) { New-Item -ItemType Directory -Path $adapterPath -Force | Out-Null }
        $manifestJson | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -NoNewline
        if (-not (Test-Path -LiteralPath $skillsLink)) {
            New-Item -ItemType Junction -Path $skillsLink -Target $sourceSkills | Out-Null
        }
        if (-not (Test-Path -LiteralPath $extensionsRoot)) { New-Item -ItemType Directory -Path $extensionsRoot -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $userLink)) {
            New-Item -ItemType Junction -Path $userLink -Target $adapterPath | Out-Null
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
    param([pscustomobject]$Agent, [hashtable]$McpEntries, [switch]$WhatIf, [switch]$Prune)

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
            foreach ($staleField in @('url','headers')) {
                if ($existing.ContainsKey($staleField)) { $existing.Remove($staleField) }
            }
        } elseif ($target.type -eq 'remote') {
            foreach ($staleField in @('command','environment')) {
                if ($existing.ContainsKey($staleField)) { $existing.Remove($staleField) }
            }
        }

        foreach ($field in @('type','url','command')) {
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
    $servers = $root.mcpServers

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

$candidateServers = Get-McpCandidatesForScope -Servers $mcpsReg.mcpServers -Scope $ScopeProfile -AllowDeprecated:$IncludeDeprecated

$allMcpEntries = @{}
$mcpHostAllowlist = @{}
foreach ($mcp in $candidateServers) {
    $allMcpEntries[$mcp.id] = Get-CanonicalMcpEntry $mcp
    if ($mcp.PSObject.Properties.Match('hosts').Count -gt 0 -and $mcp.hosts) { $mcpHostAllowlist[$mcp.id] = @($mcp.hosts) }
}

$pluginProvidedByHost = Get-PluginProvidedMcpKeysByHost -CapabilitiesRegistry $capReg -McpRegistry $mcpsReg

$agentsToSync = @($agentsReg.activeAgents)
if ($IncludeInactiveAgents) { $agentsToSync += @($agentsReg.inactiveAgents) }

foreach ($agent in $agentsToSync) {
    $hostDrift = @{ host=$agent.id; mcp=@(); files=@(); status='ok' }
    $hostMcpEntries = Get-HostMcpEntries -HostId $agent.id -BaseEntries $allMcpEntries -HostAllowlist $mcpHostAllowlist -PluginProvidedByHost $pluginProvidedByHost
    $pluginOwnedKeys = if ($pluginProvidedByHost.ContainsKey($agent.id)) { @($pluginProvidedByHost[$agent.id].Keys) } else { @() }

    switch ($agent.id) {
        'claude' {
            $r = Sync-HostMcp-Claude -Agent $agent -McpEntries $hostMcpEntries -PluginOwnedKeys $pluginOwnedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'codex' {
            $r = Sync-HostMcp-Codex -Agent $agent -McpEntries $hostMcpEntries -PluginOwnedKeys $pluginOwnedKeys -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'grok' {
            $r = Sync-HostMcp-Grok -Agent $agent -Mcps $hostMcpEntries -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'hermes' {
            $r = Sync-HostMcp-Hermes -Agent $agent -Mcps $hostMcpEntries -WhatIf:$whatIfMode
            $hostDrift.mcp += $r
        }
        'warp' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'cursor' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'vscode-insiders' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'servers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'factory' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'qwen-code' {
            $r = Sync-HostMcp-Qwen -Agent $agent -McpEntries $hostMcpEntries -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
            $hostDrift.files += Sync-QwenCapabilityExtensions -Agent $agent -CapabilitiesRegistry $capReg -WhatIf:$whatIfMode -Prune:$Prune
        }
        'devin' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.config -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'amp' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.settings -McpEntries $hostMcpEntries -JsonProperty 'amp.mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'windsurf' {
            $r = Sync-HostMcp-Windsurf -Agent $agent -McpEntries $hostMcpEntries -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'opencode' {
            $r = Sync-HostMcp-OpenCode -Agent $agent -McpEntries $hostMcpEntries -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'gemini' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.settings -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
        'copilot' {
            $r = Sync-HostMcp-JsonFile -Path $agent.nativePaths.mcp -McpEntries $hostMcpEntries -JsonProperty 'mcpServers' -WhatIf:$whatIfMode -Prune:$Prune
            $hostDrift.mcp += $r
        }
    }

    $hostDrift.files += Sync-ShwikiContextSkill -Agent $agent -CapabilitiesRegistry $capReg -WhatIf:$whatIfMode

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
        $UserProfile + '\.copilot\mcp-config.json',
        $UserProfile + '\.codeium\windsurf\mcp_config.json'
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

$driftPath = Join-Path $DriftDir ("drift-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$driftReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $driftPath -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "=== Sync complete ==="
Write-Host "Mode: $(if($Audit){'Audit'}elseif($Apply){'Apply'}elseif($Validate){'Validate'}else{'Audit(default)'})"
Write-Host "Drift report: $driftPath"
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
