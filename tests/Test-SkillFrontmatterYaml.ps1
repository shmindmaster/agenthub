#Requires -Version 5.1
<#
Behavior tests for scripts/SkillFrontmatterYaml.ps1.

Zed rejects unquoted YAML scalars that contain ": " ("mapping values are
not allowed in this context"). The live failure was Railway's use-railway
SKILL.md in ~/.agents/skills. These tests use synthetic files only.

Run: pwsh -NoProfile -File tests/Test-SkillFrontmatterYaml.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\SkillFrontmatterYaml.ps1')

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

function New-YamlScratch([string]$Body) {
    $dir = Join-Path $env:TEMP ('agenthub-yamlfm-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'SKILL.md'
    [IO.File]::WriteAllText($path, $Body, [Text.UTF8Encoding]::new($false))
    return $path
}

# 1. The Railway-shaped description is quoted; inner quotes are escaped.
$railway = @"
---
name: use-railway
description: Use when working with Railway infrastructure: signing up. Never says "Railway".
allowed-tools: Bash(railway:*), Bash(which:*)
---

# Use Railway
body
"@ -replace '`n', "`n"
$r1 = Repair-SkillFrontmatterYamlText -Content $railway
$quoted = $r1.Content -match '(?m)^description: "Use when working with Railway infrastructure: signing up. Never says \\"Railway\\"."\r?$'
$toolsUntouched = $r1.Content -match '(?m)^allowed-tools: Bash\(railway:\*\), Bash\(which:\*\)\r?$'
Report 'unquoted description with colon-space is double-quoted and inner quotes escaped' `
    ($r1.Changed -and $quoted -and $toolsUntouched) `
    "Changed=$($r1.Changed); quoted=$quoted; toolsUntouched=$toolsUntouched; content=`n$($r1.Content)"

# 2. Already-quoted description is byte-identical.
$already = "---`nname: sample`ndescription: `"Use when foo: bar`"`n---`n`nbody`n"
$r2 = Repair-SkillFrontmatterYamlText -Content $already
Report 'already-quoted description is unchanged' `
    ((-not $r2.Changed) -and ($r2.Content -ceq $already)) `
    "Changed=$($r2.Changed) Reason=$($r2.Reason)"

# 3. Folded description is left alone.
$folded = "---`nname: sample`ndescription: >`n  Use when foo: bar`n---`n`nbody`n"
$r3 = Repair-SkillFrontmatterYamlText -Content $folded
Report 'folded description block is unchanged' `
    ((-not $r3.Changed) -and ($r3.Content -ceq $folded)) `
    "Changed=$($r3.Changed) Reason=$($r3.Reason)"

# 4. No frontmatter is a no-op.
$plain = "# Just a heading`n`nNo frontmatter.`n"
$r4 = Repair-SkillFrontmatterYamlText -Content $plain
Report 'file with no frontmatter is unchanged' `
    ((-not $r4.Changed) -and ($r4.Content -ceq $plain) -and $r4.Reason -eq 'no-frontmatter') `
    "Changed=$($r4.Changed) Reason=$($r4.Reason)"

# 5. -Apply writes; a second apply is a no-op.
$scratch = New-YamlScratch -Body $railway
try {
    $first = Repair-SkillFrontmatterYamlFile -Path $scratch -Apply
    $after = [IO.File]::ReadAllText($scratch)
    $second = Repair-SkillFrontmatterYamlFile -Path $scratch -Apply
    $after2 = [IO.File]::ReadAllText($scratch)
    Report 'Apply quotes the file and a second Apply is a no-op' `
        ($first.Written -and (-not $second.Changed) -and ($after -ceq $after2) -and ($after -match 'description: "Use when')) `
        "first.Written=$($first.Written) second.Changed=$($second.Changed)"
} finally {
    Remove-Item -LiteralPath (Split-Path -Parent $scratch) -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. Directory walk repairs unmanaged skills and skips managed destinations.
$root = Join-Path $env:TEMP ('agenthub-yamlfm-root-' + [guid]::NewGuid().ToString('N'))
try {
    $badDir = Join-Path $root 'use-railway'
    $goodDir = Join-Path $root 'sarosh-communication'
    $managedDir = Join-Path $root 'managed-skill'
    New-Item -ItemType Directory -Path $badDir, $goodDir, $managedDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $badDir 'SKILL.md'), $railway, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $goodDir 'SKILL.md'), $already, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $managedDir 'SKILL.md'), $railway, [Text.UTF8Encoding]::new($false))

    $audit = Repair-SkillFrontmatterYamlDirectory -SkillsRoot $root -SkipPaths @($managedDir)
    $managedStillBad = [IO.File]::ReadAllText((Join-Path $managedDir 'SKILL.md')) -ceq $railway
    $badStillBad = [IO.File]::ReadAllText((Join-Path $badDir 'SKILL.md')) -ceq $railway
    Report 'audit reports unmanaged unsafe skills and does not write' `
        ($audit.Scanned -eq 3 -and $audit.Repaired -eq 0 -and $audit.NeedsRepair.Count -eq 1 -and $managedStillBad -and $badStillBad) `
        "scanned=$($audit.Scanned) repaired=$($audit.Repaired) needs=$($audit.NeedsRepair.Count) managedUntouched=$managedStillBad"

    $apply = Repair-SkillFrontmatterYamlDirectory -SkillsRoot $root -Apply -SkipPaths @($managedDir)
    $badNowQuoted = [IO.File]::ReadAllText((Join-Path $badDir 'SKILL.md')) -match 'description: "Use when'
    $managedStillBad2 = [IO.File]::ReadAllText((Join-Path $managedDir 'SKILL.md')) -ceq $railway
    Report 'Apply quotes unmanaged skills and skips managed destinations' `
        ($apply.Repaired -eq 1 -and $badNowQuoted -and $managedStillBad2) `
        "repaired=$($apply.Repaired) quoted=$badNowQuoted managedUntouched=$managedStillBad2"
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

# 7. CLI wrapper exists and reports the PASS line.
$cli = Join-Path $repoRoot 'scripts\Repair-SkillFrontmatterYaml.ps1'
$cliDir = Join-Path $env:TEMP ('agenthub-yamlfm-cli-' + [guid]::NewGuid().ToString('N'))
try {
    $skillDir = Join-Path $cliDir 'use-railway'
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $skillDir 'SKILL.md'), $railway, [Text.UTF8Encoding]::new($false))
    $hostExe = (Get-Process -Id $PID).Path
    $output = & $hostExe -NoProfile -File $cli -SkillsRoot $cliDir -Apply 2>&1 | Out-String
    $quotedByCli = [IO.File]::ReadAllText((Join-Path $skillDir 'SKILL.md')) -match 'description: "Use when'
    Report 'CLI -Apply quotes the Railway-shaped skill and prints PASS' `
        ($LASTEXITCODE -eq 0 -and $quotedByCli -and $output -match 'PASS: skill-frontmatter-yaml' -and $output -match 'repaired=1') `
        "exit=$LASTEXITCODE quoted=$quotedByCli output=$output"
} finally {
    Remove-Item -LiteralPath $cliDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $reported passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
