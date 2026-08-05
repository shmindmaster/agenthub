#Requires -Version 5.1
<#
Behavior tests for the tool-translation contract between a capability's
canonical agents/*.agent.md files and each host's toolMap in
registry/subagent-formats.json.

WHY THIS FILE EXISTS

scripts/Sync-Subagents.ps1 drops any canonical tool that a host's toolMap
does not name, and prints a NOTE line for each drop. That NOTE was itself a
fix (the generator it replaced dropped tools with no output at all). But a
NOTE is not a record: the run still summarizes `drift=0`, the fleet still
reports full parity, and the only trace of a role deployed without half its
tools is a console line that scrolls away.

Measured on 2026-08-05 before this file existed: three
product-experience-engineering roles -- experience-auditor,
experience-designer, experience-validator -- deployed to BOTH gemini and
antigravity with WebSearch and WebFetch stripped. An auditor whose declared
job is gathering external evidence arrived on two hosts with no way to
reach the web, and `Sync-Subagents -Audit` reported current=72 drift=0.

This file makes the drop a declared fact instead. A tool a host cannot map
must be named in that host's `toolsNotEstablished` with a reason; an
undeclared drop fails the build. That is the same discipline
registry/fleet-profile.json's hostSurfaces note applies to capabilities: a
value that costs a sentence to assert, and nothing to leave honest.

WHAT THIS FILE DELIBERATELY DOES NOT DO

It does not require that a host be able to map every tool. Neither Gemini
nor Antigravity is obliged to have a web-search tool, and AGENTS.md forbids
inventing an unverified host-native tool name to close the gap. The
requirement is only that the gap be written down where an auditor can find
it, rather than inferred from a console note nobody kept.

Not a Pester suite: this repo carries no Pester dependency. Same
self-checking idiom as tests/Test-SyncSubagents.ps1 and its prior art --
each Test-* function returns a result, the runner prints one PASS/FAIL line
per behavior, accumulates failures, and exits 1 if any behavior did not
hold.

Run: pwsh -NoProfile -File tests/Test-SubagentToolCoverage.ps1
     powershell.exe -NoProfile -File tests/Test-SubagentToolCoverage.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$hostExe = (Get-Process -Id $PID).Path

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

# ---------------------------------------------------------------------------
# Registry reads. -Encoding UTF8 is load-bearing, not decoration: Windows
# PowerShell 5.1 decodes a BOM-less UTF-8 file as the ANSI code page without
# it, so a registry entry carrying a non-ASCII character would compare
# unequal between the two shells. tests/Test-FileEncodingDiscipline.ps1
# enforces this repo-wide.
# ---------------------------------------------------------------------------
$formats = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\subagent-formats.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Canonical tool extraction.
#
# This mirrors Read-CanonicalAgent in scripts/Sync-Subagents.ps1 (the scalar
# comma-list `tools:` dialect; a YAML flow-sequence is that script's hard
# error, not this one's concern). Mirroring a parser invites the two copies
# to drift apart, which would leave this file asserting against tools the
# generator never actually saw -- so behavior 6 below runs the real
# generator and requires its reported drops to equal this file's computed
# ones. The mirror is checked, not trusted.
# ---------------------------------------------------------------------------
function Get-CanonicalAgentTools {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $match = [regex]::Match(
        $content,
        '\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n(?<body>[\s\S]*)\z',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) { throw "Invalid canonical agent frontmatter: $Path" }
    $frontmatter = $match.Groups['frontmatter'].Value
    $name = [regex]::Match($frontmatter, '(?m)^name:\s*(?<value>.+?)\s*$').Groups['value'].Value
    $tools = @()
    $toolsMatch = [regex]::Match($frontmatter, '(?m)^tools:\s*(?<value>.+?)\s*$')
    if ($toolsMatch.Success) {
        $raw = $toolsMatch.Groups['value'].Value.Trim()
        if (-not $raw.StartsWith('[') -and -not [string]::IsNullOrWhiteSpace($raw)) {
            $tools = @($raw -split '\s*,\s*' | Where-Object { $_ })
        }
    }
    return [pscustomobject]@{ Name = $name; Tools = $tools }
}

# Every (capability, agent) pair that actually exists on disk.
$agentRecords = [Collections.Generic.List[object]]::new()
foreach ($cap in $capabilities.capabilities) {
    $agentsDir = Join-Path $repoRoot (Join-Path $cap.canonicalSource 'agents')
    if (-not (Test-Path -LiteralPath $agentsDir)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $agentsDir -Filter '*.agent.md' -File)) {
        $parsed = Get-CanonicalAgentTools -Path $file.FullName
        $agentRecords.Add([pscustomobject]@{
            Capability = $cap.id
            Agent      = $parsed.Name
            Tools      = $parsed.Tools
        })
    }
}

# Hosts that translate tool names at all. A host with toolMap null (codex,
# opencode) passes every canonical tool through verbatim and therefore drops
# nothing -- it has no translation table to be incomplete.
$translatingHosts = @($formats.hosts | Where-Object { $null -ne $_.toolMap })

function Get-ToolMapKeys {
    param($ToolMapObj)
    if (-not $ToolMapObj) { return @() }
    return @($ToolMapObj.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-NotEstablishedKeys {
    param($HostEntry)
    if (-not $HostEntry.PSObject.Properties['toolsNotEstablished']) { return @() }
    if (-not $HostEntry.toolsNotEstablished) { return @() }
    return @($HostEntry.toolsNotEstablished.PSObject.Properties | ForEach-Object { $_.Name })
}

# The computed drop set, shared by behaviors 1, 5 and 6.
# Shape: @{ "<hostId>|<capability>|<agent>" = @(droppedTool, ...) }
$computedDrops = @{}
foreach ($hostEntry in $translatingHosts) {
    $mapped = @{}
    foreach ($key in (Get-ToolMapKeys $hostEntry.toolMap)) { $mapped[$key] = $true }
    foreach ($record in $agentRecords) {
        $dropped = @($record.Tools | Where-Object { -not $mapped.ContainsKey($_) })
        if ($dropped.Count -gt 0) {
            $computedDrops["$($hostEntry.id)|$($record.Capability)|$($record.Agent)"] = $dropped
        }
    }
}

# ---------------------------------------------------------------------------
# Behavior 1: every dropped tool is declared not-established for that host.
# ---------------------------------------------------------------------------
function Test-EveryDropIsDeclared {
    $undeclared = [Collections.Generic.List[string]]::new()
    foreach ($hostEntry in $translatingHosts) {
        $declared = @{}
        foreach ($key in (Get-NotEstablishedKeys $hostEntry)) { $declared[$key] = $true }
        foreach ($entry in $computedDrops.GetEnumerator()) {
            $parts = $entry.Key -split '\|', 3
            if ($parts[0] -ne $hostEntry.id) { continue }
            foreach ($tool in $entry.Value) {
                if (-not $declared.ContainsKey($tool)) {
                    $undeclared.Add("$($parts[1])/$($parts[2]) -> $($hostEntry.id): $tool")
                }
            }
        }
    }
    if ($undeclared.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($undeclared.Count) canonical tool(s) are dropped by a host's toolMap without being declared in that host's toolsNotEstablished. Each of these roles deploys missing a tool it asked for, and nothing in the registry records it: $($undeclared -join '; '). Either add a VERIFIED mapping to toolMap, or declare the tool under toolsNotEstablished with a reason. Do not invent a host-native tool name to silence this -- AGENTS.md forbids it, and an invented name deploys a role that calls a tool the host does not have." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 2: no declaration contradicts the toolMap it sits beside.
#
# This is what goes red when someone verifies a mapping and adds it to
# toolMap without removing the now-false "not established" claim next to it.
# ---------------------------------------------------------------------------
function Test-NoDeclarationContradictsItsToolMap {
    $contradictions = [Collections.Generic.List[string]]::new()
    foreach ($hostEntry in $translatingHosts) {
        $mapped = @{}
        foreach ($key in (Get-ToolMapKeys $hostEntry.toolMap)) { $mapped[$key] = $true }
        foreach ($key in (Get-NotEstablishedKeys $hostEntry)) {
            if ($mapped.ContainsKey($key)) {
                $contradictions.Add("$($hostEntry.id): $key")
            }
        }
    }
    if ($contradictions.Count -gt 0) {
        return @{ Passed = $false; Detail = "a host declares a tool both mapped and not-established, which cannot both be true -- the usual cause is a verified mapping being added to toolMap while the stale not-established entry beside it was left behind: $($contradictions -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 3: every declaration carries a non-empty reason.
#
# An empty reason is the thing this file exists to prevent: it records that
# a tool is missing while explaining nothing, which reads to a later auditor
# as settled rather than unexamined.
# ---------------------------------------------------------------------------
function Test-EveryDeclarationCarriesAReason {
    $empty = [Collections.Generic.List[string]]::new()
    $seen = 0
    foreach ($hostEntry in $translatingHosts) {
        if (-not $hostEntry.PSObject.Properties['toolsNotEstablished']) { continue }
        if (-not $hostEntry.toolsNotEstablished) { continue }
        foreach ($property in $hostEntry.toolsNotEstablished.PSObject.Properties) {
            $seen++
            if ([string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $empty.Add("$($hostEntry.id): $($property.Name)")
            }
        }
    }
    if ($empty.Count -gt 0) {
        return @{ Passed = $false; Detail = "toolsNotEstablished entries with a blank reason: $($empty -join '; '). A tool recorded as unmappable with no explanation is indistinguishable from one nobody looked into." }
    }
    if ($seen -eq 0) {
        return @{ Passed = $false; Detail = 'no toolsNotEstablished entry exists on any translating host, so this behavior asserted nothing. If every canonical tool genuinely maps on every host, delete this behavior rather than leaving a check that cannot fail; while any drop exists, behavior 1 requires a declaration and this one requires it to say something.' }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 4: anti-vacuity. This whole file is a scan, and a scan that
# matched nothing passes every other behavior trivially. A renamed packages/
# layout or a changed canonicalSource must turn this red rather than green.
# ---------------------------------------------------------------------------
function Test-ScanExaminedRealInput {
    if ($agentRecords.Count -eq 0) {
        return @{ Passed = $false; Detail = "discovered zero canonical *.agent.md files across $($capabilities.capabilities.Count) capabilities. Every other behavior in this file iterates that empty set and passes without asserting anything. Check registry/capabilities.json canonicalSource values against the packages/ layout." }
    }
    if ($translatingHosts.Count -eq 0) {
        return @{ Passed = $false; Detail = 'registry/subagent-formats.json declares no host with a non-null toolMap, so there is no translation table for this file to check.' }
    }
    $withTools = @($agentRecords | Where-Object { @($_.Tools).Count -gt 0 })
    if ($withTools.Count -eq 0) {
        return @{ Passed = $false; Detail = "found $($agentRecords.Count) canonical agents but not one declares a tools: line, so no tool was ever compared against a toolMap. That is far more likely a broken frontmatter parser than 17 agents genuinely declaring no tools." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 5: no declaration names a tool nothing actually requests.
#
# Accepted trade-off, stated so a later reader does not mistake it for an
# oversight: removing the last canonical agent that asks for WebSearch would
# turn this red until the corresponding declaration is also removed. That is
# the intended cost. The alternative -- letting declarations accumulate for
# tools no agent wants -- turns the list into folklore, and a reader cannot
# tell a live constraint from a fossil.
# ---------------------------------------------------------------------------
function Test-NoDeclarationIsUnused {
    $requested = @{}
    foreach ($record in $agentRecords) {
        foreach ($tool in $record.Tools) { $requested[$tool] = $true }
    }
    $unused = [Collections.Generic.List[string]]::new()
    foreach ($hostEntry in $translatingHosts) {
        foreach ($key in (Get-NotEstablishedKeys $hostEntry)) {
            if (-not $requested.ContainsKey($key)) {
                $unused.Add("$($hostEntry.id): $key")
            }
        }
    }
    if ($unused.Count -gt 0) {
        return @{ Passed = $false; Detail = "toolsNotEstablished names a tool no canonical agent requests, so the declaration constrains nothing and cannot be checked against reality: $($unused -join '; '). Remove it, or add the agent that needs it." }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 7: a per-tool citation names a mapping that exists, and says
# something.
#
# Scope, stated plainly because the registry note says the same thing and
# the two must not drift: this does NOT require every mapped tool to carry
# a citation. Most do not -- the six original mappings per host rest on the
# host-level verifiedAgainst field. It requires only that a citation which
# IS present points at a live mapping. That catches the rot case: a tool
# renamed or removed from toolMap while the sentence claiming it was
# verified stays behind, still reading as evidence for something that is no
# longer there.
# ---------------------------------------------------------------------------
function Test-EveryCitationNamesALiveMapping {
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($hostEntry in $translatingHosts) {
        if (-not $hostEntry.PSObject.Properties['toolMapVerifiedAgainst']) { continue }
        if (-not $hostEntry.toolMapVerifiedAgainst) { continue }
        $mapped = @{}
        foreach ($key in (Get-ToolMapKeys $hostEntry.toolMap)) { $mapped[$key] = $true }
        foreach ($property in $hostEntry.toolMapVerifiedAgainst.PSObject.Properties) {
            if (-not $mapped.ContainsKey($property.Name)) {
                $problems.Add("$($hostEntry.id): $($property.Name) is cited as verified but is not in that host's toolMap")
            }
            if ([string]::IsNullOrWhiteSpace([string]$property.Value)) {
                $problems.Add("$($hostEntry.id): $($property.Name) carries an empty citation")
            }
        }
    }
    if ($problems.Count -gt 0) {
        return @{ Passed = $false; Detail = "toolMapVerifiedAgainst has entries that no longer describe reality: $($problems -join '; ')" }
    }
    return @{ Passed = $true; Detail = $null }
}

# ---------------------------------------------------------------------------
# Behavior 6: the generator agrees with this file about what gets dropped.
#
# Behaviors 1-5 read the canonical files through a parser mirrored from
# scripts/Sync-Subagents.ps1. If the two parsers ever disagree, this file
# would be auditing tools the generator never saw and would pass while the
# real deployment stayed wrong. So run the real generator against a
# synthetic profile with both translating hosts installed, and require its
# NOTE lines to name exactly the (host, capability, agent, tool) tuples
# computed above -- in both directions, so neither a missed drop nor an
# invented one survives.
#
# -Audit never writes, and the synthetic profile is a scratch directory; the
# real user profile is not a parameter to this.
# ---------------------------------------------------------------------------
function Test-GeneratorAgreesWithComputedDrops {
    if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
        $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
    }
    $profileRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-toolcoverage-" + [guid]::NewGuid())
    foreach ($hostEntry in $translatingHosts) {
        $marker = $hostEntry.hostRootMarkerTemplate.Replace('{userProfile}', $profileRoot)
        New-Item -ItemType Directory -Path $marker -Force | Out-Null
    }
    try {
        $syncScript = Join-Path $repoRoot 'scripts\Sync-Subagents.ps1'
        $allArgs = @('-NoProfile', '-File', $syncScript, '-Audit', '-UserProfile', $profileRoot)
        # 5.1 wraps a child process's stderr as ErrorRecords, which turn
        # terminating under $ErrorActionPreference = 'Stop' even when the
        # child succeeded. Relax locally so output is captured, not thrown.
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $hostExe @allArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousEap
        }

        # The run must have SUCCEEDED before its output means anything.
        #
        # Without this, a generator that throws before rendering anything
        # emits zero NOTE lines, and comparing an empty reported set against
        # an empty computed set reads as agreement -- this behavior returns
        # PASS for a run that produced nothing at all. A reviewer proved that
        # by fault injection: an unrelated broken plugin.json makes
        # Get-EligibleCapabilities throw, and this check still went green.
        #
        # It survives today only because antigravity really does drop
        # WebSearch/WebFetch, which keeps $computedDrops non-empty and turns
        # most crashes into a mismatch by luck rather than by design. That
        # protection disappears the day antigravity's web tools get verified
        # -- an outcome this registry's own toolsNotEstablished text tells a
        # future maintainer to go and produce. Gating on the exit code and on
        # the generator's own terminal SUMMARY line makes an empty-vs-empty
        # comparison mean "the generator ran and found nothing to drop"
        # rather than "the generator never got that far".
        if ($exitCode -ne 0) {
            return @{ Passed = $false; Detail = "the generator exited $exitCode, so its output cannot be compared against anything. An empty drop set from a failed run is not agreement. Generator output: $($output.Trim())" }
        }
        if ($output -notmatch '(?m)^SUMMARY: ') {
            return @{ Passed = $false; Detail = "the generator exited 0 but never printed its SUMMARY line, so it did not complete a full audit pass and its NOTE lines (or absence of them) prove nothing. Generator output: $($output.Trim())" }
        }

        $reportedDrops = @{}
        foreach ($line in ($output -split "`r?`n")) {
            $m = [regex]::Match($line, '^NOTE: (?<cap>[^/]+)/(?<agent>[^ ]+) -> (?<host>[^:]+): unmapped tool\(s\) dropped[^:]*: (?<tools>.+?)\s*$')
            if (-not $m.Success) { continue }
            $key = "$($m.Groups['host'].Value)|$($m.Groups['cap'].Value)|$($m.Groups['agent'].Value)"
            $reportedDrops[$key] = @($m.Groups['tools'].Value -split '\s*,\s*' | Where-Object { $_ })
        }

        $problems = [Collections.Generic.List[string]]::new()
        foreach ($key in $computedDrops.Keys) {
            if (-not $reportedDrops.ContainsKey($key)) {
                $problems.Add("this file computed a drop the generator never reported: $key -> $($computedDrops[$key] -join ', ')")
                continue
            }
            $expected = @($computedDrops[$key] | Sort-Object)
            $actual = @($reportedDrops[$key] | Sort-Object)
            if (($expected -join ',') -ne ($actual -join ',')) {
                $problems.Add("drop set disagrees for ${key}: this file computed [$($expected -join ', ')], the generator reported [$($actual -join ', ')]")
            }
        }
        foreach ($key in $reportedDrops.Keys) {
            if (-not $computedDrops.ContainsKey($key)) {
                $problems.Add("the generator reported a drop this file did not compute: $key -> $($reportedDrops[$key] -join ', ')")
            }
        }

        if ($problems.Count -gt 0) {
            return @{ Passed = $false; Detail = "the tools: parser mirrored into this file has drifted from Read-CanonicalAgent in scripts/Sync-Subagents.ps1, so behaviors 1-5 are auditing a different tool set than the generator actually deploys: $($problems -join '; ')" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $profileRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------

# Each behavior runs exactly once -- behavior 6 spawns a child process, and
# evaluating it a second time to read .Detail would run the generator twice.
$behaviors = @(
    @{ Name = 'every tool a host drops is declared not-established for that host'; Run = { Test-EveryDropIsDeclared } }
    @{ Name = 'no not-established declaration contradicts its own toolMap';        Run = { Test-NoDeclarationContradictsItsToolMap } }
    @{ Name = 'every not-established declaration carries a reason';                Run = { Test-EveryDeclarationCarriesAReason } }
    @{ Name = 'the scan examined real canonical agents and a real toolMap';        Run = { Test-ScanExaminedRealInput } }
    @{ Name = 'no not-established declaration names an unrequested tool';          Run = { Test-NoDeclarationIsUnused } }
    @{ Name = 'every per-tool citation names a live mapping and says something';   Run = { Test-EveryCitationNamesALiveMapping } }
    @{ Name = 'the generator agrees with this file about what gets dropped';       Run = { Test-GeneratorAgreesWithComputedDrops } }
)
foreach ($behavior in $behaviors) {
    $result = & $behavior.Run
    Report $behavior.Name ([bool]$result.Passed) ([string]$result.Detail)
}

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
