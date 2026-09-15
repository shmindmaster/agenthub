#Requires -Version 5.1
<#
Behavior tests for fleet browser MCP servers.

2026-09-07: playwright is no longer persisted in host configs. Live inventory
showed session-start fan-out (six Playwright leaves plus npx/mise wrappers)
with no lazy path. Both playwright (--extension) and chrome-devtools
(--autoConnect) are on-demand-local, plugin-gated via browser-toolkit, and
must not appear in persistedOnDemandLocalMcpIds.

The launched-profile chrome-devtools lock (one $HOME user-data-dir) still
forbids persisting a launched Chrome DevTools profile. --autoConnect attach
does not take that lock.

Neither server may be --headless.

Run: pwsh -NoProfile -File tests/Test-BrowserServer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcpPath  = Join-Path $repoRoot 'registry\mcps.json'
$pkgRoot  = Join-Path $repoRoot 'packages\browser-toolkit'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$conn = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\native-connectors.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$browser = @($mcp.mcpServers | Where-Object { ($_.args -join ' ') -match 'playwright/mcp|chrome-devtools-mcp' })
$ids = @($browser | ForEach-Object { $_.id })

Report 'playwright and chrome-devtools are both registered' `
    (($ids -contains 'playwright') -and ($ids -contains 'chrome-devtools') -and $browser.Count -eq 2) `
    "Found $($browser.Count): $($ids -join ', ')."

$persisted = @($conn.lifecyclePolicy.persistedOnDemandLocalMcpIds)
Report 'no browser MCP is persisted in host config' `
    (('playwright' -notin $persisted) -and ('chrome-devtools' -notin $persisted)) `
    "persistedOnDemandLocalMcpIds still names a browser server: $($persisted -join ', ')."

foreach ($b in $browser) {
    $argLine = ($b.args -join ' ')
    Report "'$($b.id)' is on-demand-local" ([string]$b.activationMode -eq 'on-demand-local') `
        "activationMode is '$($b.activationMode)'; a persisted stdio browser is session-start fan-out."
    Report "'$($b.id)' runs headed" ($argLine -notmatch '--headless') `
        'Headless removes the owner-visible window.'
    Report "'$($b.id)' pins an explicit version" ($argLine -match '@\d') `
        'An unpinned @latest changes tool surface without a recorded pin.'

    $nativeHosts = @('cursor','antigravity','vscode-insiders','cline','claude','codex','qoder','hermes','windsurf','factory')
    $overlap = @($b.hosts | Where-Object { $_ -in $nativeHosts })
    Report "'$($b.id)' eligibility list excludes native-browser hosts" ($overlap.Count -eq 0) `
        "overlaps $($overlap.Count) native-browser host(s): $($overlap -join ', ')."
}

$pw = @($browser | Where-Object { $_.id -eq 'playwright' })[0]
$cd = @($browser | Where-Object { $_.id -eq 'chrome-devtools' })[0]
if ($pw) {
    $pwArgs = ($pw.args -join ' ')
    Report 'playwright attaches via --extension' ($pwArgs -match '--extension') `
        "args are '$pwArgs'; isolated --browser chromium is the session-start lane that was withdrawn."
}
if ($cd) {
    $cdArgs = ($cd.args -join ' ')
    Report 'chrome-devtools attaches via --autoConnect' ($cdArgs -match '--autoConnect') `
        "args are '$cdArgs'; launched-profile default reintroduces the user-data-dir lock."
}

$pluginMcp = Join-Path $pkgRoot '.mcp.json'
$pluginText = Get-Content -LiteralPath $pluginMcp -Raw -Encoding UTF8
Report 'browser-toolkit plugin declares playwright' ($pluginText -match '"playwright"') 'missing playwright in packages/browser-toolkit/.mcp.json'
Report 'browser-toolkit plugin declares chrome-devtools' ($pluginText -match '"chrome-devtools"') 'missing chrome-devtools in packages/browser-toolkit/.mcp.json'
Report 'plugin playwright uses --extension' ($pluginText -match '--extension') 'plugin .mcp.json still launches isolated Chromium'
Report 'plugin chrome-devtools uses --autoConnect' ($pluginText -match '--autoConnect') 'plugin .mcp.json would launch a locked profile'

