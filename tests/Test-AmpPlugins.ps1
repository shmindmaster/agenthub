#Requires -Version 7
<#
Behavior test for scripts/Install-AmpPlugins.py.

Amp cannot read a package directly, so the installer generates each plugin. Two
mistakes here fail silently in a real session: a ${env:VAR} reference, which Amp
sends literally, and a linked folder, which Amp rejects. This builds into a temp
folder and checks the generated output, and it needs no Amp install.

Run: pwsh -NoProfile -File tests/Test-AmpPlugins.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot 'scripts/Install-AmpPlugins.py'
$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$target = Join-Path ([IO.Path]::GetTempPath()) "amp-plugins-$PID"
try {
    $names = 'ah-linear', 'ah-context7', 'ah-firecrawl', 'ah-brave-search', 'ah-aws', 'ah-repowise'
    $output = & python $installer --target $target @names 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "installer failed: $output"

    foreach ($name in $names) {
        $plugin = Join-Path $target $name
        Assert-True (Test-Path -LiteralPath (Join-Path $plugin 'index.ts')) "$name has no index.ts"
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $plugin '.claude-plugin'))) "$name kept a host manifest"
        $links = @(Get-ChildItem -LiteralPath $plugin -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        Assert-True ($links.Count -eq 0) "$name contains links, which Amp rejects"
        $registered = @(Select-String -LiteralPath (Join-Path $plugin 'index.ts') -Pattern 'registerSkill').Count
        Assert-True ($registered -gt 0) "$name registers no skill"
    }

    $carriers = @(Get-ChildItem -LiteralPath $target -Recurse -Filter 'mcp.json')
    Assert-True ($carriers.Count -ge 3) "expected a server carrier for linear, context7 and firecrawl, found $($carriers.Count)"
    foreach ($carrier in $carriers) {
        $text = Get-Content -LiteralPath $carrier.FullName -Raw -Encoding utf8
        Assert-True ($text -notmatch '\$\{env:') "$($carrier.FullName) uses `${env:VAR}, which Amp sends literally"
    }

    foreach ($carrier in $carriers) {
        $commandServers = @((Get-Content -LiteralPath $carrier.FullName -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Value.command })
        Assert-True ($commandServers.Count -eq 0) "$($carrier.FullName) starts a local process, and Amp cannot switch it off"
    }

    $context7 = Get-Content -LiteralPath (Join-Path $target 'ah-context7/skills/docs/mcp.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($null -ne $context7.context7.headers.CONTEXT7_API_KEY) 'context7 lost its key header'
    $firecrawl = Get-Content -LiteralPath (Join-Path $target 'ah-firecrawl/skills/scrape/mcp.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($firecrawl.firecrawl.url -like '*/v2/mcp') 'firecrawl must use the key endpoint, not the OAuth one'
} finally {
    if (Test-Path -LiteralPath $target) { [IO.Directory]::Delete($target, $true) }
}

Write-Host "Test-AmpPlugins: passed=$passed failed=$($failures.Count)"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "  FAIL: $_" }
    exit 1
}
exit 0
