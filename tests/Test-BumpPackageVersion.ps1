#Requires -Version 5.1
<#
Bump-PackageVersion.ps1 must move every versioned manifest a package carries, and
every package in this checkout must agree with its own root plugin.json.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$bump = Join-Path $repoRoot 'scripts/Bump-PackageVersion.ps1'
$manifests = @(
    'plugin.json',
    '.claude-plugin/plugin.json',
    '.codex-plugin/plugin.json',
    '.cursor-plugin/plugin.json',
    '.qoder-plugin/plugin.json',
    '.antigravity-plugin/plugin.json',
    'gemini-extension.json'
)

$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name -- $Detail" }
}
function Read-Version([string]$Path) {
    [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json).version
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) "bump-package-$([guid]::NewGuid().ToString('N'))"
try {
    $package = Join-Path $scratch 'packages/sample'
    foreach ($relative in $manifests) {
        $path = Join-Path $package $relative
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
        Set-Content -LiteralPath $path -Value '{ "name": "sample", "version": "1.0.0", "description": "synthetic" }' -Encoding UTF8
    }

    $null = & pwsh -NoProfile -File $bump -Package sample -Version 1.0.1 -RepositoryRoot $scratch 2>&1
    Report 'the bump exits zero on a package with every manifest type' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
    $stale = @($manifests | Where-Object { (Read-Version (Join-Path $package $_)) -ne '1.0.1' })
    Report 'the bump moves every versioned manifest' ($stale.Count -eq 0) ($stale -join ', ')

    $gemini = Get-Content -LiteralPath (Join-Path $package 'gemini-extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Report 'the bump keeps the other fields of an extension manifest' ($gemini.description -eq 'synthetic') 'description lost'

    $checked = 0
    $skew = [Collections.Generic.List[string]]::new()
    foreach ($packagesDir in @((Join-Path $repoRoot 'packages'), (Join-Path $repoRoot 'overlays/personal/packages'))) {
        if (-not (Test-Path -LiteralPath $packagesDir -PathType Container)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $packagesDir -Directory)) {
            $rootManifest = Join-Path $dir.FullName 'plugin.json'
            if (-not (Test-Path -LiteralPath $rootManifest)) { continue }
            $authority = Read-Version $rootManifest
            foreach ($relative in $manifests) {
                $path = Join-Path $dir.FullName $relative
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $checked++
                $version = Read-Version $path
                if ($version -ne $authority) { $skew.Add("$($dir.Name)/$relative is $version, root is $authority") }
            }
        }
    }
    Report 'the repository check covered real manifests' ($checked -gt 0) 'no manifest was read'
    Report 'every package manifest agrees with its root plugin.json' ($skew.Count -eq 0) ($skew -join '; ')
}
finally {
    if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}

Write-Output "RESULT: $passed passed, $failed failed"
exit ([int]($failed -gt 0))
