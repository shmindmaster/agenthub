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

    It 'refuses a chained source junction that eventually resolves outside the approved profile' {
        $profile = Join-Path $TestDrive 'source-junction-chain-profile'
        $outside = Join-Path $TestDrive 'outside-source-chain'
        $source = Join-Path $profile '.host\skills\fixture'
        $inProfileHop = Join-Path $profile '.links\outside-hop'
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $source
        ), (Split-Path -Parent $inProfileHop), $outside -Force | Out-Null
        $outsideMarker = Join-Path $outside 'marker.txt'
        Set-Content -LiteralPath $outsideMarker -Value 'preserve chained outside source' `
            -Encoding UTF8
        $outsideJunction = New-AgentHubTestJunctionOrSkip `
            -Path $inProfileHop -Target $outside
        if ($null -eq $outsideJunction) {
            return
        }
        $sourceJunction = New-AgentHubTestJunctionOrSkip `
            -Path $source -Target $inProfileHop
        if ($null -eq $sourceJunction) {
            return
        }
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Chained outside junction targets are forbidden.' `
                -ContentHash ('B' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        Test-Path -LiteralPath $inProfileHop | Should -BeTrue
        (Get-Content -LiteralPath $outsideMarker -Raw).Trim() |
            Should -Be 'preserve chained outside source'
        Test-Path -LiteralPath (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        ) | Should -BeFalse
        @($batch.Entries).Count | Should -Be 0
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

    It 'refuses a chained quarantine destination with a nonexistent tail that eventually resolves outside the approved profile' {
        $profile = Join-Path $TestDrive 'destination-junction-chain-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        $insideRedirect = Join-Path $profile '.redirect'
        $outside = Join-Path $TestDrive 'outside-destination-chain'
        New-Item -ItemType Directory -Path $source, $insideRedirect, $outside -Force |
            Out-Null
        $sourceMarker = Join-Path $source 'SKILL.md'
        $outsideMarker = Join-Path $outside 'marker.txt'
        Set-Content -LiteralPath $sourceMarker -Value 'preserve chained source' `
            -Encoding UTF8
        Set-Content -LiteralPath $outsideMarker `
            -Value 'preserve chained outside destination' -Encoding UTF8
        $outsideHop = Join-Path $insideRedirect 'skills'
        $outsideJunction = New-AgentHubTestJunctionOrSkip `
            -Path $outsideHop -Target $outside
        if ($null -eq $outsideJunction) {
            return
        }
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        New-Item -ItemType Directory -Path $batch.BatchRoot -Force | Out-Null
        $destinationAncestor = Join-Path $batch.BatchRoot 'fixture-host'
        $ancestorJunction = New-AgentHubTestJunctionOrSkip `
            -Path $destinationAncestor -Target $insideRedirect
        if ($null -eq $ancestorJunction) {
            return
        }

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Chained outside destination junctions are forbidden.' `
                -ContentHash ('C' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        (Get-Content -LiteralPath $sourceMarker -Raw).Trim() |
            Should -Be 'preserve chained source'
        (Get-Content -LiteralPath $outsideMarker -Raw).Trim() |
            Should -Be 'preserve chained outside destination'
        Test-Path -LiteralPath (Join-Path $outside 'fixture') | Should -BeFalse
        @($batch.Entries).Count | Should -Be 0
    }

    It 'refuses a cyclic source reparse resolution before moving anything' {
        $profile = Join-Path $TestDrive 'source-junction-cycle-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        $safeTarget = Join-Path $profile '.links\safe-target'
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $source
        ), $safeTarget -Force | Out-Null
        $sourceJunction = New-AgentHubTestJunctionOrSkip `
            -Path $source -Target $safeTarget
        if ($null -eq $sourceJunction) {
            return
        }
        $script:agentHubSyntheticCycleSource = [IO.Path]::GetFullPath($source)
        Mock Get-AgentHubReparseTargetPath {
            return $script:agentHubSyntheticCycleSource
        }
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Cyclic source reparses are forbidden.' -ContentHash ('C' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        Test-Path -LiteralPath $safeTarget | Should -BeTrue
        Test-Path -LiteralPath (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        ) | Should -BeFalse
        @($batch.Entries).Count | Should -Be 0
    }

    It 'bounds source reparse traversal before moving anything' {
        $profile = Join-Path $TestDrive 'source-junction-bound-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        $chainRoot = Join-Path $profile '.links'
        $finalTarget = Join-Path $chainRoot 'final-target'
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $source
        ), $chainRoot, $finalTarget -Force | Out-Null

        $nextTarget = $finalTarget
        for ($index = 32; $index -ge 0; $index--) {
            $linkPath = Join-Path $chainRoot ('hop-{0:d2}' -f $index)
            $junction = New-AgentHubTestJunctionOrSkip `
                -Path $linkPath -Target $nextTarget
            if ($null -eq $junction) {
                return
            }
            $nextTarget = $linkPath
        }
        $sourceJunction = New-AgentHubTestJunctionOrSkip `
            -Path $source -Target $nextTarget
        if ($null -eq $sourceJunction) {
            return
        }
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Excessive source reparse traversal is forbidden.' `
                -ContentHash ('C' * 64)
        } | Should -Throw

        Test-Path -LiteralPath $source | Should -BeTrue
        Test-Path -LiteralPath $finalTarget | Should -BeTrue
        Test-Path -LiteralPath (
            Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        ) | Should -BeFalse
        @($batch.Entries).Count | Should -Be 0
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

    It 'rolls back the first move when initial manifest persistence fails' {
        $profile = Join-Path $TestDrive 'first-write-rollback-profile'
        $source = Join-Path $profile '.host\skills\fixture'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        $sourceMarker = Join-Path $source 'SKILL.md'
        Set-Content -LiteralPath $sourceMarker -Value 'restore initial source' `
            -Encoding UTF8
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        $destination = Join-Path $batch.BatchRoot 'fixture-host\skills\fixture'
        $manifestPath = Join-Path $batch.BatchRoot 'manifest.json'
        Mock Invoke-AgentHubQuarantineManifestPersistence {
            throw 'Synthetic initial manifest persistence failure.'
        }

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $source `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'fixture' `
                -Reason 'Initial persistence rollback fixture.' -ContentHash ('3' * 64)
        } | Should -Throw '*Synthetic initial manifest persistence failure*'

        Test-Path -LiteralPath $source | Should -BeTrue
        (Get-Content -LiteralPath $sourceMarker -Raw).Trim() |
            Should -Be 'restore initial source'
        Test-Path -LiteralPath $destination | Should -BeFalse
        Test-Path -LiteralPath $manifestPath | Should -BeFalse
        @($batch.Entries).Count | Should -Be 0
        $batch.ManifestPersisted | Should -BeFalse
        $batch.ManifestWritten | Should -BeFalse
        @(Get-ChildItem -LiteralPath $batch.BatchRoot -File `
            -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '^manifest\.json\.(tmp|bak)-'
            }).Count | Should -Be 0
    }

    It 'rolls back only the latest move when manifest replacement fails' {
        $profile = Join-Path $TestDrive 'replacement-rollback-profile'
        $firstSource = Join-Path $profile '.host\skills\first'
        $secondSource = Join-Path $profile '.host\skills\second'
        New-Item -ItemType Directory -Path $firstSource, $secondSource -Force |
            Out-Null
        Set-Content -LiteralPath (Join-Path $firstSource 'SKILL.md') `
            -Value 'keep first quarantined' -Encoding UTF8
        $secondMarker = Join-Path $secondSource 'SKILL.md'
        Set-Content -LiteralPath $secondMarker -Value 'restore second source' `
            -Encoding UTF8
        $batch = New-AgentHubQuarantineBatch -UserProfilePath $profile
        $firstDestination = Move-ToAgentHubQuarantine -Batch $batch `
            -Path $firstSource -HostId 'fixture-host' -ArtifactKind 'skills' `
            -ArtifactName 'first' -Reason 'First replacement fixture.' `
            -ContentHash ('4' * 64)
        $manifestPath = Join-Path $batch.BatchRoot 'manifest.json'
        $secondDestination = Join-Path $batch.BatchRoot 'fixture-host\skills\second'
        Mock Invoke-AgentHubQuarantineManifestPersistence {
            throw 'Synthetic replacement manifest persistence failure.'
        }

        {
            Move-ToAgentHubQuarantine -Batch $batch -Path $secondSource `
                -HostId 'fixture-host' -ArtifactKind 'skills' -ArtifactName 'second' `
                -Reason 'Replacement persistence rollback fixture.' `
                -ContentHash ('5' * 64)
        } | Should -Throw '*Synthetic replacement manifest persistence failure*'

        Test-Path -LiteralPath $firstSource | Should -BeFalse
        Test-Path -LiteralPath $firstDestination | Should -BeTrue
        Test-Path -LiteralPath $secondSource | Should -BeTrue
        (Get-Content -LiteralPath $secondMarker -Raw).Trim() |
            Should -Be 'restore second source'
        Test-Path -LiteralPath $secondDestination | Should -BeFalse
        Test-Path -LiteralPath $manifestPath | Should -BeTrue
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        @($manifest.entries).Count | Should -Be 1
        @($manifest.entries)[0].artifactName | Should -Be 'first'
        @($batch.Entries).Count | Should -Be 1
        @($batch.Entries)[0].artifactName | Should -Be 'first'
        $batch.ManifestPersisted | Should -BeTrue
        $batch.ManifestWritten | Should -BeFalse
        @(Get-ChildItem -LiteralPath $batch.BatchRoot -File `
            -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '^manifest\.json\.(tmp|bak)-'
            }).Count | Should -Be 0
    }
}
