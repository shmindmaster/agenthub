#Requires -Version 5.1
<#
Behavior tests for scripts/New-AgentHubWorktree.ps1 under the shell the
global policy mandates for invoking it.

THE DEFECT
global-agent-policy.md mandates ONE way to create a worktree:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File <helper> -Cwd <repo> -Name <slug>

That is Windows PowerShell 5.1. Under 5.1, a native command writing to
stderr while $ErrorActionPreference = 'Stop' is in force produces a
TERMINATING NativeCommandError -- even when the command succeeded. git
writes ordinary progress to stderr and exits 0:

    $ git worktree add -b probebranch <path> HEAD
      exit=0
      STDOUT: HEAD is now at 77c7299 init
      STDERR: Preparing worktree (new branch 'probebranch')

So Invoke-AgentHubGit's `@(& git @Arguments 2>&1 | ...)` aborted the
helper mid-`git worktree add`. Measured end to end against a synthetic
repository, with the pre-fix helper:

    powershell.exe  ->  git.exe : Preparing worktree (new branch '...')
                        FullyQualifiedErrorId : NativeCommandError
                        exit=1
    pwsh 7          ->  C:\wt\<repo>\<slug>, exit=0

PowerShell 7 surfaces the same stderr records as strings and does not
throw, which is why the defect was invisible to anyone testing in 7. The
mandated invocation was the broken one.

The fix (1d3cde4) restores $ErrorActionPreference to 'Continue' around the
native call only, exactly as tests/Run-AllTests.ps1 already does when it
shells out. $LASTEXITCODE still drives the failure branch, so no error
handling is traded away for it.

WHAT THIS FILE COVERS, AND WHAT IT DOES NOT
Two kinds of check live here and they catch different things. Neither
subsumes the other; the overlap is stated rather than glossed.

  AST PROBE (Behaviors 1-2) -- extracts the SHIPPED Invoke-AgentHubGit by
  AST and runs that exact function text in BOTH shells against a git
  command that writes ordinary progress to stderr and exits 0. Creates
  nothing outside $env:AGENTHUB_TEST_SCRATCH.
    Catches what the end-to-end check cannot:
      (a) the helper growing a second Invoke-AgentHubGit, or losing its
          top-level $ErrorActionPreference = 'Stop'. Either is a silent
          change of meaning rather than a failure.
      (b) PROOF THAT A STDERR WRITE WAS ACTUALLY EXERCISED. Behavior 2
          asserts git's progress line was captured, so it cannot pass over
          nothing. The end-to-end check CANNOT make that assertion: the
          helper captures git's output into a local and discards it on
          success, so if git ever stopped printing "Preparing worktree" to
          stderr, the end-to-end check would go on passing while no longer
          touching the defect at all. That is why the AST probe is kept
          rather than retired as redundant.
    It also localizes a failure to the wrapper function, so a red
    end-to-end run is diagnosable rather than merely alarming.

  END-TO-END (Behaviors 3-4) -- runs the REAL script as a child process
  through the exact invocation the policy mandates, and asserts it exits 0
  and creates a registered worktree on the expected branch.
    Catches what the AST probe cannot: everything outside that one
    function -- argument handling, parameter binding, the #Requires line,
    the JSON round-trip between -Cwd/-Name and the hook input, worktree
    root resolution, and the stdout contract (the created absolute path as
    the final line). Before 1d3cde4 these two checks failed for the same
    reason; that does not make them the same test.

  DELETION FENCE (Behavior 5) -- tests THIS FILE's own containment, not
  the helper's. Behavior 3 is the only test here that writes into a live,
  policy-significant directory, so the guard that decides what it may
  delete is watched refusing an out-of-fixture path and refusing a tree
  containing a real junction, and watched still deleting what it should.
  A guard nobody has seen refuse anything is not evidence.

  NOT COVERED by any of them, and named so this file's silence is not
  misread as coverage: the stdin/WorktreeCreate-JSON entry path,
  -PlanOnly, -RepositoryName, and every refusal branch of the helper
  (existing target, stale or ambiguous registration, pre-existing branch,
  target escaping the root). Those are real behaviors of the script with
  no test here.

