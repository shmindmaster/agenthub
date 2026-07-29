$global:AgentHubQwenRoot = Split-Path -Parent $PSScriptRoot
$global:AgentHubQwenAgentRoot = Join-Path $global:AgentHubQwenRoot 'adapters\qwen-code\agents'
$global:AgentHubQwenRoleMappings = Get-Content -LiteralPath (Join-Path $global:AgentHubQwenRoot 'registry\role-mappings.json') -Raw | ConvertFrom-Json
$global:AgentHubQwenLspRegistry = Get-Content -LiteralPath (Join-Path $global:AgentHubQwenRoot 'registry\qwen-lsp-projects.json') -Raw | ConvertFrom-Json

Describe 'Qwen native subagents' {
    $expected = @('scout', 'implementer', 'reviewer', 'verifier')

    It 'has a canonical definition for every shared role' {
        foreach ($name in $expected) {
            $path = Join-Path $global:AgentHubQwenAgentRoot "$name.md"
            Test-Path -LiteralPath $path | Should -Be $true
            (Get-Content -LiteralPath $path -Raw) | Should -Match ("(?m)^name:\s*" + [regex]::Escape($name) + "\s*$")
        }
    }

    It 'keeps verifier as a real Qwen agent mapping' {
        $qwen = @($global:AgentHubQwenRoleMappings.hostMappings | Where-Object hostId -eq 'qwen-code')
        $qwen.Count | Should -Be 1
        @($qwen[0].verifier) | Should -Be @('verifier')
    }

    It 'ships a documented TypeScript LSP contract for the requested portfolio' {
        @($global:AgentHubQwenLspRegistry.projects).Count | Should -Be 9
        @($global:AgentHubQwenLspRegistry.projects | Sort-Object -Unique).Count | Should -Be 9
        $template = Join-Path $global:AgentHubQwenRoot ([string]$global:AgentHubQwenLspRegistry.template)
        $lsp = Get-Content -LiteralPath $template -Raw | ConvertFrom-Json
        $lsp.typescript.command | Should -Be 'typescript-language-server'
        @($lsp.typescript.args) | Should -Be @('--stdio')
    }
}
