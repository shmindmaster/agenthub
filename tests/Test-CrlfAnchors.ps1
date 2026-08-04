#Requires -Version 5.1
<#
Behavior tests for task-6a: nine (or more) `(?m)...$` regex anchors across
this repo's validators/sync scripts that break under CRLF line endings.

In .NET, `$` in multiline (?m) mode matches the position immediately before
`\n`, not before `\r\n`. A pattern that reaches `$` right after a literal
character (no absorbing `.`, character class, or `\s*` in between) fails to
match at all when the line actually ends in `\r\n`. A pattern that reaches
`$` right after a capturing group whose class does not exclude `\r` (e.g.
`[^\n]+` or `.+`) still matches, but the captured group silently includes a
trailing `\r`. This repo is checked out CRLF in this worktree
(core.autocrlf=true) and LF in the main checkout -- so a validator's verdict
today depends on which checkout ran it. That is the defect this file exists
to close permanently.

Every one of the ten `(?m)...$` literals actually found in the three files
named by the task-6 brief (search: `rg "\(\?m[s]?\)" scripts/Sync-AgentHub.ps1
scripts/Validate-AgentHub.ps1 packages/product-experience-engineering/tests/validate-plugin.ps1`,
then manually filtering to the ones that actually terminate in a bare `$`)
is audited below:

  packages/product-experience-engineering/tests/validate-plugin.ps1
    L92  ^description: .+$                       -- already tolerant (`.` absorbs \r, no capture group at risk) -- UNCHANGED, verified below
    L97  ^tools:\s*(.+)$                          -- latent capture contamination -- FIXED
    L105 ^readonly:\s*(true|false)\s*$            -- already tolerant (\s*$, group closes before it) -- UNCHANGED, verified below
    L122 ^name: <escaped skill name>$             -- ACTIVE FAILURE (proven, see task-6-report.md) -- FIXED
    L124 ^## Standalone execution$                -- ACTIVE FAILURE (proven, see task-6-report.md) -- FIXED

  scripts/Validate-AgentHub.ps1
    L46  ^name:\s*([^\n]+)$                       -- latent capture contamination -- FIXED
    L47  ^description:\s*([^\n]+)$                -- latent capture contamination -- FIXED

  scripts/Sync-AgentHub.ps1
    L980  ^source\s*=.*$ (used in -replace)       -- ACTIVE CORRUPTION (the replaced line loses its \r, degrading CRLF to LF for that one line) -- FIXED
    L1096 ^\[mcp_servers\.([^\].]+)\]$             -- ACTIVE FAILURE (the -Prune stale-section scan finds zero top-level sections against a CRLF host TOML, so MCP prune silently does nothing -- the project's defining defect) -- FIXED
    L1260 ^mcp_servers:\s*$                        -- already tolerant (\s*$, no group at risk) -- UNCHANGED, verified below

Everything else matching `(?m...)` in these three files either has no `$`
anchor at all (a prefix/substring check) or already anchors on `\r?$`/uses
singleline mode with an explicit `\r?` in a lookahead (scripts/Sync-AgentHub.ps1
L948, L976, L995 -- pre-existing, already correct) and is out of scope.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
self-checking idiom: each Test-* function returns a result, the runner
prints one PASS/FAIL line per behavior, accumulates failures, and exits 1 if
any behavior did not hold, 0 otherwise.

Every -Apply invocation below targets a synthetic -RegistryRoot/-UserProfile
pair under $env:AGENTHUB_TEST_SCRATCH. None ever targets the real registry
root or user profile.

Run: pwsh -NoProfile -File tests/Test-CrlfAnchors.ps1
     powershell.exe -NoProfile -File tests/Test-CrlfAnchors.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$validatePluginScript = Join-Path $repoRoot 'packages\product-experience-engineering\tests\validate-plugin.ps1'
$validateAgentHubScript = Join-Path $repoRoot 'scripts\Validate-AgentHub.ps1'
$syncAgentHubScript = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'
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

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

# ---------------------------------------------------------------------------
# Extraction helpers: pull the ACTUAL regex literal text out of the live
# script source at test time, so these assertions test the real code (not a
# hand-copied stand-in that could silently drift from it) without needing to
# dot-source scripts that are not designed to be dot-sourced (both
# Sync-AgentHub.ps1 and Validate-AgentHub.ps1 execute their whole sync/
# validation pass as top-level statements the moment they are loaded).
# Anchor substrings are chosen to be the part of each pattern this task does
# NOT change, so the same anchor locates the literal both before and after
# the fix is applied (proving RED against the unfixed file, then GREEN
# against the fixed one, using one unmodified test).
# ---------------------------------------------------------------------------
function Get-QuotedLiteralContainingSubstring {
    param([string]$SourceText, [string]$AnchorSubstring, [string]$Because)
    $idx = $SourceText.IndexOf($AnchorSubstring, [StringComparison]::Ordinal)
    if ($idx -lt 0) { throw "anchor substring not found ($Because): $AnchorSubstring" }
    $openIdx = $SourceText.LastIndexOf("'", $idx)
    if ($openIdx -lt 0) { throw "no opening quote found before anchor ($Because): $AnchorSubstring" }
    $closeIdx = $SourceText.IndexOf("'", $idx)
    if ($closeIdx -lt 0) { throw "no closing quote found after anchor ($Because): $AnchorSubstring" }
    return $SourceText.Substring($openIdx + 1, $closeIdx - $openIdx - 1)
}

function Get-QuotedLiteralAfterMarker {
    param([string]$SourceText, [string]$Marker, [string]$Because)
    $idx = $SourceText.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($idx -lt 0) { throw "marker not found ($Because): $Marker" }
    $openIdx = $idx + $Marker.Length
    if ($SourceText[$openIdx] -ne "'") { throw "marker was not immediately followed by an opening quote ($Because): $Marker" }
    $closeIdx = $SourceText.IndexOf("'", $openIdx + 1)
    if ($closeIdx -lt 0) { throw "no closing quote found after marker ($Because): $Marker" }
    return $SourceText.Substring($openIdx + 1, $closeIdx - $openIdx - 1)
}

# --- Behavior 1: the real, checked-out-CRLF package validator must not fail
# on either of the two CRLF-regex-anchor checks this task fixes (L122's
# per-skill name match, L124's Standalone-execution match). This does NOT
# assert the validator exits 0 overall: running it against this worktree's
# real content surfaces a SEPARATE, pre-existing, out-of-scope defect --
# references/product-experience-audit-remediation-guide.md's hardcoded
# SHA256 constant (validate-plugin.ps1 ~L140) was computed against an
# LF-normalized copy of that file, so it mismatches in this CRLF worktree
# too, by a completely different mechanism (a raw content hash, not a
# regex anchor). Confirmed: the same file passes cleanly end-to-end in the
# LF main checkout (C:\Repos\shmindmaster\agenthub) but fails on this
# separate hash check in this CRLF worktree even after L122/L124 are fixed.
# That second defect is now fixed too: the guide hash is taken over
# newline-normalized bytes. The constant itself did not change -- the
# normalized digest already equalled the LF-file digest -- so the validator
# now runs clean end to end in both checkouts. ---
function Test-PackageValidatorNoLongerFailsOnCrlfRegexAnchorChecks {
    $allArgs = @('-NoProfile', '-File', $validatePluginScript)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($output -match 'Skill name mismatch') {
        return @{ Passed = $false; Detail = "the L122 skill-name CRLF anchor bug is still present. Output: $output" }
    }
    if ($output -match 'Skill must define standalone execution behavior') {
        return @{ Passed = $false; Detail = "the L124 standalone-execution CRLF anchor bug is still present. Output: $output" }
    }
    if ($output -match 'Canonical pre-video guide') {
        return @{ Passed = $false; Detail = "the guide-hash check is still comparing raw bytes, so it still depends on the checkout's line endings. Output: $output" }
    }
    if ($output -notmatch 'plugin structure, metadata, references, assets, and inactive hooks are valid') {
        return @{ Passed = $false; Detail = "expected the package validator to run clean end to end in this CRLF worktree. Output: $output" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: validate-plugin.ps1's tools: capture (L97) must not include
# a trailing \r in the captured value when the source file is CRLF. ---
function Test-ValidatePluginToolsCaptureExcludesTrailingCr {
    $source = [IO.File]::ReadAllText($validatePluginScript)
    $pattern = Get-QuotedLiteralContainingSubstring -SourceText $source -AnchorSubstring '^tools:\s*(' -Because 'validate-plugin.ps1 tools: capture'
    $sample = "tools: Read, Grep`r`nreadonly: false`r`n"
    $match = [regex]::Match($sample, $pattern)
    if (-not $match.Success) {
        return @{ Passed = $false; Detail = "pattern '$pattern' did not match CRLF sample content at all: [$sample]" }
    }
    $captured = $match.Groups[1].Value
    if ($captured -ne 'Read, Grep') {
        return @{ Passed = $false; Detail = "captured tools value was '$captured' (length $($captured.Length)), expected 'Read, Grep' with no trailing CR" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: Validate-AgentHub.ps1's skill name capture (L46) must not
# include a trailing \r when SKILL.md is CRLF. ---
function Test-ValidateAgentHubNameCaptureExcludesTrailingCr {
    $source = [IO.File]::ReadAllText($validateAgentHubScript)
    $pattern = Get-QuotedLiteralContainingSubstring -SourceText $source -AnchorSubstring '^name:\s*(' -Because 'Validate-AgentHub.ps1 skill name capture'
    $sample = "---`r`nname: engineer-product-experience`r`ndescription: Use when doing a thing.`r`n---`r`n"
    $match = [regex]::Match($sample, $pattern)
    if (-not $match.Success) {
        return @{ Passed = $false; Detail = "pattern '$pattern' did not match CRLF sample content at all: [$sample]" }
    }
    $captured = $match.Groups[1].Value
    if ($captured -ne 'engineer-product-experience') {
        return @{ Passed = $false; Detail = "captured name value was '$captured' (length $($captured.Length)), expected 'engineer-product-experience' with no trailing CR" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: Validate-AgentHub.ps1's skill description capture (L47)
# must not include a trailing \r when SKILL.md is CRLF. ---
function Test-ValidateAgentHubDescriptionCaptureExcludesTrailingCr {
    $source = [IO.File]::ReadAllText($validateAgentHubScript)
    $pattern = Get-QuotedLiteralContainingSubstring -SourceText $source -AnchorSubstring '^description:\s*(' -Because 'Validate-AgentHub.ps1 skill description capture'
    $sample = "---`r`nname: engineer-product-experience`r`ndescription: Use when doing a thing.`r`n---`r`n"
    $match = [regex]::Match($sample, $pattern)
    if (-not $match.Success) {
        return @{ Passed = $false; Detail = "pattern '$pattern' did not match CRLF sample content at all: [$sample]" }
    }
    $captured = $match.Groups[1].Value
    if ($captured -ne 'Use when doing a thing.') {
        return @{ Passed = $false; Detail = "captured description value was '$captured' (length $($captured.Length)), expected 'Use when doing a thing.' with no trailing CR" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: Sync-AgentHub.ps1's marketplace source-line -replace (L980)
# must not degrade the replaced line's CRLF ending to a bare LF, and must
# leave surrounding lines untouched. ---
function Test-SyncAgentHubSourceReplacePreservesCrlf {
    $source = [IO.File]::ReadAllText($syncAgentHubScript)
    $pattern = Get-QuotedLiteralAfterMarker -SourceText $source -Marker '$section -replace ' -Because 'Sync-AgentHub.ps1 marketplace source-line replace'
    $section = "[marketplaces.agenthub]`r`nsource = 'C:\old\path'`r`ntrust_level = `"trusted`"`r`n"
    $sourceLine = "source = 'C:\new\path'"
    $newSection = $section -replace $pattern, $sourceLine
    if ($newSection -notmatch [regex]::Escape("source = 'C:\new\path'`r`n")) {
        return @{ Passed = $false; Detail = "replaced source line did not keep its CRLF ending -- CRLF was degraded to a bare LF. Result: [$newSection]" }
    }
    if ($newSection -notmatch [regex]::Escape("trust_level = `"trusted`"`r`n")) {
        return @{ Passed = $false; Detail = "the untouched following line was corrupted by the replace. Result: [$newSection]" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: Sync-AgentHub.ps1's top-level mcp_servers section-header
# scan (L1096, used by -Prune) must actually find sections in a CRLF host
# TOML file. If it does not, -Prune silently removes nothing -- "MCP sync
# would quietly do nothing", the project's defining defect per the brief. ---
function Test-SyncAgentHubMcpSectionHeaderMatchesCrlf {
    $source = [IO.File]::ReadAllText($syncAgentHubScript)
    $pattern = Get-QuotedLiteralContainingSubstring -SourceText $source -AnchorSubstring '\[mcp_servers\.([^\].]+)\]' -Because 'Sync-AgentHub.ps1 top-level mcp_servers section header scan'
    $sample = "[mcp_servers.stale-entry]`r`ncommand = `"old.exe`"`r`nargs = []`r`n`r`n[mcp_servers.sample-server]`r`ncommand = `"sample.exe`"`r`n"
    $matches = [regex]::Matches($sample, $pattern)
    if ($matches.Count -eq 0) {
        return @{ Passed = $false; Detail = "pattern '$pattern' found zero top-level mcp_servers sections in CRLF sample content -- this is the exact 'MCP sync quietly does nothing' defect. Sample: [$sample]" }
    }
    $keys = @($matches | ForEach-Object { $_.Groups[1].Value }) -join ','
    if ($keys -ne 'stale-entry,sample-server') {
        return @{ Passed = $false; Detail = "expected keys 'stale-entry,sample-server', got '$keys'" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 7: end-to-end regression guard for the L1096 defect. Runs the
# REAL Sync-AgentHub.ps1 -Apply -Prune against a synthetic -RegistryRoot and
# -UserProfile (never the real registry or profile) with a CRLF codex
# config.toml that contains a stale, non-canonical [mcp_servers.*] section.
# Before the fix, -Prune silently leaves it in place; after the fix, it is
# removed while the canonical entry is written. ---
function Test-SyncAgentHubPruneRemovesStaleCrlfMcpSection {
    $fixtureRoot = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-crlf-mcp-prune-repo-" + [guid]::NewGuid())
    $fixtureProfile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-crlf-mcp-prune-profile-" + [guid]::NewGuid())
    $registryDir = Join-Path $fixtureRoot 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $fixtureProfile -Force | Out-Null
    $configPath = Join-Path $fixtureProfile 'config.toml'
    try {
        $agents = @{
            activeAgents = @(
                @{ id = 'codex'; name = 'Fixture Codex'; status = 'active'; nativePaths = @{ config = $configPath } }
            )
            inactiveAgents = @()
        }
        ($agents | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline

        $mcps = @{
            mcpServers = @(
                @{ id = 'sample-server'; transport = 'stdio'; command = 'sample.exe'; args = @('--flag') }
            )
        }
        ($mcps | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Encoding UTF8 -NoNewline

        $capabilities = @{
            schemaVersion = 2
            capabilities = @(
                @{ id = 'fixture-cap'; owner = 'test'; capabilityType = 'skills'; canonicalSource = 'packages/does-not-exist' }
            )
        }
        ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

        # CRLF TOML, byte-exact, with a stale top-level section absent from
        # the fixture's own registry/mcps.json above.
        $crlfToml = "[mcp_servers.stale-entry]`r`ncommand = `"old.exe`"`r`nargs = []`r`n"
        [IO.File]::WriteAllText($configPath, $crlfToml, [Text.UTF8Encoding]::new($false))

        $allArgs = @('-NoProfile', '-File', $syncAgentHubScript, '-Apply', '-Prune', '-RegistryRoot', $fixtureRoot, '-UserProfile', $fixtureProfile)
        $previousEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $hostExe @allArgs 2>&1 | Out-String
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "exit code was $LASTEXITCODE. Output: $output" }
        }
        $resultToml = [IO.File]::ReadAllText($configPath)
        if ($resultToml -match 'stale-entry') {
            return @{ Passed = $false; Detail = "-Prune left the stale, non-canonical [mcp_servers.stale-entry] section in place against a CRLF host TOML -- this is the exact 'MCP sync quietly does nothing' defect. Resulting file: [$resultToml]" }
        }
        if ($resultToml -notmatch 'sample-server') {
            return @{ Passed = $false; Detail = "the canonical [mcp_servers.sample-server] entry was not written. Resulting file: [$resultToml]" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixtureProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 8 (regression guard, not a new fix): the anchors already using
# the accepted \s*$ dialect (validate-plugin.ps1 L105, Sync-AgentHub.ps1
# L1260) must stay CRLF-tolerant. These are extracted the same way as the
# fixed ones so a future edit that drops the \s* is caught here too. ---
function Test-AlreadyTolerantAnchorsStayTolerant {
    $pluginSource = [IO.File]::ReadAllText($validatePluginScript)
    $readonlyPattern = Get-QuotedLiteralContainingSubstring -SourceText $pluginSource -AnchorSubstring '^readonly:\s*(true|false)\s*$' -Because 'validate-plugin.ps1 readonly capture'
    $readonlySample = "readonly: true`r`n"
    if (-not [regex]::IsMatch($readonlySample, $readonlyPattern)) {
        return @{ Passed = $false; Detail = "readonly pattern '$readonlyPattern' no longer matches CRLF content: [$readonlySample]" }
    }

    $syncSource = [IO.File]::ReadAllText($syncAgentHubScript)
    $mcpKeyPattern = Get-QuotedLiteralContainingSubstring -SourceText $syncSource -AnchorSubstring '^mcp_servers:\s*$' -Because 'Sync-AgentHub.ps1 mcp_servers: key existence check'
    $mcpKeySample = "mcp_servers:`r`n  github:`r`n"
    if (-not [regex]::IsMatch($mcpKeySample, $mcpKeyPattern)) {
        return @{ Passed = $false; Detail = "mcp_servers: pattern '$mcpKeyPattern' no longer matches CRLF content: [$mcpKeySample]" }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-PackageValidatorNoLongerFailsOnCrlfRegexAnchorChecks
Report 'the real, CRLF-checked-out package validator runs clean end to end' $r1.Passed $r1.Detail

$r2 = Test-ValidatePluginToolsCaptureExcludesTrailingCr
Report 'validate-plugin.ps1 tools: capture excludes a trailing CR under CRLF' $r2.Passed $r2.Detail

$r3 = Test-ValidateAgentHubNameCaptureExcludesTrailingCr
Report 'Validate-AgentHub.ps1 skill name capture excludes a trailing CR under CRLF' $r3.Passed $r3.Detail

$r4 = Test-ValidateAgentHubDescriptionCaptureExcludesTrailingCr
Report 'Validate-AgentHub.ps1 skill description capture excludes a trailing CR under CRLF' $r4.Passed $r4.Detail

$r5 = Test-SyncAgentHubSourceReplacePreservesCrlf
Report 'Sync-AgentHub.ps1 marketplace source-line replace preserves CRLF line endings' $r5.Passed $r5.Detail

$r6 = Test-SyncAgentHubMcpSectionHeaderMatchesCrlf
Report 'Sync-AgentHub.ps1 top-level mcp_servers section-header scan matches under CRLF' $r6.Passed $r6.Detail

$r7 = Test-SyncAgentHubPruneRemovesStaleCrlfMcpSection
Report 'end-to-end: -Apply -Prune removes a stale mcp_servers section from a CRLF host TOML' $r7.Passed $r7.Detail

$r8 = Test-AlreadyTolerantAnchorsStayTolerant
Report 'anchors already using the \s*$ dialect stay CRLF-tolerant (regression guard)' $r8.Passed $r8.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
