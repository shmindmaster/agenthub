#Requires -Version 5.1

. (Join-Path $PSScriptRoot 'PathSafety.ps1')

function Test-AgentHubPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Root
    )

    $normalizedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($normalizedPath.Equals(
        $normalizedRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return $false
    }

    return $normalizedPath.StartsWith(
        "$normalizedRoot\",
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Assert-AgentHubQuarantineSegment {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Quarantine $Name is required."
    }
    if ($Value -in @('.', '..') -or
        [IO.Path]::GetFileName($Value) -cne $Value -or
        $Value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Quarantine $Name must be one safe path segment."
    }
}

function Get-AgentHubReparseTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $targets = @($Item.Target)
    if ($targets.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$targets[0])) {
        throw "Cannot safely resolve reparse point target: $($Item.FullName)"
    }

    $target = [string]$targets[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path -Parent $Item.FullName) $target
    }
    return [IO.Path]::GetFullPath($target)
}

function Resolve-AgentHubQuarantinePhysicalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Root,
        [ValidateRange(1, 32)]
        [int]$MaximumReparseHops = 32
    )

    $normalizedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not $normalizedPath.Equals(
        $normalizedRoot,
        [StringComparison]::OrdinalIgnoreCase
    ) -and -not (Test-AgentHubPathWithinRoot `
        -Path $normalizedPath `
        -Root $normalizedRoot
    )) {
        throw "Path is outside its approved containment root: $normalizedPath"
    }

    $workingPath = $normalizedPath
    $visitedReparsePoints = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $reparsePoints = [Collections.ArrayList]::new()
    $reparseHopCount = 0

    while ($true) {
        $pathsToInspect = [Collections.ArrayList]::new()
        [void]$pathsToInspect.Add($normalizedRoot)
        if (-not $workingPath.Equals(
            $normalizedRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            $relativePath = $workingPath.Substring($normalizedRoot.Length).
                TrimStart('\', '/')
            $cursor = $normalizedRoot
            foreach ($segment in @($relativePath -split '[\\/]')) {
                if ([string]::IsNullOrWhiteSpace($segment)) {
                    continue
                }
                $cursor = Join-Path $cursor $segment
                [void]$pathsToInspect.Add($cursor)
            }
        }

        $resolvedReparsePoint = $false
        foreach ($candidate in $pathsToInspect) {
            $item = $null
            try {
                $item = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            } catch {
                if ($_.CategoryInfo.Category -eq
                    [Management.Automation.ErrorCategory]::ObjectNotFound) {
                    break
                }
                throw "Cannot safely inspect quarantine path '$candidate': $($_.Exception.Message)"
            }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                continue
            }

            $candidatePath = [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
            if (-not $visitedReparsePoints.Add($candidatePath)) {
                throw "Refusing a cyclic quarantine reparse-point chain at: $candidatePath"
            }
            $reparseHopCount++
            if ($reparseHopCount -gt $MaximumReparseHops) {
                throw "Refusing a quarantine reparse-point chain longer than $MaximumReparseHops hops."
            }
            [void]$reparsePoints.Add($candidatePath)

            $targetPath = Get-AgentHubReparseTargetPath -Item $item
            if (-not (Test-AgentHubPathWithinRoot `
                -Path $targetPath `
                -Root $normalizedRoot
            )) {
                throw "Refusing a quarantine reparse point outside the approved profile: $candidatePath -> $targetPath"
            }

            $remainingPath = $workingPath.Substring($candidatePath.Length).
                TrimStart('\', '/')
            if (-not [string]::IsNullOrEmpty($remainingPath)) {
                $targetPath = [IO.Path]::GetFullPath(
                    (Join-Path $targetPath $remainingPath)
                )
            }
            if (-not $targetPath.Equals(
                $normalizedRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -and -not (Test-AgentHubPathWithinRoot `
                -Path $targetPath `
                -Root $normalizedRoot
            )) {
                throw "Refusing a quarantine reparse-point tail outside the approved profile: $candidatePath -> $targetPath"
            }

            $workingPath = $targetPath.TrimEnd('\', '/')
            $resolvedReparsePoint = $true
            break
        }

        if (-not $resolvedReparsePoint) {
            return [pscustomobject]@{
                ResolvedPath = $workingPath
                ReparsePoints = @($reparsePoints)
            }
        }
    }
}

function Assert-AgentHubQuarantinePhysicalContainment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Root,
        [switch]$AllowSafeLeafReparsePoint
    )

    $normalizedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $resolution = Resolve-AgentHubQuarantinePhysicalPath `
        -Path $normalizedPath `
        -Root $Root
    $reparsePoints = @($resolution.ReparsePoints)
    if ($reparsePoints.Count -gt 0) {
        $firstReparsePoint = [string]$reparsePoints[0]
        $isLeaf = $firstReparsePoint.Equals(
            $normalizedPath,
            [StringComparison]::OrdinalIgnoreCase
        )
        if (-not $AllowSafeLeafReparsePoint -or -not $isLeaf) {
            throw "Refusing a quarantine path that traverses a reparse point: $firstReparsePoint"
        }
    }

    return $normalizedPath
}

function Assert-AgentHubQuarantineBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Batch
    )

    foreach ($propertyName in @(
        'UserProfilePath',
        'BatchRoot',
        'CreatedAtUtc',
        'Entries',
        'ManifestPersisted',
        'ManifestWritten'
    )) {
        if ($null -eq $Batch.PSObject.Properties[$propertyName]) {
            throw "Invalid AgentHub quarantine batch: missing $propertyName."
        }
    }

    $profilePath = Assert-AgentHubSafeWritePath `
        -Path ([string]$Batch.UserProfilePath) `
        -Purpose 'the quarantine user profile'
    $batchRoot = Assert-AgentHubSafeWritePath `
        -Path ([string]$Batch.BatchRoot) `
        -Purpose 'the quarantine batch directory'
    if (-not (Test-AgentHubPathWithinRoot -Path $batchRoot -Root $profilePath)) {
        throw "Invalid AgentHub quarantine batch root outside the user profile: $batchRoot"
    }
    $expectedQuarantineRoot = Join-Path $profilePath '.agenthub\quarantine'
    if (-not (Test-AgentHubPathWithinRoot -Path $batchRoot -Root $expectedQuarantineRoot)) {
        throw "Invalid AgentHub quarantine batch root: $batchRoot"
    }

    return [pscustomobject]@{
        UserProfilePath = $profilePath
        BatchRoot = $batchRoot
    }
}

