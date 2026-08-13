<#
.SYNOPSIS
    Mirror a Windows repository working tree into the macOS guest.

.DESCRIPTION
    The payload is defined by `git ls-files -co --exclude-standard`, which is
    exactly the working tree minus everything .gitignore excludes. That is the
    right boundary here: it carries uncommitted work (the host repo is often
    ahead of origin), and it automatically leaves out node_modules, ios,
    android and .expo -- 6.6 GB of generated output for Rexa, against roughly
    20 MB of actual source.

    Transfer is tar + scp rather than rsync because Git Bash on this host ships
    no rsync, and PowerShell corrupts binary data sent through a pipeline. The
    guest does have openrsync, so if a host-side rsync ever appears this can be
    simplified.

    Files in the guest copy that are no longer in the manifest are deleted, so
    a rename on the host does not leave a stale duplicate behind. Generated
    directories in the guest are never touched, so node_modules and Pods
    survive between syncs.

.EXAMPLE
    .\Sync-RepoToGuest.ps1
    .\Sync-RepoToGuest.ps1 -RepoPath C:\Repos\shmindmaster\abacare -GuestPath '~/Repos/shmindmaster/abacare'
#>
[CmdletBinding()]
param(
    [string] $RepoPath  = 'C:\Repos\shmindmaster\rexa',
    [string] $GuestPath = '~/Repos/shmindmaster/rexa',
    [string] $SshHost   = 'macvm',

    # Directories the guest generates for itself. Never synced, never pruned.
    # `build` covers Xcode DerivedData (build-expo-simulator.sh writes to
    # `<repo>/build/simulator`): repos that don't gitignore `build/` never put
    # it in the host manifest, so without this entry every sync prunes it as
    # "not in the manifest" and forces a cold rebuild. Observed: pruned=18397.
    [string[]] $GuestOwned = @('.git', 'node_modules', 'ios', 'android', '.expo', '.gradle', 'Pods', 'build')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    throw "Not a git repository: $RepoPath"
}

Write-Host "Sync $RepoPath -> ${SshHost}:$GuestPath" -ForegroundColor Cyan

# --- build the manifest -----------------------------------------------------
# -c cached (tracked), -o others (untracked), --exclude-standard honours
# .gitignore. Together: the working tree as a developer sees it.
$files = & git -C $RepoPath ls-files -co --exclude-standard
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $RepoPath" }
$files = @($files | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $RepoPath $_)) })
if ($files.Count -eq 0) { throw "Manifest is empty -- refusing to sync (this would prune the guest copy)" }

$work         = Join-Path ([System.IO.Path]::GetTempPath()) ("repo-sync-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$manifestFile = "$work.manifest"
$tarFile      = "$work.tgz"

# LF-terminated, no BOM: this file is read by the guest shell as well as tar.
[System.IO.File]::WriteAllText($manifestFile, (($files -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

try {
    Write-Host "  $($files.Count) files" -ForegroundColor DarkGray

    # --- pack -------------------------------------------------------------
    # Windows ships bsdtar as tar.exe; -T reads the file list.
    & tar.exe -czf $tarFile -C $RepoPath -T $manifestFile
    if ($LASTEXITCODE -ne 0) { throw "tar failed" }
    $sizeMB = [math]::Round((Get-Item $tarFile).Length / 1MB, 1)
    Write-Host "  payload ${sizeMB} MB" -ForegroundColor DarkGray

    # --- ship -------------------------------------------------------------
    & scp -q $tarFile "${SshHost}:/tmp/repo-sync.tgz"
    if ($LASTEXITCODE -ne 0) { throw "scp of payload failed" }
    & scp -q $manifestFile "${SshHost}:/tmp/repo-sync.manifest"
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
rm -f /tmp/repo-sync.tgz /tmp/repo-sync.manifest /tmp/repo-sync.want /tmp/repo-sync.have /tmp/repo-sync.stale
echo "SYNCED files=`$(find . $pruneFind -type f -print | wc -l | tr -d ' ') pruned=`$removed"
"@

    $result = $remote | & ssh $SshHost 'bash -s'
    if ($LASTEXITCODE -ne 0) { throw "guest-side sync failed" }
    Write-Host "  $result" -ForegroundColor Green
}
finally {
    Remove-Item $manifestFile, $tarFile -ErrorAction SilentlyContinue
}
