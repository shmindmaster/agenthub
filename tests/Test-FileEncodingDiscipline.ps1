#Requires -Version 5.1
<#
Behavior tests for the shell-dependent text-decoding defect.

THE DEFECT
Windows PowerShell 5.1 decodes a BOM-less file as the ANSI code page
(Windows-1252 here); PowerShell 7 decodes it as UTF-8. So
`Get-Content -Raw` WITHOUT `-Encoding UTF8` returns a DIFFERENT STRING in
the two shells for any file holding a non-ASCII byte. Measured on this
worktree, packages/framer/skills/framer/SKILL.md:

    pwsh 7.6.4     no-flag len 11429, -Encoding UTF8 len 11429, identical
    5.1.26100      no-flag len 11433, -Encoding UTF8 len 11429, NOT identical

About 95 tracked files carry non-ASCII bytes -- most packages/*/skills/*/
SKILL.md, many references/*.md, packages/clerk/skills/clerk-orgs/evals/
evals.json, and scripts/Sync-AgentHub.ps1 itself. So this is live, not
latent. It is the repo's signature defect class: nothing fails, the work
proceeds, and the result is silently wrong -- here, wrong for one person
and right for the other, which is worse than wrong for everyone.

`-Encoding UTF8` on Get-Content is the established fix in this repo
(tests/Test-HostSurfaces.ps1, tests/Test-CapabilityRouting.ps1 already use
it). Verified empirically in BOTH shells before relying on it:
  - `-Encoding UTF8` returns exactly what [IO.File]::ReadAllText returns,
    in 5.1 and in 7 (`-ceq` true in both).
  - `-Encoding UTF8` in 5.1 does NOT leave a U+FEFF on the front of a
    BOM'd file -- it strips it (first char was U+006E, not U+FEFF, against
    a file whose first three bytes on disk were 239,187,191).

WRITES ARE THE MIRROR IMAGE, in two shapes. `Set-Content -Encoding UTF8`
writes a BOM in 5.1 and no BOM in 7 -- three bytes. A write specifying NO
`-Encoding` at all is worse: 5.1 writes the ANSI code page and 7 writes
UTF-8 with no BOM, so EVERY non-ASCII character differs. Behavior 5 covers
scripts/ for both; see its comment.

WHAT THIS SCANNER CAN AND CANNOT SEE
It parses each .ps1 with the real PowerShell parser
([Management.Automation.Language.Parser]::ParseInput) and walks CommandAst
nodes, rather than matching text. That is what makes it immune, by
construction rather than by pattern cleverness, to all four ways a text
scanner gets defeated here (all four are exercised against a synthetic
fixture in Behavior 4, so this claim is proven, not asserted):
  - a `#` comment mentioning Get-Content -- comments are not AST commands
  - a here-string containing Get-Content -- string bodies are not commands
  - a backtick line continuation splitting a call -- the parser joins it
  - a literal `.` in a path token (registry\fleet-profile.json) -- there
    is no regex whose dot could over-match
It also resolves abbreviated parameter names (`-Enc UTF8` counts, because
PowerShell itself accepts it) and the alias forms gc/cat/type.

It CANNOT see, and does not claim to:
  - commands built as text and run through Invoke-Expression or a
    scriptblock created from a string (this repo has none in scope)
  - reads inside non-.ps1 files -- packages/product-demo-studio's .mjs
    tooling is Node, which always decodes UTF-8, so it does not have this
    defect
  - .NET reads ([IO.File]::ReadAllText / ReadAllBytes). Those are already
    shell-agnostic: .NET decodes UTF-8 on both Framework and Core, proven
    by the `-ceq` measurement above. They are correct, not exempted.
  - whether a path a script reads is actually a repo file rather than a
    host file. It flags every unencoded read, which is the safe direction:
    host configs (Grok/Hermes) were the worst instances found.

Not a Pester suite: this repo carries no Pester dependency (see
tests/Test-RegistryContentHash.ps1 and siblings for the prior art this
file follows). Same self-checking idiom: each Test-* function returns a
result, the runner prints one PASS/FAIL line per behavior, accumulates
failures, and exits 1 if any behavior did not hold, 0 otherwise.

This file reads only; it writes nothing outside $env:AGENTHUB_TEST_SCRATCH.

Run: pwsh -NoProfile -File tests/Test-FileEncodingDiscipline.ps1
     powershell.exe -NoProfile -File tests/Test-FileEncodingDiscipline.ps1
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

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

# Read cmdlets whose decoding depends on the shell when -Encoding is absent,
# with the aliases PowerShell resolves to them.
$script:ReadCommandNames = @('Get-Content', 'gc', 'cat', 'type')
# Write cmdlets whose byte output depends on the shell under -Encoding UTF8.
$script:WriteCommandNames = @('Set-Content', 'Add-Content', 'Out-File', 'sc', 'ac')

# Encoding argument values that decode/encode identically in 5.1 and 7.
# UTF8       -- reading: identical in both, BOM stripped in both (measured).
# UTF8NoBOM / UTF8BOM -- unambiguous, but PowerShell 7 only; a script using
#                        them would break under 5.1. Accepted for reads
#                        because they are still unambiguous UTF-8 there.
# Byte       -- not a text decode at all, so no code page is involved.
$script:Utf8EncodingValues = @('UTF8', 'UTF8NoBOM', 'UTF8BOM', 'utf8NoBOM', 'Byte')

# ---------------------------------------------------------------------------
# AST helpers
# ---------------------------------------------------------------------------

# The source text is read with [IO.File]::ReadAllText, which decodes UTF-8 the
# same way in both shells (measured). Parsing text we decoded ourselves --
# rather than Parser::ParseFile, which applies its own host-dependent
# detection -- keeps this scanner from having the very defect it polices.
function Get-CommandAstList {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "cannot parse $Path as PowerShell: $($errors[0].Message)"
    }
    return @($ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.CommandAst] },
        $true
    ))
}

# Returns the argument text of -Encoding on this command, or $null when the
# parameter is absent. Handles both `-Encoding UTF8` (value is the following
# element) and `-Encoding:UTF8` (value is attached to the parameter). Accepts
# any unambiguous abbreviation of the parameter name, because PowerShell
# binds `-Enc UTF8` just as happily as the full name.
function Get-EncodingArgument {
    param($CommandAst)
    $elements = @($CommandAst.CommandElements)
    for ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        $name = [string]$element.ParameterName
        if ($name.Length -eq 0) { continue }
        if (-not 'Encoding'.StartsWith($name, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($null -ne $element.Argument) { return [string]$element.Argument.Extent.Text }
        if ($i + 1 -lt $elements.Count) { return [string]$elements[$i + 1].Extent.Text }
        return ''
    }
    return $null
}

function Test-IsUtf8EncodingArgument {
    param([string]$Value)
    if ($null -eq $Value) { return $false }
    $trimmed = $Value.Trim().Trim("'", '"')
    return @($script:Utf8EncodingValues | Where-Object { $_ -eq $trimmed }).Count -gt 0
}

function Test-CommandHasSwitch {
    param($CommandAst, [string]$SwitchName)
    foreach ($element in @($CommandAst.CommandElements)) {
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        $name = [string]$element.ParameterName
        if ($name.Length -gt 0 -and $SwitchName.StartsWith($name, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function New-EncodingViolation {
    param([string]$Path, $CommandAst, [string]$RootForRelativePath)
    $relative = $Path
    if ($RootForRelativePath -and $Path.StartsWith($RootForRelativePath, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $Path.Substring($RootForRelativePath.Length).TrimStart('\', '/')
    }
    $line = $CommandAst.Extent.StartLineNumber
    $snippet = ($CommandAst.Extent.Text -replace '\s+', ' ').Trim()
    if ($snippet.Length -gt 110) { $snippet = $snippet.Substring(0, 110) + '...' }
    return "${relative}:${line}: $snippet"
}

# Get-UnencodedFileRead: pure, reusable check. Given .ps1 paths, returns one
# "relative\path.ps1:LINE: snippet" string per read that would decode
# differently in the two shells.
function Get-UnencodedFileRead {
    param([string[]]$Path, [string]$RootForRelativePath)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($file in @($Path)) {
        foreach ($command in (Get-CommandAstList -Path $file)) {
            $name = [string]$command.GetCommandName()
            if ([string]::IsNullOrEmpty($name)) { continue }
            if (@($script:ReadCommandNames | Where-Object { $_ -eq $name }).Count -eq 0) { continue }
            # A byte-stream read never decodes text, so no code page applies.
            if (Test-CommandHasSwitch -CommandAst $command -SwitchName 'AsByteStream') { continue }
            $encoding = Get-EncodingArgument -CommandAst $command
            if (Test-IsUtf8EncodingArgument -Value $encoding) { continue }
            $violations.Add((New-EncodingViolation -Path $file -CommandAst $command -RootForRelativePath $RootForRelativePath))
        }
    }
    return $violations
}

# Get-ShellDivergentWrite: same walk, for writes. TWO shapes diverge, and
# they are not the same defect:
#
#   -Encoding UTF8  -- 5.1 emits a BOM, 7 does not (measured: bytes
#                      239,187,191,104,101,108,108,111 vs
#                      104,101,108,108,111 for the same input). Three
#                      bytes, at the front, once per file.
#   NO -Encoding    -- 5.1 writes the ANSI code page (Windows-1252 here),
#                      7 writes UTF-8 with no BOM. EVERY non-ASCII
#                      character in the file differs. This is the worse
#                      of the two and was the one going unreported: the
#                      previous form did `if ($null -eq $encoding)
#                      { continue }`, so a write specifying no encoding at
#                      all was treated as compliant.
#
# The two are reported with different explanations, appended after
# ' --> ', because they want different fixes and a message that conflates
# them cannot be acted on. The ' --> ' suffix sits after the snippet, so
# the 'relative\path.ps1:LINE' allowlist key is unaffected.
$script:WriteReasonNoEncoding = 'no -Encoding at all: 5.1 writes the ANSI code page, 7 writes UTF-8 without a BOM, so EVERY non-ASCII character differs between shells. Fix: [IO.File]::WriteAllText / Write-Utf8NoBom.'
$script:WriteReasonUtf8Bom = 'writes -Encoding UTF8: 5.1 prepends a 3-byte BOM, 7 does not. Fix: [IO.File]::WriteAllText / Write-Utf8NoBom.'
function Get-ShellDivergentWrite {
    param([string[]]$Path, [string]$RootForRelativePath)
    $violations = [Collections.Generic.List[string]]::new()
    foreach ($file in @($Path)) {
        foreach ($command in (Get-CommandAstList -Path $file)) {
            $name = [string]$command.GetCommandName()
            if ([string]::IsNullOrEmpty($name)) { continue }
            if (@($script:WriteCommandNames | Where-Object { $_ -eq $name }).Count -eq 0) { continue }
            # A byte-stream write never encodes text, so no code page applies.
            if (Test-CommandHasSwitch -CommandAst $command -SwitchName 'AsByteStream') { continue }
            $encoding = Get-EncodingArgument -CommandAst $command
            $reason = $null
            if ($null -eq $encoding) {
                $reason = $script:WriteReasonNoEncoding
            } else {
                $trimmed = $encoding.Trim().Trim("'", '"')
                if ($trimmed -eq 'UTF8') { $reason = $script:WriteReasonUtf8Bom }
            }
            if ($null -eq $reason) { continue }
            $violations.Add((New-EncodingViolation -Path $file -CommandAst $command -RootForRelativePath $RootForRelativePath) + " --> $reason")
        }
    }
    return $violations
}

# ---------------------------------------------------------------------------
# Scan target discovery
# ---------------------------------------------------------------------------

# git is the source of truth for "tracked". Windows PowerShell 5.1 turns a
# native command's stderr into a TERMINATING error under
# $ErrorActionPreference = 'Stop' even when the command succeeded, so the
# preference is restored around the native call only -- same defect and
# same guard as scripts/New-AgentHubWorktree.ps1's Invoke-AgentHubGit and
# tests/Run-AllTests.ps1. $LASTEXITCODE still decides success.
function Invoke-GitForScan {
    param([string]$Root, [string[]]$Arguments)
    $allArgs = @('-C', $Root) + @($Arguments)
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @allArgs 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

# EVERY tracked .ps1 in the repository, derived from `git ls-files`.
#
# This used to be a hand-maintained directory list -- scripts/, tests/,
# packages/*/tests/ -- which is the same blind-spot defect this file
# exists to police, one level up: a guard whose reach is enumerated by
# hand cannot see the directory nobody remembered to enumerate. It did not
# see packages/local-ai/skills/local-ai-stack/validate-local-ai-stack.ps1,
# a tracked, shipped validator that was carrying two live unencoded reads
# the whole time the guard reported success. Deriving the list from git
# means a new directory is covered the day it appears rather than the day
# someone remembers it.
#
# `git ls-files` rather than `Get-ChildItem -Recurse`: untracked scratch,
# ignored build output, and the host deployment junctions that point into
# packages/ are not repository source and must not be walked. A non-zero
# git exit, or a tracked path missing from disk, is a hard failure -- a
# scanner that quietly resolves to nothing and prints PASS is the exact
# defect this file exists to close, so it must never degrade to an empty
# set silently. Every caller also checks the returned count.
function Get-EncodingScanTarget {
    param([string]$Root)
    $result = Invoke-GitForScan -Root $Root -Arguments @('ls-files', '--cached', '--', '*.ps1')
    if ($result.ExitCode -ne 0) {
        throw "git ls-files failed under '$Root' (exit $($result.ExitCode)): $(@($result.Output) -join ' | '). This scanner derives its file list from git, so it fails loudly rather than scanning nothing."
    }
    $files = [Collections.Generic.List[string]]::new()
    foreach ($relative in @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $full = [IO.Path]::GetFullPath((Join-Path $Root ($relative -replace '/', '\')))
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "git reports '$relative' as tracked under '$Root' but it is not on disk; refusing to scan a set that does not match the working tree."
        }
        $files.Add($full)
    }
    return $files
}

# --- Behavior 1: the detector itself flags an unencoded read and clears an
# encoded one, proven against a synthetic fixture, never the real tree. A
# scanner nobody has watched catch anything is not evidence. ---
function Test-DetectorFlagsUnencodedRead {
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-encoding-detector-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $bad = @(
            '$a = Get-Content -LiteralPath $p -Raw'
            '$b = Get-Content $p -Raw -Encoding UTF8'
        ) -join "`r`n"
        [IO.File]::WriteAllText((Join-Path $dir 'Bad.ps1'), $bad, [Text.UTF8Encoding]::new($false))
        $good = '$c = Get-Content -LiteralPath $p -Raw -Encoding UTF8'
        [IO.File]::WriteAllText((Join-Path $dir 'Good.ps1'), $good, [Text.UTF8Encoding]::new($false))

        $violations = @(Get-UnencodedFileRead -Path @(
            (Join-Path $dir 'Bad.ps1'), (Join-Path $dir 'Good.ps1')
        ) -RootForRelativePath $dir)
        if ($violations.Count -ne 1) {
            return @{ Passed = $false; Detail = "expected exactly 1 violation, got $($violations.Count): $($violations -join ' | ')" }
        }
        if ($violations[0] -notlike 'Bad.ps1:1:*') {
            return @{ Passed = $false; Detail = "expected the violation to name Bad.ps1 line 1, got '$($violations[0])'" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2: the scan target set is non-empty and reaches every
# tracked .ps1, including the shapes the old hand-maintained directory
# list could not see. Without this, every sweep below could pass by
# iterating nothing, or by iterating only the directories someone
# remembered. ---
function Test-ScanTargetSetCoversEveryTrackedScript {
    $targets = @(Get-EncodingScanTarget -Root $repoRoot)
    if ($targets.Count -eq 0) {
        return @{ Passed = $false; Detail = "scan target discovery yielded ZERO .ps1 files under $repoRoot -- a scanner that iterates nothing and reports success is the defect this file exists to prevent" }
    }
    $expectations = [ordered]@{
        'scripts\'  = 'scripts/'
        '\tests\'   = 'tests/ or packages/*/tests/'
        'packages\' = 'packages/'
    }
    foreach ($fragment in $expectations.Keys) {
        $hits = @($targets | Where-Object { $_ -like "*$fragment*" })
        if ($hits.Count -eq 0) {
            return @{ Passed = $false; Detail = "scan target set reached no file matching '$fragment' ($($expectations[$fragment])); found $($targets.Count) file(s) overall" }
        }
    }

    # The shape the old directory list could NOT reach: a tracked .ps1
    # under packages/ that is not inside a tests/ directory. That is where
    # validate-local-ai-stack.ps1 lives, and its two unencoded reads sat
    # there unseen while this file reported success. Derived from the
    # target set rather than naming that file, so it keeps holding as the
    # tree changes -- but it does require such a file to exist, and says
    # so loudly if one stops existing, because then this assertion would
    # be proving nothing.
    $packagesPrefix = [IO.Path]::GetFullPath((Join-Path $repoRoot 'packages')) + '\'
    $outsideTests = @($targets | Where-Object {
        $_.StartsWith($packagesPrefix, [StringComparison]::OrdinalIgnoreCase) -and $_ -notlike '*\tests\*'
    })
    if ($outsideTests.Count -eq 0) {
        return @{ Passed = $false; Detail = "the scan target set contains no tracked .ps1 under packages/ outside a tests/ directory. Either discovery has regressed to the old scripts//tests//packages/*/tests/ directory list, or the repository no longer holds such a file -- in which case this assertion proves nothing and must be revisited rather than left green." }
    }

    # Proves discovery really consults git rather than carrying a
    # directory list: a synthetic repository holding one tracked .ps1 at
    # depth, one UNTRACKED .ps1, and one tracked non-.ps1 must yield
    # exactly the tracked script at depth.
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-encoding-scanroot-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        New-Item -ItemType Directory -Path (Join-Path $dir 'deep\nested\dir') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'deep\nested\dir\Tracked.ps1'), "'x'`r`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $dir 'Untracked.ps1'), "'x'`r`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $dir 'notes.txt'), "x`r`n", [Text.UTF8Encoding]::new($false))
        foreach ($step in @(
            @('init', '-q', '-b', 'main', '.'),
            @('add', 'deep/nested/dir/Tracked.ps1', 'notes.txt')
        )) {
            $setup = Invoke-GitForScan -Root $dir -Arguments $step
            if ($setup.ExitCode -ne 0) {
                return @{ Passed = $false; Detail = "synthetic repository setup 'git $($step -join ' ')' failed: $(@($setup.Output) -join ' | ')" }
            }
        }
        $synthetic = @(Get-EncodingScanTarget -Root $dir)
        $expected = [IO.Path]::GetFullPath((Join-Path $dir 'deep\nested\dir\Tracked.ps1'))
        if ($synthetic.Count -ne 1 -or $synthetic[0] -cne $expected) {
            return @{ Passed = $false; Detail = "against a synthetic repository holding one tracked .ps1 at depth, one untracked .ps1, and one tracked .txt, discovery returned $($synthetic.Count) target(s) [$($synthetic -join ', ')]; expected exactly [$expected]. It is not reflecting the tracked set it was pointed at." }
        }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 3: the live sweep. No tracked .ps1 anywhere in the
# repository reads a file without explicit UTF-8 decoding.
#
# ALLOWLIST: empty, deliberately. Every read in scope either needs UTF-8
# decoding or is already a byte read, so there is nothing here that
# legitimately needs no flag. The allowlist stays as named, commented
# entries -- never a loosened pattern -- so that adding one is a visible,
# justified act rather than a quiet widening that also lets real defects
# through. Format: 'relative\path.ps1:LINE' with a comment giving the
# reason the read is encoding-independent. ---
$script:ReadAllowlist = @(
    # (empty -- see comment above)
)
function Test-NoUnencodedReadInScope {
    $targets = @(Get-EncodingScanTarget -Root $repoRoot)
    if ($targets.Count -eq 0) {
        return @{ Passed = $false; Detail = "scan target discovery yielded ZERO .ps1 files under $repoRoot; refusing to report success on an empty sweep" }
    }
    $violations = @(Get-UnencodedFileRead -Path $targets -RootForRelativePath $repoRoot)
    $unexpected = @($violations | Where-Object {
        $key = ($_ -split ': ', 2)[0]
        $script:ReadAllowlist -notcontains $key
    })
    if ($unexpected.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($unexpected.Count) read(s) across $($targets.Count) scanned file(s) decode differently in Windows PowerShell 5.1 and PowerShell 7:`n    " + ($unexpected -join "`n    ") }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 4: the four documented evasions. A text scanner would report
# 3 false positives and miss the 1 real violation on this fixture; the AST
# walk must report exactly the real one. ---
function Test-DetectorIsNotFooledByCommentsHereStringsOrContinuations {
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-encoding-evasion-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $lines = [Collections.Generic.List[string]]::new()
        # (a) a comment mentioning the pattern -- must NOT be flagged
        $lines.Add('# Get-Content -LiteralPath $p -Raw is what the old code did.')
        # (b) a here-string containing the pattern -- must NOT be flagged
        $lines.Add('$doc = @"')
        $lines.Add('Get-Content -LiteralPath $p -Raw')
        $lines.Add('"@')
        # (c) a literal dot in a path token on a COMPLIANT call -- must NOT be flagged
        $lines.Add('$ok = Get-Content -LiteralPath (Join-Path $r ''registry\fleet-profile.json'') -Raw -Encoding UTF8')
        # (d) a real violation split by a backtick line continuation -- MUST be flagged
        $lines.Add('$bad = Get-Content -LiteralPath $p `')
        $lines.Add('    -Raw')
        $fixture = Join-Path $dir 'Evasions.ps1'
        [IO.File]::WriteAllText($fixture, (($lines -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))

        $violations = @(Get-UnencodedFileRead -Path @($fixture) -RootForRelativePath $dir)
        if ($violations.Count -ne 1) {
            return @{ Passed = $false; Detail = "expected exactly 1 violation (the continued call on line 6), got $($violations.Count): $($violations -join ' | ')" }
        }
        if ($violations[0] -notlike 'Evasions.ps1:6:*') {
            return @{ Passed = $false; Detail = "expected the violation to name line 6 (the backtick-continued read), got '$($violations[0])'" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: no script in scripts/ writes a persistent file through
# either divergent shape -- `Set-Content -Encoding UTF8` (BOM under 5.1
# only) or a write specifying NO -Encoding at all (ANSI under 5.1, UTF-8
# under 7, so every non-ASCII character differs). Those scripts write REAL
# fleet artifacts -- host plugin manifests, the drift report, the sync
# state file -- so either difference survives the run. Sync-AgentHub.ps1
# already carries the fix as Write-Utf8NoBom ([IO.File]::WriteAllText with
# UTF8Encoding($false)); this makes using it non-optional.
#
# STATED HONESTLY: scripts/ currently contains ZERO write-cmdlet calls of
# any kind -- the only textual matches are three comments, which the AST
# walk correctly ignores. So this sweep is preventive: it iterates a
# proven non-empty set of files and finds no violations because there are
# no such calls, not because it cannot see them. What proves the detector
# can see them is Behavior 5a, against a fixture.
#
# SCOPE NOTE, stated honestly: tests/ and packages/*/tests/ still contain
# ~55 `Set-Content -Encoding UTF8` calls and are NOT swept here. Every one
# of them writes a fixture into a per-test scratch directory that the same
# shell process then hands to a child of that same shell
# ($hostExe = (Get-Process -Id $PID).Path), and deletes in its finally
# block. A BOM written and read back by one shell is self-consistent --
# 5.1's Get-Content detects and honours a BOM, and -Encoding UTF8 strips
# it in both shells -- so those writes cannot change a verdict. They are
# left alone deliberately rather than churned. ---
$script:WriteAllowlist = @(
    # (empty -- see comment above)
)

# --- Behavior 5a: the write detector itself, proven against a synthetic
# fixture. It must flag BOTH divergent shapes and must not describe them
# the same way, because they diverge for different reasons and want
# different fixes -- and it must clear a byte write, which involves no
# code page at all. ---
function Test-WriteDetectorDistinguishesNoEncodingFromUtf8 {
    $dir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-encoding-writedetector-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $lines = @(
            '''text'' | Set-Content -LiteralPath $q'                        # 1 no -Encoding
            '''text'' | Set-Content -LiteralPath $q2 -Encoding UTF8'        # 2 BOM divergence
            'Out-File -FilePath $q3'                                        # 3 no -Encoding
            'Add-Content -LiteralPath $q4 -Value ''text'''                  # 4 no -Encoding
            'Set-Content -LiteralPath $q5 -Value ''x'' -Encoding Byte'      # 5 clear
            'Set-Content -LiteralPath $q6 -Value ''x'' -AsByteStream'       # 6 clear
            '[IO.File]::WriteAllText($q7, ''x'')'                           # 7 clear
        )
        $fixture = Join-Path $dir 'Writes.ps1'
        [IO.File]::WriteAllText($fixture, (($lines -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))

        $violations = @(Get-ShellDivergentWrite -Path @($fixture) -RootForRelativePath $dir)
        $flaggedLines = @($violations | ForEach-Object { ($_ -split ':')[1] }) -join ','
        if ($flaggedLines -ne '1,2,3,4') {
            return @{ Passed = $false; Detail = "expected the detector to flag exactly lines 1,2,3,4 (three no-Encoding writes and one -Encoding UTF8 write) and to clear the byte writes and the .NET write; it flagged [$flaggedLines]: $($violations -join ' | ')" }
        }

        $noEncoding = @($violations | Where-Object { $_ -match 'no -Encoding at all' })
        $utf8Bom = @($violations | Where-Object { $_ -match 'BOM' -and $_ -notmatch 'no -Encoding at all' })
        if ($noEncoding.Count -ne 3) {
            return @{ Passed = $false; Detail = "expected 3 violations reported as no-Encoding writes, got $($noEncoding.Count): $($violations -join ' | ')" }
        }
        if ($utf8Bom.Count -ne 1) {
            return @{ Passed = $false; Detail = "expected 1 violation reported as an -Encoding UTF8 BOM divergence, got $($utf8Bom.Count): $($violations -join ' | ')" }
        }
        # The two shapes must not be described identically: a no-Encoding
        # write diverges by every non-ASCII character, an -Encoding UTF8
        # write by three BOM bytes, and they want different fixes.
        $noEncodingReason = ($noEncoding[0] -split ' --> ', 2)[1]
        $utf8BomReason = ($utf8Bom[0] -split ' --> ', 2)[1]
        if ([string]::IsNullOrWhiteSpace($noEncodingReason) -or [string]::IsNullOrWhiteSpace($utf8BomReason)) {
            return @{ Passed = $false; Detail = "one or both violations carried no ' --> reason' explanation: no-Encoding='$noEncodingReason', utf8='$utf8BomReason'" }
        }
        if ($noEncodingReason -ceq $utf8BomReason) {
            return @{ Passed = $false; Detail = "both divergence shapes were reported with the identical explanation '$noEncodingReason'; they diverge for different reasons and want different fixes, so a reader cannot act on a message that conflates them" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Test-NoShellDivergentWriteInScripts {
    $scriptsDir = Join-Path $repoRoot 'scripts'
    $targets = @(Get-ChildItem -LiteralPath $scriptsDir -File -Filter '*.ps1' | Sort-Object Name | ForEach-Object { $_.FullName })
    if ($targets.Count -eq 0) {
        return @{ Passed = $false; Detail = "found ZERO .ps1 files under $scriptsDir; refusing to report success on an empty sweep" }
    }
    $violations = @(Get-ShellDivergentWrite -Path $targets -RootForRelativePath $repoRoot)
    $unexpected = @($violations | Where-Object {
        $key = ($_ -split ': ', 2)[0]
        $script:WriteAllowlist -notcontains $key
    })
    if ($unexpected.Count -gt 0) {
        return @{ Passed = $false; Detail = "$($unexpected.Count) write(s) across $($targets.Count) scanned file(s) produce different bytes in 5.1 (BOM) and 7 (no BOM); use Write-Utf8NoBom / [IO.File]::WriteAllText instead:`n    " + ($unexpected -join "`n    ") }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 6: the end-to-end proof that the flag changes behavior, not
# just source text. Takes the REAL Get-Content call out of the live
# scripts/Validate-AgentHub.ps1 source by AST (so this tests the shipped
# code, not a hand-copied stand-in that could drift from it), then runs
# that exact call in Windows PowerShell 5.1 AND in PowerShell 7 against a
# real repo SKILL.md that holds non-ASCII bytes, and requires the two
# shells to produce the same string.
#
# Before the fix this fails: the two shells return different content for
# the same file, so a validator's verdict depends on who ran it. Both
# shells must be present -- if either is missing this FAILS rather than
# skipping, because a silent skip is how this defect stayed invisible. ---
function Test-ValidateAgentHubSkillReadAgreesAcrossShells {
    $validateScript = Join-Path $repoRoot 'scripts\Validate-AgentHub.ps1'
    $commands = @(Get-CommandAstList -Path $validateScript | Where-Object {
        [string]$_.GetCommandName() -eq 'Get-Content' -and $_.Extent.Text -match '\$skillPath'
    })
    if ($commands.Count -ne 1) {
        return @{ Passed = $false; Detail = "expected exactly one Get-Content call on `$skillPath in Validate-AgentHub.ps1, found $($commands.Count); update this test to match the script" }
    }
    $readExpression = $commands[0].Extent.Text

    # Pick a real, tracked SKILL.md that actually contains a non-ASCII byte.
    # If none does, this behavior has nothing to prove and must say so
    # rather than pass vacuously.
    $skillFile = $null
    foreach ($candidate in @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'packages') -Filter 'SKILL.md' -File -Recurse | Sort-Object FullName)) {
        if (@([IO.File]::ReadAllBytes($candidate.FullName) | Where-Object { $_ -gt 127 }).Count -gt 0) {
            $skillFile = $candidate.FullName
            break
        }
    }
    if (-not $skillFile) {
        return @{ Passed = $false; Detail = 'no packages/**/SKILL.md contains a non-ASCII byte, so this cross-shell comparison would prove nothing; the fixture assumption behind this test no longer holds' }
    }

    $shells = [ordered]@{}
    foreach ($shellName in @('pwsh', 'powershell')) {
        $resolved = Get-Command -Name $shellName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $resolved) {
            return @{ Passed = $false; Detail = "$shellName is not on PATH; this defect is defined by the disagreement BETWEEN the two shells, so it cannot be verified in only one" }
        }
        $shells[$shellName] = $resolved.Source
    }

    # Runs the extracted call verbatim and prints a hash of what it returned,
    # so the comparison is over content and never over console formatting.
    $probe = @(
        "`$ErrorActionPreference = 'Stop'"
        "`$skillPath = '$skillFile'"
        "`$text = $readExpression"
        "`$sha = [Security.Cryptography.SHA256]::Create()"
        "`$bytes = `$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(`$text))"
        "Write-Output (([BitConverter]::ToString(`$bytes) -replace '-','') + ':' + `$text.Length)"
    ) -join "`n"
    $probeFile = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-encoding-probe-" + [guid]::NewGuid() + '.ps1')
    [IO.File]::WriteAllText($probeFile, $probe, [Text.UTF8Encoding]::new($false))
    try {
        $results = [ordered]@{}
        foreach ($shellName in $shells.Keys) {
            $previousEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = & $shells[$shellName] -NoProfile -File $probeFile 2>&1 | Out-String
            } finally {
                $ErrorActionPreference = $previousEap
            }
            $results[$shellName] = $output.Trim()
        }
        if ($results['pwsh'] -cne $results['powershell']) {
            return @{ Passed = $false; Detail = "reading $skillFile through the live Validate-AgentHub.ps1 call ``$readExpression`` gave DIFFERENT content in the two shells -- pwsh 7: $($results['pwsh']) | Windows PowerShell 5.1: $($results['powershell']). The validator's verdict therefore depends on which shell ran it." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
    }
}

$r1 = Test-DetectorFlagsUnencodedRead
Report 'the detector flags an unencoded Get-Content and clears an -Encoding UTF8 one' $r1.Passed $r1.Detail

$r2 = Test-ScanTargetSetCoversEveryTrackedScript
Report 'the scan target set is proven non-empty and reaches every tracked .ps1, including packages/ paths outside a tests/ directory' $r2.Passed $r2.Detail

$r3 = Test-NoUnencodedReadInScope
Report 'no tracked .ps1 in the repository reads a file without explicit UTF-8 decoding' $r3.Passed $r3.Detail

$r4 = Test-DetectorIsNotFooledByCommentsHereStringsOrContinuations
Report 'the detector is not fooled by comments, here-strings, dotted path tokens, or line continuations' $r4.Passed $r4.Detail

$r5a = Test-WriteDetectorDistinguishesNoEncodingFromUtf8
Report 'the write detector flags both a no-Encoding write and an -Encoding UTF8 write, clears byte writes, and explains the two differently' $r5a.Passed $r5a.Detail

$r5 = Test-NoShellDivergentWriteInScripts
Report 'no script in scripts/ writes a persistent file with shell-divergent Set-Content -Encoding UTF8' $r5.Passed $r5.Detail

$r6 = Test-ValidateAgentHubSkillReadAgreesAcrossShells
Report 'the live Validate-AgentHub.ps1 SKILL.md read returns identical content in 5.1 and 7' $r6.Passed $r6.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
