#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:currentPowerShellExecutable = if ($PSVersionTable.PSVersion.Major -lt 6) {
        (Get-Command powershell.exe -ErrorAction Stop).Source
    } else {
        (Get-Command pwsh -ErrorAction Stop).Source
    }
    $script:registryRoot = Join-Path $repoRoot 'registry'
    $script:capabilities = Get-Content -LiteralPath (Join-Path $registryRoot 'capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:mcps = Get-Content -LiteralPath (Join-Path $registryRoot 'mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:hosts = Get-Content -LiteralPath (Join-Path $registryRoot 'hosts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:connectorsPath = Join-Path $registryRoot 'native-connectors.json'
    $script:gatewaysPath = Join-Path $registryRoot 'gateway-profiles.json'
    $script:worktreeRootsPath = Join-Path $registryRoot 'worktree-roots.json'
}

Describe 'Runtime-centralization registry contracts' {
    It 'declares one current owner for every MCP without generating retired knowledge labels' {
        $capabilityIds = @($capabilities.capabilities.id)
        $retiredIds = @('sh-knowledge', 'knowledge', 'legal', 'shwiki')

        @($mcps.mcpServers.id | Where-Object { $_ -in $retiredIds }) | Should -BeNullOrEmpty
        foreach ($mcp in @($mcps.mcpServers)) {
            $mcp.owner | Should -Not -BeNullOrEmpty
            [string]$mcp.owner.type | Should -BeIn @('capability', 'registry')
            [string]$mcp.owner.id | Should -Not -BeNullOrEmpty
            if ($mcp.owner.type -eq 'capability') {
                [string]$mcp.owner.id | Should -BeIn $capabilityIds
            }
        }

        foreach ($retiredId in $retiredIds) {
            [string]$mcps.migrationAliases.$retiredId | Should -Be 'repocontext'
        }

        $playwright = @($mcps.mcpServers | Where-Object id -eq 'playwright')
        $playwright.Count | Should -Be 1
        $playwright[0].args | Should -Contain '--output-dir'
        $outputIndex = [Array]::IndexOf([object[]]$playwright[0].args, '--output-dir')
        $outputIndex | Should -BeGreaterThan -1
        $playwright[0].args[$outputIndex + 1] | Should -Be `
            'C:/Users/SaroshHussain/AppData/Local/AgentHub/runtime/playwright'
    }

    It 'keeps the fleet-wide default remote-only and local MCP runtimes on demand' {
        $globalDefaults = @($mcps.mcpServers | Where-Object scope -eq 'global-default')
        $onDemandLocal = @($mcps.mcpServers |
            Where-Object activationMode -eq 'on-demand-local')

        $globalDefaults.Count | Should -BeGreaterThan 0
        @($globalDefaults | Where-Object {
            $_.transport -ne 'http' -or $_.activationMode -ne 'shared-remote'
        }) | Should -BeNullOrEmpty

        @($onDemandLocal.id | Sort-Object) | Should -Be @(
            'brave-search',
            'chrome-devtools',
            'playwright',
            'repocontext'
        )
        @($onDemandLocal | Where-Object {
            $_.transport -ne 'stdio' -or $_.scope -eq 'global-default'
        }) | Should -BeNullOrEmpty

        $context7 = @($globalDefaults | Where-Object id -eq 'context7')
        $context7.Count | Should -Be 1
        $context7[0].url | Should -Be 'https://mcp.context7.com/mcp'

        $connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $connectors.lifecyclePolicy.localFanoutPolicy |
            Should -Be 'never-persist-on-demand-local-in-host-config'
        $connectors.lifecyclePolicy.localActivationOwnerPolicy |
            Should -Be 'plugin-skill-or-reviewed-shared-gateway'
    }

    It 'classifies every current host exposure as plugin-owned, native-connector, shared-gateway, local-only, or provider-held' {
        Test-Path -LiteralPath $connectorsPath -PathType Leaf | Should -BeTrue
        $connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $knownMcpIds = @($mcps.mcpServers.id)
        $hostRows = @($connectors.hosts)

        @($hostRows.hostId | Sort-Object) | Should -Be @($hosts.hosts.id | Sort-Object)
        @($connectors.exposureModes | Sort-Object) |
            Should -Be @('local-only', 'native-connector', 'plugin-owned', 'provider-held', 'shared-gateway')
        @($connectors.bundledServerSuppressions).Count | Should -Be 0
        $firecrawlSkillsOnly = @($connectors.skillsOnlyPlugins |
            Where-Object { $_.hostId -eq 'codex' -and $_.pluginId -eq 'firecrawl-ops@portfolio' -and $_.mcpId -eq 'firecrawl' })
        $firecrawlSkillsOnly.Count | Should -Be 1
        $firecrawlSkillsOnly[0].installedState | Should -Be 'skills-only-no-mcp-manifest'
        $firecrawlSkillsOnly[0].mcpOwner | Should -Be 'registry/mcps.json'
        $firecrawlSkillsOnly[0].mutationPolicy | Should -Be 'do-not-add-bundled-mcp-without-owner-reassignment'
        $firecrawlSkillsOnly[0].sourcePath | Should -Be `
            'C:/Repos/shmindmaster/agenthub/packages/portfolio-plugins/firecrawl-ops'
        $firecrawlSkillsOnly[0].deploymentState | Should -Be `
            'live-verified-pending-canonical-merge'

        $rowByHost = @{}
        foreach ($row in $hostRows) { $rowByHost[[string]$row.hostId] = $row }

        function Resolve-ConnectorRow {
            param([string]$HostId)
            $row = $rowByHost[$HostId]
            if ($row.inheritsHostId) { return Resolve-ConnectorRow -HostId ([string]$row.inheritsHostId) }
            return $row
        }

        $hostAliases = @{}
        foreach ($alias in @($capabilities.surfaceAliases)) {
            $hostAliases[[string]$alias.surfaceId] = [string]$alias.inheritsHostId
        }

        foreach ($hostRecord in @($hosts.hosts)) {
            $effectiveHostId = if ($hostAliases.ContainsKey([string]$hostRecord.id)) { $hostAliases[[string]$hostRecord.id] } else { [string]$hostRecord.id }
            $effective = Resolve-ConnectorRow -HostId ([string]$hostRecord.id)
            $classified = @(
                @($effective.exposures.'plugin-owned') +
                @($effective.exposures.'native-connector') +
                @($effective.exposures.'shared-gateway') +
                @($effective.exposures.'local-only')
            )
            $expected = @(
                $mcps.mcpServers | Where-Object {
                    -not $_.hosts -or $effectiveHostId -in @($_.hosts)
                } | ForEach-Object id
            )

            @($classified | Where-Object { $_ -notin $knownMcpIds }) | Should -BeNullOrEmpty
            @($classified | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
            @($classified | Sort-Object) | Should -Be @($expected | Sort-Object)

            if ($hostRecord.id -in @('cursor', 'cursor-agent')) {
                [bool]$effective.providerHeld | Should -BeTrue
            }
        }

        $codexRow = Resolve-ConnectorRow -HostId 'codex'
        @($codexRow.exposures.'plugin-owned') | Should -Not -Contain 'firecrawl'
        @($codexRow.exposures.'shared-gateway') | Should -Contain 'firecrawl'

        foreach ($hostId in @('qwen-code', 'qoder', 'vscode-insiders')) {
            $pluginHost = Resolve-ConnectorRow -HostId $hostId
            @($pluginHost.exposures.'plugin-owned') | Should -Contain 'descript'
            @($pluginHost.exposures.'shared-gateway') | Should -Not -Contain 'descript'
        }
        $copilotRow = Resolve-ConnectorRow -HostId 'copilot'
        @($copilotRow.exposures.'plugin-owned') | Should -Not -Contain 'descript'
        @($copilotRow.exposures.'shared-gateway') | Should -Contain 'descript'
        $qoderRow = Resolve-ConnectorRow -HostId 'qoder'
        @($qoderRow.exposures.'plugin-owned') | Should -Contain 'context7'
        @($qoderRow.exposures.'plugin-owned') | Should -Contain 'chrome-devtools'
        @($qoderRow.exposures.'shared-gateway') | Should -Not -Contain 'context7'

        $claudeRow = Resolve-ConnectorRow -HostId 'claude'
        @($claudeRow.exposures.'plugin-owned') | Should -Contain 'github'
        @($claudeRow.exposures.'plugin-owned') | Should -Contain 'notion'
        @($claudeRow.exposures.'native-connector') | Should -Contain 'canva'
        @($claudeRow.exposures.'native-connector') | Should -Contain 'descript'
        @($claudeRow.exposures.'shared-gateway') | Should -Not -Contain 'canva'
        @($claudeRow.exposures.'plugin-owned') | Should -Not -Contain 'descript'

        $productDemo = @($capabilities.capabilities | Where-Object id -eq 'product-demo-studio')
        $productDemo.Count | Should -Be 1
        $claudeProductDemoMapping = @($productDemo[0].hostMappings |
            Where-Object hostId -eq 'claude')
        $claudeProductDemoMapping.Count | Should -Be 1
        $claudeProductDemoMapping[0].deploymentStatus |
            Should -Be 'managed-loose-skills'
    }

    It 'owns the Firecrawl skills in the portfolio package without duplicating its MCP service' {
        $firecrawl = @($capabilities.capabilities | Where-Object id -eq 'firecrawl-ops')
        $firecrawl.Count | Should -Be 1
        $firecrawl[0].owner | Should -Be 'portfolio'
        $firecrawl[0].capabilityType | Should -Be 'skills-only-plugin'
        @($firecrawl[0].hostMappings).Count | Should -Be 1
        $firecrawl[0].hostMappings[0].hostId | Should -Be 'codex'
        $firecrawl[0].hostMappings[0].deploymentStatus | Should -Be `
            'native-plugin-installed'

        $packageRoot = Join-Path $repoRoot 'packages\portfolio-plugins\firecrawl-ops'
        $manifestPath = Join-Path $packageRoot '.codex-plugin\plugin.json'
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $packageRoot '.mcp.json') | Should -BeFalse
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $manifest.PSObject.Properties.Name | Should -Not -Contain 'mcpServers'

        $marketplace = Get-Content -LiteralPath `
            (Join-Path $repoRoot 'packages\portfolio-plugins\.claude-plugin\marketplace.json') `
            -Raw -Encoding UTF8 | ConvertFrom-Json
        $marketplaceEntry = @($marketplace.plugins | Where-Object name -eq 'firecrawl-ops')
        $marketplaceEntry.Count | Should -Be 1
        $marketplaceEntry[0].source | Should -Be './firecrawl-ops'
    }

    It 'declares one inactive Docker streaming endpoint with partial POC evidence and least-privilege mappings' {
        Test-Path -LiteralPath $gatewaysPath -PathType Leaf | Should -BeTrue
        $gateways = Get-Content -LiteralPath $gatewaysPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $candidate = @($gateways.candidates | Where-Object id -eq $gateways.selectedCandidateId)
        $candidate.Count | Should -Be 1
        $candidate[0].implementation | Should -Be 'docker-mcp-gateway'
        $candidate[0].installationState | Should -Be 'installed'
        $candidate[0].activationState | Should -Be 'partial-poc-pass'
        [bool]$candidate[0].generationEnabled | Should -BeFalse
        $candidate[0].endpoint.transport | Should -Be 'streaming'
        $candidate[0].endpoint.url | Should -Be 'http://127.0.0.1:8811/mcp'
        $candidate[0].endpoint.authTokenEnvironment | Should -Be 'MCP_GATEWAY_AUTH_TOKEN'
        $candidate[0].pocEvidence.context7ReadOnlyCall | Should -Be 'passed'
        $candidate[0].pocEvidence.linearInitialization | Should -Be 'passed'
        $candidate[0].pocEvidence.notionInitialization | Should -Be 'blocked-missing-oauth'
        $candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.unauthenticatedInitialize | Should -Be 401
        $candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.bearerAuthenticatedInitialize | Should -Be 200
        $candidate[0].pocEvidence.firecrawlAuthenticatedLoopback.toolsList | Should -Be 200
        $candidate[0].windowsRuntimeConstraint.observedFailure | Should -Be 'missing socat'
        (@($candidate[0].serverMappings | Where-Object mcpId -eq 'firecrawl'))[0].proofState |
            Should -Be 'poc-passed-remote'
        @($candidate[0].profiles).Count | Should -Be 1
        $candidate[0].selectedProfileId | Should -Be $candidate[0].profiles[0].id
        $candidate[0].endpoint.boundProfileId | Should -Be $candidate[0].selectedProfileId

        $connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $connectorRows = @{}
        foreach ($connectorRow in @($connectors.hosts)) { $connectorRows[[string]$connectorRow.hostId] = $connectorRow }
        function Resolve-GatewayConnectorRow {
            param([string]$HostId)
            $row = $connectorRows[$HostId]
            if ($row.inheritsHostId) { return Resolve-GatewayConnectorRow -HostId ([string]$row.inheritsHostId) }
            return $row
        }

        $eligibleHostIds = @(
            $hosts.hosts.id | Where-Object {
                $resolvedRow = Resolve-GatewayConnectorRow -HostId ([string]$_)
                -not [bool]$resolvedRow.providerHeld
            }
        )
        @($candidate[0].profiles[0].hostMappings.hostId | Sort-Object) |
            Should -Be @($eligibleHostIds | Sort-Object)

        $sharedIntersection = $null
        foreach ($eligibleHostId in $eligibleHostIds) {
            $resolvedConnector = Resolve-GatewayConnectorRow -HostId $eligibleHostId
            $sharedForHost = @($resolvedConnector.exposures.'shared-gateway')
            $sharedIntersection = if ($null -eq $sharedIntersection) {
                @($sharedForHost)
            } else {
                @($sharedIntersection | Where-Object { $_ -in $sharedForHost })
            }
        }
        @($candidate[0].profiles[0].mcpServerIds | Sort-Object) |
            Should -Be @($sharedIntersection | Sort-Object)

        $localOnly = @(
            $connectors.hosts |
                ForEach-Object { $_.exposures.'local-only' }
        )
        @($candidate[0].profiles[0].mcpServerIds | Where-Object { $_ -in $localOnly }) | Should -BeNullOrEmpty
    }

    It 'records C:\wt as the only root without inventing unsupported host settings' {
        Test-Path -LiteralPath $worktreeRootsPath -PathType Leaf | Should -BeTrue
        $roots = Get-Content -LiteralPath $worktreeRootsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $roots.canonicalRoot | Should -Be 'C:/wt'
        $roots.pathPattern | Should -Be 'C:/wt/{repository}/{task}'
        $roots.environmentContract.name | Should -Be 'AGENTHUB_WORKTREE_ROOT'
        $roots.environmentContract.expectedValue | Should -Be 'C:/wt'
        $roots.environmentContract.ownership | Should -Be 'agenthub-controller-managed'
        $roots.environmentContract.mutationPolicy | Should -Be 'controller-set-to-canonical-value'
        $roots.deployedHelper | Should -Be 'C:/Users/SaroshHussain/AppData/Local/AgentHub/bin/New-AgentHubWorktree.ps1'
        @($roots.hosts.hostId | Sort-Object) | Should -Be @($hosts.hosts.id | Sort-Object)

        $codex = @($roots.hosts | Where-Object hostId -eq 'codex')
        $codex.Count | Should -Be 1
        $codex[0].mechanism | Should -Be 'user-managed-native-setting'
        $codex[0].settingKey | Should -Be 'git-worktree-root'
        $codex[0].mutationPolicy | Should -Be 'verify-only'

        $claude = @($roots.hosts | Where-Object hostId -eq 'claude')
        $claude.Count | Should -Be 1
        $claude[0].cliMechanism | Should -Be 'WorktreeCreate-hook'
        $claude[0].desktopMutationPolicy | Should -Be 'verify-manually-never-overwrite'

        $qwen = @($roots.hosts | Where-Object hostId -eq 'qwen-code')
        $qwen.Count | Should -Be 1
        $qwen[0].mechanism | Should -Be 'agenthub-helper-plus-generated-policy'
        $qwen[0].nativeBuiltIn.policyState | Should -Be 'noncompliant-disabled'

        $gemini = @($roots.hosts | Where-Object hostId -eq 'gemini')
        $gemini.Count | Should -Be 1
        $gemini[0].nativeBuiltIn.pathPattern | Should -Be '<repository>/.gemini/worktrees/<name>'
        $gemini[0].nativeBuiltIn.policyState | Should -Be 'noncompliant-disabled'
        $gemini[0].disableSetting | Should -Be 'experimental.worktrees=false'

        $fallbackRows = @($roots.hosts | Where-Object mechanism -eq 'agenthub-helper-plus-generated-policy')
        $fallbackRows.Count | Should -Be 19
        @($fallbackRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.deploymentState) }) |
            Should -BeNullOrEmpty
        @($roots.hosts | Where-Object hostId -ne 'codex' |
            Where-Object { $_.PSObject.Properties['settingKey'] }) | Should -BeNullOrEmpty

        $hermes = @($roots.hosts | Where-Object hostId -eq 'hermes')
        $hermes[0].disableSetting | Should -Be 'worktree=false'
        $copilot = @($roots.hosts | Where-Object hostId -eq 'copilot')
        $copilot[0].disableSetting | Should -Be 'experimental=false'
        $warp = @($roots.hosts | Where-Object hostId -eq 'warp')
        $warp[0].mechanism | Should -Be 'agenthub-managed-native-tab-config'
        $qoder = @($roots.hosts | Where-Object hostId -eq 'qoder')
        $qoder[0].nativeBuiltIn.hookDiscoveryState | Should -Be 'binary-only-undocumented'
    }
}

