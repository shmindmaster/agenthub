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
    $clineExtension = Join-Path $profile 'cline-extension.json'
    foreach ($id in @('claude','codex','cursor','grok','opencode','cline','windsurf','factory')) {
        $ext = if ($id -in @('codex','grok')) { 'toml' } else { 'json' }
        $path = Join-Path $profile "$id.$ext"
        $paths[$id] = $path
        $agents += @{ id=$id; name=$id; status='active'; nativePaths=@{config=$path; mcp=$path; mcpUser=$path} }
        if ($id -eq 'cline') { $agents[-1].nativePaths.mcpVSCodeInsiders = $clineExtension }
        $hosts[$id] = if ($id -eq 'factory') { @{} } else { @{'aws-mcp'='Owner-configured native OAuth connection.'} }
        if ($ext -eq 'toml') {
            [IO.File]::WriteAllText($path, "[mcp_servers.aws-mcp]`nurl = 'https://aws.example/mcp?oauth=initialize'`nenabled = false`n[mcp_servers.stray]`ncommand = 'old'`n")
        } elseif ($id -eq 'opencode') {
            $hosts[$id]['browse'] = 'Host-owned browser relay.'
            $hosts[$id]['parallel'] = 'Hosted anonymous search and fetch.'
            $hosts[$id]['existing-remote'] = 'Managed legacy entry with a native override.'
            Write-Json $path @{mcp=@{
                legacyStray=@{type='remote';url='https://old.example'}
                'existing-remote'=@{type='remote';url='https://legacy.example';enabled=$false}
                servers=@{
                    'aws-mcp'=@{type='remote';url='https://aws.example/mcp?oauth=initialize';disabled=$true;pool=$true}
                    browse=@{type='local';command=@('browse','mcp');pool=$true}
                    stray=@{type='remote';url='https://old.example'}
                    'existing-remote'=@{type='remote';url='https://native.example';pool=$true}
                }
            }}
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
    $parallel = @{id='parallel';scope='global-default';transport='http';activationMode='shared-remote';url=$parallelEndpoint;hosts=@('codex','opencode','cline')}
    $researchEndpoint = 'https://parallel.example/mcp?login&tools=web_research'
    $research = @{id='parallel-research';scope='owner-configured';transport='http';activationMode='shared-remote';url=$researchEndpoint;hosts=@('codex','opencode','cline')}
    $hosts.codex['parallel'] = 'Hosted anonymous search and fetch.'
    foreach ($id in 'codex','opencode','cline') {
        $hosts[$id]['parallel-research'] = 'Preserve existing consent without provisioning a connection.'
    }
    [IO.File]::AppendAllText($paths.codex, "[mcp_servers.parallel-research]`nurl = '$researchEndpoint'`nenabled = false`n")
    $openState = Get-Content -LiteralPath $paths.opencode -Raw -Encoding UTF8 | ConvertFrom-Json
    $openState.mcp.servers | Add-Member -NotePropertyName 'parallel-research' -NotePropertyValue @{
        type='remote';url=$researchEndpoint;disabled=$true;oauth=@{fixture='native'}
    }
    Write-Json $paths.opencode $openState
    $clineOAuth = @{id='cline-oauth';scope='global-default';transport='http';activationMode='shared-remote';url='https://managed.example/consent';credentialPolicy='oauth';hosts=@('cline')}
    $clineApproved = @{id='existing-remote';scope='global-default';transport='http';activationMode='shared-remote';url='https://managed.example';hosts=@('opencode','cline')}
    $clineHeaders = @{id='cline-headers';scope='global-default';transport='http';activationMode='shared-remote';url='https://managed.example/headers';headers=@{'X-Fixture'='do-not-copy'};hosts=@('cline')}
    foreach ($key in @('parallel','cline-oauth','existing-remote','cline-headers')) { $hosts.cline[$key] = 'Hosted fixture server.' }
    Write-Json $clineExtension @{mcpServers=@{
        'existing-remote'=@{type='streamableHttp';url='https://native.example';disabled=$false;oauth=@{fixture='ide-only'};autoApprove=@('read')}
        'owner-tool'=@{type='stdio';command='owner-tool'}
    }}
    $nativeHelper = @{id='devin';scope='owner-configured';transport='http';activationMode='shared-remote';url='https://devin.example/mcp';hosts=@('claude','codex')}
    $hosts.claude['devin'] = 'Preserve an existing dynamic helper.'
    $hosts.codex['devin'] = 'Preserve an existing dynamic helper.'
    [IO.File]::AppendAllText($paths.codex, "[mcp_servers.devin]`nurl = 'https://devin.example/mcp'`nhttp_headers_helper = 'native-helper'`n")
    Write-Json (Join-Path $registryDir 'mcps.json') @{activationPolicy=@{pluginOnly=@{hosts=$hosts}};mcpServers=@($parallel,$research,$clineOAuth,$clineApproved,$clineHeaders,$nativeHelper)}
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
    $ideRaw = Get-Content -LiteralPath $clineExtension -Raw -Encoding UTF8
    $ide = ($ideRaw | ConvertFrom-Json).mcpServers
    Assert-True ($ide.parallel.url -eq $parallelEndpoint -and $ide.parallel.type -eq 'streamableHttp' -and
        $ide.parallel.disabled -eq $false -and @($ide.parallel.autoApprove).Count -eq 0) 'Cline extension gets anonymous Parallel in its own settings'
    Assert-True ($ide.'cline-oauth'.disabled -eq $true -and
        $null -eq $ide.'cline-oauth'.PSObject.Properties['oauth']) 'Cline extension gets an inactive OAuth entry without copied authorization'
    Assert-True ($ide.'existing-remote'.url -eq 'https://native.example' -and $ide.'existing-remote'.oauth.fixture -eq 'ide-only' -and
        $ide.'existing-remote'.disabled -eq $false -and $ide.'existing-remote'.autoApprove[0] -eq 'read') 'Cline extension retains its existing endpoint, OAuth and approval settings'
    Assert-True ($ide.'owner-tool'.command -eq 'owner-tool' -and $null -eq $ide.PSObject.Properties['cline-headers']) 'Cline extension sync keeps local overrides and skips deployment of entries with headers'
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
    Assert-True ($oc.mcp.'existing-remote'.url -eq 'https://managed.example' -and $oc.mcp.'existing-remote'.enabled -eq $false -and
        $oc.mcp.servers.'existing-remote'.url -eq 'https://native.example' -and $oc.mcp.servers.'existing-remote'.pool -eq $true) 'OpenCode keeps an existing native override and the legacy disable switch'
    $negative = Get-Content -LiteralPath $paths.factory -Raw -Encoding UTF8
    Assert-True (-not $negative.Contains('aws.example')) 'exceptions do not leak into the next host'
    $absent = Get-Content -LiteralPath $paths.warp -Raw -Encoding UTF8
    Assert-True (-not $absent.Contains('aws-mcp')) 'an allowed native connection is not generated when absent'
    $run = & $hostExe @syncArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Second fixture sync failed: $run" }
    Assert-True ($ideRaw -ceq (Get-Content -LiteralPath $clineExtension -Raw -Encoding UTF8)) 'Cline extension settings are byte-stable on repeat apply'
    foreach ($id in $first.Keys) {
        Assert-True ($first[$id] -ceq (Get-Content -LiteralPath $paths[$id] -Raw -Encoding UTF8)) "$id is byte-stable after a second prune"
    }
    $run = & $hostExe @syncArgs -ScopeProfile all 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "All-scope fixture sync failed: $run" }
    Assert-True ((Get-Content -LiteralPath $paths.codex -Raw -Encoding UTF8) -ceq $first.codex -and
        $first.codex.Contains("http_headers_helper = 'native-helper'")) 'All-scope prune preserves an existing owner-configured helper exactly'
    $claude = Get-Content -LiteralPath $paths.claude -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($null -eq $claude.mcpServers.PSObject.Properties['devin']) 'All-scope sync does not generate an owner-configured server without its helper'
    Assert-True ($first.codex.Contains("[mcp_servers.parallel]") -and
        $first.codex.Contains("[mcp_servers.parallel-research]`nurl = '$researchEndpoint'`nenabled = false")) 'All-scope prune keeps both Codex routes and the research off switch'
    $ocResearch = $oc.mcp.servers.'parallel-research'
    Assert-True ($ocResearch.url -eq $researchEndpoint -and $ocResearch.disabled -eq $true -and
        $ocResearch.oauth.fixture -eq 'native') 'OpenCode prune keeps both routes and preserves native research consent'
    $clineSettings = Get-Content -LiteralPath $paths.cline -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($null -eq $clineSettings.mcpServers.PSObject.Properties['parallel-research'] -and
        $null -eq $ide.PSObject.Properties['parallel-research']) 'Sync does not generate an optional research connection in either Cline surface'
    Remove-Item -LiteralPath $clineExtension

    Write-Json $paths.opencode @{mcp=@{servers=@{type='remote';url='https://legacy.example'}}}
    $legacySyncArgs = $syncArgs | Where-Object { $_ -ne '-Prune' }
    $run = & $hostExe @legacySyncArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Legacy fixture sync failed: $run" }
    Assert-True (-not (Test-Path -LiteralPath $clineExtension)) 'Sync does not create a missing Cline extension settings file'
    $legacy = Get-Content -LiteralPath $paths.opencode -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($legacy.mcp.parallel.url -eq $parallelEndpoint -and $legacy.mcp.servers.url -eq 'https://legacy.example' -and
        $null -eq $legacy.mcp.servers.PSObject.Properties['parallel']) 'OpenCode keeps a legacy server named servers and writes Parallel beside it'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($scratch.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host "RESULT: $passed passed, $($failures.Count) failed"
if ($failures.Count) { exit 1 }
