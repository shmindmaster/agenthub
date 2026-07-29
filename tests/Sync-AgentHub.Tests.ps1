$global:AgentHubSyncScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Sync-AgentHub.ps1'
$global:AgentHubSyncPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source

Describe 'Sync-AgentHub Codex TOML preservation' {
    It 'writes a bearer-authenticated HTTP MCP without consuming a following plugin section' {
        $fixture = Join-Path $TestDrive 'codex-plugin-preservation'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $config = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null

        @{
            activeAgents = @(@{
                id = 'codex'
                nativePaths = @{ config = $config }
            })
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{
            mcpServers = @(@{
                id = 'repocontext'
                name = 'RepoContext'
                scope = 'global-default'
                transport = 'http'
                url = 'https://repocontext.shtrial.com/api/mcp'
                headers = @{ Authorization = 'Bearer ${env:REPOCONTEXT_MCP_TOKEN}' }
                credentialPolicy = 'environment-bearer-token'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8

        @'
[mcp_servers.shwiki-context]
command = "old"
args = ["old"]

[plugins."product-demo-studio@handoff"]
enabled = true

[plugins."sample-plugin@personal".settings.runtime]
mode = "skills-only"
'@ | Set-Content -LiteralPath $config -Encoding UTF8

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $result = Get-Content -LiteralPath $config -Raw
        $result | Should -Match '(?m)^\[plugins\."product-demo-studio@handoff"\]\s*$'
        $result | Should -Match 'enabled\s*=\s*true'
        $result | Should -Match '(?m)^\[plugins\."sample-plugin@personal"\.settings\.runtime\]\s*$'
        $result | Should -Match '(?ms)^\[plugins\."sample-plugin@personal"\.settings\.runtime\]\s*\r?\nmode\s*=\s*"skills-only"'
        $result | Should -Match '\[mcp_servers\.repocontext\]'
        $result | Should -Not -Match '(?m)^\[mcp_servers\.shwiki-context\]\s*$'
        $result | Should -Match 'url\s*=\s*"https://repocontext\.shtrial\.com/api/mcp"'
        $result | Should -Match 'bearer_token_env_var\s*=\s*"REPOCONTEXT_MCP_TOKEN"'
        $result | Should -Not -Match 'command\s*='
    }
}

Describe 'Sync-AgentHub Qwen JSON compatibility' {
    It 'writes Qwen settings as UTF-8 without a BOM and preserves unrelated settings' {
        $fixture = Join-Path $TestDrive 'qwen-bom-compatibility'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $settings = Join-Path $profile '.qwen\settings.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null

        @{
            activeAgents = @(@{
                id = 'qwen-code'
                nativePaths = @{ settings = $settings }
            })
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{
            mcpServers = @(@{
                id = 'repocontext'
                name = 'RepoContext'
                scope = 'global-default'
                transport = 'http'
                url = 'https://repocontext.shtrial.com/api/mcp'
                headers = @{ Authorization = 'Bearer ${env:REPOCONTEXT_MCP_TOKEN}' }
                credentialPolicy = 'environment-bearer-token'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        '{"$version":4,"model":{"name":"test-model"}}' | Set-Content -LiteralPath $settings -Encoding ASCII -NoNewline

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $bytes = [System.IO.File]::ReadAllBytes($settings)
        @($bytes[0..2]) -join ',' | Should -Not -Be '239,187,191'
        $raw = Get-Content -LiteralPath $settings -Raw
        $result = $raw | ConvertFrom-Json
        $result.model.name | Should -Be 'test-model'
        $result.mcpServers.repocontext.httpUrl | Should -Be 'https://repocontext.shtrial.com/api/mcp'
        $result.mcpServers.repocontext.headers.Authorization | Should -Be 'Bearer ${REPOCONTEXT_MCP_TOKEN}'
    }
}

Describe 'Sync-AgentHub Qwen extension runtime placement' {
    It 'replaces an AgentHub-owned stale junction with the user runtime adapter' {
        $fixture = Join-Path $TestDrive 'qwen-extension-runtime'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $runtime = Join-Path $fixture 'runtime'
        $settings = Join-Path $profile '.qwen\settings.json'
        $extensions = Join-Path $profile '.qwen\extensions'
        $source = Join-Path $fixture 'canonical\synthetic'
        $sourceSkills = Join-Path $source 'skills'
        $staleTarget = Join-Path $fixture 'stale-adapter'
        $userLink = Join-Path $extensions 'agenthub-synthetic'
        New-Item -ItemType Directory -Path `
            (Join-Path $registryRoot 'registry'), `
            (Split-Path -Parent $settings), `
            $extensions, `
            $sourceSkills, `
            $staleTarget, `
            $runtime -Force | Out-Null

        @{ activeAgents = @(@{
            id = 'qwen-code'
            nativePaths = @{ settings = $settings; extensionsDir = $extensions }
        }); inactiveAgents = @() } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @() } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @(@{
            id = 'synthetic'
            canonicalSource = $source
            hostMappings = @(@{
                hostId = 'qwen-code'
                deploymentStatus = 'native-extension-junction'
            })
        }) } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        '{"mcpServers":{}}' | Set-Content -LiteralPath $settings -Encoding ASCII -NoNewline
        New-Item -ItemType Junction -Path $userLink -Target $staleTarget | Out-Null

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File $global:AgentHubSyncScriptPath -Apply -Validate `
                -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0

            $adapterPath = Join-Path $runtime `
                'AgentHub\runtime\qwen-code\extensions\agenthub-synthetic'
            [IO.Path]::GetFullPath([string](Get-Item -LiteralPath $userLink -Force).Target) |
                Should -Be ([IO.Path]::GetFullPath($adapterPath))
            [IO.Path]::GetFullPath([string](Get-Item -LiteralPath `
                (Join-Path $adapterPath 'skills') -Force).Target) |
                Should -Be ([IO.Path]::GetFullPath($sourceSkills))

            & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File $global:AgentHubSyncScriptPath -Audit -Validate `
                -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
            $LASTEXITCODE | Should -Be 0
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }
}

Describe 'Sync-AgentHub inactive Devin user configuration' {
    It 'writes remote HTTP MCP entries to the documented Windows user config path only when requested' {
        $fixture = Join-Path $TestDrive 'devin-user-config'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $config = Join-Path $profile 'AppData\Roaming\devin\config.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null

        @{
            activeAgents = @()
            inactiveAgents = @(@{ id = 'devin'; nativePaths = @{ config = $config } })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @(@{ id = 'exa'; name = 'Exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        '{"agent":{"show_hints":true},"mcpServers":{}}' | Set-Content -LiteralPath $config -Encoding ASCII -NoNewline

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -IncludeInactiveAgents -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $result.agent.show_hints | Should -Be $true
        $result.mcpServers.exa.type | Should -Be 'http'
        $result.mcpServers.exa.url | Should -Be 'https://mcp.exa.ai/mcp'
    }
}

Describe 'Sync-AgentHub JSON collection preservation' {
    It 'preserves OpenCode model modality arrays while updating MCPs' {
        $fixture = Join-Path $TestDrive 'opencode-model-modality-array'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $config = Join-Path $profile '.config\opencode\opencode.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null

        @{ activeAgents = @(@{ id = 'opencode'; nativePaths = @{ config = $config } }); inactiveAgents = @() } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @(@{ id = 'exa'; name = 'Exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ provider = @{ 'bailian-token-plan-personal' = @{ models = @{ 'qwen3.6-flash' = @{ modalities = @{ input = @('text', 'image'); output = @('text') } } } }; mcp = @{} } } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding UTF8

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $raw = Get-Content -LiteralPath $config -Raw
        $raw | Should -Match '"output":\["text"\]'
        $result = $raw | ConvertFrom-Json
        @($result.provider.'bailian-token-plan-personal'.models.'qwen3.6-flash'.modalities.output).Count | Should -Be 1
        $result.provider.'bailian-token-plan-personal'.models.'qwen3.6-flash'.modalities.output[0] | Should -Be 'text'
        $result.mcp.exa.url | Should -Be 'https://mcp.exa.ai/mcp'
    }

    It 'does not collapse an unrelated one-item array while updating Amp MCPs' {
        $fixture = Join-Path $TestDrive 'amp-one-item-array'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $settings = Join-Path $profile '.config\amp\settings.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null

        @{ activeAgents = @(@{ id = 'amp'; nativePaths = @{ settings = $settings } }); inactiveAgents = @() } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @(@{ id = 'exa'; name = 'Exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ 'amp.permissions' = @(@{ action = 'allow'; tool = '*' }); 'amp.mcpServers' = @{} } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settings -Encoding UTF8

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $raw = Get-Content -LiteralPath $settings -Raw
        $raw | Should -Match '"amp\.permissions":\['
        $result = $raw | ConvertFrom-Json
        @($result.'amp.permissions').Count | Should -Be 1
        $result.'amp.permissions'[0].tool | Should -Be '*'
        $result.'amp.mcpServers'.exa.url | Should -Be 'https://mcp.exa.ai/mcp'
    }

    It 'removes the legacy Windsurf Context7 alias when the canonical entry exists' {
        $fixture = Join-Path $TestDrive 'windsurf-context7-alias'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $config = Join-Path $profile '.codeium\windsurf\mcp_config.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $config) -Force | Out-Null

        @{ activeAgents = @(@{ id = 'windsurf'; nativePaths = @{ mcp = $config } }); inactiveAgents = @() } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @(@{ id = 'context7'; name = 'Context7'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.context7.com/mcp'; credentialPolicy = 'provider-managed' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ mcpServers = @{
            context7 = @{ serverUrl = 'https://mcp.context7.com/mcp' }
            'devin/context7' = @{ serverUrl = 'https://old-context7.invalid/mcp' }
        } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding UTF8

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        (@($result.mcpServers.PSObject.Properties.Name) -contains 'devin/context7') | Should -Be $false
        $result.mcpServers.context7.serverUrl | Should -Be 'https://mcp.context7.com/mcp'
    }
}

Describe 'Sync-AgentHub Grok and Hermes remote MCP adapters' {
    It 'writes remote HTTP entries without materializing environment secrets' {
        $fixture = Join-Path $TestDrive 'text-host-configs'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $grokConfig = Join-Path $profile '.grok\config.toml'
        $hermesConfig = Join-Path $profile 'AppData\Local\hermes\config.yaml'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $grokConfig) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $hermesConfig) -Force | Out-Null

        @{
            activeAgents = @(
                @{ id = 'grok'; nativePaths = @{ config = $grokConfig } },
                @{ id = 'hermes'; nativePaths = @{ config = $hermesConfig } }
            )
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{
            mcpServers = @(
                @{ id = 'exa'; name = 'Exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed' },
                @{ id = 'firecrawl'; name = 'Firecrawl'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.firecrawl.dev/v2/mcp'; headers = @{ Authorization = 'Bearer ${env:FIRECRAWL_API_KEY}' }; credentialPolicy = 'environment-bearer-token' }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        "[plugins]`nenabled = true`n" | Set-Content -LiteralPath $grokConfig -Encoding ASCII -NoNewline
        "mcp_servers:`n    `"custom user.mcp`":`n      url: `"https://example.invalid/mcp`"`nprofiles:`n  default: true`n" | Set-Content -LiteralPath $hermesConfig -Encoding ASCII -NoNewline

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $firstGrokHash = (Get-FileHash -LiteralPath $grokConfig -Algorithm SHA256).Hash
        $firstHermesHash = (Get-FileHash -LiteralPath $hermesConfig -Algorithm SHA256).Hash
        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0
        (Get-FileHash -LiteralPath $grokConfig -Algorithm SHA256).Hash |
            Should -Be $firstGrokHash
        (Get-FileHash -LiteralPath $hermesConfig -Algorithm SHA256).Hash |
            Should -Be $firstHermesHash

        $grok = Get-Content -LiteralPath $grokConfig -Raw
        $grok | Should -Match '\[mcp_servers\.exa\]'
        $grok | Should -Match 'https://mcp\.firecrawl\.dev/v2/mcp'
        $grok | Should -Match 'Bearer \$\{FIRECRAWL_API_KEY\}'
        $grok | Should -Not -Match '\$\{env:FIRECRAWL_API_KEY\}'

        $hermes = Get-Content -LiteralPath $hermesConfig -Raw
        $hermes | Should -Match '^mcp_servers:'
        $hermes | Should -Match 'https://mcp\.exa\.ai/mcp'
        $hermes | Should -Match 'Bearer \$\{FIRECRAWL_API_KEY\}'
        $hermes | Should -Match '"custom user\.mcp":'
        $hermes | Should -Match 'https://example\.invalid/mcp'
        $hermes | Should -Match '(?m)^profiles:'
    }
}

Describe 'Sync-AgentHub plugin-owned MCP deduplication' {
    It 'omits a host-native plugin MCP from the global Claude registration' {
        $fixture = Join-Path $TestDrive 'plugin-owned-mcp'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $config = Join-Path $profile '.claude.json'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path $profile -Force | Out-Null

        @{ activeAgents = @(@{ id = 'claude'; nativePaths = @{ mcpUser = $config } }); inactiveAgents = @() } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @(
            @{ id = 'notion'; name = 'Notion'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.notion.com/mcp'; credentialPolicy = 'oauth'; pluginOwnersByHost = @{ claude = 'notion@claude-plugins-official' } },
            @{ id = 'exa'; name = 'Exa'; scope = 'global-default'; transport = 'http'; url = 'https://mcp.exa.ai/mcp'; credentialPolicy = 'provider-managed' }
        ) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ mcpServers = @{ notion = @{ type = 'http'; url = 'https://mcp.notion.com/mcp' }; exa = @{ type = 'http'; url = 'https://mcp.exa.ai/mcp' } } } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding UTF8

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        (@($result.mcpServers.PSObject.Properties.Name) -contains 'notion') | Should -Be $false
        $result.mcpServers.exa.url | Should -Be 'https://mcp.exa.ai/mcp'
    }
}

Describe 'Sync-AgentHub default MCP lifecycle suppression' {
    It 'removes stale on-demand local servers without pruning unrelated user MCPs' {
        $fixture = Join-Path $TestDrive 'default-remote-only'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $runtime = Join-Path $fixture 'runtime'
        $claudeConfig = Join-Path $profile '.claude.json'
        $clineConfig = Join-Path $profile '.cline\data\settings\cline_mcp_settings.json'
        $codexConfig = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeConfig) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $clineConfig) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $codexConfig) -Force | Out-Null

        @{
            activeAgents = @(
                @{ id = 'claude'; nativePaths = @{ mcpUser = $claudeConfig } },
                @{ id = 'cline'; nativePaths = @{ mcp = $clineConfig } },
                @{ id = 'codex'; nativePaths = @{ config = $codexConfig } }
            )
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{
            mcpServers = @(
                @{
                    id = 'context7'
                    scope = 'global-default'
                    transport = 'http'
                    activationMode = 'shared-remote'
                    url = 'https://mcp.context7.com/mcp'
                    credentialPolicy = 'provider-managed'
                },
                @{
                    id = 'playwright'
                    scope = 'on-demand-desktop'
                    transport = 'stdio'
                    activationMode = 'On-Demand-Local'
                    command = 'npx'
                    args = @('-y', '@playwright/mcp@latest')
                    credentialPolicy = 'none'
                },
                @{
                    id = 'repocontext'
                    scope = 'on-demand-desktop'
                    transport = 'stdio'
                    activationMode = 'on-demand-local'
                    command = 'pnpm'
                    args = @('mcp:serve')
                    credentialPolicy = 'none'
                }
            )
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8

        @{
            mcpServers = @{
                playwright = @{ command = 'npx'; args = @('-y', '@playwright/mcp@latest') }
                shwiki = @{ command = 'pnpm'; args = @('mcp:serve') }
                custom = @{ type = 'http'; url = 'https://user-owned.example.test/mcp' }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $claudeConfig -Encoding UTF8
        @{
            mcpServers = @{
                playwright = @{ type = 'stdio'; command = 'npx'; args = @('-y', '@playwright/mcp@latest'); disabled = $false }
                custom = @{ type = 'streamableHttp'; url = 'https://user-owned.example.test/mcp'; disabled = $false }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $clineConfig -Encoding UTF8
        @'
[mcp_servers.repo-context]
command = "pnpm"
args = ["mcp:serve"]

[plugins."user-owned@personal"]
enabled = true
'@ | Set-Content -LiteralPath $codexConfig -Encoding UTF8

        $previousLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = $runtime
            & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive `
                -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
                -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile |
                Out-Host
            $LASTEXITCODE | Should -Be 0

            $claude = Get-Content -LiteralPath $claudeConfig -Raw | ConvertFrom-Json
            @($claude.mcpServers.PSObject.Properties.Name) | Should -Contain 'context7'
            @($claude.mcpServers.PSObject.Properties.Name) | Should -Contain 'custom'
            @($claude.mcpServers.PSObject.Properties.Name) | Should -Not -Contain 'playwright'
            @($claude.mcpServers.PSObject.Properties.Name) | Should -Not -Contain 'shwiki'
            @($claude.mcpServers.PSObject.Properties.Name) | Should -Not -Contain 'repocontext'

            $cline = Get-Content -LiteralPath $clineConfig -Raw | ConvertFrom-Json
            @($cline.mcpServers.PSObject.Properties.Name) | Should -Contain 'context7'
            @($cline.mcpServers.PSObject.Properties.Name) | Should -Contain 'custom'
            @($cline.mcpServers.PSObject.Properties.Name) | Should -Not -Contain 'playwright'

            $codex = Get-Content -LiteralPath $codexConfig -Raw
            $codex | Should -Not -Match '(?m)^\[mcp_servers\.repo-context\]\s*$'
            $codex | Should -Not -Match '(?m)^\[mcp_servers\.repocontext\]\s*$'
            $codex | Should -Match '(?m)^\[plugins\."user-owned@personal"\]\s*$'

            & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive `
                -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
                -Apply -Validate -ScopeProfile all -RegistryRoot $registryRoot `
                -UserProfile $profile |
                Out-Host
            $LASTEXITCODE | Should -Be 0

            $claudeAfterAll = Get-Content -LiteralPath $claudeConfig -Raw |
                ConvertFrom-Json
            @($claudeAfterAll.mcpServers.PSObject.Properties.Name) |
                Should -Not -Contain 'playwright'
            @($claudeAfterAll.mcpServers.PSObject.Properties.Name) |
                Should -Not -Contain 'shwiki'

            $clineAfterAll = Get-Content -LiteralPath $clineConfig -Raw |
                ConvertFrom-Json
            @($clineAfterAll.mcpServers.PSObject.Properties.Name) |
                Should -Not -Contain 'playwright'

            $codexAfterAll = Get-Content -LiteralPath $codexConfig -Raw
            $codexAfterAll |
                Should -Not -Match '(?m)^\[mcp_servers\.repo-context\]\s*$'
        } finally {
            $env:LOCALAPPDATA = $previousLocalAppData
        }
    }
}

Describe 'Sync-AgentHub GitHub remote MCP host schemas' {
    It 'renders one shmindmaster registration in each active host-native format without embedding a token' {
        $fixture = Join-Path $TestDrive 'github-remote-hosts'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        $paths = @{
            claude = Join-Path $profile '.claude.json'
            codex = Join-Path $profile '.codex\config.toml'
            qwen = Join-Path $profile '.qwen\settings.json'
            opencode = Join-Path $profile '.config\opencode\opencode.json'
            gemini = Join-Path $profile '.gemini\settings.json'
            antigravity = Join-Path $profile '.gemini\antigravity\mcp_config.json'
            antigravityLegacy = Join-Path $profile '.gemini\config\mcp_config.json'
            warp = Join-Path $profile '.warp\.mcp.json'
            cline = Join-Path $profile '.cline\data\settings\cline_mcp_settings.json'
            qoder = Join-Path $profile '.qoder\settings.json'
            copilot = Join-Path $profile '.copilot\mcp-config.json'
        }

        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        foreach ($path in $paths.Values) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        }

        @{
            activeAgents = @(
                @{ id = 'claude'; nativePaths = @{ mcpUser = $paths.claude } },
                @{ id = 'codex'; nativePaths = @{ config = $paths.codex } },
                @{ id = 'qwen-code'; nativePaths = @{ settings = $paths.qwen } },
                @{ id = 'opencode'; nativePaths = @{ config = $paths.opencode } },
                @{ id = 'gemini'; nativePaths = @{ settings = $paths.gemini } },
                @{ id = 'antigravity'; nativePaths = @{ mcp = $paths.antigravity; legacyMcp = $paths.antigravityLegacy } },
                @{ id = 'warp'; nativePaths = @{ mcp = $paths.warp } },
                @{ id = 'cline'; nativePaths = @{ mcp = $paths.cline } },
                @{ id = 'qoder'; nativePaths = @{ mcp = $paths.qoder } },
                @{ id = 'copilot'; nativePaths = @{ mcp = $paths.copilot } }
            )
            inactiveAgents = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8

        @{
            mcpServers = @(
                @{
                    id = 'github'
                    name = 'GitHub (shmindmaster)'
                    scope = 'global-default'
                    transport = 'http'
                    url = 'https://api.githubcopilot.com/mcp/'
                    headers = @{ Authorization = 'Bearer ${env:GITHUB_MCP_SHMINDMASTER_TOKEN}' }
                    credentialPolicy = 'environment-bearer-token'
                    pluginOwnersByHost = @{ copilot = 'built-in:github-mcp-server' }
                },
                @{
                    id = 'oauth-service'
                    name = 'OAuth service'
                    scope = 'global-default'
                    transport = 'http'
                    url = 'https://example.test/mcp'
                    credentialPolicy = 'oauth'
                    hosts = @('copilot')
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8

        @{
            mcpServers = @{
                'github-sh-pendoah' = @{
                    type = 'http'
                    url = 'https://api.githubcopilot.com/mcp/'
                    headers = @{ Authorization = 'Bearer ${GITHUB_TOKEN_SH_PENDOAH}' }
                }
                'github-sarosh-pendoah' = @{
                    type = 'http'
                    url = 'https://api.githubcopilot.com/mcp/'
                    headers = @{ Authorization = 'Bearer ${GITHUB_TOKEN_SAROSH_PENDOAH}' }
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $paths.claude -Encoding ASCII -NoNewline
        @'
[mcp_servers.github-shmindmaster]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_TOKEN_SHMINDMASTER"

[mcp_servers.github-sh-pendoah]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_TOKEN_SH_PENDOAH"
'@ | Set-Content -LiteralPath $paths.codex -Encoding ASCII -NoNewline
        '{"mcp":{"allowed":[]}}' | Set-Content -LiteralPath $paths.qwen -Encoding ASCII -NoNewline
        '{}' | Set-Content -LiteralPath $paths.opencode -Encoding ASCII -NoNewline
        '{}' | Set-Content -LiteralPath $paths.gemini -Encoding ASCII -NoNewline
        '{}' | Set-Content -LiteralPath $paths.antigravityLegacy -Encoding ASCII -NoNewline
        '{}' | Set-Content -LiteralPath $paths.warp -Encoding ASCII -NoNewline
        '{}' | Set-Content -LiteralPath $paths.cline -Encoding ASCII -NoNewline
        '{"mcpServers":{"github":{"type":"http","url":"https://api.githubcopilot.com/mcp/","headers":{"Authorization":"Bearer ${env:GITHUB_MCP_SHMINDMASTER_TOKEN}"}}}}' |
            Set-Content -LiteralPath $paths.qoder -Encoding ASCII -NoNewline
        '{"mcpServers":{"oauth-service":{"type":"http","url":"https://example.test/mcp","auth":"oauth"}}}' |
            Set-Content -LiteralPath $paths.copilot -Encoding ASCII -NoNewline

        & $global:AgentHubSyncPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $global:AgentHubSyncScriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should -Be 0

        $claude = Get-Content -LiteralPath $paths.claude -Raw | ConvertFrom-Json
        $claude.mcpServers.github.type | Should -Be 'http'
        $claude.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${GITHUB_MCP_SHMINDMASTER_TOKEN}'
        (@($claude.mcpServers.PSObject.Properties.Name | Where-Object { $_ -like 'github-*' }).Count) | Should -Be 0

        $codex = Get-Content -LiteralPath $paths.codex -Raw
        $codex | Should -Match 'url\s*=\s*"https://api\.githubcopilot\.com/mcp/"'
        $codex | Should -Match 'bearer_token_env_var\s*=\s*"GITHUB_MCP_SHMINDMASTER_TOKEN"'
        $codex | Should -Not -Match '(?m)^\[mcp_servers\.github-'

        $qwen = Get-Content -LiteralPath $paths.qwen -Raw | ConvertFrom-Json
        $qwen.mcpServers.github.httpUrl | Should -Be 'https://api.githubcopilot.com/mcp/'
        $qwen.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${GITHUB_MCP_SHMINDMASTER_TOKEN}'
        (@($qwen.mcp.allowed) -contains 'github') | Should -Be $true

        $opencode = Get-Content -LiteralPath $paths.opencode -Raw | ConvertFrom-Json
        $opencode.mcp.github.type | Should -Be 'remote'
        $opencode.mcp.github.oauth | Should -Be $false
        $opencode.mcp.github.headers.Authorization | Should -Be 'Bearer {env:GITHUB_MCP_SHMINDMASTER_TOKEN}'

        $gemini = Get-Content -LiteralPath $paths.gemini -Raw | ConvertFrom-Json
        $gemini.mcpServers.github.httpUrl | Should -Be 'https://api.githubcopilot.com/mcp/'
        $gemini.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${GITHUB_MCP_SHMINDMASTER_TOKEN}'
        (@($gemini.mcpServers.github.PSObject.Properties.Name) -contains 'type') | Should -Be $false

        foreach ($path in @($paths.antigravity, $paths.antigravityLegacy)) {
            $antigravity = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $antigravity.mcpServers.github.serverUrl | Should -Be 'https://api.githubcopilot.com/mcp/'
            $antigravity.mcpServers.github.headers.Authorization | Should -Be 'Bearer $GITHUB_MCP_SHMINDMASTER_TOKEN'
            (@($antigravity.mcpServers.github.PSObject.Properties.Name) -contains 'type') | Should -Be $false
        }

        $warp = Get-Content -LiteralPath $paths.warp -Raw | ConvertFrom-Json
        $warp.mcpServers.github.url | Should -Be 'https://api.githubcopilot.com/mcp/'
        $warp.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${GITHUB_MCP_SHMINDMASTER_TOKEN}'
        (@($warp.mcpServers.github.PSObject.Properties.Name) -contains 'type') | Should -Be $false

        $cline = Get-Content -LiteralPath $paths.cline -Raw | ConvertFrom-Json
        $cline.mcpServers.github.type | Should -Be 'streamableHttp'
        $cline.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${env:GITHUB_MCP_SHMINDMASTER_TOKEN}'

        $qoder = Get-Content -LiteralPath $paths.qoder -Raw | ConvertFrom-Json
        $qoder.mcpServers.github.type | Should -Be 'http'
        $qoder.mcpServers.github.headers.Authorization | Should -Be 'Bearer ${GITHUB_MCP_SHMINDMASTER_TOKEN}'

        $copilot = Get-Content -LiteralPath $paths.copilot -Raw | ConvertFrom-Json
        (@($copilot.mcpServers.PSObject.Properties.Name) -contains 'github') | Should -Be $false
        $copilot.mcpServers.'oauth-service'.type | Should -Be 'http'
        (@($copilot.mcpServers.'oauth-service'.PSObject.Properties.Name) -contains 'auth') | Should -Be $false

        $allManaged = @(
            $paths.claude,
            $paths.codex,
            $paths.qwen,
            $paths.opencode,
            $paths.gemini,
            $paths.antigravity,
            $paths.antigravityLegacy,
            $paths.warp,
            $paths.cline,
            $paths.qoder,
            $paths.copilot
        ) | ForEach-Object { Get-Content -LiteralPath $_ -Raw }
        ($allManaged -join "`n") | Should -Not -Match 'gh[pousr]_[A-Za-z0-9_]{20,}'
    }
}

Describe 'Sync-AgentHub Hermes absent discovery skip' {
    It 'returns not-verified when Hermes config path does not exist' {
        $fixture = Join-Path $TestDrive 'hermes-absent'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'standards') -Force | Out-Null
        $repoRoot = Split-Path -Parent $PSScriptRoot
        Copy-Item -LiteralPath (Join-Path $repoRoot 'standards\global-agent-policy.md') -Destination (Join-Path $registryRoot 'standards\global-agent-policy.md') -Force

        # Minimal registry with Hermes as an active agent but no config file on disk
        $agents = @{
            activeAgents = @(@{
                id = 'hermes'
                name = 'Hermes'
                version = '1.0'
                executable = 'C:\fake\hermes.exe'
                nativePaths = @{ config = (Join-Path $profile 'AppData\Local\hermes\config.yaml') }
                supportedCapabilities = @('mcp')
                status = 'active'
            })
            inactiveAgents = @()
        }
        $agents | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ managedHosts = @('hermes'); hostSettings = @{} } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\fleet-profile.json') -Encoding UTF8

        $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$global:AgentHubSyncScriptPath,
            '-Apply','-RegistryRoot',$registryRoot,'-UserProfile',$profile)
        $output = & $global:AgentHubSyncPowerShell @arguments 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'not-verified|Hermes is absent'
        # The config file should NOT have been created
        (Test-Path -LiteralPath (Join-Path $profile 'AppData\Local\hermes\config.yaml')) | Should -Be $false
    }
}

Describe 'Sync-AgentHub Deploy-File user-owned conflict reporting' {
    It 'reports user-owned-conflict in WhatIf mode without mutating the destination' {
        $fixture = Join-Path $TestDrive 'user-owned-conflict'
        $registryRoot = Join-Path $fixture 'registry-root'
        $profile = Join-Path $fixture 'profile'
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'scripts') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $registryRoot 'standards') -Force | Out-Null
        $repoRoot = Split-Path -Parent $PSScriptRoot
        Copy-Item -LiteralPath (Join-Path $repoRoot 'standards\global-agent-policy.md') -Destination (Join-Path $registryRoot 'standards\global-agent-policy.md') -Force

        # Create a user-owned file at the destination that is NOT in managed state
        $destDir = Join-Path $profile '.gemini'
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $destFile = Join-Path $destDir 'GEMINI.md'
        'user-owned content' | Set-Content -LiteralPath $destFile -Encoding UTF8

        # Minimal registry with Gemini as an active agent
        $agents = @{
            activeAgents = @(@{
                id = 'gemini'
                name = 'Gemini'
                version = '1.0'
                executable = 'C:\fake\gemini.exe'
                nativePaths = @{ config = (Join-Path $profile '.gemini\settings.json'); instruction = $destFile }
                supportedCapabilities = @('mcp','instructions')
                status = 'active'
            })
            inactiveAgents = @()
        }
        $agents | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\agents.json') -Encoding UTF8
        @{ mcpServers = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        @{ managedHosts = @('gemini'); hostSettings = @{} } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\fleet-profile.json') -Encoding UTF8

        # Run in Audit mode (WhatIf)
        $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$global:AgentHubSyncScriptPath,
            '-Audit','-RegistryRoot',$registryRoot,'-UserProfile',$profile)
        $output = & $global:AgentHubSyncPowerShell @arguments 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        # The user-owned file should be unchanged
        (Get-Content -LiteralPath $destFile -Raw).Trim() | Should -Be 'user-owned content'
    }
}
