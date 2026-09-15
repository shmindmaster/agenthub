#Requires -Version 5.1
<#
.SYNOPSIS
    Single lifecycle entry point for AgentHub: inventory, validate, sync, drift.

.DESCRIPTION
    Replaces the deleted scripts/agentctl.ps1 (git show
    fc1bda6f6fb8a1476603c263c03107f70024738f:scripts/agentctl.ps1; see
    .superpowers/sdd/control-plane-restore-plan/research/agentctl-spec.md
    for its full seven-subcommand shape and why several of those subcommands
    were broken). This entry point implements four subcommands, not seven.
    Three are dropped deliberately -- if you are looking for one of these,
    it is not a gap in this port:

      evaluate  - scored hosts against registry/installations.json, which no
                  longer exists and which AGENTS.md:20 forbids recreating.
                  Its content was a one-time, hand-written decision record,
                  not a reusable capability.
      generate  - staged rendered host-instruction files into generated/, a
                  directory AGENTS.md:20 forbids recreating. The surviving
                  Sync-Instructions.ps1 / Sync-Subagents.ps1 now render and
                  stage directly under %LOCALAPPDATA%\AgentHub\runtime\...
                  and write straight to each host's real destination -- there
                  is no separate "generate" step left to expose as its own
                  subcommand.
      cleanup   - agentctl.ps1's cleanup never quarantined, moved, or deleted
                  anything, even when called with -Apply (see
                  research/agentctl-spec.md S4) -- it only ever detected and
                  reported candidates. A real, authorized apply mechanism for
                  cleanup does not exist yet; until the owner separately
                  designs and approves one, cleanup stays unimplemented here
                  rather than resurrected as another report-only command that
                  looks like it does something it does not.

    This script is a pure orchestrator: it never reimplements validate/sync
    logic. Every subcommand shells out to the real scripts under scripts/ as
    a child process of THIS process's own host executable, so `pwsh
    scripts/AgentHub.ps1` runs every delegated script under pwsh and
    `powershell.exe scripts/AgentHub.ps1` runs every delegated script under
    powershell.exe. If a delegated script cannot do something, that is
    reported as a delegated failure -- it is never patched over with inline
    replacement logic here.

.PARAMETER Command
    One of: init, inventory, validate, sync, drift.

.PARAMETER Apply
    Only meaningful for 'sync'. Without it, 'sync' audits (the default,
    identical in effect to 'drift'). With it, 'sync' deploys -- but only
    after 'validate' passes first; if validate fails, -Apply is refused
    outright and zero delegated sync scripts are run. Deploying from a
    registry validate itself rejects is exactly how bad state has reached
    the live fleet before.

.PARAMETER RepositoryRoot
    Repository root. Self-derived from this script's own on-disk location
    (same idiom as Validate-AgentHub.ps1 / Sync-AgentHub.ps1) unless passed
    explicitly. Also where this script looks for the delegated scripts
    themselves (scripts/Validate-AgentHub.ps1, scripts/Sync-*.ps1).

.PARAMETER UserProfile
    User-profile root, passed through unchanged to every delegated script
    that accepts one (-UserProfile). Defaults to $env:USERPROFILE. Override
    with a synthetic profile under $env:AGENTHUB_TEST_SCRATCH for any run
    that must not touch the real, live user profile -- this script performs
    live applies when given -Apply and a real profile.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,
    [switch]$Apply,
    [string]$RepositoryRoot,
    [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'

$ValidCommands = @('init', 'inventory', 'validate', 'sync', 'drift')

# Self-derive from this script's own on-disk location -- same idiom as
# Validate-AgentHub.ps1 / Sync-AgentHub.ps1 / Sync-Instructions.ps1. Never
# hardcode a checkout path; running from a worktree (the normal development
# path per repository policy) must resolve to that worktree, not whatever
# tree a hardcoded default happened to point at.
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')

. (Join-Path $PSScriptRoot 'lib\PathBinding.ps1')
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    $UserProfile = Get-AgentHubDefaultHome
}
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
    throw "Could not resolve a user profile directory. Pass -UserProfile explicitly."
}
$UserProfile = Get-AgentHubNormalizedDirectory $UserProfile

$ScriptsDir = Join-Path $RepositoryRoot 'scripts'
# Modules belong to this script, not to the tree being synced. A stub
# -RepositoryRoot used by tests has no scripts/lib, and loading it from
# there would make orchestration depend on the target checkout.
. (Join-Path $PSScriptRoot 'lib\SyncOrchestrator.ps1')
. (Join-Path $PSScriptRoot 'lib\HostCatalog.ps1')
$hostExe = (Get-Process -Id $PID).Path

if ([string]::IsNullOrWhiteSpace($Command) -or $Command -notin $ValidCommands) {
    Write-Host "FAIL: unknown subcommand '$Command'. Valid subcommands: $($ValidCommands -join ', ')." -ForegroundColor Red
    Write-Host "Dropped deliberately, not a gap: evaluate, generate, cleanup -- see this script's own help (Get-Help $($MyInvocation.MyCommand.Path) -Full) for why."
    Write-Host "First run: pwsh -NoProfile -File .\scripts\AgentHub.ps1 init"
    exit 1
}

function Invoke-Init {
    # Scaffold local-only files from examples. Never overwrite an existing
    # overlay or profile, and never write host configuration.
    $created = [Collections.Generic.List[string]]::new()
    $skipped = [Collections.Generic.List[string]]::new()

    $exampleOverlay = Join-Path $RepositoryRoot 'overlays\personal.example'
    $personalOverlay = Join-Path $RepositoryRoot 'overlays\personal'
    if (-not (Test-Path -LiteralPath $exampleOverlay)) {
        throw "Missing example overlay at $exampleOverlay"
    }
    if (Test-Path -LiteralPath $personalOverlay) {
        $skipped.Add('overlays/personal (already present)')
    } else {
        $parent = Split-Path -Parent $personalOverlay
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $exampleOverlay -Destination $personalOverlay -Recurse -Force
        $created.Add('overlays/personal')
    }

    $exampleProfile = Join-Path $RepositoryRoot 'agenthub.profile.example.json'
    $profilePath = Join-Path $RepositoryRoot 'agenthub.profile.json'
    if (-not (Test-Path -LiteralPath $exampleProfile)) {
        throw "Missing $exampleProfile"
    }
    if (Test-Path -LiteralPath $profilePath) {
        $skipped.Add('agenthub.profile.json (already present)')
    } else {
        Copy-Item -LiteralPath $exampleProfile -Destination $profilePath -Force
        $created.Add('agenthub.profile.json')
    }

    Write-Host "AgentHub init -- RepositoryRoot=$RepositoryRoot"
    if ($created.Count -gt 0) {
        Write-Host ("Created: {0}" -f ($created -join ', '))
    }
    if ($skipped.Count -gt 0) {
        Write-Host ("Left unchanged: {0}" -f ($skipped -join ', '))
    }
    Write-Host ''
    Write-Host 'Next:'
    Write-Host '  pwsh -NoProfile -File .\scripts\AgentHub.ps1 validate'
    Write-Host '  pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync'
    Write-Host '  # then: pwsh -NoProfile -File .\scripts\AgentHub.ps1 sync -Apply'
    Write-Host 'Docs: docs/development/quickstart.md'
    return 0
}

# ---------------------------------------------------------------------------
# Delegation helpers
# ---------------------------------------------------------------------------

# Runs a delegated script as a genuine child process of this process's own
# host executable, so an `exit N` inside the delegated script never
# terminates this orchestrator (calling a script that exits via `&` in the
# same PowerShell session would do exactly that). A missing script is
# reported, never silently skipped or replaced with inline logic.
function Invoke-DelegatedScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$ScriptArgs = @()
    )
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return @{ Name = $Name; Ran = $false; ExitCode = $null; Output = "delegated script not found: $ScriptPath" }
    }
    $allArgs = @('-NoProfile', '-File', $ScriptPath) + $ScriptArgs
    # Windows PowerShell 5.1 wraps a native child process's stderr lines as
    # ErrorRecords; under $ErrorActionPreference = 'Stop' those become
    # terminating even though the child process itself did not fail. Relax
    # locally so a failing delegated script's stderr is captured as output,
    # not thrown out of this orchestrator.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ Name = $Name; Ran = $true; ExitCode = $LASTEXITCODE; Output = $output }
}

function Invoke-ValidateAgentHub {
    $scriptPath = Join-Path $ScriptsDir 'Validate-AgentHub.ps1'
    return Invoke-DelegatedScript -ScriptPath $scriptPath -Name 'Validate-AgentHub.ps1' `
        -ScriptArgs @('-RepositoryRoot', $RepositoryRoot)
}

