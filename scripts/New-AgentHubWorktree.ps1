#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a Git worktree under the sole AgentHub root, C:\wt.

.DESCRIPTION
    This script is the repository-owned implementation for an optional Claude
    Code WorktreeCreate hook and for hosts that need an AgentHub wrapper. It
    reads the official WorktreeCreate JSON input from stdin when -InputJson is
    omitted and prints the created absolute path as the final stdout line.

    The script does not install a hook or mutate host settings.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline)]
    [string]$InputJson,
    [string]$Cwd,
    [string]$Name,
    [string]$RepositoryName,
    [string]$WorktreeRoot,
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    $WorktreeRoot = if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_WORKTREE_ROOT)) {
        'C:\wt'
    } else {
        [string]$env:AGENTHUB_WORKTREE_ROOT
    }
}

function ConvertTo-AgentHubSafeComponent {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$FieldName
    )

    $component = $Value.Trim()
    $windowsReservedName = '^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)'
    if ($component -cne $Value -or $component -cne $component.ToLowerInvariant() -or
        $component -notmatch '^[a-z0-9](?:[a-z0-9._-]*[a-z0-9_-])?$' -or
        $component -match $windowsReservedName) {
        throw "$FieldName must be an unambiguous lowercase safe path component using only a-z, 0-9, dot, underscore, or hyphen."
    }
    return $component
}

function Invoke-AgentHubGit {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Operation = 'git command',
        [switch]$AllowFailure
    )

    $gitOutput = @(& git @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $detail = @($gitOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' | '
        if ($detail) { throw "$Operation failed: $detail" }
        throw "$Operation failed with exit code $exitCode."
    }
    return [pscustomobject]@{
        exitCode = $exitCode
        output = $gitOutput
    }
}

function Get-AgentHubGitIdentity {
    param([Parameter(Mandatory)][string]$Cwd)

    if (-not (Test-Path -LiteralPath $Cwd -PathType Container)) {
        throw "WorktreeCreate cwd does not exist: $Cwd"
    }

    $commonResult = Invoke-AgentHubGit -Arguments @(
        '-C', $Cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir'
    ) -Operation 'git common dir discovery'
    $commonValue = @($commonResult.output | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | Select-Object -Last 1)
    if ($commonValue.Count -ne 1) {
        throw "git common dir discovery returned no canonical path for '$Cwd'."
    }

    $commonDir = [System.IO.Path]::GetFullPath([string]$commonValue[0]).TrimEnd('\', '/')
    if ((Split-Path -Leaf $commonDir) -cne '.git') {
        throw "git common dir '$commonDir' is not a supported non-bare repository metadata path."
    }
    $repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $commonDir)).TrimEnd('\', '/')
    $repositoryIdentity = ConvertTo-AgentHubSafeComponent -Value (Split-Path -Leaf $repositoryRoot) -FieldName 'canonical repository identity'

    return [pscustomobject]@{
        commonDir = $commonDir
        repositoryRoot = $repositoryRoot
        repositoryIdentity = $repositoryIdentity
    }
}

function ConvertFrom-AgentHubWorktreePorcelain {
    param([string[]]$Lines)

    $blocks = [System.Collections.Generic.List[object]]::new()
    $current = [ordered]@{}
    foreach ($line in @($Lines) + '') {
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            if ($current.Count -gt 0) {
                $blocks.Add([pscustomobject]$current)
                $current = [ordered]@{}
            }
            continue
        }
        $parts = [string]$line -split ' ', 2
        $current[$parts[0]] = if ($parts.Count -gt 1) { $parts[1] } else { $true }
    }
    return @($blocks.ToArray())
}

function Get-AgentHubWorktreeTarget {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Task
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($resolvedRoot -ne 'C:\wt') {
        throw "AgentHub worktrees must use C:\wt; received '$resolvedRoot'."
    }

    $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot (Join-Path $Repository $Task)))
    $prefix = $resolvedRoot + '\'
    if (-not $target.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved worktree target escapes C:\wt: $target"
    }
    return $target
}

if (-not [string]::IsNullOrWhiteSpace($InputJson) -and
    (-not [string]::IsNullOrWhiteSpace($Cwd) -or -not [string]::IsNullOrWhiteSpace($Name))) {
    throw 'Use either WorktreeCreate JSON input or the manual -Cwd and -Name parameters, not both.'
}

if ([string]::IsNullOrWhiteSpace($InputJson) -and
    (-not [string]::IsNullOrWhiteSpace($Cwd) -or -not [string]::IsNullOrWhiteSpace($Name))) {
    if ([string]::IsNullOrWhiteSpace($Cwd) -or [string]::IsNullOrWhiteSpace($Name)) {
        throw 'Manual invocation requires both -Cwd and -Name.'
    }
    $InputJson = @{
        cwd = $Cwd
        name = $Name
    } | ConvertTo-Json -Compress
}

