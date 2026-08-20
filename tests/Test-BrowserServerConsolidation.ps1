#Requires -Version 5.1
<#
Behavior tests for the single-browser-server decision (2026-08-19).

Why: the registry carried two chrome-devtools-mcp registrations that differed
only by profile flag -- `--autoConnect` (attach to the owner's real Chrome) and
`--isolated` (temporary profile, wiped on close). Both are edge cases. Read the
package's own CLI options: `userDataDir` defaults to
$HOME/.cache/chrome-devtools-mcp/chrome-profile, so invoking the server with
NEITHER flag already yields a dedicated profile that is separate from personal
Chrome and whose logins persist across sessions. That is the mode the fleet
actually wants, so the two entries collapse into one that passes neither flag.

`--isolated` was not merely redundant, it was hostile to the common case: it
discards cookies on every close, so every signed-in task re-authenticates.
`--autoConnect` required a manual chrome://inspect enable plus an Allow click
and exposed every open tab of the owner's profile.

These tests pin the decision so a future edit cannot silently reintroduce the
split or bolt a profile flag back onto the surviving entry.

Same accumulate-and-report idiom as the sibling suites; exit 1 on failure.

Run: pwsh -NoProfile -File tests/Test-BrowserServerConsolidation.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcpPath  = Join-Path $repoRoot 'registry\mcps.json'
$pkgRoot  = Join-Path $repoRoot 'packages\browser-toolkit'

$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
$browser = @($mcp.mcpServers | Where-Object {
    ($_.args -join ' ') -match 'chrome-devtools-mcp'
})

Report 'exactly one chrome-devtools-mcp server is registered' ($browser.Count -eq 1) `
    "Found $($browser.Count): $(($browser | ForEach-Object { $_.id }) -join ', '). The profile-flag split was retired; one entry uses the persistent default profile."

foreach ($b in $browser) {
    $argLine = ($b.args -join ' ')
    Report "'$($b.id)' does not pass --isolated" ($argLine -notmatch '--isolated') `
        'A temporary profile is wiped on close, forcing re-login on every signed-in task.'
    Report "'$($b.id)' does not pass --autoConnect" ($argLine -notmatch '--autoConnect') `
        'autoConnect needs a manual chrome://inspect enable and exposes every tab of the personal profile.'
}

# The retired id must not survive anywhere a router could still resolve it: a
# skill naming it as a target would send an agent to a server that no longer
# exists. Documenting the retirement is the opposite -- an agent that greps the
# dead id SHOULD land on the line explaining where it went -- so a line that
# marks the id as retired, or points at the migrationAliases entry that
# redirects it, is not a routing reference. The carve-out is deliberately
# narrow: it keys off the retirement vocabulary on the same line, so a live
# `Use chrome-devtools-isolated` instruction cannot slip through it.
$retirementMarkers = 'retired|migrationAlias|resolves to'
$stale = @()
if (Test-Path -LiteralPath $pkgRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $pkgRoot -Recurse -File -Include '*.md', '*.json' -ErrorAction SilentlyContinue) {
        $routing = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 |
            Where-Object { $_ -match 'chrome-devtools-isolated' -and $_ -notmatch $retirementMarkers })
        if ($routing.Count -gt 0) {
            $stale += ('{0} ({1} line(s))' -f $file.FullName.Substring($repoRoot.Length + 1), $routing.Count)
        }
    }
}
Report 'no browser-toolkit content still routes to the retired isolated id' ($stale.Count -eq 0) `
    "$($stale.Count) file(s) still route to chrome-devtools-isolated: $($stale -join '; ')"

# The carve-out must not be a blanket pass: a live routing line must still be
# caught even in a file that also carries a retirement note.
$probe = 'Use `chrome-devtools-isolated` for QA runs.'
Report 'a live routing line is still caught by the stale-reference check' `
    ($probe -match 'chrome-devtools-isolated' -and $probe -notmatch $retirementMarkers) `
    'The retirement carve-out swallowed an ordinary routing instruction.'

# The guard must be able to fail: the matcher has to actually find the server,
# otherwise every assertion above would pass vacuously on an empty set.
Report 'the browser-server matcher finds a server at all' ($browser.Count -gt 0) `
    'No registry entry matched chrome-devtools-mcp; the checks above proved nothing.'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: all browser-server consolidation checks passed' -ForegroundColor Green
exit 0
