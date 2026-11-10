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
    function Get-AgentHubGitTrackedRelativeFiles([string]$Path) { return @('skills/example/SKILL.md', '.mcp.json', 'mcp_config.json', 'agents/reviewer.md') }
    [IO.File]::WriteAllText((Join-Path $source '.mcp.json'), "{`n  `"mcpServers`": {`n    `"synthetic`": { `"command`": `"pyw`" }`n  }`n}")
    [IO.File]::WriteAllText((Join-Path $source 'mcp_config.json'), '{"mcpServers":{"synthetic":{}}}')
    $droid = Join-Path $testRoot.FullName 'droid'
    [void][IO.Directory]::CreateDirectory((Join-Path $droid 'skills/example'))
    [void][IO.Directory]::CreateDirectory((Join-Path $droid 'droids'))
    [IO.File]::WriteAllText((Join-Path $droid 'skills/example/SKILL.md'), '# Synthetic workflow')
    [IO.File]::WriteAllText((Join-Path $droid 'droids/reviewer.md'), '# Synthetic reviewer')
    [IO.File]::WriteAllText((Join-Path $droid 'mcp.json'), '{"mcpServers":{"synthetic":{"command":"pyw"}}}')
    if (-not (Test-SkillCopy $source $droid 'factory')) { throw 'Droid renamed install was marked stale' }
    [IO.File]::WriteAllText((Join-Path $droid 'mcp.json'), '{"mcpServers":{"synthetic":{"command":"python"}}}')
    if (Test-SkillCopy $source $droid 'factory') { throw 'Droid MCP drift was ignored' }
    if (Test-SkillCopy $source $droid 'claude') { throw 'Droid renames were accepted for another host' }
    $agy = Join-Path $testRoot.FullName 'agy'
    [void][IO.Directory]::CreateDirectory((Join-Path $agy 'skills/example'))
    [void][IO.Directory]::CreateDirectory((Join-Path $agy 'agents'))
    [IO.File]::WriteAllText((Join-Path $agy 'skills/example/SKILL.md'), '# Synthetic workflow')
    [IO.File]::WriteAllText((Join-Path $agy 'agents/reviewer.md'), '# Synthetic reviewer')
    [IO.File]::WriteAllText((Join-Path $agy 'mcp_config.json'), '{"mcpServers":{"synthetic":{}}}')
    if (-not (Test-SkillCopy $source $agy 'antigravity')) { throw 'Antigravity projection without other hosts MCP files was marked stale' }
    [IO.File]::WriteAllText((Join-Path $agy 'mcp_config.json'), '{"mcpServers":{"foreign":{}}}')
    if (Test-SkillCopy $source $agy 'antigravity') { throw 'Antigravity MCP config drift was ignored' }
    function Get-AgentHubGitTrackedRelativeFiles([string]$Path) { return @('skills/example/SKILL.md', 'scripts/example.ps1', 'mcp.json', 'agents/reviewer.md') }
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

    # --- Host-local skill projections: kilo (~/.kilocode/skills) and mimo-code
    # (~/.mimocode/skills) observe the dispatch skill through the same junction
    # contract as OpenCode and Warp. Junction on Windows, SymbolicLink elsewhere.
    function New-TestLink([string]$Path, [string]$Target) {
        $kind = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $kind -Path $Path -Target $Target | Out-Null
    }
    $skillHome = Join-Path $testRoot.FullName 'skillhome'
    [void][IO.Directory]::CreateDirectory($skillHome)
    $audit = & pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $skillHome -PluginId coding-agent-dispatch -Json
    if ($LASTEXITCODE) { throw "dispatch audit failed: $audit" }
    $dispatchReport = $audit | ConvertFrom-Json
    $kiloStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'kilo')).status
    $mimoStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'mimo-code')).status
    if ($kiloStatus -ne 'missing' -or $mimoStatus -ne 'missing') { throw "uninstalled skill links should audit missing, got kilo=$kiloStatus mimo-code=$mimoStatus" }
    if (@(Get-ChildItem $skillHome -Force).Count) { throw 'Read-only audit created files in the skill home' }
    $dispatchSkill = Join-Path $root 'packages/coding-agent-dispatch/skills/dispatch'
    [void][IO.Directory]::CreateDirectory((Join-Path $skillHome '.kilocode/skills'))
    [void][IO.Directory]::CreateDirectory((Join-Path $skillHome '.mimocode/skills'))
    New-TestLink (Join-Path $skillHome '.kilocode/skills/dispatch') $dispatchSkill
    New-TestLink (Join-Path $skillHome '.mimocode/skills/dispatch') $dispatchSkill
    $dispatchReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $skillHome -PluginId coding-agent-dispatch -Json | ConvertFrom-Json)
    $kiloStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'kilo')).status
    $mimoStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'mimo-code')).status
    if ($kiloStatus -ne 'current' -or $mimoStatus -ne 'current') { throw "linked dispatch skill not current: kilo=$kiloStatus mimo-code=$mimoStatus" }
    Remove-Item -LiteralPath (Join-Path $skillHome '.kilocode/skills/dispatch') -Force
    New-TestLink (Join-Path $skillHome '.kilocode/skills/dispatch') (Join-Path $root 'packages/browser/skills/automate')
    Remove-Item -LiteralPath (Join-Path $skillHome '.mimocode/skills/dispatch') -Force
    [void][IO.Directory]::CreateDirectory((Join-Path $skillHome '.mimocode/skills/dispatch'))
    $dispatchReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $skillHome -PluginId coding-agent-dispatch -Json | ConvertFrom-Json)
    $kiloStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'kilo')).status
    $mimoStatus = [string](@($dispatchReport.mappings | Where-Object host -EQ 'mimo-code')).status
    if ($kiloStatus -ne 'unmanaged' -or $mimoStatus -ne 'unmanaged') { throw "foreign skill content not unmanaged: kilo=$kiloStatus mimo-code=$mimoStatus" }

    # --- Surface routing: cursor-agent and vscode-insiders observe through
    # their declared native owner; one owner install satisfies both rows. ---
    $aliasHome = Join-Path $testRoot.FullName 'aliashome'
    [void][IO.Directory]::CreateDirectory($aliasHome)
    $dispatchReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $aliasHome -PluginId coding-agent-dispatch -Json | ConvertFrom-Json)
    $surfaceRow = @($dispatchReport.mappings | Where-Object host -EQ 'cursor-agent')
    $insiderRow = @($dispatchReport.mappings | Where-Object host -EQ 'vscode-insiders')
    if ([string]$surfaceRow.nativeOwnerHost -ne 'cursor' -or [string]$surfaceRow.status -ne 'missing') { throw "cursor-agent should audit missing through cursor, got status=$($surfaceRow.status) owner=$($surfaceRow.nativeOwnerHost)" }
    if ([string]$insiderRow.nativeOwnerHost -ne 'copilot' -or [string]$insiderRow.status -ne 'blocked') { throw "vscode-insiders should stay blocked on the absent copilot registration, got status=$($insiderRow.status) owner=$($insiderRow.nativeOwnerHost)" }
    $cursorPlugin = Join-Path $aliasHome '.cursor/plugins/local/ah-coding-agent-dispatch'
    Copy-Item -LiteralPath (Join-Path $root 'packages/coding-agent-dispatch') -Destination $cursorPlugin -Recurse
    $dispatchReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $aliasHome -PluginId coding-agent-dispatch -Json | ConvertFrom-Json)
    $surfaceRow = @($dispatchReport.mappings | Where-Object host -EQ 'cursor-agent')
    $cursorRow = @($dispatchReport.mappings | Where-Object host -EQ 'cursor')
    if ([string]$surfaceRow.status -ne 'current' -or [string]$cursorRow.status -ne 'current') { throw "owner install not observed by surface rows: cursor=$($cursorRow.status) cursor-agent=$($surfaceRow.status)" }
    [IO.File]::WriteAllText((Join-Path $cursorPlugin 'plugin.json'), '{"name":"foreign","version":"9.9.9"}')
    $dispatchReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $root -UserProfile $aliasHome -PluginId coding-agent-dispatch -Json | ConvertFrom-Json)
    $surfaceRow = @($dispatchReport.mappings | Where-Object host -EQ 'cursor-agent')
    $cursorRow = @($dispatchReport.mappings | Where-Object host -EQ 'cursor')
    if ([string]$surfaceRow.status -ne 'unmanaged' -or [string]$cursorRow.status -ne 'unmanaged') { throw "foreign owner content not unmanaged on both rows: cursor=$($cursorRow.status) cursor-agent=$($surfaceRow.status)" }

    # --- Invalid nativeOwnerHost declarations are rejected before any
    # observation or mutation. ---
    $fakeRoot = Join-Path $testRoot.FullName 'fakeroot'
    [void][IO.Directory]::CreateDirectory((Join-Path $fakeRoot 'scripts'))
    Copy-Item -LiteralPath (Join-Path $root 'scripts/Sync-Plugins.ps1') -Destination (Join-Path $fakeRoot 'scripts/Sync-Plugins.ps1')
    Copy-Item -LiteralPath (Join-Path $root 'scripts/RegistryContentHash.ps1') -Destination (Join-Path $fakeRoot 'scripts/RegistryContentHash.ps1')
    Copy-Item -LiteralPath (Join-Path $root 'scripts/lib') -Destination (Join-Path $fakeRoot 'scripts/lib') -Recurse
    [void][IO.Directory]::CreateDirectory((Join-Path $fakeRoot 'registry'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fakeRoot 'packages/fake-cap/skills/fake'))
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'packages/fake-cap/plugin.json'), '{"name":"ah-fake-cap","version":"1.0.0"}')
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'packages/fake-cap/skills/fake/SKILL.md'), '# fake')
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'registry/mcps.json'), '{"activationPolicy":{"pluginOnly":{"hosts":{"claude":{}}}}}')
    [void][IO.Directory]::CreateDirectory((Join-Path $fakeRoot 'packages/repowise/skills/fake'))
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'packages/repowise/plugin.json'), '{"name":"repowise","version":"1.0.0"}')
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'packages/repowise/skills/fake/SKILL.md'), '# fake')
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'registry/agents.json'), (@{ activeAgents = @('owner-a','owner-b','owner-c','surf-a','surf-c','surf-d','surf-x','surf-y','gemini','opencode','surf-g','surf-o','surf-r') | ForEach-Object { @{ id = $_; executable = 'x' } } } | ConvertTo-Json -Depth 5))
    [IO.File]::WriteAllText((Join-Path $fakeRoot 'registry/capabilities.json'), (@{ capabilities = @(
        @{ id = 'fake-cap'; canonicalSource = 'packages/fake-cap'; hostMappings = @(
            @{ hostId = 'surf-a'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'ghost-owner' },
            @{ hostId = 'surf-c'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'owner-b' },
            @{ hostId = 'owner-b'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'owner-c' },
            @{ hostId = 'owner-c'; deploymentStatus = 'native-local-plugin' },
            @{ hostId = 'surf-d'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'owner-a' },
            @{ hostId = 'surf-x'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'surf-y' },
            @{ hostId = 'surf-y'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'surf-x' },
            @{ hostId = 'gemini'; deploymentStatus = 'native-local-plugin' },
            @{ hostId = 'surf-g'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'gemini' }
        ) },
        @{ id = 'repowise'; canonicalSource = 'packages/repowise'; hostMappings = @(
            @{ hostId = 'opencode'; deploymentStatus = 'managed-loose-skills' },
            @{ hostId = 'surf-o'; deploymentStatus = 'managed-loose-skills'; nativeOwnerHost = 'opencode' },
            @{ hostId = 'surf-r'; deploymentStatus = 'native-local-plugin'; nativeOwnerHost = 'opencode' }
        ) }
    ) } | ConvertTo-Json -Depth 10))
    $fakeReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $fakeRoot -UserProfile $skillHome -PluginId fake-cap -Json | ConvertFrom-Json)
    $fakeRows = @{}
    foreach ($m in @($fakeReport.mappings)) { $fakeRows[$m.host] = [string]$m.status }
    foreach ($case in 'surf-a','surf-c','surf-d','surf-x','surf-y','surf-g') {
        if ($fakeRows[$case] -ne 'blocked') { throw "invalid owner declaration accepted on $case ($($fakeRows[$case]))" }
    }
    $detail = [string](@($fakeReport.mappings | Where-Object host -EQ 'surf-a')).detail
    if ($detail -notmatch 'ghost-owner') { throw "unknown owner was not named in the refusal: $detail" }
    if (-not ([string](@($fakeReport.mappings | Where-Object host -EQ 'surf-g')).detail -match 'Gemini rollout is disabled')) { throw 'Alias to the disabled Gemini owner did not inherit the owner block' }
    # The repowise capability carries an owner-routed blocked route on opencode:
    # both aliased surfaces must inherit the block, and a misleading surface
    # deploymentStatus must not override the owner's effective route.
    $repoReport = (& pwsh -NoProfile -File $cli plugins -RepositoryRoot $fakeRoot -UserProfile $skillHome -PluginId repowise -Json | ConvertFrom-Json)
    $surfO = @($repoReport.mappings | Where-Object host -EQ 'surf-o')
    $surfR = @($repoReport.mappings | Where-Object host -EQ 'surf-r')
    if ([string]$surfO.status -ne 'blocked' -or [string]$surfR.status -ne 'blocked') { throw "alias rows escaped the owner's blocked repowise route: surf-o=$($surfO.status) surf-r=$($surfR.status)" }
    if ([string]$surfR.route -ne 'managed-loose-skills') { throw "misleading surface route was not overridden by the owner route: $($surfR.route)" }

    # --- Rollback and pending-row helpers resolve through the native owner. ---
    foreach ($name in 'Get-RowNativeHost','Invoke-PluginRollback','Test-PluginRowPending') {
        $function = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1
        Invoke-Expression $function.Extent.Text
    }
    $liveProfile = $testRoot.FullName
    $rollbackDest = Join-Path $liveProfile 'plugins/alias-prev'
    $rollbackBackup = Join-Path $testRoot.FullName 'rollback-backup'
    [void][IO.Directory]::CreateDirectory($rollbackBackup)
    [IO.File]::WriteAllText((Join-Path $rollbackBackup 'plugin.json'), '{"name":"ah-x","version":"1.0.0"}')
    $aliasRow = [pscustomobject]@{ host = 'cursor-agent'; nativeOwnerHost = 'cursor'; plugin = 'ah-x'; capability = 'x' }
    Invoke-PluginRollback -Row $aliasRow -Entry ([pscustomobject]@{ previous = 'prev'; previousPath = $rollbackDest }) -Backup $rollbackBackup
    if (-not (Test-Path (Join-Path $rollbackDest 'plugin.json'))) { throw 'Alias rollback did not restore through the owner copy branch' }
    # A stubbed change sequence: two rows sharing one owner install once.
    function Set-PluginStatus($Row, [switch]$Fresh) { $Row.status = if ($script:ownerInstalled) { 'current' } else { 'missing' } }
    $script:ownerInstalled = $false
    $installs = 0
    $ownerRow = [pscustomobject]@{ host = 'cursor'; nativeOwnerHost = 'cursor'; status = 'missing' }
    $surfaceRow = [pscustomobject]@{ host = 'cursor-agent'; nativeOwnerHost = 'cursor'; status = 'missing' }
    foreach ($pendingRow in @($ownerRow, $surfaceRow)) {
        if (-not (Test-PluginRowPending $pendingRow)) { continue }
        $installs++
        $script:ownerInstalled = $true
    }
    if ($installs -ne 1) { throw "two rows sharing an owner triggered $installs installs" }
    Write-Host 'RESULT: 32 passed, 0 failed'
} finally {
    $resolved = (Get-Item -LiteralPath $testRoot.FullName).FullName
    if ($resolved -eq $testRoot.FullName -and (Split-Path -Parent $resolved) -eq $testRoot.Parent.FullName) {
        Remove-Item -LiteralPath $resolved -Force -Recurse
    }
}
