$global:AgentHubApplyScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Apply-FullAccessAgentProfile.ps1'
$global:AgentHubTestPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$pathSafetyScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\PathSafety.ps1'
. $pathSafetyScript
$env:AGENTHUB_PROFILE_TEST_DIRECTORY = Assert-AgentHubSafeWritePath -Path (Join-Path ([System.IO.Path]::GetTempPath()) ('agenthub-profile-tests-' + [guid]::NewGuid().ToString('N'))) -Purpose 'the synthetic agent-profile test directory'
New-Item -ItemType Directory -Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY -Force | Out-Null

$global:canonicalVideoSkills = @(
    'product-demo-studio',
    'product-demo-studio-capture',
    'product-demo-studio-descript',
    'product-demo-studio-narration',
    'product-demo-studio-qa',
    'product-demo-studio-remotion',
    'product-demo-studio-render',
    'product-demo-studio-visual-assets'
)

$global:canonicalExperienceSkills = @(
    'audit-product-experience',
    'design-agentic-experiences',
    'design-new-application-experience',
    'design-workflows-and-features',
    'discover-application',
    'engineer-product-experience',
    'implement-experience-improvements',
    'measure-experience-outcomes',
    'prepare-product-for-demo',
    'specify-experience-improvements',
    'validate-product-experience'
)

$global:canonicalPortfolioEngineeringSkills = @(
    'docs-drift',
    'portfolio-audit',
    'release-readiness',
    'repo-onboard',
    'verify-and-commit'
)

