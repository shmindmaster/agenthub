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
    if ([IO.Path]::GetFileName($Value) -cne $Value -or
        $Value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "Quarantine $Name must be one safe path segment."
    }
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
        ManifestWritten = $false
    }
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
    if ($ContentHash -notmatch '^[A-Fa-f0-9]{64}$') {
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
    if (Test-Path -LiteralPath $quarantinePath) {
        throw "Refusing to overwrite an existing quarantine destination: $quarantinePath"
    }

    New-Item -ItemType Directory `
        -Path (Split-Path -Parent $quarantinePath) `
        -Force | Out-Null
    Move-Item -LiteralPath $sourcePath -Destination $quarantinePath
    [void]$Batch.Entries.Add([ordered]@{
        sourcePath = $sourcePath
        quarantinePath = $quarantinePath
        hostId = $HostId
        artifactKind = $ArtifactKind
        artifactName = $ArtifactName
        reason = $Reason
        contentHash = $ContentHash
        quarantinedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    })

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

    $manifestPath = Join-Path $validatedBatch.BatchRoot 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Refusing to overwrite an existing quarantine manifest: $manifestPath"
    }
    New-Item -ItemType Directory -Path $validatedBatch.BatchRoot -Force |
        Out-Null
    [ordered]@{
        schemaVersion = 1
        createdAtUtc = [string]$Batch.CreatedAtUtc
        entries = @($Batch.Entries)
    } | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $Batch.ManifestWritten = $true

    return $manifestPath
}
