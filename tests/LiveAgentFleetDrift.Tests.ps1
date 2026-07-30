#Requires -Version 5.1

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:checker = Join-Path $repoRoot 'scripts\Test-LiveAgentFleetDrift.ps1'
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