if ([string]::IsNullOrWhiteSpace($InputJson)) {
    $InputJson = [Console]::In.ReadToEnd()
}
if ([string]::IsNullOrWhiteSpace($InputJson)) {
    throw 'WorktreeCreate JSON input is required.'
}

try {
    $hookInput = $InputJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "WorktreeCreate input is not valid JSON: $($_.Exception.Message)"
}

$taskSlug = ConvertTo-AgentHubSafeComponent -Value ([string]$hookInput.name) -FieldName 'name'
$cwd = [string]$hookInput.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) {
    throw 'WorktreeCreate input must include cwd.'
}

$gitIdentity = Get-AgentHubGitIdentity -Cwd $cwd
$repositorySlug = $gitIdentity.repositoryIdentity
if (-not [string]::IsNullOrWhiteSpace($RepositoryName)) {
    $requestedRepository = ConvertTo-AgentHubSafeComponent -Value $RepositoryName -FieldName 'RepositoryName'
    if ($requestedRepository -cne $repositorySlug) {
        throw "RepositoryName '$RepositoryName' does not match canonical repository identity '$repositorySlug' from git common dir '$($gitIdentity.commonDir)'."
    }
}
$target = Get-AgentHubWorktreeTarget -Root $WorktreeRoot -Repository $repositorySlug -Task $taskSlug

if ($PlanOnly) {
    Write-Output $target
    exit 0
}

$expectedBranch = "worktree-$taskSlug"
$expectedBranchRef = "refs/heads/$expectedBranch"
$listResult = Invoke-AgentHubGit -Arguments @(
    '-C', $gitIdentity.repositoryRoot, 'worktree', 'list', '--porcelain'
) -Operation 'git worktree list'
$worktreeBlocks = @(ConvertFrom-AgentHubWorktreePorcelain -Lines $listResult.output)
$targetBlocks = @($worktreeBlocks | Where-Object {
    $_.PSObject.Properties['worktree'] -and
    [System.IO.Path]::GetFullPath([string]$_.worktree).TrimEnd('\', '/').Equals(
        $target,
        [System.StringComparison]::OrdinalIgnoreCase
    )
})
$targetExists = Test-Path -LiteralPath $target

if ($targetExists -or $targetBlocks.Count -gt 0) {
    if (-not $targetExists -or $targetBlocks.Count -ne 1) {
        throw "Expected target '$target' has ambiguous or stale git worktree registration."
    }
    if (-not $targetBlocks[0].PSObject.Properties['branch'] -or
        [string]$targetBlocks[0].branch -cne $expectedBranchRef) {
        $actualBranch = if ($targetBlocks[0].PSObject.Properties['branch']) {
            [string]$targetBlocks[0].branch
        } else {
            '(detached-or-missing)'
        }
        throw "Existing target '$target' uses branch '$actualBranch', not expected branch '$expectedBranchRef'."
    }
    $targetIdentity = Get-AgentHubGitIdentity -Cwd $target
    if (-not $targetIdentity.commonDir.Equals(
        $gitIdentity.commonDir,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Existing target '$target' does not use the expected git common dir '$($gitIdentity.commonDir)'."
    }
    Write-Output $target
    exit 0
}

$branchResult = Invoke-AgentHubGit -Arguments @(
    '-C', $gitIdentity.repositoryRoot, 'show-ref', '--verify', '--quiet', $expectedBranchRef
) -Operation 'expected branch lookup' -AllowFailure
if ($branchResult.exitCode -eq 0) {
    throw "Expected branch '$expectedBranchRef' exists without the exact registered target '$target'; refusing to reuse possible WIP."
}
if ($branchResult.exitCode -ne 1) {
    throw "Expected branch lookup failed with exit code $($branchResult.exitCode)."
}

$baseResult = Invoke-AgentHubGit -Arguments @(
    '-C', $cwd, 'rev-parse', '--verify', 'HEAD'
) -Operation 'invoking worktree HEAD discovery'
$baseCommitValues = @($baseResult.output | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
})
if ($baseCommitValues.Count -ne 1 -or
    [string]$baseCommitValues[0] -notmatch '^[0-9a-f]{40,64}$') {
    throw "Invoking worktree HEAD discovery returned no exact commit for '$cwd'."
}
$baseCommit = [string]$baseCommitValues[0]

$parent = Split-Path -Parent $target
New-Item -ItemType Directory -Path $parent -Force | Out-Null

# git worktree add stdout/stderr is captured by Invoke-AgentHubGit via 2>&1.
$null = Invoke-AgentHubGit -Arguments @(
    '-C', $gitIdentity.repositoryRoot, 'worktree', 'add', '-b', $expectedBranch, $target, $baseCommit
) -Operation 'git worktree add'

Write-Output $target
