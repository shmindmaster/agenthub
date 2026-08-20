#Requires -Version 5.1
<#
Behavior test for retiredSkillNames.

Why: capabilities.json records the previous names of renamed or withdrawn
skills in `retiredSkillNames`, and until 2026-08-20 NOTHING read that field --
grep across scripts/ and tests/ returned zero hits. The field looked like a
contract and was decoration.

The consequence was live: `use-chrome-devtools-mcp` was retired when the fleet
moved to Playwright, but 10 hosts still carried it, each instructing an agent
to drive an MCP id that no longer exists in mcps.json. Prune could not help --
it only removes destinations still tracked in the ledger, and a renamed skill
drops out of the ledger and becomes unowned, which is precisely the state prune
skips.

Retired is not the same as absent-from-source. A skill deleted outright leaves
no record; a retired name is a deliberate instruction to remove deployed copies.

Run: pwsh -NoProfile -File tests/Test-RetiredSkillRemoval.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$caps   = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$agents = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Collect every retired name, and the live names, so the two can be compared.
$retired = @{}
$live    = @{}
foreach ($c in @($caps.capabilities)) {
    foreach ($n in @($c.retiredSkillNames)) { if ($n) { $retired[[string]$n] = [string]$c.id } }
    $src = Join-Path $repoRoot ((([string]$c.canonicalSource) -replace '/', '\') + '\skills')
    if (Test-Path -LiteralPath $src) {
        foreach ($d in Get-ChildItem -LiteralPath $src -Directory -ErrorAction SilentlyContinue) { $live[$d.Name] = $true }
    }
}

Report 'the registry names at least one retired skill' ($retired.Count -gt 0) `
    'No capability declares retiredSkillNames, so every check below would be vacuous.'

# A name cannot be both retired and shipping. This already bit once: a LIVE
# skill owned by another capability was listed as retired, and a cleanup keyed
# off that field would have deleted it.
$both = @($retired.Keys | Where-Object { $live.ContainsKey($_) })
Report 'no retired name is also a live skill in packages' ($both.Count -eq 0) `
    "these are both retired and shipping, so removing them would delete working skills: $($both -join ', ')"

# End state: no host may carry a directory named by a retired skill.
$roots = [Collections.Generic.List[string]]::new()
foreach ($a in @($agents.activeAgents)) {
    foreach ($p in @($a.nativePaths.skillsDir, $a.nativePaths.sharedSkillsDir)) {
        if (-not $p) { continue }
        $expanded = ([string]$p) -replace '^~', ([regex]::Escape($env:USERPROFILE))
        $resolved = [Environment]::ExpandEnvironmentVariables($expanded)
        if ((Test-Path -LiteralPath $resolved) -and $resolved -notin $roots) { $roots.Add($resolved) }
    }
}
Report 'at least one deployed skills directory was found to scan' ($roots.Count -gt 0) `
    'No host skills directory resolved, so the end-state check below proves nothing.'

foreach ($name in $retired.Keys) {
    $hits = @($roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ $name) })
    Report "retired skill '$name' is deployed nowhere" ($hits.Count -eq 0) `
        "owned by '$($retired[$name])', still present in $($hits.Count) host dir(s): $(($hits | ForEach-Object { Split-Path -Parent $_ | Split-Path -Leaf }) -join ', ')"
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: all retired-skill checks passed' -ForegroundColor Green
exit 0
