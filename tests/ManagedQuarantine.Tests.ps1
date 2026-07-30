BeforeAll {
    $script:managedQuarantinePath = Join-Path (
        Split-Path -Parent $PSScriptRoot
    ) 'scripts\ManagedQuarantine.ps1'
    if (Test-Path -LiteralPath $script:managedQuarantinePath -PathType Leaf) {
        . $script:managedQuarantinePath
    }
}

Describe 'AgentHub managed quarantine' {
    It 'moves only the exact artifact and records a recoverable manifest' {
        $profile = Join-Path $TestDrive 'profile'
        $source = Join-Path $profile '.host\skills\fixture'
        $untouched = Join-Path $profile '.host\skills\untouched'
        New-Item -ItemType Directory -Path (
            Join-Path $source 'references'
        ), $untouched -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'SKILL.md') `
            -Value 'fixture skill' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $source 'references\usage.md') `
            -Value 'fixture reference' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $untouched 'SKILL.md') `
            -Value 'keep me' -Encoding UTF8

        $contentHash = 'A' * 64
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        $quarantinePath = Move-ToAgentHubQuarantine -Batch $batch -Path $source `
            -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
            -Reason 'Synthetic superseded fixture.' -ContentHash $contentHash

        Test-Path -LiteralPath $source | Should -BeFalse
        Test-Path -LiteralPath $untouched | Should -BeTrue
        $quarantinePath | Should -Be (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        )
        Test-Path -LiteralPath (Join-Path $quarantinePath 'SKILL.md') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $quarantinePath 'references\usage.md') |
            Should -BeTrue

        $expectedManifestPath = Join-Path $batch.BatchRoot 'manifest.json'
        Test-Path -LiteralPath $expectedManifestPath | Should -BeFalse
        $manifestPath = Write-AgentHubQuarantineManifest -Batch $batch
        $manifestPath | Should -Be $expectedManifestPath
        @(Get-ChildItem -LiteralPath $batch.BatchRoot -Filter manifest.json -File).Count |
            Should -Be 1

        $manifestJson = Get-Content -LiteralPath $manifestPath -Raw
        $manifestJson | Should -Match '"quarantinedAtUtc"\s*:\s*"[^"]+Z"'
        $manifestJson | Should -Match '"createdAtUtc"\s*:\s*"[^"]+Z"'
        $manifest = $manifestJson | ConvertFrom-Json
        @($manifest.entries).Count | Should -Be 1
        $entry = @($manifest.entries)[0]
        $entry.sourcePath | Should -Be ([IO.Path]::GetFullPath($source))
        $entry.quarantinePath | Should -Be ([IO.Path]::GetFullPath($quarantinePath))
        $entry.hostId | Should -Be 'fixture-host'
        $entry.artifactKind | Should -Be 'skills'
        $entry.artifactName | Should -Be 'fixture'
        $entry.reason | Should -Be 'Synthetic superseded fixture.'
        $entry.contentHash | Should -Be $contentHash
    }

    It 'refuses a source outside the approved user profile' {
        $profile = Join-Path $TestDrive 'approved-profile'
        $outside = Join-Path $TestDrive 'sibling\fixture'
        New-Item -ItemType Directory -Path $profile, $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'SKILL.md') `
            -Value 'outside fixture' -Encoding UTF8
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $outside `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Must remain outside.' -ContentHash ('B' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $outside | Should -BeTrue
        Test-Path -LiteralPath (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        ) | Should -BeFalse
    }

    It 'does not overwrite an existing quarantine destination' {
        $profile = Join-Path $TestDrive 'collision-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'SKILL.md') `
            -Value 'source fixture' -Encoding UTF8
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        $destination = Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'marker.txt') `
            -Value 'preserve destination' -Encoding UTF8

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Would collide.' -ContentHash ('C' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $destination 'marker.txt') -Raw).Trim() |
            Should -Be 'preserve destination'
    }

    It 'rejects an empty quarantine reason before moving the source' {
        $profile = Join-Path $TestDrive 'empty-reason-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason ' ' -ContentHash ('D' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
    }

    It 'rejects a malformed content hash before moving the source' {
        $profile = Join-Path $TestDrive 'invalid-hash-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Malformed hash fixture.' -ContentHash 'not-a-sha256'
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
    }
}
