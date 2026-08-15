#Requires -Version 5.1
<#
Behavior tests for the mobile-device-lab's cross-OS repository sync.

THE DEFECT
`tar.exe -C <working-tree>` transfers the checkout rendition of a file. On a
Windows checkout with core.autocrlf enabled that means a script declared
`text eol=lf` arrives on macOS as CRLF and Bash parses `pipefail\r` as an
invalid option. A normal unit test that reads the Git blob misses this: it must
exercise an actual CRLF *working file*, an uncommitted edit, and the payload
archive the sync sends.

THE CONTRACT
Sync-RepoToGuest.ps1 builds an archive from an isolated temporary Git index.
That applies attributes without changing either the source file or the user's
real index. `-StageOnly` gives this test a local, no-SSH proof surface. Its
directory must be empty so a stale archive cannot be reported as a new result.

This file creates only a synthetic Git repository under
$env:AGENTHUB_TEST_SCRATCH. It never contacts a guest or writes to a real
repository.

Run: pwsh -NoProfile -File tests/Test-SyncRepoToGuest.ps1
     powershell.exe -NoProfile -File tests/Test-SyncRepoToGuest.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncScript = Join-Path $repoRoot 'packages\mobile-device-lab\skills\mobile-device-lab\scripts\Sync-RepoToGuest.ps1'

if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
    $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
}

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

function Invoke-FixtureGit {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)

    # Git emits CRLF checkout notices on stderr with exit 0. Windows PowerShell
    # 5.1 otherwise promotes those notices to terminating NativeCommandError
    # records under this test's Stop policy, so use Git's exit code directly.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Path @Arguments 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Path (exit $LASTEXITCODE): $output"
    }
    return $output.TrimEnd()
}

