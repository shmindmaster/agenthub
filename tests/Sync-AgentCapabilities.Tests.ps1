$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Sync-AgentCapabilities.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

Describe 'Sync-AgentCapabilities Codex TOML preservation' {
    It 'updates the final MCP section without consuming a following plugin section' {
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
                transport = 'stdio'
                command = 'pnpm'
                args = @('--dir','C:/Repos/shmindmaster/shwiki','mcp:wiki')
                credentialPolicy = 'none'
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
            -Apply -Prune -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $result = Get-Content -LiteralPath $config -Raw
        $result | Should Match '(?m)^\[plugins\."product-demo-studio@handoff"\]$'
        $result | Should Match 'enabled\s*=\s*true'
        $result | Should Match 'command\s*=\s*"pnpm"'
        $result | Should Match 'C:/Repos/shmindmaster/shwiki'
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
                transport = 'stdio'
                command = 'pnpm'
                args = @('--dir','C:/Repos/shmindmaster/shwiki','mcp:wiki')
                credentialPolicy = 'none'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
        @{ capabilities = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
        '{"$version":4,"model":{"name":"test-model"}}' | Set-Content -LiteralPath $settings -Encoding ASCII -NoNewline

        & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath `
            -Apply -Prune -Validate -RegistryRoot $registryRoot -UserProfile $profile | Out-Host
        $LASTEXITCODE | Should Be 0

        $bytes = [System.IO.File]::ReadAllBytes($settings)
        @($bytes[0..2]) -join ',' | Should Not Be '239,187,191'
        $result = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
        $result.model.name | Should Be 'test-model'
        $result.mcpServers.'shwiki-context'.command | Should Be 'pnpm'
    }
}
