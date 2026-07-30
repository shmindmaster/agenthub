#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot,
    [string]$UserProfilePath = $env:USERPROFILE,
    [string]$AppDataPath,
    [switch]$Apply,
    [string]$ReportPath,
    [switch]$Json,
    [Parameter(DontShow)]
    [ValidateRange(0, 1000)]
    [int]$TestFailAfterTargetCount = 0
)

if ([string]::IsNullOrWhiteSpace($RegistryRoot)) {
    $RegistryRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($AppDataPath)) {
    $AppDataPath = Join-Path $UserProfilePath 'AppData\Roaming'
}

$RegistryRoot = [IO.Path]::GetFullPath($RegistryRoot)
$UserProfilePath = [IO.Path]::GetFullPath($UserProfilePath)
$AppDataPath = [IO.Path]::GetFullPath($AppDataPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
. (Join-Path $PSScriptRoot 'ManagedQuarantine.ps1')

function Expand-AgentHubSkillPath {
    param([Parameter(Mandatory)][string]$Template)

    $expanded = $Template.Replace('${USERPROFILE}', $UserProfilePath).
        Replace('${APPDATA}', $AppDataPath)
    if ($expanded -match '\$\{') {
        throw "Unsupported path placeholder in external skill registry: $Template"
    }
    $expanded = $expanded.Replace('/', '\')
    $fullPath = [IO.Path]::GetFullPath($expanded)
    if (-not (Test-AgentHubPathWithinRoot -Path $fullPath -Root $UserProfilePath)) {
        throw "External skill path resolves outside the approved user profile: $fullPath"
    }
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $fullPath `
        -Root $UserProfilePath | Out-Null
    return $fullPath
}

function Get-AgentHubExternalTreeHash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return ''
    }
    return Get-AgentHubRegistryHashBasisValue -Path $Path
}

function Copy-AgentHubExternalTreeToStage {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ContainmentRoot
    )
    $parent = Split-Path -Parent $Destination
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $Source -Root $ContainmentRoot | Out-Null
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $Destination -Root $ContainmentRoot | Out-Null
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $parent -Root $ContainmentRoot | Out-Null
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $parent -Root $ContainmentRoot | Out-Null
    $stage = Join-Path $parent (
        '.agenthub-stage-' + [guid]::NewGuid().ToString('N')
    )
    Assert-AgentHubQuarantinePhysicalContainment `
        -Path $stage -Root $ContainmentRoot | Out-Null
    try {
        Copy-Item -LiteralPath $Source -Destination $stage -Recurse
        return $stage
    } catch {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
        throw
    }
}

$registryPath = Join-Path $RegistryRoot 'registry\skill-ownership.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "External skill ownership registry is missing: $registryPath"
}
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$batch = if ($Apply) {
    New-AgentHubQuarantineBatch -UserProfilePath $UserProfilePath
} else { $null }
$ownerReports = New-Object System.Collections.Generic.List[object]
$failed = $false

foreach ($owner in @($registry.externalOwners)) {
    $currentHash = ([string]$owner.treeHash).ToUpperInvariant()
    $previousHashes = @($owner.previousTreeHashes | ForEach-Object {
        ([string]$_).ToUpperInvariant()
    })
    $source = ''
    foreach ($template in @($owner.sourceCandidates)) {
        $candidate = Expand-AgentHubSkillPath -Template ([string]$template)
        if ((Get-AgentHubExternalTreeHash -Path $candidate) -eq $currentHash) {
            $source = $candidate
            break
        }
    }

    $targetReports = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($owner.targets)) {
        $path = Expand-AgentHubSkillPath -Template ([string]$target.path)
        $hash = Get-AgentHubExternalTreeHash -Path $path
        $state = if ([string]::IsNullOrWhiteSpace($hash)) {
            'missing'
        } elseif ($hash -eq $currentHash) {
            'current'
        } elseif ($hash -in $previousHashes) {
            'outdated-known'
        } else {
            'divergent-unknown'
        }
        $targetReports.Add([pscustomobject]@{
            hostId = [string]$target.hostId
            path = $path
            state = $state
            treeHash = $hash
        })
    }

    $ownerFailed = [string]::IsNullOrWhiteSpace($source) -or
        @($targetReports | Where-Object state -eq 'divergent-unknown').Count -gt 0
    if ($ownerFailed) { $failed = $true }

    if ($Apply -and -not $ownerFailed) {
        $deploymentPlans = New-Object System.Collections.Generic.List[object]
        try {
            foreach ($targetReport in $targetReports.ToArray()) {
                if ($targetReport.state -eq 'current') { continue }
                $stage = Copy-AgentHubExternalTreeToStage `
                    -Source $source `
                    -Destination $targetReport.path `
                    -ContainmentRoot $UserProfilePath
                $deploymentPlans.Add([pscustomobject]@{
                    target = $targetReport
                    stagePath = $stage
                    backupPath = ''
                    originalState = [string]$targetReport.state
                    originalHash = [string]$targetReport.treeHash
                    mutationStarted = $false
                })
            }
        } catch {
            foreach ($plan in $deploymentPlans.ToArray()) {
                if ($plan.stagePath -and
                    (Test-Path -LiteralPath $plan.stagePath)) {
                    Remove-Item -LiteralPath $plan.stagePath -Recurse -Force
                }
            }
            throw
        }

        $changedPlans = New-Object System.Collections.Generic.List[object]
        $appliedTargetCount = 0
        try {
            foreach ($plan in $deploymentPlans.ToArray()) {
                $targetReport = $plan.target
                $plan.mutationStarted = $true
                $changedPlans.Add($plan)
                if ($targetReport.state -eq 'outdated-known') {
                    $plan.backupPath = Move-ToAgentHubQuarantine `
                        -Batch $batch `
                        -Path $targetReport.path `
                        -HostId $targetReport.hostId `
                        -ArtifactKind 'skills' `
                        -ArtifactName ([string]$owner.skillId) `
                        -Reason "Replaced known outdated external skill with trusted $($owner.currentVersion)." `
                        -ContentHash $targetReport.treeHash
                }
                Move-Item -LiteralPath $plan.stagePath -Destination $targetReport.path
                $plan.stagePath = ''
                $verifiedHash = Get-AgentHubExternalTreeHash -Path $targetReport.path
                if ($verifiedHash -ne $currentHash) {
                    throw "External skill verification failed for $($targetReport.path)."
                }
                $targetReport.state = 'current'
                $targetReport.treeHash = $verifiedHash
                $appliedTargetCount++
                if ($TestFailAfterTargetCount -gt 0 -and
                    $appliedTargetCount -eq $TestFailAfterTargetCount) {
                    throw "Injected external-skill deployment failure after $appliedTargetCount target(s)."
                }
            }
        } catch {
            $deploymentError = $_
            $rollbackErrors = New-Object System.Collections.Generic.List[string]
            foreach ($plan in @($changedPlans.ToArray())[
                ($changedPlans.Count - 1)..0
            ]) {
                try {
                    $targetPath = [string]$plan.target.path
                    if (Test-Path -LiteralPath $targetPath) {
                        $deployedHash = Get-AgentHubExternalTreeHash -Path $targetPath
                        if ($deployedHash -ne $currentHash) {
                            throw "Refusing rollback over unexpected content at $targetPath."
                        }
                        Assert-AgentHubQuarantinePhysicalContainment `
                            -Path $targetPath -Root $UserProfilePath | Out-Null
                        Remove-Item -LiteralPath $targetPath -Recurse -Force
                    }
                    if ($plan.backupPath) {
                        if (-not (Test-Path -LiteralPath $plan.backupPath)) {
                            throw "Rollback backup is missing: $($plan.backupPath)"
                        }
                        Move-Item -LiteralPath $plan.backupPath -Destination $targetPath
                        foreach ($entry in @($batch.Entries)) {
                            if ([string]$entry.sourcePath -eq $targetPath -and
                                [string]$entry.quarantinePath -eq
                                    [string]$plan.backupPath) {
                                $entry['rolledBackAtUtc'] = (
                                    Get-Date
                                ).ToUniversalTime().ToString('o')
                                $entry['restoredToSource'] = $true
                            }
                        }
                    }
                    $plan.target.state = $plan.originalState
                    $plan.target.treeHash = $plan.originalHash
                } catch {
                    $rollbackErrors.Add($_.Exception.Message)
                }
            }
            if (@($batch.Entries).Count -gt 0) {
                Write-AgentHubQuarantineManifestSnapshot `
                    -Batch $batch `
                    -ValidatedBatch (
                        Assert-AgentHubQuarantineBatch -Batch $batch
                    ) | Out-Null
            }
            if ($rollbackErrors.Count -gt 0) {
                throw "External skill deployment failed: $($deploymentError.Exception.Message) Rollback failed: $($rollbackErrors -join ' | ')"
            }
            throw $deploymentError
        } finally {
            foreach ($plan in $deploymentPlans.ToArray()) {
                if ($plan.stagePath -and
                    (Test-Path -LiteralPath $plan.stagePath)) {
                    Remove-Item -LiteralPath $plan.stagePath -Recurse -Force
                }
            }
        }

        $allTargetsCurrent = @(
            $targetReports | Where-Object state -ne 'current'
        ).Count -eq 0
        if ($allTargetsCurrent) {
            foreach ($template in @($owner.sharedShadowPaths)) {
                $shadow = Expand-AgentHubSkillPath -Template ([string]$template)
                $shadowHash = Get-AgentHubExternalTreeHash -Path $shadow
                if ([string]::IsNullOrWhiteSpace($shadowHash)) { continue }
                if ($shadowHash -notin @($currentHash) + $previousHashes) {
                    $failed = $true
                    continue
                }
                Move-ToAgentHubQuarantine `
                    -Batch $batch `
                    -Path $shadow `
                    -HostId 'shared-agent-skills' `
                    -ArtifactKind 'skills' `
                    -ArtifactName ([string]$owner.skillId) `
                    -Reason 'Removed verified shared shadow after every explicit host target matched the trusted vendor tree.' `
                    -ContentHash $shadowHash | Out-Null
            }
        }
    }

    $ownerReports.Add([pscustomobject]@{
        skillId = [string]$owner.skillId
        source = $source
        sourceTrusted = -not [string]::IsNullOrWhiteSpace($source)
        targets = $targetReports.ToArray()
        status = if ($ownerFailed) { 'blocked' } else { 'ready' }
    })
}

$manifestPath = if ($Apply -and @($batch.Entries).Count -gt 0) {
    Write-AgentHubQuarantineManifest -Batch $batch
} else { $null }
$output = [ordered]@{
    schemaVersion = 1
    mode = if ($Apply) { 'apply' } else { 'report' }
    failed = $failed
    owners = $ownerReports.ToArray()
    quarantineManifest = $manifestPath
}
$serialized = $output | ConvertTo-Json -Depth 12
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $parent = Split-Path -Parent $ReportPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText(
        [IO.Path]::GetFullPath($ReportPath),
        $serialized,
        [Text.UTF8Encoding]::new($false)
    )
}
if ($Json) { $serialized } else { $output }
if ($failed) { exit 1 }
