#Requires -Version 5.1
<#
Behavior tests for the fleet's single browser MCP server.

History this pins, because both decisions were reversed once already:
- The registry carried TWO chrome-devtools-mcp entries differing only by profile
  flag. They could never be merged at runtime -- the package declares
  conflicts:['isolated','executablePath'] on autoConnect -- so they collapsed to
  one entry using the default persistent profile (2026-08-19).
- That entry was then replaced by Playwright MCP the same day. The reason is
  structural, not preference: chrome-devtools keeps its persistent profile at a
  single path under $HOME, Chrome permits one browser per user-data-dir, and
  every host on this workstation shares one $HOME. Fanning it across hosts means
  the first host to open a browser takes the lock and the rest fail at launch.
  Playwright derives its profile from the workspace hash, so per-host processes
  cannot collide.

The browser must also stay HEADED. The whole point is that the owner can watch a
run and take over; --headless silently removes that.

Run: pwsh -NoProfile -File tests/Test-BrowserServer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcpPath  = Join-Path $repoRoot 'registry\mcps.json'
$pkgRoot  = Join-Path $repoRoot 'packagesrowser-toolkit'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$browser = @($mcp.mcpServers | Where-Object { ($_.args -join ' ') -match 'playwright/mcp|chrome-devtools-mcp' })

Report 'exactly one browser MCP server is registered' ($browser.Count -eq 1) `
    "Found $($browser.Count): $(($browser | ForEach-Object { $_.id }) -join ', ')."

Report 'the browser-server matcher found a server at all' ($browser.Count -gt 0) `
    'No registry entry matched a browser MCP package; every check below would be vacuous.'

foreach ($b in $browser) {
    $argLine = ($b.args -join ' ')
    Report "'$($b.id)' is Playwright, not chrome-devtools" ($argLine -match 'playwright/mcp') `
        'chrome-devtools cannot be fanned across hosts: one persistent profile dir, one browser at a time, one shared $HOME.'
    Report "'$($b.id)' runs headed" ($argLine -notmatch '--headless') `
        'Headless removes the owner-visible window this server was chosen to provide.'
    Report "'$($b.id)' pins an explicit version" ($argLine -match '@playwright/mcp@\d') `
        'An unpinned @latest changes tool surface without a recorded protocol re-verification.'

    # Scope must exclude hosts with a native browser, or the fleet pays for a
    # process it never needed. Verified 2026-08-19 from vendor docs plus local
    # evidence for each host.
    $nativeHosts = @('cursor','antigravity','vscode-insiders','cline','claude','codex','qoder','hermes','windsurf','factory')
    $overlap = @($b.hosts | Where-Object { $_ -in $nativeHosts })
    Report "'$($b.id)' is not registered to hosts with a native browser" ($overlap.Count -eq 0) `
        "overlaps $($overlap.Count) native-browser host(s): $($overlap -join ', ')."

    Report "'$($b.id)' targets at least one host" (@($b.hosts).Count -gt 0) `
        'A browser server scoped to nobody provides nothing.'
}

# A routing skill naming a retired id sends an agent to a server that no longer
# exists. Documenting the retirement is the opposite, so the carve-out keys off
# retirement vocabulary on the same line and is deliberately narrow.
$retirementMarkers = 'retired|migrationAlias|resolves to|replaced'
$stale = @()
foreach ($file in Get-ChildItem -LiteralPath $pkgRoot -Recurse -File -Include '*.md', '*.json' -ErrorAction SilentlyContinue) {
    $routing = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 |
        Where-Object { $_ -match 'chrome-devtools' -and $_ -notmatch $retirementMarkers })
    if ($routing.Count -gt 0) { $stale += ('{0} ({1} line(s))' -f $file.FullName.Substring($repoRoot.Length + 1), $routing.Count) }
}
Report 'no browser-toolkit content still routes to the retired chrome-devtools id' ($stale.Count -eq 0) `
    "$($stale.Count) file(s) still route to chrome-devtools: $($stale -join '; ')"

# The retired ids must still RESOLVE, so a host config carrying one is migrated
# rather than pruned as unknown.
$aliases = @{}
if ($mcp.migrationAliases) { foreach ($p in $mcp.migrationAliases.PSObject.Properties) { $aliases[$p.Name] = [string]$p.Value } }
foreach ($old in @('chrome-devtools', 'chrome-devtools-isolated')) {
    Report "retired id '$old' resolves to the current browser server" `
        ($aliases.ContainsKey($old) -and $aliases[$old] -eq 'playwright') `
        "migrationAliases maps it to '$($aliases[$old])'; without this, prune deletes it from any host config that still carries it."
}

# The carve-out must not be a blanket pass.
$probe = 'Use `chrome-devtools` for QA runs.'
Report 'a live routing line is still caught by the stale-reference check' `
    ($probe -match 'chrome-devtools' -and $probe -notmatch $retirementMarkers) `
    'The retirement carve-out swallowed an ordinary routing instruction.'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
