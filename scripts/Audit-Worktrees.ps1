#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PortfolioRoot = "C:\Repos\shmindmaster",
    [string[]]$AdditionalPaths = @(
        "C:\Users\SaroshHussain\subops-wt-extractor",
        "C:\Users\SaroshHussain\wt-agents",
        "C:\Users\SaroshHussain\wt95",
        "C:\Repos\shmindmaster\.worktrees",
        "C:\Repos\shmindmaster\.wt",
        "C:\Repos\shmindmaster\lawli-worktrees"
    ),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = "$env:TEMP\agent-capabilities-worktree-audit-$stamp.json"
}

function Get-WorktreeBlocks {
    param([string[]]$Lines)

    $blocks = [System.Collections.Generic.List[object]]::new()
    $current = [ordered]@{}
    foreach ($line in @($Lines) + '') {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $blocks.Add([pscustomobject]$current)
                $current = [ordered]@{}
            }
            continue
        }

        $parts = $line -split ' ', 2
        $key = $parts[0]
        $value = if ($parts.Count -gt 1) { $parts[1] } else { $true }
        $current[$key] = $value
    }
    return $blocks
}

function Get-CheckoutRecord {
    param(
        [string]$OwnerRoot,
        [string]$Path,
        [string]$Head,
        [string]$Branch,
        [bool]$Registered,
        [string]$InitialKind = 'RegisteredWorktree'
    )

    $exists = Test-Path -LiteralPath $Path
    $kind = $InitialKind
    $changeCount = $null
    $upstream = $null
    $ahead = $null
    $behind = $null
    $generated = @()
    $risks = [System.Collections.Generic.List[string]]::new()

    if ($exists) {
        foreach ($name in @('node_modules', '.next', 'dist', 'build', '.turbo', 'coverage', 'test-results')) {
            if (Test-Path -LiteralPath (Join-Path $Path $name)) { $generated += $name }
        }

        $inside = & git -C $Path rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
            $statusLines = @(& git -C $Path status --porcelain=v1 --untracked-files=normal 2>$null)
            if ($LASTEXITCODE -eq 0) { $changeCount = $statusLines.Count }

            if ($Branch -and $Branch -ne '(detached)') {
                $upstreamValue = & git -C $Path rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null
                if ($LASTEXITCODE -eq 0 -and $upstreamValue) {
                    $upstream = [string]$upstreamValue
                    $counts = (& git -C $Path rev-list --left-right --count "$upstream...HEAD" 2>$null) -split '\s+'
                    if ($LASTEXITCODE -eq 0 -and $counts.Count -ge 2) {
                        $behind = [int]$counts[0]
                        $ahead = [int]$counts[1]
                    }
                } else {
                    $risks.Add('no-upstream')
                }
            } elseif ($Branch -eq '(detached)') {
                $risks.Add('detached-head')
            }
        }
    } elseif ($Registered) {
        $risks.Add('registered-path-missing')
    } else {
        $kind = 'AbsentKnownPath'
    }

    if ($null -ne $changeCount -and $changeCount -gt 0) { $risks.Add('dirty-or-untracked') }
    if ($null -ne $ahead -and $ahead -gt 0) { $risks.Add('unpushed-commits') }
    if ($generated.Count -gt 0) { $risks.Add('generated-files-present') }
    if (-not $Registered) { $risks.Add('not-registered-to-discovered-repository') }

    [pscustomobject]@{
        ownerRoot = $OwnerRoot
        path = $Path
        kind = $kind
        registered = $Registered
        exists = $exists
        head = $Head
        branch = $Branch
        upstream = $upstream
        ahead = $ahead
        behind = $behind
        changeCount = $changeCount
        generatedRoots = $generated
        risks = @($risks)
    }
}

$records = [System.Collections.Generic.List[object]]::new()
$registeredPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$commonGitDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$repoCandidates = Get-ChildItem -LiteralPath $PortfolioRoot -Directory -Force | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName '.git')
}

foreach ($repo in $repoCandidates) {
    $commonDir = & git -C $repo.FullName rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -eq 0 -and $commonDir) {
        $commonDir = [System.IO.Path]::GetFullPath([string]$commonDir)
    } else {
        $commonDir = [System.IO.Path]::GetFullPath((Join-Path $repo.FullName '.git'))
    }
    if (-not $commonGitDirs.Add($commonDir)) { continue }

    $lines = @(& git -C $repo.FullName worktree list --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath (Join-Path $repo.FullName '.git') -PathType Container)) {
        $lines = @(& git "--git-dir=$($repo.FullName)\.git" worktree list --porcelain 2>$null)
    }

    if ($LASTEXITCODE -ne 0 -or $lines.Count -eq 0) {
        $records.Add([pscustomobject]@{
            ownerRoot = $repo.FullName
            path = $repo.FullName
            kind = 'InvalidRepositoryMetadata'
            registered = $false
            exists = $true
            head = $null
            branch = $null
            upstream = $null
            ahead = $null
            behind = $null
            changeCount = $null
            generatedRoots = @()
            risks = @('git-worktree-list-failed')
        })
        continue
    }

    foreach ($block in Get-WorktreeBlocks -Lines $lines) {
        $path = [string]$block.worktree
        if (-not $path) { continue }
        $null = $registeredPaths.Add([System.IO.Path]::GetFullPath($path))
        $branch = if ($block.branch) { ([string]$block.branch) -replace '^refs/heads/', '' } elseif ($block.detached) { '(detached)' } else { $null }
        $records.Add((Get-CheckoutRecord -OwnerRoot $repo.FullName -Path $path -Head ([string]$block.HEAD) -Branch $branch -Registered $true))
    }
}

foreach ($path in $AdditionalPaths) {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    if ($registeredPaths.Contains($fullPath)) { continue }
    $records.Add((Get-CheckoutRecord -OwnerRoot $null -Path $fullPath -Head $null -Branch $null -Registered $false -InitialKind 'UnregisteredDirectory'))
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    policy = 'C:\Repos\agent-capabilities\docs\worktree-management-policy.md'
    portfolioRoot = $PortfolioRoot
    recordCount = $records.Count
    records = @($records | Sort-Object path)
}

$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

$records | Group-Object kind | Sort-Object Name | Select-Object Name, Count | Format-Table -AutoSize
Write-Host "Report-only audit written to $OutputPath"