function New-SyncFixture {
    $root = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sync-repo-" + [guid]::NewGuid())
    # Keep generated evidence outside the fixture repository. Otherwise the
    # evidence itself would appear as untracked work and invalidate the claim
    # that sync left the developer's Git state alone.
    $stage = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sync-stage-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    Invoke-FixtureGit -Path $root -Arguments @('init') | Out-Null
    Invoke-FixtureGit -Path $root -Arguments @('config', 'user.email', 'fixture@example.test') | Out-Null
    Invoke-FixtureGit -Path $root -Arguments @('config', 'user.name', 'AgentHub fixture') | Out-Null

    # The committed tree uses LF. The source script below intentionally uses
    # CRLF and contains a real unstaged change, as Rexa did when the guest
    # build first failed.
    [IO.File]::WriteAllText((Join-Path $root '.gitattributes'), "*.sh text eol=lf`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'e2e-ios.sh'), "#!/bin/bash`nset -euo pipefail`n", [Text.UTF8Encoding]::new($false))
    Invoke-FixtureGit -Path $root -Arguments @('add', '--all') | Out-Null
    Invoke-FixtureGit -Path $root -Arguments @('commit', '-m', 'fixture') | Out-Null

    [IO.File]::WriteAllText((Join-Path $root 'e2e-ios.sh'), "#!/bin/bash`r`nset -euo pipefail # unstaged fixture edit`r`n", [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ Root = $root; Stage = $stage; Script = Join-Path $root 'e2e-ios.sh' }
}

# ---------------------------------------------------------------------------
# Behavior 1: source has CRLF and a genuine unstaged change; staging must send
# an LF archive that carries the change and must not alter the source or index.
# ---------------------------------------------------------------------------
function Test-NormalizedArchivePreservesUncommittedWork {
    $fixture = New-SyncFixture
    $extract = Join-Path $env:AGENTHUB_TEST_SCRATCH ("agenthub-sync-extract-" + [guid]::NewGuid())
    try {
        $beforeBytes = [IO.File]::ReadAllBytes($fixture.Script)
        $beforeStatus = Invoke-FixtureGit -Path $fixture.Root -Arguments @('status', '--porcelain')
        $beforeIndex = Invoke-FixtureGit -Path $fixture.Root -Arguments @('ls-files', '-s', '--', 'e2e-ios.sh')
        if (($beforeBytes -join ',') -notmatch '13,10' -or $beforeStatus -notmatch '^ M e2e-ios\.sh$') {
            return @{ Passed = $false; Detail = "fixture did not establish a CRLF, unstaged script. bytes=[$($beforeBytes -join ',')] status=[$beforeStatus]" }
        }

        & $syncScript -RepoPath $fixture.Root -StageOnly -StagePath $fixture.Stage
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "-StageOnly exited $LASTEXITCODE" }
        }

        $archive = Join-Path $fixture.Stage 'repo-sync.tar.gz'
        $manifest = Join-Path $fixture.Stage 'repo-sync.manifest'
        if (-not (Test-Path -LiteralPath $archive) -or -not (Test-Path -LiteralPath $manifest)) {
            return @{ Passed = $false; Detail = "-StageOnly did not retain both archive and manifest under $($fixture.Stage)" }
        }
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        & tar.exe -xzf $archive -C $extract
        if ($LASTEXITCODE -ne 0) { return @{ Passed = $false; Detail = 'tar.exe could not extract the staged archive' } }

        $payloadPath = Join-Path $extract 'e2e-ios.sh'
        $payloadBytes = [IO.File]::ReadAllBytes($payloadPath)
        $payloadText = [Text.UTF8Encoding]::new($false).GetString($payloadBytes)
        $afterBytes = [IO.File]::ReadAllBytes($fixture.Script)
        $afterStatus = Invoke-FixtureGit -Path $fixture.Root -Arguments @('status', '--porcelain')
        $afterIndex = Invoke-FixtureGit -Path $fixture.Root -Arguments @('ls-files', '-s', '--', 'e2e-ios.sh')
        $manifestBytes = [IO.File]::ReadAllBytes($manifest)

        if (($payloadBytes -join ',') -match '13,10') {
            return @{ Passed = $false; Detail = "the staged shell script still contains CRLF bytes: [$($payloadBytes -join ',')]" }
        }
        if ($payloadText -notmatch [regex]::Escape('pipefail # unstaged fixture edit')) {
            return @{ Passed = $false; Detail = "the staged archive lost the uncommitted source edit. Payload: [$payloadText]" }
        }
        if (($afterBytes -join ',') -cne ($beforeBytes -join ',')) {
            return @{ Passed = $false; Detail = 'the sync changed the CRLF working-tree source bytes' }
        }
        if ($afterStatus -cne $beforeStatus -or $afterIndex -cne $beforeIndex) {
            return @{ Passed = $false; Detail = "the sync changed the real Git state. beforeStatus=[$beforeStatus] afterStatus=[$afterStatus] beforeIndex=[$beforeIndex] afterIndex=[$afterIndex]" }
        }
        if (($manifestBytes -join ',') -match '13,10') {
            return @{ Passed = $false; Detail = 'the guest manifest contains CRLF despite the guest shell consuming it' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixture.Stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Behavior 2: a destination containing an old artifact must fail before a
# fresh normalized payload can be confused with stale output.
# ---------------------------------------------------------------------------
function Test-StageOnlyRejectsNonEmptyDestination {
    $fixture = New-SyncFixture
    try {
        New-Item -ItemType Directory -Path $fixture.Stage -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture.Stage 'stale.tar.gz'), 'not this run', [Text.UTF8Encoding]::new($false))
        $threw = $false
        try {
            & $syncScript -RepoPath $fixture.Root -StageOnly -StagePath $fixture.Stage
        } catch {
            $threw = $_.Exception.Message -match '-StagePath must be empty'
        }
        if (-not $threw) {
            return @{ Passed = $false; Detail = 'a non-empty -StagePath was accepted, so a stale payload could be mistaken for this run' }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $fixture.Stage 'stale.tar.gz'))) {
            return @{ Passed = $false; Detail = 'the preflight altered the existing staging artifact instead of refusing it' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixture.Stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Behavior 3: filters may turn a developer's local file into a pointer or
# another representation. Until sync owns a byte-preserving path for them,
# refusing before staging is safer than silently dropping the working bytes.
# ---------------------------------------------------------------------------
function Test-PreflightRejectsNonEolGitConversions {
    $fixture = New-SyncFixture
    try {
        [IO.File]::AppendAllText((Join-Path $fixture.Root '.gitattributes'), "asset.bin filter=lfs`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllBytes((Join-Path $fixture.Root 'asset.bin'), [byte[]](1, 2, 3, 4))
        $threw = $false
        try {
            & $syncScript -RepoPath $fixture.Root -StageOnly -StagePath $fixture.Stage
        } catch {
            $threw = $_.Exception.Message -match 'non-EOL Git clean conversions'
        }
        if (-not $threw) {
            return @{ Passed = $false; Detail = 'a repository with filter=lfs was not refused before isolated-index staging could replace the file with a pointer' }
        }
        if (Test-Path -LiteralPath $fixture.Stage) {
            return @{ Passed = $false; Detail = 'the non-EOL conversion preflight created a staging directory instead of failing before payload creation' }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fixture.Stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Behavior 4: never stream a Windows here-string into guest bash. PowerShell's
# native pipeline writes CRLF and turns `pipefail` into an invalid option.
# ---------------------------------------------------------------------------
function Test-GuestScriptTransportIsExplicitlyLf {
    $source = Get-Content -LiteralPath $syncScript -Raw -Encoding UTF8
    $hasLfMaterialization = $source -match '\$normalizedRemote\s*=.*-replace\s+"`r`n",\s*"`n"' -and
        $source -match 'WriteAllText\(\$remoteScriptFile,\s*\$normalizedRemote'
    $shipsScript = $source -match 'repo-sync\.sh' -and $source -match "bash /tmp/repo-sync\.sh"
    $streamsHereString = $source -match '\$remote\s*\|\s*&\s*ssh'
    if (-not $hasLfMaterialization -or -not $shipsScript -or $streamsHereString) {
        return @{ Passed = $false; Detail = 'guest sync must scp an explicit LF-only script and must not pipe a Windows here-string to ssh' }
    }
    return @{ Passed = $true; Detail = $null }
}

$r1 = Test-NormalizedArchivePreservesUncommittedWork
Report 'the staged archive normalizes eol=lf while preserving uncommitted work and real Git state' $r1.Passed $r1.Detail

$r2 = Test-StageOnlyRejectsNonEmptyDestination
Report '-StageOnly refuses a non-empty destination before stale output can be reused' $r2.Passed $r2.Detail

$r3 = Test-PreflightRejectsNonEolGitConversions
Report 'the preflight rejects non-EOL Git conversions rather than silently changing working bytes' $r3.Passed $r3.Detail

$r4 = Test-GuestScriptTransportIsExplicitlyLf
Report 'guest execution uses an explicit LF-only script instead of a Windows native pipeline' $r4.Passed $r4.Detail

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
