#Requires -Version 5.1
<#
.SYNOPSIS
    Detect git object stores and regenerable build dirs inside folders 01-06 and 10.

.DESCRIPTION
    Report only. Does not move or delete anything. A HOLD row still needs
    a human (or an explicit later authorization) before any copy off
    OneDrive.
#>
[CmdletBinding()]
param(
    [string]$DocumentsRoot = 'D:\OneDrive - MahumTech\Documents',
    [string]$CsvPath
)

$ErrorActionPreference = 'Continue'

$roots = @(
    (Join-Path $DocumentsRoot '01_Business_and_Entities'),
    (Join-Path $DocumentsRoot '02_Client_Work'),
    (Join-Path $DocumentsRoot '03_Products_and_Startups'),
    (Join-Path $DocumentsRoot '04_Career_and_Public_Profile'),
    (Join-Path $DocumentsRoot '05_Methodologies_Templates_and_Accelerators'),
    (Join-Path $DocumentsRoot '06_Research_and_Knowledge_Base'),
    (Join-Path $DocumentsRoot '10_Certifications_Prep')
)

# Compiler/package caches only. Do not treat a documents folder named
# "Build" as regenerable — this tree uses that name for delivery kits.
$regenerable = @(
    'node_modules', '.venv', 'venv', 'env', '__pycache__', '.pytest_cache',
    '.mypy_cache', 'dist', 'out', '.next', '.nuxt', 'target',
    '.turbo', '.gradle', '.tox', '.ipynb_checkpoints'
)

if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $env:USERPROFILE 'Desktop\code-in-knowledge.csv'
}

$found = foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) {
        Write-Warning "missing: $r"
        continue
    }
    Get-ChildItem -LiteralPath $r -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' -or $regenerable -contains $_.Name } |
        ForEach-Object {
            $files = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
            $sum = 0L
            if ($files.Count -gt 0) {
                $sum = [int64]($files | Measure-Object Length -Sum).Sum
            }
            [pscustomobject]@{
                Kind     = if ($_.Name -eq '.git') { 'REPO' } else { 'REGENERABLE' }
                Name     = $_.Name
                Files    = $files.Count
                MB       = [math]::Round($sum / 1MB, 1)
                RepoRoot = if ($_.Name -eq '.git') { $_.Parent.FullName } else { '' }
                Path     = $_.FullName
            }
        }
}

$rows = @($found)
$rows | Sort-Object MB -Descending | Format-Table -AutoSize
$destDir = Split-Path -Parent $CsvPath
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}
$rows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
Write-Output ("wrote {0} ({1} rows)" -f $CsvPath, $rows.Count)

$repos = @($rows | Where-Object { $_.Kind -eq 'REPO' -and $_.RepoRoot })
if ($repos.Count -eq 0) {
    Write-Output 'no nested git repos detected in 01-06 or 10'
    exit 0
}

Write-Output ''
Write-Output 'nested git repos (verify before any move):'
$repoRows = foreach ($repo in $repos) {
    $p = $repo.RepoRoot
    $dirty = git -C $p status --porcelain 2>$null
    $url = git -C $p remote get-url origin 2>$null
    $owner = $null
    if ($url -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?$') { $owner = $Matches[1] }
    $unpushed = if ($url) { git -C $p log --oneline '@{u}..HEAD' 2>$null } else { 'NO-REMOTE' }
    $state = if (-not $url) { 'NO REMOTE — only copy' }
        elseif ($dirty -or $unpushed) { 'HOLD — commit and push first' }
        else { 'ready' }
    [pscustomobject]@{
        Repo   = Split-Path $p -Leaf
        Owner  = if ($owner) { $owner } else { '(none)' }
        Target = if ($owner) { "C:\Repos\$owner" } else { 'C:\Repos\_unsorted — route by hand' }
        State  = $state
        Path   = $p
    }
}
$repoRows | Format-Table -AutoSize
