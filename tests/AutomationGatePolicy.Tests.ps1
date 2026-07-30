#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:policyPath = Join-Path $repoRoot 'registry\automation-gates.json'
    $script:checkerPath = Join-Path $repoRoot 'scripts\Test-AutomationGatePolicy.ps1'
    $script:ecosystemValidatorPath = Join-Path $repoRoot 'tests\Validate-AgentEcosystem.ps1'
    $script:policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe 'Automation-first gate policy' {
    It 'covers every portfolio repository with a valid decision class' {
        @($policy.portfolio.id | Sort-Object) | Should -Be @(
            'abacare', 'agenthub', 'coledger', 'crewscore', 'gentlenext', 'lawli',
            'lexalign', 'repocontext', 'sabhi', 'subops', 'verigence', 'warrantygains'
        )
        foreach ($project in @($policy.portfolio)) {
            [string]$project.defaultDecisionClass | Should -BeIn @(
                'machine', 'automated_evidence', 'accountable_external_action', 'fail_closed_exception'
            )
            @($project.automate).Count | Should -BeGreaterThan 0
            @($project.retain).Count | Should -BeGreaterThan 0
        }
    }

    It 'rejects legacy discretionary process gates and validates as JSON output' {
        $raw = & powershell.exe -NoLogo -NoProfile -NonInteractive -File $checkerPath -RegistryRoot $repoRoot -Json
        $LASTEXITCODE | Should -Be 0
        $result = $raw | ConvertFrom-Json
        [int]$result.summary.fail | Should -Be 0
        (($policy | ConvertTo-Json -Depth 20) -match '(?i)await human review|mandatory interview|mandatory workshop|discretionary approval count') |
            Should -BeFalse
    }

    It 'uses the repository root when invoked without an explicit path' {
        $raw = & powershell.exe -NoLogo -NoProfile -NonInteractive -File $checkerPath -Json
        $LASTEXITCODE | Should -Be 0
        ($raw | ConvertFrom-Json).summary.fail | Should -Be 0
    }

    It 'is invoked by the repository-wide ecosystem validator' {
        $validatorSource = Get-Content -LiteralPath $ecosystemValidatorPath -Raw -Encoding UTF8
        $validatorSource | Should -Match 'Test-AutomationGatePolicy\.ps1'
        $validatorSource | Should -Match 'registry:automation-gates'
    }
}
