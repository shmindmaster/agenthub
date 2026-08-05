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
                        exit=1, no worktree created
    pwsh 7          ->  C:\wt\<repo>\<slug>, exit=0

PowerShell 7 surfaces the same stderr records as strings and does not
throw, which is why the defect was invisible to anyone testing in 7. The
mandated invocation was the broken one.

The fix restores $ErrorActionPreference to 'Continue' around the native
call only, exactly as tests/Run-AllTests.ps1 already does when it shells
out. $LASTEXITCODE still drives the failure branch, so no error handling
is traded away for it.

WHAT THIS FILE TESTS, AND WHAT IT DELIBERATELY DOES NOT
It extracts the SHIPPED Invoke-AgentHubGit from
scripts/New-AgentHubWorktree.ps1 by AST and runs that exact function text
in both shells -- so this tests the shipped code rather than a hand-copied
stand-in that could drift from it.

It does NOT drive the helper end to end. Get-AgentHubWorktreeTarget hard-
rejects any root but C:\wt, so an end-to-end assertion would have to
create and delete a real worktree under the live, policy-significant
worktree root on every test run, in both shells. A run interrupted between
those two steps would leave exactly the stale-registration mess that root
must not accumulate. The end-to-end invocation was instead verified by
hand, once, against the real repository and cleaned up (see the task
report); what is automated here is the single function that carried the
defect. That is a narrower claim than "the helper works", and is stated
narrowly on purpose.

The stderr-producing command used below is `git checkout -b` rather than
`git worktree add`, because it exhibits the same class -- ordinary
progress on stderr, exit 0 -- inside a throwaway repository in scratch,
without creating a worktree anywhere. Each behavior asserts the progress
line was actually captured, so the test cannot pass by exercising nothing
if git ever stops emitting it.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this
file follows). Same self-checking idiom: each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

This file writes nothing outside $env:AGENTHUB_TEST_SCRATCH.

Run: pwsh -NoProfile -File tests/Test-WorktreeHelper.ps1
     powershell.exe -NoProfile -File tests/Test-WorktreeHelper.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$helperScript = Join-Path $repoRoot 'scripts\New-AgentHubWorktree.ps1'

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
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
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

# --- Behavior 1: the premise this file's probe rests on. Exactly one
# Invoke-AgentHubGit exists in the shipped helper, and the helper really
# does set $ErrorActionPreference = 'Stop' at its own top level. If either
# stops being true the probe below would be reproducing a context the
# helper no longer has, and would prove nothing -- so that is a failure
# here rather than a silent change of meaning downstream. ---
function Test-ShippedHelperPremiseHolds {
    if (-not (Test-Path -LiteralPath $helperScript -PathType Leaf)) {
        return @{ Passed = $false; Detail = "scripts/New-AgentHubWorktree.ps1 not found at $helperScript" }
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

# --- Behavior 2: the regression itself. The shipped Invoke-AgentHubGit,
# run under $ErrorActionPreference = 'Stop' exactly as the helper runs it,
# survives a git command that writes an ordinary progress line to stderr
# and exits 0 -- in BOTH shells. powershell.exe is the shell the policy
# mandates for this helper, so a failure there is a failure of the
# mandated path, not an edge case. Both shells must be present: a skip is
# how a shell-divergent defect stays invisible. ---
function Test-ShippedGitWrapperSurvivesStderrProgressInBothShells {
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

$r1 = Test-ShippedHelperPremiseHolds
Report 'the shipped helper defines exactly one Invoke-AgentHubGit and still sets $ErrorActionPreference = ''Stop'' at top level' $r1.Passed $r1.Detail

$r2 = Test-ShippedGitWrapperSurvivesStderrProgressInBothShells
Report 'the shipped Invoke-AgentHubGit survives a succeeding git command''s stderr progress line in BOTH shells, including the powershell.exe invocation the policy mandates' $r2.Passed $r2.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