# The four scripts named in the brief as the real 'sync' engine
# (RegistryContentHash.ps1 is a dot-sourced helper, not a command;
# New-AgentHubWorktree.ps1 is a worktree helper, not a lifecycle command --
# neither belongs here). Sync-AgentHub.ps1 alone uses -RegistryRoot instead
# of -RepositoryRoot; every other parameter name is shared.
function Get-SyncStepDefinitions {
    param([switch]$ApplyMode)
    return Get-AgentHubSyncStepDefinitions -RepositoryRoot $RepositoryRoot -UserProfile $UserProfile -ApplyMode:$ApplyMode
}

# Aggregates all four Sync-* scripts honestly: success requires every known
# step to have actually run AND every one of them to have exited 0. A loop
# that iterates over zero available scripts (wrong -RepositoryRoot, a
# checkout missing a script) must never fall through to a success message
# merely because the loop finished without an error -- that is precisely the
# empty-work-set-reports-success defect class this whole effort exists to
# eliminate.
function Invoke-SyncAggregate {
    param([switch]$ApplyMode)

    $stepDefs = Get-SyncStepDefinitions -ApplyMode:$ApplyMode
    $results = [Collections.Generic.List[object]]::new()
    $executed = 0
    $failed = 0

    foreach ($step in $stepDefs) {
        $scriptPath = Join-Path $ScriptsDir $step.Relative
        $result = Invoke-DelegatedScript -ScriptPath $scriptPath -Name $step.Name -ScriptArgs $step.Args
        $results.Add($result)
        if (-not $result.Ran) {
            $failed++
            continue
        }
        $executed++
        if ($result.ExitCode -ne 0) { $failed++ }
        Write-Host $result.Output.TrimEnd()
    }

    foreach ($result in $results) {
        $marker = if (-not $result.Ran) { 'MISSING' } elseif ($result.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0}: {1}" -f $marker, $result.Name)
    }

    if ($executed -eq 0) {
        Write-Host "FAIL: zero delegated sync steps executed out of $($stepDefs.Count) known scripts under $ScriptsDir. Refusing to report success against an empty work set." -ForegroundColor Red
        return 1
    }
    if ($failed -gt 0) {
        Write-Host "FAIL: $failed of $($stepDefs.Count) delegated sync step(s) did not succeed." -ForegroundColor Red
        return 1
    }
    Write-Host "PASS: $executed of $($stepDefs.Count) delegated sync steps succeeded." -ForegroundColor Green
    return 0
}

