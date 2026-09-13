#Requires -Version 5.1
<#
The public-core export must omit private packages, the personal overlay,
and owner-specific path residue in the control plane. It must not push.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$exportScript = Join-Path $repoRoot 'scripts\Export-PublicCore.ps1'

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

function Test-ExportOmitsPersonalSurface {
    if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) {
        $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath()
    }
    $dest = Join-Path $env:AGENTHUB_TEST_SCRATCH ('agenthub-public-core-' + [guid]::NewGuid())
    try {
        $output = & pwsh -NoProfile -File $exportScript -Destination $dest 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "export exited $LASTEXITCODE. $output" }
        }
        $missing = @()
        foreach ($relative in @('LICENSE', 'policy-core.md', 'scripts\lib\PathBinding.ps1', 'CONTRIBUTING.md', 'SECURITY.md')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dest $relative))) { $missing += $relative }
        }
        if ($missing.Count -gt 0) {
            return @{ Passed = $false; Detail = "export missing: $($missing -join ', ')" }
        }
        $forbidden = @(
            'packages\sarosh-communication',
            'overlays\personal',
            'global-agent-policy.md'
        )
        $present = @($forbidden | Where-Object { Test-Path -LiteralPath (Join-Path $dest $_) })
        if ($present.Count -gt 0) {
            return @{ Passed = $false; Detail = "export still contains: $($present -join ', ')" }
        }
        $caps = Get-Content -LiteralPath (Join-Path $dest 'registry\capabilities.json') -Raw -Encoding UTF8
        if ($caps -match 'sarosh-communication') {
            return @{ Passed = $false; Detail = 'exported capabilities.json still names sarosh-communication' }
        }
        $agents = Get-Content -LiteralPath (Join-Path $dest 'registry\agents.json') -Raw -Encoding UTF8
        if ($agents -match 'SaroshHussain') {
            return @{ Passed = $false; Detail = 'exported agents.json still contains a machine username' }
        }
        $marketplace = Join-Path $dest '.agents\plugins\marketplace.json'
        if (Test-Path -LiteralPath $marketplace) {
            $market = Get-Content -LiteralPath $marketplace -Raw -Encoding UTF8
            if ($market -match '"linkedin"') {
                return @{ Passed = $false; Detail = 'public marketplace still lists linkedin' }
            }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$result = Test-ExportOmitsPersonalSurface
Report 'public-core export omits private packages, overlay, and owner path residue' ([bool]$result.Passed) ([string]$result.Detail)

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
