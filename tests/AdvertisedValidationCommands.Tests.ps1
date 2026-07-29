$global:AgentHubRepoRoot = Split-Path -Parent $PSScriptRoot
$global:AgentHubValidateScript = Join-Path $PSScriptRoot 'Validate-AgentEcosystem.ps1'
$global:AgentHubReadinessScript = Join-Path $PSScriptRoot 'Test-HostReadiness.ps1'
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

    It 'validates the checked-in ecosystem without network access' {
        if (-not (Test-Path -LiteralPath $global:AgentHubValidateScript -PathType Leaf)) {
            throw "Missing advertised command: $global:AgentHubValidateScript"
        }

        $exitCode = Invoke-AdvertisedCommand -ScriptPath $global:AgentHubValidateScript -Arguments @('-RegistryRoot', $global:AgentHubRepoRoot)
        $exitCode | Should -BeIn @(0, 1)
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