function global:New-DistributionFixture {
    param([string]$Root)

    $registryRoot = Join-Path $Root 'registry-root'
    $canonicalRoot = Join-Path $Root 'canonical-product-demo-studio'
    $canonicalExperienceRoot = Join-Path $Root 'canonical-product-experience-engineering'
    $canonicalBrowserRoot = Join-Path $Root 'canonical-browser-toolkit'
    $canonicalPortfolioEngineeringRoot = Join-Path $Root 'canonical-portfolio-engineering-ops'
    $fakeProfile = Join-Path $Root 'profile'
    $fakeAppData = Join-Path $fakeProfile 'AppData\Roaming'
    $fakeLocalAppData = Join-Path $fakeProfile 'AppData\Local'
    New-Item -ItemType Directory -Path (Join-Path $registryRoot 'registry') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $registryRoot 'scripts') -Force | Out-Null
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot 'standards') -Destination (Join-Path $registryRoot 'standards') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $canonicalRoot 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $canonicalBrowserRoot 'skills\browser-debugging') -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeAppData -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $canonicalRoot '.codex-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $canonicalRoot '.claude-plugin') -Force | Out-Null
    '{"name":"product-demo-studio","version":"0.4.0"}' | Set-Content -LiteralPath (Join-Path $canonicalRoot '.codex-plugin\plugin.json') -Encoding UTF8
    '{"name":"product-demo-studio","version":"0.4.0"}' | Set-Content -LiteralPath (Join-Path $canonicalRoot '.claude-plugin\plugin.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $canonicalBrowserRoot 'skills\browser-debugging\SKILL.md') -Value 'canonical:browser-debugging' -Encoding UTF8

    foreach ($name in $global:canonicalVideoSkills) {
        $skillRoot = Join-Path $canonicalRoot "skills\$name"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value "canonical:$name" -Encoding UTF8
    }

    New-Item -ItemType Directory -Path (Join-Path $canonicalExperienceRoot 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $canonicalExperienceRoot '.codex-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $canonicalExperienceRoot '.claude-plugin') -Force | Out-Null
    '{"name":"product-experience-engineering","version":"1.1.0"}' |
        Set-Content -LiteralPath (Join-Path $canonicalExperienceRoot '.codex-plugin\plugin.json') -Encoding UTF8
    '{"name":"product-experience-engineering","version":"1.1.0"}' |
        Set-Content -LiteralPath (Join-Path $canonicalExperienceRoot '.claude-plugin\plugin.json') -Encoding UTF8
    foreach ($name in $global:canonicalExperienceSkills) {
        $skillRoot = Join-Path $canonicalExperienceRoot "skills\$name"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value "canonical:$name" -Encoding UTF8
    }
    foreach ($name in $global:canonicalPortfolioEngineeringSkills) {
        $skillRoot = Join-Path $canonicalPortfolioEngineeringRoot "skills\$name"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value "canonical:$name" -Encoding UTF8
    }
    $experienceReferences = Join-Path $canonicalExperienceRoot 'skills\engineer-product-experience\references'
    New-Item -ItemType Directory -Path $experienceReferences -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $experienceReferences 'surface-coverage.md') -Value 'coverage:complete' -Encoding UTF8
    $references = Join-Path $canonicalRoot 'skills\product-demo-studio\references'
    New-Item -ItemType Directory -Path $references -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $references 'portfolio-standard.md') -Value 'version:2' -Encoding UTF8
    $rules = Join-Path $canonicalRoot 'skills\product-demo-studio-remotion\rules'
    New-Item -ItemType Directory -Path $rules -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $rules 'video-layout.md') -Value 'safe-area:80' -Encoding UTF8
    $qwenExtensionSkills = Join-Path $fakeProfile '.qwen\extensions\agenthub-product-demo-studio\skills'
    New-Item -ItemType Directory -Path $qwenExtensionSkills -Force | Out-Null
    $qwenAdapterRoot = Join-Path $fakeLocalAppData 'AgentHub\runtime\qwen-code\extensions\agenthub-product-demo-studio'
    New-Item -ItemType Directory -Path (Join-Path $qwenAdapterRoot 'skills') -Force | Out-Null
    '{"name":"agenthub-product-demo-studio","version":"1.0.0","skills":"skills"}' |
        Set-Content -LiteralPath (Join-Path $qwenAdapterRoot 'qwen-extension.json') -Encoding UTF8
    foreach ($name in $global:canonicalVideoSkills) {
        Copy-Item -LiteralPath (Join-Path $canonicalRoot "skills\$name") -Destination $qwenExtensionSkills -Recurse
        Copy-Item -LiteralPath (Join-Path $canonicalRoot "skills\$name") -Destination (Join-Path $qwenAdapterRoot 'skills') -Recurse
    }
    $qwenExperienceExtensionSkills = Join-Path $fakeProfile '.qwen\extensions\agenthub-product-experience-engineering\skills'
    New-Item -ItemType Directory -Path $qwenExperienceExtensionSkills -Force | Out-Null
    $qwenExperienceAdapterRoot = Join-Path $fakeLocalAppData 'AgentHub\runtime\qwen-code\extensions\agenthub-product-experience-engineering'
    New-Item -ItemType Directory -Path (Join-Path $qwenExperienceAdapterRoot 'skills') -Force | Out-Null
    '{"name":"agenthub-product-experience-engineering","version":"1.0.0","skills":"skills"}' |
        Set-Content -LiteralPath (Join-Path $qwenExperienceAdapterRoot 'qwen-extension.json') -Encoding UTF8
    foreach ($name in $global:canonicalExperienceSkills) {
        Copy-Item -LiteralPath (Join-Path $canonicalExperienceRoot "skills\$name") -Destination $qwenExperienceExtensionSkills -Recurse
        Copy-Item -LiteralPath (Join-Path $canonicalExperienceRoot "skills\$name") -Destination (Join-Path $qwenExperienceAdapterRoot 'skills') -Recurse
    }

    @{ mcpServers = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
    @{ capabilities = @(
        @{ id = 'product-demo-studio'; canonicalSource = $canonicalRoot; hostMappings = @(
            @{ hostId = 'claude'; deploymentStatus = 'managed-loose-skills' },
            @{ hostId = 'codex'; deploymentStatus = 'native-plugin-installed' },
            @{ hostId = 'copilot'; deploymentStatus = 'native-local-plugin-skills-only' }
        ) },
        @{ id = 'product-experience-engineering'; canonicalSource = $canonicalExperienceRoot; hostMappings = @(
            @{ hostId = 'claude'; deploymentStatus = 'native-plugin-installed' },
            @{ hostId = 'codex'; deploymentStatus = 'native-plugin-installed' },
            @{ hostId = 'copilot'; deploymentStatus = 'native-local-plugin' }
        ) },
        @{ id = 'browser-toolkit'; canonicalSource = $canonicalBrowserRoot; managedSkillNames = @('browser-debugging'); hostMappings = @(
            @{ hostId = 'claude'; deploymentStatus = 'managed-loose-skills-and-mcp' }
        ) },
        @{ id = 'portfolio-engineering-ops'; canonicalSource = $canonicalPortfolioEngineeringRoot; managedSkillNames = $global:canonicalPortfolioEngineeringSkills; hostMappings = @(
            @{ hostId = 'claude'; deploymentStatus = 'managed-loose-skills' },
            @{ hostId = 'codex'; deploymentStatus = 'managed-loose-skills' },
            @{ hostId = 'cline'; deploymentStatus = 'managed-loose-skills' }
        ) }
    ) } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\capabilities.json') -Encoding UTF8
    @{
        managedHosts = @('claude','codex','cursor','qwen-code','opencode','factory','devin','amp','windsurf','gemini','hermes','grok','antigravity','warp','copilot')
        hostSettings = @{}
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\fleet-profile.json') -Encoding UTF8

    # This should never be reached by -SkillDistributionOnly, but make an
    # accidental invocation fail loudly rather than altering a real host.
    "throw 'Synchronizer must not run in a distribution-only test.'" |
        Set-Content -LiteralPath (Join-Path $registryRoot 'scripts\Sync-AgentHub.ps1') -Encoding UTF8

    return @{
        RegistryRoot = $registryRoot
        CanonicalRoot = $canonicalRoot
        CanonicalExperienceRoot = $canonicalExperienceRoot
        CanonicalBrowserRoot = $canonicalBrowserRoot
        CanonicalPortfolioEngineeringRoot = $canonicalPortfolioEngineeringRoot
        UserProfile = $fakeProfile
        AppData = $fakeAppData
        LocalAppData = $fakeLocalAppData
    }
}

function global:Invoke-DistributionOnly {
    param([hashtable]$Fixture, [switch]$RetireLegacyVideoOwners)

    $previousAppData = $env:APPDATA
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $env:APPDATA = $Fixture.AppData
        $env:LOCALAPPDATA = $Fixture.LocalAppData
        $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$global:AgentHubApplyScriptPath,
            '-RegistryRoot',$Fixture.RegistryRoot,'-UserProfile',$Fixture.UserProfile,'-SkillDistributionOnly')
        if ($RetireLegacyVideoOwners) { $arguments += '-RetireLegacyVideoOwners' }
        & $global:AgentHubTestPowerShell @arguments | Out-Host
        return $LASTEXITCODE
    } finally {
        $env:APPDATA = $previousAppData
        $env:LOCALAPPDATA = $previousLocalAppData
    }
}

