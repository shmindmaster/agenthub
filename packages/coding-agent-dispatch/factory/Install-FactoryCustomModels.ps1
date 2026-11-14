#Requires -Version 7
<# Audit or install the AgentHub-managed Factory BYOK custom models (SH-4676).

   -Audit (default) compares packages/coding-agent-dispatch/factory/custom-models.json
   with the customModels array in ~/.factory/settings.json and prints a per-entry
   state: current, drift, or missing. Owner-authored entries (any model id not in
   the canonical file) are reported and never touched; nothing is ever removed.
   -Apply merges the canonical entries into customModels. Before the first change
   it backs up the settings file to settings.json.bak-<yyyyMMdd-HHmm>, keeps the
   JSON valid at every write (re-parses after writing and restores the backup if
   the result is invalid), and never prints an apiKey value.
   -UserProfile redirects the target (default: the current user's profile).

   The stable dispatch id of an entry is custom:<model field>. Entries whose
   upstream model name collides with a Factory built-in model id carry the
   colliding name in extraArgs.model instead, so Factory does not account BYOK
   usage at the built-in multiplier (see fleet-profile.json
   dispatchPolicy.factory.byokCreditsNote). #>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Apply,
    [string]$UserProfile
)
$ErrorActionPreference = 'Stop'

if ($Audit -and $Apply) { throw 'Use either -Audit or -Apply, not both.' }
if (-not $UserProfile) { $UserProfile = [Environment]::GetFolderPath('UserProfile') }
$canonicalFile = Join-Path $PSScriptRoot 'custom-models.json'
$settingsFile = Join-Path $UserProfile '.factory\settings.json'
if (-not (Test-Path -LiteralPath $canonicalFile -PathType Leaf)) { throw "canonical file missing: $canonicalFile" }
if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) { throw "settings file missing: $settingsFile" }

$canonical = @((Get-Content -LiteralPath $canonicalFile -Raw -Encoding UTF8 | ConvertFrom-Json).customModels)
$settings = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$existing = @()
if ($settings.PSObject.Properties['customModels'] -and $settings.customModels) { $existing = @($settings.customModels) }

# Compare only the canonical fields; an owner entry may carry extra fields.
# Never print a credential value: a ${VAR} reference is a name and is safe to
# show, but an existing entry may carry a literal key, so anything else in a
# key-like field is masked in diff output (Codex/Sentry review, SH-4676 PR).
function Format-SafeValue([string]$Name, $Value) {
    if ($null -eq $Value) { return $null }
    if ($Name -match '(?i)^(apikey|api_key|token|secret)$' -and $Value -notmatch '^\$\{[A-Za-z_][A-Za-z0-9_]*\}$') { return '***' }
    return $Value
}
function Get-FieldDiff($Canonical, $Existing) {
    $diff = @()
    foreach ($prop in $Canonical.PSObject.Properties) {
        $name = $prop.Name
        if ($name -eq '$comment') { continue }
        $want = if ($prop.Value -is [pscustomobject]) { $prop.Value | ConvertTo-Json -Depth 10 -Compress } else { [string]$prop.Value }
        $have = if ($Existing.PSObject.Properties[$name]) {
            if ($Existing.$name -is [pscustomobject]) { $Existing.$name | ConvertTo-Json -Depth 10 -Compress } else { [string]$Existing.$name }
        } else { $null }
        if ($want -cne $have) { $diff += ("{0}: have '{1}', want '{2}'" -f $name, (Format-SafeValue $name $have), (Format-SafeValue $name $want)) }
    }
    return $diff
}

$drifted = @()
foreach ($entry in $canonical) {
    $id = [string]$entry.model
    $match = $existing | Where-Object { [string]$_.model -eq $id } | Select-Object -First 1
    if (-not $match) {
        Write-Host ("{0,-16} custom:{1}" -f 'missing', $id)
        $drifted += @{ State = 'missing'; Entry = $entry }
        continue
    }
    $diff = Get-FieldDiff $entry $match
    if ($diff.Count -gt 0) {
        Write-Host ("{0,-16} custom:{1}" -f 'drift', $id)
        foreach ($line in $diff) { Write-Host ("                 {0}" -f $line) }
        $drifted += @{ State = 'drift'; Entry = $entry }
    } else {
        Write-Host ("{0,-16} custom:{1}" -f 'current', $id)
    }
}
$canonicalIds = @($canonical | ForEach-Object { [string]$_.model })
foreach ($entry in $existing) {
    if ([string]$entry.model -notin $canonicalIds) {
        Write-Host ("{0,-16} custom:{1}" -f 'owner-authored', $entry.model)
    }
}

if (-not $Apply) { Write-Host 'audit only: nothing written'; return }
if ($drifted.Count -eq 0) { Write-Host 'applied: 0 change(s)'; return }

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$backup = "$settingsFile.bak-$stamp"
Copy-Item -LiteralPath $settingsFile -Destination $backup
Write-Host ("backup: {0}" -f $backup)

$merged = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $existing) {
    $id = [string]$entry.model
    $canonicalEntry = $canonical | Where-Object { [string]$_.model -eq $id } | Select-Object -First 1
    if ($canonicalEntry) { $merged.Add($canonicalEntry) } else { $merged.Add($entry) }
}
foreach ($entry in $canonical) {
    $present = $existing | Where-Object { [string]$_.model -eq [string]$entry.model }
    if (-not $present) { $merged.Add($entry) }
}
# A first-time install has no customModels property, and assigning a missing
# property on a PSCustomObject throws; add it explicitly in that case.
if ($settings.PSObject.Properties['customModels']) {
    $settings.customModels = $merged.ToArray()
} else {
    $settings | Add-Member -NotePropertyName 'customModels' -NotePropertyValue $merged.ToArray()
}

[IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
# Keep the config valid at every write: re-parse, and restore on any failure.
try {
    $check = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $checkIds = @($check.customModels | ForEach-Object { [string]$_.model })
    foreach ($id in $canonicalIds) {
        if ($id -notin $checkIds) { throw "canonical id custom:$id is absent after the write" }
    }
} catch {
    Copy-Item -LiteralPath $backup -Destination $settingsFile -Force
    throw "settings.json failed validation after the write and was restored from $backup : $($_.Exception.Message)"
}
Write-Host ("applied: {0} entry/entries merged" -f $drifted.Count)
