#Requires -Version 5.1

Describe 'AgentHub worktree policy deployment' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:helperScript = Join-Path $script:repoRoot 'scripts\New-AgentHubWorktree.ps1'
        $script:installerScript = Join-Path $script:repoRoot 'scripts\Install-WorktreePolicy.ps1'
        $script:readinessScript = Join-Path $script:repoRoot 'tests\Test-HostReadiness.ps1'
        $script:originalProcessRoot = $env:AGENTHUB_WORKTREE_ROOT
    }

    AfterAll {
        $env:AGENTHUB_WORKTREE_ROOT = $script:originalProcessRoot
    }

    It 'supports manual host invocation without requiring hook JSON' {
        $planned = & $script:helperScript `
            -Cwd $script:repoRoot `
            -Name 'manual-policy-check' `
            -PlanOnly

        $planned | Should -Be 'C:\wt\agenthub\manual-policy-check'
    }

    It 'records current native controls and every verified global instruction target' {
        $roots = Get-Content -LiteralPath `
            (Join-Path $script:repoRoot 'registry\worktree-roots.json') -Raw |
            ConvertFrom-Json
        $roots.schemaVersion | Should -Be 2
        $roots.environmentContract.ownership | Should -Be 'agenthub-controller-managed'
        $roots.environmentContract.required | Should -BeTrue
        $roots.environmentContract.mutationPolicy | Should -Be 'controller-set-to-canonical-value'
        $roots.deployedHelper | Should -Be `
            'C:/Users/SaroshHussain/AppData/Local/AgentHub/bin/New-AgentHubWorktree.ps1'
        $roots.installerScript | Should -Be 'scripts/Install-WorktreePolicy.ps1'
        @($roots.hosts | Where-Object mechanism -eq 'agenthub-helper-plus-generated-policy').Count |
            Should -Be 19

        $gemini = @($roots.hosts | Where-Object hostId -eq 'gemini')
        $gemini.disableSetting | Should -Be 'experimental.worktrees=false'
        $hermes = @($roots.hosts | Where-Object hostId -eq 'hermes')
        $hermes.disableSetting | Should -Be 'worktree=false'
        $copilot = @($roots.hosts | Where-Object hostId -eq 'copilot')
        $copilot.disableSetting | Should -Be 'experimental=false'
        $qoder = @($roots.hosts | Where-Object hostId -eq 'qoder')
        $qoder.nativeBuiltIn.hookDiscoveryState | Should -Be 'binary-only-undocumented'
        $warp = @($roots.hosts | Where-Object hostId -eq 'warp')
        $warp.mechanism | Should -Be 'agenthub-managed-native-tab-config'
        $warp.tabConfigPath | Should -Be `
            'C:/Users/SaroshHussain/.warp/tab_configs/agenthub_worktree.toml'

        $installations = Get-Content -LiteralPath `
            (Join-Path $script:repoRoot 'registry\installations.json') -Raw |
            ConvertFrom-Json
        @($installations.managedInstructionTargets.id | Sort-Object) | Should -Be @(
            'amp',
            'claude',
            'cline-cli',
            'cline-desktop',
            'codex',
            'copilot',
            'factory',
            'gemini',
            'grok',
            'hermes',
            'opencode',
            'qwen-code'
        )
        @($installations.managedInstructionTargets.id) | Should -Not -Contain 'qoder'
    }

    It 'resolves the checker repository default under Windows PowerShell 5.1' {
        $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
        if (-not $windowsPowerShell) {
            Set-ItResult -Skipped -Because 'Windows PowerShell is not installed.'
            return
        }
        $checker = Join-Path $script:repoRoot 'scripts\Test-WorktreeRootPolicy.ps1'
        $output = & $windowsPowerShell.Source -NoProfile -ExecutionPolicy Bypass `
            -File $checker -Json
        $LASTEXITCODE | Should -Be 0
        $parsed = $output | ConvertFrom-Json
        $parsed.summary.fail | Should -Be 0
    }

    It 'returns valid readiness JSON for managed instruction targets' {
        $fixture = Join-Path $TestDrive 'readiness-json'
        $registry = Join-Path $fixture 'registry'
        $docs = Join-Path $fixture 'docs'
        $instruction = Join-Path $fixture 'profile\AGENTS.md'
        $policy = Join-Path $docs 'worktree-management-policy.md'
        New-Item -ItemType Directory -Path `
            $registry, `
            $docs, `
            (Split-Path -Parent $instruction) -Force | Out-Null
        'synthetic policy' | Set-Content -LiteralPath $policy -Encoding UTF8
        "Follow $policy" | Set-Content -LiteralPath $instruction -Encoding UTF8
        @{
            activeAgents = @(
                @{
                    id = 'synthetic'
                    name = 'Synthetic Agent'
                    executable = 'powershell.exe'
                    nativePaths = @{ instructions = $instruction }
                }
            )
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $registry 'agents.json') -Encoding UTF8

        $output = & powershell.exe -NoLogo -NoProfile -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $script:readinessScript `
            -RegistryRoot $fixture `
            -Json
        $LASTEXITCODE | Should -Be 0
        $result = $output | ConvertFrom-Json
        $result.summary.policyFailures | Should -Be 0
        @($result.hosts).Count | Should -Be 1
        $result.hosts[0].worktreePolicy | Should -Be 'present'
    }

    It 'deploys the helper and merges supported settings without destroying unrelated state' {
        Test-Path -LiteralPath $script:installerScript -PathType Leaf | Should -BeTrue

        $fixture = Join-Path $TestDrive 'deploy'
        $fixtureRegistry = Join-Path $fixture 'control'
        $profile = Join-Path $fixture 'profile'
        $localAppData = Join-Path $fixture 'local-app-data'
        New-Item -ItemType Directory -Path `
            (Join-Path $fixtureRegistry 'registry'), `
            (Join-Path $fixtureRegistry 'scripts'), `
            (Join-Path $profile '.claude'), `
            (Join-Path $profile '.gemini'), `
            (Join-Path $profile '.codex'), `
            (Join-Path $profile '.qoder'), `
            (Join-Path $profile '.copilot'), `
            (Join-Path $profile '.grok') -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'registry\worktree-roots.json') `
            -Destination (Join-Path $fixtureRegistry 'registry\worktree-roots.json')
        Copy-Item -LiteralPath $script:helperScript `
            -Destination (Join-Path $fixtureRegistry 'scripts\New-AgentHubWorktree.ps1')

        @{
            keep = 'claude-user-state'
            hooks = @{
                PreToolUse = @(
                    @{
                        matcher = 'Read'
                        hooks = @(@{ type = 'command'; command = 'existing-command' })
                    }
                )
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath `
            (Join-Path $profile '.claude\settings.json') -Encoding UTF8
        @{
            keep = 'gemini-user-state'
            experimental = @{ dynamicModelConfiguration = $true }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath `
            (Join-Path $profile '.gemini\settings.json') -Encoding UTF8
        @{
            keep = 'qoder-user-state'
            enabledPlugins = @{ example = $true }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath `
            (Join-Path $profile '.qoder\settings.json') -Encoding UTF8
        @{
            keep = 'copilot-user-state'
            stayInAutopilot = $true
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath `
            (Join-Path $profile '.copilot\settings.json') -Encoding UTF8
        @"
[hints]
keep = "grok-user-state"

[[marketplace.sources]]
name = "synthetic"
git = "https://example.invalid/synthetic.git"

[ui]
yolo = true

[subagents]
enabled = true
"@ | Set-Content -LiteralPath (Join-Path $profile '.grok\config.toml') -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $localAppData 'hermes') -Force | Out-Null
        @"
model:
  default: synthetic
agent:
  max_iterations: 10
"@ | Set-Content -LiteralPath (Join-Path $localAppData 'hermes\config.yaml') -Encoding UTF8
        @"
model = 'synthetic'
git-worktree-root = 'C:\wt'
"@ | Set-Content -LiteralPath (Join-Path $profile '.codex\config.toml') -Encoding UTF8

        $qoderHashBefore = (Get-FileHash -LiteralPath `
            (Join-Path $profile '.qoder\settings.json') -Algorithm SHA256).Hash

        & $script:installerScript `
            -Apply `
            -RegistryRoot $fixtureRegistry `
            -UserProfile $profile `
            -LocalAppData $localAppData `
            -EnvironmentScope Process | Out-Null

        $runtimeHelper = Join-Path $localAppData 'AgentHub\bin\New-AgentHubWorktree.ps1'
        Test-Path -LiteralPath $runtimeHelper -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $runtimeHelper -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $fixtureRegistry 'scripts\New-AgentHubWorktree.ps1') -Algorithm SHA256).Hash

        $claude = Get-Content -LiteralPath (Join-Path $profile '.claude\settings.json') -Raw | ConvertFrom-Json
        $claude.keep | Should -Be 'claude-user-state'
        @($claude.hooks.PreToolUse).Count | Should -Be 1
        @($claude.hooks.WorktreeCreate).Count | Should -Be 1
        @($claude.hooks.WorktreeCreate[0].hooks).Count | Should -Be 1
        $claude.hooks.WorktreeCreate[0].hooks[0].type | Should -Be 'command'
        $claude.hooks.WorktreeCreate[0].hooks[0].command |
            Should -Be ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runtimeHelper)

        $gemini = Get-Content -LiteralPath (Join-Path $profile '.gemini\settings.json') -Raw | ConvertFrom-Json
        $gemini.keep | Should -Be 'gemini-user-state'
        $gemini.experimental.dynamicModelConfiguration | Should -BeTrue
        $gemini.experimental.worktrees | Should -BeFalse

        $copilot = Get-Content -LiteralPath (Join-Path $profile '.copilot\settings.json') -Raw | ConvertFrom-Json
        $copilot.keep | Should -Be 'copilot-user-state'
        $copilot.stayInAutopilot | Should -BeTrue
        $copilot.experimental | Should -BeFalse

        $grokText = Get-Content -LiteralPath (Join-Path $profile '.grok\config.toml') -Raw
        $hints = [regex]::Match(
            $grokText,
            '(?ms)^\[hints\]\s*(?<body>.*?)(?=^\[\[marketplace\.sources\]\])'
        )
        $hints.Success | Should -BeTrue
        $hints.Groups['body'].Value | Should -Match 'keep\s*=\s*"grok-user-state"'
        $hints.Groups['body'].Value | Should -Match 'new_session_worktree_mode\s*=\s*"never"'
        $hints.Groups['body'].Value | Should -Match 'fork_worktree_mode\s*=\s*"never"'
        $grokText | Should -Match '(?ms)^\[\[marketplace\.sources\]\]\s*name\s*=\s*"synthetic"'
        $grokText | Should -Match '(?ms)^\[subagents\].*enabled\s*=\s*true'

        $hermesText = Get-Content -LiteralPath (Join-Path $localAppData 'hermes\config.yaml') -Raw
        $hermesText | Should -Match '(?m)^worktree:\s*false\s*$'
        $hermesText | Should -Match '(?ms)^model:.*default:\s*synthetic'

        $warpTabConfig = Join-Path $profile '.warp\tab_configs\agenthub_worktree.toml'
        Test-Path -LiteralPath $warpTabConfig -PathType Leaf | Should -BeTrue
        $warpText = Get-Content -LiteralPath $warpTabConfig -Raw
        $warpText | Should -Match 'agenthub:managed'
        $warpText | Should -Match 'New-AgentHubWorktree\.ps1'
        $warpText | Should -Match '(?m)^type\s*=\s*"agent"'
        $warpText | Should -Match 'repository_path'
        $warpText | Should -Match 'task'

        (Get-FileHash -LiteralPath (Join-Path $profile '.qoder\settings.json') -Algorithm SHA256).Hash |
            Should -Be $qoderHashBefore
        $env:AGENTHUB_WORKTREE_ROOT | Should -Be 'C:\wt'

        $backupFiles = @(Get-ChildItem -LiteralPath `
            (Join-Path $localAppData 'AgentHub\reports\backups') -File -Recurse)
        @($backupFiles.Name) | Should -Contain 'settings.claude.json'
        @($backupFiles.Name) | Should -Contain 'settings.gemini.json'
        @($backupFiles.Name) | Should -Contain 'settings.copilot.json'
        @($backupFiles.Name) | Should -Contain 'config.grok.toml'
        @($backupFiles.Name) | Should -Contain 'config.hermes.yaml'

        $claudeHash = (Get-FileHash -LiteralPath `
            (Join-Path $profile '.claude\settings.json') -Algorithm SHA256).Hash
        $geminiHash = (Get-FileHash -LiteralPath `
            (Join-Path $profile '.gemini\settings.json') -Algorithm SHA256).Hash
        & $script:installerScript `
            -Apply `
            -RegistryRoot $fixtureRegistry `
            -UserProfile $profile `
            -LocalAppData $localAppData `
            -EnvironmentScope Process | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $profile '.claude\settings.json') -Algorithm SHA256).Hash |
            Should -Be $claudeHash
        (Get-FileHash -LiteralPath (Join-Path $profile '.gemini\settings.json') -Algorithm SHA256).Hash |
            Should -Be $geminiHash
    }

    It 'fails closed before mutation when another WorktreeCreate hook owns the event' {
        $fixture = Join-Path $TestDrive 'conflict'
        $fixtureRegistry = Join-Path $fixture 'control'
        $profile = Join-Path $fixture 'profile'
        $localAppData = Join-Path $fixture 'local-app-data'
        New-Item -ItemType Directory -Path `
            (Join-Path $fixtureRegistry 'registry'), `
            (Join-Path $fixtureRegistry 'scripts'), `
            (Join-Path $profile '.claude'), `
            (Join-Path $profile '.gemini'), `
            (Join-Path $profile '.codex'), `
            (Join-Path $profile '.copilot'), `
            (Join-Path $profile '.grok') -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'registry\worktree-roots.json') `
            -Destination (Join-Path $fixtureRegistry 'registry\worktree-roots.json')
        Copy-Item -LiteralPath $script:helperScript `
            -Destination (Join-Path $fixtureRegistry 'scripts\New-AgentHubWorktree.ps1')
        @{
            hooks = @{
                WorktreeCreate = @(
                    @{
                        hooks = @(@{ type = 'command'; command = 'user-owned-worktree-hook' })
                    }
                )
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath `
            (Join-Path $profile '.claude\settings.json') -Encoding UTF8
        @{ experimental = @{ dynamicModelConfiguration = $true } } |
            ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $profile '.gemini\settings.json') -Encoding UTF8
        "git-worktree-root = 'C:\wt'" |
            Set-Content -LiteralPath (Join-Path $profile '.codex\config.toml') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $profile '.copilot\settings.json') -Encoding UTF8
        '[ui]' | Set-Content -LiteralPath (Join-Path $profile '.grok\config.toml') -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $localAppData 'hermes') -Force | Out-Null
        'model: {}' | Set-Content -LiteralPath (Join-Path $localAppData 'hermes\config.yaml') -Encoding UTF8

        {
            & $script:installerScript `
                -Apply `
                -RegistryRoot $fixtureRegistry `
                -UserProfile $profile `
                -LocalAppData $localAppData `
                -EnvironmentScope Process
        } | Should -Throw '*WorktreeCreate*already owned*'

        Test-Path -LiteralPath `
            (Join-Path $localAppData 'AgentHub\bin\New-AgentHubWorktree.ps1') |
            Should -BeFalse
        $gemini = Get-Content -LiteralPath (Join-Path $profile '.gemini\settings.json') -Raw | ConvertFrom-Json
        $gemini.experimental.PSObject.Properties.Name | Should -Not -Contain 'worktrees'
    }
}
