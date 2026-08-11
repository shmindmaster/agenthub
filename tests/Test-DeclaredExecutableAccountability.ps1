#Requires -Version 5.1
<#
Behavior tests for registry/agents.json `executable`: an active host whose
declared binary is not on this machine must say why.

tests/Test-DeclaredPathAccountability.ps1 already applies this contract to
`nativePaths`, and deliberately stops there -- it iterates the properties of
nativePaths and never looks at the sibling `executable`. So the ONE path that
decides whether a host can run at all was the one path nothing checked.

Measured 2026-08-11, the first time anybody looked: 7 of 22 active hosts
declared an absolute executable that does not exist. Three were simply wrong
while the product was installed elsewhere (cline under a different bin root,
amp recorded at a WinGet shim path for an install that never used WinGet,
factory pinned to app-0.144.0 when only app-0.150.0 remained). Four were
uninstalled products still declared active. None of it was visible, because
`Validate-AgentHub.ps1` counts active agents without resolving anything and
every other suite was green.

Two things this file must get right, both learned from the data:

  - BARE NAMES ARE NOT PATHS. qwen-code declares `qwen`, which is correct and
    resolves through PATH to ~/bin/qwen.cmd. A Test-Path-only check reports it
    missing, and a false positive on a correct declaration is how a gate gets
    ignored. Behavior 1 pins that case down explicitly.
  - RESOLVING ON PATH IS NOT BEING INSTALLED. qoder is uninstalled, yet an
    orphaned vendor wrapper at ~/bin/qodercli.cmd is still on PATH and points
    at the (absent) declared exe, failing only when invoked. So PATH resolution
    is used ONLY to resolve a bare name to a file, never as proof a product is
    present.

Absence is judged on this machine and means nothing fleet-wide -- codex,
hermes and qoder are all in fleet-profile.json managedHosts and may exist on
another host. That is exactly why the remedy is a NOTE rather than deletion:
the same reasoning Test-DeclaredPathAccountability records in
gemini.agentsDirNote, where a declared path was changed on the mistaken basis
that a directory absent from disk must be wrong.

Accounting may take either form, and both are accepted on purpose:
  - `executableNote`, the <field>Note convention the path suite established;
  - `installationExpectation`, a structured enum windsurf already carries with
    a full explanation in its `notes`. It answers the question in a more
    checkable form than prose, and a gate that rejected the stronger
    declaration to demand the weaker one would be backwards -- it would force
    windsurf's 200-word explanation to be duplicated into a second field, and
    two copies of an explanation drift.

Scope is activeAgents. inactiveAgents is excluded because moving an uninstalled
host there IS an honest answer to this finding, and a gate that followed it
there would punish the fix. It is currently empty.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom -- one PASS/FAIL line per behavior, exit 1 if any
behavior did not hold.

Run: pwsh -NoProfile -File tests/Test-DeclaredExecutableAccountability.ps1
     powershell.exe -NoProfile -File tests/Test-DeclaredExecutableAccountability.ps1
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

$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# The vocabulary for installationExpectation. Closed and checked, for the same
# reason the step-role vocabulary in Test-CapabilityRouting.ps1 is: an
# unrecognised value must be REPORTED BY NAME, not silently accepted as
# accounting. A typo'd expectation that still satisfied the gate would be an
# escape hatch opened by misspelling.
$knownInstallationExpectations = @(
    'in-use-executable-not-located'
)

