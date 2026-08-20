#Requires -Version 5.1
<#
Behavior test: a persisted MCP declaration must exist in the host's config.

Why: three registry audits converged on one root cause -- `hosts` arrays are
written as intent and read as fact, and nothing compared them to deployed
configuration. Reported symptoms included repowise-workspace declaring five
hosts, railway declaring two, and brave-search recording declaredByHostCount:1
against zero real declarations. Test-LocalMcpHostScope only checks that a named
host EXISTS; Test-RegistryHostReferences only checks that host ids RESOLVE.
Neither opens the host's config.

The rule is deliberately narrow, because not every declaration is written to a
config:

  - shared-remote servers are persisted, so a declared host must carry them.
  - on-demand-local servers are persisted ONLY if named in
    native-connectors.json lifecyclePolicy.persistedOnDemandLocalMcpIds.
    Anything else is delivered by a plugin or gated behind explicit
    activation, and its `hosts` array is an ELIGIBILITY list rather than a
    deployment claim -- appium-mobile is the worked example, deliberately
    absent from every config since 2026-08-20.

Asserting deployment for the gated ones would re-create exactly the per-session
process cost that gating removed, so this file must not do that.

Run: pwsh -NoProfile -File tests/Test-DeclaredVsDeployedMcp.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

function Read-Json([string]$RelPath) {
    Get-Content -LiteralPath (Join-Path $repoRoot $RelPath) -Raw -Encoding UTF8 | ConvertFrom-Json
}

$mcps    = Read-Json 'registry\mcps.json'
$formats = Read-Json 'registry\plugin-formats.json'
$conn    = Read-Json 'registry\native-connectors.json'

# Per-host plugin ownership: a server a plugin supplies is never written to
# the host's MCP config, so its absence there is correct rather than drift.
# github is the worked example -- plugin-owned on claude and copilot, and
# reachable in-session from the plugin while absent from every config file.
# Two exposure modes deliver a server WITHOUT writing the host's MCP config, so
# absence there is correct rather than drift:
#   plugin-owned     - a plugin supplies it (github on claude and copilot)
#   native-connector - the host's own built-in connector (descript on claude)
# shared-gateway is deliberately NOT in this set: those ARE written to the
# config, which is how codex's missing github was caught as genuine drift.
$notInConfig = @{}
foreach ($h in @($conn.hosts)) {
    $hid = [string]$h.hostId
    foreach ($mode in 'plugin-owned', 'native-connector') {
        foreach ($sid in @($h.exposures.$mode)) {
            if ($sid) { $notInConfig["$hid/$sid"] = $mode }
        }
    }
}

$persistedLocal = @{}
foreach ($id in @($conn.lifecyclePolicy.persistedOnDemandLocalMcpIds)) { if ($id) { $persistedLocal[[string]$id] = $true } }

# Which server ids does a host's config actually declare?
function Get-DeployedIds([string]$McpPath, [string]$McpKey) {
    # The regex-escape that used to be here was wrong, and its comment argued
    # for it backwards: escaping is for a PATTERN operand, but $env:USERPROFILE
    # is the REPLACEMENT operand, where the escaped form's doubled backslashes
    # survive literally and produce C:\\Users\\... . Win32 tolerates doubled
    # separators, so it never failed -- it just emitted wrong paths in the
    # failure text a reader would then go chase. Substring avoids both the
    # escaping question and -replace's argument-separator parse trap.
    $expanded = if ($McpPath.StartsWith('~')) { $env:USERPROFILE + $McpPath.Substring(1) } else { $McpPath }
    $expanded = $expanded -replace '/', '\'
    $p = [Environment]::ExpandEnvironmentVariables($expanded)
    if (-not (Test-Path -LiteralPath $p)) { return $null }          # null = could not check
    $text = Get-Content -LiteralPath $p -Raw -Encoding UTF8
    if ($p -like '*.toml') {
        return @([regex]::Matches($text, '(?m)^\[mcp_servers\.([^\].]+)\]') | ForEach-Object { $_.Groups[1].Value })
    }
    $json = $text | ConvertFrom-Json
    # A dotted mcpKey may be a PATH (claude: mcpServers) or a LITERAL key name
    # (amp stores "amp.mcpServers" as one property). Try the literal first,
    # then walk the segments, so neither shape is misread as "no servers".
    $node = $json.PSObject.Properties[$McpKey].Value
    if ($null -eq $node) {
        $node = $json
        foreach ($seg in ($McpKey -split '\.')) {
            if ($null -eq $node) { break }
            $node = $node.PSObject.Properties[$seg].Value
        }
    }
    # `return @()` UNROLLS to $null leaving a function, which would be
    # indistinguishable from the missing-file signal above. The comma operator
    # wraps it so an empty set stays an empty set.
    if ($null -eq $node) { return ,@() }
    return ,@($node.PSObject.Properties.Name)
}

