#Requires -Version 5.1
<#
Validates every AgentHub plugin against the HOST'S OWN schema, not a
reimplementation of it.

Why this exists: product-experience-engineering shipped
`"agents": "./agents/"` -- a directory string where the schema requires an
array of file paths. Claude Code refused to load the entire plugin, so all four
of its subagents were unavailable. Validate-AgentHub.ps1 reported PASS and
counted it among the seven installable plugins, because a wrong type is still
valid JSON with the right name. It was found by running `claude plugin list` by
hand, which is not a control.

Validate-AgentHub now type-checks the fields we know about. This file is the
stronger guarantee: `claude plugin validate` IS the schema authority, so it
catches the fields we have not thought of yet. A hand-written checker can only
ever encode the mistakes already made.

Run: pwsh -NoProfile -File tests/Test-PluginManifests.ps1
     powershell.exe -NoProfile -File tests/Test-PluginManifests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

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

function Get-PluginPackages {
    Get-ChildItem (Join-Path $repoRoot 'packages') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.claude-plugin\plugin.json') }
}

# --- Behavior 1: every plugin passes the host's own validator.
#
# If the `claude` CLI is unavailable this CANNOT pass quietly -- an absent
# checker reporting success is the failure mode this repository exists to
# eliminate. It fails and says why. ---
function Test-EveryPluginPassesHostValidator {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        return @{ Passed = $false; Detail = "the 'claude' CLI is not on PATH, so plugin manifests could not be validated against the host schema. Reporting this as a failure rather than a silent skip: an unavailable checker must never read as a passing check. Install Claude Code, or run this suite on a machine that has it." }
    }

    $packages = @(Get-PluginPackages)
    if ($packages.Count -eq 0) {
        return @{ Passed = $false; Detail = "found zero packages carrying .claude-plugin\plugin.json. Either the packages tree moved or the glob is wrong; a validator that checks nothing must not report success." }
    }

    $broken = [Collections.Generic.List[string]]::new()
    foreach ($package in $packages) {
        $output = & claude plugin validate $package.FullName 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $reason = (($output -split "`n") | Where-Object { $_ -match '>\s*\S' } | ForEach-Object { $_.Trim() }) -join '; '
            $broken.Add("$($package.Name): $reason")
        }
    }
    if ($broken.Count -gt 0) {
        return @{ Passed = $false; Detail = "plugin(s) rejected by 'claude plugin validate': $($broken -join ' | '). Claude Code refuses to load a plugin whose manifest fails this check, so every skill, agent and hook it ships becomes unavailable while the registry still counts it as installed." }
    }
    return @{ Passed = $true; Detail = $null }
}

# --- Behavior 2: the check is not vacuous.
#
# Behavior 1 passing means little unless a genuinely broken manifest is
# rejected. Mutate a real manifest into the exact shape that shipped broken,
# confirm the validator fails it, and restore. Without this, a validator that
# always exited 0 would look identical from the outside. ---
function Test-HostValidatorRejectsABrokenManifest {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        return @{ Passed = $false; Detail = "the 'claude' CLI is not on PATH, so the anti-vacuity mutation could not be run." }
    }

    $package = Get-PluginPackages | Where-Object { $_.Name -eq 'product-experience-engineering' } | Select-Object -First 1
    if (-not $package) {
        return @{ Passed = $false; Detail = 'product-experience-engineering package not found; this mutation targets its agents array specifically.' }
    }
    $manifest = Join-Path $package.FullName '.claude-plugin\plugin.json'
    $pristine = Get-Content -LiteralPath $manifest -Raw

    try {
        # The exact defect that shipped: an array field written as a directory string.
        $mutated = $pristine -replace '(?s)"agents"\s*:\s*\[.*?\]', '"agents": "./agents/"'
        if ($mutated -eq $pristine) {
            return @{ Passed = $false; Detail = "could not mutate the agents array in $manifest -- the field shape changed, so this anti-vacuity check is no longer testing what it claims to." }
        }
        Set-Content -LiteralPath $manifest -Value $mutated -Encoding UTF8 -NoNewline

        $null = & claude plugin validate $package.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Passed = $false; Detail = "'claude plugin validate' accepted a manifest with `"agents`" as a directory string -- the exact shape Claude Code rejects at load time. Behavior 1 therefore proves nothing." }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Set-Content -LiteralPath $manifest -Value $pristine -Encoding UTF8 -NoNewline
    }
}

$r1 = Test-EveryPluginPassesHostValidator
Report 'every AgentHub plugin passes the host schema via claude plugin validate' $r1.Passed $r1.Detail

$r2 = Test-HostValidatorRejectsABrokenManifest
Report 'the host validator rejects a manifest broken the way one actually shipped' $r2.Passed $r2.Detail

if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed, $($reported - $failures.Count) passed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $reported passed, 0 failed" -ForegroundColor Green
exit 0
