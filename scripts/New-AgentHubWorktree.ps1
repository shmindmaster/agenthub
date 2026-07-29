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

function ConvertTo-AgentHubSlug {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$FieldName
    )

    $slug = $Value.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9._-]+', '-')
    $slug = [regex]::Replace($slug, '-{2,}', '-').Trim('-', '.', '_')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "$FieldName does not contain a safe worktree path component."
    }
    return $slug
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

$taskSlug = ConvertTo-AgentHubSlug -Value ([string]$hookInput.name) -FieldName 'name'
$cwd = [string]$hookInput.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) {
    throw 'WorktreeCreate input must include cwd.'
}

$gitRoot = $null
if (-not $PlanOnly -or [string]::IsNullOrWhiteSpace($RepositoryName)) {
    if (-not (Test-Path -LiteralPath $cwd -PathType Container)) {
        throw "WorktreeCreate cwd does not exist: $cwd"
    }
    $gitRoot = (& git -C $cwd rev-parse --show-toplevel 2>$null | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$gitRoot)) {
        throw "WorktreeCreate cwd is not inside a Git repository: $cwd"
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryName)) {
    $RepositoryName = Split-Path -Leaf ([string]$gitRoot).TrimEnd('\', '/')
}
$repositorySlug = ConvertTo-AgentHubSlug -Value $RepositoryName -FieldName 'repository'
$target = Get-AgentHubWorktreeTarget -Root $WorktreeRoot -Repository $repositorySlug -Task $taskSlug

if ($PlanOnly) {
    Write-Output $target
    exit 0
}

$resolvedGitRoot = [System.IO.Path]::GetFullPath([string]$gitRoot).TrimEnd('\')
if ((ConvertTo-AgentHubSlug -Value (Split-Path -Leaf $resolvedGitRoot) -FieldName 'repository') -ne $repositorySlug) {
    throw "RepositoryName '$RepositoryName' does not match the Git repository '$resolvedGitRoot'."
}

if (Test-Path -LiteralPath $target) {
    $registered = @(& git -C $resolvedGitRoot worktree list --porcelain 2>$null |
        Where-Object { $_ -like 'worktree *' } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_.Substring(9)).TrimEnd('\') })
    if ($target -notin $registered) {
        throw "Target exists but is not a registered worktree for this repository: $target"
    }
    Write-Output $target
    exit 0
}

$parent = Split-Path -Parent $target
New-Item -ItemType Directory -Path $parent -Force | Out-Null

$branch = "worktree-$taskSlug"
& git -C $resolvedGitRoot show-ref --verify --quiet "refs/heads/$branch"
$branchExists = $LASTEXITCODE -eq 0
if ($branchExists) {
    & git -C $resolvedGitRoot worktree add $target $branch
} else {
    & git -C $resolvedGitRoot worktree add -b $branch $target HEAD
}
if ($LASTEXITCODE -ne 0) {
    throw "git worktree add failed for '$target'."
}

Write-Output $target
