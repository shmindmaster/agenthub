#Requires -Version 5.1
# Execute the canonical writer against synthetic files; never touches a live host.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/Sync-AgentHub.ps1'), [ref]$null, [ref]$null)
foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($node.Extent.Text))
}
$mcpsReg = @{mcpServers=@()}
$script:mcpMigrationAliases=@{}
$script:state=@{managedFiles=@{}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('agenthub-cline-deferred-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$path=Join-Path $fixture 'mcp.json'
$agent=[pscustomobject]@{nativePaths=@{mcp=$path}}
function Assert([bool]$Ok,[string]$Name) { if(-not $Ok){throw "FAIL: $Name"}; Write-Host "PASS: $Name" }
try {
    $seed=@{mcpServers=@{sample=@{type='streamableHttp';url='https://old.example/mcp';disabled=$true;autoApprove=@('read');headers=@{Authorization='synthetic-fixture'};oauth=@{fixture='keep'}}}}
    [IO.File]::WriteAllText($path,($seed | ConvertTo-Json -Depth 10))
    $entries=@{sample=@{type='http';url='https://new.example/mcp';headers=@{Authorization='${env:FIXTURE_UNRESOLVED}'}}; fresh=@{type='http';url='https://fresh.example/mcp'}}
    $first=Sync-HostMcp-Cline -Agent $agent -McpEntries $entries
    $result=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($result.mcpServers.sample.disabled -eq $true -and (@($result.mcpServers.sample.autoApprove) -join ',') -eq 'read') 'deferred activation and approval choice survive transport sync'
    Assert ($result.mcpServers.sample.url -eq 'https://new.example/mcp') 'canonical transport refresh still applies'
    Assert ($result.mcpServers.sample.headers.Authorization -eq 'synthetic-fixture' -and $result.mcpServers.sample.oauth.fixture -eq 'keep') 'unresolved placeholders preserve existing authentication'
    Assert ($result.mcpServers.fresh.disabled -eq $false -and @($result.mcpServers.fresh.autoApprove).Count -eq 0) 'new server uses documented defaults'
    $before=[IO.File]::ReadAllText($path)
    $second=Sync-HostMcp-Cline -Agent $agent -McpEntries $entries
    Assert ($before -eq [IO.File]::ReadAllText($path) -and $second.status -eq 'unchanged') 'second sync is byte-identical and reports unchanged'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'agenthub-cline-deferred-*') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
