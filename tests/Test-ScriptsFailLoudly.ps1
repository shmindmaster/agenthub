#Requires -Version 5.1
<#
Behavior tests for task-6b coverage-gap priority 2: the meta-test for this
project's defining defect. Two parts:

  1. Every script in scripts/ sets $ErrorActionPreference = 'Stop' at its
     own top level.
  2. Scripts that take a registry root must never print a success line
     against an empty/bogus registry root -- the honest way is to invoke
     them against one and require a non-zero exit.

registry-driven scripts already have this covered by their own dedicated
test files: Sync-AgentHub.ps1 (tests/Test-SyncAgentHubRegistryRoot.ps1
Behavior 1), Sync-Instructions.ps1 (tests/Test-SyncInstructions.ps1
Behavior 4), Sync-Subagents.ps1 (tests/Test-SyncSubagents.ps1 Behavior 9).
Sync-Capabilities.ps1's own empty-work-set behavior is covered in
tests/Test-SyncCapabilities.ps1 (and is a documented, reported-not-fixed
bug there -- see that file). This file covers the two scripts that had NO
coverage at all for this contract: Validate-AgentHub.ps1, and (part 1
only, since New-AgentHubWorktree.ps1 has no "registry root" concept) a
project-wide EAP sweep.

KNOWN GAP (discovered while building this file, reported not fixed -- see
task-6 report): scripts/RegistryContentHash.ps1 is the one script under
scripts/ that does NOT set $ErrorActionPreference = 'Stop' at its own top
level. It is a function-only library (Get-AgentHubRegistryHashBasisValue
etc.) with no top-level executable statements -- every consumer
(scripts/Validate-AgentHub.ps1, tests/Test-RegistryContentHash.ps1) dot-
sources it and inherits the caller's EAP, so this has no live effect
today. It is still a real violation of this project's stated global
constraint ("$ErrorActionPreference = 'Stop'" for every script in
scripts/), so Behavior 1 below intentionally checks ALL of scripts/*.ps1
(no silent exclusion list) and is left failing for this one file, exactly
as instructed for a discovered bug this task must report, not fix
(RegistryContentHash.ps1 is not one of the three files task-6's regex-fix
scope covers).

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this
file follows). Same self-checking idiom: each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

Every -RepositoryRoot invocation below targets a synthetic scratch
directory under $env:AGENTHUB_TEST_SCRATCH. None ever targets the real
repository or the real user profile.

Run: pwsh -NoProfile -File tests/Test-ScriptsFailLoudly.ps1
     powershell.exe -NoProfile -File tests/Test-ScriptsFailLoudly.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$scriptsDir = Join-Path $repoRoot 'scripts'
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

# Get-ScriptsWithoutStopEap: pure, reusable check -- given a directory of
# *.ps1 files, returns the file names that do NOT set
# $ErrorActionPreference = 'Stop' at their own top level (a top-level
# assignment, not merely mentioned inside a nested function/string).
function Get-ScriptsWithoutStopEap {
    param([string]$Directory)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($file in (Get-ChildItem -LiteralPath $Directory -File -Filter '*.ps1' | Sort-Object Name)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ($text -notmatch '(?m)^\$ErrorActionPreference\s*=\s*[''"]Stop[''"]\s*\r?$') {
            $violations.Add($file.Name)
        }
    }
    return $violations
}

# --- Behavior 1a: the checker function itself -- proven against a
# synthetic fixture directory containing one compliant and one
# non-compliant script, never touching the real scripts/ directory. ---
function Test-CheckerFlagsScriptMissingStopEap {
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-eap-fixture-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        Set-Content -LiteralPath (Join-Path $dir 'Good.ps1') -Value "`$ErrorActionPreference = 'Stop'`nWrite-Output 'ok'`n" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'Bad.ps1') -Value "Write-Output 'no EAP set here'`n" -Encoding UTF8
        $violations = Get-ScriptsWithoutStopEap -Directory $dir
        if (($violations -join ',') -ne 'Bad.ps1') {
            return @{ Passed = $false; Detail = "expected exactly ['Bad.ps1'], got [$($violations -join ',')]" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 1b: the live sweep. Every *.ps1 directly under scripts/ sets
# $ErrorActionPreference = 'Stop', with ONE documented, reported-not-fixed
# exception (RegistryContentHash.ps1 -- see file header). This assertion
# intentionally checks the real scripts/ directory with no other silent
# exclusions, so a newly-added script that omits EAP=Stop is caught. ---
function Test-LiveScriptsSetStopEap {
    $knownReportedException = 'RegistryContentHash.ps1'
    $violations = Get-ScriptsWithoutStopEap -Directory $scriptsDir
    $unexpected = @($violations | Where-Object { $_ -ne $knownReportedException })
    if ($unexpected.Count -gt 0) {
        return @{ Passed = $false; Detail = "script(s) missing `$ErrorActionPreference = 'Stop' beyond the one documented exception: $($unexpected -join ', ')" }
    }
    if ($violations -notcontains $knownReportedException) {
        return @{ Passed = $false; Detail = "$knownReportedException now sets `$ErrorActionPreference = 'Stop' -- update this test's documented-exception comment and drop the exception." }
    }
    return @{ Passed = $true; Detail = $null }
}

function Invoke-ValidateAgentHub {
    param([string]$RepositoryRoot)
    $allArgs = @('-NoProfile', '-File', (Join-Path $scriptsDir 'Validate-AgentHub.ps1'), '-RepositoryRoot', $RepositoryRoot)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

# --- Behavior 2: Validate-AgentHub.ps1 against a bogus (nonexistent)
# repository root fails loudly. ---
function Test-ValidateAgentHubBogusRootFailsLoudly {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-validate-bogus-" + [guid]::NewGuid())
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    $result = Invoke-ValidateAgentHub -RepositoryRoot $root
    if ($result.ExitCode -eq 0) {
        return @{ Passed = $false; Detail = "exit code was 0 against a nonexistent repository root. Output: $($result.Output)" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: Validate-AgentHub.ps1 against a well-formed but entirely
# empty registry (zero agents, zero capabilities, zero of everything) still
# fails loudly and never prints its 'PASS:' success line. ---
function Test-ValidateAgentHubEmptyRegistryFailsLoudly {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-validate-empty-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'packages') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.agents\plugins') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root '.claude-plugin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $scriptsDir 'RegistryContentHash.ps1') -Destination (Join-Path $root 'scripts\RegistryContentHash.ps1')
    (@{ activeAgents = @(); inactiveAgents = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'agents.json') -Encoding UTF8 -NoNewline
    (@{ schemaVersion = 2; capabilities = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline
    (@{ mcpServers = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'mcps.json') -Encoding UTF8 -NoNewline
    (@{ products = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'product-video-delivery.json') -Encoding UTF8 -NoNewline
    (@{ hosts = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'plugin-formats.json') -Encoding UTF8 -NoNewline
    (@{ autonomyProfiles = @{ knownDefaultProfiles = @(); profiles = @(); exemptions = @() } } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $registryDir 'fleet-profile.json') -Encoding UTF8 -NoNewline
    (@{ name = 'agenthub'; plugins = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $root '.agents\plugins\marketplace.json') -Encoding UTF8 -NoNewline
    (@{ plugins = @() } | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $root '.claude-plugin\marketplace.json') -Encoding UTF8 -NoNewline
    try {
        $result = Invoke-ValidateAgentHub -RepositoryRoot $root
        if ($result.ExitCode -eq 0) {
            return @{ Passed = $false; Detail = "exit code was 0 (reported success) against a well-formed but entirely empty registry. Output: $($result.Output)" }
        }
        if ($result.Output -match 'PASS:') {
            return @{ Passed = $false; Detail = "script printed a PASS: line against an empty registry. Output: $($result.Output)" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1a = Test-CheckerFlagsScriptMissingStopEap
Report 'the EAP checker flags a script missing $ErrorActionPreference = ''Stop''' $r1a.Passed $r1a.Detail

$r1b = Test-LiveScriptsSetStopEap
Report 'every script in scripts/ sets $ErrorActionPreference = ''Stop'', with one documented reported-not-fixed exception (RegistryContentHash.ps1)' $r1b.Passed $r1b.Detail

$r2 = Test-ValidateAgentHubBogusRootFailsLoudly
Report 'Validate-AgentHub.ps1 against a bogus (nonexistent) repository root fails loudly' $r2.Passed $r2.Detail

$r3 = Test-ValidateAgentHubEmptyRegistryFailsLoudly
Report 'Validate-AgentHub.ps1 against a well-formed but entirely empty registry fails loudly, never prints PASS:' $r3.Passed $r3.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
