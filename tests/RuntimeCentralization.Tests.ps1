#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
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
    }

    It 'classifies every current host exposure as plugin-owned, native-connector, shared-gateway, local-only, or provider-held' {
        Test-Path -LiteralPath $connectorsPath -PathType Leaf | Should -BeTrue
        $connectors = Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $knownMcpIds = @($mcps.mcpServers.id)
        $hostRows = @($connectors.hosts)

        @($hostRows.hostId | Sort-Object) | Should -Be @($hosts.hosts.id | Sort-Object)
        @($connectors.exposureModes | Sort-Object) |
            Should -Be @('local-only', 'native-connector', 'plugin-owned', 'provider-held', 'shared-gateway')
        $firecrawlSuppression = @($connectors.bundledServerSuppressions |
            Where-Object { $_.hostId -eq 'codex' -and $_.pluginId -eq 'firecrawl-ops@personal' -and $_.mcpId -eq 'firecrawl' })
        $firecrawlSuppression.Count | Should -Be 1
        [bool]$firecrawlSuppression[0].expectedValue | Should -BeFalse
        $firecrawlSuppression[0].mutationPolicy | Should -Be 'user-setting-preserve-never-enable'

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
        @($candidate[0].profiles).Count | Should -BeGreaterThan 0
        @($candidate[0].profiles.hostMappings.hostId | Sort-Object) |
            Should -Be @($hosts.hosts.id | Sort-Object)

        $localOnly = @(
            (Get-Content -LiteralPath $connectorsPath -Raw -Encoding UTF8 | ConvertFrom-Json).hosts |
                ForEach-Object { $_.exposures.'local-only' }
        )
        @($candidate[0].profiles.mcpServerIds | Where-Object { $_ -in $localOnly }) | Should -BeNullOrEmpty
    }

    It 'records C:\wt as the only root without inventing unsupported host settings' {
        Test-Path -LiteralPath $worktreeRootsPath -PathType Leaf | Should -BeTrue
        $roots = Get-Content -LiteralPath $worktreeRootsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $roots.canonicalRoot | Should -Be 'C:/wt'
        $roots.pathPattern | Should -Be 'C:/wt/{repository}/{task}'
        $roots.environmentContract.name | Should -Be 'AGENTHUB_WORKTREE_ROOT'
        $roots.environmentContract.expectedValue | Should -Be 'C:/wt'
        $roots.environmentContract.mutationPolicy | Should -Be 'verify-only-never-overwrite'
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

        $fallbackRows = @($roots.hosts | Where-Object mechanism -eq 'agenthub-helper-plus-generated-policy')
        $fallbackRows.Count | Should -Be 20
        @($fallbackRows | Where-Object deploymentState -notmatch 'controller-sync-required') | Should -BeNullOrEmpty
        @($roots.hosts | Where-Object hostId -ne 'codex' |
            Where-Object { $_.PSObject.Properties['settingKey'] }) | Should -BeNullOrEmpty
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
                    'shared-gateway' = @('context7', 'exa')
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
                endpoint = @{
                    id = 'agenthub-gateway'
                    transport = 'streaming'
                    url = 'http://127.0.0.1:8811/mcp'
                    authTokenEnvironment = 'MCP_GATEWAY_AUTH_TOKEN'
                }
                profiles = @(@{
                    id = 'synthetic-shared'
                    activationState = 'validated'
                    mcpServerIds = @('context7', 'exa')
                    hostMappings = @(@{ hostId = 'claude'; state = 'enabled' })
                })
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixtureRegistry 'gateway-profiles.json') -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result = Get-Content -LiteralPath $claudeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        @($result.mcpServers.PSObject.Properties.Name | Sort-Object) |
            Should -Be @('agenthub-gateway', 'custom', 'repocontext')
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

[plugins."firecrawl-ops@personal".mcp_servers.firecrawl]
enabled = false
'@ | Set-Content -LiteralPath $codexConfig -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File (Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1') `
                -Apply -Validate -RegistryRoot $fixture -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }

        $result = Get-Content -LiteralPath $codexConfig -Raw -Encoding UTF8
        $result | Should -Not -Match '(?m)^\[mcp_servers\.canva\]\s*$'
        $result | Should -Match '(?m)^\[mcp_servers\.context7\]\s*$'
        $result | Should -Match '(?ms)^\[plugins\."firecrawl-ops@personal"\.mcp_servers\.firecrawl\]\s*\r?\nenabled\s*=\s*false'
    }
}

Describe 'AgentHub worktree-root helper' {
    It 'plans a normalized C:\wt\{repository}\{task} target from synthetic hook input' {
        $helper = Join-Path $repoRoot 'scripts\New-AgentHubWorktree.ps1'
        Test-Path -LiteralPath $helper -PathType Leaf | Should -BeTrue
        $result = '{"cwd":"C:\\Repos\\Synthetic\\sample-repo","name":"Feature/Auth"}' |
            & $helper -PlanOnly -RepositoryName 'sample-repo'
        $result | Should -Be 'C:\wt\sample-repo\feature-auth'
    }

    It 'consumes only the approved user-owned worktree-root environment contract' {
        $helper = Join-Path $repoRoot 'scripts\New-AgentHubWorktree.ps1'
        $previousRoot = $env:AGENTHUB_WORKTREE_ROOT
        try {
            $env:AGENTHUB_WORKTREE_ROOT = 'C:\wt'
            $result = & $helper -InputJson '{"cwd":"C:\\Repos\\Synthetic\\sample-repo","name":"Env Contract"}' `
                -PlanOnly -RepositoryName 'sample-repo'
            $result | Should -Be 'C:\wt\sample-repo\env-contract'

            $env:AGENTHUB_WORKTREE_ROOT = 'D:\not-agenthub'
            {
                & $helper -InputJson '{"cwd":"C:\\Repos\\Synthetic\\sample-repo","name":"Rejected"}' `
                    -PlanOnly -RepositoryName 'sample-repo'
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