Describe 'Sync-AgentHub gateway and native connector convergence' {
    It 'replaces gateway-managed direct MCPs with one endpoint and removes native duplicates narrowly' {
        $fixture = Join-Path $TestDrive 'gateway-sync'
        $fixtureRegistry = Join-Path $fixture 'registry'
        $profile = Join-Path $fixture 'profile'
        $runtime = Join-Path $fixture 'runtime'
        New-Item -ItemType Directory -Path $fixtureRegistry, $profile, $runtime -Force | Out-Null

        $claudeConfig = Join-Path $profile '.claude.json'
        @{
            mcpServers = @{
                notion = @{ type = 'http'; url = 'https://mcp.notion.com/mcp' }
                context7 = @{ type = 'http'; url = 'https://mcp.context7.com/mcp' }
                exa = @{ type = 'http'; url = 'https://mcp.exa.ai/mcp' }
                other = @{ type = 'http'; url = 'https://other.example.test/mcp' }
                custom = @{ type = 'http'; url = 'https://example.test/mcp' }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $claudeConfig -Encoding UTF8

        @{
            activeAgents = @(@{ id = 'claude'; nativePaths = @{ mcpUser = $claudeConfig } })
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'agents.json') -Encoding UTF8
        @{
            schemaVersion = 4
            migrationAliases = @{ shwiki = 'repocontext'; knowledge = 'repocontext'; legal = 'repocontext'; 'sh-knowledge' = 'repocontext' }
            mcpServers = @(
                @{ id = 'notion'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.notion.com/mcp'; credentialPolicy = 'oauth'; owner = @{ type = 'registry'; id = 'mcp-registry' } },
                @{ id = 'context7'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.context7.com/mcp'; credentialPolicy = 'provider-managed'; owner = @{ type = 'registry'; id = 'mcp-registry' } },
                @{ id = 'exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed'; owner = @{ type = 'registry'; id = 'mcp-registry' } },
                @{ id = 'other'; scope = 'global-default'; transport = 'http'; url = 'https://other.example.test/mcp'; credentialPolicy = 'provider-managed'; owner = @{ type = 'registry'; id = 'mcp-registry' } },
                @{ id = 'repocontext'; scope = 'global-default'; transport = 'stdio'; command = 'synthetic-repocontext'; args = @('serve'); credentialPolicy = 'none'; owner = @{ type = 'capability'; id = 'repocontext' } }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'capabilities.json') -Encoding UTF8
        @{
            schemaVersion = 1
            hosts = @(@{
                hostId = 'claude'
                providerHeld = $false
                exposures = @{
                    'plugin-owned' = @('notion')
                    'native-connector' = @()
                    'shared-gateway' = @('context7', 'exa', 'other')
                    'local-only' = @('repocontext')
                }
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'native-connectors.json') -Encoding UTF8
        @{
            schemaVersion = 1
            selectedCandidateId = 'docker-mcp-gateway'
            candidates = @(@{
                id = 'docker-mcp-gateway'
                implementation = 'docker-mcp-gateway'
                activationState = 'validated'
                generationEnabled = $true
                selectedProfileId = 'synthetic-shared'
                endpoint = @{
                    id = 'agenthub-gateway'
                    transport = 'streaming'
                    bindAddress = '127.0.0.1'
                    port = 8811
                    path = '/mcp'
                    url = 'http://127.0.0.1:8811/mcp'
                    authScheme = 'bearer'
                    authTokenEnvironment = 'MCP_GATEWAY_AUTH_TOKEN'
                    boundProfileId = 'synthetic-shared'
                }
                profiles = @(
                    @{
                        id = 'wrong-profile'
                        activationState = 'validated'
                        mcpServerIds = @('other')
                        hostMappings = @(@{ hostId = 'claude'; state = 'enabled' })
                    },
                    @{
                        id = 'synthetic-shared'
                        activationState = 'validated'
                        mcpServerIds = @('context7', 'exa')
                        hostMappings = @(@{ hostId = 'claude'; state = 'enabled' })
                    }
                )
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'gateway-profiles.json') -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result = Get-Content -LiteralPath $claudeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        @($result.mcpServers.PSObject.Properties.Name | Sort-Object) |
            Should -Be @('agenthub-gateway', 'custom', 'other', 'repocontext')
        $result.mcpServers.'agenthub-gateway'.url | Should -Be 'http://127.0.0.1:8811/mcp'
        $result.mcpServers.'agenthub-gateway'.headers.Authorization |
            Should -Be 'Bearer ${MCP_GATEWAY_AUTH_TOKEN}'
    }

    It 'removes a native connector duplicate while preserving unrelated Codex plugin settings' {
        $fixture = Join-Path $TestDrive 'native-sync'
        $fixtureRegistry = Join-Path $fixture 'registry'
        $profile = Join-Path $fixture 'profile'
        $runtime = Join-Path $fixture 'runtime'
        $codexConfig = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path $fixtureRegistry, (Split-Path -Parent $codexConfig), $runtime -Force | Out-Null

        @{
            activeAgents = @(@{ id = 'codex'; nativePaths = @{ config = $codexConfig } })
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'agents.json') -Encoding UTF8
        @{
            mcpServers = @(
                @{ id = 'canva'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.canva.com/mcp'; credentialPolicy = 'oauth'; owner = @{ type = 'registry'; id = 'mcp-registry' } },
                @{ id = 'context7'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.context7.com/mcp'; credentialPolicy = 'provider-managed'; owner = @{ type = 'registry'; id = 'mcp-registry' } }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'capabilities.json') -Encoding UTF8
        @{
            hosts = @(@{
                hostId = 'codex'
                exposures = @{
                    'plugin-owned' = @()
                    'native-connector' = @('canva')
                    'shared-gateway' = @('context7')
                    'local-only' = @()
                }
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'native-connectors.json') -Encoding UTF8
        @'
[mcp_servers.canva]
url = "https://mcp.canva.com/mcp"

[plugins."sample-plugin@personal".settings.runtime]
mode = "skills-only"
'@ | Set-Content -LiteralPath $codexConfig -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $firstHash = (Get-FileHash -LiteralPath $codexConfig -Algorithm SHA256).Hash
        try {
            $env:LOCALAPPDATA = $runtime
            & $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
        (Get-FileHash -LiteralPath $codexConfig -Algorithm SHA256).Hash |
            Should -Be $firstHash

        $result = Get-Content -LiteralPath $codexConfig -Raw -Encoding UTF8
        $result | Should -Not -Match '(?m)^\[mcp_servers\.canva\]\s*$'
        $result | Should -Match '(?m)^\[mcp_servers\.context7\]\s*$'
        $result | Should -Match '(?ms)^\[plugins\."sample-plugin@personal"\.settings\.runtime\]\s*\r?\nmode\s*=\s*"skills-only"'
    }

    It 'fails closed and preserves direct MCPs for malformed or ineligible gateway contracts' {
        $fixture = Join-Path $TestDrive 'gateway-fail-closed'
        $fixtureRegistry = Join-Path $fixture 'registry'
        $profile = Join-Path $fixture 'profile'
        $runtime = Join-Path $fixture 'runtime'
        $claudeConfig = Join-Path $profile '.claude.json'
        New-Item -ItemType Directory -Path $fixtureRegistry, $profile, $runtime -Force | Out-Null

        @{
            activeAgents = @(@{ id = 'claude'; nativePaths = @{ mcpUser = $claudeConfig } })
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'agents.json') -Encoding UTF8
        @{
            mcpServers = @(
                @{ id = 'context7'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.context7.com/mcp'; credentialPolicy = 'provider-managed'; owner = @{ type = 'registry'; id = 'mcp-registry' } }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'capabilities.json') -Encoding UTF8

        $baseConnector = @{
            hosts = @(@{
                hostId = 'claude'
                providerHeld = $false
                exposures = @{
                    'plugin-owned' = @()
                    'native-connector' = @()
                    'shared-gateway' = @('context7')
                    'local-only' = @()
                }
            })
        }
        $baseGateway = @{
            selectedCandidateId = 'docker-mcp-gateway'
            candidates = @(@{
                id = 'docker-mcp-gateway'
                activationState = 'validated'
                generationEnabled = $true
                selectedProfileId = 'shared'
                endpoint = @{
                    id = 'agenthub-gateway'
                    transport = 'streaming'
                    bindAddress = '127.0.0.1'
                    port = 8811
                    path = '/mcp'
                    url = 'http://127.0.0.1:8811/mcp'
                    authScheme = 'bearer'
                    authTokenEnvironment = 'MCP_GATEWAY_AUTH_TOKEN'
                    boundProfileId = 'shared'
                }
                profiles = @(@{
                    id = 'shared'
                    activationState = 'validated'
                    mcpServerIds = @('context7')
                    hostMappings = @(@{ hostId = 'claude'; state = 'enabled' })
                })
            })
        }

        $cases = @(
            @{ name = 'duplicate selected candidates'; mutate = {
                param($gateway, $connector)
                $duplicate = $gateway.candidates[0] |
                    ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $gateway.candidates += @($duplicate)
            } },
            @{ name = 'candidate not validated'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].activationState = 'partial-poc-pass'
            } },
            @{ name = 'generation disabled'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].generationEnabled = $false
            } },
            @{ name = 'selected profile not validated'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].profiles[0].activationState = 'poc-pending'
            } },
            @{ name = 'non-loopback endpoint'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.url = 'http://192.0.2.10:8811/mcp'
            } },
            @{ name = 'declared bind address mismatch'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.bindAddress = '127.0.0.2'
            } },
            @{ name = 'declared port mismatch'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.port = 8812
            } },
            @{ name = 'declared path mismatch'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.path = '/not-mcp'
            } },
            @{ name = 'URL query beyond declared path'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.url = 'http://127.0.0.1:8811/mcp?unexpected=true'
            } },
            @{ name = 'missing bearer auth'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.authScheme = 'none'
            } },
            @{ name = 'unsafe token environment name'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.authTokenEnvironment = 'bad-token-name'
            } },
            @{ name = 'endpoint bound to another profile'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].endpoint.boundProfileId = 'not-shared'
            } },
            @{ name = 'provider-held host'; mutate = {
                param($gateway, $connector)
                $connector.hosts[0].providerHeld = $true
            } },
            @{ name = 'host mapping disabled'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].profiles[0].hostMappings[0].state = 'poc-pending'
            } },
            @{ name = 'managed MCP not declared shared'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].profiles[0].mcpServerIds += @('other')
            } },
            @{ name = 'duplicate managed MCP'; mutate = {
                param($gateway, $connector)
                $gateway.candidates[0].profiles[0].mcpServerIds += @('context7')
            } },
            @{ name = 'plugin/native overlap'; mutate = {
                param($gateway, $connector)
                $connector.hosts[0].exposures.'native-connector' = @('context7')
            } },
            @{ name = 'missing connector row'; mutate = {
                param($gateway, $connector)
                $connector.hosts = @()
            } },
            @{ name = 'duplicate selected profile definitions'; mutate = {
                param($gateway, $connector)
                $duplicate = $gateway.candidates[0].profiles[0] |
                    ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $gateway.candidates[0].profiles += @($duplicate)
            } }
        )

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            foreach ($case in $cases) {
                $gateway = $baseGateway | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $connector = $baseConnector | ConvertTo-Json -Depth 10 | ConvertFrom-Json
                $mutation = $case.mutate
                & $mutation $gateway $connector
                $gateway | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $fixtureRegistry 'gateway-profiles.json') -Encoding UTF8
                $connector | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $fixtureRegistry 'native-connectors.json') -Encoding UTF8
                @{ mcpServers = @{ context7 = @{ type = 'http'; url = 'https://mcp.context7.com/mcp' } } } |
                    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $claudeConfig -Encoding UTF8

                & $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                    -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                    -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
                $LASTEXITCODE | Should -Be 0 -Because $case.name

                $result = Get-Content -LiteralPath $claudeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
                @($result.mcpServers.PSObject.Properties.Name) | Should -Contain 'context7' -Because $case.name
                @($result.mcpServers.PSObject.Properties.Name) | Should -Not -Contain 'agenthub-gateway' -Because $case.name
            }
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }
}

