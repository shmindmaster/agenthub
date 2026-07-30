#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:policyPath = Join-Path $repoRoot 'registry\automation-gates.json'
    $script:checkerPath = Join-Path $repoRoot 'scripts\Test-AutomationGatePolicy.ps1'
    $script:ecosystemValidatorPath = Join-Path $repoRoot 'tests\Validate-AgentEcosystem.ps1'
    $script:powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $script:policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json

    function Invoke-AutomationGateChecker {
        param([Parameter(Mandatory)][string]$RegistryRoot)

        $raw = & $script:powerShellExecutable -NoLogo -NoProfile -NonInteractive `
            -File $script:checkerPath -RegistryRoot $RegistryRoot -Json
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Result = $raw | ConvertFrom-Json
        }
    }

    function New-AutomationGatePolicyFixture {
        $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fixtureRegistry = Join-Path $fixtureRoot 'registry'
        New-Item -ItemType Directory -Path $fixtureRegistry -Force | Out-Null
        [pscustomobject]@{
            Root = $fixtureRoot
            PolicyPath = Join-Path $fixtureRegistry 'automation-gates.json'
            Policy = Get-Content -LiteralPath $script:policyPath -Raw -Encoding UTF8 |
                ConvertFrom-Json
        }
    }
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

    It 'validates the current policy as JSON output' {
        $invocation = Invoke-AutomationGateChecker -RegistryRoot $repoRoot
        $invocation.ExitCode | Should -Be 0
        [int]$invocation.Result.summary.fail | Should -Be 0
    }

    It 'uses the repository root when invoked without an explicit path' {
        $raw = & $script:powerShellExecutable -NoLogo -NoProfile -NonInteractive `
            -File $checkerPath -Json
        $LASTEXITCODE | Should -Be 0
        ($raw | ConvertFrom-Json).summary.fail | Should -Be 0
    }

    It 'rejects an accountable external action in automate: <Action>' -TestCases @(
        @{ Action = 'process customer payment' }
        @{ Action = 'provision production credential' }
        @{ Action = 'submit regulatory filing' }
        @{ Action = 'mutate production deployment' }
        @{ Action = 'send binding customer commitment' }
    ) {
        param([string]$Action)

        $fixture = New-AutomationGatePolicyFixture
        $fixture.Policy.portfolio[0].automate += $Action
        $fixture.Policy | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $fixture.PolicyPath -Encoding UTF8

        $invocation = Invoke-AutomationGateChecker -RegistryRoot $fixture.Root

        $invocation.ExitCode | Should -Be 1
        @($invocation.Result.results | Where-Object name -eq 'accountable actions excluded from automate').passed |
            Should -BeFalse
    }

    It 'classifies every currently retained action as non-automatable' {
        $fixture = New-AutomationGatePolicyFixture
        $retainedActions = @(
            foreach ($project in @($fixture.Policy.portfolio)) {
                foreach ($action in @($project.retain)) {
                    $project.automate += [string]$action
                    [string]$action
                }
            }
        )
        $fixture.Policy | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $fixture.PolicyPath -Encoding UTF8

        $invocation = Invoke-AutomationGateChecker -RegistryRoot $fixture.Root
        $classification = @(
            $invocation.Result.results |
                Where-Object name -eq 'accountable actions excluded from automate'
        )

        $invocation.ExitCode | Should -Be 1
        $classification.passed | Should -BeFalse
        foreach ($action in $retainedActions) {
            [string]$classification.detail | Should -Match ([regex]::Escape($action))
        }
    }

    It 'rejects a process-theater wording variant: <Phrase>' -TestCases @(
        @{ Phrase = 'mandatory customer interviews' }
        @{ Phrase = 'two interviews required' }
        @{ Phrase = 'required workshop' }
        @{ Phrase = 'human approval required' }
    ) {
        param([string]$Phrase)

        $fixture = New-AutomationGatePolicyFixture
        $fixture.Policy.guardrails += $Phrase
        $fixture.Policy | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $fixture.PolicyPath -Encoding UTF8

        $invocation = Invoke-AutomationGateChecker -RegistryRoot $fixture.Root

        $invocation.ExitCode | Should -Be 1
        @($invocation.Result.results | Where-Object name -eq 'no process-theater gate').passed |
            Should -BeFalse
    }

    It 'runs the automation checker without relying on a globally resolvable PowerShell command' {
        $gitExecutable = @(Get-Command git -CommandType Application -ErrorAction Stop)[0].Source
        $originalPath = $env:PATH
        try {
            $env:PATH = Split-Path -Parent $gitExecutable
            $raw = & $script:powerShellExecutable -NoLogo -NoProfile -NonInteractive `
                -File $ecosystemValidatorPath -RegistryRoot $repoRoot -Json
            $result = (@($raw) -join [Environment]::NewLine) | ConvertFrom-Json
        } finally {
            $env:PATH = $originalPath
        }

        @($result.results | Where-Object check -eq 'registry:automation-gates').status |
            Should -Be 'PASS'
    }

    It 'is invoked by the repository-wide ecosystem validator' {
        $validatorSource = Get-Content -LiteralPath $ecosystemValidatorPath -Raw -Encoding UTF8
        $validatorSource | Should -Match 'Test-AutomationGatePolicy\.ps1'
        $validatorSource | Should -Match 'registry:automation-gates'
        $validatorSource | Should -Not -Match '&\s+powershell\.exe'
        @([regex]::Matches($validatorSource, '&\s+\$powerShellHostExecutable')).Count |
            Should -Be 2
    }
}