# A declaration is one of four things, and the difference matters to the
# message a maintainer reads:
#   Present   - resolves to a file on this machine.
#   Absent    - names a path or command that does not resolve.
#   Undeclared- null, empty, or the property missing entirely.
# Bare names resolve through PATH (Application/ExternalScript only -- a
# declaration that resolved to a PowerShell function or alias would not be an
# executable), absolute paths resolve through the filesystem.
function Resolve-DeclaredExecutable {
    param($Value)
    if ($null -eq $Value) { return 'Undeclared' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Undeclared' }
    if ($text -match '[\\/]') {
        if (Test-Path -LiteralPath $text -PathType Leaf) { return 'Present' }
        return 'Absent'
    }
    $command = Get-Command -Name $text -CommandType Application, ExternalScript -ErrorAction SilentlyContinue
    if ($command) { return 'Present' }
    return 'Absent'
}

function Get-ExecutableDeclarations {
    $declarations = [Collections.Generic.List[object]]::new()
    foreach ($agent in @($agents.activeAgents)) {
        $property = $agent.PSObject.Properties['executable']
        $value = if ($property) { $property.Value } else { $null }
        $noteProperty = $agent.PSObject.Properties['executableNote']
        $expectationProperty = $agent.PSObject.Properties['installationExpectation']
        $declarations.Add([pscustomobject]@{
            HostId      = [string]$agent.id
            Declared    = ($null -ne $property)
            Value       = $value
            State       = (Resolve-DeclaredExecutable -Value $value)
            Note        = if ($noteProperty) { [string]$noteProperty.Value } else { $null }
            Expectation = if ($expectationProperty) { [string]$expectationProperty.Value } else { $null }
        })
    }
    return $declarations
}

function Test-HasAccounting {
    param($Declaration)
    if (-not [string]::IsNullOrWhiteSpace($Declaration.Note)) { return $true }
    if ($Declaration.Expectation -in $knownInstallationExpectations) { return $true }
    return $false
}

# --- Behavior 1 (anti-vacuity): the resolver tells the four states apart, and
# there are real hosts to run it over.
#
# Every behavior below is a filter over Resolve-DeclaredExecutable's output, so
# a resolver that answered 'Present' to everything would make all of them pass
# while checking nothing. The bare-name case is pinned with a command this
# repository's own toolchain guarantees (pwsh, which is running this file), and
# the absent-bare-name case with a name no PATH can plausibly hold. ---
function Test-ResolverDistinguishesTheFourStates {
    $checks = [ordered]@{
        'an absolute path that exists'      = @{ Value = (Join-Path $repoRoot 'registry\agents.json'); Expected = 'Present' }
        'an absolute path that does not'    = @{ Value = (Join-Path $repoRoot 'registry\no-such-file-here.json'); Expected = 'Absent' }
        'a bare name on PATH'               = @{ Value = 'pwsh'; Expected = 'Present' }
        'a bare name not on PATH'           = @{ Value = 'agenthub-no-such-command-b7f2'; Expected = 'Absent' }
        'a null declaration'                = @{ Value = $null; Expected = 'Undeclared' }
        'an empty-string declaration'       = @{ Value = '   '; Expected = 'Undeclared' }
    }
    $wrong = [Collections.Generic.List[string]]::new()
    foreach ($check in $checks.GetEnumerator()) {
        $actual = Resolve-DeclaredExecutable -Value $check.Value.Value
        if ($actual -ne $check.Value.Expected) {
            $wrong.Add("$($check.Key) resolved '$actual', expected '$($check.Value.Expected)'")
        }
    }
    if ($wrong.Count -gt 0) {
        return @{ Passed = $false; Detail = "the executable resolver misclassified its control cases, so no result below can be trusted: $($wrong -join '; '). The bare-name cases matter most: qwen-code correctly declares the bare name 'qwen', and a resolver that cannot follow PATH reports that correct declaration as missing." }
    }
    $declarations = Get-ExecutableDeclarations
    if ($declarations.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/agents.json lists no activeAgents, so every behavior below would pass over an empty set.' }
    }
    $undeclaredProperty = @($declarations | Where-Object { -not $_.Declared } | ForEach-Object { $_.HostId })
    if ($undeclaredProperty.Count -eq $declarations.Count) {
        return @{ Passed = $false; Detail = "not one of the $($declarations.Count) active host(s) carries an 'executable' property at all, so this suite is asserting nothing about a field that no longer exists in the schema." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: an active host whose declared executable does not resolve on
# this machine must say whether the path is wrong or the product is absent.
#
# Those are different tasks for whoever picks this up -- one is a one-line
# correction, the other is an install or a bucket change -- and an unannotated
# absence is indistinguishable from nobody having looked. Same reasoning, and
# the same remedy, as Test-DeclaredPathAccountability behavior 1. ---
function Test-EveryAbsentExecutableIsAccountedFor {
    $declarations = Get-ExecutableDeclarations
    $absent = @($declarations | Where-Object { $_.State -eq 'Absent' })
    $unaccounted = @($absent | Where-Object { -not (Test-HasAccounting -Declaration $_) })
    if ($unaccounted.Count -gt 0) {
        $rendered = @($unaccounted | ForEach-Object { "$($_.HostId) ($($_.Value))" })
        return @{ Passed = $false; Detail = "$($unaccounted.Count) active host(s) declare an executable that does not resolve on this machine, with no 'executableNote' saying whether the path is wrong or the product is simply not installed here: $($rendered -join '; '). Check the real location first -- resolve bare names through PATH, and remember that a vendor wrapper surviving on PATH does NOT mean the product is installed (qoder). 'Not installed on this workstation' is a valid note; absence of a note is not, because it cannot be told apart from nobody having checked." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: a host that declares no executable at all must say why.
#
# null is a claim, not a blank. windsurf declares null and is the reason this
# behavior accepts installationExpectation: the owner states it is in use while
# no binary was ever located, which is a real and stable situation that
# deserves a name rather than a guessed path. The danger is the opposite case --
# a host added with the field left null because nobody got to it, which looks
# identical in the JSON. ---
function Test-EveryUndeclaredExecutableIsAccountedFor {
    $declarations = Get-ExecutableDeclarations
    $undeclared = @($declarations | Where-Object { $_.State -eq 'Undeclared' })
    $unaccounted = @($undeclared | Where-Object { -not (Test-HasAccounting -Declaration $_) })
    if ($unaccounted.Count -gt 0) {
        $rendered = @($unaccounted | ForEach-Object { $_.HostId })
        return @{ Passed = $false; Detail = "$($unaccounted.Count) active host(s) declare no executable (null, empty, or the property omitted) and explain nothing: $($rendered -join ', '). A null here must be a decision, not a gap -- record an 'installationExpectation' from [$($knownInstallationExpectations -join ', ')] with the reasoning in 'notes', or an 'executableNote'. Do not invent a plausible path to fill the hole; that is the defect hooksFileNote and workflowsDirNote were both written to record." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: an installationExpectation must be a value this suite knows.
#
# It is accepted as accounting in behaviors 2 and 3, so an unrecognised string
# would otherwise be an escape hatch reachable by typo -- and worse, a silent
# one, since a misspelling would simply fail the -in test and surface as
# "explains nothing", sending the reader to write a note they already wrote. ---
function Test-InstallationExpectationsAreKnown {
    $declarations = Get-ExecutableDeclarations
    $used = @($declarations | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Expectation) })
    $unknown = @($used | Where-Object { $_.Expectation -notin $knownInstallationExpectations })
    if ($unknown.Count -gt 0) {
        $rendered = @($unknown | ForEach-Object { "$($_.HostId) => '$($_.Expectation)'" })
        return @{ Passed = $false; Detail = "these hosts declare an installationExpectation this suite does not know: $($rendered -join '; '). The vocabulary is [$($knownInstallationExpectations -join ', ')]. Either fix the spelling or add the new value to `$knownInstallationExpectations in this file, deliberately -- it is accepted as accounting, so an unrecognised value must never pass silently." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: an explanation must be substantive enough to act on.
#
# Lifted from Test-DeclaredPathAccountability behavior 3, at the same 40-character
# threshold, because the failure it prevents is identical: 'TODO', 'n/a' and
# 'missing' all satisfy a presence check and tell the next reader nothing. ---
function Test-ExecutableNotesAreSubstantive {
    $declarations = Get-ExecutableDeclarations
    $thin = [Collections.Generic.List[string]]::new()
    foreach ($declaration in $declarations) {
        if ([string]::IsNullOrWhiteSpace($declaration.Note)) { continue }
        if ($declaration.Note.Trim().Length -lt 40) {
            $thin.Add("$($declaration.HostId).executableNote: '$($declaration.Note.Trim())'")
        }
    }
    if ($thin.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($thin.Count) executableNote(s) are too short to act on: $($thin -join '; '). Say which of the two it is -- wrong path, or product absent -- and what was actually checked." }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-ResolverDistinguishesTheFourStates
Report 'the resolver tells present, absent and undeclared apart, over real hosts' $r1.Passed $r1.Detail

$r2 = Test-EveryAbsentExecutableIsAccountedFor
Report 'every absent declared executable carries a note explaining it' $r2.Passed $r2.Detail

$r3 = Test-EveryUndeclaredExecutableIsAccountedFor
Report 'every host declaring no executable explains why' $r3.Passed $r3.Detail

$r4 = Test-InstallationExpectationsAreKnown
Report 'every installationExpectation is a value this suite knows' $r4.Passed $r4.Detail

$r5 = Test-ExecutableNotesAreSubstantive
Report 'every executable note is substantive enough to act on' $r5.Passed $r5.Detail

$declarationSummary = Get-ExecutableDeclarations
$absentCount = @($declarationSummary | Where-Object { $_.State -eq 'Absent' }).Count
$undeclaredCount = @($declarationSummary | Where-Object { $_.State -eq 'Undeclared' }).Count
Write-Host "SCOPE: $($declarationSummary.Count) active hosts, $absentCount declared executables absent on this machine, $undeclaredCount undeclared"

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
