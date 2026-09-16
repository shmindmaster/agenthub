#Requires -Version 5.1
<#
The public-core export must omit private packages, the personal overlay,
and owner-specific path residue in the control plane. It must not push.
It must ship the example overlay, quickstart, and package.json CLI entry, and
the exported init -> validate workflow must execute successfully without sync.
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
        foreach ($relative in @(
            'LICENSE',
            'policy-core.md',
            'scripts\lib\PathBinding.ps1',
            'CONTRIBUTING.md',
            'SECURITY.md',
            'package.json',
            'scripts\agenthub-cli.mjs',
            'overlays\personal.example\overlay.json',
            'docs\development\quickstart.md',
            'README.md'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $dest $relative))) { $missing += $relative }
        }
        if ($missing.Count -gt 0) {
            return @{ Passed = $false; Detail = "export missing: $($missing -join ', ')" }
        }
        $forbidden = @(
            'packages\sarosh-communication',
            'overlays\personal',
            'global-agent-policy.md',
            'scripts\Export-PublicCore.ps1',
            'registry\product-video-delivery.json',
            'registry\repo-standard.json',
            'registry\mobile-scope.json'
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
        $readme = Get-Content -LiteralPath (Join-Path $dest 'README.md') -Raw -Encoding UTF8
        if ($readme -match 'SaroshHussain|D:\\Local-AI|MahumTech') {
            return @{ Passed = $false; Detail = 'exported README still contains personal residue' }
        }
        if ($readme -notmatch 'node \./scripts/agenthub-cli\.mjs init') {
            return @{ Passed = $false; Detail = 'exported README missing first-click init command' }
        }
        $marketplace = Join-Path $dest '.agents\plugins\marketplace.json'
        if (Test-Path -LiteralPath $marketplace) {
            $market = Get-Content -LiteralPath $marketplace -Raw -Encoding UTF8
            if ($market -match '"linkedin"') {
                return @{ Passed = $false; Detail = 'public marketplace still lists linkedin' }
            }
        }
        $gi = Get-Content -LiteralPath (Join-Path $dest '.gitignore') -Raw -Encoding UTF8
        if ($gi -notmatch 'overlays/personal/') {
            return @{ Passed = $false; Detail = 'exported .gitignore does not ignore overlays/personal/' }
        }

        # Model a recipient's Git checkout. Hash validation deliberately uses
        # tracked files, never an untracked filesystem walk. No commit or host
        # synchronization is needed to establish this synthetic index.
        $gitOutput = & git -C $dest init --quiet 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "synthetic checkout init failed: $gitOutput" }
        }
        $gitOutput = & git -C $dest -c core.autocrlf=false add --all 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "synthetic checkout indexing failed: $gitOutput" }
        }
        $entry = Join-Path $dest 'scripts\AgentHub.ps1'
        $syntheticProfile = Join-Path $dest 'synthetic-user-profile'
        $initOutput = & pwsh -NoProfile -File $entry init -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "exported init failed: $initOutput" }
        }
        foreach ($relative in @('agenthub.profile.json', 'overlays\personal\overlay.json')) {
            if (-not (Test-Path -LiteralPath (Join-Path $dest $relative))) {
                return @{ Passed = $false; Detail = "exported init did not create $relative" }
            }
        }
        if (Test-Path -LiteralPath $syntheticProfile) {
            return @{ Passed = $false; Detail = 'init wrote into the synthetic host profile' }
        }
        $validateOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $validateOutput -notmatch 'PASS:') {
            return @{ Passed = $false; Detail = "exported init -> validate failed: $validateOutput" }
        }
        if (Test-Path -LiteralPath $syntheticProfile) {
            return @{ Passed = $false; Detail = 'validate wrote into the synthetic host profile' }
        }

        $capPath = Join-Path $dest 'registry\capabilities.json'
        $publicCaps = Get-Content -LiteralPath $capPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($publicCaps.distribution -ne 'public-core') {
            return @{ Passed = $false; Detail = 'export lacks its public-core distribution declaration' }
        }

        # A public export still runs real content-hash validation.
        $originalHash = $publicCaps.capabilities[0].contentHash
        $publicCaps.capabilities[0].contentHash = 'synthetic-invalid-hash'
        $publicCaps | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $capPath -Encoding UTF8
        $invalidOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $invalidOutput -notmatch 'contentHash drift:') {
            return @{ Passed = $false; Detail = "public validation accepted hash drift: $invalidOutput" }
        }
        $publicCaps.capabilities[0].contentHash = $originalHash
        $publicCaps | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $capPath -Encoding UTF8

        # A marker cannot conceal canonical fleet inputs.
        $compiledPolicy = Join-Path $dest 'global-agent-policy.md'
        Set-Content -LiteralPath $compiledPolicy -Value '# Synthetic compiled policy' -Encoding UTF8
        $mixedOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        Remove-Item -LiteralPath $compiledPolicy -Force
        if ($LASTEXITCODE -eq 0 -or $mixedOutput -notmatch 'public-core distribution contains private fleet input') {
            return @{ Passed = $false; Detail = "public marker bypassed private fleet validation: $mixedOutput" }
        }

        # No marker means canonical validation, including missing and wrong-size
        # delivery registries. These are synthetic records, never private data.
        $publicCaps.PSObject.Properties.Remove('distribution')
        $publicCaps | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $capPath -Encoding UTF8
        $missingOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $missingOutput -notmatch 'product video delivery registry must contain seven products') {
            return @{ Passed = $false; Detail = "canonical mode accepted missing delivery registry: $missingOutput" }
        }
        $deliveryPath = Join-Path $dest 'registry\product-video-delivery.json'
        @{ products = @(1..6 | ForEach-Object { @{ id = "synthetic-product-$_" } }) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $deliveryPath -Encoding UTF8
        $countOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $countOutput -notmatch 'product video delivery registry must contain seven products') {
            return @{ Passed = $false; Detail = "canonical mode accepted six delivery products: $countOutput" }
        }
        @{ products = @(1..7 | ForEach-Object { @{ id = "synthetic-product-$_" } }) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $deliveryPath -Encoding UTF8
        $canonicalOutput = & pwsh -NoProfile -File $entry validate -UserProfile $syntheticProfile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return @{ Passed = $false; Detail = "canonical mode rejected seven synthetic products: $canonicalOutput" }
        }
        return @{ Passed = $true; Detail = $null }
    } finally {
        $scratchPrefix = [IO.Path]::GetFullPath($env:AGENTHUB_TEST_SCRATCH).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not [IO.Path]::GetFullPath($dest).StartsWith($scratchPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing cleanup outside the test scratch directory'
        }
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$result = Test-ExportOmitsPersonalSurface
Report 'public-core export preserves privacy, runs init -> validate, and retains canonical validation gates' ([bool]$result.Passed) ([string]$result.Detail)

Write-Host ''
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
