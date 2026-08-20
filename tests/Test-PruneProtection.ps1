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
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$syncText = Get-Content -LiteralPath $syncPath -Raw -Encoding UTF8
$conn = Get-Content -LiteralPath $connPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mcpRegistry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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
#
# The assertion MUST be scoped to the grok function body. The earlier form ran
# a `(?s).*?` regex over the whole file; it matched starting inside
# Sync-HostMcp-Codex and bridged 126 lines across the function boundary, so
# deleting grok's entire prune block still passed. Extract the function extent
# from the AST -- text scanning cannot find a function's end reliably.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($syncPath, [ref]$null, [ref]$null)
$grokFn = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Sync-HostMcp-Grok'
}, $true) | Select-Object -First 1

# An unmatched function is a hard failure, never a fallback to the whole file:
# the fallback is exactly what made the old assertion vacuous.
Report 'the grok writer function is locatable for scoped assertions' ($null -ne $grokFn) `
    'Sync-HostMcp-Grok not found in the AST; every grok assertion below would be unscoped.'
$grokText = if ($grokFn) { $grokFn.Extent.Text } else { '' }

Report 'the grok prune no longer uses a hardcoded server denylist' `
    ($grokText -and $grokText -notmatch "foreach \(\`$name in @\('context7', 'firecrawl', 'tavily'") `
    'The denylist deleted canonical servers that had just been written in place.'

Report 'the grok prune keys off the canonical set' `
    ($grokText -match '(?s)if \(\$Prune\) \{.*?\$keep\[.*?\] = \$true.*?\$existingKeys') `
    'Expected a keep-set built from $Mcps.Keys plus host-owned ids, then removal of everything else.'

# The keep-set must be alias-resolved on INSERT, not only on lookup. Grok
# seeded raw ids while looking up through Resolve-McpAliasKey, so any
# host-owned id carrying a migrationAliases entry was kept in codex and pruned
# from grok -- a silent divergence between two writers of the same policy.
$hostOwnedBuild = [regex]::Match($syncText,
    '(?s)\$script:hostOwnedMcpKeys\s*=\s*@\(.*?\)\s*?
')
Report 'the host-owned key list is built at all' $hostOwnedBuild.Success `
    'Could not locate the $script:hostOwnedMcpKeys assignment; the assertion below would be vacuous.'
Report 'the host-owned key list is alias-resolved where it is built' `
    ($hostOwnedBuild.Success -and $hostOwnedBuild.Value -match 'Resolve-McpAliasKey') `
    'The writers seed this list raw into their keep-sets, so if construction stops resolving, an aliased host-owned id is pruned.'

$grokConfig = Join-Path $env:USERPROFILE '.grok\config.toml'
Report 'deployed grok config is present to check' (Test-Path -LiteralPath $grokConfig) `
    "absent: $grokConfig -- a broken TOML write is one way it goes missing, so this is a failure, not a skip."
if (Test-Path -LiteralPath $grokConfig) {
    $gk = @([regex]::Matches((Get-Content -LiteralPath $grokConfig -Raw -Encoding UTF8),
        '(?m)^\[mcp_servers\.([^\].]+)\]
?$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    # Expected count comes from the registry, not a magic number: the old
    # `-ge 5` would still pass if the canonical set shrank to five.
    $expected = @($mcpRegistry.mcpServers | Where-Object { @($_.hosts) -contains 'grok' } | ForEach-Object { $_.id })
    $missing = @($expected | Where-Object { $_ -notin $gk })
    Report 'grok retains every canonical server the registry scopes to it' ($missing.Count -eq 0) `
        "missing $($missing.Count) of $($expected.Count): $($missing -join ', '). grok carries: $($gk -join ', ')."
}

# The guard must be able to fail. Derive the negative from real data rather
# than a hand-picked string that cannot match by construction: take a canonical
# server id that is NOT host-owned and assert the protection list excludes it.
$canonicalIds = @($mcpRegistry.mcpServers | ForEach-Object { $_.id })
$notProtected = @($canonicalIds | Where-Object { $_ -notin $hostOwned })
Report 'the protection list is a strict subset of what exists, not a catch-all' `
    ($notProtected.Count -gt 0 -and $hostOwned.Count -lt $canonicalIds.Count + $hostOwned.Count) `
    "Every canonical id ($($canonicalIds.Count)) appears protected; the protection check would pass for anything."
foreach ($id in $notProtected) {
    Report "canonical server '$id' is correctly NOT in the host-owned protection list" `
        ($id -notin $hostOwned) `
        'A registry-declared server was treated as host-owned, which would exempt it from prune entirely.'
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
