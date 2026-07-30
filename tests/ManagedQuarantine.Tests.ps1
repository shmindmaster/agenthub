BeforeAll {
    $script:managedQuarantinePath = Join-Path (
        Split-Path -Parent $PSScriptRoot
    ) 'scripts\ManagedQuarantine.ps1'
    if (Test-Path -LiteralPath $script:managedQuarantinePath -PathType Leaf) {
        . $script:managedQuarantinePath
    }

    function New-AgentHubTestJunctionOrSkip {
        param(
            [Parameter(Mandatory)]
            [string]$Path,
            [Parameter(Mandatory)]
            [string]$Target
        )

        try {
            return New-Item -ItemType Junction -Path $Path -Target $Target `
                -ErrorAction Stop
        } catch {
            $junctionDenied = $_.Exception -is [UnauthorizedAccessException] -or
                $_.Exception -is [PlatformNotSupportedException] -or
                $_.Exception -is [NotSupportedException] -or
                $_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::PermissionDenied -or
                $_.Exception.Message -match '(?i)privilege.*not held|junction.*not supported'
            if (-not $junctionDenied) {
                throw
            }

            $reason = "The operating system denied synthetic junction creation: $($_.Exception.Message)"
            if (Get-Command Set-ItResult -ErrorAction SilentlyContinue) {
                Set-ItResult -Skipped -Because $reason
                return $null
            }
            if (Get-Command Set-TestInconclusive -ErrorAction SilentlyContinue) {
                Set-TestInconclusive $reason
                return $null
            }
            throw $reason
        }
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
        Test-Path -LiteralPath $expectedManifestPath | Should -BeTrue
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

    It 'refuses an in-profile source junction that resolves outside the approved profile' {
        $profile = Join-Path $TestDrive 'source-junction-profile'
        $outside = Join-Path $TestDrive 'outside-source'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $source
        ), $outside -Force | Out-Null
        $outsideMarker = Join-Path $outside 'marker.txt'
        Set-Content -LiteralPath $outsideMarker -Value 'preserve outside source' `
            -Encoding UTF8
        $junction = New-AgentHubTestJunctionOrSkip -Path $source -Target $outside
        if ($null -eq $junction) {
            return
        }
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Outside junction targets are forbidden.' -ContentHash ('B' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        Test-Path -LiteralPath $outside | Should -BeTrue
        (Get-Content -LiteralPath $outsideMarker -Raw).Trim() |
            Should -Be 'preserve outside source'
        Test-Path -LiteralPath (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        ) | Should -BeFalse
    }

    It 'refuses a quarantine destination that traverses a junction outside the approved profile' {
        $profile = Join-Path $TestDrive 'destination-junction-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        $outside = Join-Path $TestDrive 'outside-destination'
        New-Item -ItemType Directory -Path $source, $outside -Force | Out-Null
        $sourceMarker = Join-Path $source 'SKILL.md'
        $outsideMarker = Join-Path $outside 'marker.txt'
        Set-Content -LiteralPath $sourceMarker -Value 'preserve source' -Encoding UTF8
        Set-Content -LiteralPath $outsideMarker -Value 'preserve outside destination' `
            -Encoding UTF8
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        New-Item -ItemType Directory -Path $batch.BatchRoot -Force | Out-Null
        $destinationAncestor = Join-Path $batch.BatchRoot 'fixture-host'
        $junction = New-AgentHubTestJunctionOrSkip `
            -Path $destinationAncestor -Target $outside
        if ($null -eq $junction) {
            return
        }

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Outside destination junctions are forbidden.' `
                -ContentHash ('C' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        (Get-Content -LiteralPath $sourceMarker -Raw).Trim() |
            Should -Be 'preserve source'
        (Get-Content -LiteralPath $outsideMarker -Raw).Trim() |
            Should -Be 'preserve outside destination'
        Test-Path -LiteralPath (Join-Path $outside 'skills') | Should -BeFalse
        (Get-Item -LiteralPath $destinationAncestor -Force).LinkType |
            Should -Be 'Junction'
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

    It 'rejects a SHA-256 hash with a trailing line feed before moving the source' {
        $profile = Join-Path $TestDrive 'line-feed-hash-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Trailing line feed fixture.' `
                -ContentHash (('E' * 64) + "`n")
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
    }

    It 'rejects dot metadata segments and reserved manifest collisions before moving' {
        $cases = @(
            @{
                Root = 'dot-kind'
                HostId = 'fixture-host'
                ArtifactKind = '.'
                ArtifactName = 'fixture'
            },
            @{
                Root = 'dot-dot-manifest'
                HostId = 'fixture-host'
                ArtifactKind = '..'
                ArtifactName = 'manifest.json'
            }
        )

        foreach ($case in $cases) {
            $profile = Join-Path $TestDrive "$($case.Root)-profile"
            $source = Join-Path $profile '.host\skills\fixture'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            $sourceMarker = Join-Path $source 'SKILL.md'
            Set-Content -LiteralPath $sourceMarker -Value 'preserve source' `
                -Encoding UTF8
            $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

            {
                Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                    -HostId $case.HostId -ArtifactKind $case.ArtifactKind `
                    -ArtifactName $case.ArtifactName `
                    -Reason 'Dot segments are forbidden.' -ContentHash ('F' * 64)
            } | Should -Throw

            Test-Path -LiteralPath $source | Should -BeTrue
            (Get-Content -LiteralPath $sourceMarker -Raw).Trim() |
                Should -Be 'preserve source'
            Test-Path -LiteralPath (
                Join-Path $batch.BatchRoot 'manifest.json'
            ) | Should -BeFalse
        }
    }

    It 'persists the same recoverable manifest after each move and finalizes it once' {
        $profile = Join-Path $TestDrive 'incremental-manifest-profile'
        $firstSource = Join-Path $profile '.host\skills\first'
        $secondSource = Join-Path $profile '.host\skills\second'
        New-Item -ItemType Directory -Path $firstSource, $secondSource -Force |
            Out-Null
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        $manifestPath = Join-Path $batch.BatchRoot 'manifest.json'

        Move-ToAgentHubQuarantine -Batch $batch -Path $firstSource `
            -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'first' `
            -Reason 'First synthetic move.' -ContentHash ('1' * 64) | Out-Null

        Test-Path -LiteralPath $manifestPath | Should -BeTrue
        $firstManifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json
        @($firstManifest.entries).Count | Should -Be 1
        @($firstManifest.entries)[0].artifactName | Should -Be 'first'

        Move-ToAgentHubQuarantine -Batch $batch -Path $secondSource `
            -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'second' `
            -Reason 'Second synthetic move.' -ContentHash ('2' * 64) | Out-Null

        Test-Path -LiteralPath $manifestPath | Should -BeTrue
        $secondManifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json
        @($secondManifest.entries).Count | Should -Be 2
        @($secondManifest.entries | ForEach-Object artifactName | Sort-Object) -join ',' |
            Should -Be 'first,second'

        Write-AgentHubQuarantineManifest -Batch $batch |
            Should -Be $manifestPath
        $batch.ManifestWritten | Should -BeTrue
        @(Get-ChildItem -LiteralPath $batch.BatchRoot -Filter manifest.json -File).Count |
            Should -Be 1
    }
}
