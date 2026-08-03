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
    must be written inside). Renders <header> + blank + <!-- agenthub:managed
    --> + blank + <canonical body> (Hermes is a documented exception -- see
    "Hermes" below), stages the rendered bytes under
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

if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = [System.IO.Path]::GetFullPath($UserProfile).TrimEnd('\')

# Reroute the staging root away from the invoking user's live %LOCALAPPDATA%
# whenever -UserProfile is overridden. Without this, a test run against a
# temp -UserProfile would still stage rendered files under the real,
# machine-wide %LOCALAPPDATA%\AgentHub -- a synthetic profile must never
# contaminate live AgentHub runtime state merely because LOCALAPPDATA was
# inherited from the actual process environment.
$effectiveLocalAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA)
$invokingUserProfile = if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $null
} else {
    [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
}
if ($invokingUserProfile -and
    -not $UserProfile.Equals($invokingUserProfile, [StringComparison]::OrdinalIgnoreCase)) {
    $invokingLocalAppData = [System.IO.Path]::GetFullPath(
        (Join-Path $invokingUserProfile 'AppData\Local')
    ).TrimEnd('\')
    if ($effectiveLocalAppData.TrimEnd('\').Equals(
        $invokingLocalAppData,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        $effectiveLocalAppData = Join-Path $UserProfile 'AppData\Local'
    }
}

$RegistryDir = Join-Path $RepositoryRoot 'registry'
$AgentsFile  = Join-Path $RegistryDir 'agents.json'
$PolicyFile  = Join-Path $RepositoryRoot 'global-agent-policy.md'
$StagingRoot = Join-Path $effectiveLocalAppData 'AgentHub\runtime\instructions'

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
$PolicyBody = [System.IO.File]::ReadAllText($PolicyFile)
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

# Hermes' currently-deployed file (C:\Users\SaroshHussain\AppData\Local\
# hermes\SOUL.md, read during this task) uses a persona-preamble layout, not
# the standard header/marker/body layout every other host uses: the header
# is followed by a persona paragraph, then the canonical body, and the
# <!-- agenthub:managed --> marker sits at the very END of the file (line 45
# of 45), not right after the header. Per this task's dispatch: "if the
# byte layout you measure from the deployed files disagrees with the
# brief's render contract, the deployed files win." This text is
# transcribed verbatim from that real file because no registry field
# captures it -- it is not invented. See task-2-report.md for the
# byte-level `od -c` evidence.
$HermesPersonaPreamble = 'You are Hermes Agent, an intelligent AI assistant created by Nous Research. Be helpful, knowledgeable, direct, targeted, and efficient. Admit uncertainty when appropriate and prioritize genuine usefulness.'

function Get-RenderedInstructionContent {
    param(
        [Parameter(Mandatory)][string]$HostId,
        [Parameter(Mandatory)][string]$Header
    )
    if ($HostId -eq 'hermes') {
        return "$Header`n`n$HermesPersonaPreamble`n`n$PolicyBody`n$Marker`n"
    }
    return "$Header`n`n$Marker`n`n$PolicyBody"
}

# ---------------------------------------------------------------------------
# Registry load
# ---------------------------------------------------------------------------
$agentsReg = Get-Content -LiteralPath $AgentsFile -Raw -Encoding UTF8 | ConvertFrom-Json

# registry/agents.json stores ABSOLUTE destination paths baked to the real
# invoking user's profile at the time the registry was captured (e.g.
# "C:\\Users\\SaroshHussain\\.claude\\CLAUDE.md"), recorded verbatim in
# agentsReg.userProfile. They are NOT relative to %USERPROFILE% and are NOT
# self-rebasing. Every destination path/dir must have that recorded prefix
# swapped for the effective -UserProfile before it is read, compared, or
# written -- otherwise -Apply against a synthetic test profile would still
# write the real, live user profile regardless of -UserProfile. (This was
# caught during this task's own testing: see task-2-report.md.)
$registryUserProfile = if ($agentsReg.PSObject.Properties['userProfile'] -and
    -not [string]::IsNullOrWhiteSpace([string]$agentsReg.userProfile)) {
    [System.IO.Path]::GetFullPath([string]$agentsReg.userProfile).TrimEnd('\')
} else {
    $null
}

function ConvertTo-EffectiveUserPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if (-not $registryUserProfile) { return $Path }
    if ($Path.Equals($registryUserProfile, [StringComparison]::OrdinalIgnoreCase)) {
        return $UserProfile
    }
    $prefixWithSeparator = $registryUserProfile + '\'
    if ($Path.StartsWith($prefixWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        return $UserProfile + $Path.Substring($registryUserProfile.Length)
    }
    # A registry path that does not fall under the recorded userProfile at
    # all (should not happen for any host with a real destination) is left
    # untouched rather than guessed at.
    return $Path
}

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

    return [pscustomobject]@{
        HostId            = $hostId
        Kind              = 'destination'
        DestinationPath   = $destinationPath
        DestinationDir    = $destinationDir
        FileName          = $fileName
        Header            = $header
        HeaderSource      = $headerSource
        IsDirectoryTarget = [bool]$isDirectoryTarget
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
    $expectedContent = Get-RenderedInstructionContent -HostId $target.HostId -Header $target.Header

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
