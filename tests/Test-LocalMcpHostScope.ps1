#Requires -Version 5.1
<#
Behavior test for the host scope of process-spawning MCP servers.

Why: an `on-demand-local` registration is a licence for that host to spawn a
local process. Registering one to a host that is not installed cannot buy any
capability -- it only widens the surface the sync writes and the host loads.
Three servers (chrome-devtools, chrome-devtools-isolated, repowise-workspace)
carried all 18 hosts on 2026-08-19 while far fewer hosts were installed.

The invariant: every host named by an `on-demand-local` server must appear in
`hostInventory.hosts`. `shared-remote` servers are exempt -- they cost a config
line, not a process.

The field is named `hosts` deliberately: Test-RegistryHostReferences.ps1 walks
the registry generically and validates every property literally named `hosts`
against registry/agents.json, so this inventory inherits that check for free.
Renaming it to something more descriptive would silently drop that validation.

Same accumulate-and-report idiom as the other suites here; exit 1 on failure.

Run: pwsh -NoProfile -File tests/Test-LocalMcpHostScope.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcpPath  = Join-Path $repoRoot 'registry\mcps.json'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json

# The inventory is the authority for what exists on this machine. Without it
# the invariant has nothing to check against, so its absence is a failure --
# not a silent skip that would make this suite look green while proving nothing.
$inventory = $mcp.hostInventory
Report 'the registry declares a host inventory' ($null -ne $inventory) `
    'mcps.json has no hostInventory block; the scope invariant cannot be evaluated.'

$installed = @()
if ($inventory) { $installed = @($inventory.hosts | Where-Object { $_ }) }
Report 'the inventory names at least one installed host' ($installed.Count -gt 0) `
    'hostInventory.hosts is empty; every local registration would fail below.'

$installedSet = @{}
foreach ($h in $installed) { if ($h) { $installedSet[[string]$h] = $true } }

$intentionallyUnscoped = @('brave-search')
$localServers = @($mcp.mcpServers | Where-Object { $_.activationMode -eq 'on-demand-local' })
Report 'the registry declares at least one on-demand-local server' ($localServers.Count -gt 0) `
    'No server matched activationMode on-demand-local. If that field was renamed, every scope check below silently disappears.'

foreach ($server in @($mcp.mcpServers)) {
    if ($server.activationMode -ne 'on-demand-local') { continue }
    # PowerShell wraps a null property into a one-element array holding $null,
    # so an unscoped server would otherwise report a stray with a blank name.
    $hosts = @($server.hosts | Where-Object { $_ })
    # A silent `continue` here meant the guard vanished exactly when the thing
    # it guards did: emptying a hosts array removes that server from the check
    # entirely and the suite stays green with one fewer PASS nobody counts.
    # Unscoped must therefore be declared, not inferred.
    if ($hosts.Count -eq 0) {
        Report "on-demand-local '$($server.id)' is unscoped only if declared so" `
            ($server.id -in $intentionallyUnscoped) `
            'Its hosts array is empty and it is not in the intentionally-unscoped list, so its scope check was silently skipped.'
        continue
    }

    $strays = @($hosts | Where-Object { -not $installedSet.ContainsKey([string]$_) })
    Report "on-demand-local '$($server.id)' targets only installed hosts" `
        ($strays.Count -eq 0) `
        "$($strays.Count) host(s) not in hostInventory.hosts: $($strays -join ', ')"
}

# ---------------------------------------------------------------------------
# Deployed-key drift. Prune keeps what the canonical set names, after passing
# each existing key through Resolve-McpAliasKey. A host config that carries a
# server under a different key than the registry's id therefore reads as
# "unknown" and gets deleted. On 2026-08-19 .claude/settings.json carried
# repowise-workspace under the key `repowise` while migrationAliases was empty
# -- a prune run would have removed the only working repowise registration.
# Every deployed key must resolve to a canonical id, by being one or by having
# a migrationAliases entry that maps to one.
$canonical = @{}
foreach ($s in @($mcp.mcpServers)) { if ($s.id) { $canonical[[string]$s.id] = $true } }

$aliases = @{}
if ($mcp.migrationAliases) {
    foreach ($p in $mcp.migrationAliases.PSObject.Properties) { $aliases[$p.Name] = [string]$p.Value }
}

# Host-owned servers are written by the host itself and are deliberately absent
# from the registry, so they are not drift -- they are protected by name.
$connPath = Join-Path $repoRoot 'registry\native-connectors.json'
# A wrong path here must fail loudly. The previous form carried a literal
# newline, so Test-Path simply returned false and the host-owned carve-out
# below silently became dead code -- the failure mode a guard must not have.
if (-not (Test-Path -LiteralPath $connPath)) {
    throw "native-connectors.json not found at '$connPath'. Refusing to run with an empty host-owned set, which would make the carve-out below vacuous."
}
$hostOwned = @{}
if (Test-Path -LiteralPath $connPath) {
    $conn = Get-Content -LiteralPath $connPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($id in @($conn.lifecyclePolicy.hostConfiguredLocalMcpIds)) { if ($id) { $hostOwned[[string]$id] = $true } }
}

$claudeSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path -LiteralPath $claudeSettings) {
    $cs = Get-Content -LiteralPath $claudeSettings -Raw -Encoding UTF8 | ConvertFrom-Json
    $deployed = @()
    if ($cs.mcpServers) { $deployed = @($cs.mcpServers.PSObject.Properties.Name) }
    foreach ($key in $deployed) {
        $resolved = if ($aliases.ContainsKey($key)) { $aliases[$key] } else { $key }
        $ok = $canonical.ContainsKey($resolved) -or $hostOwned.ContainsKey($key)
        Report "deployed claude key '$key' resolves to a canonical server" $ok `
            "Neither a registry id nor a migrationAliases target nor host-owned; prune would delete it."
    }
} else {
    Report 'claude settings.json is present to check for key drift' (Test-Path -LiteralPath $claudeSettings) "absent: $claudeSettings -- drift cannot be checked against a file that is gone, so this is a failure: $claudeSettings"
}

# The guard must be able to fail: a host that is definitely not installed must
# not be treated as installed. A test that cannot fail is decoration.
Report 'a fabricated host name is not reported as installed' `
    (-not $installedSet.ContainsKey('definitely-not-an-installed-host')) `
    'The inventory matched an arbitrary name, so the check above proves nothing.'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
