#Requires -Version 5.1
<#
.SYNOPSIS
    Regenerates each host's global instruction file from the canonical
    global-agent-policy.md and syncs it into the host's documented
    destination. Self-derives its repository root from this script's own
    on-disk location unless -RepositoryRoot is passed explicitly.

.DESCRIPTION
    Reads registry/agents.json for each host's instructionHeader,
    instructionFormat, and destination (a single file, or -- for hosts that
    declare instructionsDestinationKind = 'directory' -- a directory a file
    must be written inside). By default renders <header> + blank +
    <!-- agenthub:managed --> + blank + <canonical body>. A host whose real
    deployed layout differs (currently only Hermes: an identity preamble
    before the policy, and the managed marker at the end of the file
    instead of after the header) instead declares
    nativePaths.instructionBodyTemplate in the registry -- a template
    containing a {{globalPolicy}} placeholder that fully owns the layout,
    including marker placement, so there is no per-host code branch for
    this. Stages the rendered bytes under
    %LOCALAPPDATA%\AgentHub\runtime\instructions\<hostId>\ (or the
    -UserProfile-relative equivalent under test), and either reports drift
    (-Audit, the default) or writes the destination (-Apply).

    A destination that exists but lacks the <!-- agenthub:managed --> marker
    is reported 'unmanaged' and is never written -- this is what stops a
    fleet sync from destroying hand-written user policy. Any run with at
    least one unmanaged host exits non-zero, in both -Audit and -Apply mode,
    because it reflects a real state an -Apply run could not clear.

.PARAMETER Audit
    Report per-host drift without writing any destination. Default mode.

.PARAMETER Apply
    Write destinations that are 'missing' or 'drift'. Never writes an
    'unmanaged' destination.

.PARAMETER RepositoryRoot
    Repository root to read registry/agents.json and global-agent-policy.md
    from. Self-derived from this script's own path when omitted.

.PARAMETER UserProfile
    User-profile root whose native destinations are audited/written.
    Defaults to $env:USERPROFILE. Overriding it also reroutes the staging
    directory away from the invoking user's live %LOCALAPPDATA%, so a test
    run against a synthetic profile never touches real AgentHub runtime
    state (same guard Sync-AgentHub.ps1 uses for the same reason).
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$RepositoryRoot,
    [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

if ($Apply -and $Audit) {
    throw "Specify only one of -Audit or -Apply, not both."
}
# -Audit is the default mode: any invocation that did not pass -Apply audits.
if (-not $Apply) { $Audit = $true }

# ---------------------------------------------------------------------------
# Path resolution -- self-derived, never hardcoded to one checkout (this is
# exactly the class of defect 61b6c0c fixed in Sync-AgentHub.ps1; do not
# reintroduce it here).
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')

. (Join-Path $PSScriptRoot 'lib\PathBinding.ps1')
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    $UserProfile = Get-AgentHubDefaultHome
}
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = Get-AgentHubNormalizedDirectory $UserProfile

# Reroute the staging root away from the invoking user's live %LOCALAPPDATA%
# whenever -UserProfile is overridden. Without this, a test run against a
# temp -UserProfile would still stage rendered files under the real,
# machine-wide %LOCALAPPDATA%\AgentHub -- a synthetic profile must never
# contaminate live AgentHub runtime state merely because LOCALAPPDATA was
# inherited from the actual process environment.
$invokingUserProfile = Get-AgentHubNormalizedDirectory (Get-AgentHubDefaultHome)
$requestedPlatform = Get-AgentHubRequestedPlatform -RepositoryRoot $RepositoryRoot
$effectiveLocalAppData = Get-AgentHubIsolatedLocalData -TargetUserProfile $UserProfile -InvokingUserProfile $invokingUserProfile -LocalAppData $env:LOCALAPPDATA -Platform $requestedPlatform

