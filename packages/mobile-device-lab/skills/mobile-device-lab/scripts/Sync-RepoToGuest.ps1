<#
.SYNOPSIS
    Mirror a Windows repository working tree into the macOS guest.

.DESCRIPTION
    The payload is defined by `git ls-files -co --exclude-standard`, which is
    exactly the working tree minus everything .gitignore excludes. That is the
    right boundary here: it carries uncommitted work (the host repo is often
    ahead of origin), and it automatically leaves out node_modules, ios,
    android and .expo, avoiding generated native payloads that can be several
    gigabytes larger than the actual source.

    Transfer is Git archive + scp rather than rsync because Git Bash on this
    host ships no rsync, and PowerShell corrupts binary data sent through a
    pipeline. The archive is built from an isolated temporary Git index: `git
    add --all` applies the source repository's attributes (including
    `text eol=lf`) without changing the developer's index or working tree.
    This is important on a CRLF Windows checkout, where sending working-tree
    bytes directly breaks guest shell scripts. The guest does have openrsync,
    so if a host-side rsync ever appears this can be simplified.

    Files in the guest copy that are no longer in the manifest are deleted, so
    a rename on the host does not leave a stale duplicate behind. Generated
    directories in the guest are never touched, so node_modules and Pods
    survive between syncs.

.EXAMPLE
    .\Sync-RepoToGuest.ps1 -RepoPath C:\Repos\shmindmaster\abacare -GuestPath '~/Repos/shmindmaster/abacare'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $RepoPath,
    [string] $GuestPath,
    [string] $SshHost   = 'macvm',
    [string] $SshHostName,

    # Build and retain the normalized payload locally, without contacting a
    # guest. This is primarily a deterministic verification surface; callers
    # must provide an empty, explicitly chosen directory so no existing staged
    # payload can be mistaken for this run's output.
    [switch] $StageOnly,
    [string] $StagePath,

    # Directories the guest generates for itself. Never synced, never pruned.
    # `build` covers Xcode DerivedData (build-expo-simulator.sh writes to
    # `<repo>/build/simulator`): repos that don't gitignore `build/` never put
    # it in the host manifest, so without this entry every sync prunes it as
    # "not in the manifest" and forces a cold rebuild. Observed: pruned=18397.
    [string[]] $GuestOwned = @('.git', 'node_modules', 'ios', 'android', '.expo', '.gradle', 'Pods', 'build')
)

$ErrorActionPreference = 'Stop'

if (-not $StageOnly -and [string]::IsNullOrWhiteSpace($GuestPath)) {
    throw '-GuestPath is required unless -StageOnly is used. Product-neutral infrastructure never guesses a repository destination.'
}
if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    throw "Not a git repository: $RepoPath"
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if ($StageOnly -and [string]::IsNullOrWhiteSpace($StagePath)) {
    throw '-StageOnly requires -StagePath so the retained payload has an explicit, inspectable destination.'
}

Write-Host "Sync $RepoPath -> ${SshHost}:$GuestPath" -ForegroundColor Cyan

function Invoke-SyncGit {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $FailureMessage
    )

    # Windows PowerShell 5.1 turns ordinary Git stderr warnings (including
    # harmless CRLF checkout notices) into NativeCommandError records when
    # ErrorActionPreference is Stop. Capture them, then use Git's actual exit
    # code as the contract so a warning cannot abort a safe sync while a real
    # non-zero exit still fails loudly.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $RepoPath @Arguments 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $previousEap
    }
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage (git exit $LASTEXITCODE): $output" }
    return $output.TrimEnd()
}

# --- build the manifest -----------------------------------------------------
# -c cached (tracked), -o others (untracked), --exclude-standard honours
# .gitignore. Together: the working tree as a developer sees it.
$files = @((Invoke-SyncGit -Arguments @('ls-files', '-co', '--exclude-standard') -FailureMessage "git ls-files failed in $RepoPath") -split "`r?`n")
$files = @($files | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $RepoPath $_)) })
if ($files.Count -eq 0) { throw "Manifest is empty -- refusing to sync (this would prune the guest copy)" }

