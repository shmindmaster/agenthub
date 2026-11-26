#Requires -Version 5.1
<#
Structural conformance with the Agent Plugins 1.0.0 specification
(https://agent-plugins.org/specification), owner direction 2026-11-25.

Three rules, each written because the fleet had drifted away from it:

1. Nothing standalone. A skill exists only inside a plugin's skills/ directory,
   and an MCP server exists only when a plugin package carries it. There is no
   second delivery path -- no skill tree outside packages/, no registry row that
   no package ships.
2. plugin.json is a closed schema. Only $schema, name, version, description,
   author, homepage, repository, license, keywords and extensions are allowed;
   the spec says a client MUST reject a plugin on any other violation and MUST
   report and ignore unknown fields. The portable manifest in every package is
   checked here. Host projections (.claude-plugin, .codex-plugin, ...) are each
   host's own format and are not this file's business.
3. mcp.json is a closed schema located at the plugin root. Its only top-level
   fields are $schema and mcpServers, and every entry matches exactly one of
   stdio / streamable-http / sse with that variant's fields.

The schemas are the authority and are referenced by URL in the files themselves;
this file encodes only what the schemas state, and says so where it is stricter.

Run: pwsh -NoProfile -File tests/Test-PluginSpecConformance.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

$pluginSchema = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
$mcpSchema = 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json'
# plugin.schema.json -> "additionalProperties": false, required $schema + name.
$manifestFields = @('$schema', 'name', 'version', 'description', 'author', 'homepage', 'repository', 'license', 'keywords', 'extensions')
$serverTypes = @('stdio', 'streamable-http', 'sse')

. (Join-Path $repoRoot 'scripts/lib/CapabilityGraph.ps1')

$packagesRoot = Join-Path $repoRoot 'packages'
$overlayRoot = Get-AgentHubOverlayRoot -RepositoryRoot $repoRoot
$overlayPackagesRoot = if ($overlayRoot) { Join-Path $overlayRoot 'packages' } else { $null }

function Get-PackageDirs {
    $dirs = @(Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue)
    if ($overlayPackagesRoot -and (Test-Path -LiteralPath $overlayPackagesRoot -PathType Container)) {
        $dirs += @(Get-ChildItem -LiteralPath $overlayPackagesRoot -Directory -ErrorAction SilentlyContinue)
    }
    $dirs
}

# --- 1a. no skill outside a plugin package -----------------------------------
# Skills/ is discovered only inside a plugin. A SKILL.md elsewhere is either a
# second delivery path for the same content or a stray file; both are drift.
$straySkills = @()
foreach ($tree in @($packagesRoot, $repoRoot)) {
    $straySkills += @(Get-ChildItem -LiteralPath (Join-Path $tree 'skills') -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue)
}
$straySkills = @($straySkills | Where-Object { $_.FullName -notlike "$packagesRoot*" -and $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)packages$([IO.Path]::DirectorySeparatorChar)*" })
Report 'no skill tree exists outside a plugin package' ($straySkills.Count -eq 0) `
    "Found: $($straySkills.FullName -join ', ')"

# --- 1b + 3. registry rows are plugin-carried, and the plugin really ships them
$mcps = Get-Content -LiteralPath (Join-Path $repoRoot 'registry/mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$packageDirs = Get-PackageDirs
$packageNames = @($packageDirs | ForEach-Object Name)
$shippedServers = @{}
foreach ($pkg in $packageDirs) {
    $mcpPath = Join-Path $pkg.FullName 'mcp.json'
    if (-not (Test-Path -LiteralPath $mcpPath -PathType Leaf)) {
        $legacy = Join-Path $pkg.FullName '.mcp.json'
        if (Test-Path -LiteralPath $legacy -PathType Leaf) { $mcpPath = $legacy } else { continue }
    }
    try { $doc = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Report "$($pkg.Name) mcp.json parses" $false $_.Exception.Message; continue }
    # schema: only $schema and mcpServers at the top level.
    $top = @($doc.PSObject.Properties.Name)
    $topOk = (@($top | Where-Object { $_ -notin @('$schema', 'mcpServers') }).Count -eq 0) -and
        (@($top | Where-Object { $_ -eq '$schema' }).Count -eq 1) -and
        (@($top | Where-Object { $_ -eq 'mcpServers' }).Count -eq 1)
    Report "$($pkg.Name) mcp.json carries only `$schema and mcpServers" $topOk "Found: $($top -join ', ')"
    Report "$($pkg.Name) mcp.json names the 1.0.0 MCP schema" ([string]$doc.'$schema' -ceq $mcpSchema) "Found '$($doc.'$schema')'."
    foreach ($server in @($doc.mcpServers.PSObject.Properties)) {
        $name = $server.Name
        $definition = $server.Value
        $keys = @($definition.PSObject.Properties.Name)
        $type = [string]$definition.type
        $variantFields = switch ($type) {
            'stdio' { @('type', 'command', 'args', 'env', 'cwd') }
            'streamable-http' { @('type', 'url', 'headers') }
            'sse' { @('type', 'url', 'headers') }
            default { @() }
        }
        $unknown = @($keys | Where-Object { $_ -notin $variantFields })
        $required = if ($type -eq 'stdio') { 'command' } else { 'url' }
        $ok = $type -in $serverTypes -and $unknown.Count -eq 0 -and $keys -contains $required -and
            -not [string]::IsNullOrWhiteSpace([string]$definition.$required)
        Report "$($pkg.Name) mcp.json server '$name' matches the $type variant" $ok `
            "type='$type', unknown fields: $($unknown -join ', '), '$required' present: $($keys -contains $required)."
        if ($ok -and -not $shippedServers.ContainsKey($name)) { $shippedServers[$name] = $pkg.Name }
    }
}

# Every registered server must be carried by a package. A row with no plugin is
# the second delivery path the owner direction removes.
foreach ($server in @($mcps.mcpServers)) {
    $ownerId = [string]$server.owner.id
    $ownerType = [string]$server.owner.type
    Report "registered MCP '$($server.id)' is owned by a capability package" `
        ($ownerType -ceq 'capability' -and $ownerId -and $ownerId -in $packageNames) `
        "owner.type='$ownerType' owner.id='$ownerId'."
    if ($ownerType -ceq 'capability' -and $ownerId) {
        Report "capability package '$ownerId' ships MCP server '$($server.id)' in its mcp.json" `
            ($shippedServers.ContainsKey([string]$server.id)) `
            "No mcp.json entry named '$($server.id)' found in $ownerId."
    }
}

# A package must not ship a server no row describes: that is the registry and the
# plugins disagreeing about what the fleet offers.
$registryIds = @($mcps.mcpServers | ForEach-Object { [string]$_.id })
$unregistered = @($shippedServers.Keys | Where-Object { $_ -notin $registryIds })
Report 'every MCP server a package ships is registered' ($unregistered.Count -eq 0) `
    "Shipped but not in registry/mcps.json: $($unregistered -join ', ')"

# --- 2. the portable manifest is the closed plugin schema --------------------
foreach ($pkg in $packageDirs) {
    $manifestPath = Join-Path $pkg.FullName 'plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Report "$($pkg.Name) plugin.json parses" $false $_.Exception.Message; continue }
    $fields = @($manifest.PSObject.Properties.Name)
    $extra = @($fields | Where-Object { $_ -notin $manifestFields })
    Report "$($pkg.Name) portable manifest uses only the 1.0.0 fields" ($extra.Count -eq 0) `
        "Not in plugin.schema.json: $($extra -join ', '). Host data belongs in .<host>-plugin/ or an extensions namespace."
    Report "$($pkg.Name) portable manifest declares the 1.0.0 plugin schema" `
        ([string]$manifest.'$schema' -ceq $pluginSchema) "Found '$($manifest.'$schema')'."
    if ($manifest.author) {
        $authorExtra = @(@($manifest.author.PSObject.Properties.Name) | Where-Object { $_ -notin @('name', 'email', 'url') })
        Report "$($pkg.Name) manifest author uses only name, email, url" ($authorExtra.Count -eq 0) `
            "Not in plugin.schema.json: $($authorExtra -join ', ')."
    }
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
