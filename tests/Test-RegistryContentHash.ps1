#Requires -Version 5.1
<#
Behavior tests for scripts/RegistryContentHash.ps1's tracked-only enumeration
(task-0b: make the registry content hash reproducible from a clean clone).

Not a Pester suite: this repo carries no Pester dependency, Windows
PowerShell 5.1 here only exposes the bundled Pester 3.4.0 (old `Should Be`
dialect), and pwsh's newer Pester versions live in a module path invisible to
powershell.exe (confirmed while building this file -- see task-0b report).
Same self-checking idiom scripts/Validate-AgentHub.ps1 already uses: each
Test-* function returns a result, the runner prints one PASS/FAIL line per
behavior, accumulates failures, and exits 1 if any behavior did not hold, 0
otherwise.

Run: pwsh -NoProfile -File tests/Test-RegistryContentHash.ps1
     powershell.exe -NoProfile -File tests/Test-RegistryContentHash.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\RegistryContentHash.ps1')

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

# --- Behavior 1: a gitignored file inside a package must never affect the hash. ---
function Test-IgnoredFileDoesNotMoveHash {
    $packageDir = Join-Path $repoRoot 'packages\framer'
    $scratchFile = Join-Path $packageDir 'scratch.mp4'
    if (Test-Path -LiteralPath $scratchFile) { Remove-Item -LiteralPath $scratchFile -Force }
    $before = Get-AgentHubRegistryHashBasisValue -Path $packageDir
    try {
        Set-Content -LiteralPath $scratchFile -Value 'not a real video -- transient scratch content for task-0b test' -Encoding UTF8 -NoNewline
        $statusLine = (& git -C $packageDir status --porcelain --ignored -- scratch.mp4) -join "`n"
        if ($statusLine -notmatch '^!! ') {
            throw "test setup invalid: 'packages/framer/scratch.mp4' was not recognized by git as ignored (status: '$statusLine'); .gitignore may have changed"
        }
        $after = Get-AgentHubRegistryHashBasisValue -Path $packageDir
        if ($before -ne $after) {
            return @{ Passed = $false; Detail = "hash moved: before=$before after=$after" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $scratchFile -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 2 (regression guard, not new): a tracked file change must still move the hash. ---
function Test-TrackedFileChangeMovesHash {
    $packageDir = Join-Path $repoRoot 'packages\framer'
    $trackedFile = Join-Path $packageDir 'skills\framer\SKILL.md'
    if (-not (Test-Path -LiteralPath $trackedFile)) {
        return @{ Passed = $false; Detail = "fixture file missing: $trackedFile" }
    }
    $originalBytes = [IO.File]::ReadAllBytes($trackedFile)
    $before = Get-AgentHubRegistryHashBasisValue -Path $packageDir
    try {
        Add-Content -LiteralPath $trackedFile -Value "`n<!-- temp task-0b hash-sensitivity probe, reverted immediately -->" -Encoding UTF8
        $after = Get-AgentHubRegistryHashBasisValue -Path $packageDir
        if ($before -eq $after) {
            return @{ Passed = $false; Detail = "hash did not move after editing a tracked file: $before" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        [IO.File]::WriteAllBytes($trackedFile, $originalBytes)
    }
}

# --- Behavior 3: if git is unavailable, fail loudly instead of returning a wrong hash. ---
function Test-UnavailableGitFailsLoudly {
    $packageDir = Join-Path $repoRoot 'packages\framer'
    $originalPath = $env:PATH
    try {
        $filtered = ($originalPath -split ';' | Where-Object {
            $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'git.exe')) -and -not (Test-Path -LiteralPath (Join-Path $_ 'git.cmd'))
        }) -join ';'
        $env:PATH = $filtered
        if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
            return @{ Passed = $false; Detail = 'test setup invalid: git is still resolvable on PATH after filtering' }
        }
        $threw = $false
        $message = $null
        try {
            Get-AgentHubRegistryHashBasisValue -Path $packageDir | Out-Null
        } catch {
            $threw = $true
            $message = $_.Exception.Message
        }
        if (-not $threw) {
            return @{ Passed = $false; Detail = 'no exception was thrown when git was unavailable -- a wrong hash could be returned silently' }
        }
        if ($message -notmatch 'git') {
            return @{ Passed = $false; Detail = "exception thrown but message does not mention git: $message" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        $env:PATH = $originalPath
    }
}

# --- Behavior 4: a path outside any git work tree must fail loudly, not silently hash the filesystem. ---
function Test-NonWorkTreePathFailsLoudly {
    $tempDir = Join-Path $env:AGENTHUB_TEST_SCRATCH ("non-worktree-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        Set-Content -LiteralPath (Join-Path $tempDir 'file.txt') -Value 'content outside any git work tree' -Encoding UTF8
        $threw = $false
        try { Get-AgentHubRegistryHashBasisValue -Path $tempDir | Out-Null } catch { $threw = $true }
        if (-not $threw) {
            return @{ Passed = $false; Detail = "no exception was thrown for a path outside any git work tree: $tempDir" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Behavior 5: zero tracked files under an existing directory must fail loudly, not silently hash an empty set. ---
function Test-EmptyTrackedSetFailsLoudly {
    $emptyDir = Join-Path $repoRoot 'packages\framer\.tmp-task0b-empty-hash-test'
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    try {
        $threw = $false
        try { Get-AgentHubRegistryHashBasisValue -Path $emptyDir | Out-Null } catch { $threw = $true }
        if (-not $threw) {
            return @{ Passed = $false; Detail = "no exception was thrown for a directory with zero git-tracked files: $emptyDir" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

$r1 = Test-IgnoredFileDoesNotMoveHash
Report 'gitignored file does not move the hash' $r1.Passed $r1.Detail

$r2 = Test-TrackedFileChangeMovesHash
Report 'tracked file change moves the hash' $r2.Passed $r2.Detail

$r3 = Test-UnavailableGitFailsLoudly
Report 'unavailable git enumeration mechanism fails loudly' $r3.Passed $r3.Detail

$r4 = Test-NonWorkTreePathFailsLoudly
Report 'path outside a git work tree fails loudly' $r4.Passed $r4.Detail

$r5 = Test-EmptyTrackedSetFailsLoudly
Report 'zero git-tracked files under an existing directory fails loudly' $r5.Passed $r5.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
