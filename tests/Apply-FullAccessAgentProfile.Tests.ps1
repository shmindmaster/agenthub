$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Apply-FullAccessAgentProfile.ps1'
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source

$canonicalVideoSkills = @(
    'product-demo-studio',
    'product-demo-studio-capture',
    'product-demo-studio-descript',
    'product-demo-studio-narration',
    'product-demo-studio-qa',
    'product-demo-studio-remotion',
    'product-demo-studio-render',
    'product-demo-studio-visual-assets'
)

$canonicalExperienceSkills = @(
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

function New-DistributionFixture {
    param([string]$Root)

    $registryRoot = Join-Path $Root 'registry-root'
    $canonicalRoot = Join-Path $Root 'canonical-product-demo-studio'
    $canonicalExperienceRoot = Join-Path $Root 'canonical-product-experience-engineering'
    $canonicalBrowserRoot = Join-Path $Root 'canonical-browser-toolkit'
    $fakeProfile = Join-Path $Root 'profile'
    $fakeAppData = Join-Path $fakeProfile 'AppData\Roaming'
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

    foreach ($name in $canonicalVideoSkills) {
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
    foreach ($name in $canonicalExperienceSkills) {
        $skillRoot = Join-Path $canonicalExperienceRoot "skills\$name"
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
    $qwenAdapterRoot = Join-Path $registryRoot 'adapters\qwen-code\extensions\agenthub-product-demo-studio'
    New-Item -ItemType Directory -Path (Join-Path $qwenAdapterRoot 'skills') -Force | Out-Null
    '{"name":"agenthub-product-demo-studio","version":"1.0.0","skills":"skills"}' |
        Set-Content -LiteralPath (Join-Path $qwenAdapterRoot 'qwen-extension.json') -Encoding UTF8
    foreach ($name in $canonicalVideoSkills) {
        Copy-Item -LiteralPath (Join-Path $canonicalRoot "skills\$name") -Destination $qwenExtensionSkills -Recurse
        Copy-Item -LiteralPath (Join-Path $canonicalRoot "skills\$name") -Destination (Join-Path $qwenAdapterRoot 'skills') -Recurse
    }
    $qwenExperienceExtensionSkills = Join-Path $fakeProfile '.qwen\extensions\agenthub-product-experience-engineering\skills'
    New-Item -ItemType Directory -Path $qwenExperienceExtensionSkills -Force | Out-Null
    $qwenExperienceAdapterRoot = Join-Path $registryRoot 'adapters\qwen-code\extensions\agenthub-product-experience-engineering'
    New-Item -ItemType Directory -Path (Join-Path $qwenExperienceAdapterRoot 'skills') -Force | Out-Null
    '{"name":"agenthub-product-experience-engineering","version":"1.0.0","skills":"skills"}' |
        Set-Content -LiteralPath (Join-Path $qwenExperienceAdapterRoot 'qwen-extension.json') -Encoding UTF8
    foreach ($name in $canonicalExperienceSkills) {
        Copy-Item -LiteralPath (Join-Path $canonicalExperienceRoot "skills\$name") -Destination $qwenExperienceExtensionSkills -Recurse
        Copy-Item -LiteralPath (Join-Path $canonicalExperienceRoot "skills\$name") -Destination (Join-Path $qwenExperienceAdapterRoot 'skills') -Recurse
    }

    @{ mcpServers = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $registryRoot 'registry\mcps.json') -Encoding UTF8
    @{ capabilities = @(
        @{ id = 'product-demo-studio'; canonicalSource = $canonicalRoot },
        @{ id = 'product-experience-engineering'; canonicalSource = $canonicalExperienceRoot },
        @{ id = 'browser-toolkit'; canonicalSource = $canonicalBrowserRoot; managedSkillNames = @('browser-debugging'); hostMappings = @(
            @{ hostId = 'claude'; deploymentStatus = 'managed-loose-skills-and-mcp' }
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
        UserProfile = $fakeProfile
        AppData = $fakeAppData
    }
}

function Invoke-DistributionOnly {
    param([hashtable]$Fixture, [switch]$RetireLegacyVideoOwners)

    $previousAppData = $env:APPDATA
    try {
        $env:APPDATA = $Fixture.AppData
        $arguments = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$scriptPath,
            '-RegistryRoot',$Fixture.RegistryRoot,'-UserProfile',$Fixture.UserProfile,'-SkillDistributionOnly')
        if ($RetireLegacyVideoOwners) { $arguments += '-RetireLegacyVideoOwners' }
        & $powershell @arguments | Out-Host
        return $LASTEXITCODE
    } finally {
        $env:APPDATA = $previousAppData
    }
}

Describe 'Apply-FullAccessAgentProfile managed video distribution' {
    It 'preserves an expected Browser Toolkit junction during generic skill distribution' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'expected-junction')
        $browserTarget = Join-Path $fixture.UserProfile '.claude\skills\browser-debugging'
        New-Item -ItemType Directory -Path (Split-Path -Parent $browserTarget) -Force | Out-Null
        New-Item -ItemType Junction -Path $browserTarget -Target (Join-Path $fixture.CanonicalBrowserRoot 'skills\browser-debugging') | Out-Null

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0
        (Get-Item -LiteralPath $browserTarget -Force).LinkType | Should Be 'Junction'
        (Get-Content -LiteralPath (Join-Path $browserTarget 'SKILL.md') -Raw).Trim() | Should Be 'canonical:browser-debugging'
    }

    It 'does not distribute a canonical capability to hosts without a registry mapping' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'mapping-boundary')

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\browser-debugging')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.codex\skills\browser-debugging')) | Should Be $false
    }

    It 'exactly replaces canonical siblings everywhere, quarantines mapped conflicts, and is idempotent' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'replacement')
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

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should Be 0

        foreach ($target in $skillTargets.Values) {
            foreach ($name in $canonicalVideoSkills) {
                (Get-Content -LiteralPath (Join-Path $target "$name\SKILL.md") -Raw).Trim() | Should Be "canonical:$name"
            }
            (Get-Content -LiteralPath (Join-Path $target 'product-demo-studio\references\portfolio-standard.md') -Raw).Trim() | Should Be 'version:2'
            (Get-Content -LiteralPath (Join-Path $target 'product-demo-studio-remotion\rules\video-layout.md') -Raw).Trim() | Should Be 'safe-area:80'
        }
        (Test-Path -LiteralPath (Join-Path $staleManaged 'references\retired-v1.md')) | Should Be $false
        (Test-Path -LiteralPath $mappedConflict) | Should Be $false
        (Test-Path -LiteralPath $mappedPluginConflict) | Should Be $false
        (Test-Path -LiteralPath $mappedExtensionConflict) | Should Be $false
        (Get-Content -LiteralPath (Join-Path $unmappedVideoSkill 'SKILL.md') -Raw).Trim() | Should Be 'keep-me'
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.copilot\skills\product-demo-studio')) | Should Be $false
        (Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'bin\copilot.cmd') -Raw) | Should Match '--plugin-dir'
        $vscodeSettings = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json') -Raw | ConvertFrom-Json
        $portablePluginPath = $fixture.CanonicalRoot.Replace('\','/')
        $vscodeSettings.'chat.pluginLocations'.$portablePluginPath | Should Be $true

        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        $manifestsBefore = @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse)
        $manifestsBefore.Count | Should Be 1
        $manifest = Get-Content -LiteralPath $manifestsBefore[0].FullName -Raw | ConvertFrom-Json
        @($manifest.entries | ForEach-Object { "$($_.artifactKind):$($_.artifactName)" } | Sort-Object) -join '|' |
            Should Be 'extensions:remotion-video-creation|plugins:remotion-video-creation|skills:product-demo-studio|skills:remotion-video-creation'

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should Be 0
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should Be $manifestsBefore.Count
    }

    It 'removes stale empty directories from an otherwise current managed sibling' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'empty-directory-drift')
        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0
        $staleEmptyDirectory = Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio\references\retired-empty'
        New-Item -ItemType Directory -Path $staleEmptyDirectory -Force | Out-Null

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        (Test-Path -LiteralPath $staleEmptyDirectory) | Should Be $false
        $quarantineRoot = Join-Path $fixture.UserProfile '.agenthub\quarantine'
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should Be 1
        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0
        @(Get-ChildItem -LiteralPath $quarantineRoot -Filter manifest.json -File -Recurse).Count | Should Be 1
    }

    It 'fails closed when a configured host has no allowlisted skill target' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'unknown-host')
        $profilePath = Join-Path $fixture.RegistryRoot 'registry\fleet-profile.json'
        $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
        $profile.managedHosts = @($profile.managedHosts) + 'future-agent'
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $profilePath -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should Not Be 0
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio')) | Should Be $false
    }

    It 'preserves a future canonical plugin cache that does not match the retired signature' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'future-cache')
        $futureCache = Join-Path $fixture.UserProfile '.claude\plugins\cache\handoff\product-demo-studio\0.3.0'
        New-Item -ItemType Directory -Path $futureCache -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $futureCache 'marker.txt') -Value 'keep-future-canonical' -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        (Get-Content -LiteralPath (Join-Path $futureCache 'marker.txt') -Raw).Trim() | Should Be 'keep-future-canonical'
    }

    It 'preserves exact-named conflicts without an audited legacy signature' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'unsigned-conflict')
        $unsigned = Join-Path $fixture.UserProfile '.claude\skills\remotion-video-creation'
        New-Item -ItemType Directory -Path $unsigned -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unsigned 'SKILL.md') -Value "---`nname: custom-remotion-helper`n---`nkeep" -Encoding UTF8

        (Invoke-DistributionOnly -Fixture $fixture -RetireLegacyVideoOwners) | Should Be 0

        (Test-Path -LiteralPath $unsigned) | Should Be $true
    }

    It 'self-heals a missing Qwen native extension junction' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'qwen-self-heal')
        $extension = Join-Path $fixture.UserProfile '.qwen\extensions\agenthub-product-demo-studio'
        Remove-Item -LiteralPath $extension -Recurse -Force

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        (Get-Item -LiteralPath $extension).LinkType | Should Be 'Junction'
        foreach ($name in $canonicalVideoSkills) {
            (Get-Content -LiteralPath (Join-Path $extension "skills\$name\SKILL.md") -Raw).Trim() | Should Be "canonical:$name"
        }
    }
}

