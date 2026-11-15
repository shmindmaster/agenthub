#Requires -Version 5.1
<# Audit or install the AgentHub-managed Factory custom droids.

   -Audit (default) compares the repository copies with ~/.factory/droids and
   prints a per-file state: current, drift, missing, or owner-authored
   (untouched).
   -Apply copies only the AgentHub-managed files named in $ManagedFiles. It
   never overwrites or deletes an owner-authored droid (including the Mission
   droids Factory itself writes), never touches settings.json, mcp.json,
   plugins or permission rules, writes no backup copies, and prints the before
   and after SHA-256 of each file it changes.
   -UserProfile redirects the target (default: the current user's profile). #>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$UserProfile
)
$ErrorActionPreference = 'Stop'

# The only names this script may write. Everything else under the target is owner-authored.
$ManagedFiles = [ordered]@{
    'droids' = @('ah-engineer.md', 'ah-reviewer.md', 'ah-browser-tester.md')
}

if ($Audit -and $Apply) { throw 'Use either -Audit or -Apply, not both.' }
if (-not $UserProfile) { $UserProfile = [Environment]::GetFolderPath('UserProfile') }
$source = $PSScriptRoot
$target = Join-Path $UserProfile '.factory'

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$changed = 0
foreach ($dir in $ManagedFiles.Keys) {
    $srcDir = Join-Path $source $dir
    $dstDir = Join-Path $target $dir
    $dirItem = Get-Item -LiteralPath $dstDir -Force -ErrorAction SilentlyContinue
    if ($dirItem -and ($dirItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Write-Host ("note: {0} is a junction or link; managed files are written to its target" -f $dir)
    }
    foreach ($name in $ManagedFiles[$dir]) {
        $src = Join-Path $srcDir $name
        $dst = Join-Path $dstDir $name
        $srcHash = Get-Sha256 $src
        if (-not $srcHash) { Write-Host ("missing-in-repo  {0}/{1}" -f $dir, $name); continue }
        # A managed name that is a directory, or a link pointing elsewhere, is never written through.
        $existing = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.PSIsContainer) { Write-Host ("refused-dir      {0}/{1}" -f $dir, $name); continue }
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Write-Host ("refused-link     {0}/{1}" -f $dir, $name); continue }
        $dstHash = Get-Sha256 $dst
        $state = if (-not $dstHash) { 'missing' } elseif ($dstHash -eq $srcHash) { 'current' } else { 'drift' }
        Write-Host ("{0,-16} {1}/{2}" -f $state, $dir, $name)
        if ($Apply -and $state -ne 'current') {
            if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $after = Get-Sha256 $dst
            $beforeText = if ($dstHash) { $dstHash } else { '(absent)' }
            Write-Host ("  changed {0}/{1}: before={2} after={3}" -f $dir, $name, $beforeText, $after)
            $changed++
        }
    }
    # Owner-authored: anything else in the target directory. Reported, never touched.
    if (Test-Path -LiteralPath $dstDir) {
        foreach ($f in Get-ChildItem -LiteralPath $dstDir -File | Sort-Object Name) {
            if ($ManagedFiles[$dir] -notcontains $f.Name) {
                Write-Host ("{0,-16} {1}/{2}" -f 'owner-authored', $dir, $f.Name)
            }
        }
    }
}
if ($Apply) { Write-Host ("applied: {0} file(s) changed" -f $changed) } else { Write-Host 'audit only: nothing written' }
