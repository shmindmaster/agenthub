#Requires -Version 5.1
<#
Public-repository privacy gate.

AgentHub is public. Owner-specific policy, career and job-pursuit material,
customer identifiers, personal contact details and secrets belong only in the
gitignored personal overlay (overlays/personal/). This test fails when such
material appears in a TRACKED file.

Two layers:
  1. Generic patterns that apply to any clone (CI, a public fork): career and
     job-pursuit policy markers, owner-confirmed claim tags, US phone numbers,
     non-example email addresses, credential-shaped strings, and a stricter
     check on the tracked policy files (no owner name, no personal paths).
  2. An overlay-held denylist, read ONLY when present:
       overlays/personal/privacy-denylist.txt
     One .NET regex per line; blank lines and lines starting with # are
     ignored. The denylist is private because naming a client or a pursuit in
     a tracked file would itself be the leak. With no overlay this layer prints
     one SKIP line and reports nothing else.

Run: pwsh -NoProfile -File tests/Test-PublicRepoPrivacy.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'lib\PrivateOverlay.ps1')

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

# --- tracked file list (git when available, directory walk otherwise) ------
function Get-TrackedFiles {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
        $raw = & git -C $repoRoot ls-files -z 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            return @(($raw -join '') -split "`0" | Where-Object { $_ })
        }
    }
    $skip = '^(\.git|node_modules|overlays[\\/]personal|\.repowise)([\\/]|$)'
    return @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/') } |
        Where-Object { $_ -notmatch $skip })
}

$textExtensions = '\.(md|txt|json|jsonc|ya?ml|toml|ps1|psm1|mjs|cjs|js|ts|tsx|jsx|css|html|sh|cmd|bat|example|env|ini|cfg|csv)$'
$files = [Collections.Generic.List[object]]::new()
foreach ($relative in Get-TrackedFiles) {
    if ($relative -notmatch $textExtensions -and (Split-Path -Leaf $relative) -notmatch '^(LICENSE|\.gitignore|\.gitattributes|\.env\.example)$') { continue }
    $full = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    if ((Get-Item -LiteralPath $full).Length -gt 2MB) { continue }
    $files.Add([pscustomobject]@{ Relative = ($relative -replace '\\', '/'); Text = [IO.File]::ReadAllText($full) })
}
if ($files.Count -lt 50) { throw "Only $($files.Count) tracked text files were found under $repoRoot; the scan would be vacuous." }
$self = 'tests/Test-PublicRepoPrivacy.ps1'

function Find-Hits {
    param([string]$Pattern, [string[]]$ExemptFiles = @())
    $regex = [regex]::new($Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $hits = foreach ($f in $files) {
        if ($f.Relative -eq $self -or $ExemptFiles -contains $f.Relative) { continue }
        if ($regex.IsMatch($f.Text)) { $f.Relative }
    }
    return @($hits)
}

# --- layer 1: generic patterns --------------------------------------------
$generic = @(
    @{ Name = 'no owner-confirmed claim tags'; Pattern = 'OWNER_CONFIRMED' }
    @{ Name = 'no career or job-pursuit policy sections'; Pattern = '^#{1,4}\s*(Career (positioning|representation|production)|Role-specific positioning|Opportunity evidence|Portfolio materials)\b' }
    @{ Name = 'no job-posting or requisition identifiers tied to a pursuit'; Pattern = '(?i)\b(requisition|req(uisition)?\s*#|JD\s*#|job\s*id)\s*[:#]?\s*\d{5,}' }
    @{ Name = 'no US phone numbers'; Pattern = '(?<![\d.,-])(\+1[ .-]?)?(\(\d{3}\)[ .-]?\d{3}[ .-]\d{4}|\d{3}[.-]\d{3}[.-]\d{4})(?![\d-])' }
    @{ Name = 'no non-example email addresses'; Pattern = '(?<![\w.-])[A-Za-z0-9._%+-]+@(?!example\.(com|org|net|test|invalid)\b|users\.noreply\.github\.com\b|noreply\.)(?:[A-Za-z0-9-]+\.)+(?!(md|json|js|mjs|cjs|ts|ps1|ya?ml|txt|exe|dll)\b)[A-Za-z]{2,}\b' }
    @{ Name = 'no credential-shaped strings'; Pattern = '(sk-[A-Za-z0-9_-]{24,}|ghp_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{24,}|AKIA[0-9A-Z]{16}|xox[bpa]-[0-9A-Za-z-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' }
)
foreach ($rule in $generic) {
    $hits = Find-Hits -Pattern $rule.Pattern
    Report "tracked files: $($rule.Name)" ($hits.Count -eq 0) "found in: $($hits -join ', ')"
}

# The tracked policy files are the highest-risk surface: they are compiled
# verbatim into every host and carry no owner identity or personal paths.
$policyFiles = @('global-agent-policy.md', 'policy-core.md')
$policyPattern = 'Sarosh|OneDrive|[A-Z]:\\Users\\|D:\\Local-AI|C:\\Repos\\|\bOwner voice\b|OPENAI_API_KEY'
$policyHits = @()
foreach ($name in $policyFiles) {
    $match = $files | Where-Object { $_.Relative -eq $name }
    if (-not $match) { $policyHits += "$name (missing)"; continue }
    if ($match.Text -match $policyPattern) { $policyHits += "$name ($($Matches[0]))" }
}
Report 'tracked policy files carry no owner identity, personal paths, or owner-voice rules' ($policyHits.Count -eq 0) "found in: $($policyHits -join ', ')"

# --- layer 2: overlay-held denylist ---------------------------------------
$overlay = Resolve-AgentHubTestOverlay -RepositoryRoot $repoRoot
$denylistPath = if ($overlay.Root) { Join-Path $overlay.Root 'privacy-denylist.txt' } else { $null }
if ($denylistPath -and (Test-Path -LiteralPath $denylistPath -PathType Leaf)) {
    $patterns = @([IO.File]::ReadAllLines($denylistPath) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $bad = foreach ($p in $patterns) { Find-Hits -Pattern $p | ForEach-Object { "$_ [denylist entry $([array]::IndexOf($patterns, $p) + 1)]" } }
    Report "tracked files: none of the $($patterns.Count) overlay denylist patterns match" (@($bad).Count -eq 0) "found in: $(@($bad) -join ', ')"
} else {
    Write-Host "SKIP: overlay denylist layer -- no privacy-denylist.txt ($(if ($overlay.Root) { $overlay.Root } else { $overlay.Reason }))"
}

Write-Host "SCOPE: $($files.Count) tracked text files scanned"
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