$RegistryDir = Join-Path $RepositoryRoot 'registry'
$AgentsFile  = Join-Path $RegistryDir 'agents.json'
. (Join-Path $PSScriptRoot 'lib\CapabilityGraph.ps1')
. (Join-Path $PSScriptRoot 'lib\HostCatalog.ps1')
$PolicyFile  = Resolve-AgentHubPolicyPath -RepositoryRoot $RepositoryRoot
$StagingRoot = Join-AgentHubPlatformPath -Platform (Get-AgentHubPlatformId $requestedPlatform) -Base $effectiveLocalAppData -Child 'AgentHub/runtime/instructions'

# ---------------------------------------------------------------------------
# Fail loudly on missing inputs -- never silently proceed against a partial
# or wrong tree.
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $AgentsFile)) {
    throw "Missing registry file: $AgentsFile"
}
if (-not (Test-Path -LiteralPath $PolicyFile)) {
    throw "Missing canonical policy document: $PolicyFile"
}

$Marker = '<!-- agenthub:managed -->'
# Normalize to LF. Without this the deployed bytes carry whatever line endings
# the checkout happened to have, so the same commit deployed from a CRLF
# worktree and audited from an LF checkout reports drift on every host while
# each checkout reports itself clean. LF is the canonical form: it is what git
# stores and what the content hasher normalizes to before hashing.
$PolicyBody = [System.IO.File]::ReadAllText($PolicyFile).Replace("`r`n", "`n")
if ([string]::IsNullOrWhiteSpace($PolicyBody)) {
    throw "Canonical policy document is empty: $PolicyFile"
}

