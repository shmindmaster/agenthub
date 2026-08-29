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
    Set-Content -LiteralPath (Join-Path $Path 'docs\README.md') -Encoding UTF8 -Value "# Documentation Map`n`n[current-state.md](./current-state.md)`n[completed/](./plans/completed/)`n"
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
        compliant  = [pscustomobject]@{ tracker = 'none' }
        drifting   = [pscustomobject]@{ tracker = 'none' }
        'corrupt-vcs' = [pscustomobject]@{ tracker = 'none' }
    }
}
Set-Content -LiteralPath (Join-Path $fixtureRoot '.repowise-workspace.yaml') -Encoding UTF8 -Value "version: 1`nrepos:`n- path: compliant`n- path: drifting`n- path: corrupt-vcs`n"
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
Set-Content -LiteralPath (Join-Path $bad 'error.log') -Value 'stale log'
# A directory link whose target does not exist: the negative half of the
# directory-link fixture below. The trailing '/' must not hide the breakage.
New-Item -ItemType Directory -Force (Join-Path $bad 'docs') | Out-Null
Set-Content -LiteralPath (Join-Path $bad 'docs\README.md') -Encoding UTF8 -Value "# Documentation Map`n`n[missing/](./no-such-dir/)`n"
# .repowise deliberately absent -> indexed check must fail

