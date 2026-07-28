#Requires -Version 5.1
<#
.SYNOPSIS
    Safely reclaim stale agent-created git worktrees. Companion to the
    report-only Audit-Worktrees.ps1 -- this is the explicit cleanup step the
    worktree-management policy requires be kept separate from auditing.

.DESCRIPTION
    Enumerates every registered worktree across the portfolio (deduped by
    git common-dir, exactly as Audit-Worktrees.ps1 does) and re-checks LIVE
    state at removal time -- never trusting a possibly-stale audit for a
    destructive operation. A worktree is eligible only when all four technical
    gates pass:

        1. Not a main working tree.
        2. Clean            -- `git status --porcelain` is empty.
        3. Fully pushed     -- `git rev-list --count HEAD --not --remotes` == 0.
        4. Idle             -- no git/file activity within -MinIdleHours,
                               so a worktree an agent is actively using is
                               skipped even if momentarily clean.

    Apply also requires the exact worktree path in -ApprovedPath. Idle time is
    evidence, not ownership transfer; it never authorizes deletion by itself.

    Scope: only worktrees under the configured ephemeral roots are
    eligible by default. In-repo review siblings under -PortfolioRoot are
    report-only unless -IncludeInRepo is passed. Dirty / unpushed / busy
    worktrees are always reported and left in place.

    Also reports (never deletes): the non-git subops-monorepo COPIES the
    Playwright harness drops in the home dir, and orphaned worktree dirs git
    no longer tracks.

    Dry-run by default. Pass -Apply plus at least one exact -ApprovedPath to
    remove an eligible worktree. Removal uses non-forced `git worktree remove`.
    If Git fails, the script reports the failure and leaves the path untouched.

    Policy: C:\Repos\shmindmaster\agenthub\docs\worktree-management-policy.md

.EXAMPLE
    pwsh -File Remove-StaleWorktrees.ps1                  # report only (safe)
    pwsh -File Remove-StaleWorktrees.ps1 -Apply -ApprovedPath C:\path\to\worktree
    pwsh -File Remove-StaleWorktrees.ps1 -IncludeInRepo -Apply -ApprovedPath C:\path\to\worktree
#>
[CmdletBinding()]
param(
    [string]   $PortfolioRoot = 'C:\Repos\shmindmaster',
    [string[]] $EphemeralRoots = @(
        "$env:TEMP\opencode",
        "$env:TEMP\claude",
        "$env:TEMP\claude-worktrees"
    ),
    [string]   $HomeRoot     = $env:USERPROFILE,
    [int]      $MinIdleHours = 12,
    [switch]   $IncludeInRepo,
    [switch]   $Apply,
    [string[]] $ApprovedPath = @(),
    [string]   $OutputPath
)

$ErrorActionPreference = 'Stop'

if ($Apply -and $ApprovedPath.Count -eq 0) {
    throw '-Apply requires at least one -ApprovedPath.'
}

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = "$env:TEMP\agenthub-worktree-cleanup-$stamp.json"
}

