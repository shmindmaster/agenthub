#Requires -Version 5.1
<# Exercise the real fleet writer against synthetic profiles only. Explicit
native exceptions must survive plugin suppression and -Prune without being
generated on hosts where they are absent or not allowed. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/TestPlatform.ps1')
$repoRoot = Split-Path -Parent $PSScriptRoot
$hostExe = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($env:AGENTHUB_TEST_SCRATCH)) { $env:AGENTHUB_TEST_SCRATCH = [IO.Path]::GetTempPath() }
$scratch = [IO.Path]::GetFullPath($env:AGENTHUB_TEST_SCRATCH)
$fixture = Join-Path $scratch ('agenthub-native-prune-' + [guid]::NewGuid())
$profile = Join-Path $fixture 'profile'
$registryDir = Join-Path $fixture 'registry'
$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++; Write-Host "PASS: $Message" }
    else { $script:failures.Add($Message); Write-Host "FAIL: $Message" }
}
function Write-Json($Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}
try {
    New-Item -ItemType Directory -Path $profile, $registryDir -Force | Out-Null
    $agents = @()
    $hosts = @{}
    $paths = @{}
    foreach ($id in @('claude','codex','cursor','grok','opencode','cline','windsurf','factory')) {
        $ext = if ($id -in @('codex','grok')) { 'toml' } else { 'json' }
        $path = Join-Path $profile "$id.$ext"
        $paths[$id] = $path
        $agents += @{ id=$id; name=$id; status='active'; nativePaths=@{config=$path; mcp=$path; mcpUser=$path} }
        $hosts[$id] = if ($id -eq 'factory') { @{} } else { @{'aws-mcp'='Owner-configured native OAuth connection.'} }
        if ($ext -eq 'toml') {
            [IO.File]::WriteAllText($path, "[mcp_servers.aws-mcp]`nurl = 'https://aws.example/mcp?oauth=initialize'`nenabled = false`n[mcp_servers.stray]`ncommand = 'old'`n")
        } elseif ($id -eq 'opencode') {
            $hosts[$id]['browse'] = 'Host-owned browser relay.'
            $hosts[$id]['parallel'] = 'Hosted anonymous search and fetch.'
            Write-Json $path @{mcp=@{legacyStray=@{type='remote';url='https://old.example'};servers=@{'aws-mcp'=@{type='remote';url='https://aws.example/mcp?oauth=initialize';disabled=$true;pool=$true};browse=@{type='local';command=@('browse','mcp');pool=$true};stray=@{type='remote';url='https://old.example'}}}}
        } else {
            Write-Json $path @{mcpServers=@{'aws-mcp'=@{type='http';url='https://aws.example/mcp?oauth=initialize';headers=@{'X-Fixture'='preserve'}};stray=@{command='old'}}}
        }
    }
    # A second host with permission but no existing entry must stay empty.
    $empty = Join-Path $profile 'warp.json'
    Write-Json $empty @{mcpServers=@{}}
    $paths['warp'] = $empty
    $hosts['warp'] = @{'aws-mcp'='Allowed only when owner-configured.'}
    $agents += @{id='warp';name='warp';status='active';nativePaths=@{mcp=$empty}}
    Write-Json (Join-Path $registryDir 'agents.json') @{activeAgents=$agents;inactiveAgents=@()}
    $parallelEndpoint = 'https://parallel.example/mcp'
    $parallel = @{id='parallel';scope='global-default';transport='http';activationMode='shared-remote';url=$parallelEndpoint;hosts=@('opencode')}
    Write-Json (Join-Path $registryDir 'mcps.json') @{activationPolicy=@{pluginOnly=@{hosts=$hosts}};mcpServers=@($parallel)}
    # Simulate a vendor package supplying the same key, without making AWS a
    # generated registry row. Its ownership must not suppress a direct exception.
    $package = Join-Path $fixture 'packages/native-fixture'
    New-Item -ItemType Directory -Path $package -Force | Out-Null
    Write-Json (Join-Path $package '.mcp.json') @{mcpServers=@{'aws-mcp'=@{command='vendor-proxy'}}}
    $mappings = @($agents | ForEach-Object { @{hostId=$_.id;deploymentStatus='plugin-owned'} })
    Write-Json (Join-Path $registryDir 'capabilities.json') @{schemaVersion=2;capabilities=@(@{id='fixture';owner='test';capabilityType='skills';canonicalSource='packages/native-fixture';hostMappings=$mappings})}
    $syncArgs = @('-NoProfile','-File',(Join-Path $repoRoot 'scripts/Sync-AgentHub.ps1'),'-Apply','-Prune','-RegistryRoot',$fixture,'-UserProfile',$profile)
    $run = & $hostExe @syncArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Fixture sync failed: $run" }
    $first = @{}
    foreach ($id in @('claude','codex','cursor','grok','opencode','cline','windsurf')) {
        $raw = Get-Content -LiteralPath $paths[$id] -Raw -Encoding UTF8
        Assert-True ($raw.Contains('https://aws.example/mcp?oauth=initialize')) "$id keeps the native AWS endpoint"
        Assert-True (-not $raw.Contains('old.example') -and -not $raw.Contains('mcp_servers.stray') -and -not $raw.Contains('"stray"')) "$id removes unrelated stale entries"
        if ($id -in @('codex','grok')) {
            Assert-True ($raw -match 'enabled = false') "$id preserves the disabled switch"
        } elseif ($id -ne 'opencode') {
            $data = $raw | ConvertFrom-Json
            Assert-True ($data.mcpServers.'aws-mcp'.headers.'X-Fixture' -eq 'preserve') "$id preserves native connection fields"
        }
        $first[$id] = $raw
    }
    $oc = Get-Content -LiteralPath $paths.opencode -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($oc.mcp.servers.browse.command[0] -eq 'browse' -and $oc.mcp.servers.'aws-mcp'.disabled -eq $true -and $oc.mcp.servers.'aws-mcp'.pool -eq $true) 'OpenCode preserves native nested connections and their switches'
    Assert-True ($oc.mcp.servers.parallel.url -eq $parallelEndpoint -and $oc.mcp.servers.parallel.type -eq 'remote' -and
        $null -eq $oc.mcp.PSObject.Properties['parallel'] -and
        $null -eq $oc.mcp.servers.parallel.PSObject.Properties['enabled']) 'OpenCode writes a managed remote to its native nested catalog without a flat duplicate'
    $negative = Get-Content -LiteralPath $paths.factory -Raw -Encoding UTF8
    Assert-True (-not $negative.Contains('aws.example')) 'exceptions do not leak into the next host'
    $absent = Get-Content -LiteralPath $paths.warp -Raw -Encoding UTF8
    Assert-True (-not $absent.Contains('aws-mcp')) 'an allowed native connection is not generated when absent'
    $run = & $hostExe @syncArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Second fixture sync failed: $run" }
    foreach ($id in $first.Keys) {
        Assert-True ($first[$id] -ceq (Get-Content -LiteralPath $paths[$id] -Raw -Encoding UTF8)) "$id is byte-stable after a second prune"
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($scratch.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host "RESULT: $passed passed, $($failures.Count) failed"
if ($failures.Count) { exit 1 }
