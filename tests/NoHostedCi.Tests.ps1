#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:workflowsRoot = Join-Path $script:repoRoot '.github\workflows'
    $script:readme = Get-Content -LiteralPath `
        (Join-Path $script:repoRoot 'README.md') -Raw -Encoding UTF8
}

Describe 'AgentHub local-only validation policy' {
    It 'keeps a single self-hosted validation workflow definition' {
        $workflowDefinitions = @(
            Get-ChildItem -LiteralPath $script:workflowsRoot -File `
                -ErrorAction SilentlyContinue |
                Where-Object Extension -in @('.yml', '.yaml')
        )
        $workflowDefinitions.Count | Should -Be 1
        $workflowDefinitions[0].Name | Should -Be 'validate.yml'

        $workflowText = Get-Content -LiteralPath (Join-Path $script:workflowsRoot 'validate.yml') -Raw -Encoding UTF8
        $workflowText | Should -Match 'runs-on:\s*\[?\s*self-hosted'
    }

    It 'declares validation runs on a self-hosted runner' {
        $script:readme | Should -Match (
            '(?s)## Validation policy.*' +
            'does not produce a build, package, release, or deployment artifact'
        )
        $script:readme | Should -Match (
            '(?s)## Validation policy.*' +
            'GitHub Actions runs on .*self-hosted runner on DigitalOcean'
        )
    }

    It 'keeps both local PowerShell validation commands documented' {
        $script:readme | Should -Match (
            [regex]::Escape(
                "pwsh -NoProfile -File .\tests\Validate-AgentEcosystem.ps1"
            )
        )
        $script:readme | Should -Match (
            [regex]::Escape(
                "powershell.exe -NoProfile -File .\tests\Validate-AgentEcosystem.ps1"
            )
        )
    }
}