function Write-Line($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Get-Norm($p) { ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant() }

# Most-recent activity: newest of worktree root mtime and its git metadata
# mtime (index / HEAD / logs). Cheap heuristic -- avoids walking node_modules.
function Get-IdleHours($p) {
    $times = @()
    try { $times += (Get-Item -LiteralPath $p).LastWriteTime } catch {}
    try {
        $gd = & git -C $p rev-parse --absolute-git-dir 2>$null
        if ($gd) {
            $gd = $gd -replace '/', '\'
            foreach ($f in @('index', 'HEAD', 'logs\HEAD')) {
                $fp = Join-Path $gd $f
                if (Test-Path -LiteralPath $fp) { $times += (Get-Item -LiteralPath $fp).LastWriteTime }
            }
        }
    } catch {}
    if ($times.Count -eq 0) { return 9999 }
    $newest = ($times | Sort-Object)[-1]
    return [math]::Round(((Get-Date) - $newest).TotalHours, 1)
}

$ephNorms = @($EphemeralRoots | ForEach-Object { Get-Norm $_ })
$approvedNorms = @{}
foreach ($approved in $ApprovedPath) {
    if (-not [string]::IsNullOrWhiteSpace($approved)) {
        $approvedNorms[(Get-Norm ([System.IO.Path]::GetFullPath($approved)))] = $true
    }
}
function Test-Ephemeral($p) {
    $n = Get-Norm $p
    foreach ($r in $ephNorms) { if ($n.StartsWith($r + '\')) { return $true } }
    return $false
}

# --- enumerate every registered worktree, deduped by common git-dir --------
$repoCandidates = Get-ChildItem -LiteralPath $PortfolioRoot -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') }

$seen        = @{}   # normalized worktree path -> record
$mainPaths   = @{}   # normalized main-tree paths (never touch)
$commonDirs  = @{}

foreach ($repo in $repoCandidates) {
    $common = & git -C $repo.FullName rev-parse --path-format=absolute --git-common-dir 2>$null
    if ($LASTEXITCODE -eq 0 -and $common) { $common = [System.IO.Path]::GetFullPath([string]$common) }
    else { $common = [System.IO.Path]::GetFullPath((Join-Path $repo.FullName '.git')) }
    if ($commonDirs.ContainsKey((Get-Norm $common))) { continue }
    $commonDirs[(Get-Norm $common)] = $true

    $lines = @(& git -C $repo.FullName worktree list --porcelain 2>$null)
    if (-not $lines) { continue }

    $wt = $null; $records = @()
    foreach ($line in $lines) {
        if ($line -like 'worktree *')  { if ($wt) { $records += $wt }; $wt = [ordered]@{ path = $line.Substring(9); detached = $false; branch = ''; owner = $repo.FullName } }
        elseif ($line -eq 'detached')  { $wt.detached = $true }
        elseif ($line -like 'branch *') { $wt.branch = ($line.Substring(7) -replace '^refs/heads/', '') }
    }
    if ($wt) { $records += $wt }
    if ($records.Count) { $mainPaths[(Get-Norm $records[0].path)] = $true }
    foreach ($r in ($records | Select-Object -Skip 1)) {
        $k = Get-Norm $r.path
        if (-not $seen.ContainsKey($k)) { $seen[$k] = $r }
    }
}

$eligible = @(); $removed = @(); $held = @(); $keptInRepo = @(); $failed = @()

foreach ($k in $seen.Keys) {
    $r = $seen[$k]
    $p = ($r.path -replace '/', '\')
    if ($mainPaths.ContainsKey($k)) { continue }
    if (-not (Test-Path -LiteralPath $p)) { continue }

    $dirty    = @(& git -C $p status --porcelain 2>$null).Count -gt 0
    $unpushed = 0
    try { $unpushed = [int](& git -C $p rev-list --count HEAD --not --remotes 2>$null) } catch { $unpushed = -1 }
    $label = "$p  [$($r.branch)$(if ($r.detached) { ' (detached)' })]"

    if ($dirty -or $unpushed -ne 0) {
        $held += [pscustomobject]@{ path = $p; branch = $r.branch; reason = 'dirty-or-unpushed'; dirty = $dirty; unpushed = $unpushed }
        Write-Line "  HOLD  $label  dirty=$dirty unpushed=$unpushed" 'Yellow'; continue
    }

    $idle = Get-IdleHours $p
    if ($MinIdleHours -gt 0 -and $idle -lt $MinIdleHours) {
        $held += [pscustomobject]@{ path = $p; branch = $r.branch; reason = 'busy'; idleHours = $idle }
        Write-Line "  BUSY  $label  active ${idle}h ago (< ${MinIdleHours}h)" 'Yellow'; continue
    }

    if (-not (Test-Ephemeral $p) -and -not $IncludeInRepo) {
        $keptInRepo += [pscustomobject]@{ path = $p; branch = $r.branch }
        Write-Line "  IN-REPO (clean+pushed+idle, kept; -IncludeInRepo to reap)  $label" 'DarkGray'; continue
    }

    $candidate = [pscustomobject]@{ path = $p; branch = $r.branch; idleHours = $idle }
    $eligible += $candidate

    if ($Apply) {
        if (-not $approvedNorms.ContainsKey((Get-Norm ([System.IO.Path]::GetFullPath($p))))) {
            $held += [pscustomobject]@{ path = $p; branch = $r.branch; reason = 'explicit-approval-required' }
            Write-Line "  HOLD  $label  exact -ApprovedPath not supplied" 'Yellow'
            continue
        }

        $gitOutput = @(& git -C $r.owner worktree remove $p 2>&1)
        $gitExit = $LASTEXITCODE
        if ($gitExit -ne 0 -or (Test-Path -LiteralPath $p)) {
            $failed += [pscustomobject]@{ path = $p; branch = $r.branch; reason = 'git-worktree-remove-failed'; exitCode = $gitExit }
            Write-Line "  ERROR git worktree remove failed; path preserved: $label" 'Red'
            if ($gitOutput.Count) { Write-Line "  Git reported an error; inspect manually without pruning metadata." 'Red' }
        }
        else {
            $removed += $candidate
            Write-Line "  REMOVED $label" 'Green'
        }
    }
    else { Write-Line "  ELIGIBLE (approval still required) $label" 'Cyan' }
}

# --- orphaned worktree dirs git no longer tracks (have a .git pointer) ------
$known = @{}; foreach ($k in $seen.Keys) { $known[$k] = $true }; foreach ($k in $mainPaths.Keys) { $known[$k] = $true }
$orphans = @()
foreach ($root in $EphemeralRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($known.ContainsKey((Get-Norm $_.FullName))) { return }
        if (Test-Path -LiteralPath (Join-Path $_.FullName '.git')) { $orphans += $_.FullName }
    }
}

# --- home-dir subops-monorepo COPIES (non-git harness leftovers) -----------
$homeCopies = @()
Get-ChildItem -LiteralPath $HomeRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $pkg = Join-Path $_.FullName 'package.json'
    if ((Test-Path -LiteralPath $pkg) -and -not (Test-Path -LiteralPath (Join-Path $_.FullName '.git'))) {
        try { if (((Get-Content -LiteralPath $pkg -Raw | ConvertFrom-Json).name) -eq 'subops-monorepo') { $homeCopies += $_.FullName } } catch {}
    }
}

# --- action report ---------------------------------------------------------
$report = [ordered]@{
    generatedAt   = (Get-Date).ToString('o')
    policy        = 'C:\Repos\shmindmaster\agenthub\docs\worktree-management-policy.md'
    applied       = [bool]$Apply
    minIdleHours  = $MinIdleHours
    includeInRepo = [bool]$IncludeInRepo
    approvedPaths = @($ApprovedPath)
    eligible      = @($eligible)
    removed       = @($removed)
    heldBack      = @($held)
    keptInRepo    = @($keptInRepo)
    orphanDirs    = @($orphans)
    homeCopies    = @($homeCopies)
    failed        = @($failed)
}
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Line ""
Write-Line "==================== SUMMARY ====================" 'White'
Write-Line ("{0} eligible worktree(s); explicit path approval required" -f $eligible.Count) 'Cyan'
Write-Line ("{0} worktree(s) removed" -f $removed.Count) 'Green'
Write-Line ("{0} held back (dirty / unpushed / busy)" -f $held.Count) 'Yellow'
if (-not $IncludeInRepo -and $keptInRepo.Count) { Write-Line ("{0} clean in-repo sibling(s) kept (-IncludeInRepo to reap)" -f $keptInRepo.Count) 'DarkGray' }
if ($orphans)    { Write-Line ("{0} orphaned worktree dir(s) -- review manually:" -f $orphans.Count) 'Magenta'; $orphans    | ForEach-Object { Write-Line "    $_" 'Magenta' } }
if ($homeCopies) { Write-Line ("{0} home-dir subops COPY(ies) -- NOT worktrees, delete manually:" -f $homeCopies.Count) 'Magenta'; $homeCopies | ForEach-Object { Write-Line "    $_" 'Magenta' } }
if ($failed)     { Write-Line ("{0} deletion error(s) -- file-locked; rerun later" -f $failed.Count) 'Red' }
Write-Line "Action report written to $OutputPath"
if (-not $Apply) { Write-Line "Dry-run only. Re-run with -Apply and an exact -ApprovedPath after owner release." 'Cyan' }
