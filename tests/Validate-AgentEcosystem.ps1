#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot,
    [switch]$IncludeGlobalInstructions,
    [string]$UserProfilePath = $env:USERPROFILE,
    [switch]$Json
)

if ([string]::IsNullOrWhiteSpace($RegistryRoot)) {
    $RegistryRoot = Split-Path -Parent $PSScriptRoot
}
$RegistryRoot = [System.IO.Path]::GetFullPath($RegistryRoot)
$canonicalRepositoryRoot = [System.IO.Path]::GetFullPath(
    'C:\Repos\shmindmaster\agenthub'
).TrimEnd('\')

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
    'registry\hosts.json',
    'registry\mcps.json',
    'registry\native-connectors.json',
    'registry\gateway-profiles.json',
    'registry\worktree-roots.json'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $RegistryRoot $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Add-ValidationResult PASS "required:$relativePath" 'present'
    } else {
        Add-ValidationResult FAIL "required:$relativePath" 'missing'
    }
}

function Resolve-RegistryOwnedPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.Equals($canonicalRepositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $RegistryRoot
    }
    $canonicalPrefix = $canonicalRepositoryRoot + '\'
    if ($fullPath.StartsWith($canonicalPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $fullPath.Substring($canonicalPrefix.Length)
        return Join-Path $RegistryRoot $relativePath
    }
    return $fullPath
}

