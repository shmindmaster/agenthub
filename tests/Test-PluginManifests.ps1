#Requires -Version 5.1
<#
Validates every AgentHub plugin against the HOST'S OWN schema, not a
reimplementation of it.

Why this exists: product-experience-engineering shipped
`"agents": "./agents/"` -- a directory string where the schema requires an
array of file paths. Claude Code refused to load the entire plugin, so all four
of its subagents were unavailable. Validate-AgentHub.ps1 reported PASS and
counted it among the seven installable plugins, because a wrong type is still
valid JSON with the right name. It was found by running `claude plugin list` by
hand, which is not a control.

Validate-AgentHub now type-checks the fields we know about. This file is the
stronger guarantee: `claude plugin validate` IS the schema authority, so it
catches the fields we have not thought of yet. A hand-written checker can only
ever encode the mistakes already made.

Run: pwsh -NoProfile -File tests/Test-PluginManifests.ps1
     powershell.exe -NoProfile -File tests/Test-PluginManifests.ps1
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

function Get-PluginPackages {
    Get-ChildItem (Join-Path $repoRoot 'packages') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.claude-plugin\plugin.json') }
}

# --- Behavior 1: every plugin passes the host's own validator.
#
# If the `claude` CLI is unavailable this CANNOT pass quietly -- an absent
# checker reporting success is the failure mode this repository exists to
# eliminate. It fails and says why. ---
function Test-EveryPluginPassesHostValidator {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        return @{ Passed = $false; Detail = "the 'claude' CLI is not on PATH, so plugin manifests could not be validated against the host schema. Reporting this as a failure rather than a silent skip: an unavailable checker must never read as a passing check. Install Claude Code, or run this suite on a machine that has it." }
    }

    $packages = @(Get-PluginPackages)
    if ($packages.Count -eq 0) {
        return @{ Passed = $false; Detail = "found zero packages carrying .claude-plugin\plugin.json. Either the packages tree moved or the glob is wrong; a validator that checks nothing must not report success." }
    }

    $broken = [Collections.Generic.List[string]]::new()
    foreach ($package in $packages) {
        $output = & claude plugin validate $package.FullName 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $reason = (($output -split "`n") | Where-Object { $_ -match '>\s*\S' } | ForEach-Object { $_.Trim() }) -join '; '
            $broken.Add("$($package.Name): $reason")
        }
    }
    if ($broken.Count -gt 0) {
        return @{ Passed = $false; Detail = "plugin(s) rejected by 'claude plugin validate': $($broken -join ' | '). Claude Code refuses to load a plugin whose manifest fails this check, so every skill, agent and hook it ships becomes unavailable while the registry still counts it as installed." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: the check is not vacuous.
#
# Behavior 1 passing means little unless a genuinely broken manifest is
# rejected. Mutate a manifest into the exact shape that shipped broken and
# confirm the validator fails it. Without this, a validator that always exited 0
# would look identical from the outside.
#
# The mutation happens on a COPY of the package in a temp directory, never on
# the tracked file. `claude plugin validate` takes any directory path, so the
# copy is as good a subject as the original -- and unlike the original, a run
# killed mid-mutation leaves nothing behind but a temp directory. The earlier
# version wrote the tracked manifest and restored it in a `finally`; a hard kill
# bypasses `finally`, and the file it left broken is the one Claude Code then
# refuses to load, in the user's live checkout.
#
# The copy is validated CLEAN first. Without that control the mutated copy's
# rejection would be unattributable: a copy that fails validation for some
# unrelated reason -- a missing referenced file, a path that did not survive the
# copy -- would exit non-zero too, and this behavior would report a pass for a
# rejection the mutation did not cause.
#
# The tracked manifest's bytes are read before and after regardless, and handed
# to Behavior 3 along with the path actually written, so Behavior 3 depends on
# them explicitly rather than on being called after this function in file
# order. ---
function New-EmptyResult([string]$Detail) {
    return @{ Passed = $false; Detail = $Detail; MutatedPath = $null; TrackedManifest = $null; TrackedBytesBefore = $null; TrackedBytesAfter = $null }
}
function Test-HostValidatorRejectsABrokenManifest {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        return New-EmptyResult "the 'claude' CLI is not on PATH, so the anti-vacuity mutation could not be run."
    }

    $package = Get-PluginPackages | Where-Object { $_.Name -eq 'product-experience-engineering' } | Select-Object -First 1
    if (-not $package) {
        return New-EmptyResult 'product-experience-engineering package not found; this mutation targets its agents array specifically.'
    }
    $trackedManifest = Join-Path $package.FullName '.claude-plugin\plugin.json'
    $trackedBytesBefore = [IO.File]::ReadAllBytes($trackedManifest)

    $scratchRoot = if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) { [IO.Path]::GetTempPath() } else { $env:AGENTHUB_TEST_SCRATCH }
    $workRoot = Join-Path $scratchRoot ("agenthub-plugin-mutation-" + [guid]::NewGuid().ToString('n'))
    $copyRoot = Join-Path $workRoot $package.Name
    $copyManifest = Join-Path $copyRoot '.claude-plugin\plugin.json'
    # Write through [IO.File] with an explicit BOM-free encoding, NOT
    # Set-Content -Encoding UTF8. That parameter means UTF-8 WITHOUT a BOM in
    # pwsh 7 and WITH one in Windows PowerShell 5.1, and a BOM makes
    # `claude plugin validate` fail with "Unrecognized token ''" -- which would
    # be a rejection this mutation did not cause, in the one place a false pass
    # is invisible.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $passed = $false
    $detail = $null
    $mutatedPath = $null

    try {
        $null = New-Item -ItemType Directory -Path $workRoot -Force
        Copy-Item -LiteralPath $package.FullName -Destination $copyRoot -Recurse -Force
        if (-not (Test-Path -LiteralPath $copyManifest -PathType Leaf)) {
            $detail = "the copy of $($package.Name) under $workRoot has no .claude-plugin\plugin.json, so there was nothing to mutate."
        } else {
            $null = & claude plugin validate $copyRoot 2>&1
            if ($LASTEXITCODE -ne 0) {
                $detail = "the UNMUTATED copy of $($package.Name) at $copyRoot was already rejected by 'claude plugin validate' (exit $LASTEXITCODE). The copy is not a faithful control, so a rejection after mutating it would prove nothing about the mutation."
            } else {
                $pristine = [IO.File]::ReadAllText($copyManifest)
                # The exact defect that shipped: an array field written as a directory string.
                $mutated = $pristine -replace '(?s)"agents"\s*:\s*\[.*?\]', '"agents": "./agents/"'
                if ($mutated -eq $pristine) {
                    $detail = "could not mutate the agents array in $copyManifest -- the field shape changed, so this anti-vacuity check is no longer testing what it claims to."
                } else {
                    [IO.File]::WriteAllText($copyManifest, $mutated, $utf8NoBom)
                    $mutatedPath = $copyManifest

                    $null = & claude plugin validate $copyRoot 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $detail = "'claude plugin validate' accepted a manifest with `"agents`" as a directory string -- the exact shape Claude Code rejects at load time. Behavior 1 therefore proves nothing."
                    } else {
                        $passed = $true
                    }
                }
            }
        }
    } finally {
        # Housekeeping only. Nothing tracked depends on this running: the only
        # thing written was under $workRoot.
        if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $trackedBytesAfter = [IO.File]::ReadAllBytes($trackedManifest)
    return @{
        Passed             = $passed
        Detail             = $detail
        MutatedPath        = $mutatedPath
        TrackedManifest    = $trackedManifest
        TrackedBytesBefore = $trackedBytesBefore
        TrackedBytesAfter  = $trackedBytesAfter
    }
}

function Test-BytesEqual([byte[]]$Left, [byte[]]$Right) {
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}

function Test-HasUtf8Bom([byte[]]$Bytes) {
    return $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
}

# --- Behavior 3: this suite never writes to a tracked file.
#
# Behavior 2 used to mutate the REAL, TRACKED
# packages/product-experience-engineering/.claude-plugin/plugin.json in whichever
# checkout ran it, and rely on a `finally` to put it back. A hard-killed run --
# Ctrl+C at the wrong instant, a killed shell, a crashed host -- bypasses
# `finally` and leaves a manifest Claude Code then refuses to load, in the user's
# live repository, with no failing test to say why. A test that can damage the
# thing it validates is not a safe test at any restore fidelity, so the mutation
# now happens on a copy outside the repository and this behavior checks BOTH
# halves of that:
#
#   - the path Behavior 2 actually wrote to is outside the repository root, so
#     no `finally` is load-bearing for the tracked tree; and
#   - the tracked manifest's bytes are identical before and after Behavior 2 ran,
#     read with ReadAllBytes rather than as text, because a text read normalizes
#     away exactly the BOM difference that a stray write would introduce
#     (Set-Content -Encoding UTF8 writes a BOM in Windows PowerShell 5.1 and none
#     in pwsh 7).
#
# The byte comparison is not redundant with the path check: the path check says
# where Behavior 2 MEANT to write, and the byte check says what the tracked file
# looks like regardless. Reproduced before this landed: with Behavior 2 still
# mutating in place, the path half fails and names the tracked file. ---
function Test-SuiteNeverWritesATrackedManifest([hashtable]$MutationResult) {
    if (-not $MutationResult.MutatedPath -or -not $MutationResult.TrackedManifest -or
        $null -eq $MutationResult.TrackedBytesBefore -or $null -eq $MutationResult.TrackedBytesAfter) {
        return @{ Passed = $false; Detail = 'Behavior 2 never reached the point of mutating a manifest (see its own failure above), so there is no write location and no before/after bytes to check.' }
    }

    $mutatedPath = [IO.Path]::GetFullPath([string]$MutationResult.MutatedPath)
    $repoPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($mutatedPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return @{ Passed = $false; Detail = "Behavior 2 mutated '$mutatedPath', which is inside the repository at '$repoRoot'. A run killed between the write and the restore leaves that file broken in the user's checkout -- and if it is the plugin manifest, Claude Code refuses to load the whole plugin. Mutate a copy outside the repository instead." }
    }

    $before = $MutationResult.TrackedBytesBefore
    $after = $MutationResult.TrackedBytesAfter
    if (Test-BytesEqual $before $after) {
        return @{ Passed = $true; Detail = $null }
    }

    $beforeHasBom = Test-HasUtf8Bom $before
    $afterHasBom = Test-HasUtf8Bom $after
    if ($beforeHasBom -ne $afterHasBom) {
        if ($afterHasBom) {
            $likelyCause = 'a write added a UTF-8 BOM the tracked manifest did not have'
        } else {
            $likelyCause = 'a write dropped a UTF-8 BOM the tracked manifest had'
        }
    } else {
        $likelyCause = "byte length differs ($($before.Length) before vs $($after.Length) after), or content differs at some offset without a BOM change"
    }
    return @{ Passed = $false; Detail = "the tracked manifest $($MutationResult.TrackedManifest) changed while this suite ran -- $likelyCause. Nothing in this suite may write to it." }
}

# --- Behavior 4: a plugin's .mcp.json spells variables in CLAUDE's dialect, not
# the registry's.
#
# registry/mcps.json deliberately writes `${env:NAME}` -- the host-neutral
# spelling -- and Sync-AgentHub.ps1 translates it to Claude's `${NAME}` on the
# way into .claude.json. A plugin's own .mcp.json never passes through that
# translator: Claude Code reads it directly. So the registry spelling, copied
# into a plugin manifest, is handed to the server verbatim.
#
# Measured 2026-08-11: mobile-device-lab shipped `"ANDROID_HOME":
# "${env:ANDROID_HOME}"`, and the first real tool call failed with
#   The Android SDK root folder '${env:ANDROID_HOME}' does not exist
# on a machine where ANDROID_HOME was correctly set to C:\Android\Sdk. The
# capability was installed, enabled, and completely unusable.
#
# Nothing existing could catch it. `claude plugin validate` passes -- the value
# is a valid JSON string, and a schema cannot know a dialect. Validate-AgentHub
# type-checks fields it knows. Behavior 1 above delegates to the host validator
# for exactly the fields nobody thought of, and this is one the host validator
# does not think about either. It is the same lesson as this file's opening
# note, one layer down: `"agents": "./agents/"` was valid JSON of the wrong
# TYPE; this was a valid string in the wrong LANGUAGE.
#
# The check is deliberately narrow -- the `${env:...}` form specifically, not
# variables in general -- because `${NAME}` is correct and must stay allowed. ---
$registryDialectPattern = '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}'
function Test-PluginMcpUsesClaudeVariableDialect {
    $packages = @(Get-PluginPackages)
    if ($packages.Count -eq 0) {
        return @{ Passed = $false; Detail = "found no plugin packages under $repoRoot\packages, so this check inspected nothing." }
    }
    # Anti-vacuity: prove the pattern matches the form that actually shipped and
    # does NOT match the correct one, before a clean sweep means anything.
    $shouldMatch = '{ "ANDROID_HOME": "${env:ANDROID_HOME}" }'
    $shouldNotMatch = '{ "ANDROID_HOME": "${ANDROID_HOME}" }'
    if (-not [regex]::IsMatch($shouldMatch, $registryDialectPattern)) {
        return @{ Passed = $false; Detail = 'the dialect pattern does not match the exact form that shipped broken, so a clean result would mean nothing.' }
    }
    if ([regex]::IsMatch($shouldNotMatch, $registryDialectPattern)) {
        return @{ Passed = $false; Detail = "the dialect pattern also matches Claude's correct `${NAME} form, so it would condemn every valid manifest." }
    }
    $bad = [Collections.Generic.List[string]]::new()
    $inspected = 0
    foreach ($package in $packages) {
        $mcpPath = Join-Path $package.FullName '.mcp.json'
        if (-not (Test-Path -LiteralPath $mcpPath -PathType Leaf)) { continue }
        $inspected++
        $text = [IO.File]::ReadAllText($mcpPath)
        foreach ($match in @([regex]::Matches($text, $registryDialectPattern))) {
            $name = $match.Groups[1].Value
            $bad.Add("packages\$($package.Name)\.mcp.json uses the registry's host-neutral spelling '`${env:$name}'; Claude Code reads a plugin's .mcp.json directly and does not translate it, so the server receives that text literally. Write '`${$name}' here. The `${env:...} form is correct ONLY in registry/mcps.json, which Sync-AgentHub.ps1 translates per host.")
        }
    }
    if ($inspected -eq 0) {
        return @{ Passed = $false; Detail = "none of the $($packages.Count) plugin package(s) carries a .mcp.json, so this check inspected no file. If plugins stopped shipping MCP servers that is fine, but this check is then asserting nothing and should be reconsidered rather than left green." }
    }
    if ($bad.Count -gt 0) { return @{ Passed = $false; Detail = ($bad -join '; ') } }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-EveryPluginPassesHostValidator
Report 'every AgentHub plugin passes the host schema via claude plugin validate' $r1.Passed $r1.Detail

$r2 = Test-HostValidatorRejectsABrokenManifest
Report 'the host validator rejects a manifest broken the way one actually shipped' $r2.Passed $r2.Detail

$r3 = Test-SuiteNeverWritesATrackedManifest $r2
Report 'the suite mutates only a copy outside the repository and leaves the tracked manifest byte-identical' $r3.Passed $r3.Detail

$r4 = Test-PluginMcpUsesClaudeVariableDialect
Report "every plugin .mcp.json spells variables in Claude's `${NAME} dialect, not the registry's `${env:NAME}" $r4.Passed $r4.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}

# Root plugin.json is the portable Agent Plugins floor and the version
# authority. Host projections may add host-native fields but must not diverge
# on version. On 2026-08-19 only .claude-plugin was bumped for one package, so
# hosts disagreed; requiring root authority prevents that split.
$hostManifestDirs = @('.claude-plugin', '.codex-plugin', '.cursor-plugin', '.qoder-plugin')
$packagesWithHostVersion = 0
foreach ($pkgDir in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'packages') -Directory) {
    $rootManifest = Join-Path $pkgDir.FullName 'plugin.json'
    $hostVersions = [ordered]@{}
    foreach ($hostDir in $hostManifestDirs) {
        $hostManifest = Join-Path $pkgDir.FullName "$hostDir\plugin.json"
        if (-not (Test-Path -LiteralPath $hostManifest)) { continue }
        $hv = (Get-Content -LiteralPath $hostManifest -Raw -Encoding UTF8 | ConvertFrom-Json).version
        if ($hv) { $hostVersions[$hostDir] = [string]$hv }
    }
    if ($hostVersions.Count -eq 0) { continue }
    $packagesWithHostVersion++
    if (-not (Test-Path -LiteralPath $rootManifest)) {
        Report "$($pkgDir.Name) has portable root plugin.json as version authority" $false `
            "host manifests declare version(s) ($(($hostVersions.GetEnumerator() | ForEach-Object { '$($_.Key)=$($_.Value)' }) -join ', ')) but packages/$($pkgDir.Name)/plugin.json is missing."
        continue
    }
    $root = Get-Content -LiteralPath $rootManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $rv = [string]$root.version
    Report "$($pkgDir.Name) root plugin.json declares the package version" (-not [string]::IsNullOrWhiteSpace($rv)) `
        "packages/$($pkgDir.Name)/plugin.json must carry version; it is the Agent Plugins portable authority."
    if ([string]::IsNullOrWhiteSpace($rv)) { continue }
    foreach ($entry in $hostVersions.GetEnumerator()) {
        Report "$($pkgDir.Name) $($entry.Key)/plugin.json matches root version" ($entry.Value -eq $rv) `
            "root plugin.json says '$rv' but $($entry.Key)/plugin.json says '$($entry.Value)'."
    }
}
Report 'at least one package participates in portable root version authority' ($packagesWithHostVersion -gt 0) `
    'found no packages with host plugin manifests declaring version; the authority check would be vacuously true.'

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