# ---------------------------------------------------------------------------
# inventory -- read-only, derived from registry/agents.json, never writes.
# ---------------------------------------------------------------------------
function Invoke-Inventory {
    $agentsFile = Join-Path $RepositoryRoot 'registry\agents.json'
    if (-not (Test-Path -LiteralPath $agentsFile)) {
        throw "Missing registry file: $agentsFile"
    }
    $agentsReg = Get-Content -LiteralPath $agentsFile -Raw -Encoding UTF8 | ConvertFrom-Json

    # Destinations are templates or recorded absolutes. PathBinding is the
    # only materializer, so inventory against a synthetic -UserProfile reports
    # synthetic paths and never the live profile.
    $binding = New-AgentHubPathBindingContext -TargetUserProfile $UserProfile -RegistryUserProfile (Get-AgentHubRecordedUserProfile $agentsReg) -Platform (Get-AgentHubRequestedPlatform -RepositoryRoot $RepositoryRoot)
    Import-AgentHubBoundHostCatalog -AgentsDocument $agentsReg -Context $binding | Out-Null

    $allHosts = [Collections.Generic.List[object]]::new()
    if ($agentsReg.PSObject.Properties['activeAgents'] -and $agentsReg.activeAgents) {
        foreach ($a in @($agentsReg.activeAgents)) { $allHosts.Add([pscustomobject]@{ Agent = $a; Status = 'active' }) }
    }
    if ($agentsReg.PSObject.Properties['inactiveAgents'] -and $agentsReg.inactiveAgents) {
        foreach ($a in @($agentsReg.inactiveAgents)) { $allHosts.Add([pscustomobject]@{ Agent = $a; Status = 'inactive' }) }
    }
    if ($allHosts.Count -eq 0) {
        throw "Registry root '$RepositoryRoot' resolved to zero hosts in $agentsFile. Refusing to report success against what looks like an empty or wrong registry tree; pass -RepositoryRoot explicitly if this is intentional."
    }

    $rows = [Collections.Generic.List[object]]::new()
    foreach ($entry in $allHosts) {
        $agent = $entry.Agent
        $hostId = [string]$agent.id
        $paths = $agent.nativePaths
        $pathFieldFound = $false
        if ($paths) {
            foreach ($prop in $paths.PSObject.Properties) {
                $value = [string]$prop.Value
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                # Only real filesystem paths (absolute drive-letter or UNC)
                # are probed. nativePaths also carries prose/format metadata
                # (instructionHeader, instructionFormat,
                # instructionsDestinationKind, instructionBodyTemplate) that
                # is never a path this can Test-Path -- classify by shape,
                # not by a hardcoded field-name list that would silently
                # miss a future field.
                $isPosixAbsolute = $value.StartsWith('/') -and -not $value.StartsWith('//')
                if ($value -notmatch '^[A-Za-z]:\\' -and $value -notmatch '^\\\\' -and -not $isPosixAbsolute) { continue }
                $pathFieldFound = $true
                $effective = $value
                $rows.Add([pscustomobject]@{
                    HostId = $hostId; Status = $entry.Status; Field = $prop.Name
                    Declared = $value; EffectivePath = $effective; Present = (Test-Path -LiteralPath $effective)
                })
            }
        }
        if (-not $pathFieldFound) {
            $rows.Add([pscustomobject]@{
                HostId = $hostId; Status = $entry.Status; Field = '(no path fields declared)'
                Declared = $null; EffectivePath = $null; Present = $false
            })
        }
    }

    Write-Host "Inventory -- RepositoryRoot=$RepositoryRoot UserProfile=$UserProfile"
    Write-Host ("{0,-20} {1,-10} {2,-28} {3,-8} {4}" -f 'HOSTID', 'STATUS', 'FIELD', 'PRESENT', 'PATH')
    foreach ($row in $rows) {
        Write-Host ("{0,-20} {1,-10} {2,-28} {3,-8} {4}" -f $row.HostId, $row.Status, $row.Field, $row.Present, $row.EffectivePath)
    }
    $presentCount = @($rows | Where-Object Present).Count
    Write-Host ("SUMMARY: {0} hosts, {1} path fields checked, {2} present, {3} missing." -f $allHosts.Count, $rows.Count, $presentCount, ($rows.Count - $presentCount))
    return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
switch ($Command) {
    'init' {
        if ($Apply) {
            throw "'init' does not accept -Apply. It only scaffolds local overlay/profile files."
        }
        exit (Invoke-Init)
    }
    'validate' {
        $result = Invoke-ValidateAgentHub
        Write-Host $result.Output.TrimEnd()
        if (-not $result.Ran) {
            Write-Host "FAIL: $($result.Output)" -ForegroundColor Red
            exit 1
        }
        exit $result.ExitCode
    }
    'inventory' {
        exit (Invoke-Inventory)
    }
    'drift' {
        # drift is always read-only; -Apply belongs to 'sync' only. Requiring
        # this explicitly (rather than silently ignoring -Apply) keeps the
        # promise in this script's own help text honest.
        if ($Apply) {
            throw "'drift' is always read-only and does not accept -Apply. Use 'sync -Apply' to deploy."
        }
        exit (Invoke-SyncAggregate)
    }
    'sync' {
        if ($Apply) {
            # Requirement: -Apply must refuse to run if validate would fail.
            # Deploying from a registry validate itself rejects is exactly
            # how bad state has reached the live fleet before.
            $validateResult = Invoke-ValidateAgentHub
            Write-Host $validateResult.Output.TrimEnd()
            if (-not $validateResult.Ran -or $validateResult.ExitCode -ne 0) {
                Write-Host "REFUSED: 'sync -Apply' requires 'validate' to pass first; it did not (exit=$($validateResult.ExitCode)). No delegated sync script was run." -ForegroundColor Red
                exit 1
            }
            exit (Invoke-SyncAggregate -ApplyMode)
        }
        exit (Invoke-SyncAggregate)
    }
}
