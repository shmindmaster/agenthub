#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:checker = Join-Path $repoRoot 'scripts\Test-LiveAgentFleetDrift.ps1'
    . (Join-Path $repoRoot 'scripts\RegistryContentHash.ps1')
    $script:powerShell = if ($PSVersionTable.PSVersion.Major -lt 6) {
        (Get-Command powershell.exe -ErrorAction Stop).Source
    } else {
        (Get-Command pwsh -ErrorAction Stop).Source
    }

    function Write-FixtureJson {
        param(
            [string]$Path,
            [object]$Value
        )
        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText(
            $Path,
            ($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )
    }

    function Write-FixtureSkill {
        param(
            [string]$Path,
            [string]$Name,
            [string]$Body
        )
        $parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        [System.IO.File]::WriteAllText(
            $Path,
            "---`nname: $Name`n---`n`n$Body`n",
            [System.Text.UTF8Encoding]::new($false)
        )
    }
}

Describe 'Comprehensive live fleet drift inventory' {
    It 'detects retired skills, active collisions, and broken required plugin sources' {
        $fixtureRoot = Join-Path $TestDrive 'fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $qoderSkills = Join-Path $profile '.qoder\skills'
        $qoderSettings = Join-Path $profile '.qoder\settings.json'
        $qoderPluginRoot = Join-Path $profile '.qoder\plugins\cache\local\fixture-plugin\1.0.0'
        $claudeSkills = Join-Path $profile '.claude\skills'
        $devinSkills = Join-Path $appData 'devin\skills'
        $devinPlugins = Join-Path $appData 'devin\cli\plugins'
        $canonicalRoot = Join-Path $registryRoot 'capabilities\fixture'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureSkill -Path (Join-Path $canonicalRoot 'skills\fixture-skill\SKILL.md') `
            -Name 'fixture-skill' -Body 'canonical body'
        Write-FixtureSkill -Path (Join-Path $qoderSkills 'fixture-skill\SKILL.md') `
            -Name 'fixture-skill' -Body 'canonical body'
        Write-FixtureSkill -Path (Join-Path $qoderPluginRoot 'skills\fixture-skill\SKILL.md') `
            -Name 'fixture-skill' -Body 'plugin drift'
        Write-FixtureSkill -Path (Join-Path $claudeSkills 'agent-fleet-ops\SKILL.md') `
            -Name 'agent-fleet-ops' -Body 'retired'
        New-Item -ItemType Directory -Path $devinSkills, $devinPlugins -Force | Out-Null

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents = @(
                @{
                    id='qoder'; name='Qoder'; version='fixture'; executable=$executable
                    status='active'
                    nativePaths=@{
                        settings=$qoderSettings
                        skillsDir=$qoderSkills
                        pluginsDir=(Join-Path $profile '.qoder\plugins')
                    }
                },
                @{
                    id='claude'; name='Claude'; version='fixture'; executable=$executable
                    status='active'
                    nativePaths=@{ skillsDir=$claudeSkills }
                },
                @{
                    id='devin'; name='Devin'; version='fixture'; executable=$executable
                    status='inactive'
                    nativePaths=@{
                        config=(Join-Path $appData 'devin\config.json')
                        skillsDir=$devinSkills
                        pluginsDir=$devinPlugins
                    }
                }
            )
            inactiveAgents = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{
            capabilities = @(
                @{
                    id='fixture-capability'
                    canonicalSource=$canonicalRoot
                    hostMappings=@(@{ hostId='qoder'; deploymentStatus='fixture' })
                }
            )
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{
            mcpServers = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy = @{ onDemandLocalMcpIds=@() }
            hosts = @(
                @{
                    hostId='qoder'
                    exposures=@{
                        'plugin-owned'=@()
                        'native-connector'=@()
                        'shared-gateway'=@()
                        'local-only'=@()
                    }
                },
                @{
                    hostId='claude'
                    exposures=@{
                        'plugin-owned'=@()
                        'native-connector'=@()
                        'shared-gateway'=@()
                        'local-only'=@()
                    }
                },
                @{
                    hostId='devin'
                    exposures=@{
                        'plugin-owned'=@()
                        'native-connector'=@()
                        'shared-gateway'=@()
                        'local-only'=@()
                    }
                }
            )
        }
        Write-FixtureJson -Path $qoderSettings -Value @{
            enabledPlugins = @{ 'fixture-plugin@local'=$true }
            mcpServers = @{}
        }
        Write-FixtureJson -Path (Join-Path $profile '.claude.json') -Value @{
            mcpServers = @{}
        }
        Write-FixtureJson -Path (Join-Path $appData 'devin\config.json') -Value @{
            mcpServers = @{}
        }
        $missingPluginSource = Join-Path $fixtureRoot 'deleted-plugin-source'
        Write-FixtureJson -Path (Join-Path $devinPlugins 'lock.json') -Value @{
            requirements = @(
                @{
                    spec=@{ source='local'; path=$missingPluginSource }
                    origin=@{ scope='user' }
                    required=$true
                }
            )
            resolved=@()
            edges=@()
        }

        $report = Join-Path $fixtureRoot 'report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)

        $LASTEXITCODE | Should -Be 1
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        Test-Path -LiteralPath $report -PathType Leaf | Should -BeTrue
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        [int]$parsed.summary.fail | Should -BeGreaterThan 0
        @($parsed.results.check) | Should -Contain 'retired-skill:agent-fleet-ops'
        @($parsed.results.check) | Should -Contain 'duplicate-skill-exposure:qoder:fixture-skill'
        @($parsed.results.check) | Should -Contain `
            'canonical-skill-content-drift:qoder:fixture-skill'
        @($parsed.results.check) | Should -Contain `
            'required-plugin-source-missing:devin:deleted-plugin-source'
    }

    It 'treats mapped canonical portfolio copies as owned and flags only divergent mapped content' {
        $repositoryRegistry = Get-Content -LiteralPath (
            Join-Path $repoRoot 'registry\capabilities.json'
        ) -Raw | ConvertFrom-Json
        @($repositoryRegistry.capabilities | Where-Object {
            $_.id -eq 'portfolio-engineering-ops'
        }).Count | Should -Be 1

        $fixtureRoot = Join-Path $TestDrive 'portfolio-ownership-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $canonicalRoot = Join-Path $registryRoot 'capabilities\portfolio-engineering-ops'
        $canonicalSkill = Join-Path $canonicalRoot 'skills\docs-drift\SKILL.md'
        $claudeSkill = Join-Path $profile '.claude\skills\docs-drift\SKILL.md'
        $codexSkill = Join-Path $profile '.codex\skills\docs-drift\SKILL.md'
        $qoderSkill = Join-Path $profile '.qoder\skills\docs-drift\SKILL.md'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureSkill -Path $canonicalSkill -Name 'docs-drift' -Body 'canonical body'
        $canonicalHash = Get-AgentHubRegistryHashBasisValue -Path (
            Split-Path -Parent $canonicalSkill
        )
        foreach ($mappedSkill in @($claudeSkill, $codexSkill, $qoderSkill)) {
            Copy-Item -LiteralPath $canonicalSkill -Destination (
                New-Item -ItemType Directory -Path (Split-Path -Parent $mappedSkill) -Force
            ).FullName
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($mappedSkill)) |
                Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($canonicalSkill)))
        }

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents = @(
                @{
                    id='claude'; name='Claude'; version='fixture'; executable=$executable
                    status='active'; nativePaths=@{ skillsDir=(Split-Path -Parent (Split-Path -Parent $claudeSkill)) }
                },
                @{
                    id='codex'; name='Codex'; version='fixture'; executable=$executable
                    status='active'; nativePaths=@{ skillsDir=(Split-Path -Parent (Split-Path -Parent $codexSkill)) }
                },
                @{
                    id='qoder'; name='Qoder'; version='fixture'; executable=$executable
                    status='active'; nativePaths=@{ skillsDir=(Split-Path -Parent (Split-Path -Parent $qoderSkill)) }
                }
            )
            inactiveAgents = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{
            capabilities = @(
                @{
                    id='portfolio-engineering-ops'
                    canonicalSource=$canonicalRoot
                    managedSkillNames=@('docs-drift')
                    hostMappings=@(
                        @{ hostId='claude'; deploymentStatus='managed-loose-skills' },
                        @{ hostId='codex'; deploymentStatus='managed-loose-skills' },
                        @{ hostId='qoder'; deploymentStatus='managed-loose-skills' }
                    )
                }
            )
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{ mcpServers=@() }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy=@{ onDemandLocalMcpIds=@() }
            hosts=@(
                @{ hostId='claude'; exposures=@{ 'plugin-owned'=@(); 'native-connector'=@(); 'shared-gateway'=@(); 'local-only'=@() } },
                @{ hostId='codex'; exposures=@{ 'plugin-owned'=@(); 'native-connector'=@(); 'shared-gateway'=@(); 'local-only'=@() } },
                @{ hostId='qoder'; exposures=@{ 'plugin-owned'=@(); 'native-connector'=@(); 'shared-gateway'=@(); 'local-only'=@() } }
            )
        }
        Write-FixtureJson -Path (Join-Path $profile '.claude.json') -Value @{ mcpServers=@{} }
        $codexConfig = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $codexConfig) -Force | Out-Null
        Set-Content -LiteralPath $codexConfig -Value '' -Encoding UTF8
        Write-FixtureJson -Path (Join-Path $profile '.qoder\settings.json') -Value @{
            enabledPlugins=@{ '_fixture-disabled@local'=$false }
            mcpServers=@{}
        }

        $report = Join-Path $fixtureRoot 'baseline-report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)

        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        @($parsed.inventory.skills | Where-Object {
            $_.hostId -in @('claude','codex','qoder') -and
            $_.skillId -eq 'docs-drift' -and
            $_.hash -eq $canonicalHash
        }).Count | Should -Be 3
        @($parsed.results.check | Where-Object {
            $_ -like 'unowned-*:docs-drift'
        }).Count | Should -Be 0
        @($parsed.results.check) | Should -Not -Contain 'canonical-skill-content-drift:claude:docs-drift'
        @($parsed.results.check) | Should -Not -Contain 'canonical-skill-content-drift:codex:docs-drift'
        @($parsed.results.check) | Should -Not -Contain 'canonical-skill-content-drift:qoder:docs-drift'

        Write-FixtureSkill -Path $qoderSkill -Name 'docs-drift' -Body 'mutated body'
        $mutatedReport = Join-Path $fixtureRoot 'mutated-report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $mutatedReport `
            -Json 2>&1)

        $LASTEXITCODE | Should -Be 1
        if (-not (Test-Path -LiteralPath $mutatedReport -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $mutated = Get-Content -LiteralPath $mutatedReport -Raw -Encoding UTF8 | ConvertFrom-Json
        @($mutated.results.check) | Should -Contain 'canonical-skill-content-drift:qoder:docs-drift'
        @($mutated.results.check) | Should -Not -Contain 'canonical-skill-content-drift:claude:docs-drift'
        @($mutated.results.check) | Should -Not -Contain 'canonical-skill-content-drift:codex:docs-drift'
    }

    It 'owns both Framer skill IDs atomically and detects missing companion resources' {
        $fixtureRoot = Join-Path $TestDrive 'framer-tree-drift-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $canonicalRoot = Join-Path $registryRoot 'capabilities\framer'
        $canonicalFramer = Join-Path $canonicalRoot 'skills\framer'
        $canonicalComponents = Join-Path $canonicalRoot 'skills\framer-code-components'
        $qoderSkillsRoot = Join-Path $profile '.qoder\skills'
        $qoderFramer = Join-Path $qoderSkillsRoot 'framer'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureSkill -Path (Join-Path $canonicalFramer 'SKILL.md') `
            -Name 'framer' -Body 'canonical Framer body'
        New-Item -ItemType Directory -Path (
            Join-Path $canonicalFramer 'projects\__template__'
        ) -Force | Out-Null
        Set-Content -LiteralPath (
            Join-Path $canonicalFramer 'projects\__template__\recipes.md'
        ) -Value 'canonical recipes' -Encoding UTF8
        Write-FixtureSkill -Path (Join-Path $canonicalComponents 'SKILL.md') `
            -Name 'framer-code-components' -Body 'canonical component body'
        New-Item -ItemType Directory -Path $qoderSkillsRoot -Force | Out-Null
        Copy-Item -LiteralPath $canonicalFramer -Destination $qoderSkillsRoot -Recurse
        Copy-Item -LiteralPath $canonicalComponents -Destination $qoderSkillsRoot -Recurse

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents = @(@{
                id='qoder'; name='Qoder'; version='fixture'; executable=$executable
                status='active'; nativePaths=@{ skillsDir=$qoderSkillsRoot }
            })
            inactiveAgents = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{
            capabilities = @(@{
                id='framer'
                canonicalSource=$canonicalRoot
                managedSkillNames=@('framer','framer-code-components')
                hostMappings=@(
                    @{ hostId='qoder'; deploymentStatus='managed-loose-skills' }
                )
            })
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{
            mcpServers=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy=@{ onDemandLocalMcpIds=@() }
            hosts=@(@{
                hostId='qoder'
                exposures=@{
                    'plugin-owned'=@(); 'native-connector'=@()
                    'shared-gateway'=@(); 'local-only'=@()
                }
            })
        }
        Write-FixtureJson -Path (Join-Path $profile '.qoder\settings.json') -Value @{
            enabledPlugins=@{ '_fixture-disabled@local'=$false }
            mcpServers=@{}
        }

        $baselineReport = Join-Path $fixtureRoot 'baseline-report.json'
        & $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $baselineReport `
            -Json 2>&1 | Out-Null
        $baseline = Get-Content -LiteralPath $baselineReport -Raw -Encoding UTF8 |
            ConvertFrom-Json
        @($baseline.inventory.canonicalSkills | Where-Object {
            $_.capabilityId -eq 'framer' -and
            $_.skillId -in @('framer','framer-code-components')
        }).Count | Should -Be 2
        @($baseline.results.check) |
            Should -Not -Contain 'canonical-skill-content-drift:qoder:framer'
        @($baseline.results.check) |
            Should -Not -Contain 'canonical-skill-content-drift:qoder:framer-code-components'

        Remove-Item -LiteralPath (
            Join-Path $qoderFramer 'projects\__template__\recipes.md'
        )
        $mutatedReport = Join-Path $fixtureRoot 'mutated-report.json'
        & $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $mutatedReport `
            -Json 2>&1 | Out-Null
        $mutated = Get-Content -LiteralPath $mutatedReport -Raw -Encoding UTF8 |
            ConvertFrom-Json
        @($mutated.results.check) |
            Should -Contain 'canonical-skill-content-drift:qoder:framer'
        @($mutated.results.check) |
            Should -Not -Contain 'canonical-skill-content-drift:qoder:framer-code-components'
    }

    It 'classifies vendor-owned and preserve-pending skills without treating them as unowned' {
        $fixtureRoot = Join-Path $TestDrive 'external-skill-drift-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $codexSkills = Join-Path $profile '.codex\skills'
        $claudeSkills = Join-Path $profile '.claude\skills'
        $sharedSkills = Join-Path $profile '.agents\skills'
        $railwayTarget = Join-Path $codexSkills 'use-railway\SKILL.md'
        $railwayShadow = Join-Path $sharedSkills 'use-railway\SKILL.md'
        $codexPending = Join-Path $codexSkills 'issue-to-pr\SKILL.md'
        $claudePending = Join-Path $claudeSkills 'issue-to-pr\SKILL.md'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureSkill -Path $railwayTarget -Name 'use-railway' -Body 'trusted vendor tree'
        Copy-Item -LiteralPath $railwayTarget -Destination (
            New-Item -ItemType Directory -Path (Split-Path -Parent $railwayShadow) -Force
        ).FullName
        Write-FixtureSkill -Path $codexPending -Name 'issue-to-pr' -Body 'preserved evidence'
        Write-FixtureSkill -Path $claudePending -Name 'issue-to-pr' -Body 'unknown divergence'
        $railwayHash = Get-AgentHubRegistryHashBasisValue -Path (
            Split-Path -Parent $railwayTarget
        )
        $pendingHash = Get-AgentHubRegistryHashBasisValue -Path (
            Split-Path -Parent $codexPending
        )

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents=@(
                @{
                    id='codex'; name='Codex'; version='fixture'; executable=$executable
                    status='active'
                    nativePaths=@{ skillsDir=$codexSkills; sharedSkillsDir=$sharedSkills }
                },
                @{
                    id='claude'; name='Claude'; version='fixture'; executable=$executable
                    status='active'; nativePaths=@{ skillsDir=$claudeSkills }
                },
                @{
                    id='gemini'; name='Gemini'; version='fixture'; executable=$executable
                    status='inactive'; nativePaths=@{ sharedSkillsDir=$sharedSkills }
                },
                @{
                    id='cline'; name='Cline'; version='fixture'; executable=$executable
                    status='inactive'; nativePaths=@{ sharedSkillsDir=$sharedSkills }
                }
            )
            inactiveAgents=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{
            capabilities=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{
            mcpServers=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy=@{ onDemandLocalMcpIds=@() }
            hosts=@(
                @{ hostId='codex'; exposures=@{ 'plugin-owned'=@(); 'native-connector'=@(); 'shared-gateway'=@(); 'local-only'=@() } },
                @{ hostId='claude'; exposures=@{ 'plugin-owned'=@(); 'native-connector'=@(); 'shared-gateway'=@(); 'local-only'=@() } }
            )
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'skill-ownership.json') -Value @{
            schemaVersion=1
            externalOwners=@(@{
                skillId='use-railway'; owner='railway'; currentVersion='fixture'
                treeHash=$railwayHash
                targets=@(@{
                    hostId='codex'
                    path='${USERPROFILE}/.codex/skills/use-railway'
                })
            })
            preservePendingEvidence=@(@{
                skillId='issue-to-pr'
                observedHashes=@($pendingHash)
                blockerReason='fixture ownership is unresolved'
                status='preserve-pending-evidence'
            })
        }
        Write-FixtureJson -Path (Join-Path $profile '.claude.json') -Value @{
            mcpServers=@{}
        }
        $codexConfig = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $codexConfig) -Force |
            Out-Null
        Set-Content -LiteralPath $codexConfig -Value '' -Encoding UTF8

        $report = Join-Path $fixtureRoot 'report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 |
            ConvertFrom-Json
        @($parsed.results | Where-Object {
            $_.check -eq 'external-skill-current:codex:use-railway' -and
            $_.status -eq 'PASS'
        }).Count | Should -Be 1
        @($parsed.results | Where-Object {
            $_.check -eq 'preserve-pending-evidence:codex:issue-to-pr' -and
            $_.status -eq 'WARN'
        }).Count | Should -Be 1
        $divergentPending = @($parsed.results | Where-Object {
            $_.check -eq 'preserve-pending-evidence:claude:issue-to-pr'
        })
        $divergentPending.status | Should -Be 'FAIL'
        $divergentPending.detail | Should -Match 'preserve-pending-evidence'
        @($parsed.results.check) |
            Should -Contain 'duplicate-skill-exposure:codex:use-railway'
        @($parsed.results.check | Where-Object {
            $_ -like 'unowned-*:use-railway' -or $_ -like 'unowned-*:issue-to-pr'
        }).Count | Should -Be 0

        Write-FixtureSkill -Path $railwayTarget -Name 'use-railway' -Body 'known old tree'
        $mutatedReport = Join-Path $fixtureRoot 'mutated-report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $mutatedReport `
            -Json 2>&1)
        if (-not (Test-Path -LiteralPath $mutatedReport -PathType Leaf)) {
            throw "Checker did not produce its mutated report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $mutated = Get-Content -LiteralPath $mutatedReport -Raw -Encoding UTF8 |
            ConvertFrom-Json
        @($mutated.results.check) |
            Should -Contain 'external-skill-content-drift:codex:use-railway'
    }

    It 'uses Copilot manifest-selected skill bodies instead of nested build inputs' {
        $fixtureRoot = Join-Path $TestDrive 'copilot-manifest-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $pluginRoot = Join-Path $profile '.copilot\installed-plugins\_direct\fixture-plugin'
        $missingManifestPluginRoot = Join-Path $profile `
            '.copilot\installed-plugins\_direct\missing-manifest-plugin'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureSkill -Path (Join-Path $pluginRoot 'skills\fixture-skill\SKILL.md') `
            -Name 'fixture-skill' -Body 'manifest-selected output'
        Write-FixtureSkill -Path (Join-Path $pluginRoot 'skills\fixture-skill\upstream\SKILL.md') `
            -Name 'fixture-skill' -Body 'non-runtime build input'
        Write-FixtureJson -Path (Join-Path $pluginRoot 'generated\skill-manifest.json') -Value @{
            skills = @{
                'fixture-skill' = @{ bodyPath = 'skills/fixture-skill/SKILL.md' }
            }
        }
        Write-FixtureSkill -Path (Join-Path $missingManifestPluginRoot `
            'skills\missing-fixture-skill\SKILL.md') `
            -Name 'missing-fixture-skill' -Body 'unselected output'
        Write-FixtureSkill -Path (Join-Path $missingManifestPluginRoot `
            'skills\missing-fixture-skill\upstream\SKILL.md') `
            -Name 'missing-fixture-skill' -Body 'non-runtime build input'
        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents = @(
                @{
                    id='copilot'; name='Copilot'; version='fixture'; executable=$executable
                    status='active'
                    nativePaths=@{ pluginsDir=(Join-Path $profile '.copilot\installed-plugins') }
                }
            )
            inactiveAgents = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{ capabilities = @() }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{ mcpServers = @() }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy = @{ onDemandLocalMcpIds=@() }
            hosts = @(@{
                hostId='copilot'
                exposures=@{
                    'plugin-owned'=@()
                    'native-connector'=@()
                    'shared-gateway'=@()
                    'local-only'=@()
                }
            })
        }
        Write-FixtureJson -Path (Join-Path $profile '.copilot\config.json') -Value @{
            installedPlugins = @(
                @{
                    name='fixture-plugin'
                    enabled=$true
                    cache_path=$pluginRoot
                },
                @{
                    name='missing-manifest-plugin'
                    enabled=$true
                    cache_path=$missingManifestPluginRoot
                }
            )
        }
        Write-FixtureJson -Path (Join-Path $profile '.copilot\mcp-config.json') -Value @{ mcpServers = @{} }

        $report = Join-Path $fixtureRoot 'report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)

        $LASTEXITCODE | Should -Be 1
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        @($parsed.results.check) | Should -Not -Contain 'duplicate-skill-exposure:copilot:fixture-skill'
        $inventoried = @($parsed.inventory.skills | Where-Object {
            $_.hostId -eq 'copilot' -and $_.skillId -eq 'fixture-skill'
        })
        $inventoried.Count | Should -Be 1
        $inventoried[0].path | Should -Be (Join-Path $pluginRoot 'skills\fixture-skill\SKILL.md')
        @($parsed.results.check) | Should -Contain `
            'copilot-manifest-missing:missing-manifest-plugin'
        @($parsed.inventory.skills | Where-Object {
            $_.hostId -eq 'copilot' -and $_.skillId -eq 'missing-fixture-skill'
        }).Count | Should -Be 0
    }

    It 'uses explicit Codex plugin state instead of retained remote-package cache directories' {
        $fixtureRoot = Join-Path $TestDrive 'codex-plugin-state-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $cacheRoot = Join-Path $profile '.codex\plugins\cache\openai-curated-remote'
        $snapshotPath = Join-Path $fixtureRoot 'runtime\codex-plugin-install-state.json'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents = @(@{
                id='codex'; name='Codex'; version='fixture'; executable=$executable; status='active'
                nativePaths=@{ skillsDir=(Join-Path $profile '.codex\skills'); pluginsDir=(Join-Path $profile '.codex\plugins') }
            })
            inactiveAgents = @()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{ capabilities=@() }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{
            mcpServers=@(
                @{ id='context7' }, @{ id='exa' }, @{ id='tavily' }, @{ id='notion' }
            )
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy=@{ onDemandLocalMcpIds=@() }
            hosts=@(@{
                hostId='codex'
                exposures=@{
                    'plugin-owned'=@(); 'native-connector'=@(); 'local-only'=@()
                    'shared-gateway'=@('context7','exa','tavily','notion')
                }
            })
        }
        $configPath = Join-Path $profile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        @('[mcp_servers.context7]','url = "https://example.invalid/context7"','',
          '[mcp_servers.exa]','url = "https://example.invalid/exa"','',
          '[mcp_servers.tavily]','url = "https://example.invalid/tavily"','',
          '[mcp_servers.notion]','url = "https://example.invalid/notion"') |
            Set-Content -LiteralPath $configPath -Encoding utf8
        foreach ($plugin in @('Context7','Exa','Tavily','Notion')) {
            Write-FixtureJson -Path (Join-Path $cacheRoot "$plugin\1.0.0\.codex-plugin\plugin.json") -Value @{
                interface=@{ displayName=$plugin }
            }
        }
        Write-FixtureJson -Path $snapshotPath -Value @{
            schemaVersion=1
            generatedAt=(Get-Date).ToUniversalTime().ToString('o')
            source='fixture Plugin Management control plane'
            apps=@(
                @{ appId='Context7'; name='Context7'; state='installed' }
                @{ appId='Exa'; name='Exa'; state='uninstalled' }
                @{ appId='Tavily'; name='Tavily'; state='not-installed' }
            )
        }

        $report = Join-Path $fixtureRoot 'report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -CodexPluginStatePath $snapshotPath `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)

        $LASTEXITCODE | Should -Be 1
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
        $rows = @($parsed.results | Where-Object { $_.check -like 'codex-remote-and-direct-duplicate:*' })
        (@($rows | Where-Object { $_.check -eq 'codex-remote-and-direct-duplicate:context7' }).status) | Should -Be 'FAIL'
        (@($rows | Where-Object { $_.check -eq 'codex-remote-and-direct-duplicate:exa' }).status) | Should -Be 'PASS'
        (@($rows | Where-Object { $_.check -eq 'codex-remote-and-direct-duplicate:tavily' }).status) | Should -Be 'PASS'
        (@($rows | Where-Object { $_.check -eq 'codex-remote-and-direct-duplicate:notion' }).status) | Should -Be 'WARN'
    }

    It 'groups one local MCP process tree and rejects an unsupported enabled Grok plugin' {
        $fixtureRoot = Join-Path $TestDrive 'runtime-tree-fixture'
        $registryRoot = Join-Path $fixtureRoot 'agenthub'
        $registryDir = Join-Path $registryRoot 'registry'
        $profile = Join-Path $fixtureRoot 'profile'
        $appData = Join-Path $profile 'AppData\Roaming'
        $localAppData = Join-Path $profile 'AppData\Local'
        $grokRoot = Join-Path $profile '.grok'
        $pluginRoot = Join-Path $grokRoot 'installed-plugins\chrome-fixture'
        $executable = (Get-Command powershell.exe -ErrorAction Stop).Source

        Write-FixtureJson -Path (Join-Path $registryDir 'agents.json') -Value @{
            activeAgents=@(@{
                id='grok'; name='Grok'; version='fixture'; executable=$executable
                status='active'
                nativePaths=@{
                    config=(Join-Path $grokRoot 'config.toml')
                    pluginsDir=(Join-Path $grokRoot 'installed-plugins')
                }
            })
            inactiveAgents=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'capabilities.json') -Value @{
            capabilities=@()
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'mcps.json') -Value @{
            mcpServers=@(@{ id='chrome-devtools' })
        }
        Write-FixtureJson -Path (Join-Path $registryDir 'native-connectors.json') -Value @{
            lifecyclePolicy=@{ onDemandLocalMcpIds=@('chrome-devtools') }
            hosts=@(@{
                hostId='grok'
                exposures=@{
                    'plugin-owned'=@()
                    'native-connector'=@()
                    'shared-gateway'=@()
                    'local-only'=@()
                }
            })
        }
        New-Item -ItemType Directory -Path $grokRoot -Force | Out-Null
        @(
            '[plugins]',
            'enabled = ["chrome-devtools-mcp"]',
            'disabled = []'
        ) | Set-Content -LiteralPath (Join-Path $grokRoot 'config.toml') `
            -Encoding UTF8
        Write-FixtureJson -Path (
            Join-Path $grokRoot 'installed-plugins\registry.json'
        ) -Value @{
            repos=@{
                'chrome-fixture'=@{
                    path=$pluginRoot
                    plugins=@{
                        'chrome-devtools-mcp'=@{ version='fixture' }
                    }
                }
            }
        }
        Write-FixtureJson -Path (
            Join-Path $pluginRoot '.claude-plugin\plugin.json'
        ) -Value @{
            name='chrome-devtools-mcp'
            mcpServers=@{
                'chrome-devtools'=@{
                    command='npx'
                    args=@('chrome-devtools-mcp@1.6.0')
                }
            }
        }
        $processSnapshot = Join-Path $fixtureRoot 'processes.json'
        Write-FixtureJson -Path $processSnapshot -Value @{
            processes=@(
                @{
                    ProcessId=50; ParentProcessId=1; Name='powershell.exe'
                    ExecutablePath=$executable; CommandLine='grok.exe --yolo'
                },
                @{
                    ProcessId=100; ParentProcessId=50; Name='node.exe'
                    CommandLine='npx chrome-devtools-mcp@1.6.0'
                },
                @{
                    ProcessId=101; ParentProcessId=100; Name='node.exe'
                    CommandLine='chrome-devtools-mcp.js'
                },
                @{
                    ProcessId=102; ParentProcessId=101; Name='node.exe'
                    CommandLine='telemetry watchdog --parent-pid=101'
                }
            )
        }

        $report = Join-Path $fixtureRoot 'report.json'
        $checkerOutput = @(& $powerShell -NoLogo -NoProfile -NonInteractive `
            -File $checker `
            -RegistryRoot $registryRoot `
            -UserProfilePath $profile `
            -AppDataPath $appData `
            -LocalAppDataPath $localAppData `
            -ReposRoot (Join-Path $fixtureRoot 'Repos') `
            -WorktreeRoot (Join-Path $fixtureRoot 'wt') `
            -ProcessSnapshotPath $processSnapshot `
            -SkipRepositoryScan `
            -ReportPath $report `
            -Json 2>&1)
        $LASTEXITCODE | Should -Be 1
        if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
            throw "Checker did not produce its report:`n$($checkerOutput -join [Environment]::NewLine)"
        }
        $parsed = Get-Content -LiteralPath $report -Raw -Encoding UTF8 |
            ConvertFrom-Json
        @($parsed.inventory.runtimeTrees).Count | Should -Be 1
        $tree = @($parsed.inventory.runtimeTrees)[0]
        $tree.rootProcessId | Should -Be 100
        $tree.ownerHostId | Should -Be 'grok'
        $tree.mcpId | Should -Be 'chrome-devtools'
        @($tree.processIds) | Should -Be @(100, 101, 102)
        @($parsed.results.check) | Should -Contain `
            'unsupported-enabled-local-plugin:grok:chrome-devtools-mcp:chrome-devtools'
    }

    It 'keeps normal agent runtimes distinct from local MCP workers' {
        $source = Get-Content -LiteralPath $checker -Raw -Encoding UTF8
        $source | Should -Match "'agent-runtime'"
        $source | Should -Match "'local-mcp-worker'"
        $source | Should -Match 'Normal autostart runtimes are not drift'
        $source | Should -Match 'Protect-ProcessCommandLine'
        $source | Should -Match 'forbidden-root-recreated:'
        $source | Should -Match "'C:\\tmp'"
    }

    It 'covers the host configuration formats omitted by the legacy checker' {
        $source = Get-Content -LiteralPath $checker -Raw -Encoding UTF8
        foreach ($hostId in @(
            'codex', 'claude', 'qwen-code', 'opencode', 'gemini', 'hermes',
            'copilot', 'antigravity', 'grok', 'warp', 'cline', 'qoder',
            'cursor', 'amp', 'devin', 'factory', 'vscode-insiders', 'windsurf'
        )) {
            $source | Should -Match ([regex]::Escape("hostId='$hostId'"))
        }
    }
}
