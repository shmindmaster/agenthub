#Requires -Version 5.1
<#
Test-side resolution of the gitignored personal overlay.

Production resolution is shared with scripts/lib/CapabilityGraph.ps1:
AGENTHUB_OVERLAY=off -> absent, AGENTHUB_OVERLAY=<dir> -> that directory,
otherwise <checkout>/overlays/personal and then the primary checkout's
overlay for a linked worktree. When none exists the caller prints one SKIP
line naming every location checked, so "absent" is never mistaken for a pass
of the private assertions.
#>

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repositoryRoot 'scripts\lib\CapabilityGraph.ps1')

function Resolve-AgentHubTestOverlay {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $resolution = Get-AgentHubOverlayRoot -RepositoryRoot $RepositoryRoot -PassThru
    if ($resolution.Root) {
        return [pscustomobject]@{ Root = $resolution.Root; Source = $resolution.Source; Reason = $null }
    }
    $reason = if ($resolution.Source -eq 'off') {
        'AGENTHUB_OVERLAY=off selects the public graph only'
    } else {
        "no personal overlay at: $($resolution.Checked -join '; ')"
    }
    return [pscustomobject]@{ Root = $null; Source = $resolution.Source; Reason = $reason }
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

# The policy a machine actually deploys: the overlay's global-agent-policy.md
# when an overlay resolves and carries one, otherwise the tracked public
# global-agent-policy.md. Mirrors scripts/lib/CapabilityGraph.ps1
# Resolve-AgentHubPolicyPath without its fail-closed throw (a test must still
# be able to read the public policy). IsOverlay tells the caller whether
# owner-specific assertions can apply.
function Get-AgentHubTestEffectivePolicy {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $overlay = Resolve-AgentHubTestOverlay -RepositoryRoot $RepositoryRoot
    if ($overlay.Root) {
        $private = Join-Path $overlay.Root 'global-agent-policy.md'
        if (Test-Path -LiteralPath $private -PathType Leaf) {
            return [pscustomobject]@{ Path = $private; IsOverlay = $true }
        }
    }
    return [pscustomobject]@{ Path = (Join-Path $RepositoryRoot 'global-agent-policy.md'); IsOverlay = $false }
}
