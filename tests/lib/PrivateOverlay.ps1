#Requires -Version 5.1
<#
Test-side resolution of the gitignored personal overlay.

Production resolves the overlay in scripts/lib/CapabilityGraph.ps1
(Get-AgentHubOverlayRoot): AGENTHUB_OVERLAY=off -> none, AGENTHUB_OVERLAY=<dir>
-> that directory, otherwise <checkout>/overlays/personal. The overlay is
gitignored, so a linked worktree under C:\wt never contains it: the operator
machine's overlay lives in the primary checkout that owns the worktree. Tests
that assert facts about private packages therefore resolve it in this order:

  1. AGENTHUB_OVERLAY=off            -> absent (the caller asked for the public graph)
  2. AGENTHUB_OVERLAY=<dir>          -> that directory (the documented override)
  3. <repo>/overlays/personal        -> the documented in-checkout location
  4. <primary checkout>/overlays/personal, when <repo> is a linked worktree
     (read from <repo>/.git -> gitdir -> commondir; no git process is spawned)

When none exists the caller prints one SKIP line naming every location that
was checked and reports nothing else, so "absent" is never mistaken for a
pass of the private assertions. Production resolution is deliberately not
changed here; see docs/architecture/control-plane-modules.md -> Overlay.
#>

function Get-AgentHubPrimaryCheckoutRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $dotGit = Join-Path $RepositoryRoot '.git'
    if (-not (Test-Path -LiteralPath $dotGit -PathType Leaf)) { return $null }
    $line = (Get-Content -LiteralPath $dotGit -Raw -Encoding UTF8).Trim()
    if ($line -notmatch '^gitdir:\s*(.+)$') { return $null }
    $gitDir = $Matches[1].Trim()
    if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $RepositoryRoot $gitDir }
    $commonFile = Join-Path $gitDir 'commondir'
    if (-not (Test-Path -LiteralPath $commonFile -PathType Leaf)) { return $null }
    $common = (Get-Content -LiteralPath $commonFile -Raw -Encoding UTF8).Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $gitDir $common }
    $common = [IO.Path]::GetFullPath($common).TrimEnd('\', '/')
    # A bare common directory has no primary checkout to borrow an overlay from.
    if ((Split-Path -Leaf $common) -ne '.git') { return $null }
    return Split-Path -Parent $common
}

function Resolve-AgentHubTestOverlay {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $checked = [Collections.Generic.List[string]]::new()
    if ($env:AGENTHUB_OVERLAY -eq 'off') {
        return [pscustomobject]@{ Root = $null; Source = 'off'; Reason = 'AGENTHUB_OVERLAY=off selects the public graph only' }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_OVERLAY)) {
        $explicit = [IO.Path]::GetFullPath($env:AGENTHUB_OVERLAY).TrimEnd('\', '/')
        if (Test-Path -LiteralPath (Join-Path $explicit 'overlay.json') -PathType Leaf) {
            return [pscustomobject]@{ Root = $explicit; Source = 'AGENTHUB_OVERLAY'; Reason = $null }
        }
        $checked.Add("AGENTHUB_OVERLAY=$explicit (no overlay.json)")
    }
    $local = Join-Path $RepositoryRoot 'overlays\personal'
    if (Test-Path -LiteralPath (Join-Path $local 'overlay.json') -PathType Leaf) {
        return [pscustomobject]@{ Root = $local; Source = 'checkout'; Reason = $null }
    }
    $checked.Add($local)
    $primary = Get-AgentHubPrimaryCheckoutRoot -RepositoryRoot $RepositoryRoot
    if ($primary) {
        $shared = Join-Path $primary 'overlays\personal'
        if (Test-Path -LiteralPath (Join-Path $shared 'overlay.json') -PathType Leaf) {
            return [pscustomobject]@{ Root = $shared; Source = 'primary-checkout'; Reason = $null }
        }
        $checked.Add($shared)
    }
    return [pscustomobject]@{
        Root = $null; Source = 'absent'
        Reason = "no personal overlay (overlay.json) at: $($checked -join '; ')"
    }
}

# Repository-relative overlay path (as recorded in canonicalSource, e.g.
# overlays/personal/packages/<id>) rebased onto the resolved overlay root.
function Resolve-AgentHubTestOverlayPath {
    param(
        [Parameter(Mandatory)][string]$OverlayRoot,
        [Parameter(Mandatory)][string]$RelativeToOverlay
    )
    return Join-Path $OverlayRoot ($RelativeToOverlay -replace '/', '\')
}
