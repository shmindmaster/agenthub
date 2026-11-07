#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = [IO.Directory]::CreateTempSubdirectory('agenthub-plugin-audit-')
try {
    $cli = Join-Path $root 'scripts/AgentHub.ps1'
    $output = & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId cursor -PluginId ah-browser -Json
    if ($LASTEXITCODE) { throw "Plugin audit failed: $output" }
    $report = $output | ConvertFrom-Json
    if ($report.mode -ne 'audit' -or @($report.mappings).Count -ne 1) { throw 'Expected one audit row' }
    $row = $report.mappings[0]
    if ($row.host -ne 'cursor' -or $row.plugin -ne 'ah-browser' -or $row.status -ne 'missing' -or -not $row.expected) { throw 'Incorrect filtered row' }
    if (@(Get-ChildItem $testRoot.FullName -Force).Count) { throw 'Read-only audit created files' }
    & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId cursor -PluginId ah-browser -Apply *> $null
    if ($LASTEXITCODE -eq 0 -or @(Get-ChildItem $testRoot.FullName -Force).Count) { throw 'Apply accepted an unpublished checkout or alternate profile' }
    & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $testRoot.FullName -HostId invalid-host -Json *> $null
    if ($LASTEXITCODE -eq 0) { throw 'Unknown host filter reported success' }
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Sync-Plugins.ps1'), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Plugin script has parse errors' }
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-SkillCopy' }, $true)
    Invoke-Expression $function.Extent.Text
    . (Join-Path $root 'scripts/RegistryContentHash.ps1')
    function Get-AgentHubGitTrackedRelativeFiles([string]$Path) { return @('skills/example/SKILL.md', 'scripts/example.ps1', 'mcp.json', 'agents/reviewer.md') }
    $source = Join-Path $testRoot.FullName 'source'
    $installed = Join-Path $testRoot.FullName 'installed'
    foreach ($tree in $source,$installed) {
        [void][IO.Directory]::CreateDirectory((Join-Path $tree 'skills/example'))
        [void][IO.Directory]::CreateDirectory((Join-Path $tree 'scripts'))
        [void][IO.Directory]::CreateDirectory((Join-Path $tree 'agents'))
        [IO.File]::WriteAllText((Join-Path $tree 'skills/example/SKILL.md'), '# Synthetic workflow')
        [IO.File]::WriteAllText((Join-Path $tree 'scripts/example.ps1'), 'Write-Output 1')
        [IO.File]::WriteAllText((Join-Path $tree 'mcp.json'), '{"mcpServers":{}}')
        [IO.File]::WriteAllText((Join-Path $tree 'agents/reviewer.md'), '# Synthetic reviewer')
    }
    if (-not (Test-SkillCopy $source $installed)) { throw 'Matching copy was marked stale' }
    [IO.File]::WriteAllText((Join-Path $installed 'scripts/example.ps1'), 'Write-Output 2')
    if (Test-SkillCopy $source $installed) { throw 'Script drift at the same version was ignored' }
    [IO.File]::WriteAllText((Join-Path $installed 'scripts/example.ps1'), 'Write-Output 1')
    [void][IO.Directory]::CreateDirectory((Join-Path $installed 'skills/obsolete'))
    [IO.File]::WriteAllText((Join-Path $installed 'skills/obsolete/SKILL.md'), '# Obsolete')
    if (Test-SkillCopy $source $installed) { throw 'An obsolete skill was ignored' }
    [IO.File]::Delete((Join-Path $installed 'skills/obsolete/SKILL.md'))
    [IO.Directory]::Delete((Join-Path $installed 'skills/obsolete'))
    [IO.File]::WriteAllText((Join-Path $installed 'mcp.json'), '{"mcpServers":{"foreign":{}}}')
    if (Test-SkillCopy $source $installed) { throw 'Root MCP drift was ignored' }
    [IO.File]::WriteAllText((Join-Path $installed 'mcp.json'), '{"mcpServers":{}}')
    [IO.File]::Delete((Join-Path $installed 'agents/reviewer.md'))
    if (Test-SkillCopy $source $installed) { throw 'Missing shared reviewer was ignored' }
    [IO.File]::WriteAllText((Join-Path $installed 'agents/reviewer.md'), '# Synthetic reviewer')
    foreach ($name in 'Read-Document','New-Observation','Get-ManifestObservation','Get-PluginSnapshotHash','Test-PluginRollbackSource') {
        $node = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        Invoke-Expression $node.Extent.Text
    }
    [IO.File]::WriteAllText((Join-Path $installed 'plugin.json'), '{"name":"foreign","version":"1.0.0"}')
    if ((Get-ManifestObservation $installed 'plugin.json' 'ah-browser').status -ne 'unmanaged') { throw 'Foreign manifest was treated as managed' }
    function Get-AgentHubDefaultLocalData { return $testRoot.FullName }
    $backupRoot = Join-Path $testRoot.FullName 'AgentHub/runtime/plugin-deployment'
    [void][IO.Directory]::CreateDirectory($backupRoot)
    $backup = Join-Path $backupRoot 'synthetic-backup'
    Copy-Item -LiteralPath $source -Destination $backup -Recurse
    Remove-Item Function:Get-AgentHubGitTrackedRelativeFiles
    $digest = Get-PluginSnapshotHash $backup
    @{ originalSource=$source; plugin='ah-browser'; version='1.0.0'; contentHash=$digest } |
        ConvertTo-Json | Set-Content -LiteralPath "$backup.json"
    if (-not (Test-PluginRollbackSource $backup $source 'ah-browser' '1.0.0')) { throw 'Intact rollback source lost ownership' }
    [IO.File]::WriteAllText((Join-Path $backup 'scripts/example.ps1'), 'Write-Output 999')
    if (Test-PluginRollbackSource $backup $source 'ah-browser' '1.0.0') { throw 'Modified rollback source retained ownership' }
    Write-Host 'RESULT: 12 passed, 0 failed'
} finally {
    $resolved = (Get-Item -LiteralPath $testRoot.FullName).FullName
    if ($resolved -eq $testRoot.FullName -and (Split-Path -Parent $resolved) -eq $testRoot.Parent.FullName) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