HOW THE LIVE-ROOT HAZARD IS CONTAINED
Get-AgentHubWorktreeTarget hard-rejects any root but C:\wt, so an
end-to-end assertion cannot be redirected into scratch -- it must write
into the live, policy-significant worktree root. C:\wt\agenthub already
holds real human worktrees, including a stale one, so an interrupted run
must not be able to add to that pile. Containment:

  * The -Cwd repository is SYNTHETIC: `git init` plus one empty commit
    under $env:AGENTHUB_TEST_SCRATCH. The real AgentHub repository is
    never passed. The helper derives the first path component from the
    LEAF of that repository's root, so the synthetic repository is named
    'agenthub-selftest-fixture' and everything this file creates lands
    under C:\wt\agenthub-selftest-fixture -- a SIBLING of C:\wt\agenthub,
    never inside it. No human worktree can collide with that name.
  * Deletion is doubly fenced (Remove-TreeUnderLiveRoot): it refuses any
    path outside C:\wt\agenthub-selftest-fixture, and it refuses any tree
    containing a reparse point/junction. Seven junctions point into this
    repository's packages/ tree, and a recursive delete that followed one
    would destroy tracked source. There is no broad sweep of C:\wt
    anywhere in this file; C:\wt\agenthub\migration-evidence-20260729 is
    deliberately untouched -- it is not ours to clean.
  * Residue from a previously interrupted run is cleared BEFORE anything
    is created, scoped to that same fixture path and nothing else.
  * Cleanup runs in a finally, removes the worktree and its branch through
    git, and then VERIFIES both are gone rather than assuming it. Behavior
    4 re-measures the live root independently instead of trusting the
    cleanup block's own word, and fails if the run created nothing for it
    to verify.
  * The branch (worktree-selftest-e2e-*) only ever exists inside the
    throwaway synthetic repository, so it cannot reach a real one. It is
    verified removed anyway: an unverified cleanup claim is not evidence.

If C:\wt is genuinely unavailable this FAILS, loudly, with the reason. It
never skips. tests/Test-PluginManifests.ps1 sets that precedent for an
absent prerequisite, and a skip that reads as a pass is this repository's
signature defect.

-HelperScript exists so the pre-fix script can be recovered into a
DISPOSABLE copy (`git show 1d3cde4~1:scripts/New-AgentHubWorktree.ps1`)
and this file pointed at it, proving the end-to-end check really goes red
-- which it does, under powershell.exe only. The default is the real
tracked script; a missing or unreadable one FAILS rather than skips. The
tracked script is never mutated to produce a red run.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this
file follows). Same self-checking idiom: each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

Outside C:\wt\agenthub-selftest-fixture, this file writes nothing beyond
$env:AGENTHUB_TEST_SCRATCH.

Run: pwsh -NoProfile -File tests/Test-WorktreeHelper.ps1
     powershell.exe -NoProfile -File tests/Test-WorktreeHelper.ps1
#>
[CmdletBinding()]
param(
    # Defaults to the real tracked helper. Overridden only to point a red
    # run at a disposable pre-fix copy; see the header.
    [string]$HelperScript
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ([string]::IsNullOrWhiteSpace($HelperScript)) {
    $HelperScript = Join-Path $repoRoot 'scripts\New-AgentHubWorktree.ps1'
}
$helperScript = [IO.Path]::GetFullPath($HelperScript)

# The only root the helper accepts, and the only place under it this file
# is ever allowed to write or delete.
$script:LiveWorktreeRoot = 'C:\wt'
$script:FixtureRepositorySlug = 'agenthub-selftest-fixture'
$script:FixtureRootPath = Join-Path $script:LiveWorktreeRoot $script:FixtureRepositorySlug

# Filled by Behavior 3, re-measured by Behavior 4.
$script:PlannedTargets = [Collections.Generic.List[string]]::new()
$script:CleanupFindings = [Collections.Generic.List[string]]::new()
$script:CleanupRan = $false

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

# Runs a native command with EAP forced to 'Continue' -- the same guard
# this file exists to require of the helper. Without it, this test would
# fail under 5.1 for its own reasons rather than the helper's.
function Invoke-NativeForTest {
    param([string]$Exe, [string[]]$Arguments)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Exe @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
        Lines = $output
    }
}

# The source text is read with [IO.File]::ReadAllText and parsed with
# ParseInput, for the reason tests/Test-FileEncodingDiscipline.ps1 gives:
# Parser::ParseFile applies its own host-dependent decoding.
function Get-ShippedFunctionText {
    param([string]$Path, [string]$Name)
    $text = [IO.File]::ReadAllText($Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "cannot parse $Path as PowerShell: $($errors[0].Message)"
    }
    return @($ast.FindAll(
        {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $Name
        },
        $true
    ) | ForEach-Object { [string]$_.Extent.Text })
}

