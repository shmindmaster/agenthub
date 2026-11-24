#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/lib/PluginPaths.ps1')
. (Join-Path $root 'scripts/lib/PluginCleanup.ps1')
function Read-Document([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
}

$fixture = Resolve-AgentHubPhysicalPath ([IO.Directory]::CreateTempSubdirectory('agenthub-cleanup-test-').FullName)
try {
    $base = Join-Path $fixture 'cache'
    foreach ($v in '1.0.0','1.1.0','1.2.0','2.0.0','9.0.0') {
        $dir = Join-Path $base $v
        [void][IO.Directory]::CreateDirectory($dir)
        $name = if ($v -eq '1.1.0') { 'third-party' } else { 'ah-browser' }
        [IO.File]::WriteAllText((Join-Path $dir 'plugin.json'), (@{name=$name;version=$v} | ConvertTo-Json))
    }
    $active = Join-Path $base '2.0.0'
    $retained = Join-Path $base '1.2.0'
    $plan = @(Get-AgentHubOldPluginVersions -HostId codex -Plugin ah-browser -Root $base -ActivePath $active -Version '2.0.0' -RegisteredPaths @((Join-Path $retained 'project')))
    if (@($plan | Where-Object status -eq pending).target -ne (Join-Path $base '1.0.0') -or
        @($plan | Where-Object status -eq unmanaged).target -ne (Join-Path $base '1.1.0') -or $plan.Count -ne 2) {
        throw 'Cache plan did not preserve foreign, active, scoped and newer versions.'
    }
    $link = Join-Path $base '1.0.1'
    $outside = Join-Path $fixture 'outside'
    [void][IO.Directory]::CreateDirectory($outside)
    $kind = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $kind -Path $link -Target $outside | Out-Null
    if (Test-AgentHubPluginTree $base $link) { throw 'Cleanup accepted a linked cache directory.' }
    if (Test-AgentHubPluginTree $base $outside) { throw 'Cleanup accepted a path outside its root.' }
    [IO.Directory]::Delete($link, $false)

    $scopeAlias = Join-Path $fixture 'scope-alias'
    New-Item -ItemType $kind -Path $scopeAlias -Target $base | Out-Null
    $referenced = @(Get-AgentHubOldPluginVersions -HostId claude -Plugin ah-browser -Root $base -ActivePath $active -Version '2.0.0' -RegisteredPaths @(
        (Join-Path $scopeAlias '1.0.0/project'), $retained
    ))
    if ($referenced.status -contains 'pending') { throw 'A project registration through a link did not protect its physical cache.' }
    [IO.Directory]::Delete($scopeAlias, $false)

    $cfg = Join-Path $fixture 'config.json'
    $direct = @{name='ah-research';source=@{source='github';repo='shmindmaster/agenthub';path='packages/research'}}
    $fork = @{name='ah-research';source=@{source='github';repo='someone/agenthub';path='packages/research'}}
    $raw = (@{installedPlugins=@($direct,$fork);theme='test'} | ConvertTo-Json -Depth 7)
    [IO.File]::WriteAllText($cfg,$raw)
    if (-not $IsWindows) {
        $privateMode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
        [IO.File]::SetUnixFileMode($cfg, $privateMode)
    }
    try { Remove-AgentHubCopilotDirectRegistration $cfg ah-research 'packages/research' { $false }; throw 'Expected rollback.' }
    catch { if ($_.Exception.Message -notmatch 'did not verify') { throw } }
    if ([IO.File]::ReadAllText($cfg) -cne $raw) { throw 'Copilot did not roll back failed readback.' }
    Remove-AgentHubCopilotDirectRegistration $cfg ah-research 'packages/research' { $true }
    $result = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $IsWindows -and [IO.File]::GetUnixFileMode($cfg) -ne $privateMode) { throw 'Copilot configuration mode changed.' }
    if ($result.theme -ne 'test' -or @($result.installedPlugins).Count -ne 1 -or $result.installedPlugins[0].source.repo -ne 'someone/agenthub') {
        throw 'Copilot changed an unrelated registration or setting.'
    }

    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Sync-Plugins.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Sync parse failure.' }
    foreach ($name in 'Get-PluginCleanup','Get-PluginCleanupPlan','Get-RowNativeHost') {
        $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
    $UserProfile = $fixture
    $HostId = ''
    $live = $true
    $script:freshStatus = 'current'
    $script:busy = $false
    $script:calls = 0
    $script:canonicalEnabled = $true
    function Test-AgentHubPluginHostBusy { return $script:busy }
    function Get-ListedPlugin { return $script:copilotCatalog }
    function Get-PluginClientList($Command) {
        if ($Command -eq 'copilot') {
            return $script:copilotCatalog, [pscustomobject]@{name='ah-research'; source='installed'}
        }
        @(
            @{pluginId='ah-media-studio@agenthub'; name='ah-media-studio'; enabled=$script:canonicalEnabled},
            @{pluginId='ah-media-studio@created-by-me-remote'; name='ah-media-studio'},
            @{pluginId='ah-media-studio@independent'; name='ah-media-studio'}
        ) | ForEach-Object { [pscustomobject]$_ }
    }
    function Set-PluginStatus($Row, [switch]$Fresh) { $Row.status = $script:freshStatus }
    function Invoke-PluginCleanup($Row, $Candidate) {
        if ($Candidate.kind -ne 'codex-retired-registration') { throw 'Unexpected mutation' }
        $script:calls++
    }
    $row = [pscustomobject]@{host='codex';plugin='ah-media-studio';marketplace='agenthub';expected='2.0.0';status='current'}
    $readOnly = @(Get-PluginCleanupPlan @($row))
    if ($readOnly.Count -ne 2 -or $readOnly.status -notcontains 'unmanaged' -or $script:calls) { throw 'Audit mutated or ignored an alternate marketplace.' }
    $script:freshStatus = 'drift'
    $null = Get-PluginCleanupPlan @($row) -Execute
    if ($script:calls) { throw 'Cleanup ran after replacement lost parity.' }
    $script:freshStatus = 'current'
    $row.status = 'current'
    $script:canonicalEnabled = $false
    if (@(Get-PluginCleanupPlan @($row) -Execute | Where-Object status -eq unmanaged).Count -ne 2 -or $script:calls) {
        throw 'Disabled Codex replacement did not preserve the legacy registration.'
    }
    $script:canonicalEnabled = $true
    $apply = @(Get-PluginCleanupPlan @($row,$row) -Execute)
    if ($script:calls -ne 1 -or $apply.status -notcontains 'removed' -or $apply.status -notcontains 'unmanaged') {
        throw 'Apply did not remove only the known retired registration once.'
    }
    $codexCache = Join-Path $fixture '.codex/plugins/cache/agenthub/ah-browser'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $codexCache))
    [IO.Directory]::Move($base, $codexCache)
    $row = [pscustomobject]@{host='codex';plugin='ah-browser';marketplace='agenthub';expected='2.0.0';status='current';previousPath=(Join-Path $codexCache '2.0.0')}
    $script:busy = $true
    if ((Get-PluginCleanupPlan @($row) -Execute).status -notcontains 'deferred' -or $script:calls -ne 1) {
        throw 'An open host did not defer old cache cleanup.'
    }
    $script:busy = $false

    $copilotDir = Join-Path $fixture '.copilot'
    $copilotRow = [pscustomobject]@{host='copilot';plugin='ah-research';marketplace='agenthub';expected='2.0.0';status='current';relative='packages/research'}
    $script:copilotCatalog = [pscustomobject]@{name='ah-research';marketplace='agenthub';source='live';installedFrom=$outside}
    $managedConfig = @{'installedPlugins'=@($direct)} | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $outside 'config.json'), $managedConfig)
    New-Item -ItemType $kind -Path $copilotDir -Target $outside | Out-Null
    if ((Get-PluginCleanupPlan @($copilotRow) -Execute).status -ne 'unmanaged') { throw 'Unknown Copilot catalog was not reported and preserved.' }
    $script:copilotCatalog.installedFrom = $root
    if ((Get-PluginCleanupPlan @($copilotRow) -Execute).status -ne 'unmanaged' -or $script:calls -ne 1) { throw 'Linked Copilot configuration was not preserved.' }
    [IO.Directory]::Delete($copilotDir, $false)
    [void][IO.Directory]::CreateDirectory($copilotDir)
    [IO.File]::WriteAllText((Join-Path $copilotDir 'config.json'), $managedConfig)
    if ((Get-PluginCleanupPlan @($copilotRow)).status -ne 'pending') { throw 'Verified Copilot direct duplicate was not detected.' }

    $local = Join-Path $fixture '.cursor/plugins/local/ah-media-studio'
    $claudeRegistry = Join-Path $fixture '.claude/plugins/installed_plugins.json'
    [void][IO.Directory]::CreateDirectory($local)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $claudeRegistry))
    [IO.File]::WriteAllText($claudeRegistry, '{"plugins":{"ah-media-studio@agenthub":[{"scope":"user"}]}}')
    $row = [pscustomobject]@{host='cursor';nativeOwnerHost='claude';plugin='ah-media-studio';marketplace='agenthub';expected='2.0.0';status='current'}
    if ((Get-PluginCleanupPlan @($row) -Execute).status -ne 'unmanaged' -or $script:calls -ne 1) {
        throw 'An unverified Cursor import should preserve the local copy.'
    }
    [IO.File]::WriteAllText($claudeRegistry, '{invalid json')
    if ((Get-PluginCleanupPlan @($row) -Execute).status -ne 'unmanaged') { throw 'Corrupt Claude registry did not fail safely.' }
    Write-Output 'RESULT: plugin cleanup ownership, audit, readback, deduplication and rollback passed'
} finally {
    [IO.Directory]::Delete($fixture, $true)
}
