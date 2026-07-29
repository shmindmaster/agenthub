#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
    [switch]$IncludeGlobalInstructions,
    [string]$UserProfilePath = $env:USERPROFILE,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

function Add-ValidationResult {
    param(
        [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [string]$Check,
        [string]$Detail
    )

    $results.Add([pscustomobject]@{
        status = $Status
        check = $Check
        detail = $Detail
    })
}

function Get-DuplicateValues {
    param([object[]]$Values)
    return @($Values | Where-Object { $null -ne $_ -and "$_" -ne '' } | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
}

function Get-RegistryHashBasisValue([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }

    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    [string[]]$filePaths = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object FullName)
    [Array]::Sort($filePaths, [System.StringComparer]::Ordinal)
    $inventory = @(
        foreach ($filePath in $filePaths) {
            $relativePath = $filePath.Substring($root.Length).TrimStart('\').Replace('\', '/')
            '{0}|{1}' -f $relativePath, (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
        }
    ) -join "`n"
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($inventory)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

$requiredFiles = @(
    'README.md',
    'AGENTS.md',
    'docs\worktree-management-policy.md',
    'registry\agents.json',
    'registry\capabilities.json',
    'registry\hosts.json'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $RegistryRoot $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Add-ValidationResult PASS "required:$relativePath" 'present'
    } else {
        Add-ValidationResult FAIL "required:$relativePath" 'missing'
    }
}

if ($IncludeGlobalInstructions) {
    $forbiddenRootPaths = @(
        'C:\registry-root',
        'C:\canonical-product-demo-studio',
        'C:\canonical-product-experience-engineering',
        'C:\canonical-browser-toolkit',
        'C:\profile'
    )
    foreach ($forbiddenPath in $forbiddenRootPaths) {
        if (Test-Path -LiteralPath $forbiddenPath) {
            Add-ValidationResult FAIL "forbidden-root:$forbiddenPath" 'unexpected drive-root fixture remains; remove it only through an explicit cleanup task'
        } else {
            Add-ValidationResult PASS "forbidden-root:$forbiddenPath" 'absent'
        }
    }

    $retiredAgentFleetOpsPath = Join-Path $UserProfilePath '.agents\skills\agent-fleet-ops'
    if (Test-Path -LiteralPath $retiredAgentFleetOpsPath) {
        Add-ValidationResult FAIL 'retired-skill:agent-fleet-ops' 'retired user skill remains installed; remove it only through an explicit cleanup task'
    } else {
        Add-ValidationResult PASS 'retired-skill:agent-fleet-ops' 'absent'
    }
}

$registryObjects = @{}
$registryDir = Join-Path $RegistryRoot 'registry'
if (Test-Path -LiteralPath $registryDir -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $registryDir -File -Filter '*.json') {
        try {
            $registryObjects[$file.Name] = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            Add-ValidationResult PASS "json:$($file.Name)" 'valid JSON'
        } catch {
            Add-ValidationResult FAIL "json:$($file.Name)" 'invalid JSON'
        }
    }
}

if ($registryObjects.ContainsKey('agents.json')) {
    $agents = $registryObjects['agents.json']
    $agentIds = @($agents.activeAgents | ForEach-Object { $_.id }) + @($agents.inactiveAgents | ForEach-Object { $_.id })
    $duplicates = @(Get-DuplicateValues $agentIds)
    if ($duplicates.Count -eq 0) {
        Add-ValidationResult PASS 'registry:agent-ids' "$($agentIds.Count) unique agent IDs"
    } else {
        Add-ValidationResult FAIL 'registry:agent-ids' "duplicate IDs: $($duplicates -join ', ')"
    }
}

if ($registryObjects.ContainsKey('hosts.json')) {
    $hostIds = @($registryObjects['hosts.json'].hosts.id)
    $duplicates = @(Get-DuplicateValues $hostIds)
    if ($duplicates.Count -eq 0) {
        Add-ValidationResult PASS 'registry:host-ids' "$($hostIds.Count) unique packaging host IDs"
    } else {
        Add-ValidationResult FAIL 'registry:host-ids' "duplicate IDs: $($duplicates -join ', ')"
    }
}

if ($registryObjects.ContainsKey('capabilities.json')) {
    $capabilityRegistry = $registryObjects['capabilities.json']
    $capabilities = @($capabilityRegistry.capabilities)
    $duplicates = @(Get-DuplicateValues @($capabilities.id))
    if ($duplicates.Count -eq 0) {
        Add-ValidationResult PASS 'registry:capability-ids' "$($capabilities.Count) unique capability IDs"
    } else {
        Add-ValidationResult FAIL 'registry:capability-ids' "duplicate IDs: $($duplicates -join ', ')"
    }

    if ($registryObjects.ContainsKey('agents.json')) {
        $knownAgentIds = @($registryObjects['agents.json'].activeAgents | ForEach-Object { $_.id }) + @($registryObjects['agents.json'].inactiveAgents | ForEach-Object { $_.id })
        $unknownMappings = @($capabilities.hostMappings.hostId | Sort-Object -Unique | Where-Object { $_ -notin $knownAgentIds })
        if ($unknownMappings.Count -eq 0) {
            Add-ValidationResult PASS 'registry:capability-host-mappings' 'all mappings reference registered agent IDs'
        } else {
            Add-ValidationResult FAIL 'registry:capability-host-mappings' "unknown agent IDs: $($unknownMappings -join ', ')"
        }
    }

    if ($registryObjects.ContainsKey('fleet-profile.json')) {
        $managedHosts = @($registryObjects['fleet-profile.json'].managedHosts)
        foreach ($baselineCapabilityId in @('product-demo-studio', 'product-experience-engineering', 'repocontext')) {
            $baselineCapability = @($capabilities | Where-Object id -eq $baselineCapabilityId)
            if ($baselineCapability.Count -ne 1) {
                Add-ValidationResult FAIL "coverage:$baselineCapabilityId" 'expected exactly one baseline capability definition'
                continue
            }
            $mappedHosts = @($baselineCapability[0].hostMappings | ForEach-Object hostId)
            $missingHosts = @($managedHosts | Where-Object { $_ -notin $mappedHosts })
            if ($missingHosts.Count -eq 0) {
                Add-ValidationResult PASS "coverage:$baselineCapabilityId" 'mapped to every managed host'
            } else {
                Add-ValidationResult FAIL "coverage:$baselineCapabilityId" "missing managed hosts: $($missingHosts -join ', ')"
            }
        }
    }

    foreach ($capability in $capabilities) {
        if (-not (Test-Path -LiteralPath $capability.canonicalSource)) {
            Add-ValidationResult FAIL "capability:$($capability.id):source" 'canonical source missing'
            continue
        }
        Add-ValidationResult PASS "capability:$($capability.id):source" 'canonical source present'

        if (-not (Test-Path -LiteralPath $capability.hashBasis)) {
            Add-ValidationResult FAIL "capability:$($capability.id):hash" 'hash-basis path missing'
            continue
        }

        $actualHash = Get-RegistryHashBasisValue $capability.hashBasis
        if ($actualHash -eq $capability.contentHash) {
            $basisKind = if (Test-Path -LiteralPath $capability.hashBasis -PathType Container) { 'full tree' } else { 'file' }
            Add-ValidationResult PASS "capability:$($capability.id):hash" "content hash current ($basisKind)"
        } else {
            Add-ValidationResult FAIL "capability:$($capability.id):hash" 'content hash drifted'
        }
    }
}

if ($registryObjects.ContainsKey('mcps.json')) {
    $mcpRegistry = $registryObjects['mcps.json']
    $mcpServers = @($mcpRegistry.mcpServers)
    $mcpIds = @($mcpServers | ForEach-Object { $_.id })
    $duplicateMcpIds = @(Get-DuplicateValues $mcpIds)
    if ($duplicateMcpIds.Count -eq 0) {
        Add-ValidationResult PASS 'registry:mcp-ids' "$($mcpIds.Count) unique MCP IDs"
    } else {
        Add-ValidationResult FAIL 'registry:mcp-ids' "duplicate IDs: $($duplicateMcpIds -join ', ')"
    }

    if ($registryObjects.ContainsKey('agents.json')) {
        $knownAgentIds = @($registryObjects['agents.json'].activeAgents | ForEach-Object { $_.id }) + @($registryObjects['agents.json'].inactiveAgents | ForEach-Object { $_.id })
        $unknownMcpOwners = @(
            foreach ($mcp in $mcpServers) {
                $ownersProperty = $mcp.PSObject.Properties['pluginOwnersByHost']
                if (-not $ownersProperty -or $null -eq $ownersProperty.Value) { continue }
                foreach ($owner in $ownersProperty.Value.PSObject.Properties) {
                    if ([string]$owner.Name -notin $knownAgentIds) { "$( $mcp.id ):$( $owner.Name )" }
                    if ([string]::IsNullOrWhiteSpace([string]$owner.Value)) { "$( $mcp.id ):$( $owner.Name ) has no plugin owner" }
                }
            }
        )
        if ($unknownMcpOwners.Count -eq 0) {
            Add-ValidationResult PASS 'registry:mcp-plugin-owners' 'plugin-owned MCP mappings reference registered hosts and non-empty owners'
        } else {
            Add-ValidationResult FAIL 'registry:mcp-plugin-owners' "invalid mappings: $($unknownMcpOwners -join ', ')"
        }
    }
}

$originUrl = git -C $RegistryRoot config --get remote.origin.url 2>$null
if ($LASTEXITCODE -eq 0 -and $originUrl) {
    Add-ValidationResult PASS 'git:origin' 'origin is configured'
} else {
    Add-ValidationResult WARN 'git:origin' 'no origin configured; GitHub publication is not yet wired'
}

if ($IncludeGlobalInstructions) {
    $policyPath = Join-Path $RegistryRoot 'docs\worktree-management-policy.md'
    $instructionPaths = @(
        @{ id = 'codex'; path = Join-Path $UserProfilePath '.codex\AGENTS.md' },
        @{ id = 'claude'; path = Join-Path $UserProfilePath '.claude\CLAUDE.md' }
    )

    foreach ($entry in $instructionPaths) {
        if (-not (Test-Path -LiteralPath $entry.path -PathType Leaf)) {
            Add-ValidationResult FAIL "global:$($entry.id):policy-pointer" 'instruction file missing'
            continue
        }
        $raw = Get-Content -LiteralPath $entry.path -Raw -Encoding UTF8
        if ($raw.Contains($policyPath)) {
            Add-ValidationResult PASS "global:$($entry.id):policy-pointer" 'canonical policy referenced'
        } else {
            Add-ValidationResult FAIL "global:$($entry.id):policy-pointer" 'canonical policy reference missing'
        }
    }

    $codexConfig = Join-Path $UserProfilePath '.codex\config.toml'
    $codexRaw = if (Test-Path -LiteralPath $codexConfig) { Get-Content -LiteralPath $codexConfig -Raw -Encoding UTF8 } else { '' }
    if ($codexRaw -match '(?m)^worktree-keep-count\s*=\s*5\s*$') {
        Add-ValidationResult PASS 'global:codex:retention' 'managed worktree keep count is 5'
    } else {
        Add-ValidationResult FAIL 'global:codex:retention' 'expected worktree-keep-count = 5'
    }

    $claudeSettingsPath = Join-Path $UserProfilePath '.claude\settings.json'
    try {
        $claudeSettings = Get-Content -LiteralPath $claudeSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($claudeSettings.cleanupPeriodDays -eq 7) {
            Add-ValidationResult PASS 'global:claude:retention' 'cleanup period is 7 days'
        } else {
            Add-ValidationResult FAIL 'global:claude:retention' 'expected cleanupPeriodDays = 7'
        }
        $agentTeamsEnabled = $false
        $envProperty = $claudeSettings.PSObject.Properties['env']
        if ($envProperty -and $null -ne $envProperty.Value) {
            $agentTeamsProperty = $envProperty.Value.PSObject.Properties['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS']
            if ($agentTeamsProperty) {
                $agentTeamsEnabled = [string]$agentTeamsProperty.Value -eq '1'
            }
        }
        if (-not $agentTeamsEnabled) {
            Add-ValidationResult PASS 'global:claude:agent-teams' 'experimental agent teams are not globally enabled'
        } else {
            Add-ValidationResult FAIL 'global:claude:agent-teams' 'experimental agent teams must remain disabled by default'
        }
    } catch {
        Add-ValidationResult FAIL 'global:claude:retention' 'settings missing or invalid JSON'
    }

    $longPaths = git config --global --get core.longpaths 2>$null
    if ($LASTEXITCODE -eq 0 -and $longPaths -eq 'true') {
        Add-ValidationResult PASS 'global:git:longpaths' 'enabled'
    } else {
        Add-ValidationResult FAIL 'global:git:longpaths' 'expected core.longpaths=true'
    }
}

$summary = [ordered]@{
    pass = @($results | Where-Object status -eq 'PASS').Count
    warn = @($results | Where-Object status -eq 'WARN').Count
    fail = @($results | Where-Object status -eq 'FAIL').Count
}

if ($Json) {
    [ordered]@{ summary = $summary; results = @($results.ToArray()) } | ConvertTo-Json -Depth 6
} else {
    $results | Format-Table status, check, detail -AutoSize
    Write-Output "Summary: pass=$($summary.pass) warn=$($summary.warn) fail=$($summary.fail)"
}

if ($summary.fail -gt 0) { exit 1 }
exit 0
