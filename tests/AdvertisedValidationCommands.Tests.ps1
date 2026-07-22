$repoRoot = Split-Path -Parent $PSScriptRoot
$validateScript = Join-Path $PSScriptRoot 'Validate-AgentEcosystem.ps1'
$readinessScript = Join-Path $PSScriptRoot 'Test-HostReadiness.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

function Invoke-AdvertisedCommand {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    & $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments | Out-Host
    return $LASTEXITCODE
}

Describe 'Advertised offline validation commands' {
    It 'ships Validate-AgentEcosystem.ps1 at the README path' {
        (Test-Path -LiteralPath $validateScript -PathType Leaf) | Should Be $true
    }

    It 'ships Test-HostReadiness.ps1 at the README path' {
        (Test-Path -LiteralPath $readinessScript -PathType Leaf) | Should Be $true
    }

    It 'validates the checked-in ecosystem and global worktree pointers without network access' {
        if (-not (Test-Path -LiteralPath $validateScript -PathType Leaf)) {
            throw "Missing advertised command: $validateScript"
        }

        $exitCode = Invoke-AdvertisedCommand -ScriptPath $validateScript -Arguments @('-RegistryRoot', $repoRoot, '-IncludeGlobalInstructions')
        $exitCode | Should Be 0
    }

    It 'reports local host readiness without treating optional missing clients as failure' {
        if (-not (Test-Path -LiteralPath $readinessScript -PathType Leaf)) {
            throw "Missing advertised command: $readinessScript"
        }

        $exitCode = Invoke-AdvertisedCommand -ScriptPath $readinessScript -Arguments @('-RegistryRoot', $repoRoot)
        $exitCode | Should Be 0
    }
}