if ($IncludeGlobalInstructions) {
    $forbiddenRootPaths = @(
        'C:\package.js',
        'C:\.codex-plugin',
        'C:\.playwright-mcp',
        'C:\cache',
        'C:\product-demo-studio',
        'C:\registry',
        'C:\scripts',
        'C:\skills',
        'C:\Temp',
        'C:\tmp',
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

    $expectedAgentTempRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA 'AgentHub\tmp')
    )
    $configuredAgentTempRoot = [Environment]::GetEnvironmentVariable('TMPDIR', 'User')
    if (-not [string]::IsNullOrWhiteSpace($configuredAgentTempRoot) -and
        [System.IO.Path]::GetFullPath($configuredAgentTempRoot).Equals(
            $expectedAgentTempRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $expectedAgentTempRoot -PathType Container)) {
        Add-ValidationResult PASS 'global:agent-temp-root' 'TMPDIR is pinned below the AgentHub user runtime'
    } else {
        Add-ValidationResult FAIL 'global:agent-temp-root' 'TMPDIR must resolve to the AgentHub user runtime before agents restart'
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
        $canonicalSource = Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
        if (-not (Test-Path -LiteralPath $canonicalSource)) {
            Add-ValidationResult FAIL "capability:$($capability.id):source" 'canonical source missing'
            continue
        }
        Add-ValidationResult PASS "capability:$($capability.id):source" 'canonical source present'

        $hashBasis = Resolve-RegistryOwnedPath ([string]$capability.hashBasis)
        if (-not (Test-Path -LiteralPath $hashBasis)) {
            Add-ValidationResult FAIL "capability:$($capability.id):hash" 'hash-basis path missing'
            continue
        }

        $actualHash = Get-RegistryHashBasisValue $hashBasis
        if ($actualHash -eq $capability.contentHash) {
            $basisKind = if (Test-Path -LiteralPath $hashBasis -PathType Container) { 'full tree' } else { 'file' }
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

    $knownCapabilityIds = if ($registryObjects.ContainsKey('capabilities.json')) {
        @($registryObjects['capabilities.json'].capabilities.id)
    } else { @() }
    $invalidOwners = @(
        foreach ($mcp in $mcpServers) {
            $ownerProperty = $mcp.PSObject.Properties['owner']
            $ownerIdProperty = if ($ownerProperty -and $null -ne $ownerProperty.Value) {
                $ownerProperty.Value.PSObject.Properties['id']
            } else { $null }
            $ownerTypeProperty = if ($ownerProperty -and $null -ne $ownerProperty.Value) {
                $ownerProperty.Value.PSObject.Properties['type']
            } else { $null }
            if (-not $ownerProperty -or $null -eq $ownerProperty.Value -or
                -not $ownerIdProperty -or [string]::IsNullOrWhiteSpace([string]$ownerIdProperty.Value)) {
                "$($mcp.id):missing-owner"
            } elseif (-not $ownerTypeProperty -or [string]$ownerTypeProperty.Value -notin @('registry', 'capability')) {
                "$($mcp.id):unsupported-owner-type"
            } elseif ([string]$ownerTypeProperty.Value -eq 'capability' -and
                [string]$ownerIdProperty.Value -notin $knownCapabilityIds) {
                "$($mcp.id):unknown-capability-owner"
            }
        }
    )
    if ($invalidOwners.Count -eq 0) {
        Add-ValidationResult PASS 'registry:mcp-current-owners' 'every MCP has one current registry or capability owner'
    } else {
        Add-ValidationResult FAIL 'registry:mcp-current-owners' "invalid owners: $($invalidOwners -join ', ')"
    }

    $invalidLifecycles = @(
        foreach ($mcp in $mcpServers) {
            $activationMode = [string]$mcp.activationMode
            if ($activationMode -notin @('shared-remote', 'on-demand-local')) {
                "$($mcp.id):invalid-activation-mode"
                continue
            }
            if ($activationMode -eq 'shared-remote' -and
                ([string]$mcp.transport -ne 'http' -or [string]$mcp.scope -ne 'global-default')) {
                "$($mcp.id):shared-remote-must-be-global-http"
            }
            if ($activationMode -eq 'on-demand-local' -and
                ([string]$mcp.transport -ne 'stdio' -or [string]$mcp.scope -eq 'global-default')) {
                "$($mcp.id):on-demand-local-must-be-non-global-stdio"
            }
        }
    )
    if ($invalidLifecycles.Count -eq 0) {
        Add-ValidationResult PASS 'registry:mcp-lifecycle' 'global defaults are shared HTTP services and local stdio servers are on-demand only'
    } else {
        Add-ValidationResult FAIL 'registry:mcp-lifecycle' ($invalidLifecycles -join ', ')
    }

    $playwright = @($mcpServers | Where-Object id -eq 'playwright')
    $playwrightOutputValid = $false
    if ($playwright.Count -eq 1) {
        [object[]]$playwrightArgs = @($playwright[0].args)
        $playwrightOutputIndex = [Array]::IndexOf(
            $playwrightArgs,
            '--output-dir'
        )
        $playwrightOutputValid = (
            $playwrightOutputIndex -ge 0 -and
            $playwrightOutputIndex + 1 -lt $playwrightArgs.Count -and
            [string]$playwrightArgs[$playwrightOutputIndex + 1] -eq
                'C:/Users/SaroshHussain/AppData/Local/AgentHub/runtime/playwright'
        )
    }
    if ($playwrightOutputValid) {
        Add-ValidationResult PASS 'registry:playwright-output' 'output is pinned below the AgentHub user runtime root'
    } else {
        Add-ValidationResult FAIL 'registry:playwright-output' 'missing canonical --output-dir contract'
    }

    $invalidAliases = @(
        foreach ($retiredId in @('sh-knowledge', 'knowledge', 'legal', 'shwiki')) {
            $aliasesProperty = $mcpRegistry.PSObject.Properties['migrationAliases']
            $aliasProperty = if ($aliasesProperty -and $null -ne $aliasesProperty.Value) {
                $aliasesProperty.Value.PSObject.Properties[$retiredId]
            } else { $null }
            if (-not $aliasProperty -or [string]$aliasProperty.Value -ne 'repocontext') { $retiredId }
            if ($retiredId -in $mcpIds) { "$retiredId:generated-as-current" }
        }
    )
    if ($invalidAliases.Count -eq 0) {
        Add-ValidationResult PASS 'registry:mcp-migration-aliases' 'retired knowledge labels migrate only to repocontext'
    } else {
        Add-ValidationResult FAIL 'registry:mcp-migration-aliases' "invalid aliases: $($invalidAliases -join ', ')"
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

if ($registryObjects.ContainsKey('native-connectors.json') -and
    $registryObjects.ContainsKey('hosts.json') -and
    $registryObjects.ContainsKey('mcps.json')) {
    $connectorRegistry = $registryObjects['native-connectors.json']
    $knownHostIds = @($registryObjects['hosts.json'].hosts.id)
    $knownMcpIds = @($registryObjects['mcps.json'].mcpServers.id)
    $connectorHostIds = @($connectorRegistry.hosts.hostId)
    $connectorProblems = @()
    $expectedOnDemandLocal = @('brave-search', 'chrome-devtools', 'playwright', 'repocontext')
    $onDemandLifecycleDifference = @(Compare-Object `
        -ReferenceObject @($expectedOnDemandLocal | Sort-Object) `
        -DifferenceObject @($connectorRegistry.lifecyclePolicy.onDemandLocalMcpIds | Sort-Object))
    if ([string]$connectorRegistry.lifecyclePolicy.defaultHostConfiguration -ne 'shared-remote-only' -or
        [string]$connectorRegistry.lifecyclePolicy.sharedRemoteTransport -ne 'http' -or
        [string]$connectorRegistry.lifecyclePolicy.localFanoutPolicy -ne 'never-persist-on-demand-local-in-host-config' -or
        [string]$connectorRegistry.lifecyclePolicy.localActivationOwnerPolicy -ne 'plugin-skill-or-reviewed-shared-gateway' -or
        $onDemandLifecycleDifference.Count -ne 0) {
        $connectorProblems += 'mcp-lifecycle-policy'
    }
    if (@(Get-DuplicateValues $connectorHostIds).Count -gt 0) { $connectorProblems += 'duplicate-host-rows' }
    $connectorProblems += @($connectorHostIds | Where-Object { $_ -notin $knownHostIds } | ForEach-Object { "unknown-host:$_" })
    $connectorProblems += @($knownHostIds | Where-Object { $_ -notin $connectorHostIds } | ForEach-Object { "missing-host:$_" })
    foreach ($row in @($connectorRegistry.hosts | Where-Object {
        -not $_.PSObject.Properties['inheritsHostId'] -or -not $_.inheritsHostId
    })) {
        $classified = @(
            @($row.exposures.'plugin-owned') +
            @($row.exposures.'native-connector') +
            @($row.exposures.'shared-gateway') +
            @($row.exposures.'local-only')
        )
        $connectorProblems += @($classified | Where-Object { $_ -notin $knownMcpIds } | ForEach-Object { "$($row.hostId):unknown-mcp:$_" })
        if (@(Get-DuplicateValues $classified).Count -gt 0) { $connectorProblems += "$($row.hostId):duplicate-exposure" }
    }
    $codexFirecrawlSkillsOnly = @($connectorRegistry.skillsOnlyPlugins | Where-Object {
        $_.hostId -eq 'codex' -and $_.pluginId -eq 'firecrawl-ops@portfolio' -and
        $_.mcpId -eq 'firecrawl' -and
        $_.installedState -eq 'skills-only-no-mcp-manifest' -and
        $_.mcpOwner -eq 'registry/mcps.json' -and
        $_.sourcePath -eq 'C:/Repos/shmindmaster/agenthub/packages/portfolio-plugins/firecrawl-ops' -and
        $_.deploymentState -eq 'live-verified-pending-canonical-merge' -and
        $_.mutationPolicy -eq 'do-not-add-bundled-mcp-without-owner-reassignment'
    })
    $codexConnector = @($connectorRegistry.hosts | Where-Object hostId -eq 'codex')
    if (@($connectorRegistry.bundledServerSuppressions).Count -ne 0 -or
        $codexFirecrawlSkillsOnly.Count -ne 1 -or $codexConnector.Count -ne 1 -or
        'firecrawl' -notin @($codexConnector[0].exposures.'shared-gateway') -or
        'firecrawl' -in @($codexConnector[0].exposures.'plugin-owned')) {
        $connectorProblems += 'codex-firecrawl-skills-only-contract'
    }
    if ($connectorProblems.Count -eq 0) {
        Add-ValidationResult PASS 'registry:native-connectors' 'host exposure rows reference current hosts and MCPs without duplicate modes'
    } else {
        Add-ValidationResult FAIL 'registry:native-connectors' ($connectorProblems -join ', ')
    }
}

if ($registryObjects.ContainsKey('gateway-profiles.json') -and
    $registryObjects.ContainsKey('hosts.json') -and
    $registryObjects.ContainsKey('native-connectors.json')) {
    $gatewayRegistry = $registryObjects['gateway-profiles.json']
    $candidate = @($gatewayRegistry.candidates | Where-Object id -eq $gatewayRegistry.selectedCandidateId)
    $gatewayProblems = @()
    if ($candidate.Count -ne 1) { $gatewayProblems += 'selected-candidate-count' }
    else {
        if ([bool]$candidate[0].generationEnabled) { $gatewayProblems += 'generation-must-remain-disabled-until-production-profiles-pass' }
        if ([string]$candidate[0].activationState -ne 'partial-poc-pass') { $gatewayProblems += 'activation-must-record-partial-poc' }
        if ([string]$candidate[0].pocEvidence.context7ReadOnlyCall -ne 'passed') { $gatewayProblems += 'context7-poc-evidence' }
        if ([string]$candidate[0].pocEvidence.linearInitialization -ne 'passed') { $gatewayProblems += 'linear-poc-evidence' }
        if ([string]$candidate[0].pocEvidence.notionInitialization -ne 'blocked-missing-oauth') { $gatewayProblems += 'notion-oauth-evidence' }
        if ([int]$candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.unauthenticatedInitialize -ne 401 -or
            [int]$candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.bearerAuthenticatedInitialize -ne 200 -or
            [int]$candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.toolsList -ne 200) {
            $gatewayProblems += 'firecrawl-authenticated-poc-evidence'
        }
        if ([string]$candidate[0].endpoint.url -ne 'http://127.0.0.1:8811/mcp') { $gatewayProblems += 'unexpected-endpoint' }
        if ([string]$candidate[0].endpoint.authScheme -ne 'bearer') { $gatewayProblems += 'endpoint-must-use-bearer-auth' }
        if ([string]$candidate[0].endpoint.boundProfileId -ne [string]$candidate[0].selectedProfileId) {
            $gatewayProblems += 'endpoint-profile-binding'
        }
        $profiles = @($candidate[0].profiles)
        $selectedProfiles = @($profiles | Where-Object id -eq $candidate[0].selectedProfileId)
        if ($profiles.Count -ne 1 -or $selectedProfiles.Count -ne 1) {
            $gatewayProblems += 'single-selected-profile'
        } else {
            $connectorRows = @{}
            foreach ($connectorRow in @($registryObjects['native-connectors.json'].hosts)) {
                $connectorRows[[string]$connectorRow.hostId] = $connectorRow
            }
            $eligibleHostIds = @()
            $sharedIntersection = $null
            foreach ($hostId in @($registryObjects['hosts.json'].hosts.id)) {
                $effectiveRow = $connectorRows[[string]$hostId]
                $visited = @{}
                while ($effectiveRow -and
                    $effectiveRow.PSObject.Properties['inheritsHostId'] -and
                    $effectiveRow.inheritsHostId) {
                    if ($visited.ContainsKey([string]$effectiveRow.inheritsHostId)) {
                        $effectiveRow = $null
                        break
                    }
                    $visited[[string]$effectiveRow.inheritsHostId] = $true
                    $effectiveRow = $connectorRows[[string]$effectiveRow.inheritsHostId]
                }
                if (-not $effectiveRow) {
                    $gatewayProblems += "missing-effective-connector:$hostId"
                    continue
                }
                if ([bool]$effectiveRow.providerHeld) { continue }
                $eligibleHostIds += [string]$hostId
                $hostShared = @($effectiveRow.exposures.'shared-gateway')
                if ($null -eq $sharedIntersection) {
                    $sharedIntersection = @($hostShared)
                } else {
                    $sharedIntersection = @($sharedIntersection | Where-Object { $_ -in $hostShared })
                }
            }
            $mappedHostIds = @($selectedProfiles[0].hostMappings.hostId)
            $gatewayProblems += @($eligibleHostIds | Where-Object { $_ -notin $mappedHostIds } | ForEach-Object { "missing-host:$_" })
            $gatewayProblems += @($mappedHostIds | Where-Object { $_ -notin $eligibleHostIds } | ForEach-Object { "ineligible-host:$_" })
            if (@(Get-DuplicateValues $mappedHostIds).Count -gt 0) { $gatewayProblems += 'duplicate-host-mapping' }
            $managedIds = @($selectedProfiles[0].mcpServerIds)
            $gatewayProblems += @($sharedIntersection | Where-Object { $_ -notin $managedIds } | ForEach-Object { "missing-intersection-mcp:$_" })
            $gatewayProblems += @($managedIds | Where-Object { $_ -notin $sharedIntersection } | ForEach-Object { "non-intersection-mcp:$_" })
        }
    }
    if ($gatewayProblems.Count -eq 0) {
        Add-ValidationResult PASS 'registry:gateway-profiles' 'partial POC evidence is recorded and generation remains disabled for one authenticated endpoint'
    } else {
        Add-ValidationResult FAIL 'registry:gateway-profiles' ($gatewayProblems -join ', ')
    }
}

if ($registryObjects.ContainsKey('worktree-roots.json') -and $registryObjects.ContainsKey('hosts.json')) {
    $rootRegistry = $registryObjects['worktree-roots.json']
    $rootProblems = @()
    if ([string]$rootRegistry.canonicalRoot -ne 'C:/wt') { $rootProblems += 'canonical-root' }
    if ([int]$rootRegistry.schemaVersion -ne 2 -or
        [string]$rootRegistry.environmentContract.name -ne 'AGENTHUB_WORKTREE_ROOT' -or
        [string]$rootRegistry.environmentContract.ownership -ne 'agenthub-controller-managed' -or
        [string]$rootRegistry.environmentContract.expectedValue -ne 'C:/wt' -or
        [bool]$rootRegistry.environmentContract.required -ne $true -or
        [string]$rootRegistry.environmentContract.mutationPolicy -ne 'controller-set-to-canonical-value') {
        $rootProblems += 'environment-contract'
    }
    if ([string]$rootRegistry.deployedHelper -ne 'C:/Users/SaroshHussain/AppData/Local/AgentHub/bin/New-AgentHubWorktree.ps1' -or
        [string]$rootRegistry.installerScript -ne 'scripts/Install-WorktreePolicy.ps1') {
        $rootProblems += 'controller-deployment-contract'
    }
    $rootHostIds = @($rootRegistry.hosts.hostId)
    $knownHostIds = @($registryObjects['hosts.json'].hosts.id)
    $rootProblems += @($knownHostIds | Where-Object { $_ -notin $rootHostIds } | ForEach-Object { "missing-host:$_" })
    if (@(Get-DuplicateValues $rootHostIds).Count -gt 0) { $rootProblems += 'duplicate-host-row' }
    $qwenRow = @($rootRegistry.hosts | Where-Object hostId -eq 'qwen-code')
    if ($qwenRow.Count -ne 1 -or
        [string]$qwenRow[0].nativeBuiltIn.pathPattern -ne '<repository>/.qwen/worktrees/<name>' -or
        [string]$qwenRow[0].nativeBuiltIn.policyState -ne 'noncompliant-disabled') {
        $rootProblems += 'qwen-built-in-must-be-disabled'
    }
    $geminiRow = @($rootRegistry.hosts | Where-Object hostId -eq 'gemini')
    if ($geminiRow.Count -ne 1 -or
        [string]$geminiRow[0].nativeBuiltIn.pathPattern -ne '<repository>/.gemini/worktrees/<name>' -or
        [string]$geminiRow[0].nativeBuiltIn.policyState -ne 'noncompliant-disabled') {
        $rootProblems += 'gemini-built-in-must-be-disabled'
    }
    $fallbackRows = @($rootRegistry.hosts | Where-Object mechanism -eq 'agenthub-helper-plus-generated-policy')
    $allowedFallbackStates = @(
        'repository-ready-controller-sync-required',
        'retained-provider-held-controller-sync-required',
        'controller-sync-required',
        'controller-setting-and-sync-required',
        'managed-gemini-instructions',
        'repository-policy-required',
        'live-verified',
        'retained-provider-held-live-verified'
    )
    if ($fallbackRows.Count -ne 19 -or
        @($fallbackRows | Where-Object deploymentState -notin $allowedFallbackStates).Count -gt 0) {
        $rootProblems += 'fallback-deployment-contract'
    }
    if ($rootProblems.Count -eq 0) {
        Add-ValidationResult PASS 'registry:worktree-roots' 'C:/wt is canonical and every host has a documented enforcement mode'
    } else {
        Add-ValidationResult FAIL 'registry:worktree-roots' ($rootProblems -join ', ')
    }
}

$originUrl = git -C $RegistryRoot config --get remote.origin.url 2>$null
if ($LASTEXITCODE -eq 0 -and $originUrl) {
    Add-ValidationResult PASS 'git:origin' 'origin is configured'
} else {
    Add-ValidationResult WARN 'git:origin' 'no origin configured; GitHub publication is not yet wired'
}

if ($IncludeGlobalInstructions) {
    # Deployed global instructions must reference the durable canonical
    # checkout, even when validation is running from an isolated worktree.
    $policyPath = Join-Path $canonicalRepositoryRoot 'docs\worktree-management-policy.md'
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
