$global:AgentHubRepoRoot = Split-Path -Parent $PSScriptRoot
$global:AgentHubValidateScript = Join-Path $PSScriptRoot 'Validate-AgentEcosystem.ps1'
$global:AgentHubReadinessScript = Join-Path $PSScriptRoot 'Test-HostReadiness.ps1'
$global:AgentHubExternalSkillTest = Join-Path $PSScriptRoot 'ExternalSkillOwnership.Tests.ps1'
$global:AgentHubExternalSkillSync = Join-Path $global:AgentHubRepoRoot 'scripts\Sync-ExternalSkills.ps1'
$global:AgentHubAdvertisedPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source

function global:Invoke-AdvertisedCommand {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    & $global:AgentHubAdvertisedPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments | Out-Host
    return $LASTEXITCODE
}

Describe 'Advertised offline validation commands' {
    It 'ships Validate-AgentEcosystem.ps1 at the README path' {
        (Test-Path -LiteralPath $global:AgentHubValidateScript -PathType Leaf) | Should -Be $true
    }

    It 'ships Test-HostReadiness.ps1 at the README path' {
        (Test-Path -LiteralPath $global:AgentHubReadinessScript -PathType Leaf) | Should -Be $true
    }

    It 'ships the external skill ownership reconciler and its behavioral tests' {
        Test-Path -LiteralPath $global:AgentHubExternalSkillSync -PathType Leaf |
            Should -BeTrue
        Test-Path -LiteralPath $global:AgentHubExternalSkillTest -PathType Leaf |
            Should -BeTrue
    }

    It 'validates the checked-in ecosystem without network access' {
        if (-not (Test-Path -LiteralPath $global:AgentHubValidateScript -PathType Leaf)) {
            throw "Missing advertised command: $global:AgentHubValidateScript"
        }

        $exitCode = Invoke-AdvertisedCommand -ScriptPath $global:AgentHubValidateScript -Arguments @('-RegistryRoot', $global:AgentHubRepoRoot)
        $exitCode | Should -Be 0
    }

    It 'defaults validation to the repository containing the script' {
        $output = & $global:AgentHubAdvertisedPowerShell -NoLogo -NoProfile `
            -NonInteractive -ExecutionPolicy Bypass `
            -File $global:AgentHubValidateScript -Json 2>$null
        $output | Should -Not -BeNullOrEmpty
        $parsed = (@($output) -join [Environment]::NewLine) | ConvertFrom-Json

        @($parsed.results | Where-Object check -eq 'registry:mcp-lifecycle').Count |
            Should -Be 1
    }

    It 'reports local host readiness without treating optional missing clients as failure' {
        if (-not (Test-Path -LiteralPath $global:AgentHubReadinessScript -PathType Leaf)) {
            throw "Missing advertised command: $global:AgentHubReadinessScript"
        }

        $exitCode = Invoke-AdvertisedCommand -ScriptPath $global:AgentHubReadinessScript -Arguments @('-RegistryRoot', $global:AgentHubRepoRoot)
        # A missing user-managed policy pointer is reported as a nonzero
        # readiness status; the command must still complete and report it.
        $exitCode | Should -BeIn @(0, 1)
    }
}