AfterAll {
    if (Test-Path -LiteralPath $env:AGENTHUB_PROFILE_TEST_DIRECTORY) {
        Remove-Item -LiteralPath $env:AGENTHUB_PROFILE_TEST_DIRECTORY -Recurse -Force
    }
}

Describe 'Apply-FullAccessAgentProfile managed video distribution' {
    It 'honors the loose-skill mapping when a disabled Claude plugin cache entry remains' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'claude-disabled-plugin-transition'
        )
        $installedPath = Join-Path $fixture.UserProfile '.claude\plugins\installed_plugins.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $installedPath) -Force | Out-Null
        @{
            plugins = @{
                'product-demo-studio@handoff' = @(@{
                    scope = 'user'
                    installPath = $fixture.CanonicalRoot
                    version = '0.4.0'
                })
            }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $installedPath -Encoding UTF8
        @{
            enabledPlugins = @{
                'product-demo-studio@handoff' = $false
            }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $fixture.UserProfile '.claude\settings.json') -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        $skillPath = Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio\SKILL.md'
        (Get-Content -LiteralPath $skillPath -Raw).Trim() | Should -Be 'canonical:product-demo-studio'
    }

    It 'fails closed when Claude still enables a plugin mapped to loose skills' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'claude-enabled-plugin-conflict'
        )
        $installedPath = Join-Path $fixture.UserProfile '.claude\plugins\installed_plugins.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $installedPath) -Force | Out-Null
        @{
            plugins = @{
                'product-demo-studio@handoff' = @(@{
                    scope = 'user'
                    installPath = $fixture.CanonicalRoot
                    version = '0.4.0'
                })
            }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $installedPath -Encoding UTF8
        @{
            enabledPlugins = @{
                'product-demo-studio@handoff' = $true
            }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $fixture.UserProfile '.claude\settings.json') -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Not -Be 0
    }

    It 'accepts the singular managed-loose-skill status used by single-skill capabilities' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'singular-managed-loose-skill'
        )
        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        ($capabilities.capabilities | Where-Object id -eq 'browser-toolkit').hostMappings[0].deploymentStatus =
            'managed-loose-skill'
        $capabilities | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        $skillPath = Join-Path $fixture.UserProfile '.claude\skills\browser-debugging\SKILL.md'
        (Get-Content -LiteralPath $skillPath -Raw).Trim() | Should -Be 'canonical:browser-debugging'
    }

    It 'quarantines only the audited orphan Claude local-ai-stack skill when Codex is its sole owner' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'retired-claude-local-ai-stack'
        )
        $canonicalRoot = Join-Path $fixture.RegistryRoot 'capabilities\local-ai-stack'
        $canonicalSkill = Join-Path $canonicalRoot 'skills\local-ai-stack'
        New-Item -ItemType Directory -Path $canonicalSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonicalSkill 'SKILL.md') `
            -Value 'canonical:local-ai-stack' -Encoding UTF8

        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $registry = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        $registry.capabilities = @($registry.capabilities) + @(
            @{
                id = 'local-ai-stack'
                canonicalSource = $canonicalRoot
                managedSkillNames = @('local-ai-stack')
                hostMappings = @(
                    @{ hostId = 'codex'; deploymentStatus = 'managed-loose-skill' }
                )
            }
        )
        $registry | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        $legacyPath = Join-Path $fixture.UserProfile '.claude\skills\local-ai-stack'
        New-Item -ItemType Directory -Path $legacyPath -Force | Out-Null
        @'
---
name: local-ai-stack
---
## The father's-memorial pipeline (personal, high-care)
Canonical copy: `C:\Repos\creative-lab\skills\local-ai-stack\SKILL.md` (committed).
'@ | Set-Content -LiteralPath (Join-Path $legacyPath 'SKILL.md') -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should -Be 0
        (Test-Path -LiteralPath $legacyPath) | Should -BeFalse
        (Get-Content -LiteralPath (
            Join-Path $fixture.UserProfile '.codex\skills\local-ai-stack\SKILL.md'
        ) -Raw).Trim() | Should -Be 'canonical:local-ai-stack'

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifest = Get-Content -LiteralPath (
            Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse |
                Select-Object -First 1 -ExpandProperty FullName
        ) -Raw | ConvertFrom-Json
        @($manifest.entries | Where-Object {
            $_.hostId -eq 'claude' -and
            $_.artifactKind -eq 'skills' -and
            $_.artifactName -eq 'local-ai-stack'
        }).Count | Should -Be 1
    }

    It 'preserves an unexpected Claude local-ai-stack skill that lacks the audited legacy signature' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'preserved-claude-local-ai-stack'
        )
        $canonicalRoot = Join-Path $fixture.RegistryRoot 'capabilities\local-ai-stack'
        $canonicalSkill = Join-Path $canonicalRoot 'skills\local-ai-stack'
        New-Item -ItemType Directory -Path $canonicalSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonicalSkill 'SKILL.md') `
            -Value 'canonical:local-ai-stack' -Encoding UTF8

        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $registry = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        $registry.capabilities = @($registry.capabilities) + @(
            @{
                id = 'local-ai-stack'
                canonicalSource = $canonicalRoot
                managedSkillNames = @('local-ai-stack')
                hostMappings = @(
                    @{ hostId = 'codex'; deploymentStatus = 'managed-loose-skill' }
                )
            }
        )
        $registry | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        $unexpectedPath = Join-Path $fixture.UserProfile '.claude\skills\local-ai-stack'
        New-Item -ItemType Directory -Path $unexpectedPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unexpectedPath 'SKILL.md') `
            -Value 'preserve:user-owned-local-ai-stack' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $unexpectedPath 'SKILL.md') -Raw).Trim() |
            Should -Be 'preserve:user-owned-local-ai-stack'
        (Get-Content -LiteralPath (
            Join-Path $fixture.UserProfile '.codex\skills\local-ai-stack\SKILL.md'
        ) -Raw).Trim() | Should -Be 'canonical:local-ai-stack'
    }

    It 'quarantines only exact registry-signed retired skills' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'retired-skill-signature'
        )
        $exactRetired = Join-Path $fixture.UserProfile '.claude\skills\browser-evidence'
        $userOwnedConflict = Join-Path $fixture.UserProfile '.codex\skills\browser-evidence'
        New-Item -ItemType Directory -Path $exactRetired, $userOwnedConflict -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $exactRetired 'SKILL.md') `
            -Value 'retired:browser-evidence' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $userOwnedConflict 'SKILL.md') `
            -Value 'preserve:user-owned-browser-evidence' -Encoding UTF8

        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        $browserCapability = $capabilities.capabilities |
            Where-Object id -eq 'browser-toolkit'
        $browserCapability | Add-Member -NotePropertyName retiredSkills -NotePropertyValue @(
            @{
                name = 'browser-evidence'
                contentHash = (Get-FileHash -LiteralPath (
                    Join-Path $exactRetired 'SKILL.md'
                ) -Algorithm SHA256).Hash
                reason = 'Synthetic retired skill.'
            }
        )
        $capabilities | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        Test-Path -LiteralPath $exactRetired | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $userOwnedConflict 'SKILL.md') -Raw).Trim() |
            Should -Be 'preserve:user-owned-browser-evidence'

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifest = Get-Content -LiteralPath (
            Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse |
                Select-Object -First 1 -ExpandProperty FullName
        ) -Raw | ConvertFrom-Json
        @($manifest.entries | Where-Object {
            $_.hostId -eq 'claude' -and
            $_.artifactKind -eq 'skills' -and
            $_.artifactName -eq 'browser-evidence'
        }).Count | Should -Be 1
    }

    It 'deploys Qwen native-skill mappings and replaces their stale junctions' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'qwen-managed-native-skills'
        )
        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        $browserCapability = $capabilities.capabilities | Where-Object id -eq 'browser-toolkit'
        $browserCapability.hostMappings = @($browserCapability.hostMappings) + @(
            @{ hostId = 'qwen-code'; deploymentStatus = 'managed-native-skills-and-mcp' }
        )
        $capabilities | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        $qwenSkill = Join-Path $fixture.UserProfile '.qwen\skills\browser-debugging'
        $retiredTarget = Join-Path $fixture.UserProfile 'retired-qwen-browser-skill'
        New-Item -ItemType Directory -Path $retiredTarget -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $qwenSkill) -Force | Out-Null
        New-Item -ItemType Junction -Path $qwenSkill -Target $retiredTarget | Out-Null
        Remove-Item -LiteralPath $retiredTarget -Recurse -Force

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $qwenSkill 'SKILL.md') -Raw).Trim() |
            Should -Be 'canonical:browser-debugging'
        (Get-Item -LiteralPath $qwenSkill -Force).LinkType | Should -BeNullOrEmpty
    }

    It 'preserves an expected Browser Toolkit junction during generic skill distribution' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'expected-junction')
        $browserTarget = Join-Path $fixture.UserProfile '.claude\skills\browser-debugging'
        New-Item -ItemType Directory -Path (Split-Path -Parent $browserTarget) -Force | Out-Null
        New-Item -ItemType Junction -Path $browserTarget -Target (Join-Path $fixture.CanonicalBrowserRoot 'skills\browser-debugging') | Out-Null

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        (Get-Item -LiteralPath $browserTarget -Force).LinkType | Should -Be 'Junction'
        (Get-Content -LiteralPath (Join-Path $browserTarget 'SKILL.md') -Raw).Trim() | Should -Be 'canonical:browser-debugging'
    }

    It 'replaces a broken managed-skill junction without traversing its missing target' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'broken-managed-junction'
        )
        $browserTarget = Join-Path $fixture.UserProfile '.claude\skills\browser-debugging'
        $retiredTarget = Join-Path $fixture.UserProfile 'retired-source\browser-debugging'
        New-Item -ItemType Directory -Path $retiredTarget -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $browserTarget) -Force | Out-Null
        New-Item -ItemType Junction -Path $browserTarget -Target $retiredTarget | Out-Null
        Remove-Item -LiteralPath $retiredTarget -Recurse -Force

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        (Get-Content -LiteralPath (Join-Path $browserTarget 'SKILL.md') -Raw).Trim() |
            Should -Be 'canonical:browser-debugging'
        (Get-Item -LiteralPath $browserTarget -Force).LinkType | Should -BeNullOrEmpty
        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifest = Get-Content -LiteralPath (
            Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse |
                Select-Object -First 1 -ExpandProperty FullName
        ) -Raw | ConvertFrom-Json
        @($manifest.entries | Where-Object {
            $_.hostId -eq 'claude' -and
            $_.artifactKind -eq 'skills' -and
            $_.artifactName -eq 'browser-debugging'
        }).Count | Should -Be 1
    }

    It 'does not distribute a canonical capability to hosts without a registry mapping' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'mapping-boundary')

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\browser-debugging')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.codex\skills\browser-debugging')) | Should -Be $false
    }

    It 'distributes all repository-owned portfolio engineering skills to each mapped loose-skill host' {
        $repositoryRegistry = Get-Content -LiteralPath (
            Join-Path (Split-Path -Parent $PSScriptRoot) 'registry\capabilities.json'
        ) -Raw | ConvertFrom-Json
        @($repositoryRegistry.capabilities | Where-Object {
            $_.id -eq 'portfolio-engineering-ops'
        }).Count | Should -Be 1

        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'portfolio-engineering-ops'
        )
        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        $mappedRoots = @(
            (Join-Path $fixture.UserProfile '.claude\skills'),
            (Join-Path $fixture.UserProfile '.codex\skills'),
            (Join-Path $fixture.UserProfile '.cline\skills')
        )
        foreach ($hostRoot in $mappedRoots) {
            foreach ($skillId in $global:canonicalPortfolioEngineeringSkills) {
                Test-Path (Join-Path $hostRoot "$skillId\SKILL.md") | Should -BeTrue
            }
        }
    }

    It 'quarantines shared Agent Skills shadows after deploying each mapped host copy' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'shared-agent-skills-shadow'
        )
        $canonicalRoot = Join-Path $fixture.RegistryRoot 'capabilities\shared-fixture'
        $canonicalSkill = Join-Path $canonicalRoot 'skills\shared-fixture-skill'
        New-Item -ItemType Directory -Path $canonicalSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonicalSkill 'SKILL.md') `
            -Value 'canonical:shared-fixture-skill' -Encoding UTF8

        $capabilitiesPath = Join-Path $fixture.RegistryRoot 'registry\capabilities.json'
        $registry = Get-Content -LiteralPath $capabilitiesPath -Raw | ConvertFrom-Json
        $registry.capabilities = @($registry.capabilities) + @(
            @{
                id = 'shared-fixture'
                canonicalSource = $canonicalRoot
                hostMappings = @(
                    @{ hostId = 'codex'; deploymentStatus = 'managed' },
                    @{ hostId = 'gemini'; deploymentStatus = 'managed' }
                )
            }
        )
        $registry | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        $sharedRoot = Join-Path $fixture.UserProfile '.agents\skills'
        $managedShadow = Join-Path $sharedRoot 'shared-fixture-skill'
        $unrelatedSkill = Join-Path $sharedRoot 'user-owned-skill'
        New-Item -ItemType Directory -Path $managedShadow -Force | Out-Null
        New-Item -ItemType Directory -Path $unrelatedSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $managedShadow 'SKILL.md') `
            -Value 'stale:shared-fixture-skill' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $unrelatedSkill 'SKILL.md') `
            -Value 'preserve:user-owned-skill' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        (Test-Path -LiteralPath $managedShadow) | Should -Be $false
        (Get-Content -LiteralPath (
            Join-Path $fixture.UserProfile '.codex\skills\shared-fixture-skill\SKILL.md'
        ) -Raw).Trim() | Should -Be 'canonical:shared-fixture-skill'
        (Get-Content -LiteralPath (
            Join-Path $fixture.UserProfile '.gemini\skills\shared-fixture-skill\SKILL.md'
        ) -Raw).Trim() | Should -Be 'canonical:shared-fixture-skill'
        (Get-Content -LiteralPath (Join-Path $unrelatedSkill 'SKILL.md') -Raw).Trim() |
            Should -Be 'preserve:user-owned-skill'

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifests = @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse)
        $manifests.Count | Should -Be 1
        $manifest = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
        @($manifest.entries | Where-Object {
            $_.hostId -eq 'shared-agent-skills' -and
            $_.artifactKind -eq 'skills' -and
            $_.artifactName -eq 'shared-fixture-skill'
        }).Count | Should -Be 1

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count |
            Should -Be $manifests.Count
    }

    It 'exactly replaces canonical siblings everywhere, quarantines mapped conflicts, and is idempotent' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'replacement')
        $skillTargets = @{
            claude = Join-Path $fixture.UserProfile '.claude\skills'
            codex = Join-Path $fixture.UserProfile '.codex\skills'
            cursor = Join-Path $fixture.UserProfile '.cursor\skills'
            opencode = Join-Path $fixture.UserProfile '.config\opencode\skills'
            factory = Join-Path $fixture.UserProfile '.factory\skills'
            devin = Join-Path $fixture.AppData 'devin\skills'
            amp = Join-Path $fixture.UserProfile '.config\amp\skills'
            windsurf = Join-Path $fixture.UserProfile '.codeium\windsurf\skills'
            gemini = Join-Path $fixture.UserProfile '.gemini\skills'
            hermes = Join-Path $fixture.UserProfile 'AppData\Local\hermes\skills'
            grok = Join-Path $fixture.UserProfile '.grok\skills'
            antigravity = Join-Path $fixture.UserProfile '.gemini\config\skills'
            warp = Join-Path $fixture.UserProfile '.warp\skills'
        }

        $staleManaged = Join-Path $skillTargets.claude 'product-demo-studio'
        New-Item -ItemType Directory -Path (Join-Path $staleManaged 'references') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staleManaged 'SKILL.md') -Value 'version:1' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $staleManaged 'references\retired-v1.md') -Value 'stale' -Encoding UTF8
        $mappedConflict = Join-Path $skillTargets.claude 'remotion-video-creation'
        New-Item -ItemType Directory -Path $mappedConflict -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $mappedConflict 'SKILL.md') -Value "---`nname: remotion-video-creation`n---`nlegacy" -Encoding UTF8
        $mappedPluginConflict = Join-Path $fixture.UserProfile '.claude\plugins\remotion-video-creation'
        New-Item -ItemType Directory -Path $mappedPluginConflict -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $mappedPluginConflict 'plugin.json') -Value '{"name":"remotion-video-creation"}' -Encoding UTF8
        $mappedExtensionConflict = Join-Path $fixture.UserProfile '.qwen\extensions\remotion-video-creation'
        New-Item -ItemType Directory -Path $mappedExtensionConflict -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $mappedExtensionConflict 'qwen-extension.json') -Value '{"name":"remotion-video-creation"}' -Encoding UTF8
        $unmappedVideoSkill = Join-Path $skillTargets.claude 'customer-video-caption-review'
        New-Item -ItemType Directory -Path $unmappedVideoSkill -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unmappedVideoSkill 'SKILL.md') -Value 'keep-me' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should -Be 0

        foreach ($target in $skillTargets.Values) {
            foreach ($name in $global:canonicalVideoSkills) {
                (Get-Content -LiteralPath (Join-Path $target "$name\SKILL.md") -Raw).Trim() | Should -Be "canonical:$name"
            }
            (Get-Content -LiteralPath (Join-Path $target 'product-demo-studio\references\portfolio-standard.md') -Raw).Trim() | Should -Be 'version:2'
            (Get-Content -LiteralPath (Join-Path $target 'product-demo-studio-remotion\rules\video-layout.md') -Raw).Trim() | Should -Be 'safe-area:80'
        }
        (Test-Path -LiteralPath (Join-Path $staleManaged 'references\retired-v1.md')) | Should -Be $false
        (Test-Path -LiteralPath $mappedConflict) | Should -Be $false
        (Test-Path -LiteralPath $mappedPluginConflict) | Should -Be $false
        (Test-Path -LiteralPath $mappedExtensionConflict) | Should -Be $false
        (Get-Content -LiteralPath (Join-Path $unmappedVideoSkill 'SKILL.md') -Raw).Trim() | Should -Be 'keep-me'
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.copilot\skills\product-demo-studio')) | Should -Be $false
        $copilotWrapper = Get-Content -LiteralPath (
            Join-Path $fixture.UserProfile 'bin\copilot.cmd'
        ) -Raw
        $copilotWrapper | Should -Match '--plugin-dir'
        $copilotAdapter = Join-Path $fixture.LocalAppData `
            'AgentHub\runtime\copilot\plugins\product-demo-studio'
        $copilotWrapper.Replace('\','/') | Should -Match `
            ([regex]::Escape($copilotAdapter.Replace('\','/')))
        Test-Path -LiteralPath (Join-Path $copilotAdapter '.mcp.json') |
            Should -BeFalse
        (Get-Content -LiteralPath (
            Join-Path $copilotAdapter 'skills\product-demo-studio\SKILL.md'
        ) -Raw).Trim() | Should -Be 'canonical:product-demo-studio'
        $vscodeSettings = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json') -Raw | ConvertFrom-Json
        $portablePluginPath = $fixture.CanonicalRoot.Replace('\','/')
        $vscodeSettings.'chat.pluginLocations'.$portablePluginPath | Should -Be $true

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifestsBefore = @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse)
        $manifestsBefore.Count | Should -Be 1
        $manifest = Get-Content -LiteralPath $manifestsBefore[0].FullName -Raw | ConvertFrom-Json
        @($manifest.entries | ForEach-Object { "$($_.artifactKind):$($_.artifactName)" } | Sort-Object) -join '|' |
            Should -Be 'extensions:remotion-video-creation|plugins:remotion-video-creation|skills:product-demo-studio|skills:remotion-video-creation'

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should -Be 0
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should -Be $manifestsBefore.Count
    }

    It 'removes stale empty directories from an otherwise current managed sibling' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'empty-directory-drift')
        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        $staleEmptyDirectory = Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio\references\retired-empty'
        New-Item -ItemType Directory -Path $staleEmptyDirectory -Force | Out-Null

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        (Test-Path -LiteralPath $staleEmptyDirectory) | Should -Be $false
        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should -Be 1
        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should -Be 1
    }

    It 'retires historical VS Code plugin locations without removing unrelated user entries' {
        $fixture = New-DistributionFixture -Root `
            (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'vscode-retired-locations')
        $settingsPath = Join-Path $fixture.UserProfile `
            'AppData\Roaming\Code - Insiders\User\settings.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $settingsPath) -Force |
            Out-Null
        @{
            'chat.pluginLocations' = @{
                'C:/Repos/agent-capabilities/packages/portfolio-plugins/clerk' = $true
                'C:/Repos/agenthub/packages/handoff-plugins/plugins/product-demo-studio' = $true
                'D:/user-owned/plugin' = $true
            }
        } | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $settingsPath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $locationNames = @($settings.'chat.pluginLocations'.PSObject.Properties.Name)
        $locationNames | Should -Not -Contain `
            'C:/Repos/agent-capabilities/packages/portfolio-plugins/clerk'
        $locationNames | Should -Not -Contain `
            'C:/Repos/agenthub/packages/handoff-plugins/plugins/product-demo-studio'
        $settings.'chat.pluginLocations'.'D:/user-owned/plugin' | Should -BeTrue
        $settings.'chat.pluginLocations'.$($fixture.CanonicalRoot.Replace('\','/')) |
            Should -BeTrue
    }

    It 'fails closed when a configured host has no allowlisted skill target' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'unknown-host')
        $profilePath = Join-Path $fixture.RegistryRoot 'registry\fleet-profile.json'
        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        $profile.managedHosts = @($profile.managedHosts) + 'future-agent'
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $profilePath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Not -Be 0
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio')) | Should -Be $false
    }

    It 'persists recovery metadata when a later distribution failure follows a quarantine move' {
        $fixture = New-DistributionFixture -Root (
            Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'failure-after-quarantine'
        )
        $staleManaged = Join-Path $fixture.UserProfile `
            '.claude\skills\product-demo-studio'
        New-Item -ItemType Directory -Path $staleManaged -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staleManaged 'SKILL.md') `
            -Value 'stale before late failure' -Encoding UTF8

        $capabilitiesPath = Join-Path $fixture.RegistryRoot `
            'registry\capabilities.json'
        $capabilities = Get-Content -LiteralPath $capabilitiesPath -Raw |
            ConvertFrom-Json
        $browserCapability = @($capabilities.capabilities |
            Where-Object id -eq 'browser-toolkit')[0]
        @($browserCapability.hostMappings |
            Where-Object hostId -eq 'claude')[0].deploymentStatus =
            'unsupported-test-status'
        $capabilities | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $capabilitiesPath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Not -Be 0

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifests = @(Get-ChildItem -LiteralPath $quarantineRoot `
            -Filter manifest.json -File -Recurse)
        $manifests.Count | Should -Be 1
        $manifest = Get-Content -LiteralPath $manifests[0].FullName -Raw |
            ConvertFrom-Json
        $movedEntry = @($manifest.entries | Where-Object {
            $_.sourcePath -eq [IO.Path]::GetFullPath($staleManaged) -and
            $_.hostId -eq 'claude' -and
            $_.artifactKind -eq 'skills' -and
            $_.artifactName -eq 'product-demo-studio'
        })
        $movedEntry.Count | Should -Be 1
        Test-Path -LiteralPath $movedEntry[0].quarantinePath |
            Should -BeTrue
    }

    It 'preserves a future canonical plugin cache that does not match the retired signature' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'future-cache')
        $futureCache = Join-Path $fixture.UserProfile '.claude\plugins\cache\handoff\product-demo-studio\0.3.0'
        New-Item -ItemType Directory -Path $futureCache -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $futureCache 'marker.txt') -Value 'keep-future-canonical' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        (Get-Content -LiteralPath (Join-Path $futureCache 'marker.txt') -Raw).Trim() | Should -Be 'keep-future-canonical'
    }

    It 'preserves exact-named conflicts without an audited legacy signature' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'unsigned-conflict')
        $unsigned = Join-Path $fixture.UserProfile '.claude\skills\remotion-video-creation'
        New-Item -ItemType Directory -Path $unsigned -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unsigned 'SKILL.md') -Value "---`nname: custom-remotion-helper`n---`nkeep" -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should -Be 0

        (Test-Path -LiteralPath $unsigned) | Should -Be $true
    }

    It 'self-heals a missing Qwen native extension junction' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'qwen-self-heal')
        $extension = Join-Path $fixture.UserProfile '.qwen\extensions\agenthub-product-demo-studio'
        Remove-Item -LiteralPath $extension -Recurse -Force

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        $extensionItem = Get-Item -LiteralPath $extension -Force
        $extensionItem.LinkType | Should -Be 'Junction'
        [IO.Path]::GetFullPath([string]$extensionItem.Target) | Should -Be (
            [IO.Path]::GetFullPath((Join-Path $fixture.LocalAppData `
                'AgentHub\runtime\qwen-code\extensions\agenthub-product-demo-studio'))
        )
        foreach ($name in $global:canonicalVideoSkills) {
            (Get-Content -LiteralPath (Join-Path $extension "skills\$name\SKILL.md") -Raw).Trim() | Should -Be "canonical:$name"
        }
    }
}

Describe 'Apply-FullAccessAgentProfile managed product experience distribution' {
    It 'uses native plugin locations and exact loose-skill trees without duplicating the Qwen extension' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'product-experience')
        $looseSkillTargets = @(
            (Join-Path $fixture.UserProfile '.claude\skills'),
            (Join-Path $fixture.UserProfile '.codex\skills'),
            (Join-Path $fixture.UserProfile '.cursor\skills'),
            (Join-Path $fixture.UserProfile '.config\opencode\skills'),
            (Join-Path $fixture.UserProfile '.factory\skills'),
            (Join-Path $fixture.AppData 'devin\skills'),
            (Join-Path $fixture.UserProfile '.config\amp\skills'),
            (Join-Path $fixture.UserProfile '.codeium\windsurf\skills'),
            (Join-Path $fixture.UserProfile '.gemini\skills'),
            (Join-Path $fixture.UserProfile 'AppData\Local\hermes\skills'),
            (Join-Path $fixture.UserProfile '.grok\skills'),
            (Join-Path $fixture.UserProfile '.gemini\config\skills'),
            (Join-Path $fixture.UserProfile '.warp\skills')
        )

        $staleManaged = Join-Path $looseSkillTargets[0] 'engineer-product-experience'
        New-Item -ItemType Directory -Path (Join-Path $staleManaged 'references') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $staleManaged 'SKILL.md') -Value 'version:personal' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $staleManaged 'references\retired-personal.md') -Value 'stale' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        foreach ($target in $looseSkillTargets) {
            foreach ($name in $global:canonicalExperienceSkills) {
                (Get-Content -LiteralPath (Join-Path $target "$name\SKILL.md") -Raw).Trim() | Should -Be "canonical:$name"
            }
            (Get-Content -LiteralPath (Join-Path $target 'engineer-product-experience\references\surface-coverage.md') -Raw).Trim() |
                Should -Be 'coverage:complete'
        }
        (Test-Path -LiteralPath (Join-Path $staleManaged 'references\retired-personal.md')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.copilot\skills\engineer-product-experience')) | Should -Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.qwen\skills\engineer-product-experience')) | Should -Be $false

        $copilotWrapper = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'bin\copilot.cmd') -Raw
        $copilotAdapterRoot = Join-Path $fixture.LocalAppData `
            'AgentHub\runtime\copilot\plugins'
        $copilotWrapper.Replace('\','/') | Should -Match ([regex]::Escape(
            (Join-Path $copilotAdapterRoot 'product-demo-studio').Replace('\','/')
        ))
        $copilotWrapper.Replace('\','/') | Should -Match ([regex]::Escape(
            (Join-Path $copilotAdapterRoot 'product-experience-engineering').Replace('\','/')
        ))
        $vscodeSettings = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json') -Raw | ConvertFrom-Json
        $vscodeSettings.'chat.pluginLocations'.$($fixture.CanonicalExperienceRoot.Replace('\','/')) | Should -Be $true

        $qwenExtension = Join-Path $fixture.UserProfile '.qwen\extensions\agenthub-product-experience-engineering'
        foreach ($name in $global:canonicalExperienceSkills) {
            (Get-Content -LiteralPath (Join-Path $qwenExtension "skills\$name\SKILL.md") -Raw).Trim() | Should -Be "canonical:$name"
        }
    }

    It 'removes loose duplicates when current Claude and Codex native plugins are enabled' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'product-experience-native')
        $claudeInstalledPath = Join-Path $fixture.UserProfile '.claude\plugins\installed_plugins.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeInstalledPath) -Force | Out-Null
        @{
            plugins = @{
                'product-experience-engineering@handoff' = @(@{
                    scope = 'user'
                    installPath = $fixture.CanonicalExperienceRoot
                    version = '1.1.0'
                })
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $claudeInstalledPath -Encoding UTF8
        @{
            enabledPlugins = @{
                'product-experience-engineering@handoff' = $true
            }
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $fixture.UserProfile '.claude\settings.json') -Encoding UTF8

        $codexConfig = Join-Path $fixture.UserProfile '.codex\config.toml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $codexConfig) -Force | Out-Null
        "[plugins.`"product-experience-engineering@handoff`"]`nenabled = true" |
            Set-Content -LiteralPath $codexConfig -Encoding UTF8
        $codexCache = Join-Path $fixture.UserProfile '.codex\plugins\cache\handoff\product-experience-engineering\1.1.0'
        New-Item -ItemType Directory -Path (Split-Path -Parent $codexCache) -Force | Out-Null
        Copy-Item -LiteralPath $fixture.CanonicalExperienceRoot -Destination $codexCache -Recurse
        New-Item -ItemType Directory -Path (Join-Path $codexCache '.in_use') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $codexCache '.in_use\live-session') -Value 'ephemeral' -Encoding UTF8

        foreach ($target in @(
            (Join-Path $fixture.UserProfile '.claude\skills'),
            (Join-Path $fixture.UserProfile '.codex\skills')
        )) {
            foreach ($name in $global:canonicalExperienceSkills) {
                $skillRoot = Join-Path $target $name
                New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value 'duplicate-loose-copy' -Encoding UTF8
            }
        }

        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        foreach ($target in @(
            (Join-Path $fixture.UserProfile '.claude\skills'),
            (Join-Path $fixture.UserProfile '.codex\skills')
        )) {
            foreach ($name in $global:canonicalExperienceSkills) {
                (Test-Path -LiteralPath (Join-Path $target $name)) | Should -Be $false
            }
        }
    }
}

Describe 'Apply-FullAccessAgentProfile dependency artifact exclusion' {
    It 'treats a capability with node_modules as equivalent to one without' {
        $fixture = New-DistributionFixture -Root (Join-Path $env:AGENTHUB_PROFILE_TEST_DIRECTORY 'node-modules-exclusion')
        # Add node_modules to the canonical source so it would normally cause drift
        $videoSkill = Join-Path $fixture.CanonicalRoot 'skills\product-demo-studio'
        $nodeModules = Join-Path $videoSkill 'node_modules'
        New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $nodeModules 'package.js') -Value 'runtime artifact' -Encoding UTF8

        # Deploy once to get the canonical skill without node_modules
        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        # The deployed skill should be considered current despite node_modules
        # being in the source. Run again - it should be idempotent (exit 0).
        (Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0

        # Verify node_modules was NOT copied to the destination
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio\node_modules')) | Should -Be $false
    }
}

Describe 'Apply-FullAccessAgentProfile Qoder plugin convergence' {
    BeforeAll {
        $script:applyProfileSource = Get-Content -LiteralPath $global:AgentHubApplyScriptPath -Raw -Encoding UTF8
    }

    It 'upgrades stale native plugins and verifies the installed package contents' {
        $script:applyProfileSource | Should -Match 'function Test-QoderPluginEquivalent'
        $script:applyProfileSource | Should -Match 'plugins uninstall --scope user'
        $script:applyProfileSource | Should -Match 'plugins install --scope user'
        $script:applyProfileSource | Should -Match 'remains content-stale after reconciliation'
    }

    It 'retires duplicate loose skills after the final AgentHub synchronization' {
        $script:applyProfileSource | Should -Match 'function Retire-QoderNativePluginLooseSkills'
        $finalSyncIndex = $script:applyProfileSource.LastIndexOf("Sync-AgentHub.ps1")
        $finalRetirementIndex = $script:applyProfileSource.LastIndexOf('Retire-QoderNativePluginLooseSkills')
        $finalSyncIndex | Should -BeGreaterThan -1
        $finalRetirementIndex | Should -BeGreaterThan $finalSyncIndex
    }
}
