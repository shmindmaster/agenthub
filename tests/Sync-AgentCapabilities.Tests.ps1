$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Sync-AgentCapabilities.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

Describe 'Sync-AgentCapabilities Codex TOML preservation' {
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
                id = 'shwiki-context'
                name = 'ShWiki Context'
                scope = 'global-default'
                transport = 'http'
                url = 'https://shwiki.shtrial.com/api/mcp'
                headers = @{ Authorization = 'Bearer ${env:SHWIKI_MCP_TOKEN}' }
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
'@ | Set-Content -LiteralPath $config -Encoding UTF8

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $result = Get-Content -LiteralPath $config -Raw
        $result | Should Match '(?m)^\[plugins\."product-demo-studio@handoff"\]$'
        $result | Should Match 'enabled\s*=\s*true'
        $result | Should Match 'url\s*=\s*"https://shwiki\.shtrial\.com/api/mcp"'
        $result | Should Match 'bearer_token_env_var\s*=\s*"SHWIKI_MCP_TOKEN"'
        $result | Should Not Match 'command\s*='
    }
}

Describe 'Sync-AgentCapabilities Qwen JSON compatibility' {
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
                id = 'shwiki-context'
                name = 'ShWiki Context'
                scope = 'global-default'
                transport = 'http'
                url = 'https://shwiki.shtrial.com/api/mcp'
                headers = @{ Authorization = 'Bearer ${env:SHWIKI_MCP_TOKEN}' }
                credentialPolicy = 'environment-bearer-token'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        '{"$version":4,"model":{"name":"test-model"}}' | Set-Content -LiteralPath $settings -Encoding ASCII -NoNewline

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $bytes = [System.IO.File]::ReadAllBytes($settings)
        @($bytes[0..2]) -join ',' | Should Not Be '239,187,191'
        $raw = Get-Content -LiteralPath $settings -Raw
        $result = $raw | ConvertFrom-Json
        $result.model.name | Should Be 'test-model'
        $result.mcpServers.'shwiki-context'.httpUrl | Should Be 'https://shwiki.shtrial.com/api/mcp'
        $result.mcpServers.'shwiki-context'.headers.Authorization | Should Be 'Bearer ${SHWIKI_MCP_TOKEN}'
    }
}

Describe 'Sync-AgentCapabilities inactive Devin user configuration' {
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -IncludeInactiveAgents -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $result.agent.show_hints | Should Be $true
        $result.mcpServers.exa.type | Should Be 'http'
        $result.mcpServers.exa.url | Should Be 'https://mcp.exa.ai/mcp'
    }
}

Describe 'Sync-AgentCapabilities JSON collection preservation' {
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $raw = Get-Content -LiteralPath $config -Raw
        $raw | Should Match '"output":\["text"\]'
        $result = $raw | ConvertFrom-Json
        @($result.provider.'bailian-token-plan-personal'.models.'qwen3.6-flash'.modalities.output).Count | Should Be 1
        $result.provider.'bailian-token-plan-personal'.models.'qwen3.6-flash'.modalities.output[0] | Should Be 'text'
        $result.mcp.exa.url | Should Be 'https://mcp.exa.ai/mcp'
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $raw = Get-Content -LiteralPath $settings -Raw
        $raw | Should Match '"amp\.permissions":\['
        $result = $raw | ConvertFrom-Json
        @($result.'amp.permissions').Count | Should Be 1
        $result.'amp.permissions'[0].tool | Should Be '*'
        $result.'amp.mcpServers'.exa.url | Should Be 'https://mcp.exa.ai/mcp'
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        (@($result.mcpServers.PSObject.Properties.Name) -contains 'devin/context7') | Should Be $false
        $result.mcpServers.context7.serverUrl | Should Be 'https://mcp.context7.com/mcp'
    }
}

Describe 'Sync-AgentCapabilities Grok and Hermes remote MCP adapters' {
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $grok = Get-Content -LiteralPath $grokConfig -Raw
        $grok | Should Match '\[mcp_servers\.exa\]'
        $grok | Should Match 'https://mcp\.firecrawl\.dev/v2/mcp'
        $grok | Should Match 'Bearer \$\{FIRECRAWL_API_KEY\}'
        $grok | Should Not Match '\$\{env:FIRECRAWL_API_KEY\}'

        $hermes = Get-Content -LiteralPath $hermesConfig -Raw
        $hermes | Should Match '^mcp_servers:'
        $hermes | Should Match 'https://mcp\.exa\.ai/mcp'
        $hermes | Should Match 'Bearer \$\{FIRECRAWL_API_KEY\}'
        $hermes | Should Match '"custom user\.mcp":'
        $hermes | Should Match 'https://example\.invalid/mcp'
        $hermes | Should Match '(?m)^profiles:'
    }
}

Describe 'Sync-AgentCapabilities plugin-owned MCP deduplication' {
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

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $result = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        (@($result.mcpServers.PSObject.Properties.Name) -contains 'notion') | Should Be $false
        $result.mcpServers.exa.url | Should Be 'https://mcp.exa.ai/mcp'
    }
}