$aliases = @{}
if ($mcp.migrationAliases) { foreach ($p in $mcp.migrationAliases.PSObject.Properties) { $aliases[$p.Name] = [string]$p.Value } }
Report 'chrome-devtools is a live id, not an alias to playwright' `
    (-not $aliases.ContainsKey('chrome-devtools')) `
    "migrationAliases still maps chrome-devtools to '$($aliases['chrome-devtools'])'."
Report "retired id 'chrome-devtools-isolated' aliases to chrome-devtools" `
    ($aliases.ContainsKey('chrome-devtools-isolated') -and $aliases['chrome-devtools-isolated'] -eq 'chrome-devtools') `
    "migrationAliases maps it to '$($aliases['chrome-devtools-isolated'])'."

# Provider catalog must teach the live Microsoft Playwright MCP vocabulary.
# The 2026-08-19 server swap renamed the skill to use-playwright-mcp while the
# body still documented Chrome DevTools MCP tools; routing tests do not catch
# that because provider-reference catalogs are exempt from post-resolution tool
# name bans. Pin the live names here.
$mcpSkill = Join-Path $pkgRoot 'skills\use-playwright-mcp\SKILL.md'
$mcpText = Get-Content -LiteralPath $mcpSkill -Raw -Encoding UTF8
foreach ($tool in @('browser_navigate', 'browser_snapshot', 'browser_click', 'browser_fill_form', 'browser_tabs', 'browser_console_messages', 'browser_network_requests', 'browser_take_screenshot')) {
    Report ("use-playwright-mcp documents live Playwright MCP tool '{0}'" -f $tool) `
        ($mcpText -match [regex]::Escape($tool)) `
        ("Microsoft @playwright/mcp exposes {0}; the catalog must not keep teaching Chrome DevTools MCP names for this server." -f $tool)
}
$staleTools = @('list_pages', 'take_snapshot', 'fill_form', 'list_console_messages', 'lighthouse_audit')
$staleHits = @()
foreach ($tool in $staleTools) {
    # Mentions are allowed only on retirement/migration lines (same carve-out idea).
    $toolPattern = '`' + [regex]::Escape($tool) + '`'
    $lines = @(Get-Content -LiteralPath $mcpSkill -Encoding UTF8 |
        Where-Object { $_ -match $toolPattern -and $_ -notmatch 'retired|not expose|Do \*\*not\*\*|Do not use|Chrome DevTools MCP' })
    if ($lines.Count -gt 0) { $staleHits += $tool }
}
Report 'use-playwright-mcp does not teach retired Chrome DevTools MCP tool names as live' `
    ($staleHits.Count -eq 0) `
    "still presents as live: $($staleHits -join ', ')"

$cliSkill = Join-Path $pkgRoot 'skills\use-playwright-cli\SKILL.md'
$testSkill = Join-Path $pkgRoot 'skills\use-playwright-test\SKILL.md'
$desktopSkill = Join-Path $pkgRoot 'skills\desktop-evidence\SKILL.md'
$captureHelper = Join-Path $pkgRoot 'scripts\Capture-Screen.ps1'
$evidenceSkill = Join-Path $pkgRoot 'skills\browser-evidence\SKILL.md'
Report 'use-playwright-cli provider catalog exists' (Test-Path -LiteralPath $cliSkill) 'missing skills/use-playwright-cli/SKILL.md'
Report 'use-playwright-test provider catalog exists' (Test-Path -LiteralPath $testSkill) 'missing skills/use-playwright-test/SKILL.md'
Report 'desktop-evidence provider catalog exists' (Test-Path -LiteralPath $desktopSkill) 'missing skills/desktop-evidence/SKILL.md'
Report 'Capture-Screen.ps1 helper exists' (Test-Path -LiteralPath $captureHelper) 'missing scripts/Capture-Screen.ps1'
$evidenceText = Get-Content -LiteralPath $evidenceSkill -Raw -Encoding UTF8
Report 'browser-evidence routes desktop targets to desktop-evidence' `
    ($evidenceText -match '`desktop-evidence`') `
    'browser-evidence must name desktop-evidence so a desktop capture request does not stay on a browser lane'
Report 'browser-evidence requires Playwright CLI for session video' `
    ($evidenceText -match 'Session video' -and $evidenceText -match 'use-playwright-cli') `
    'session video must be the CLI lane; fleet Playwright MCP does not pass --caps=devtools'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
