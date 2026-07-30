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