$hostConfig = @{}
foreach ($h in @($formats.hosts)) {
    if ($h.id -and $h.mcpPath -and $h.mcpKey -and $h.mcpKey -notlike '`[*') {
        $hostConfig[[string]$h.id] = @{ Path = [string]$h.mcpPath; Key = [string]$h.mcpKey }
    } elseif ($h.id -and $h.mcpPath) {
        $hostConfig[[string]$h.id] = @{ Path = [string]$h.mcpPath; Key = $null }   # TOML
    }
}
Report 'host MCP config paths are declared in plugin-formats' ($hostConfig.Count -gt 0) `
    'No host declares mcpPath, so every check below would be vacuous.'

# Every exposure id must be a canonical server id. Without this, an id that
# stops existing just sits in a host's exposure list looking like coverage:
# claude carried 'chrome-devtools' for a day after playwright replaced it
# fleet-wide, and the descript gap analysis that found it was itself only
# looking at two of the three exposure modes. migrationAliases are accepted,
# because that is exactly what they are for.
$canonicalIds = @{}
foreach ($s in @($mcps.mcpServers)) { $canonicalIds[[string]$s.id] = $true }
$aliasKeys = @{}
foreach ($p in @($mcps.migrationAliases.PSObject.Properties)) { $aliasKeys[$p.Name] = [string]$p.Value }
$staleExposures = [Collections.Generic.List[string]]::new()
foreach ($h in @($conn.hosts)) {
    foreach ($mode in @($h.exposures.PSObject.Properties)) {
        foreach ($sid in @($mode.Value)) {
            if (-not $sid) { continue }
            if ($canonicalIds.ContainsKey([string]$sid)) { continue }
            $staleExposures.Add("$($h.hostId)/$($mode.Name)/$sid" + $(if ($aliasKeys.ContainsKey([string]$sid)) { " (alias -> $($aliasKeys[[string]$sid]))" } else { ' (no alias)' }))
        }
    }
}
Report 'every native-connector exposure id is a canonical MCP server id' ($staleExposures.Count -eq 0) `
    "these exposure ids no longer exist in mcps.json, so they read as coverage while providing none: $($staleExposures -join '; ')"

# hostInventory.installed is the 'all hosts' set for a shared-remote server that
# names no hosts. Empty-hosts on shared-remote means EVERY host by convention --
# the same convention used to reject a reported 5-server grok drift as a
# non-finding. Until 2026-08-20 this file read that convention as 'skip', so
# seven servers (linear, context7, notion, firecrawl, exa, descript,
# brave-search) were asserted nowhere at all.
$installedHosts = @($mcps.hostInventory.hosts | Where-Object { $_ })
# The field is `hosts`, not `installed` -- named that way so
# Test-RegistryHostReferences validates the ids for free. Reading the wrong name
# yields an empty set, which makes the all-hosts expansion below expand to
# NOTHING and pass silently. That is precisely what it did on first run.
Report 'the all-hosts inventory resolved to a non-empty host set' ($installedHosts.Count -gt 0) `
    'mcps.json hostInventory.hosts is empty or missing, so every shared-remote server that names no hosts expands to zero hosts and is asserted nowhere.'

$checked = 0
foreach ($server in @($mcps.mcpServers)) {
    $id = [string]$server.id
    $hosts = @($server.hosts | Where-Object { $_ })

    $isPersisted = ($server.activationMode -eq 'shared-remote') -or $persistedLocal.ContainsKey($id)
    if (-not $isPersisted) { continue }

    if ($hosts.Count -eq 0) {
        # Only shared-remote carries the all-hosts reading. An on-demand-local
        # server with no hosts (brave-search) is declared by nobody, which is a
        # different statement and is asserted by its declaredByHostCount instead.
        if ($server.activationMode -ne 'shared-remote') { continue }
        $hosts = $installedHosts
    }

    foreach ($hostId in $hosts) {
        if (-not $hostConfig.ContainsKey($hostId)) { continue }
        if ($notInConfig.ContainsKey("$hostId/$id")) { continue }   # delivered off-config; see $notInConfig
        $deployed = Get-DeployedIds $hostConfig[$hostId].Path $hostConfig[$hostId].Key
        if ($null -eq $deployed) {
            Report "persisted '$id' host '$hostId' has a readable config" $false `
                "config not found at $($hostConfig[$hostId].Path); a declaration cannot be verified against a missing file."
            continue
        }
        $checked++
        Report "persisted '$id' is deployed to declared host '$hostId'" ($deployed -contains $id) `
            "declared in mcps.json but absent from $($hostConfig[$hostId].Path), which carries: $($deployed -join ', ')"
    }
}

# Without this, a change that stops classifying anything as persisted would
# empty the loop and leave the file green having verified nothing.
Report 'at least one persisted declaration was actually checked' ($checked -gt 0) `
    'No server/host pair was evaluated. If activationMode or persistedOnDemandLocalMcpIds changed shape, every check above silently vanished.'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