# --- Fixture 3: repo with an unusable .git (present as a directory, but not
# a valid git repository) plus a .repowise/state.json claiming a specific
# commit. `git -C $path rev-parse HEAD` must fail here -- this proves the
# freshness check's error path (line ~298: `2>$null`) surfaces that failure
# honestly instead of silently swallowing it and reporting the unrelated,
# misleading verdict "index not at HEAD". ---
$brokenGit = Join-Path $fixtureRoot 'corrupt-vcs'
New-Item -ItemType Directory -Force $brokenGit | Out-Null
New-Item -ItemType Directory -Force (Join-Path $brokenGit '.git') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $brokenGit '.repowise') | Out-Null
Set-Content -LiteralPath (Join-Path $brokenGit '.repowise\state.json') -Encoding UTF8 `
    -Value '{ "last_sync_commit": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" }'

$oldLocation = Get-Location
try {
    # Compliant repo passes every check whose preconditions we fabricated.
    $out = & $checker -Repo compliant -ConfigPath $configPath 2>&1 | Out-String
    $code = $LASTEXITCODE
    Report 'compliant-repo-passes' ($code -eq 0) (($out.Trim().Split("`n")) | Select-Object -Last 3 | Out-String)

    # Directory links with a trailing '/' must resolve to the directory they
    # name. Join-Path mangles a child with a trailing separator
    # ('a\b' + 'c\' joins as 'a\b\c\'), which made links like
    # [completed/](./plans/completed/) fail even when the directory exists --
    # the drift agenthub's own docs/README.md carried. The compliant fixture
    # links docs/README.md -> ./plans/completed/ and that directory exists, so
    # any broken-link verdict here is the defect this fixture pins.
    Report 'directory-link-to-existing-dir-not-broken' ($out -notmatch 'broken-link') `
        "compliant repo reported a broken link for a directory link whose target exists. Output tail: $((($out.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"

    # A git failure during the freshness check must be reported honestly --
    # never silently swallowed into the unrelated "index not at HEAD" verdict.
    $outBrokenGit = & $checker -Repo corrupt-vcs -ConfigPath $configPath 2>&1 | Out-String
    Report 'corrupt-vcs-freshness-check-runs' ($outBrokenGit -match 'repowise-freshness') `
        (($outBrokenGit.Trim().Split("`n")) | Select-Object -Last 8 | Out-String)
    Report 'corrupt-vcs-does-not-claim-stale-index' ($outBrokenGit -notmatch 'index not at HEAD') `
        "checker blamed 'index not at HEAD' for a git command failure, not a real staleness verdict. Output tail: $((($outBrokenGit.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"
    # Deliberately specific (not a bare 'git' substring match, which
    # 'gitignore-repowise' -- a check name printed for every repo -- would
    # satisfy trivially and prove nothing).
    Report 'corrupt-vcs-names-the-real-failure' ($outBrokenGit -match '(?i)(not a git repository|rev-parse HEAD|fatal:)') `
        "expected the freshness failure detail to name the git command failure. Output tail: $((($outBrokenGit.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"

    # Drifting repo fails and names the drift.
    $outBad = & $checker -Repo drifting -ConfigPath $configPath 2>&1 | Out-String
    $codeBad = $LASTEXITCODE
    Report 'drift-detected-exit-1' ($codeBad -eq 1) "exit=$codeBad"
    Report 'drift-names-cursorrules' ($outBad -match 'forbidden:\.cursorrules') (($outBad.Trim().Split("`n")) | Select-Object -Last 6 | Out-String)
    Report 'drift-names-missing-agents' ($outBad -match 'root-file:AGENTS\.md') (($outBad.Trim().Split("`n")) | Select-Object -Last 6 | Out-String)
    Report 'drift-names-root-scratch' ($outBad -match 'root-scratch.*error\.log') (($outBad.Trim().Split("`n")) | Select-Object -Last 8 | Out-String)
    Report 'drift-names-repowise' ($outBad -match 'repowise-indexed') (($outBad.Trim().Split("`n")) | Select-Object -Last 8 | Out-String)
    # Negative half of the directory-link fixture: a link to a directory that
    # does not exist must still be named as broken, trailing '/' and all.
    Report 'drift-names-broken-directory-link' ($outBad -match 'broken-link:.*no-such-dir') `
        "expected the broken directory link './no-such-dir/' to be named. Output tail: $((($outBad.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"

    # -Fix -WhatIf previews mutations without performing them
    # (SupportsShouldProcess). Run before the real -Fix below, while
    # .cursorrules and the docs skeleton gap still exist to preview.
    try {
        $outWhatIf = & $checker -Repo drifting -ConfigPath $configPath -Fix -WhatIf 2>&1 | Out-String
        $codeWhatIf = $LASTEXITCODE
    } catch {
        $outWhatIf = "INVOCATION FAILED: $($_.Exception.Message)"
        $codeWhatIf = -1
    }
    Report 'fix-whatif-does-not-delete-forbidden' `
        (Test-Path -LiteralPath (Join-Path $bad '.cursorrules')) `
        "-Fix -WhatIf must not delete .cursorrules. exit=$codeWhatIf. Output tail: $((($outWhatIf.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"
    Report 'fix-whatif-does-not-create-docs-skeleton' `
        (-not (Test-Path -LiteralPath (Join-Path $bad 'docs\plans\PLANS.md'))) `
        "-Fix -WhatIf must not create docs\plans\PLANS.md. Output tail: $((($outWhatIf.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"
    # PowerShell's own "What if:" preview line is written straight to host UI
    # (PSHostUserInterface), never through any redirectable stream -- proven
    # empirically: even `*>&1` does not capture it. The RESULT summary line
    # (plain Write-Output, genuinely capturable) is the honest place to prove
    # -WhatIf suppressed every fix.
    Report 'fix-whatif-reports-zero-auto-fixed' `
        ($outWhatIf -match 'RESULT:.*\b0 auto-fixed\b') `
        "Expected the RESULT summary to report 0 auto-fixed under -WhatIf. Output tail: $((($outWhatIf.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"

    # -Fix deletes forbidden files and creates the docs skeleton, nothing else.
    $outRealFix = & $checker -Repo drifting -ConfigPath $configPath -Fix 2>&1 | Out-String
    Report 'fix-deletes-forbidden' (-not (Test-Path -LiteralPath (Join-Path $bad '.cursorrules'))) '.cursorrules survived -Fix'
    Report 'fix-creates-docs-skeleton' ((Test-Path -LiteralPath (Join-Path $bad 'docs\plans\PLANS.md')) -and (Test-Path -LiteralPath (Join-Path $bad 'docs\current-state.md'))) 'docs skeleton missing after -Fix'
    # Without -WhatIf, ShouldProcess must default to proceeding (no prompt,
    # no silent no-op) so real -Fix still reports a nonzero auto-fixed count
    # -- guards against a ShouldProcess wiring that accidentally suppresses
    # every fix regardless of -WhatIf.
    Report 'fix-real-reports-nonzero-auto-fixed' `
        ($outRealFix -match 'RESULT:.*auto-fixed' -and $outRealFix -notmatch 'RESULT:.*\b0 auto-fixed\b') `
        "Expected a nonzero auto-fixed count from a real (non-WhatIf) -Fix run. Output tail: $((($outRealFix.Trim() -split "`n") | Select-Object -Last 8) -join ' | ')"

    # -Fix runs Remove-Item -Recurse -Force on a path built from config data
    # against a SIBLING repository. Without containment, a blank entry makes
    # Join-Path return the repo root itself and -Fix deletes the whole repo; a
    # '..' or absolute entry escapes it entirely. Assert refusal, and assert
    # the repo survives -- a guard that only logs is not a guard.
    foreach ($case in @(
        @{ Name = 'blank';    Entry = '   ' },
        @{ Name = 'traversal'; Entry = '..\ESCAPED.md' },
        @{ Name = 'absolute'; Entry = (Join-Path $fixtureRoot 'ESCAPED.md') })) {

        $evilPath = Join-Path $fixtureRoot 'repo-standard.evil.json'
        $evil = $fixtureConfig | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $evil.forbiddenPaths = @($case.Entry)
        $evil | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evilPath -Encoding UTF8

        # A canary the escaping entries would delete if containment is missing.
        $canary = Join-Path $fixtureRoot 'ESCAPED.md'
        Set-Content -LiteralPath $canary -Encoding UTF8 -Value 'canary'
        # The drifting fixture deliberately has no README.md -- missing root
        # files is its drift -- so the canary is the repository directory
        # itself plus a file the checker never deletes. A blank entry made
        # Join-Path return this directory and -Fix removed it wholesale.
        $marker = $bad

        $out = & pwsh -NoProfile -File $checker -ConfigPath $evilPath -All -Fix 2>&1 | Out-String

        # No canary disjunction: survival is asserted on its own below, and
        # folding it in here made the refusal itself unfalsifiable.
        Report "fix-refuses-$($case.Name)-forbidden-entry" `
            ($out -match 'Refus|refus|invalid|outside') `
            "no refusal reported for entry '$($case.Entry)'; output tail: $((($out.Trim() -split "`n") | Select-Object -Last 4) -join ' | ')"

        Report "fix-does-not-destroy-repo-on-$($case.Name)-entry" `
            (Test-Path -LiteralPath $marker) `
            "the fixture repository DIRECTORY was deleted by a '$($case.Entry)' forbiddenPaths entry"

        Report "fix-does-not-escape-repo-on-$($case.Name)-entry" `
            (Test-Path -LiteralPath $canary) `
            "a file OUTSIDE the repo was deleted via forbiddenPaths entry '$($case.Entry)'"

        Remove-Item -LiteralPath $canary -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $evilPath -Force -ErrorAction SilentlyContinue
    }
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
