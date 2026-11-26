#Requires -Version 5.1
<# Audit or install the AgentHub-managed Kilo settings and agent profiles.

   -Audit (default) compares the repository copies with the installed state and
   prints a per-file verdict: current, drift, missing, owner-authored
   (untouched) or refused-dir/refused-link. It also reports a legacy config
   file (config.json, kilo.json, opencode.json, opencode.jsonc) inside
   ~/.config/kilo as stale-legacy: Kilo deep-merges those files, so leaving
   one next to the managed kilo.jsonc would create a second effective
   settings owner. The installer never deletes it; removing a legacy file is
   an explicit owner action recorded in registry/agents.json.
   -Apply copies only the AgentHub-managed files named below, resolving the
   {userHome} placeholder in kilo.jsonc against the target profile. A file that
   is not on that managed list is reported as owner-authored and never written,
   overwritten or deleted; measured 2026-11-26: `owner-notes.md` beside the
   settings and `agent/custom-agent.md` both reported owner-authored and left
   intact across an -Apply run. It writes no backup copies and prints the before
   and after SHA-256 of every file it changes.
   A MANAGED file that an owner has edited is a different case: -Apply repairs it
   back to the package copy, because repairing drift is what apply is for. Run
   -Audit first to see that drift, and read the printed before/after pair, or
   remove the file from the managed list before applying if the edit is wanted.
   -UserProfile redirects the target (default: the current user's profile).
   Evidence for the destinations: ~/.config/kilo/agent/peer.md was discovered
   and enforced by kilo 7.8.27 on 2026-11-10 (registry/fleet-profile.json
   dispatchPolicy.kilo), and ~/.config/kilo/kilo.jsonc is the documented
   global config (https://kilo.ai/docs/getting-started/settings). #>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$UserProfile
)
$ErrorActionPreference = 'Stop'

if ($Audit -and $Apply) { throw 'Use either -Audit or -Apply, not both.' }
if (-not $UserProfile) { $UserProfile = [Environment]::GetFolderPath('UserProfile') }
$source = $PSScriptRoot
$target = Join-Path $UserProfile '.config\kilo'

# The only names this script may write. Everything else under the target is owner-authored.
$ManagedAgents = @('peer.md', 'engineer.md', 'reviewer.md', 'tester.md')
$ManagedSettings = 'kilo.jsonc'
# Files Kilo deep-merges when present next to kilo.jsonc (settings docs).
$LegacySettings = @('config.json', 'kilo.json', 'opencode.json', 'opencode.jsonc')

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# kilo.jsonc carries the {userHome} placeholder so the public repository copy
# never bakes a username. Comparison and deployment both run through this pair.
function Resolve-SettingsText([string]$Path, [string]$ProfileRoot) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return ([IO.File]::ReadAllText($Path)).Replace('{userHome}', ($ProfileRoot -replace '\\', '/'))
}

$changed = 0

# --- agent profiles ---
$srcAgents = Join-Path $source 'agent'
$dstAgents = Join-Path $target 'agent'
foreach ($name in $ManagedAgents) {
    $src = Join-Path $srcAgents $name
    $dst = Join-Path $dstAgents $name
    $srcHash = Get-Sha256 $src
    if (-not $srcHash) { Write-Host ("missing-in-repo  agent/{0}" -f $name); continue }
    $existing = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
    if ($existing -and $existing.PSIsContainer) { Write-Host ("refused-dir      agent/{0}" -f $name); continue }
    if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Write-Host ("refused-link     agent/{0}" -f $name); continue }
    $dstHash = Get-Sha256 $dst
    $state = if (-not $dstHash) { 'missing' } elseif ($dstHash -eq $srcHash) { 'current' } else { 'drift' }
    Write-Host ("{0,-16} agent/{1}" -f $state, $name)
    if ($Apply -and $state -ne 'current') {
        if (-not (Test-Path -LiteralPath $dstAgents)) { New-Item -ItemType Directory -Path $dstAgents -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $after = Get-Sha256 $dst
        $beforeText = if ($dstHash) { $dstHash } else { '(absent)' }
        Write-Host ("  changed agent/{0}: before={1} after={2}" -f $name, $beforeText, $after)
        $changed++
    }
}
if (Test-Path -LiteralPath $dstAgents) {
    foreach ($f in Get-ChildItem -LiteralPath $dstAgents -File | Sort-Object Name) {
        if ($ManagedAgents -notcontains $f.Name) { Write-Host ("{0,-16} agent/{1}" -f 'owner-authored', $f.Name) }
    }
}

# --- global settings ---
$srcSettings = Join-Path $source $ManagedSettings
$dstSettings = Join-Path $target $ManagedSettings
if (Test-Path -LiteralPath $srcSettings -PathType Leaf) {
    $existing = Get-Item -LiteralPath $dstSettings -Force -ErrorAction SilentlyContinue
    if ($existing -and $existing.PSIsContainer) { Write-Host 'refused-dir      kilo.jsonc (a directory occupies the path)'
    } elseif ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Write-Host 'refused-link     kilo.jsonc (a link occupies the path)'
    } else {
        $expected = Resolve-SettingsText $srcSettings $UserProfile
        $installed = if (Test-Path -LiteralPath $dstSettings -PathType Leaf) { [IO.File]::ReadAllText($dstSettings) } else { $null }
        $state = if ($null -eq $installed) { 'missing' } elseif ($installed -ceq $expected) { 'current' } else { 'drift' }
        Write-Host ("{0,-16} {1}" -f $state, $ManagedSettings)
        if ($Apply -and $state -ne 'current') {
            $beforeHash = Get-Sha256 $dstSettings
            if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
            [IO.File]::WriteAllText($dstSettings, $expected, [Text.UTF8Encoding]::new($false))
            $after = Get-Sha256 $dstSettings
            $beforeText = if ($beforeHash) { $beforeHash } else { '(absent)' }
            Write-Host ("  changed {0}: before={1} after={2}" -f $ManagedSettings, $beforeText, $after)
            $changed++
        }
    }
} else {
    Write-Host 'missing-in-repo  kilo.jsonc'
}

# --- legacy settings files: reported, never written or deleted ---
foreach ($legacy in $LegacySettings) {
    $p = Join-Path $target $legacy
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        Write-Host ("{0,-16} {1} (Kilo deep-merges this legacy file; remove it so kilo.jsonc is the one settings owner)" -f 'stale-legacy', $legacy)
    }
}

if ($Apply) { Write-Host ("applied: {0} file(s) changed" -f $changed) } else { Write-Host 'audit only: nothing written' }