# A temporary index lets Git apply text/eol conversion without changing the
# developer's index or checkout. It must not silently apply *other* clean
# conversions: an LFS/filter pointer, working-tree encoding conversion, or
# ident collapse would make the guest payload differ materially from the
# developer's file. Refuse those repositories until this sync owns a safe
# byte-preserving implementation for the relevant filter.
$attributeOutput = @((Invoke-SyncGit -Arguments (@('check-attr', 'filter', 'ident', 'working-tree-encoding', '--') + $files) -FailureMessage "git check-attr failed in $RepoPath") -split "`r?`n")
$unsupportedAttributes = @(
    $attributeOutput |
        Where-Object { $_ -match ': (filter|ident|working-tree-encoding): (.+)$' } |
        ForEach-Object {
            $match = [regex]::Match($_, ': (filter|ident|working-tree-encoding): (.+)$')
            if ($match.Success -and $match.Groups[2].Value -notin @('unspecified', 'unset')) { $_ }
        }
)
if ($unsupportedAttributes.Count -gt 0) {
    throw "Refusing to normalize a repository that uses non-EOL Git clean conversions. The isolated index would change those files before transfer: $($unsupportedAttributes -join '; '). This sync safely supports Git text/eol policy only."
}

if ($StageOnly) {
    $StagePath = [IO.Path]::GetFullPath($StagePath)
    if (Test-Path -LiteralPath $StagePath) {
        $existing = @(Get-ChildItem -LiteralPath $StagePath -Force)
        if ($existing.Count -gt 0) {
            throw "-StagePath must be empty: $StagePath"
        }
    } else {
        New-Item -ItemType Directory -Path $StagePath -Force | Out-Null
    }
    $work = $StagePath
} else {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("repo-sync-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
}

$manifestFile = Join-Path $work 'repo-sync.manifest'
$tarFile      = Join-Path $work 'repo-sync.tar.gz'
$tempIndex    = Join-Path $work 'repo-sync.index'
$remoteScriptFile = Join-Path $work 'repo-sync.sh'

# LF-terminated, no BOM: this file is read by the guest shell as well as tar.
[System.IO.File]::WriteAllText($manifestFile, (($files -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
try {
    Write-Host "  $($files.Count) files" -ForegroundColor DarkGray

    # --- normalize and pack -----------------------------------------------
    # Build the tree in a private index. The real .git/index is never opened
    # for writing, so staged and unstaged developer work stays exactly where it
    # was. `git archive` writes canonical blob bytes, unlike checkout-index or
    # tar.exe, which would write the CRLF working-tree rendition again.
    $env:GIT_INDEX_FILE = $tempIndex
    Invoke-SyncGit -Arguments @('read-tree', 'HEAD') -FailureMessage "git read-tree failed in $RepoPath" | Out-Null
    Invoke-SyncGit -Arguments @('add', '--all') -FailureMessage "git add failed while staging the normalized payload in $RepoPath" | Out-Null
    $tree = (Invoke-SyncGit -Arguments @('write-tree') -FailureMessage "git write-tree failed while staging the normalized payload in $RepoPath").Trim()
    if ([string]::IsNullOrWhiteSpace($tree)) { throw "git write-tree returned no tree while staging the normalized payload in $RepoPath" }
    Invoke-SyncGit -Arguments @('archive', '--format=tar.gz', "--output=$tarFile", $tree) -FailureMessage 'git archive failed' | Out-Null
    $sizeMB = [math]::Round((Get-Item $tarFile).Length / 1MB, 1)
    Write-Host "  normalized payload ${sizeMB} MB" -ForegroundColor DarkGray

    if ($StageOnly) {
        Write-Host "  STAGED archive=$tarFile manifest=$manifestFile tree=$tree" -ForegroundColor Green
        return
    }

    # --- ship -------------------------------------------------------------
    $scpArgs = @('-q')
    if ($SshHostName) { $scpArgs += @('-o', "HostName=$SshHostName", '-o', "HostKeyAlias=$SshHost") }
    & scp @scpArgs $tarFile "${SshHost}:/tmp/repo-sync.tgz"
    if ($LASTEXITCODE -ne 0) { throw "scp of payload failed" }
    & scp @scpArgs $manifestFile "${SshHost}:/tmp/repo-sync.manifest"
    if ($LASTEXITCODE -ne 0) { throw "scp of manifest failed" }

    # --- unpack and prune -------------------------------------------------
    $pruneFind = ($GuestOwned | ForEach-Object { "-name '$_' -prune -o" }) -join ' '

    $remote = @"
set -euo pipefail
dest="$GuestPath"
# A tilde inside double quotes is a literal character, not `$HOME. Without this
# the sync silently creates a directory actually named "~" and everything
# afterwards works -- in the wrong place. Observed 2026-08-10.
dest="`${dest/#\~/`$HOME}"
mkdir -p "`$dest"
tar -xzf /tmp/repo-sync.tgz -C "`$dest"

# Prune: anything under the guest copy that the manifest no longer lists, and
# that is not inside a directory the guest owns.
cd "`$dest"
sed 's|\\|/|g' /tmp/repo-sync.manifest | sed 's|\r`$||' | sort > /tmp/repo-sync.want
find . $pruneFind -type f -print | sed 's|^\./||' | sort > /tmp/repo-sync.have
removed=`$(comm -13 /tmp/repo-sync.want /tmp/repo-sync.have | tee /tmp/repo-sync.stale | wc -l | tr -d ' ')
if [ "`$removed" -gt 0 ]; then
  while IFS= read -r f; do [ -n "`$f" ] && rm -f -- "`$f"; done < /tmp/repo-sync.stale
fi
find . -type d -empty -delete 2>/dev/null || true
rm -f /tmp/repo-sync.tgz /tmp/repo-sync.manifest /tmp/repo-sync.want /tmp/repo-sync.have /tmp/repo-sync.stale /tmp/repo-sync.sh
echo "SYNCED files=`$(find . $pruneFind -type f -print | wc -l | tr -d ' ') pruned=`$removed"
"@

    # PowerShell's native-command pipeline writes platform newlines. Sending
    # the here-string through stdin therefore turns `pipefail` into
    # `pipefail\r` under both Windows shells. Materialize and transfer explicit
    # LF bytes instead so the guest always executes the versioned script the
    # tests inspected.
    $normalizedRemote = ($remote -replace "`r`n", "`n") -replace "`r", "`n"
    $normalizedRemote = $normalizedRemote.TrimEnd([char[]]@("`r", "`n")) + "`n"
    [System.IO.File]::WriteAllText($remoteScriptFile, $normalizedRemote, (New-Object System.Text.UTF8Encoding($false)))
    & scp @scpArgs $remoteScriptFile "${SshHost}:/tmp/repo-sync.sh"
    if ($LASTEXITCODE -ne 0) { throw "scp of guest sync script failed" }

    $sshArgs = @()
    if ($SshHostName) { $sshArgs += @('-o', "HostName=$SshHostName", '-o', "HostKeyAlias=$SshHost") }
    $sshArgs += @($SshHost, 'bash /tmp/repo-sync.sh')
    $result = & ssh @sshArgs
    if ($LASTEXITCODE -ne 0) { throw "guest-side sync failed" }
    Write-Host "  $result" -ForegroundColor Green
}
finally {
    if ($null -eq $previousIndex) {
        Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $previousIndex, 'Process')
    }
    Remove-Item -LiteralPath $tempIndex, "$tempIndex.lock" -ErrorAction SilentlyContinue
    if (-not $StageOnly) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
