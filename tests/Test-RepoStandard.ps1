#Requires -Version 5.1
<#
Behavior tests for scripts/Check-RepoStandard.ps1 against fixture repositories
built under %TEMP%. A checker whose "pass" path has never seen a compliant
repo, or whose "fail" path has never seen drift, is decoration -- each fixture
below exists to prove one specific verdict is real.

Run: pwsh -NoProfile -File tests/Test-RepoStandard.ps1
     powershell.exe -NoProfile -File tests/Test-RepoStandard.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$checker  = Join-Path $repoRoot 'scripts\Check-RepoStandard.ps1'

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

$fixtureRoot = Join-Path $env:TEMP ("repo-standard-fixtures-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $fixtureRoot | Out-Null

function New-FixtureRepo([string]$Name) {
    $p = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Force $p | Out-Null
    git -C $p init -q
    git -C $p config user.email fixture@example.com
    git -C $p config user.name fixture
    Set-Content -LiteralPath (Join-Path $p '.gitignore') -Value 'node_modules/' -Encoding UTF8
    git -C $p add .gitignore
    git -C $p commit -qm 'fixture init'
    return $p
}

function Write-MinimalCompliantRepo([string]$Path) {
    Set-Content -LiteralPath (Join-Path $Path 'README.md') -Encoding UTF8 -Value "# Fixture`n"
    $agents = @'
# Fixture Repository Agent Guide

## Mission

Fixture repo.

## Knowledge authority

Executable code/tests describe reality. docs/ holds intentional knowledge.
RepoWise holds derived intelligence.

## Start here

1. AGENTS.md
2. docs/README.md
3. docs/current-state.md

## RepoWise workflow

Use RepoWise before broad exploration.

## Canonical commands

- git status

## Tracker

None; docs/plans/ for complex work.

## Safety

Never commit secrets.

## Definition of done

Behavior exists, checks pass, docs match reality.
'@
    Set-Content -LiteralPath (Join-Path $Path 'AGENTS.md') -Encoding UTF8 -Value $agents
    Set-Content -LiteralPath (Join-Path $Path 'CLAUDE.md') -Encoding UTF8 -Value "# CLAUDE.md`n`n@AGENTS.md`n`n@.claude/CLAUDE.md`n"
    foreach ($d in @('docs\product','docs\architecture','docs\development','docs\runbooks','docs\plans\active','docs\plans\completed')) {
        New-Item -ItemType Directory -Force (Join-Path $Path $d) | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $Path 'docs\README.md') -Encoding UTF8 -Value "# Documentation Map`n`n[current-state.md](./current-state.md)`n"
    Set-Content -LiteralPath (Join-Path $Path 'docs\current-state.md') -Encoding UTF8 -Value "# Current State`n"
    Set-Content -LiteralPath (Join-Path $Path 'docs\plans\PLANS.md') -Encoding UTF8 -Value "# Execution Plans`n"
}
# Fixture config mirrors the real roster shape but points fleetRoot at TEMP.
$fixtureConfig = [pscustomobject]@{
    schemaVersion = 1
    fleetRoot = $fixtureRoot
    workspace = @{ file = '.repowise-workspace.yaml' }
    requiredRootFiles = @('README.md','AGENTS.md','CLAUDE.md')
    requiredDocsFiles = @('docs/README.md','docs/current-state.md','docs/plans/PLANS.md')
    requiredDocsDirs = @('docs/product','docs/architecture','docs/development','docs/runbooks','docs/plans')
    forbiddenPaths = @('GEMINI.md','.cursorrules','.windsurfrules','.github/copilot-instructions.md','output.txt')
    rootMarkdownAllowlist = @('README.md','AGENTS.md','CLAUDE.md','CHANGELOG.md')
    agentsAnchors = @('## Mission','Knowledge authority','Start here','RepoWise','Canonical commands','## Tracker','Definition of done','## Safety')
    claudeMaxAuthoredLines = 8
    repos = [pscustomobject]@{
        compliant = [pscustomobject]@{ tracker = 'none' }
        drifting  = [pscustomobject]@{ tracker = 'none' }
    }
}
Set-Content -LiteralPath (Join-Path $fixtureRoot '.repowise-workspace.yaml') -Encoding UTF8 -Value "version: 1`nrepos:`n- path: compliant`n- path: drifting`n"
$configPath = Join-Path $fixtureRoot 'repo-standard.test.json'
$fixtureConfig | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8

# --- Fixture 1: compliant repo (RepoWise state fabricated to match HEAD) ----
$good = New-FixtureRepo 'compliant'
Write-MinimalCompliantRepo $good
git -C $good add .
git -C $good commit -qm 'standard layout'
Set-Content -LiteralPath (Join-Path $good '.git\hooks\post-commit') -Value "#!/bin/sh`n# repowise post-commit placeholder (fixture)"
$gi = Get-Content -LiteralPath (Join-Path $good '.gitignore') -Raw -Encoding UTF8
Set-Content -LiteralPath (Join-Path $good '.gitignore') -Value ($gi + "`n.repowise/`n.claude/CLAUDE.md") -Encoding UTF8
git -C $good add .gitignore
git -C $good commit -qm 'ignore repowise state'
New-Item -ItemType Directory -Force (Join-Path $good '.repowise') | Out-Null
$head = git -C $good rev-parse HEAD
Set-Content -LiteralPath (Join-Path $good '.repowise\state.json') -Encoding UTF8 -Value ('{ "last_sync_commit": "' + $head + '" }')

# --- Fixture 2: drifting repo ----------------------------------------------
$bad = New-FixtureRepo 'drifting'
Set-Content -LiteralPath (Join-Path $bad '.cursorrules') -Value 'legacy rules'
Set-Content -LiteralPath (Join-Path $bad 'STATUS.md') -Value 'stale status'
# .repowise deliberately absent -> indexed check must fail
$oldLocation = Get-Location
try {
    # Compliant repo passes every check whose preconditions we fabricated.
    $out = & $checker -Repo compliant -ConfigPath $configPath 2>&1 | Out-String
    $code = $LASTEXITCODE
    Report 'compliant-repo-passes' ($code -eq 0) (($out.Trim().Split("`n")) | Select-Object -Last 3 | Out-String)

    # Drifting repo fails and names the drift.
    $outBad = & $checker -Repo drifting -ConfigPath $configPath 2>&1 | Out-String
    $codeBad = $LASTEXITCODE
    Report 'drift-detected-exit-1' ($codeBad -eq 1) "exit=$codeBad"
    Report 'drift-names-cursorrules' ($outBad -match 'forbidden:\.cursorrules') (($outBad.Trim().Split("`n")) | Select-Object -Last 6 | Out-String)
    Report 'drift-names-missing-agents' ($outBad -match 'root-file:AGENTS\.md') (($outBad.Trim().Split("`n")) | Select-Object -Last 6 | Out-String)
    Report 'drift-names-root-scratch' ($outBad -match 'root-scratch.*STATUS\.md') (($outBad.Trim().Split("`n")) | Select-Object -Last 8 | Out-String)
    Report 'drift-names-repowise' ($outBad -match 'repowise-indexed') (($outBad.Trim().Split("`n")) | Select-Object -Last 8 | Out-String)

    # -Fix deletes forbidden files and creates the docs skeleton, nothing else.
    $null = & $checker -Repo drifting -ConfigPath $configPath -Fix 2>&1 | Out-String
    Report 'fix-deletes-forbidden' (-not (Test-Path -LiteralPath (Join-Path $bad '.cursorrules'))) '.cursorrules survived -Fix'
    Report 'fix-creates-docs-skeleton' ((Test-Path -LiteralPath (Join-Path $bad 'docs\plans\PLANS.md')) -and (Test-Path -LiteralPath (Join-Path $bad 'docs\current-state.md'))) 'docs skeleton missing after -Fix'
    Report 'fix-does-not-author-agents' (-not (Test-Path -LiteralPath (Join-Path $bad 'AGENTS.md'))) '-Fix must never author AGENTS.md'

    # CLAUDE.md duplication heuristic: 40 authored lines must fail.
    Set-Content -LiteralPath (Join-Path $good 'CLAUDE.md') -Encoding UTF8 -Value ("# CLAUDE.md`n`n@AGENTS.md`n" + ((1..40 | ForEach-Object { "Authored rule line $_" }) -join "`n"))
    $outDup = & $checker -Repo compliant -ConfigPath $configPath 2>&1 | Out-String
    Report 'claude-duplication-detected' ($outDup -match 'claude-no-duplication') (($outDup.Trim().Split("`n")) | Select-Object -Last 4 | Out-String)

    # Nested AGENTS.md: a file that defers to the root passes, one that does not
    # fails, and the root's own AGENTS.md is never audited as nested. The last of
    # those regressed once already -- $env:TEMP is an 8.3 short path here while
    # Get-ChildItem returns the long form, so a raw string compare mistook the root
    # file for a nested one and sliced its $rel to "iant\AGENTS.md".
    Remove-Item -LiteralPath (Join-Path $good 'CLAUDE.md') -Force
    Set-Content -LiteralPath (Join-Path $good 'CLAUDE.md') -Encoding UTF8 -Value "# CLAUDE.md`n`n@AGENTS.md`n`n@.claude/CLAUDE.md`n"
    New-Item -ItemType Directory -Force (Join-Path $good 'service') | Out-Null
    Set-Content -LiteralPath (Join-Path $good 'service\AGENTS.md') -Encoding UTF8 `
        -Value "# Service — local agent notes`n`nRoot contract still applies: [``../AGENTS.md``](../AGENTS.md).`n"
    $outNested = & $checker -Repo compliant -ConfigPath $configPath 2>&1 | Out-String
    Report 'nested-deferring-passes' ($outNested -notmatch 'nested-refs-root') (($outNested.Trim().Split("`n")) | Select-Object -Last 5 | Out-String)
    Report 'root-agents-not-audited-as-nested' ($outNested -notmatch 'nested-\w+:[^\\/]*AGENTS\.md') (($outNested.Trim().Split("`n")) | Select-Object -Last 5 | Out-String)

    Set-Content -LiteralPath (Join-Path $good 'service\AGENTS.md') -Encoding UTF8 `
        -Value "# Service — local agent notes`n`nDo whatever you like in here.`n"
    $outOrphan = & $checker -Repo compliant -ConfigPath $configPath 2>&1 | Out-String
    Report 'nested-not-deferring-fails' ($outOrphan -match 'nested-refs-root:service') (($outOrphan.Trim().Split("`n")) | Select-Object -Last 5 | Out-String)
    Remove-Item -LiteralPath (Join-Path $good 'service') -Recurse -Force

    # JSON mode stays parseable for machine consumers.
    $jsonOut = & $checker -Repo drifting -ConfigPath $configPath -Format json 2>&1 | Out-String
    $parsed = $null
    try { $parsed = $jsonOut | ConvertFrom-Json } catch { }
    Report 'json-mode-parseable' ($null -ne $parsed -and $parsed.failed -gt 0) ($jsonOut.Substring(0, [Math]::Min(200, $jsonOut.Length)))
} finally {
    Set-Location $oldLocation
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f ($reported - $failures.Count), $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
