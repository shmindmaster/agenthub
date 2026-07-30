#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:syncScript = Join-Path $script:repoRoot 'scripts\Sync-ExternalSkills.ps1'
    $script:powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
    . (Join-Path $script:repoRoot 'scripts\RegistryContentHash.ps1')

    function global:Write-ExternalSkillTree {
        param(
            [string]$Path,
            [string]$Version,
            [string]$Body
        )
        New-Item -ItemType Directory -Path (Join-Path $Path 'references') -Force |
            Out-Null
        @"
---
name: use-railway
version: $Version
---
$Body
"@ | Set-Content -LiteralPath (Join-Path $Path 'SKILL.md') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $Path 'references\iac.md') `
            -Value "iac:$Version" -Encoding UTF8
    }

    function global:Write-ExternalRegistryFixture {
        param(
            [string]$RegistryRoot,
            [string]$CurrentHash,
            [string]$PreviousHash,
            [object[]]$Targets,
            [string[]]$SourceCandidates,
            [string[]]$SharedShadows = @()
        )
        $registryDir = Join-Path $RegistryRoot 'registry'
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
        [ordered]@{
            schemaVersion = 1
            externalOwners = @([ordered]@{
                skillId = 'use-railway'
                owner = 'railway'
                ownershipType = 'vendor-installed-local-skill'
                currentVersion = 'fixture-current'
                skillHash = ('A' * 64)
                treeHash = $CurrentHash
                previousTreeHashes = @($PreviousHash)
                sourceCandidates = $SourceCandidates
                targets = $Targets
                sharedShadowPaths = $SharedShadows
            })
            preservePendingEvidence = @()
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $registryDir 'skill-ownership.json') `
                -Encoding UTF8
    }

    function global:Invoke-ExternalSyncFixture {
        param(
            [string]$RegistryRoot,
            [string]$Profile,
            [string]$Report,
            [switch]$Apply
        )
        $arguments = @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $script:syncScript,
            '-RegistryRoot', $RegistryRoot,
            '-UserProfilePath', $Profile,
            '-AppDataPath', (Join-Path $Profile 'AppData\Roaming'),
            '-ReportPath', $Report,
            '-Json'
        )
        if ($Apply) { $arguments += '-Apply' }
        $output = @(& $script:powerShell @arguments 2>&1)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
            Report = if (Test-Path -LiteralPath $Report) {
                Get-Content -LiteralPath $Report -Raw -Encoding UTF8 |
                    ConvertFrom-Json
            } else { $null }
        }
    }
}

Describe 'External skill ownership reconciliation' {
    It 'reports an outdated external skill without mutating in report mode' {
        $profile = Join-Path $TestDrive 'report-profile'
        $registryRoot = Join-Path $TestDrive 'report-agenthub'
        $source = Join-Path $profile '.claude\skills\use-railway'
        $target = Join-Path $profile '.codex\skills\use-railway'
        Write-ExternalSkillTree -Path $source -Version 'current' -Body 'current'
        Write-ExternalSkillTree -Path $target -Version 'previous' -Body 'previous'
        $currentHash = Get-AgentHubRegistryHashBasisValue -Path $source
        $previousHash = Get-AgentHubRegistryHashBasisValue -Path $target
        Write-ExternalRegistryFixture `
            -RegistryRoot $registryRoot `
            -CurrentHash $currentHash `
            -PreviousHash $previousHash `
            -SourceCandidates @('${USERPROFILE}/.claude/skills/use-railway') `
            -Targets @(@{
                hostId='codex'
                path='${USERPROFILE}/.codex/skills/use-railway'
            })
        $beforeHash = Get-AgentHubRegistryHashBasisValue -Path $target
        $result = Invoke-ExternalSyncFixture `
            -RegistryRoot $registryRoot `
            -Profile $profile `
            -Report (Join-Path $TestDrive 'report.json')

        $result.ExitCode | Should -Be 0 -Because (
            @($result.Output) -join [Environment]::NewLine
        )
        $result.Report.mode | Should -Be 'report'
        $result.Report.owners[0].targets[0].state | Should -Be 'outdated-known'
        (Get-AgentHubRegistryHashBasisValue -Path $target) | Should -Be $beforeHash
        Test-Path -LiteralPath (Join-Path $profile '.agenthub\quarantine') |
            Should -BeFalse
    }

    It 'replaces outdated targets and retires a shared shadow only after all targets verify' {
        $profile = Join-Path $TestDrive 'apply-profile'
        $registryRoot = Join-Path $TestDrive 'apply-agenthub'
        $source = Join-Path $profile '.claude\skills\use-railway'
        $codexTarget = Join-Path $profile '.codex\skills\use-railway'
        $devinTarget = Join-Path $profile 'AppData\Roaming\devin\skills\use-railway'
        $shadow = Join-Path $profile '.agents\skills\use-railway'
        Write-ExternalSkillTree -Path $source -Version 'current' -Body 'current'
        Write-ExternalSkillTree -Path $codexTarget -Version 'previous' -Body 'previous'
        Copy-Item -LiteralPath $source -Destination (
            New-Item -ItemType Directory -Path (Split-Path -Parent $shadow) -Force
        ).FullName -Recurse
        $currentHash = Get-AgentHubRegistryHashBasisValue -Path $source
        $previousHash = Get-AgentHubRegistryHashBasisValue -Path $codexTarget
        Write-ExternalRegistryFixture `
            -RegistryRoot $registryRoot `
            -CurrentHash $currentHash `
            -PreviousHash $previousHash `
            -SourceCandidates @('${USERPROFILE}/.claude/skills/use-railway') `
            -Targets @(
                @{ hostId='codex'; path='${USERPROFILE}/.codex/skills/use-railway' },
                @{ hostId='devin'; path='${APPDATA}/devin/skills/use-railway' }
            ) `
            -SharedShadows @('${USERPROFILE}/.agents/skills/use-railway')
        $result = Invoke-ExternalSyncFixture `
            -RegistryRoot $registryRoot `
            -Profile $profile `
            -Report (Join-Path $TestDrive 'apply.json') `
            -Apply

        $result.ExitCode | Should -Be 0 -Because (
            @($result.Output) -join [Environment]::NewLine
        )
        (Get-AgentHubRegistryHashBasisValue -Path $codexTarget) |
            Should -Be $currentHash
        (Get-AgentHubRegistryHashBasisValue -Path $devinTarget) |
            Should -Be $currentHash
        Test-Path -LiteralPath $shadow | Should -BeFalse
        Test-Path -LiteralPath $result.Report.quarantineManifest -PathType Leaf |
            Should -BeTrue
        $manifest = Get-Content -LiteralPath $result.Report.quarantineManifest -Raw |
            ConvertFrom-Json
        @($manifest.entries.artifactName | Where-Object { $_ -eq 'use-railway' }).Count |
            Should -Be 2
    }

    It 'fails closed when no source candidate matches the trusted hash' {
        $profile = Join-Path $TestDrive 'blocked-profile'
        $registryRoot = Join-Path $TestDrive 'blocked-agenthub'
        $source = Join-Path $profile '.claude\skills\use-railway'
        $target = Join-Path $profile '.codex\skills\use-railway'
        $shadow = Join-Path $profile '.agents\skills\use-railway'
        Write-ExternalSkillTree -Path $source -Version 'unknown' -Body 'unknown'
        Write-ExternalSkillTree -Path $target -Version 'previous' -Body 'previous'
        Write-ExternalSkillTree -Path $shadow -Version 'current' -Body 'current'
        $trustedSource = Join-Path $TestDrive 'trusted-source'
        Write-ExternalSkillTree -Path $trustedSource -Version 'trusted' -Body 'trusted'
        $trustedHash = Get-AgentHubRegistryHashBasisValue -Path $trustedSource
        $previousHash = Get-AgentHubRegistryHashBasisValue -Path $target
        $targetBefore = $previousHash
        $shadowBefore = Get-AgentHubRegistryHashBasisValue -Path $shadow
        Write-ExternalRegistryFixture `
            -RegistryRoot $registryRoot `
            -CurrentHash $trustedHash `
            -PreviousHash $previousHash `
            -SourceCandidates @('${USERPROFILE}/.claude/skills/use-railway') `
            -Targets @(@{
                hostId='codex'
                path='${USERPROFILE}/.codex/skills/use-railway'
            }) `
            -SharedShadows @('${USERPROFILE}/.agents/skills/use-railway')
        $result = Invoke-ExternalSyncFixture `
            -RegistryRoot $registryRoot `
            -Profile $profile `
            -Report (Join-Path $TestDrive 'blocked.json') `
            -Apply

        $result.ExitCode | Should -Be 1
        $result.Report.owners[0].status | Should -Be 'blocked'
        (Get-AgentHubRegistryHashBasisValue -Path $target) | Should -Be $targetBefore
        (Get-AgentHubRegistryHashBasisValue -Path $shadow) | Should -Be $shadowBefore
        Test-Path -LiteralPath (Join-Path $profile '.agenthub\quarantine') |
            Should -BeFalse
    }
}
