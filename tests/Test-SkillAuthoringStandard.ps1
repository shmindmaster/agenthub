#Requires -Version 5.1
<#
Walks every managed skill under packages/*/skills/*/SKILL.md and checks it
against docs/development/skill-authoring-standard.md.

Hard failures (fail the run):
  - frontmatter `name` must equal the skill's own directory name
  - frontmatter `description` must contain "Use when" (after the outcome)
  - frontmatter `description` must be at most 300 characters
  - frontmatter `name` must not contain "claude" or "anthropic"
  - frontmatter values must be YAML-safe (no unquoted `: `)

Reported only (never fails the run):
  - skills with no numbered sections (`## N. ...`) -- older skills predate
    the standard; a blanket rewrite is a separate task, not this checker's
    job.

Run: pwsh -NoProfile -File tests/Test-SkillAuthoringStandard.ps1
     powershell.exe -NoProfile -File tests/Test-SkillAuthoringStandard.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$packagesRoot = Join-Path $repoRoot 'packages'

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

# A dependency tree can carry its own skills directory, and this scan is about the
# skills AgentHub authors. Measured 2026-11-05: playwright-core ships
# lib/tools/skills/playwright-cli/SKILL.md and two siblings, which satisfied the
# skills/<name>/SKILL.md shape below and failed the 'Use when' and 300-character
# rules as if they were ours. Same exclusion set Sync-Capabilities.ps1 refuses to
# deploy, and the same class of over-count that Test-MobileDevelopment.ps1 had.
$skillFiles = @(Get-ChildItem -LiteralPath $packagesRoot -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|dist|coverage)[\\/]' } |
    Where-Object { $_.FullName -match '[\\/]skills[\\/][^\\/]+[\\/]SKILL\.md$' })

if ($skillFiles.Count -eq 0) {
    Write-Host "FAIL: no SKILL.md files found under $packagesRoot" -ForegroundColor Red
    exit 1
}

$nameMismatches = [Collections.Generic.List[string]]::new()
$descriptionFailures = [Collections.Generic.List[string]]::new()
$descriptionTooLong = [Collections.Generic.List[string]]::new()
$reservedNames = [Collections.Generic.List[string]]::new()
$yamlUnsafe = [Collections.Generic.List[string]]::new()
$noNumberedSections = [Collections.Generic.List[string]]::new()

foreach ($file in $skillFiles) {
    $skillDirName = Split-Path -Leaf (Split-Path -Parent $file.FullName)
    $relativePath = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    $content = Read-Utf8 $file.FullName
    if (-not $content) {
        $nameMismatches.Add("$relativePath (empty or unreadable)")
        continue
    }

    $nameMatch = [regex]::Match($content, '(?m)^name:\s*(\S+)\s*$')
    if (-not $nameMatch.Success -or $nameMatch.Groups[1].Value -ne $skillDirName) {
        $actual = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { '<missing>' }
        $nameMismatches.Add("$relativePath (name=$actual, expected=$skillDirName)")
    }

    $descMatch = [regex]::Match($content, '(?m)^description:\s*(.*)$')
    # The description states the outcome first and then carries "Use when"; a YAML quote is syntax, not content.
    $descValue = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim().Trim('"', "'") } else { '' }
    if ($descValue -notmatch '\bUse when\b') {
        $descriptionFailures.Add($relativePath)
    }
    if ($descValue.Length -gt 300) {
        $descriptionTooLong.Add("$relativePath ($($descValue.Length) characters)")
    }
    if ($skillDirName -match '(?i)claude|anthropic') {
        $reservedNames.Add($relativePath)
    }

    $fmMatch = [regex]::Match($content, '(?s)\A---\r?\n(?<yaml>.*?)\r?\n---')
    if ($fmMatch.Success) {
        foreach ($line in ($fmMatch.Groups['yaml'].Value -split '\r?\n')) {
            if ($line -match '^(?<k>[A-Za-z0-9][A-Za-z0-9_-]*):\s+(?<v>.*)$') {
                $v = $Matches['v']
                $alreadyQuoted = $v.TrimStart() -match '^["''>|\[{]'
                if (-not $alreadyQuoted -and $v -match ': ') {
                    $yamlUnsafe.Add("$relativePath ($($Matches['k']))")
                }
            }
        }
    }

    if ($content -notmatch '(?m)^#{1,2}\s*\d+[.)]\s') {
        $noNumberedSections.Add($relativePath)
    }
}

Write-Host "Scanned $($skillFiles.Count) SKILL.md files under packages/*/skills/*/"
Write-Host ''

$hardFailed = $false

if ($nameMismatches.Count -gt 0) {
    $hardFailed = $true
    Write-Host "FAIL: frontmatter name != directory name ($($nameMismatches.Count)):" -ForegroundColor Red
    $nameMismatches | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "PASS: every skill's frontmatter name matches its directory name" -ForegroundColor Green
}

if ($descriptionFailures.Count -gt 0) {
    $hardFailed = $true
    Write-Host "FAIL: description does not contain 'Use when' ($($descriptionFailures.Count)):" -ForegroundColor Red
    $descriptionFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "PASS: every skill's description contains 'Use when'" -ForegroundColor Green
}

if ($descriptionTooLong.Count -gt 0) {
    $hardFailed = $true
    Write-Host "FAIL: description exceeds 300 characters ($($descriptionTooLong.Count)):" -ForegroundColor Red
    $descriptionTooLong | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "PASS: every skill's description is at most 300 characters" -ForegroundColor Green
}

if ($reservedNames.Count -gt 0) {
    $hardFailed = $true
    Write-Host "FAIL: skill name contains 'claude' or 'anthropic' ($($reservedNames.Count)):" -ForegroundColor Red
    $reservedNames | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "PASS: no skill name contains 'claude' or 'anthropic'" -ForegroundColor Green
}

if ($yamlUnsafe.Count -gt 0) {
    $hardFailed = $true
    Write-Host "FAIL: unquoted frontmatter value contains ': ' ($($yamlUnsafe.Count)):" -ForegroundColor Red
    $yamlUnsafe | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "PASS: every skill's frontmatter is YAML-safe (no unquoted ': ')" -ForegroundColor Green
}

Write-Host ''
if ($noNumberedSections.Count -gt 0) {
    Write-Host "REPORT (non-failing): $($noNumberedSections.Count) skill(s) have no numbered sections:" -ForegroundColor Yellow
    $noNumberedSections | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else {
    Write-Host "REPORT: every skill has at least one numbered section" -ForegroundColor Yellow
}

Write-Host ''
Write-Host "RESULT: $(if ($hardFailed) { 'FAILED (hard identity checks)' } else { 'PASSED (hard identity checks)' }); $($noNumberedSections.Count) skill(s) flagged for missing numbered sections (non-failing)"
if ($hardFailed) { exit 1 }
exit 0
