#Requires -Version 5.1
<#
Behavior tests for the fleet browser lane after the 2026-10-29 retirement.

Owner direction 2026-10-29: Playwright MCP and Chrome DevTools MCP are retired,
including the isolated alias. No browser MCP is registered in registry/mcps.json;
every host uses its own first-party browser. Playwright CLI and Playwright Test
remain the repeatable non-MCP lanes. The use-playwright-mcp catalog documented
tools for a server the fleet no longer runs, so it is retired with the server.

This suite asserts the retirement is complete and stays complete: no server,
package, alias, plugin manifest or skill may bring a browser MCP back, and the
browser capability itself must still be declared so the lane is not silently
dropped.

Run: pwsh -NoProfile -File tests/Test-BrowserServer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcpPath  = Join-Path $repoRoot 'registry\mcps.json'
$capPath  = Join-Path $repoRoot 'registry\capabilities.json'
$pkgRoot  = Join-Path $repoRoot 'packages\browser-toolkit'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp  = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$caps = Get-Content -LiteralPath $capPath -Raw -Encoding UTF8 | ConvertFrom-Json
$conn = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# --- The retirement itself. ---
$retiredIds = @($mcp.retiredMcpIds | ForEach-Object { [string]$_ })
Report 'playwright is a retired MCP id' ($retiredIds -contains 'playwright') "retiredMcpIds: $($retiredIds -join ', ')"
Report 'mcp-playwright is a retired MCP id' ($retiredIds -contains 'mcp-playwright') "retiredMcpIds: $($retiredIds -join ', ')"
$retiredPkgs = @($mcp.retiredMcpPackages | ForEach-Object { [string]$_ })
Report '@playwright/mcp is a retired package' ($retiredPkgs -contains '@playwright/mcp') "retiredMcpPackages: $($retiredPkgs -join ', ')"

# --- Nothing may register a browser MCP server again. ---
$browser = @($mcp.mcpServers | Where-Object {
    ([string]$_.id) -in @('playwright', 'mcp-playwright', 'chrome-devtools', 'chrome-devtools-isolated') -or
    ((@($_.command) + @($_.args)) -join ' ') -match 'playwright/mcp|chrome-devtools-mcp'
})
Report 'no browser MCP server is registered' ($browser.Count -eq 0) "Found $($browser.Count): $(@($browser | ForEach-Object { $_.id }) -join ', ')"

$persisted = @($conn.lifecyclePolicy.persistedOnDemandLocalMcpIds)
Report 'no browser MCP is persisted in host config' `
    (('playwright' -notin $persisted) -and ('chrome-devtools' -notin $persisted)) `
    "persistedOnDemandLocalMcpIds still names a browser server: $($persisted -join ', ')."

$aliases = @{}
if ($mcp.migrationAliases) { foreach ($p in $mcp.migrationAliases.PSObject.Properties) { $aliases[$p.Name] = [string]$p.Value } }
foreach ($key in @('chrome-devtools', 'chrome-devtools-isolated', 'mcp-playwright')) {
    Report "migrationAliases does not map '$key'" (-not $aliases.ContainsKey($key)) "migrationAliases maps '$key' to '$($aliases[$key])'."
}

# --- Plugins carry no MCP declarations; the registry is the single source. ---
$pluginMcp = Join-Path $pkgRoot '.mcp.json'
$pluginManifest = Get-Content -LiteralPath $pluginMcp -Raw -Encoding UTF8 | ConvertFrom-Json
$pluginServerCount = @($pluginManifest.mcpServers.PSObject.Properties).Count
Report 'browser-toolkit plugin declares no MCP servers' ($pluginServerCount -eq 0) "packages/browser-toolkit/.mcp.json declares $pluginServerCount server(s)"
$pluginText = Get-Content -LiteralPath $pluginMcp -Raw -Encoding UTF8
Report 'plugin manifest references no browser MCP package' ($pluginText -notmatch 'playwright/mcp|chrome-devtools-mcp') 'plugin still references a retired browser package'

# --- The lane must still exist as a declared capability. ---
$cap = @($caps.capabilities | Where-Object { $_.id -eq 'browser-toolkit' })[0]
Report 'browser-toolkit capability package still exists' ($null -ne $cap) 'capabilities.json lost the browser-toolkit package'
if ($cap) {
    $provides = @($cap.provides)
    Report 'browser.isolated is still declared' ($provides -contains 'browser.isolated') "provides: $($provides -join ', ')"
    Report 'browser.authenticated is still declared' ($provides -contains 'browser.authenticated') "provides: $($provides -join ', ')"
    Report 'browserProviderPolicy names the 2026-10-29 retirement' ([string]$cap.browserProviderPolicy -match '2026-10-29' -and [string]$cap.browserProviderPolicy -match 'no browser MCP') 'policy must state the retirement and that no browser MCP is registered'
}

# --- The retired catalog is gone and the surviving lanes are intact. ---
$retiredSkills = @($cap.retiredSkillNames)
Report 'use-playwright-mcp is recorded as retired' ($retiredSkills -contains 'use-playwright-mcp') "retiredSkillNames: $($retiredSkills -join ', ')"
Report 'use-playwright-mcp catalog is removed' (-not (Test-Path -LiteralPath (Join-Path $pkgRoot 'skills\use-playwright-mcp'))) 'skills/use-playwright-mcp still exists'
$managed = @($cap.managedSkillNames)
Report 'use-playwright-mcp is not a managed skill' ($managed -notcontains 'use-playwright-mcp') 'managedSkillNames still lists the retired catalog'

$cliSkill = Join-Path $pkgRoot 'skills\use-playwright-cli\SKILL.md'
$testSkill = Join-Path $pkgRoot 'skills\use-playwright-test\SKILL.md'
$desktopSkill = Join-Path $pkgRoot 'skills\desktop-evidence\SKILL.md'
$captureHelper = Join-Path $pkgRoot 'scripts\Capture-Screen.ps1'
$evidenceSkill = Join-Path $pkgRoot 'skills\browser-evidence\SKILL.md'
Report 'use-playwright-cli provider catalog exists' (Test-Path -LiteralPath $cliSkill) 'missing skills/use-playwright-cli/SKILL.md'
Report 'use-playwright-test provider catalog exists' (Test-Path -LiteralPath $testSkill) 'missing skills/use-playwright-test/SKILL.md'
Report 'desktop-evidence provider catalog exists' (Test-Path -LiteralPath $desktopSkill) 'missing skills/desktop-evidence/SKILL.md'
Report 'Capture-Screen.ps1 helper exists' (Test-Path -LiteralPath $captureHelper) 'missing scripts/Capture-Screen.ps1'

foreach ($routing in @('browser-debugging', 'browser-evidence', 'interactive-browser-testing')) {
    $text = Get-Content -LiteralPath (Join-Path $pkgRoot "skills\$routing\SKILL.md") -Raw -Encoding UTF8
    Report "$routing routes to the CLI lane, not a browser MCP" `
        ($text -match '`use-playwright-cli`' -and $text -notmatch '`use-playwright-mcp`') `
        'routing skill still names the retired MCP catalog or does not name the CLI fallback'
}

$evidenceText = Get-Content -LiteralPath $evidenceSkill -Raw -Encoding UTF8
Report 'browser-evidence routes desktop targets to desktop-evidence' `
    ($evidenceText -match '`desktop-evidence`') `
    'browser-evidence must name desktop-evidence so a desktop capture request does not stay on a browser lane'
Report 'browser-evidence requires Playwright CLI for session video' `
    ($evidenceText -match 'Session video' -and $evidenceText -match 'use-playwright-cli') `
    'session video must be the CLI lane'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