function Write-Utf8NoBomLf {
    param([string]$Path, [string]$Content)
    # Every deployed instruction file (confirmed by reading the real
    # ~/.claude/CLAUDE.md and ~/.../hermes/SOUL.md bytes) uses plain LF line
    # endings and no BOM -- match that exactly rather than defaulting to
    # Windows CRLF, which would make every render byte-mismatch the deployed
    # files on line endings alone.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# Cursor's rules directory needs one stable, deliberately-chosen filename so
# repeated runs stay idempotent. 'agenthub-global-policy.mdc' is namespaced
# with the same 'agenthub' prefix used by the managed marker itself, and
# uses the .mdc extension recorded in the registry's instructionFormat field
# for Cursor -- which Task 1 explicitly flagged as an unverified inference,
# not read from a real deployed file (the directory was empty). Because that
# format is unverified, this renderer deliberately does NOT invent
# Cursor-specific MDC frontmatter (e.g. a `---\nalwaysApply: true\n---`
# block) it cannot confirm Cursor's real parser expects -- it writes the
# same plain header/marker/body structure used by every other host. See
# task-2-report.md for the full discussion.
$CursorRulesFileName = 'agenthub-global-policy.mdc'

# The token a host's registry-declared instructionBodyTemplate uses to mark
# where the canonical policy body is substituted in. See Hermes below for
# why this exists.
$GlobalPolicyPlaceholder = '{{globalPolicy}}'

function Get-RenderedInstructionContent {
    param(
        [Parameter(Mandatory)][string]$HostId,
        [Parameter(Mandatory)][string]$Header,
        [string]$BodyTemplate
    )
    if (-not [string]::IsNullOrWhiteSpace($BodyTemplate)) {
        # A host with an instructionBodyTemplate (currently only Hermes) has
        # a real deployed layout that is NOT the generic header/blank/
        # marker/blank/body contract -- it can carry a preamble BEFORE the
        # policy and/or place the managed marker somewhere other than right
        # after the header. The template fully owns that layout, including
        # marker placement, so there is no per-host special case in this
        # function: any host with a template gets exactly one substitution
        # of the canonical body into the placeholder, nothing more.
        $occurrences = ([regex]::Matches($BodyTemplate, [regex]::Escape($GlobalPolicyPlaceholder))).Count
        if ($occurrences -ne 1) {
            throw "Host '$HostId' declares nativePaths.instructionBodyTemplate but it contains $occurrences occurrences of '$GlobalPolicyPlaceholder' (expected exactly 1). Refusing to guess which one is the real insertion point."
        }
        return $BodyTemplate.Replace($GlobalPolicyPlaceholder, $PolicyBody)
    }
    return "$Header`n`n$Marker`n`n$PolicyBody"
}

# ---------------------------------------------------------------------------
# Registry load
# ---------------------------------------------------------------------------
$agentsReg = Get-Content -LiteralPath $AgentsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$script:instructionPathBinding = New-AgentHubPathBindingContext -TargetUserProfile $UserProfile -InvokingUserProfile $invokingUserProfile -RegistryUserProfile (Get-AgentHubRecordedUserProfile $agentsReg) -Platform $requestedPlatform
Import-AgentHubBoundHostCatalog -AgentsDocument $agentsReg -Context $script:instructionPathBinding | Out-Null

function ConvertTo-EffectiveUserPath {
    param([string]$Path)
    return Resolve-AgentHubBoundPath -Declared $Path -Context $script:instructionPathBinding
}

# PathBinding rebases recorded absolutes from the registry profile, or from
# the invoking profile when the registry no longer records one. A missing
# userProfile field is therefore not a silent live write: destinations under
# the invoking profile move to -UserProfile. UNC and forward-slash shapes
# still throw inside Resolve-AgentHubBoundPath.

# Instructions go to EVERY host, active or inactive. This differs from
# Sync-Capabilities, which skips inactive hosts by default, and the asymmetry is
# deliberate -- do not "fix" it into consistency.
#
# The two have opposite failure modes. Skills are bulk file copies, so deploying
# them to a host nobody uses wastes real space, and an over-broad prune based on
# a stale 'inactive' label once removed 158 directories. Instructions are one
# small policy file per host, and the cost of writing one unnecessarily is
# nothing. The cost of NOT writing one is that a host somebody actually launches
# runs on stale policy -- silently, because a skipped host reports success.
#
# 'inactive' is a human-maintained label, and this repository has already been
# burned once by treating a stale one as authoritative. Instructions therefore
# fail safe in the direction of over-delivery: correct policy everywhere beats
# current policy only where a label happens to be accurate.
# Pinned by Test-SyncInstructions.ps1 'instructions reach inactive hosts too'.
$allHosts = @()
if ($agentsReg.PSObject.Properties['activeAgents'] -and $agentsReg.activeAgents) {
    $allHosts += @($agentsReg.activeAgents)
}
if ($agentsReg.PSObject.Properties['inactiveAgents'] -and $agentsReg.inactiveAgents) {
    $allHosts += @($agentsReg.inactiveAgents)
}
if (@($allHosts).Count -eq 0) {
    throw "Registry root '$RepositoryRoot' resolved to zero hosts in $AgentsFile. Refusing to report success against what looks like an empty or wrong registry tree; pass -RepositoryRoot explicitly if this is intentional."
}

# ---------------------------------------------------------------------------
# Per-host destination resolution
# ---------------------------------------------------------------------------
function Resolve-HostTarget {
    param([Parameter(Mandatory)]$Agent)

    $hostId = [string]$Agent.id
    $paths = $Agent.nativePaths
    if (-not $paths) {
        return [pscustomobject]@{ HostId = $hostId; Kind = 'none' }
    }

    $isDirectoryTarget = $paths.PSObject.Properties['instructionsDestinationKind'] -and
        [string]$paths.instructionsDestinationKind -eq 'directory'

    if ($isDirectoryTarget) {
        $rulesDir = if ($paths.PSObject.Properties['rulesDir']) { [string]$paths.rulesDir } else { $null }
        if ([string]::IsNullOrWhiteSpace($rulesDir)) {
            throw "Host '$hostId' declares nativePaths.instructionsDestinationKind = 'directory' but has no nativePaths.rulesDir."
        }
        $fileName = $CursorRulesFileName
        $destinationDir = ConvertTo-EffectiveUserPath $rulesDir
        $destinationPath = Join-Path $destinationDir $fileName
    } elseif ($paths.PSObject.Properties['instructions'] -and
              -not [string]::IsNullOrWhiteSpace([string]$paths.instructions)) {
        $destinationPath = ConvertTo-EffectiveUserPath ([string]$paths.instructions)
        $fileName = Split-Path -Leaf $destinationPath
        $destinationDir = Split-Path -Parent $destinationPath
    } else {
        # Covers both "instructions": null with "verification":
        # "documentation-not-read" (8 hosts) and any host with no
        # nativePaths.instructions key at all -- both mean "no known
        # destination," which must audit as skipped, never as an error.
        return [pscustomobject]@{ HostId = $hostId; Kind = 'none' }
    }

    $headerSource = 'registry'
    if ($paths.PSObject.Properties['instructionHeader'] -and
        -not [string]::IsNullOrWhiteSpace([string]$paths.instructionHeader)) {
        $header = [string]$paths.instructionHeader
    } else {
        # copilot (file deleted), cursor (directory currently empty), and
        # windsurf (0-byte file) all carry instructionHeader: null in the
        # registry per Task 1 -- there was no live line 1 to read without
        # inventing one. Deriving a fallback here, following the exact
        # "# <name> Global Instructions" pattern already used by every host
        # whose header WAS read from a real file, lets this renderer still
        # produce content for those three when needed (e.g. -Apply against a
        # fresh profile). Flagged explicitly so it is never confused with a
        # value verified against a live deployed file.
        $header = "# $($Agent.name) Global Instructions"
        $headerSource = 'derived-fallback'
    }

    # A host whose real deployed layout is not the generic header/marker/
    # body contract (currently only Hermes: identity preamble before the
    # policy, managed marker at the end of the file) declares
    # nativePaths.instructionBodyTemplate. This is read generically here --
    # nothing in this function or the renderer checks $hostId against a
    # literal host name; marker placement and any preamble live entirely in
    # the registry data.
    $bodyTemplate = if ($paths.PSObject.Properties['instructionBodyTemplate'] -and
        -not [string]::IsNullOrWhiteSpace([string]$paths.instructionBodyTemplate)) {
        [string]$paths.instructionBodyTemplate
    } else {
        $null
    }

    return [pscustomobject]@{
        HostId            = $hostId
        Kind              = 'destination'
        DestinationPath   = $destinationPath
        DestinationDir    = $destinationDir
        FileName          = $fileName
        Header            = $header
        HeaderSource      = $headerSource
        IsDirectoryTarget = [bool]$isDirectoryTarget
        BodyTemplate      = $bodyTemplate
    }
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$workSetCount = 0
$hasUnmanaged = $false

foreach ($agent in $allHosts) {
    $target = Resolve-HostTarget -Agent $agent

    if ($target.Kind -eq 'none') {
        $results.Add([pscustomobject]@{
            HostId = $target.HostId; State = 'skipped (no destination)'
            Path = $null; Action = 'none'; HeaderSource = $null
        })
        continue
    }

    $workSetCount++
    $expectedContent = Get-RenderedInstructionContent -HostId $target.HostId -Header $target.Header -BodyTemplate $target.BodyTemplate

    # Stage the rendered bytes for inspection regardless of mode. Always
    # under %LOCALAPPDATA%\AgentHub\runtime\instructions\<hostId>\ (or its
    # -UserProfile-relative equivalent), never under a tracked repo
    # directory (AGENTS.md:20 forbids generated/).
    $stagingDir = Join-Path $StagingRoot $target.HostId
    if (-not (Test-Path -LiteralPath $stagingDir)) {
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    }
    Write-Utf8NoBomLf -Path (Join-Path $stagingDir $target.FileName) -Content $expectedContent

    $destExists = Test-Path -LiteralPath $target.DestinationPath
    if (-not $destExists) {
        # A missing parent directory is also "missing," not an error -- the
        # -Apply path below creates it. We do not probe whether the host
        # software itself is installed: Task 1 only ever recorded a real
        # nativePaths.instructions/rulesDir for hosts it verified against a
        # real local install, so every host reaching this branch already
        # cleared that bar; the 8 hosts with no verified destination never
        # reach here (Kind = 'none', handled above).
        $state = 'missing'
    } else {
        $existingContent = [System.IO.File]::ReadAllText($target.DestinationPath)
        if ($existingContent.IndexOf($Marker, [StringComparison]::Ordinal) -lt 0) {
            $state = 'unmanaged'
            $hasUnmanaged = $true
        } elseif ($existingContent -ceq $expectedContent) {
            $state = 'current'
        } else {
            $state = 'drift'
        }
    }

    $action = 'none'
    if ($Apply) {
        if ($state -eq 'missing' -or $state -eq 'drift') {
            if ($target.IsDirectoryTarget) {
                if (-not (Test-Path -LiteralPath $target.DestinationDir)) {
                    New-Item -ItemType Directory -Path $target.DestinationDir -Force | Out-Null
                } elseif (-not (Test-Path -LiteralPath $target.DestinationDir -PathType Container)) {
                    throw "Host '$($target.HostId)' declares a directory destination at '$($target.DestinationDir)' but a file exists there instead. Refusing to replace it."
                }
                # Write a file INSIDE the directory; the directory itself is
                # never replaced or deleted.
            } else {
                if (-not (Test-Path -LiteralPath $target.DestinationDir)) {
                    New-Item -ItemType Directory -Path $target.DestinationDir -Force | Out-Null
                }
            }
            Write-Utf8NoBomLf -Path $target.DestinationPath -Content $expectedContent
            $action = 'updated'
        } elseif ($state -eq 'unmanaged') {
            # Refuse to write. This is the load-bearing guard: an unmanaged
            # destination is real, hand-written user content, not a stale
            # AgentHub render, and must never be overwritten by a fleet sync.
            $action = 'refused'
        }
    }

    $results.Add([pscustomobject]@{
        HostId = $target.HostId; State = $state
        Path = $target.DestinationPath; Action = $action
        HeaderSource = $target.HeaderSource
    })
}

if ($workSetCount -eq 0) {
    throw "Zero hosts resolved to a real instruction destination out of $(@($allHosts).Count) hosts in the registry. Refusing to report success against an empty work set."
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$mode = if ($Apply) { 'Apply' } else { 'Audit' }
Write-Host "Sync-Instructions ($mode) -- RepositoryRoot=$RepositoryRoot UserProfile=$UserProfile"
Write-Host ("{0,-20} {1,-25} {2,-10} {3}" -f 'HOSTID', 'STATE', 'ACTION', 'PATH')
foreach ($r in $results) {
    Write-Host ("{0,-20} {1,-25} {2,-10} {3}" -f $r.HostId, $r.State, $r.Action, $r.Path)
}

$counts = @{
    current   = @($results | Where-Object State -eq 'current').Count
    drift     = @($results | Where-Object State -eq 'drift').Count
    missing   = @($results | Where-Object State -eq 'missing').Count
    unmanaged = @($results | Where-Object State -eq 'unmanaged').Count
    skipped   = @($results | Where-Object State -eq 'skipped (no destination)').Count
    updated   = @($results | Where-Object Action -eq 'updated').Count
}
Write-Host ("SUMMARY: current={0} drift={1} missing={2} unmanaged={3} skipped={4} updated={5} total={6} workSet={7}" -f `
    $counts.current, $counts.drift, $counts.missing, $counts.unmanaged, $counts.skipped, $counts.updated, $results.Count, $workSetCount)

if ($hasUnmanaged) {
    Write-Host "REFUSED: one or more hosts are unmanaged (a destination exists without the $Marker marker). Refusing to overwrite hand-written policy at those destinations. This run is a failure, not a partial success." -ForegroundColor Red
    exit 1
}

Write-Host "Sync-Instructions complete: $($results.Count) hosts evaluated, $workSetCount with a real destination." -ForegroundColor Green
exit 0
