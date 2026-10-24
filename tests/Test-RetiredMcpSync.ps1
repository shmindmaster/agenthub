#Requires -Version 5.1
# Exercise default apply (without broad prune) against isolated native formats.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('retired-mcp-' + [guid]::NewGuid().ToString('N'))
$registry = Join-Path $scratch 'registry'
$profile = Join-Path $scratch 'profile'
$null = New-Item -ItemType Directory -Path $registry,$profile -Force
function Save-Json($Path, $Value) { $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8 }
try {
    $hosts = @(
        @{id='codex';status='active';nativePaths=@{config="$profile\codex.toml"}},
        @{id='factory';status='active';nativePaths=@{mcp="$profile\factory.json"}},
        @{id='warp';status='active';nativePaths=@{mcp="$profile\warp.json"}},
        @{id='opencode';status='active';nativePaths=@{config="$profile\opencode.json"}}
    )
    Save-Json "$registry\agents.json" @{activeAgents=$hosts;inactiveAgents=@()}
    $mcps = @{retiredMcpIds=@('chrome-devtools','chrome-devtools-isolated');retiredMcpPackages=@('chrome-devtools-mcp');migrationAliases=@{}
        mcpServers=@(@{id='fixture-active';transport='stdio';command='fixture.exe';args=@()})}
    Save-Json "$registry\mcps.json" $mcps
    Save-Json "$registry\capabilities.json" @{capabilities=@(@{id='fixture';canonicalSource='packages/absent';capabilityType='skills'})}
    $servers = @{'chrome-devtools'=@{command='npx';args=@('chrome-devtools-mcp@0.0.1')};'chrome-devtools-isolated'=@{command='old.exe'};'owner-custom'=@{command='owner.exe'}}
    Save-Json "$profile\factory.json" @{mcpServers=$servers}
    Save-Json "$profile\warp.json" @{mcpServers=$servers}
    Save-Json "$profile\opencode.json" @{mcp=$servers}
    [IO.File]::WriteAllText((Join-Path $profile "codex.toml"), "[mcp_servers.chrome-devtools]`ncommand = 'old.exe'`n[mcp_servers.chrome-devtools-isolated]`ncommand = 'old.exe'`n[mcp_servers.owner-custom]`ncommand = 'owner.exe'`n")
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -File "$root\scripts\Sync-AgentHub.ps1" -Apply -QuietOverlayResolution -RegistryRoot $scratch -UserProfile $profile *> "$scratch\sync.log"
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic sync failed; inspect fixture setup.' }
    foreach ($file in @('codex.toml','factory.json','warp.json','opencode.json')) {
        $text = [IO.File]::ReadAllText((Join-Path $profile "$file"))
        if ($text -match 'chrome-devtools' -or $text -notmatch 'owner-custom' -or $text -notmatch 'fixture-active') { throw "Retirement/preservation failed: $file" }
    }
    Write-Host 'PASS: default apply removes retired IDs across TOML, JSON, converted JSON and OpenCode; preserves owner entries and adds active server'
    $before = Get-FileHash -LiteralPath "$profile\factory.json"
    $mcps.mcpServers += @{id='renamed-browser';transport='stdio';command='npx';args=@('-y','chrome-devtools-mcp@0.0.1')}
    Save-Json "$registry\mcps.json" $mcps
    $ErrorActionPreference = 'Continue'
    & $exe -NoProfile -File "$root\scripts\Sync-AgentHub.ps1" -Apply -QuietOverlayResolution -RegistryRoot $scratch -UserProfile $profile *> "$scratch\rejected.log"
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -or (Get-FileHash -LiteralPath "$profile\factory.json").Hash -ne $before.Hash) { throw 'Retired package was not rejected before host writes.' }
    Write-Host 'PASS: renamed retired package is rejected before configuration writes'
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