function New-AgentHubQuarantineBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserProfilePath
    )

    $safeUserProfilePath = Assert-AgentHubSafeWritePath `
        -Path $UserProfilePath `
        -Purpose 'the quarantine user profile'
    $batchId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') +
        '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $batchRoot = Assert-AgentHubSafeWritePath `
        -Path (Join-Path $safeUserProfilePath ".agenthub\quarantine\$batchId") `
        -Purpose 'the quarantine batch directory'

    return [pscustomobject]@{
        UserProfilePath = $safeUserProfilePath
        BatchId = $batchId
        BatchRoot = $batchRoot
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Entries = [System.Collections.ArrayList]::new()
        ManifestPersisted = $false
        ManifestWritten = $false
    }
}

function Invoke-AgentHubQuarantineManifestPersistence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemporaryPath,
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [Parameter(Mandatory)]
        [string]$ManifestJson,
        [Parameter(Mandatory)]
        [bool]$ManifestExists
    )

    [IO.File]::WriteAllText(
        $TemporaryPath,
        $ManifestJson,
        [Text.UTF8Encoding]::new($false)
    )
    if ($ManifestExists) {
        [IO.File]::Replace($TemporaryPath, $ManifestPath, $BackupPath)
    } else {
        [IO.File]::Move($TemporaryPath, $ManifestPath)
    }
}

function Write-AgentHubQuarantineManifestSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Batch,
        [Parameter(Mandatory)]
        [object]$ValidatedBatch,
        [switch]$Finalize
    )

    if (@($Batch.Entries).Count -eq 0) {
        return $null
    }

    $manifestPath = Assert-AgentHubSafeWritePath `
        -Path (Join-Path $ValidatedBatch.BatchRoot 'manifest.json') `
        -Purpose 'the quarantine manifest'
    if (-not (Test-AgentHubPathWithinRoot `
        -Path $manifestPath `
        -Root $ValidatedBatch.BatchRoot
    )) {
        throw "Refusing an unsafe quarantine manifest path: $manifestPath"
    }
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $manifestPath `
        -Root $ValidatedBatch.UserProfilePath | Out-Null

    if ((Test-Path -LiteralPath $manifestPath) -and
        -not [bool]$Batch.ManifestPersisted) {
        throw "Refusing to overwrite an existing quarantine manifest: $manifestPath"
    }

    New-Item -ItemType Directory -Path $ValidatedBatch.BatchRoot -Force |
        Out-Null
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $manifestPath `
        -Root $ValidatedBatch.UserProfilePath | Out-Null

    $writeId = [guid]::NewGuid().ToString('N')
    $temporaryPath = "$manifestPath.tmp-$writeId"
    $backupPath = "$manifestPath.bak-$writeId"
    try {
        $manifestJson = [ordered]@{
            schemaVersion = 1
            createdAtUtc = [string]$Batch.CreatedAtUtc
            entries = @($Batch.Entries)
        } | ConvertTo-Json -Depth 10
        Invoke-AgentHubQuarantineManifestPersistence `
            -TemporaryPath $temporaryPath `
            -ManifestPath $manifestPath `
            -BackupPath $backupPath `
            -ManifestJson $manifestJson `
            -ManifestExists (Test-Path -LiteralPath $manifestPath)
    } finally {
        foreach ($cleanupPath in @($temporaryPath, $backupPath)) {
            try {
                if (Test-Path -LiteralPath $cleanupPath) {
                    Remove-Item -LiteralPath $cleanupPath -Force
                }
            } catch {
                Write-Warning "Could not remove quarantine manifest write artifact '$cleanupPath': $($_.Exception.Message)"
            }
        }
    }

    $Batch.ManifestPersisted = $true
    if ($Finalize) {
        $Batch.ManifestWritten = $true
    }
    return $manifestPath
}

