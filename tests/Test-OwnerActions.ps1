#Requires -Version 5.1
<#
Behavior tests for native-connectors.json's ownerActionRequired block.

The block records actions the owner authorized that AgentHub cannot perform --
disconnecting a claude.ai account connector, revoking an OAuth grant at the
provider. Recorded, they survive the session that found them and carry the
evidence for why the limit is real. Left in a chat transcript, they are
indistinguishable from work that was quietly skipped.

Which is the danger this file exists to guard. A list of "things I could not
do" is the most comfortable place in a repository to put something that was
merely not done, and nothing about the entry looks different. So the
load-bearing rule here is Behavior 3: an entry claiming AgentHub COULD perform
the action, still open, is a build failure. The cheapest way out of this file
is to do the work.

That rule is written from a specific mistake. Earlier in this work an action
was reported as the owner's to take, having never been attempted; testing found
it was perfectly reachable. An unevidenced "cannot" is the same defect as an
unevidenced `false` in the capability matrix, and it gets the same treatment
here: a claim needs evidence, and a date.

Run: pwsh -NoProfile -File tests/Test-OwnerActions.ps1
     powershell.exe -NoProfile -File tests/Test-OwnerActions.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

# -Encoding UTF8 is required by tests/Test-FileEncodingDiscipline.ps1 and is not
# decoration: 5.1 decodes a BOM-less file as the ANSI code page, so without it
# the two shells read different bytes the moment a non-ASCII character lands in
# this registry -- and these entries quote owner instructions verbatim, which is
# exactly where a curly quote arrives first.
$connectors = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-Actions { @($connectors.ownerActionRequired.actions) }

$IsoDate = '^\d{4}-\d{2}-\d{2}$'