function New-SyntheticGitRepository {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $steps = @(
        @('init', '-q', '-b', 'main', $Path),
        @('-C', $Path, 'config', 'user.email', 'agenthub-test@example.invalid'),
        @('-C', $Path, 'config', 'user.name', 'AgentHub Test'),
        @('-C', $Path, 'commit', '-q', '--allow-empty', '-m', 'init')
    )
    foreach ($step in $steps) {
        $result = Invoke-NativeForTest -Exe 'git' -Arguments $step
        if ($result.ExitCode -ne 0) {
            throw "synthetic repository setup step 'git $($step -join ' ')' failed: $($result.Output)"
        }
    }
}

function Resolve-ShellPath {
    param([string]$Name)
    $resolved = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolved) { return $null }
    return [string]$resolved.Source
}

# ---------------------------------------------------------------------------
# Live-root deletion fence. Everything that removes anything under C:\wt
# goes through here.
# ---------------------------------------------------------------------------

# Returns every reparse point (junction/symlink) at or under $Path. A
# directory that IS a reparse point short-circuits: nothing below it is
# ours, and walking through it is the mistake this guard exists to stop.
function Get-ReparsePointPath {
    param([string]$Path)
    $found = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return $found }
    $item = Get-Item -LiteralPath $Path -Force
    if (([int]$item.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
        $found.Add([string]$item.FullName)
        return $found
    }
    if ($item -is [IO.DirectoryInfo]) {
        foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue)) {
            if (([int]$child.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
                $found.Add([string]$child.FullName)
            }
        }
    }
    return $found
}

# Removes a tree under this test's own fixture root, or explains why it
# refused. Returns $null on success and an error string otherwise -- never
# throws, so a caller in a finally block records the problem instead of
# losing it. Two independent fences: path containment, then reparse points.
function Remove-TreeUnderLiveRoot {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fixturePrefix = $script:FixtureRootPath + '\'
    if (-not $full.Equals($script:FixtureRootPath, [StringComparison]::OrdinalIgnoreCase) -and
        -not $full.StartsWith($fixturePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return "refusing to delete '$full': it is outside this test's own fixture root '$($script:FixtureRootPath)'. This file never sweeps $($script:LiveWorktreeRoot) broadly -- C:\wt\agenthub holds real human worktrees."
    }
    if (-not (Test-Path -LiteralPath $full)) { return $null }
    $reparse = @(Get-ReparsePointPath -Path $full)
    if ($reparse.Count -gt 0) {
        return "refusing to recursively delete '$full': it contains reparse point(s)/junction(s) [$($reparse -join ', ')]. Seven junctions point into this repository's packages/ tree; a recursive delete that followed one would destroy tracked source. Remove the junction by hand and re-run."
    }
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $full) {
        return "removal of '$full' did not take effect: the path still exists afterwards."
    }
    return $null
}