function Move-ToAgentHubQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Batch,
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$HostId,
        [Parameter(Mandatory)]
        [string]$ArtifactKind,
        [Parameter(Mandatory)]
        [string]$ArtifactName,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Reason,
        [Parameter(Mandatory)]
        [string]$ContentHash
    )

    $validatedBatch = Assert-AgentHubQuarantineBatch -Batch $Batch
    if ([bool]$Batch.ManifestWritten) {
        throw 'The AgentHub quarantine manifest has already been written for this batch.'
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        throw 'A non-empty quarantine reason is required.'
    }
    if ($ContentHash.Length -ne 64 -or
        $ContentHash -match '[^A-Fa-f0-9]') {
        throw 'Quarantine contentHash must be a 64-character hexadecimal SHA-256 value.'
    }
    Assert-AgentHubQuarantineSegment -Value $HostId -Name 'hostId'
    Assert-AgentHubQuarantineSegment -Value $ArtifactKind -Name 'artifactKind'
    Assert-AgentHubQuarantineSegment -Value $ArtifactName -Name 'artifactName'

    $sourcePath = Assert-AgentHubSafeWritePath `
        -Path $Path `
        -Purpose 'the quarantine source artifact'
    if (-not (Test-AgentHubPathWithinRoot `
        -Path $sourcePath `
        -Root $validatedBatch.UserProfilePath
    )) {
        throw "Refusing to quarantine a source outside the approved user profile: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Quarantine source artifact does not exist: $sourcePath"
    }
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $sourcePath `
        -Root $validatedBatch.UserProfilePath `
        -AllowSafeLeafReparsePoint | Out-Null

    $quarantinePath = Assert-AgentHubSafeWritePath `
        -Path (Join-Path $validatedBatch.BatchRoot (
            Join-Path $HostId (Join-Path $ArtifactKind $ArtifactName)
        )) `
        -Purpose 'the quarantine destination'
    if (-not (Test-AgentHubPathWithinRoot `
        -Path $quarantinePath `
        -Root $validatedBatch.BatchRoot
    )) {
        throw "Refusing an unsafe quarantine destination: $quarantinePath"
    }
    $manifestPath = Join-Path $validatedBatch.BatchRoot 'manifest.json'
    if ($quarantinePath.Equals(
        [IO.Path]::GetFullPath($manifestPath),
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing a quarantine destination that collides with the manifest: $quarantinePath"
    }
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $quarantinePath `
        -Root $validatedBatch.UserProfilePath | Out-Null
    if (Test-Path -LiteralPath $quarantinePath) {
        throw "Refusing to overwrite an existing quarantine destination: $quarantinePath"
    }

    New-Item -ItemType Directory `
        -Path (Split-Path -Parent $quarantinePath) `
        -Force | Out-Null
    Move-Item -LiteralPath $sourcePath -Destination $quarantinePath
    $entry = [ordered]@{
        sourcePath = $sourcePath
        quarantinePath = $quarantinePath
        hostId = $HostId
        artifactKind = $ArtifactKind
        artifactName = $ArtifactName
        reason = $Reason
        contentHash = $ContentHash
        quarantinedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    [void]$Batch.Entries.Add($entry)
    try {
        Write-AgentHubQuarantineManifestSnapshot `
            -Batch $Batch `
            -ValidatedBatch $validatedBatch | Out-Null
    } catch {
        $manifestError = $_
        $Batch.Entries.RemoveAt($Batch.Entries.Count - 1)
        try {
            if ((Test-Path -LiteralPath $quarantinePath) -and
                -not (Test-Path -LiteralPath $sourcePath)) {
                Move-Item -LiteralPath $quarantinePath -Destination $sourcePath
            }
        } catch {
            throw "Quarantine manifest persistence failed after moving '$sourcePath', and rollback also failed. Manifest error: $($manifestError.Exception.Message) Rollback error: $($_.Exception.Message)"
        }
        throw $manifestError
    }

    return $quarantinePath
}

function Write-AgentHubQuarantineManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Batch
    )

    $validatedBatch = Assert-AgentHubQuarantineBatch -Batch $Batch
    if ([bool]$Batch.ManifestWritten) {
        throw 'The AgentHub quarantine manifest has already been written for this batch.'
    }
    if (@($Batch.Entries).Count -eq 0) {
        return $null
    }

    return Write-AgentHubQuarantineManifestSnapshot `
        -Batch $Batch `
        -ValidatedBatch $validatedBatch `
        -Finalize
}