# --- Behavior 1: the block exists and records something.
#
# Every check below iterates the action list. An absent or empty list makes all
# of them pass over nothing while still printing PASS -- the shape this
# repository keeps producing. If the day comes that every action is genuinely
# complete, the entries stay (completionPolicy says so) and this still passes;
# an empty list means the block was deleted, not satisfied. ---
function Test-BlockRecordsActions {
    if (-not $connectors.ownerActionRequired) {
        return @{ Passed = $false; Detail = 'native-connectors.json declares no ownerActionRequired block. Every behavior below iterates its actions, so its absence would make this whole file pass over nothing.' }
    }
    $actions = Get-Actions
    if ($actions.Count -eq 0) {
        return @{ Passed = $false; Detail = 'ownerActionRequired.actions is empty. Completed entries are kept with completedOn set rather than removed, so an empty list means the record was deleted rather than satisfied.' }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: every entry is identifiable and states what and where.
#
# An entry the owner cannot act on is worse than no entry: it reads as a
# handoff and delivers nothing. ids must also be unique, or a later entry
# silently shadows an earlier one in any tooling that keys on id. ---
function Test-EveryActionIsActionable {
    $bad = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new()
    foreach ($action in Get-Actions) {
        $id = [string]$action.id
        if ([string]::IsNullOrWhiteSpace($id)) { $bad.Add('an entry has no id'); continue }
        if (-not $seen.Add($id)) { $bad.Add("duplicate id '$id'; a later entry with the same id shadows the earlier one") }
        foreach ($field in @('action', 'surface', 'ownerStep')) {
            if ([string]::IsNullOrWhiteSpace([string]$action.$field)) {
                $bad.Add("$id has no $field, so a reader cannot tell what to do or where to do it")
            }
        }
        $targets = @($action.targets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($targets.Count -eq 0) {
            $bad.Add("$id names no targets; an action with nothing to act on is a note, not an action")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3 (the load-bearing one): this block is not a parking lot.
#
# agentHubCanPerform: true means the work is AgentHub's. If it is also still
# open, it was not blocked -- it was skipped, and writing it here dressed it as
# a limitation. That is a build failure, deliberately, so that recording is
# never cheaper than doing.
#
# The field must also be a real boolean. Omitted, or the string "false", it
# would be neither true nor caught, and the entry would slip past this check
# reading exactly like a blocked one. ---
function Test-BlockIsNotAParkingLot {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($action in Get-Actions) {
        $id = [string]$action.id
        $canPerform = $action.agentHubCanPerform
        if ($canPerform -isnot [bool]) {
            $bad.Add("$id records agentHubCanPerform as something other than true or false, so neither this check nor the evidence rule can read it")
            continue
        }
        $open = [string]::IsNullOrWhiteSpace([string]$action.completedOn)
        if ($canPerform -and $open) {
            $bad.Add("$id says AgentHub CAN perform it and it is still open. Then it is not blocked, it is undone -- do it, or establish and record what actually blocks it. This list is for what AgentHub cannot do, never for what it did not do")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: a "cannot" carries dated evidence.
#
# Same rule the capability matrix applies to `false`, for the same reason: the
# cheapest entry to write is a claim nobody checked, and it reads identically to
# one that was. A capability limit asserted without testing was wrong once in
# this work already, so the claim costs a sentence and a date.
#
# The date matters on its own -- a blocker verified a year ago and one verified
# today make the same assertion and are not equally trustworthy. ---
function Test-CannotClaimsCarryDatedEvidence {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($action in Get-Actions) {
        $id = [string]$action.id
        if ($action.agentHubCanPerform -isnot [bool] -or $action.agentHubCanPerform) { continue }
        foreach ($field in @('blockedBy', 'blockerVerification')) {
            if ([string]::IsNullOrWhiteSpace([string]$action.$field)) {
                $bad.Add("$id claims AgentHub cannot perform it but records no $field; an unevidenced 'cannot' is indistinguishable from an untried one")
            }
        }
        $verifiedOn = [string]$action.blockerVerifiedOn
        if ($verifiedOn -notmatch $IsoDate) {
            $bad.Add("$id has no ISO blockerVerifiedOn date (found '$verifiedOn'); an undated blocker cannot be audited for staleness")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: an authorized action quotes its authorization, and an
# unauthorized one claims none.
#
# authorizedOn and authorization travel together in both directions. A date
# without the instruction is an assertion that the owner asked for something,
# with no way to check what; an instruction without a date cannot be aged. And
# an entry carrying neither must not imply consent -- account-level-plugin-servers
# is recorded for visibility, not because anyone asked for it, and null in both
# fields is how it says so. ---
function Test-AuthorizationIsPairedOrAbsent {
    $bad = [Collections.Generic.List[string]]::new()
    $quoted = 0
    foreach ($action in Get-Actions) {
        $id = [string]$action.id
        $hasDate = -not [string]::IsNullOrWhiteSpace([string]$action.authorizedOn)
        $hasText = -not [string]::IsNullOrWhiteSpace([string]$action.authorization)
        if ($hasDate -ne $hasText) {
            $bad.Add("$id records authorizedOn=$hasDate and authorization=$hasText. Both or neither: a date alone asserts the owner asked for something with no way to check what, and text alone cannot be aged")
        }
        if ($hasDate) {
            $quoted++
            if ([string]$action.authorizedOn -notmatch $IsoDate) {
                $bad.Add("$id has a non-ISO authorizedOn ('$($action.authorizedOn)')")
            }
        }
    }
    if ($quoted -eq 0) {
        return @{ Passed = $false; Detail = 'no entry records an authorization at all, so the paired-fields rule above iterated nothing and would pass against any mismatch. At least one entry here exists because the owner asked for it.' }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: a completed action says when, in a format that can be aged.
#
# Nothing here forces an entry to complete -- these are the owner's to do, on
# the owner's schedule. What is forced is that "done" is a date rather than a
# truthy string, so a later reader can tell a completion from a placeholder like
# "yes" or "soon". ---
function Test-CompletionsAreDated {
    $bad = [Collections.Generic.List[string]]::new()
    foreach ($action in Get-Actions) {
        $completedOn = $action.completedOn
        if ($null -eq $completedOn) { continue }
        if ([string]$completedOn -notmatch $IsoDate) {
            $bad.Add("$($action.id) records completedOn = '$completedOn', which is not an ISO date. Open entries use null; anything else is a placeholder wearing a completion's clothes")
        }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-BlockRecordsActions
Report 'the ownerActionRequired block exists and records at least one action' $r1.Passed $r1.Detail

$r2 = Test-EveryActionIsActionable
Report 'every action has a unique id and states what, where, and the owner step' $r2.Passed $r2.Detail

$r3 = Test-BlockIsNotAParkingLot
Report 'no open action claims AgentHub could have performed it' $r3.Passed $r3.Detail

$r4 = Test-CannotClaimsCarryDatedEvidence
Report 'every cannot-perform claim carries dated evidence' $r4.Passed $r4.Detail

$r5 = Test-AuthorizationIsPairedOrAbsent
Report 'authorization date and quoted instruction are present together or not at all' $r5.Passed $r5.Detail

$r6 = Test-CompletionsAreDated
Report 'a completed action records an ISO date, not a truthy placeholder' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
