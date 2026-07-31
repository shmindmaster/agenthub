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
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\RegistryContentHash.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$results = New-Object System.Collections.Generic.List[object]

function Get-CurrentPowerShellHostExecutable {
    $candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $currentExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($currentExecutable)) {
            $candidates.Add($currentExecutable)
        }
    } catch {
        # Fall back to the executable installed beside this PowerShell runtime.
    }
    foreach ($executableName in @('pwsh.exe', 'pwsh', 'powershell.exe')) {
        $candidate = Join-Path $PSHOME $executableName
        if (-not $candidates.Contains($candidate)) {
            $candidates.Add($candidate)
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "Cannot resolve the current PowerShell host executable from process $PID or PSHOME '$PSHOME'."
}

$powerShellHostExecutable = Get-CurrentPowerShellHostExecutable

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

$requiredFiles = @(
    'README.md',
    'AGENTS.md',
    'docs\worktree-management-policy.md',
    'registry\agents.json',
    'registry\capabilities.json',
    'registry\hosts.json',
    'registry\mcps.json',
    'registry\native-connectors.json',
    'registry\skill-ownership.json',
    'registry\runtime-policy.json',
    'registry\reviewer-execution-broker.json',
    'registry\product-video-delivery.json',
    'registry\gateway-profiles.json',
    'registry\automation-gates.json',
    'registry\worktree-roots.json',
    'scripts\Test-AutomationGatePolicy.ps1',
    'scripts\Test-LiveAgentFleetDrift.ps1'
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

$automationGateCheckerPath = Join-Path $RegistryRoot 'scripts\Test-AutomationGatePolicy.ps1'
if (Test-Path -LiteralPath $automationGateCheckerPath -PathType Leaf) {
    try {
        $automationGateOutput = & $powerShellHostExecutable -NoLogo -NoProfile -NonInteractive `
            -File $automationGateCheckerPath -RegistryRoot $RegistryRoot -Json
        if ($LASTEXITCODE -ne 0) {
            throw "checker exited with code $LASTEXITCODE"
        }
        $automationGateResult = $automationGateOutput | ConvertFrom-Json -ErrorAction Stop
        if ([int]$automationGateResult.summary.fail -eq 0) {
            Add-ValidationResult PASS 'registry:automation-gates' "policy passed $($automationGateResult.summary.pass) checks"
        } else {
            Add-ValidationResult FAIL 'registry:automation-gates' "policy reported $($automationGateResult.summary.fail) failures"
        }
    } catch {
        Add-ValidationResult FAIL 'registry:automation-gates' $_.Exception.Message
    }
} else {
    Add-ValidationResult FAIL 'registry:automation-gates' 'checker is missing'
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

if ($registryObjects.ContainsKey('skill-ownership.json')) {
    $ownershipRegistry = $registryObjects['skill-ownership.json']
    $externalOwners = @($ownershipRegistry.externalOwners)
    $retiredOwners = @($ownershipRegistry.retiredUnownedSkills)
    $ownershipProblems = New-Object System.Collections.Generic.List[string]
    $allSkillIds = @($externalOwners.skillId) + @($retiredOwners.skillId)
    $duplicateSkillIds = @(Get-DuplicateValues $allSkillIds)
    if ($duplicateSkillIds.Count -gt 0) {
        $ownershipProblems.Add(
            "duplicate skill IDs: $($duplicateSkillIds -join ', ')"
        )
    }

    $knownAgents = @()
    if ($registryObjects.ContainsKey('agents.json')) {
        $knownAgents = @($registryObjects['agents.json'].activeAgents) +
            @($registryObjects['agents.json'].inactiveAgents)
    }
    $knownAgentIds = @($knownAgents.id)
    $allowedPlaceholders = @('${USERPROFILE}', '${APPDATA}')
    $appDataPath = Join-Path $UserProfilePath 'AppData\Roaming'

    function Expand-ValidatedSkillOwnershipPath {
        param([string]$Template)
        $placeholders = @([regex]::Matches($Template, '\$\{[^}]+\}') |
            ForEach-Object Value | Sort-Object -Unique)
        $unsupported = @($placeholders | Where-Object {
            $_ -notin $allowedPlaceholders
        })
        if ($unsupported.Count -gt 0) {
            throw "unsupported placeholder(s): $($unsupported -join ', ')"
        }
        return [IO.Path]::GetFullPath(
            $Template.Replace('${USERPROFILE}', $UserProfilePath).
                Replace('${APPDATA}', $appDataPath).
                Replace('/', '\')
        ).TrimEnd('\')
    }

    foreach ($externalOwner in $externalOwners) {
        foreach ($hash in @(
            $externalOwner.skillHash,
            $externalOwner.treeHash
        ) + @($externalOwner.previousTreeHashes)) {
            if ([string]$hash -notmatch '^[A-Fa-f0-9]{64}$') {
                $ownershipProblems.Add(
                    "malformed hash for external skill $($externalOwner.skillId)"
                )
            }
        }
        foreach ($template in @($externalOwner.sourceCandidates) +
            @($externalOwner.sharedShadowPaths)) {
            try {
                [void](Expand-ValidatedSkillOwnershipPath -Template ([string]$template))
            } catch {
                $ownershipProblems.Add(
                    "$($externalOwner.skillId): $($_.Exception.Message)"
                )
            }
        }
        foreach ($target in @($externalOwner.targets)) {
            $hostId = [string]$target.hostId
            if ($hostId -notin $knownAgentIds) {
                $ownershipProblems.Add(
                    "unknown target host $hostId for $($externalOwner.skillId)"
                )
                continue
            }
            try {
                $targetPath = Expand-ValidatedSkillOwnershipPath `
                    -Template ([string]$target.path)
                $agent = @($knownAgents | Where-Object id -eq $hostId |
                    Select-Object -First 1)
                $registeredSkillRoot = [string]$agent[0].nativePaths.skillsDir
                if ([string]::IsNullOrWhiteSpace($registeredSkillRoot)) {
                    throw "host $hostId has no registered skillsDir"
                }
                $registeredSkillRoot = [IO.Path]::GetFullPath(
                    $registeredSkillRoot
                ).TrimEnd('\')
                if (-not (
                    $targetPath.Equals(
                        $registeredSkillRoot,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -or
                    $targetPath.StartsWith(
                        $registeredSkillRoot + '\',
                        [StringComparison]::OrdinalIgnoreCase
                    )
                )) {
                    throw "target is outside registered skillsDir for $hostId"
                }
            } catch {
                $ownershipProblems.Add(
                    "$($externalOwner.skillId): $($_.Exception.Message)"
                )
            }
        }
    }

    foreach ($retiredOwner in $retiredOwners) {
        if ([string]::IsNullOrWhiteSpace([string]$retiredOwner.blockerReason)) {
            $ownershipProblems.Add(
                "retired unowned skill $($retiredOwner.skillId) has no blocker reason"
            )
        }
        foreach ($hash in @($retiredOwner.observedHashes)) {
            if ([string]$hash -notmatch '^[A-Fa-f0-9]{64}$') {
                $ownershipProblems.Add(
                    "malformed hash for retired skill $($retiredOwner.skillId)"
                )
            }
        }
        foreach ($template in @($retiredOwner.paths)) {
            try {
                [void](Expand-ValidatedSkillOwnershipPath -Template ([string]$template))
            } catch {
                $ownershipProblems.Add(
                    "$($retiredOwner.skillId): $($_.Exception.Message)"
                )
            }
        }
    }

    if ($ownershipProblems.Count -eq 0) {
        Add-ValidationResult PASS 'registry:skill-ownership' `
            "$($externalOwners.Count) external and $($retiredOwners.Count) retired-unowned skill contracts are valid"
    } else {
        Add-ValidationResult FAIL 'registry:skill-ownership' `
            (($ownershipProblems | Sort-Object -Unique) -join '; ')
    }
}

if ($registryObjects.ContainsKey('runtime-policy.json')) {
    $runtimePolicy = $registryObjects['runtime-policy.json']
    $budgetIds = @($runtimePolicy.resourceBudgets.id)
    $budgetDuplicates = @(Get-DuplicateValues $budgetIds)
    if ($runtimePolicy.schemaVersion -eq 1 -and
        $runtimePolicy.enforcement.autoTerminate -eq $false -and
        @($runtimePolicy.sessionFreshness.versionedCapabilities).Count -gt 0 -and
        $budgetIds.Count -gt 0 -and
        $budgetDuplicates.Count -eq 0) {
        Add-ValidationResult PASS 'registry:runtime-policy' `
            "$($budgetIds.Count) unique advisory resource budgets; auto-termination disabled"
    } else {
        Add-ValidationResult FAIL 'registry:runtime-policy' `
            'runtime policy must define versioned session freshness and unique advisory budgets without auto-termination'
    }
}

if ($registryObjects.ContainsKey('reviewer-execution-broker.json')) {
    $broker = $registryObjects['reviewer-execution-broker.json']
    if ($broker.schemaVersion -eq 1 -and
        $broker.mode -eq 'on-demand' -and
        $broker.persistentProcessAllowed -eq $false -and
        $broker.trust.registryEnvironmentVariable -eq 'AGENTHUB_EXECUTION_HOST_TRUST_CONFIG' -and
        $broker.trust.agentsMayAuthorReceipts -eq $false -and
        $broker.trust.agentsMaySignReceipts -eq $false -and
        $broker.trust.privateKeyMaterialAllowedInAgentHub -eq $false -and
        $broker.trust.privateKeyMaterialAllowedInAgentEnvironment -eq $false -and
        $broker.trust.missingTrustDecision -eq 'PIPELINE_BLOCKED' -and
        $broker.execution.spawnOnlyWhenRoleIsDispatched -eq $true -and
        $broker.execution.terminateAfterReceiptIsEmitted -eq $true -and
        $broker.execution.sharedDaemonRequired -eq $false) {
        Add-ValidationResult PASS 'registry:reviewer-execution-broker' `
            'on-demand, fail-closed, operator-owned signing contract is valid'
    } else {
        Add-ValidationResult FAIL 'registry:reviewer-execution-broker' `
            'broker must be on-demand and prohibit resident daemons, agent-authored receipts, and agent-readable signing keys'
    }
}

if ($registryObjects.ContainsKey('product-video-delivery.json')) {
    $delivery = $registryObjects['product-video-delivery.json']
    $products = @($delivery.products)
    $deliveryProblems = New-Object System.Collections.Generic.List[string]
    foreach ($duplicate in @(Get-DuplicateValues @($products.productId))) {
        $deliveryProblems.Add("duplicate productId $duplicate")
    }
    foreach ($duplicate in @(Get-DuplicateValues @($products.repositoryRoot))) {
        $deliveryProblems.Add("duplicate repositoryRoot $duplicate")
    }
    foreach ($product in $products) {
        if ([string]::IsNullOrWhiteSpace([string]$product.productId) -or
            -not [IO.Path]::IsPathRooted(([string]$product.repositoryRoot).Replace('/', '\')) -or
            -not [IO.Path]::IsPathRooted(([string]$product.reviewRoot).Replace('/', '\'))) {
            $deliveryProblems.Add("invalid mapping for $($product.productId)")
        }
    }
    if ($delivery.deliveryPolicy.classification -ne 'review-only' -or
        $delivery.deliveryPolicy.immutableCandidateDirectories -ne $true -or
        $delivery.deliveryPolicy.overwriteAllowed -ne $false -or
        $delivery.deliveryPolicy.publicationPromotionRequiresSignedHumanApproval -ne $true) {
        $deliveryProblems.Add('delivery policy does not separate immutable private review from publication')
    }
    if ($deliveryProblems.Count -eq 0) {
        Add-ValidationResult PASS 'registry:product-video-delivery' `
            "$($products.Count) private review destinations are uniquely mapped"
    } else {
        Add-ValidationResult FAIL 'registry:product-video-delivery' `
            (($deliveryProblems | Sort-Object -Unique) -join '; ')
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

        if ($capability.PSObject.Properties.Name -contains 'legacySkillTreeHashes') {
            $managedSkillNames = @($capability.managedSkillNames | ForEach-Object {
                [string]$_
            })
            $legacyHashProblems = @(
                foreach ($property in @(
                    $capability.legacySkillTreeHashes.PSObject.Properties
                )) {
                    if ([string]$property.Name -notin $managedSkillNames) {
                        "unknown skill $($property.Name)"
                    }
                    foreach ($hash in @($property.Value)) {
                        if ([string]$hash -notmatch '^[A-Fa-f0-9]{64}$') {
                            "invalid hash for $($property.Name)"
                        }
                    }
                }
            )
            if ($legacyHashProblems.Count -eq 0) {
                Add-ValidationResult PASS `
                    "capability:$($capability.id):legacy-skill-hashes" `
                    'legacy shared-skill retirement hashes are valid'
            } else {
                Add-ValidationResult FAIL `
                    "capability:$($capability.id):legacy-skill-hashes" `
                    (($legacyHashProblems | Sort-Object -Unique) -join '; ')
            }
        }

        $hashBasis = Resolve-RegistryOwnedPath ([string]$capability.hashBasis)
        if (-not (Test-Path -LiteralPath $hashBasis)) {
            Add-ValidationResult FAIL "capability:$($capability.id):hash" 'hash-basis path missing'
            continue
        }

        $actualHash = Get-AgentHubRegistryHashBasisValue -Path $hashBasis
        if ($actualHash -eq $capability.contentHash) {
            $basisKind = if (Test-Path -LiteralPath $hashBasis -PathType Container) { 'full tree' } else { 'file' }
            Add-ValidationResult PASS "capability:$($capability.id):hash" "content hash current ($basisKind)"
        } else {
            Add-ValidationResult FAIL "capability:$($capability.id):hash" 'content hash drifted'
        }
    }
}

# ---------------------------------------------------------------------------
# Deployment freshness. Package-style capabilities (plugin, plugin+mcp) are
# distributed to host-native runtimes as byte copies, sometimes pinned to a
# version-named cache directory (e.g. Claude's
# .claude\plugins\cache\<owner>\<id>\<version>). A canonical content change
# without a version bump never re-triggers those installs, so a deployed copy
# can go silently stale while every canonical/registry check above stays
# green. This section compares deployed bytes against canonical bytes (same
# normalization as Get-AgentHubStableFileHash) for every capability+host
# deployment that actually exists on this machine, and separately flags a
# version-pinned cache directory whose name no longer matches the canonical
# version. A host with no discoverable deployment for a capability is
# skipped, not failed: most registered hosts are not installed on every
# machine. Cursor and Qwen-code are deliberately excluded from paid model
# prompts: Cursor uses non-paid version/config/plugin/MCP checks, and Qwen-code's
# extension junction only mirrors a skills+agents subset (not the full
# package), so a whole-tree comparison would misreport it as missing files.
# Copilot and VS Code Insiders are excluded for now: their local plugin
# manifests were not verified against a real installation on this machine.
# ---------------------------------------------------------------------------
$deploymentExclusionPattern = '\\(?:node_modules|\.git|\.venv|venv|__pycache__|dist|build|\.next|\.in_use)\\'

function Get-AgentHubDeployedTreeInventory {
    param([Parameter(Mandatory)][string]$Root)
    $rootFull = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
    $inventory = @{}
    foreach ($file in Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch $deploymentExclusionPattern }) {
        $relativePath = $file.FullName.Substring($rootFull.Length).TrimStart('\').Replace('\', '/')
        $inventory[$relativePath] = Get-AgentHubStableFileHash -Path $file.FullName
    }
    return $inventory
}

function Test-AgentHubDeployedCapabilityFreshness {
    param(
        [string]$CapabilityId,
        [string]$HostId,
        [string]$DeployedPath,
        [hashtable]$CanonicalInventory,
        [string]$ExpectedVersion
    )
    if ([string]::IsNullOrWhiteSpace($DeployedPath) -or
        -not (Test-Path -LiteralPath $DeployedPath -PathType Container)) {
        Add-ValidationResult FAIL "deployment-freshness:${CapabilityId}:${HostId}" `
            "registered deployment root is missing: $DeployedPath"
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        $segmentName = Split-Path -Leaf $DeployedPath
        if ($segmentName -match '^\d+\.\d+\.\d+$') {
            if ($segmentName -ne $ExpectedVersion) {
                Add-ValidationResult FAIL "deployment-freshness:${CapabilityId}:${HostId}:version-pin" `
                    "deployed cache directory is pinned to version $segmentName but canonical version is ${ExpectedVersion}: $DeployedPath"
            } else {
                Add-ValidationResult PASS "deployment-freshness:${CapabilityId}:${HostId}:version-pin" `
                    "deployed cache directory version $segmentName matches canonical: $DeployedPath"
            }
        }
    }

    $deployedInventory = Get-AgentHubDeployedTreeInventory -Root $DeployedPath
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $CanonicalInventory.Keys) {
        if (-not $deployedInventory.ContainsKey($relativePath)) {
            $problems.Add("missing:$relativePath")
        } elseif ($deployedInventory[$relativePath] -ne $CanonicalInventory[$relativePath]) {
            $problems.Add("stale:$relativePath")
        }
    }
    foreach ($relativePath in $deployedInventory.Keys) {
        if (-not $CanonicalInventory.ContainsKey($relativePath)) {
            $problems.Add("extra:$relativePath")
        }
    }
    if ($problems.Count -eq 0) {
        Add-ValidationResult PASS "deployment-freshness:${CapabilityId}:${HostId}" `
            "deployed bytes at $DeployedPath match canonical"
    } else {
        $sample = ($problems | Sort-Object | Select-Object -First 8) -join ', '
        Add-ValidationResult FAIL "deployment-freshness:${CapabilityId}:${HostId}" `
            "$DeployedPath drifted from canonical ($($problems.Count) file(s)): $sample"
    }
}

function Get-AgentHubTomlPluginSectionEnabled {
    param([string]$Raw, [string]$PluginId)
    $match = [regex]::Match(
        $Raw,
        "(?ms)^\[plugins\.`"$([regex]::Escape($PluginId))`"\]\s*\r?\n(?<body>.*?)(?=^\[|\z)"
    )
    if (-not $match.Success) { return $false }
    return [bool][regex]::IsMatch($match.Groups['body'].Value, '(?m)^\s*enabled\s*=\s*true\s*$')
}

function Get-AgentHubTomlStringArray {
    param([string]$Raw, [string]$Section, [string]$Property)
    $sectionMatch = [regex]::Match(
        $Raw,
        "(?ms)^\[$([regex]::Escape($Section))\]\s*(?<body>.*?)(?=^\[|\z)"
    )
    if (-not $sectionMatch.Success) { return @() }
    $propertyMatch = [regex]::Match(
        $sectionMatch.Groups['body'].Value,
        "(?ms)^\s*$([regex]::Escape($Property))\s*=\s*\[(?<items>.*?)\]"
    )
    if (-not $propertyMatch.Success) { return @() }
    return @([regex]::Matches($propertyMatch.Groups['items'].Value, '"(?<value>[^"]+)"') |
        ForEach-Object { $_.Groups['value'].Value })
}

if ($registryObjects.ContainsKey('capabilities.json')) {
    $packageCapabilities = @($registryObjects['capabilities.json'].capabilities | Where-Object {
        [string]$_.capabilityType -in @('plugin', 'plugin+mcp')
    })

    $claudeInstalledPluginsPath = Join-Path $UserProfilePath '.claude\plugins\installed_plugins.json'
    $claudeInstalledPlugins = $null
    if (Test-Path -LiteralPath $claudeInstalledPluginsPath -PathType Leaf) {
        try {
            $claudeInstalledPlugins = Get-Content -LiteralPath $claudeInstalledPluginsPath -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            Add-ValidationResult FAIL 'deployment-freshness:claude:installed-plugins' `
                "invalid or unreadable JSON: $($_.Exception.Message)"
        }
    }

    $codexConfigPath = Join-Path $UserProfilePath '.codex\config.toml'
    $codexConfigRaw = if (Test-Path -LiteralPath $codexConfigPath -PathType Leaf) {
        Get-Content -LiteralPath $codexConfigPath -Raw -Encoding UTF8
    } else { $null }

    $qoderSettingsPath = Join-Path $UserProfilePath '.qoder\settings.json'
    $qoderSettings = $null
    if (Test-Path -LiteralPath $qoderSettingsPath -PathType Leaf) {
        try {
            $qoderSettings = Get-Content -LiteralPath $qoderSettingsPath -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            Add-ValidationResult FAIL 'deployment-freshness:qoder:settings' `
                "invalid or unreadable JSON: $($_.Exception.Message)"
        }
    }

    $grokRegistryPath = Join-Path $UserProfilePath '.grok\installed-plugins\registry.json'
    $grokConfigPath = Join-Path $UserProfilePath '.grok\config.toml'
    $grokRegistry = $null
    if (Test-Path -LiteralPath $grokRegistryPath -PathType Leaf) {
        try {
            $grokRegistry = Get-Content -LiteralPath $grokRegistryPath -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            Add-ValidationResult FAIL 'deployment-freshness:grok:registry' `
                "invalid or unreadable JSON: $($_.Exception.Message)"
        }
    }
    $grokConfigRaw = if (Test-Path -LiteralPath $grokConfigPath -PathType Leaf) {
        Get-Content -LiteralPath $grokConfigPath -Raw -Encoding UTF8
    } else { '' }
    $grokEnabledPlugins = @(Get-AgentHubTomlStringArray -Raw $grokConfigRaw -Section 'plugins' -Property 'enabled')

    foreach ($capability in $packageCapabilities) {
        $canonicalSource = Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
        if (-not (Test-Path -LiteralPath $canonicalSource -PathType Container)) { continue }
        $capabilityId = [string]$capability.id
        $owner = [string]$capability.owner
        $pluginId = "$capabilityId@$owner"

        $expectedVersion = $null
        $claudeManifestPath = Join-Path $canonicalSource '.claude-plugin\plugin.json'
        if (Test-Path -LiteralPath $claudeManifestPath -PathType Leaf) {
            try {
                $expectedVersion = [string](Get-Content -LiteralPath $claudeManifestPath -Raw -Encoding UTF8 |
                    ConvertFrom-Json -ErrorAction Stop).version
            } catch {
                $expectedVersion = $null
            }
        }

        $canonicalInventory = Get-AgentHubDeployedTreeInventory -Root $canonicalSource

        # Claude: version-pinned marketplace cache resolved from the
        # authoritative installed-plugins ledger (most recently installed entry).
        if ($claudeInstalledPlugins -and $claudeInstalledPlugins.plugins) {
            $entryProperty = $claudeInstalledPlugins.plugins.PSObject.Properties[$pluginId]
            if ($entryProperty) {
                $selected = @($entryProperty.Value | Sort-Object installedAt -Descending | Select-Object -First 1)
                if ($selected.Count -eq 1) {
                    Test-AgentHubDeployedCapabilityFreshness -CapabilityId $capabilityId -HostId 'claude' `
                        -DeployedPath ([string]$selected[0].installPath) -CanonicalInventory $canonicalInventory `
                        -ExpectedVersion $expectedVersion
                }
            }
        }

        # Codex: enabled plugin resolved to its version-pinned marketplace
        # cache directory (most recently modified real version folder).
        if ($codexConfigRaw -and (Get-AgentHubTomlPluginSectionEnabled -Raw $codexConfigRaw -PluginId $pluginId)) {
            $codexCacheParent = Join-Path $UserProfilePath ".codex\plugins\cache\$owner\$capabilityId"
            $codexVersionDir = @(
                Get-ChildItem -LiteralPath $codexCacheParent -Directory -ErrorAction SilentlyContinue |
                    Where-Object Name -notmatch '^latest$|^plugin-backup-' |
                    Sort-Object LastWriteTimeUtc -Descending |
                    Select-Object -First 1
            )
            if ($codexVersionDir.Count -eq 1) {
                Test-AgentHubDeployedCapabilityFreshness -CapabilityId $capabilityId -HostId 'codex' `
                    -DeployedPath $codexVersionDir[0].FullName -CanonicalInventory $canonicalInventory `
                    -ExpectedVersion $expectedVersion
            }
        }

        # Qoder: enabled plugin resolved to its (non-versioned) marketplace cache.
        if ($qoderSettings -and $qoderSettings.enabledPlugins) {
            $qoderEnabledProperty = $qoderSettings.enabledPlugins.PSObject.Properties[$pluginId]
            if ($qoderEnabledProperty -and [bool]$qoderEnabledProperty.Value) {
                $qoderCachePath = Join-Path $UserProfilePath ".qoder\plugins\cache\$owner\$capabilityId"
                Test-AgentHubDeployedCapabilityFreshness -CapabilityId $capabilityId -HostId 'qoder' `
                    -DeployedPath $qoderCachePath -CanonicalInventory $canonicalInventory `
                    -ExpectedVersion $expectedVersion
            }
        }

        # Grok: enabled plugin resolved to its hashed local install directory.
        if ($grokRegistry -and $grokRegistry.repos -and $capabilityId -in $grokEnabledPlugins) {
            $grokPluginPath = $null
            foreach ($repo in @($grokRegistry.repos.PSObject.Properties)) {
                $repoPluginProperty = $repo.Value.plugins.PSObject.Properties[$capabilityId]
                if ($repoPluginProperty) {
                    $grokPluginPath = [string]$repo.Value.path
                    break
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($grokPluginPath)) {
                Test-AgentHubDeployedCapabilityFreshness -CapabilityId $capabilityId -HostId 'grok' `
                    -DeployedPath $grokPluginPath -CanonicalInventory $canonicalInventory `
                    -ExpectedVersion $expectedVersion
            }
        }
    }
}

$codexMarketplacePath = Join-Path $RegistryRoot '.agents\plugins\marketplace.json'
if (-not (Test-Path -LiteralPath $codexMarketplacePath -PathType Leaf)) {
    Add-ValidationResult FAIL 'marketplace:codex:agenthub' 'canonical AgentHub marketplace is missing'
} else {
    try {
        $codexMarketplace = Get-Content -LiteralPath $codexMarketplacePath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        $expectedPluginNames = @(
            'product-demo-studio',
            'product-experience-engineering',
            'use-prompt-os',
            'use-campaign-production',
            'use-digitalocean',
            'use-elevenlabs',
            'clerk',
            'firecrawl-ops'
        )
        $actualPluginNames = @($codexMarketplace.plugins | ForEach-Object { [string]$_.name })
        $marketplaceProblems = @()
        if ([string]$codexMarketplace.name -ne 'agenthub') {
            $marketplaceProblems += 'internal-name'
        }
        if ([string]$codexMarketplace.interface.displayName -ne 'AgentHub') {
            $marketplaceProblems += 'display-name'
        }
        if (($expectedPluginNames -join '|') -cne ($actualPluginNames -join '|')) {
            $marketplaceProblems += 'plugin-set-or-order'
        }
        if (@($actualPluginNames | Group-Object | Where-Object Count -gt 1).Count -ne 0) {
            $marketplaceProblems += 'duplicate-plugin'
        }
        foreach ($entry in @($codexMarketplace.plugins)) {
            if ([string]$entry.source.source -ne 'local' -or
                [string]::IsNullOrWhiteSpace([string]$entry.source.path)) {
                $marketplaceProblems += "$($entry.name):source-contract"
                continue
            }
            $sourcePath = [IO.Path]::GetFullPath(
                (Join-Path $RegistryRoot ([string]$entry.source.path))
            )
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
                $marketplaceProblems += "$($entry.name):missing-source"
            }
        }
        if ($marketplaceProblems.Count -eq 0) {
            Add-ValidationResult PASS 'marketplace:codex:agenthub' 'one AgentHub catalog exposes all eight canonical plugin packages'
        } else {
            Add-ValidationResult FAIL 'marketplace:codex:agenthub' ($marketplaceProblems -join ', ')
        }
    } catch {
        Add-ValidationResult FAIL 'marketplace:codex:agenthub' "invalid marketplace JSON: $($_.Exception.Message)"
    }
}

$productVideoValidator = Join-Path $RegistryRoot `
    'packages\handoff-plugins\plugins\product-demo-studio\scripts\validate-package.mjs'
if (-not (Test-Path -LiteralPath $productVideoValidator -PathType Leaf)) {
    Add-ValidationResult FAIL 'capability:product-demo-studio:package-contract' 'package validator missing'
} else {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand) {
        Add-ValidationResult FAIL 'capability:product-demo-studio:package-contract' `
            'Node.js is required to validate the canonical product-video package'
    } else {
        $productVideoOutput = @(& $nodeCommand.Source $productVideoValidator 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Add-ValidationResult PASS 'capability:product-demo-studio:package-contract' `
                'canonical agents, schemas, policy, and validators are coherent'
        } else {
            Add-ValidationResult FAIL 'capability:product-demo-studio:package-contract' `
                (($productVideoOutput | ForEach-Object { "$_" }) -join '; ')
        }
    }
}

$elevenLabsValidator = Join-Path $RegistryRoot `
    'packages\portfolio-plugins\use-elevenlabs\scripts\validate_package.py'
if (-not (Test-Path -LiteralPath $elevenLabsValidator -PathType Leaf)) {
    Add-ValidationResult FAIL 'capability:use-elevenlabs:package-contract' 'package validator missing'
} else {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) {
        Add-ValidationResult FAIL 'capability:use-elevenlabs:package-contract' `
            'Python is required to validate the canonical ElevenLabs package'
    } else {
        $elevenLabsOutput = @(& $pythonCommand.Source $elevenLabsValidator 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Add-ValidationResult PASS 'capability:use-elevenlabs:package-contract' `
                'manifest identity, version, and canonical TTS adapter are coherent'
        } else {
            Add-ValidationResult FAIL 'capability:use-elevenlabs:package-contract' `
                (($elevenLabsOutput | ForEach-Object { "$_" }) -join '; ')
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
            if ($activationMode -notin @(
                'shared-remote',
                'on-demand-local',
                'host-configured-local'
            )) {
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
            if ($activationMode -eq 'host-configured-local' -and
                ([string]$mcp.transport -ne 'stdio' -or [string]$mcp.scope -ne 'global-default')) {
                "$($mcp.id):host-configured-local-must-be-global-stdio"
            }
        }
    )
    if ($invalidLifecycles.Count -eq 0) {
        Add-ValidationResult PASS 'registry:mcp-lifecycle' 'global defaults are shared HTTP services or explicit host-configured local servers; other local stdio servers remain on demand'
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
    $expectedOnDemandLocal = @('brave-search', 'playwright', 'repocontext')
    $expectedHostConfiguredLocal = @('chrome-devtools')
    $onDemandLifecycleDifference = @(Compare-Object `
        -ReferenceObject @($expectedOnDemandLocal | Sort-Object) `
        -DifferenceObject @($connectorRegistry.lifecyclePolicy.onDemandLocalMcpIds | Sort-Object))
    $hostConfiguredLifecycleDifference = @(Compare-Object `
        -ReferenceObject @($expectedHostConfiguredLocal | Sort-Object) `
        -DifferenceObject @($connectorRegistry.lifecyclePolicy.hostConfiguredLocalMcpIds | Sort-Object))
    if ([string]$connectorRegistry.lifecyclePolicy.defaultHostConfiguration -ne 'shared-remote-plus-explicit-local' -or
        [string]$connectorRegistry.lifecyclePolicy.sharedRemoteTransport -ne 'http' -or
        [string]$connectorRegistry.lifecyclePolicy.localFanoutPolicy -ne 'never-persist-on-demand-local-in-host-config' -or
        [string]$connectorRegistry.lifecyclePolicy.hostConfiguredLocalFanoutPolicy -ne 'persist-only-explicit-user-requested-readme-installations' -or
        [string]$connectorRegistry.lifecyclePolicy.localActivationOwnerPolicy -ne 'plugin-skill-or-reviewed-shared-gateway' -or
        $onDemandLifecycleDifference.Count -ne 0 -or
        $hostConfiguredLifecycleDifference.Count -ne 0) {
        $connectorProblems += 'mcp-lifecycle-policy'
    }
    $privateExtensionHosts = @(
        $connectorRegistry.hostPrivateExtensionPolicy.hosts | Sort-Object
    )
    if (@(Compare-Object -ReferenceObject @('claude', 'codex') `
            -DifferenceObject $privateExtensionHosts).Count -ne 0 -or
        [string]$connectorRegistry.hostPrivateExtensionPolicy.authority -ne 'user-managed' -or
        [bool]$connectorRegistry.hostPrivateExtensionPolicy.fleetParityRequired -or
        [bool]$connectorRegistry.hostPrivateExtensionPolicy.agentHubMayInstallOrRemove -or
        [bool]$connectorRegistry.hostPrivateExtensionPolicy.agentHubMayCopyToOtherHosts -or
        [string]$connectorRegistry.hostPrivateExtensionPolicy.inventoryMode -ne
            'canonical-conflict-and-resource-observation-only') {
        $connectorProblems += 'host-private-extension-boundary'
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
        $_.hostId -eq 'codex' -and $_.pluginId -eq 'firecrawl-ops@agenthub' -and
        $_.mcpId -eq 'firecrawl' -and
        $_.installedState -eq 'skills-only-no-mcp-manifest' -and
        $_.mcpOwner -eq 'registry/mcps.json' -and
        $_.sourcePath -eq 'C:/Repos/shmindmaster/agenthub/packages/portfolio-plugins/firecrawl-ops' -and
        $_.installedSourcePath -eq 'C:/Repos/shmindmaster/agenthub/packages/portfolio-plugins/firecrawl-ops' -and
        $_.deploymentState -eq 'live-verified' -and
        $_.mutationPolicy -eq 'do-not-add-bundled-mcp-without-owner-reassignment'
    })
    $codexAgentHubMarketplace = @($connectorRegistry.managedMarketplaces | Where-Object {
        $_.hostId -eq 'codex' -and
        $_.name -eq 'agenthub' -and
        $_.sourcePath -eq 'C:/Repos/shmindmaster/agenthub' -and
        $_.manifestPath -eq '.agents/plugins/marketplace.json'
    })
    $codexConnector = @($connectorRegistry.hosts | Where-Object hostId -eq 'codex')
    if (@($connectorRegistry.bundledServerSuppressions).Count -ne 0 -or
        $codexFirecrawlSkillsOnly.Count -ne 1 -or
        $codexAgentHubMarketplace.Count -ne 1 -or
        $codexConnector.Count -ne 1 -or
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
    $liveFleetCheckerPath = Join-Path $RegistryRoot 'scripts\Test-LiveAgentFleetDrift.ps1'
    if (Test-Path -LiteralPath $liveFleetCheckerPath -PathType Leaf) {
        try {
            $liveFleetOutput = & $powerShellHostExecutable -NoLogo -NoProfile -NonInteractive `
                -ExecutionPolicy Bypass -File $liveFleetCheckerPath `
                -RegistryRoot $RegistryRoot -UserProfilePath $UserProfilePath -Json
            $liveFleetExitCode = $LASTEXITCODE
            $liveFleet = (@($liveFleetOutput) -join [Environment]::NewLine) |
                ConvertFrom-Json -ErrorAction Stop
            Add-ValidationResult PASS 'global:live-fleet-inventory' `
                "inventoried $($liveFleet.inventory.agents.Count) agents, $($liveFleet.inventory.discoveryRoots.Count) discovery roots, $($liveFleet.inventory.plugins.Count) plugins, $($liveFleet.inventory.skills.Count) skills, $($liveFleet.inventory.mcpConfigurations.Count) MCP configs, and $($liveFleet.inventory.worktrees.Count) worktrees"
            foreach ($finding in @($liveFleet.results | Where-Object status -ne 'PASS')) {
                Add-ValidationResult ([string]$finding.status) `
                    "live:$([string]$finding.check)" ([string]$finding.detail)
            }
            if ($liveFleetExitCode -ne 0 -and [int]$liveFleet.summary.fail -eq 0) {
                Add-ValidationResult FAIL 'global:live-fleet-inventory-exit' `
                    "checker exited with code $liveFleetExitCode without a structured failure"
            }
        } catch {
            Add-ValidationResult FAIL 'global:live-fleet-inventory' $_.Exception.Message
        }
    } else {
        Add-ValidationResult FAIL 'global:live-fleet-inventory' 'checker is missing'
    }

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
    $agentHubSection = [regex]::Match(
        $codexRaw,
        '(?ms)^\[marketplaces\.agenthub\]\s*$.*?(?=^\[|\z)'
    ).Value
    $agentHubSource = [regex]::Match(
        $agentHubSection,
        "(?m)^source\s*=\s*['`"](?<value>[^'`"]+)['`"]\s*$"
    )
    $expectedAgentHubSource = '\\?\C:\Repos\shmindmaster\agenthub'
    if ($agentHubSource.Success -and
        $agentHubSource.Groups['value'].Value -ceq $expectedAgentHubSource -and
        $codexRaw -notmatch '(?m)^\[marketplaces\.(handoff|portfolio)\]\s*$') {
        Add-ValidationResult PASS 'global:codex:agenthub-marketplace' 'one canonical AgentHub marketplace referenced'
    } else {
        Add-ValidationResult FAIL 'global:codex:agenthub-marketplace' 'canonical AgentHub marketplace missing or a legacy AgentHub catalog remains'
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