Describe 'AgentHub worktree-root helper' {
    BeforeAll {
        $script:worktreeHelper = Join-Path $repoRoot 'scripts\New-AgentHubWorktree.ps1'
        $script:canonicalFixtureRepo = Join-Path $TestDrive 'canonical-repo'
        $script:nestedFixtureWorktree = Join-Path $TestDrive 'nested-host-worktree'
        $null = & git init --quiet $canonicalFixtureRepo 2>&1
        $null = & git -C $canonicalFixtureRepo config user.name 'AgentHub Synthetic Test' 2>&1
        $null = & git -C $canonicalFixtureRepo config user.email 'agenthub-test@example.invalid' 2>&1
        'synthetic' | Set-Content -LiteralPath (Join-Path $canonicalFixtureRepo 'fixture.txt') -Encoding UTF8
        $null = & git -C $canonicalFixtureRepo add fixture.txt 2>&1
        $null = & git -C $canonicalFixtureRepo commit --quiet -m 'synthetic fixture' 2>&1
        $null = & git -C $canonicalFixtureRepo worktree add --quiet -b nested-fixture $nestedFixtureWorktree 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create nested synthetic worktree fixture.' }
    }

    It 'derives the canonical repository identity from git common-dir when invoked inside a worktree' {
        Test-Path -LiteralPath $worktreeHelper -PathType Leaf | Should -BeTrue
        $inputJson = @{ cwd = $nestedFixtureWorktree; name = 'safe-task' } | ConvertTo-Json -Compress
        $result = @($inputJson | & $worktreeHelper -PlanOnly)
        $result.Count | Should -Be 1
        $result[0] | Should -Be 'C:\wt\canonical-repo\safe-task'
    }

    It 'rejects ambiguous normalized names and repository identity overrides' {
        $slashName = @{ cwd = $nestedFixtureWorktree; name = 'Feature/Auth' } | ConvertTo-Json -Compress
        $spaceName = @{ cwd = $nestedFixtureWorktree; name = 'feature auth' } | ConvertTo-Json -Compress
        $trailingDotName = @{ cwd = $nestedFixtureWorktree; name = 'feature.' } | ConvertTo-Json -Compress
        { & $worktreeHelper -InputJson $slashName -PlanOnly } | Should -Throw '*safe*component*'
        { & $worktreeHelper -InputJson $spaceName -PlanOnly } | Should -Throw '*safe*component*'
        { & $worktreeHelper -InputJson $trailingDotName -PlanOnly } | Should -Throw '*safe*component*'
        {
            & $worktreeHelper -InputJson (@{ cwd = $nestedFixtureWorktree; name = 'safe-task' } | ConvertTo-Json -Compress) `
                -PlanOnly -RepositoryName 'not-the-canonical-repo'
        } | Should -Throw '*does not match*canonical*'
    }

    It 'fails closed for branch/target ambiguity and captures all git command output' {
        $source = Get-Content -LiteralPath $worktreeHelper -Raw -Encoding UTF8
        $source | Should -Match '--git-common-dir'
        $source | Should -Match 'expected.*branch'
        $source | Should -Match 'branch.*exists.*without.*registered target'
        $source | Should -Match 'git common dir'
        $source | Should -Match 'worktree add.*2>&1'
        ([regex]::Matches($source, '(?m)& git')).Count | Should -Be 1
    }

    It 'bases a new task branch on the invoking worktree HEAD' {
        'feature-only' | Set-Content -LiteralPath (Join-Path $nestedFixtureWorktree 'feature-only.txt') -Encoding UTF8
        $null = & git -C $nestedFixtureWorktree add feature-only.txt 2>&1
        $null = & git -C $nestedFixtureWorktree commit --quiet -m 'feature-only fixture' 2>&1
        $featureHead = (& git -C $nestedFixtureWorktree rev-parse HEAD).Trim()
        $mainHead = (& git -C $canonicalFixtureRepo rev-parse HEAD).Trim()
        $featureHead | Should -Not -Be $mainHead

        $global:AgentHubMockGitCalls = [System.Collections.Generic.List[object]]::new()
        Mock git {
            $call = @($args)
            $global:AgentHubMockGitCalls.Add($call)
            $joined = $call -join ' '
            if ($joined -match '--git-common-dir') {
                $global:LASTEXITCODE = 0
                return (Join-Path $canonicalFixtureRepo '.git')
            }
            if ($joined -match 'rev-parse --verify HEAD') {
                $global:LASTEXITCODE = 0
                return $featureHead
            }
            if ($joined -match 'show-ref --verify --quiet') {
                $global:LASTEXITCODE = 1
                return
            }
            $global:LASTEXITCODE = 0
        }
        Mock New-Item { [pscustomobject]@{ FullName = $Path } } -ParameterFilter {
            [string]$Path -like 'C:\wt\canonical-repo*'
        }

        $taskName = 'base-' + [guid]::NewGuid().ToString('N')
        $inputJson = @{ cwd = $nestedFixtureWorktree; name = $taskName } | ConvertTo-Json -Compress
        $result = @(& $worktreeHelper -InputJson $inputJson)
        $result | Should -Be "C:\wt\canonical-repo\$taskName"

        $headLookup = @($global:AgentHubMockGitCalls | Where-Object {
            ($_ -join ' ') -match [regex]::Escape("-C $nestedFixtureWorktree rev-parse --verify HEAD")
        })
        $headLookup.Count | Should -Be 1
        $addCall = @($global:AgentHubMockGitCalls | Where-Object { ($_ -join ' ') -match 'worktree add -b' })
        $addCall.Count | Should -Be 1
        $addCall[0][-1] | Should -Be $featureHead
        Remove-Variable -Name AgentHubMockGitCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'consumes only the approved user-owned worktree-root environment contract' {
        $previousRoot = $env:AGENTHUB_WORKTREE_ROOT
        try {
            $env:AGENTHUB_WORKTREE_ROOT = 'C:\wt'
            $result = & $worktreeHelper -InputJson (
                @{ cwd = $nestedFixtureWorktree; name = 'env-contract' } | ConvertTo-Json -Compress
            ) -PlanOnly
            $result | Should -Be 'C:\wt\canonical-repo\env-contract'

            $env:AGENTHUB_WORKTREE_ROOT = 'D:\not-agenthub'
            {
                & $worktreeHelper -InputJson (
                    @{ cwd = $nestedFixtureWorktree; name = 'rejected' } | ConvertTo-Json -Compress
                ) -PlanOnly
            } | Should -Throw '*must use C:\wt*'
        } finally {
            $env:AGENTHUB_WORKTREE_ROOT = $previousRoot
        }
    }

    It 'keeps cleanup eligibility under only C:\wt and labels legacy roots report-only' {
        $auditSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Audit-Worktrees.ps1') -Raw -Encoding UTF8
        $reaperSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Remove-StaleWorktrees.ps1') -Raw -Encoding UTF8

        $auditSource | Should -Match "\[string\]\`$ConfiguredRoot = 'C:\\wt'"
        $reaperSource | Should -Match "\[string\]\s+\`$ConfiguredRoot = 'C:\\wt'"
        $reaperSource | Should -Not -Match '\$EphemeralRoots'
        $auditSource | Should -Match 'forbidden-migration-source'
        $reaperSource | Should -Match 'forbidden-migration-source'
    }
}

Describe 'Worktree policy checker and local validation wiring' {
    It 'defaults to its containing repository and emits valid normal and JSON output' {
        $checker = Join-Path $repoRoot 'scripts\Test-WorktreeRootPolicy.ps1'
        $source = Get-Content -LiteralPath $checker -Raw -Encoding UTF8
        $source | Should -Match 'if\s*\(\[string\]::IsNullOrWhiteSpace\(\$RegistryRoot\)\)'
        $source | Should -Match '\$RegistryRoot\s*=\s*Split-Path -Parent \$PSScriptRoot'

        $syntheticProfile = Join-Path $TestDrive 'checker-profile'
        New-Item -ItemType Directory -Path $syntheticProfile -Force | Out-Null
        $normal = @(& $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive `
            -File $checker -RegistryRoot $repoRoot -UserProfilePath $syntheticProfile 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($normal -join "`n") | Should -Match 'Summary:'
        ($normal -join "`n") | Should -Not -Match 'missing or invalid registry'

        $jsonRaw = (& $currentPowerShellExecutable -NoLogo -NoProfile -NonInteractive `
            -File $checker -RegistryRoot $repoRoot -UserProfilePath $syntheticProfile -Json 2>&1) -join "`n"
        $LASTEXITCODE | Should -Be 0
        { $jsonRaw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        $parsed = $jsonRaw | ConvertFrom-Json
        [int]$parsed.summary.fail | Should -Be 0
        @($parsed.results).Count | Should -BeGreaterThan 0
    }

    It 'does not delegate configuration validation to a hosted workflow' {
        $workflowRoot = Join-Path $repoRoot '.github\workflows'
        @(
            Get-ChildItem -LiteralPath $workflowRoot -File `
                -ErrorAction SilentlyContinue |
                Where-Object Extension -in @('.yml', '.yaml')
        ) | Should -BeNullOrEmpty
    }

    It 'executes child script checks through the current PowerShell generation' {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            (Split-Path -Leaf $currentPowerShellExecutable) | Should -Be 'powershell.exe'
        } else {
            (Split-Path -Leaf $currentPowerShellExecutable) | Should -BeIn @('pwsh', 'pwsh.exe')
        }
        $source = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
        ([regex]::Matches($source, '& \$currentPowerShellExecutable')).Count | Should -BeGreaterOrEqual 5
    }
}
