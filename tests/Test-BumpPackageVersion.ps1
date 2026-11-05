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

    # The bump edits a version, it does not reformat a file. Everything above compares parsed values, so a
    # writer that round-trips through ConvertTo-Json passes all of it while re-emitting the manifest at
    # four-space indent with "key":  value spacing and CRLF endings. Measured 2026-11-05: that turned a
    # one-field bump into a whole-file diff on all seven manifests of two packages and churned their
    # content hashes. This fixture carries nested objects and arrays, the layout such a writer changes.
    function Test-OnlyVersionMoved([string]$Label, [string]$Before, [string]$After, $Problems) {
        $nlBefore = if ($Before -match "`r`n") { 'CRLF' } else { 'LF' }
        $nlAfter = if ($After -match "`r`n") { 'CRLF' } else { 'LF' }
        if ($nlBefore -ne $nlAfter) { $Problems.Add("$Label changed newline style $nlBefore -> $nlAfter") }
        $b = $Before -split "`r?`n"
        $a = $After -split "`r?`n"
        if ($b.Count -ne $a.Count) { $Problems.Add("$Label changed line count $($b.Count) -> $($a.Count)"); return }
        for ($i = 0; $i -lt $b.Count; $i++) {
            if ($b[$i] -eq $a[$i]) { continue }
            $isVersionEdit = ($b[$i] -match '^\s*"version"\s*:\s*"') -and ($a[$i] -match '^\s*"version"\s*:\s*"')
            if (-not $isVersionEdit) { $Problems.Add("$Label rewrote line $($i+1)") }
        }
    }

    $prettyLines = @(
        '{',
        '  "name": "pretty",',
        '  "version": "1.0.0",',
        '  "description": "synthetic",',
        '  "author": {',
        '    "name": "Someone"',
        '  },',
        '  "keywords": [',
        '    "alpha",',
        '    "beta"',
        '  ]',
        '}'
    ) -join "`n"
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    foreach ($relative in @('plugin.json', '.claude-plugin/plugin.json')) {
        $path = Join-Path $scratch "packages/pretty/$relative"
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
        [IO.File]::WriteAllText($path, $prettyLines, $utf8NoBom)
    }
    $beforePretty = @{}
    foreach ($relative in @('plugin.json', '.claude-plugin/plugin.json')) {
        $beforePretty[$relative] = [IO.File]::ReadAllText((Join-Path $scratch "packages/pretty/$relative"))
    }
    $null = & pwsh -NoProfile -File $bump -Package pretty -Version 2.0.1 -RepositoryRoot $scratch 2>&1
    $reflow = [Collections.Generic.List[string]]::new()
    foreach ($relative in @('plugin.json', '.claude-plugin/plugin.json')) {
        $after = [IO.File]::ReadAllText((Join-Path $scratch "packages/pretty/$relative"))
        Test-OnlyVersionMoved $relative $beforePretty[$relative] $after $reflow
        Report "the bump still sets the version in $relative" ((Read-Version (Join-Path $scratch "packages/pretty/$relative")) -eq '2.0.1') 'version not moved'
    }
    Report 'the bump edits only the version line and leaves the rest of the file byte-identical' `
        ($reflow.Count -eq 0) ($reflow -join '; ')

    # A guard that cannot fire is not a guard: the same comparison must reject the exact two ways the old
    # writer damaged a manifest, a re-indent and a CRLF conversion.
    $reflowGuard = [Collections.Generic.List[string]]::new()
    $reIndented = ($beforePretty['plugin.json'] -split "`n" | ForEach-Object { $_ -replace '^  ', '    ' }) -join "`n"
    Test-OnlyVersionMoved 'fixture' $beforePretty['plugin.json'] $reIndented $reflowGuard
    $crlfGuard = [Collections.Generic.List[string]]::new()
    Test-OnlyVersionMoved 'fixture' $beforePretty['plugin.json'] ($beforePretty['plugin.json'] -replace "`n", "`r`n") $crlfGuard
    Report 'the layout guard rejects a re-indented and a CRLF-converted manifest' `
        (($reflowGuard.Count -gt 0) -and ($crlfGuard.Count -gt 0)) 'the guard cannot see a reflow'
}
finally {
    if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}

Write-Output "RESULT: $passed passed, $failed failed"
exit ([int]($failed -gt 0))