Describe 'Apply-FullAccessAgentProfile managed product experience distribution' {
    It 'uses native plugin locations and exact loose-skill trees without duplicating the Qwen extension' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'product-experience')
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

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        foreach ($target in $looseSkillTargets) {
            foreach ($name in $canonicalExperienceSkills) {
                (Get-Content -LiteralPath (Join-Path $target "$name\SKILL.md") -Raw).Trim() | Should Be "canonical:$name"
            }
            (Get-Content -LiteralPath (Join-Path $target 'engineer-product-experience\references\surface-coverage.md') -Raw).Trim() |
                Should Be 'coverage:complete'
        }
        (Test-Path -LiteralPath (Join-Path $staleManaged 'references\retired-personal.md')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.copilot\skills\engineer-product-experience')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.qwen\skills\engineer-product-experience')) | Should Be $false

        $copilotWrapper = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'bin\copilot.cmd') -Raw
        $copilotWrapper | Should Match ([regex]::Escape($fixture.CanonicalRoot))
        $copilotWrapper | Should Match ([regex]::Escape($fixture.CanonicalExperienceRoot))
        $vscodeSettings = Get-Content -LiteralPath (Join-Path $fixture.UserProfile 'AppData\Roaming\Code - Insiders\User\settings.json') -Raw | ConvertFrom-Json
        $vscodeSettings.'chat.pluginLocations'.$($fixture.CanonicalExperienceRoot.Replace('\','/')) | Should Be $true

        $qwenExtension = Join-Path $fixture.UserProfile '.qwen\extensions\agenthub-product-experience-engineering'
        foreach ($name in $canonicalExperienceSkills) {
            (Get-Content -LiteralPath (Join-Path $qwenExtension "skills\$name\SKILL.md") -Raw).Trim() | Should Be "canonical:$name"
        }
    }

    It 'removes loose duplicates when current Claude and Codex native plugins are enabled' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'product-experience-native')
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
            foreach ($name in $canonicalExperienceSkills) {
                $skillRoot = Join-Path $target $name
                New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value 'duplicate-loose-copy' -Encoding UTF8
            }
        }

        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        foreach ($target in @(
            (Join-Path $fixture.UserProfile '.claude\skills'),
            (Join-Path $fixture.UserProfile '.codex\skills')
        )) {
            foreach ($name in $canonicalExperienceSkills) {
                (Test-Path -LiteralPath (Join-Path $target $name)) | Should Be $false
            }
        }
    }
}

Describe 'Apply-FullAccessAgentProfile dependency artifact exclusion' {
    It 'treats a capability with node_modules as equivalent to one without' {
        $fixture = New-DistributionFixture -Root (Join-Path $TestDrive 'node-modules-exclusion')
        # Add node_modules to the canonical source so it would normally cause drift
        $videoSkill = Join-Path $fixture.CanonicalRoot 'skills\product-demo-studio'
        $nodeModules = Join-Path $videoSkill 'node_modules'
        New-Item -ItemType Directory -Path $nodeModules -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $nodeModules 'package.js') -Value 'runtime artifact' -Encoding UTF8

        # Deploy once to get the canonical skill without node_modules
        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        # The deployed skill should be considered current despite node_modules
        # being in the source. Run again - it should be idempotent (exit 0).
        (Invoke-DistributionOnly -Fixture $fixture) | Should Be 0

        # Verify node_modules was NOT copied to the destination
        (Test-Path -LiteralPath (Join-Path $fixture.UserProfile '.claude\skills\product-demo-studio\node_modules')) | Should Be $false
    }
}