# `git worktree list --porcelain` -> @{ <absolute worktree path> = <branch ref> }
function Get-WorktreeBranchMap {
    param([string[]]$PorcelainLines)
    $map = @{}
    $current = $null
    foreach ($line in @($PorcelainLines)) {
        $text = ([string]$line).Trim()
        if ($text -match '^worktree (.+)$') {
            $current = [IO.Path]::GetFullPath($Matches[1].Trim()).TrimEnd('\', '/')
            if (-not $map.ContainsKey($current)) { $map[$current] = '(detached-or-missing)' }
        } elseif ($current -and $text -match '^branch (.+)$') {
            $map[$current] = $Matches[1].Trim()
        }
    }
    return $map
}

# --- Behavior 1: the premise this file's probe rests on. Exactly one
# Invoke-AgentHubGit exists in the shipped helper, and the helper really
# does set $ErrorActionPreference = 'Stop' at its own top level. If either
# stops being true the probe below would be reproducing a context the
# helper no longer has, and would prove nothing -- so that is a failure
# here rather than a silent change of meaning downstream. ---
function Test-ShippedHelperPremiseHolds {
    if (-not (Test-Path -LiteralPath $helperScript -PathType Leaf)) {
        return @{ Passed = $false; Detail = "helper script not found at '$helperScript'. An unreadable script under test is a failure, not a skip." }
    }
    $functions = @(Get-ShippedFunctionText -Path $helperScript -Name 'Invoke-AgentHubGit')
    if ($functions.Count -ne 1) {
        return @{ Passed = $false; Detail = "expected exactly one Invoke-AgentHubGit definition in the helper, found $($functions.Count); the probe below extracts it by name and would otherwise test the wrong text" }
    }
    $source = [IO.File]::ReadAllText($helperScript)
    if ($source -notmatch '(?m)^\$ErrorActionPreference\s*=\s*[''"]Stop[''"]\s*\r?$') {
        return @{ Passed = $false; Detail = "the helper no longer sets `$ErrorActionPreference = 'Stop' at top level, so the probe's reproduction of its runtime context is no longer faithful" }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: the regression itself, at function scope. The shipped
# Invoke-AgentHubGit, run under $ErrorActionPreference = 'Stop' exactly as
# the helper runs it, survives a git command that writes an ordinary
# progress line to stderr and exits 0 -- in BOTH shells. powershell.exe is
# the shell the policy mandates for this helper, so a failure there is a
# failure of the mandated path, not an edge case. Both shells must be
# present: a skip is how a shell-divergent defect stays invisible.
#
# The stderr-producing command is `git checkout -b` rather than
# `git worktree add`, because it exhibits the same class -- ordinary
# progress on stderr, exit 0 -- inside a throwaway repository in scratch,
# without creating a worktree anywhere. This behavior asserts the progress
# line was actually captured, which is the assertion Behavior 3 cannot
# make and the reason this probe is kept alongside it. ---
function Test-ShippedGitWrapperSurvivesStderrProgressInBothShells {
    if (-not (Test-Path -LiteralPath $helperScript -PathType Leaf)) {
        return @{ Passed = $false; Detail = "helper script not found at '$helperScript'. An unreadable script under test is a failure, not a skip." }
    }
    $functions = @(Get-ShippedFunctionText -Path $helperScript -Name 'Invoke-AgentHubGit')
    if ($functions.Count -ne 1) {
        return @{ Passed = $false; Detail = "expected exactly one Invoke-AgentHubGit definition, found $($functions.Count)" }
    }

    $shells = [ordered]@{}
    foreach ($shellName in @('pwsh', 'powershell')) {
        $path = Resolve-ShellPath -Name $shellName
        if (-not $path) {
            return @{ Passed = $false; Detail = "$shellName is not on PATH; this defect is defined by the disagreement BETWEEN the two shells, so it cannot be verified in only one" }
        }
        $shells[$shellName] = $path
    }

    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-worktree-helper-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $synthetic = Join-Path $dir 'synthetic-repo'
        New-SyntheticGitRepository -Path $synthetic

        foreach ($shellName in $shells.Keys) {
            $branch = "stderr-progress-$shellName"
            # Reproduces the helper's own top-level context (StrictMode +
            # EAP=Stop, asserted in Behavior 1) around the shipped function.
            $probe = @(
                "Set-StrictMode -Version Latest"
                "`$ErrorActionPreference = 'Stop'"
                $functions[0]
                "try {"
                "    `$r = Invoke-AgentHubGit -Arguments @('-C', '$synthetic', 'checkout', '-b', '$branch') -Operation 'stderr progress probe'"
                "    Write-Output ('EXIT=' + `$r.exitCode)"
                "    foreach (`$line in @(`$r.output)) { Write-Output ('LINE=' + `$line) }"
                "} catch {"
                "    Write-Output ('THREW=' + `$_.Exception.GetType().FullName + ': ' + `$_.Exception.Message)"
                "}"
            ) -join "`n"
            $probeFile = Join-Path $dir ("probe-$shellName.ps1")
            [IO.File]::WriteAllText($probeFile, $probe, [Text.UTF8Encoding]::new($false))

            $result = Invoke-NativeForTest -Exe $shells[$shellName] -Arguments @('-NoProfile', '-File', $probeFile)
            $output = $result.Output

            if ($output -match 'THREW=') {
                return @{ Passed = $false; Detail = "under $shellName, the shipped Invoke-AgentHubGit turned a SUCCEEDING git command's ordinary stderr progress line into a terminating error. git exited 0; the wrapper threw. Output: $output" }
            }
            if ($output -notmatch '(?m)^EXIT=0\s*$') {
                return @{ Passed = $false; Detail = "under $shellName, the shipped Invoke-AgentHubGit did not report exit code 0 for a git command that exited 0. Output: $output" }
            }
            # Proves the probe actually exercised a stderr write. Without
            # this the behavior could pass over nothing if git ever stopped
            # printing the line.
            if ($output -notmatch "Switched to a new branch '$branch'") {
                return @{ Passed = $false; Detail = "under $shellName the probe never captured git's ``Switched to a new branch '$branch'`` progress line, so it did not exercise a stderr write at all and proves nothing. Output: $output" }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 3: the mandated invocation, end to end. Runs the REAL
# script as a child process exactly as global-agent-policy.md mandates --
# `<shell> -NoProfile -ExecutionPolicy Bypass -File <helper> -Cwd <repo>
# -Name <slug>` -- against a SYNTHETIC repository, and requires that it
# exits 0, prints the created absolute path as its final stdout line, and
# leaves a real worktree registered on branch worktree-<slug> against that
# synthetic repository's git dir.
#
# Both shells are driven. powershell.exe is the one that carries the
# defect: against the pre-1d3cde4 helper this behavior goes red under
# powershell.exe and GREEN under pwsh, so a pwsh-only run would prove
# nothing. Both must be present -- a skip is how the divergence hid.
#
# See the header for how the live-root hazard is fenced. ---
function Test-MandatedInvocationCreatesWorktreeEndToEnd {
    if (-not (Test-Path -LiteralPath $helperScript -PathType Leaf)) {
        return @{ Passed = $false; Detail = "helper script not found at '$helperScript'. An unreadable script under test is a failure, not a skip." }
    }

    # The helper honours AGENTHUB_WORKTREE_ROOT but then hard-rejects any
    # resolved root but C:\wt. A different value is a broken configuration,
    # not an excuse to skip.
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_WORKTREE_ROOT)) {
        $configuredRoot = [IO.Path]::GetFullPath([string]$env:AGENTHUB_WORKTREE_ROOT).TrimEnd('\')
        if ($configuredRoot -ne $script:LiveWorktreeRoot) {
            return @{ Passed = $false; Detail = "AGENTHUB_WORKTREE_ROOT is '$configuredRoot', but the helper accepts only '$($script:LiveWorktreeRoot)' and would refuse every invocation. That is a broken worktree configuration on this machine, reported as a failure rather than skipped." }
        }
    }

    # An unavailable worktree root FAILS. It never skips.
    if (-not (Test-Path -LiteralPath $script:LiveWorktreeRoot -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $script:LiveWorktreeRoot -Force | Out-Null
        } catch {
            return @{ Passed = $false; Detail = "the mandated worktree root '$($script:LiveWorktreeRoot)' does not exist and could not be created: $($_.Exception.Message). Reporting this as a failure rather than a skip: an unavailable prerequisite that reads as a pass is how a broken mandated path ships green." }
        }
    }

    # Residue from a previously interrupted run, scoped to this file's own
    # fixture path and nothing else in C:\wt.
    $preClean = Remove-TreeUnderLiveRoot -Path $script:FixtureRootPath
    if ($preClean) {
        return @{ Passed = $false; Detail = "residue from a previous interrupted run at '$($script:FixtureRootPath)' could not be cleared, so this run would build on an unknown state: $preClean" }
    }

    $shells = [ordered]@{}
    foreach ($shellName in @('pwsh', 'powershell')) {
        $path = Resolve-ShellPath -Name $shellName
        if (-not $path) {
            return @{ Passed = $false; Detail = "$shellName is not on PATH; the mandated invocation is powershell.exe and the defect is defined by the disagreement BETWEEN the two shells, so it cannot be verified in only one" }
        }
        $shells[$shellName] = $path
    }

    $scratchDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-worktree-e2e-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    # Named so the helper's repository-identity derivation lands the whole
    # run under C:\wt\agenthub-selftest-fixture.
    $synthetic = Join-Path $scratchDir $script:FixtureRepositorySlug
    $failure = $null
    try {
        New-SyntheticGitRepository -Path $synthetic
        $syntheticCommon = Invoke-NativeForTest -Exe 'git' -Arguments @(
            '-C', $synthetic, 'rev-parse', '--path-format=absolute', '--git-common-dir'
        )
        if ($syntheticCommon.ExitCode -ne 0) {
            return @{ Passed = $false; Detail = "could not read the synthetic repository's git common dir: $($syntheticCommon.Output)" }
        }
        $expectedCommonDir = @($syntheticCommon.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)[0]

        foreach ($shellName in $shells.Keys) {
            $slug = "selftest-e2e-$shellName"
            $expectedTarget = [IO.Path]::GetFullPath((Join-Path $script:FixtureRootPath $slug))
            $expectedBranchRef = "refs/heads/worktree-$slug"
            # Recorded BEFORE the invocation so the finally block cleans up
            # a partially created worktree too -- which is exactly what the
            # pre-fix helper can leave behind.
            $script:PlannedTargets.Add($expectedTarget)

            # The invocation global-agent-policy.md mandates, verbatim.
            $run = Invoke-NativeForTest -Exe $shells[$shellName] -Arguments @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $helperScript,
                '-Cwd', $synthetic, '-Name', $slug
            )

            if ($run.ExitCode -ne 0) {
                $native = if ($run.Output -match 'NativeCommandError') {
                    " The output carries a NativeCommandError, which is the 1d3cde4 defect: Windows PowerShell 5.1 turned git's ordinary stderr progress line into a terminating error while git itself succeeded."
                } else { '' }
                $failure = @{ Passed = $false; Detail = "the mandated invocation `"$($shells[$shellName]) -NoProfile -ExecutionPolicy Bypass -File $helperScript -Cwd <synthetic> -Name $slug`" exited $($run.ExitCode) instead of 0.$native Output: $($run.Output)" }
                break
            }

            $stdoutLines = @($run.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($stdoutLines.Count -eq 0) {
                $failure = @{ Passed = $false; Detail = "under $shellName the helper exited 0 but printed nothing; its contract is to print the created absolute path as the final stdout line" }
                break
            }
            $reportedPath = ([string]$stdoutLines[-1]).Trim()
            if (-not $reportedPath.Equals($expectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
                $failure = @{ Passed = $false; Detail = "under $shellName the helper's final stdout line was '$reportedPath'; expected the created path '$expectedTarget'. Output: $($run.Output)" }
                break
            }

            if (-not (Test-Path -LiteralPath $expectedTarget -PathType Container)) {
                $failure = @{ Passed = $false; Detail = "under $shellName the helper exited 0 and reported '$expectedTarget', but no directory exists there. Output: $($run.Output)" }
                break
            }

            # The created worktree must belong to the synthetic repository.
            # Both sides are asked of git so the two answers are normalized
            # identically -- comparing git's path text to ours would be
            # defeated by 8.3 short names in the scratch path.
            $targetCommon = Invoke-NativeForTest -Exe 'git' -Arguments @(
                '-C', $expectedTarget, 'rev-parse', '--path-format=absolute', '--git-common-dir'
            )
            if ($targetCommon.ExitCode -ne 0) {
                $failure = @{ Passed = $false; Detail = "under $shellName the created directory '$expectedTarget' is not a working git worktree: $($targetCommon.Output)" }
                break
            }
            $actualCommonDir = @($targetCommon.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)[0]
            if (-not ([string]$actualCommonDir).Trim().Equals(([string]$expectedCommonDir).Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                $failure = @{ Passed = $false; Detail = "under $shellName the created worktree's git common dir is '$actualCommonDir', not the synthetic repository's '$expectedCommonDir'" }
                break
            }

            $listed = Invoke-NativeForTest -Exe 'git' -Arguments @(
                '-C', $synthetic, 'worktree', 'list', '--porcelain'
            )
            if ($listed.ExitCode -ne 0) {
                $failure = @{ Passed = $false; Detail = "under $shellName, git worktree list failed in the synthetic repository: $($listed.Output)" }
                break
            }
            $registered = Get-WorktreeBranchMap -PorcelainLines $listed.Lines
            if (-not $registered.ContainsKey($expectedTarget)) {
                $failure = @{ Passed = $false; Detail = "under $shellName the directory '$expectedTarget' exists but git has no worktree registered at that path. Registered: $(($registered.Keys | Sort-Object) -join ', ')" }
                break
            }
            if ([string]$registered[$expectedTarget] -cne $expectedBranchRef) {
                $failure = @{ Passed = $false; Detail = "under $shellName the worktree at '$expectedTarget' is on '$($registered[$expectedTarget])', not the expected '$expectedBranchRef'" }
                break
            }
        }
    } catch {
        $failure = @{ Passed = $false; Detail = "the end-to-end run threw before completing: $($_.Exception.Message)" }
    } finally {
        # Cleanup ALWAYS runs, removes worktree and branch through git, and
        # VERIFIES both are gone. Findings are recorded rather than thrown
        # so a cleanup problem cannot be lost inside a finally block;
        # Behavior 4 reports them.
        $script:CleanupRan = $true
        foreach ($target in @($script:PlannedTargets)) {
            $slug = Split-Path -Leaf $target
            $branch = "worktree-$slug"
            if (Test-Path -LiteralPath $synthetic -PathType Container) {
                $null = Invoke-NativeForTest -Exe 'git' -Arguments @('-C', $synthetic, 'worktree', 'remove', '--force', $target)
                $null = Invoke-NativeForTest -Exe 'git' -Arguments @('-C', $synthetic, 'worktree', 'prune')
                $null = Invoke-NativeForTest -Exe 'git' -Arguments @('-C', $synthetic, 'branch', '-D', $branch)

                # VERIFY the branch is gone rather than assume it. exit 1
                # from show-ref --verify --quiet means "no such ref".
                $refCheck = Invoke-NativeForTest -Exe 'git' -Arguments @(
                    '-C', $synthetic, 'show-ref', '--verify', '--quiet', "refs/heads/$branch"
                )
                if ($refCheck.ExitCode -eq 0) {
                    $script:CleanupFindings.Add("branch 'refs/heads/$branch' still exists in the synthetic repository after 'git branch -D'")
                }

                $stillListed = Invoke-NativeForTest -Exe 'git' -Arguments @(
                    '-C', $synthetic, 'worktree', 'list', '--porcelain'
                )
                if ($stillListed.ExitCode -eq 0) {
                    $remaining = Get-WorktreeBranchMap -PorcelainLines $stillListed.Lines
                    if ($remaining.ContainsKey($target)) {
                        $script:CleanupFindings.Add("git still has a worktree registered at '$target' after 'git worktree remove --force' and 'git worktree prune'")
                    }
                }
            }

            # VERIFY the directory is gone; fall back to the fenced delete.
            if (Test-Path -LiteralPath $target) {
                $removal = Remove-TreeUnderLiveRoot -Path $target
                if ($removal) { $script:CleanupFindings.Add($removal) }
            }
        }

        $rootRemoval = Remove-TreeUnderLiveRoot -Path $script:FixtureRootPath
        if ($rootRemoval) { $script:CleanupFindings.Add($rootRemoval) }

        Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($failure) { return $failure }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: this file left the live worktree root exactly as it
# found it. Re-measures C:\wt independently instead of trusting the
# cleanup block's own report, and refuses to pass over nothing: if
# Behavior 3 never planned a target there is nothing whose removal could
# be verified, and saying so is the point. C:\wt\agenthub and everything
# else under the root are never inspected or touched. ---
function Test-LiveWorktreeRootLeftClean {
    if (-not $script:CleanupRan) {
        return @{ Passed = $false; Detail = 'the end-to-end behavior never reached its cleanup block, so nothing guarantees the live worktree root was restored' }
    }
    if ($script:PlannedTargets.Count -eq 0) {
        return @{ Passed = $false; Detail = "the end-to-end behavior planned ZERO worktree targets, so this verification would be passing over an empty set and proving nothing about cleanup" }
    }
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($finding in @($script:CleanupFindings)) { $problems.Add([string]$finding) }
    foreach ($target in @($script:PlannedTargets)) {
        if (Test-Path -LiteralPath $target) {
            $problems.Add("'$target' still exists under the live worktree root")
        }
    }
    if (Test-Path -LiteralPath $script:FixtureRootPath) {
        $problems.Add("this test's fixture root '$($script:FixtureRootPath)' still exists")
    }
    if ($problems.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($problems.Count) cleanup problem(s) across $($script:PlannedTargets.Count) planned target(s); the live worktree root must not accumulate stale registrations:`n    " + (($problems) -join "`n    ") }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 5: the deletion fence, watched refusing. Every removal
# under C:\wt in this file goes through Remove-TreeUnderLiveRoot, and a
# guard nobody has seen refuse anything is not evidence -- the standard
# tests/Test-FileEncodingDiscipline.ps1 sets for its own detector.
#
# Proven against a synthetic fixture in scratch with the fixture root
# temporarily redirected there, so the fence is exercised WITHOUT ever
# pointing a possibly-broken delete at C:\wt. Passing a real path such as
# C:\wt\agenthub to a guard whose whole purpose is doubted would destroy
# human worktrees on the run where the guard is broken, which is the one
# run that matters.
#
# The junction case is not hypothetical: seven junctions point into this
# repository's packages/ tree, and Remove-Item -Recurse has historically
# deleted THROUGH a junction rather than removing the link, so a recursive
# delete that met one would destroy tracked source. ---
function Test-DeletionFenceRefusesOutsideFixtureRootAndThroughJunctions {
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-worktree-fence-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $previousFixtureRoot = $script:FixtureRootPath
    $junction = Join-Path $dir 'fixture-root\worktree\link-into-protected'
    try {
        $script:FixtureRootPath = Join-Path $dir 'fixture-root'
        $worktree = Join-Path $dir 'fixture-root\worktree'
        $protected = Join-Path $dir 'protected'
        $canary = Join-Path $protected 'must-survive.txt'
        New-Item -ItemType Directory -Path $worktree -Force | Out-Null
        New-Item -ItemType Directory -Path $protected -Force | Out-Null
        [IO.File]::WriteAllText($canary, 'tracked source stand-in', [Text.UTF8Encoding]::new($false))

        # (a) containment. Paths outside the fixture root must be refused,
        # untouched. Deliberately harmless stand-ins in scratch, never the
        # live paths they stand for.
        $outsidePaths = @($protected, $dir, (Join-Path $dir 'fixture-root-sibling'))
        if ($outsidePaths.Count -eq 0) {
            return @{ Passed = $false; Detail = 'the containment case iterates an empty path set and would prove nothing' }
        }
        foreach ($outside in $outsidePaths) {
            $refusal = Remove-TreeUnderLiveRoot -Path $outside
            if (-not $refusal) {
                return @{ Passed = $false; Detail = "the deletion fence did NOT refuse '$outside', which lies outside the fixture root '$($script:FixtureRootPath)'. Unfenced, this is what would let a run delete C:\wt\agenthub." }
            }
            if ($refusal -notmatch 'outside this test') {
                return @{ Passed = $false; Detail = "the fence refused '$outside' but not as a containment refusal; it said: $refusal" }
            }
        }
        if (-not (Test-Path -LiteralPath $canary -PathType Leaf)) {
            return @{ Passed = $false; Detail = "the containment refusals still removed '$canary'" }
        }

        # (b) reparse points. A tree containing a junction must be refused
        # whole, and the junction's TARGET must survive untouched.
        try {
            New-Item -ItemType Junction -Path $junction -Value $protected -ErrorAction Stop | Out-Null
        } catch {
            return @{ Passed = $false; Detail = "could not create a junction fixture at '$junction': $($_.Exception.Message). This behavior cannot be verified without one, so it fails rather than passing over an untested guard." }
        }
        if (@(Get-ReparsePointPath -Path $worktree).Count -eq 0) {
            return @{ Passed = $false; Detail = "the junction fixture at '$junction' was created but Get-ReparsePointPath found no reparse point under '$worktree', so the refusal below would prove nothing" }
        }
        $junctionRefusal = Remove-TreeUnderLiveRoot -Path $worktree
        if (-not $junctionRefusal) {
            return @{ Passed = $false; Detail = "the deletion fence recursively deleted '$worktree' even though it contained the junction '$junction'; Remove-Item -Recurse can delete THROUGH a junction, so this is how a run would destroy the packages/ tree the host junctions point at" }
        }
        if ($junctionRefusal -notmatch 'reparse point') {
            return @{ Passed = $false; Detail = "the fence refused '$worktree' but not as a reparse-point refusal; it said: $junctionRefusal" }
        }
        if (-not (Test-Path -LiteralPath $canary -PathType Leaf)) {
            return @{ Passed = $false; Detail = "the junction's target file '$canary' was destroyed despite the refusal" }
        }
        if (-not (Test-Path -LiteralPath $worktree -PathType Container)) {
            return @{ Passed = $false; Detail = "the fence reported a refusal for '$worktree' but removed it anyway" }
        }

        # (c) and it still deletes what it is meant to, once the junction is
        # gone -- a fence that refuses everything would pass (a) and (b) and
        # be useless.
        Remove-Item -LiteralPath $junction -Force -Recurse -ErrorAction SilentlyContinue
        $allowed = Remove-TreeUnderLiveRoot -Path $worktree
        if ($allowed) {
            return @{ Passed = $false; Detail = "with no junction present the fence still refused to delete '$worktree', so it would never clean up after itself: $allowed" }
        }
        if (Test-Path -LiteralPath $worktree) {
            return @{ Passed = $false; Detail = "the fence reported success but '$worktree' still exists" }
        }
        if (-not (Test-Path -LiteralPath $canary -PathType Leaf)) {
            return @{ Passed = $false; Detail = "deleting '$worktree' also destroyed the junction target's file '$canary'" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        $script:FixtureRootPath = $previousFixtureRoot
        # Remove the junction LINK before the recursive cleanup below, so
        # this file's own teardown cannot delete through it.
        Remove-Item -LiteralPath $junction -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-ShippedHelperPremiseHolds
Report 'the shipped helper defines exactly one Invoke-AgentHubGit and still sets $ErrorActionPreference = ''Stop'' at top level' $r1.Passed $r1.Detail

$r2 = Test-ShippedGitWrapperSurvivesStderrProgressInBothShells
Report 'the shipped Invoke-AgentHubGit survives a succeeding git command''s stderr progress line in BOTH shells, including the powershell.exe invocation the policy mandates' $r2.Passed $r2.Detail

$r3 = Test-MandatedInvocationCreatesWorktreeEndToEnd
Report 'the mandated powershell.exe -NoProfile -ExecutionPolicy Bypass -File invocation runs the real script end to end and creates a registered worktree on the expected branch' $r3.Passed $r3.Detail

$r4 = Test-LiveWorktreeRootLeftClean
Report 'the end-to-end run removed every worktree and branch it created and left the live worktree root clean, verified rather than assumed' $r4.Passed $r4.Detail

$r5 = Test-DeletionFenceRefusesOutsideFixtureRootAndThroughJunctions
Report 'the deletion fence refuses a path outside its own fixture root and refuses a tree containing a junction, leaving the junction target intact, while still deleting what it should' $r5.Passed $r5.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
