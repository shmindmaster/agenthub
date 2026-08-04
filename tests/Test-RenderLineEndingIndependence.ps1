#Requires -Version 5.1
<#
The generated host files must not depend on the line endings of the checkout
that produced them.

This was a live defect. The subagent and instruction files were deployed from
a CRLF worktree (core.autocrlf=true), so the deployed bytes embedded CRLF. The
same commit audited from the LF main checkout then reported drift on 48 of 72
subagent files and 14 of 14 instruction files, while each checkout reported
itself clean. Identical content, opposite verdicts, decided by git config --
the exact defect class this repository's test suite exists to eliminate.

The fix normalizes source content to LF before rendering. This file proves it:
build two byte-different fixture trees whose only difference is line endings,
render each into its own synthetic profile, and require the outputs to be
byte-identical.

Not a Pester suite: see tests/Test-RegistryContentHash.ps1 for why. Same
accumulate-and-report idiom.

Every -Apply below targets a synthetic -RepositoryRoot/-UserProfile pair under
$env:AGENTHUB_TEST_SCRATCH. None ever targets the real registry or profile.

Run: pwsh -NoProfile -File tests/Test-RenderLineEndingIndependence.ps1
     powershell.exe -NoProfile -File tests/Test-RenderLineEndingIndependence.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncSubagents = Join-Path $repoRoot 'scripts\Sync-Subagents.ps1'
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

$agentMarkdown = @(
    '---'
    'name: fixture-reviewer'
    'description: A fixture subagent used only by this test.'
    'tools: Read, Grep, Glob'
    'readonly: true'
    '---'
    ''
    '# Fixture Reviewer'
    ''
    'First body line.'
    'Second body line.'
    ''
) -join "`n"

# One fixture repository, written with the requested line endings. Everything
# else -- ids, order, content -- is identical between the two.
function New-LineEndingFixture {
    param([Parameter(Mandatory)][ValidateSet('LF', 'CRLF')][string]$LineEnding)
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-eol-$LineEnding-" + [guid]::NewGuid())
    $registryDir = Join-Path $root 'registry'
    $agentsDir = Join-Path $root 'packages\zz-eol-cap\agents'
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null

    $body = if ($LineEnding -eq 'CRLF') { $agentMarkdown.Replace("`n", "`r`n") } else { $agentMarkdown }
    [IO.File]::WriteAllText((Join-Path $agentsDir 'fixture-reviewer.agent.md'), $body, [Text.UTF8Encoding]::new($false))

    $manifestDir = Join-Path $root 'packages\zz-eol-cap\.codex-plugin'
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $manifestDir 'plugin.json') -Value '{ "name": "zz-eol-cap", "version": "1.0.0" }' -Encoding UTF8 -NoNewline

    $capabilities = @{
        schemaVersion = 2
        capabilities  = @(
            @{ id = 'zz-eol-cap'; owner = 'test'; capabilityType = 'skill-pack'; canonicalSource = 'packages/zz-eol-cap'; hostMappings = @() }
        )
    }
    ($capabilities | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $registryDir 'capabilities.json') -Encoding UTF8 -NoNewline

    # Reuse the real subagent-formats contract rather than inventing one, so
    # this test exercises the shipped rendering rules.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'registry\subagent-formats.json') -Destination (Join-Path $registryDir 'subagent-formats.json')

    $profile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-eol-$LineEnding-profile-" + [guid]::NewGuid())
    # Sync-Subagents skips a host whose root config directory is absent, so
    # create the one host root this fixture renders for.
    New-Item -ItemType Directory -Path (Join-Path $profile '.codex') -Force | Out-Null
    return [pscustomobject]@{ Root = $root; Profile = $profile }
}

function Invoke-SyncSubagents {
    param([Parameter(Mandatory)]$Fixture)
    $allArgs = @('-NoProfile', '-File', $syncSubagents, '-Apply', '-RepositoryRoot', $Fixture.Root, '-UserProfile', $Fixture.Profile)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $hostExe @allArgs 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-RenderedFileMap {
    param([Parameter(Mandatory)][string]$Profile)
    $map = @{}
    $agentsRoot = Join-Path $Profile '.codex\agents'
    if (-not (Test-Path -LiteralPath $agentsRoot)) { return $map }
    foreach ($file in @(Get-ChildItem -LiteralPath $agentsRoot -File -Recurse)) {
        $map[$file.Name] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    }
    return $map
}

# --- Behavior 1: rendering the same logical agent from an LF tree and from a
# CRLF tree must produce byte-identical host files. ---
function Test-RenderIsLineEndingIndependent {
    $lf = New-LineEndingFixture -LineEnding 'LF'
    $crlf = New-LineEndingFixture -LineEnding 'CRLF'
    try {
        $lfSourceBytes = [IO.File]::ReadAllBytes((Join-Path $lf.Root 'packages\zz-eol-cap\agents\fixture-reviewer.agent.md'))
        $crlfSourceBytes = [IO.File]::ReadAllBytes((Join-Path $crlf.Root 'packages\zz-eol-cap\agents\fixture-reviewer.agent.md'))
        if ([Convert]::ToBase64String($lfSourceBytes) -eq [Convert]::ToBase64String($crlfSourceBytes)) {
            return @{ Passed = $false; Detail = 'the two fixture sources are byte-identical, so this assertion would pass trivially and prove nothing.' }
        }

        $lfResult = Invoke-SyncSubagents -Fixture $lf
        if ($lfResult.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "LF fixture -Apply exit code was $($lfResult.ExitCode). Output: $($lfResult.Output)" }
        }
        $crlfResult = Invoke-SyncSubagents -Fixture $crlf
        if ($crlfResult.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "CRLF fixture -Apply exit code was $($crlfResult.ExitCode). Output: $($crlfResult.Output)" }
        }

        $lfFiles = Get-RenderedFileMap -Profile $lf.Profile
        $crlfFiles = Get-RenderedFileMap -Profile $crlf.Profile
        if ($lfFiles.Count -eq 0) {
            return @{ Passed = $false; Detail = "the LF fixture rendered zero files, so this assertion checked nothing. Output: $($lfResult.Output)" }
        }
        if ($lfFiles.Count -ne $crlfFiles.Count) {
            return @{ Passed = $false; Detail = "LF rendered $($lfFiles.Count) file(s), CRLF rendered $($crlfFiles.Count)." }
        }
        foreach ($name in $lfFiles.Keys) {
            if (-not $crlfFiles.ContainsKey($name)) {
                return @{ Passed = $false; Detail = "CRLF fixture did not render '$name'." }
            }
            if ($lfFiles[$name] -ne $crlfFiles[$name]) {
                return @{ Passed = $false; Detail = "'$name' differs between an LF and a CRLF checkout of identical content -- the rendered output depends on git's core.autocrlf." }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        foreach ($fixture in @($lf, $crlf)) {
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fixture.Profile -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$r1 = Test-RenderIsLineEndingIndependent
Report 'subagent rendering is byte-identical from an LF and a CRLF checkout' $r1.Passed $r1.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
