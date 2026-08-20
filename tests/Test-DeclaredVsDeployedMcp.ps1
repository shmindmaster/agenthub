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
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green }
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
$pluginOwned = @{}
foreach ($h in @($conn.hosts)) {
    $hid = [string]$h.hostId
    foreach ($sid in @($h.exposures.'plugin-owned')) {
        if ($sid) { $pluginOwned["$hid/$sid"] = $true }
    }
}

$persistedLocal = @{}
foreach ($id in @($conn.lifecyclePolicy.persistedOnDemandLocalMcpIds)) { if ($id) { $persistedLocal[[string]$id] = $true } }

# Which server ids does a host's config actually declare?
function Get-DeployedIds([string]$McpPath, [string]$McpKey) {
    # Assign before calling: inside method parentheses the comma of -replace's
    # second operand is parsed as an argument separator, so the inline form
    # fails with "cannot find an overload ... argument count: 2". The profile
    # path is regex-escaped because it is the REPLACEMENT operand and holds
    # backslashes.
    $profileRoot = [regex]::Escape($env:USERPROFILE)
    $expanded = ($McpPath -replace '^~', $profileRoot) -replace '/', '\'
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

$checked = 0
foreach ($server in @($mcps.mcpServers)) {
    $id = [string]$server.id
    $hosts = @($server.hosts | Where-Object { $_ })
    if ($hosts.Count -eq 0) { continue }

    $isPersisted = ($server.activationMode -eq 'shared-remote') -or $persistedLocal.ContainsKey($id)
    if (-not $isPersisted) { continue }

    foreach ($hostId in $hosts) {
        if (-not $hostConfig.ContainsKey($hostId)) { continue }
        if ($pluginOwned.ContainsKey("$hostId/$id")) { continue }   # supplied by a plugin, not the config
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
    Write-Host "RESULT: $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: all declared-vs-deployed MCP checks passed' -ForegroundColor Green
exit 0
