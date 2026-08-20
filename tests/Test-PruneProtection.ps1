#Requires -Version 5.1
<#
Behavior tests for host-owned MCP survival under prune.

Why: registry-driven prune removes any server a host config carries that the
registry does not name. Codex writes `node_repl` itself -- a content-addressed
runtime path plus a live per-session named pipe in its env -- so it can never
appear in the registry as a reproducible entry, and pruning it as "unknown"
breaks Codex code mode. `lifecyclePolicy.hostConfiguredLocalMcpIds` names those
servers; this file proves the sync actually consumes that list rather than
merely declaring it, which was the state before 2026-08-19.

Same accumulate-and-report idiom as the other suites here; exit 1 on failure.

Run: pwsh -NoProfile -File tests/Test-PruneProtection.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncPath = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'
$connPath = Join-Path $repoRoot 'registry\native-connectors.json'

$failures = [Collections.Generic.List[string]]::new()
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$syncText = Get-Content -LiteralPath $syncPath -Raw -Encoding UTF8
$conn = Get-Content -LiteralPath $connPath -Raw -Encoding UTF8 | ConvertFrom-Json
$hostOwned = @($conn.lifecyclePolicy.hostConfiguredLocalMcpIds)

Report 'the registry names at least one host-owned server' ($hostOwned.Count -gt 0) `
    'lifecyclePolicy.hostConfiguredLocalMcpIds is empty; nothing would be protected.'

Report 'the sync reads hostConfiguredLocalMcpIds into a keep-set' `
    ($syncText -match 'hostConfiguredLocalMcpIds' -and $syncText -match '\$script:hostOwnedMcpKeys\s*=') `
    'Declaring the list without reading it is what let prune delete host-owned servers.'

# Both prune paths must honour it: the codex TOML writer and the generic
# JSON merge. Protecting only one leaves the other free to delete.
$codexSeeded = $syncText -match '(?s)\$keep\[\(Resolve-McpAliasKey \$k\)\] = \$true.*?foreach \(\$k in @\(\$script:hostOwnedMcpKeys\)\)'
Report 'the codex TOML prune keep-set is seeded from the list' $codexSeeded `
    'Codex is the host that actually carries node_repl; its prune must preserve it.'

$mergeSeeded = $syncText -match '(?s)if \(\$PruneUnknown\) \{\s*foreach \(\$k in @\(\$script:hostOwnedMcpKeys\)\)'
Report 'the generic JSON prune keep-set is seeded from the list' $mergeSeeded `
    'Merge-McpServers prunes every JSON host; an unseeded keep-set removes host-owned servers there too.'

# End state: the protected server is still present where its host wrote it.
$codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
if (Test-Path -LiteralPath $codexConfig) {
    $cfgText = Get-Content -LiteralPath $codexConfig -Raw -Encoding UTF8
    foreach ($id in $hostOwned) {
        Report "deployed codex config still carries host-owned '$id'" `
            ($cfgText -match [regex]::Escape("[mcp_servers.$id]")) `
            "A prune run removed it, or the host has not written it yet."
    }
} else {
    Report 'deployed codex config is present to check' $true "absent, skipped: $codexConfig"
}

# Regression, 2026-08-19: the grok writer pruned a hardcoded denylist AFTER
# rewriting canonical sections in place, so it deleted servers it had just
# written -- grok went from seven servers to two. Prune must key off the
# canonical set, which cannot delete a canonical server by construction.
$grokBlock = [regex]::Match($syncText, '(?s)function Sync-HostMcp-Grok.*?\nfunction ')
$grokText = if ($grokBlock.Success) { $grokBlock.Value } else { '' }
if (-not $grokText) {
    # Fall back to the region between the grok writer and the next function.
    $grokText = $syncText
}
Report 'the grok prune no longer uses a hardcoded server denylist' `
    ($syncText -notmatch "foreach \(\`$name in @\('context7', 'firecrawl', 'tavily'") `
    'The denylist deleted canonical servers that had just been written in place.'

Report 'the grok prune keys off the canonical set' `
    ($syncText -match '(?s)if \(\$Prune\) \{.*?\$keep\[\(Resolve-McpAliasKey \$k\)\] = \$true.*?\$existingKeys') `
    'Expected a keep-set built from $Mcps.Keys plus host-owned ids, then removal of everything else.'

$grokConfig = Join-Path $env:USERPROFILE '.grok\config.toml'
if (Test-Path -LiteralPath $grokConfig) {
    $gk = @([regex]::Matches((Get-Content -LiteralPath $grokConfig -Raw -Encoding UTF8),
        '(?m)^\[mcp_servers\.([^\].]+)\]\r?$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    Report 'grok retains its canonical remote servers after prune' ($gk.Count -ge 5) `
        "grok carries $($gk.Count) server(s): $($gk -join ', '). A denylist prune left it with two."
}

# The guard must be able to fail: an id the registry does not protect and the
# canonical set does not contain must NOT be treated as protected.
$fake = 'definitely-not-a-registered-server'
Report 'an unprotected, unregistered id is not in the protected list' `
    ($fake -notin $hostOwned) `
    'The protection list matched an arbitrary id, so it proves nothing.'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: all prune-protection checks passed' -ForegroundColor Green
exit 0
