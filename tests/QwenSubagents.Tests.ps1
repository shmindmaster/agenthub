$root = Split-Path -Parent $PSScriptRoot
$agentRoot = Join-Path $root 'adapters\qwen-code\agents'
$roleMappings = Get-Content -LiteralPath (Join-Path $root 'registry\role-mappings.json') -Raw | ConvertFrom-Json
$lspRegistry = Get-Content -LiteralPath (Join-Path $root 'registry\qwen-lsp-projects.json') -Raw | ConvertFrom-Json

Describe 'Qwen native subagents' {
    $expected = @('scout', 'implementer', 'reviewer', 'verifier')

    It 'has a canonical definition for every shared role' {
        foreach ($name in $expected) {
            $path = Join-Path $agentRoot "$name.md"
            Test-Path -LiteralPath $path | Should Be $true
            (Get-Content -LiteralPath $path -Raw) | Should Match ("(?m)^name:\s*" + [regex]::Escape($name) + "\s*$")
        }
    }

    It 'keeps verifier as a real Qwen agent mapping' {
        $qwen = @($roleMappings.hostMappings | Where-Object hostId -eq 'qwen-code')
        $qwen.Count | Should Be 1
        @($qwen[0].verifier) | Should Be @('verifier')
    }

    It 'ships a documented TypeScript LSP contract for the requested portfolio' {
        @($lspRegistry.projects).Count | Should Be 9
        @($lspRegistry.projects | Sort-Object -Unique).Count | Should Be 9
        $template = Join-Path $root ([string]$lspRegistry.template)
        $lsp = Get-Content -LiteralPath $template -Raw | ConvertFrom-Json
        $lsp.typescript.command | Should Be 'typescript-language-server'
        @($lsp.typescript.args) | Should Be @('--stdio')
    }
}
