#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$UserProfile,
    [string]$HostId,
    [string]$PluginId,
    [switch]$Json,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/CapabilityGraph.ps1')
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
. (Join-Path $PSScriptRoot 'lib/PathBinding.ps1')
. (Join-Path $PSScriptRoot 'lib/PluginTransaction.ps1')
$liveProfile = [IO.Path]::GetFullPath((Get-AgentHubDefaultHome))
$live = $UserProfile.TrimEnd('\', '/') -eq $liveProfile.TrimEnd('\', '/')
$root = $RepositoryRoot.Replace('\', '/')
$overlay = Get-AgentHubOverlayRoot -RepositoryRoot $root
$agents = Get-Content (Join-Path $root 'registry/agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities = Get-Content (Join-Path $root 'registry/capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mcpRegistry = Get-Content (Join-Path $root 'registry/mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$hostCatalog = @{}
foreach ($agent in $agents.activeAgents) { $hostCatalog[$agent.id] = $agent }
if ($HostId -and -not $hostCatalog.ContainsKey($HostId)) { throw "Unknown active host: $HostId" }

function Read-Document([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Invoke-Client([string]$Command, [string[]]$Arguments) {
    $exe = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "Client unavailable: $Command" }
    $output = @(& $exe @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "$Command exited $LASTEXITCODE" }
    return ($output -join [Environment]::NewLine)
}

function New-Observation([string]$Version, [string]$Path, [string]$Status, [string]$Detail) {
    return @{ version = $Version; path = $Path; status = $Status; detail = $Detail }
}

function Get-ManifestObservation([string]$Path, [string]$Manifest = 'plugin.json', [string]$ExpectedName) {
    if (-not $Path) { return }
    $doc = Read-Document (Join-Path $Path $Manifest)
    if ($doc.version) {
        if ($ExpectedName -and $doc.name -ne $ExpectedName) { return New-Observation '' '' 'unmanaged' 'Installed package identity differs from the registered owner.' }
        return New-Observation $doc.version $Path
    }
    if (Test-Path -LiteralPath $Path) { return New-Observation '' '' 'unmanaged' 'Existing package has no recognizable manifest.' }
}

function Get-VersionedObservation([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending)
    if ($dirs.Count) { return Get-ManifestObservation $dirs[0].FullName 'plugin.json' (Split-Path -Leaf $Path) }
}

function Get-LinkedObservation([string]$Path, [string]$Source) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $target = $item.ResolveLinkTarget($true)
    if (-not $target -or [IO.Path]::GetFullPath($target.FullName) -ne [IO.Path]::GetFullPath($Source)) {
        return New-Observation '' '' 'unmanaged' "Existing path has a different owner: $Path"
    }
    return New-Observation '' $target.FullName 'current'
}

$clientLists = @{}
function Get-ListedPlugin([string]$Command, [string]$Name, [switch]$Fresh) {
    if (-not $live) { return }
    if ($Fresh -or -not $clientLists.ContainsKey($Command)) {
        $clientLists[$Command] = @(Invoke-Client $Command @('plugin','list','--json') | ConvertFrom-Json)
    }
    return $clientLists[$Command] | Where-Object name -eq $Name | Select-Object -First 1
}

function Get-PluginSnapshotHash([string]$Path) {
    $base = [IO.Path]::GetFullPath($Path)
    $entries = @(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction Stop)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw 'Package backup contains a link. Snapshot ownership cannot be established.'
    }
    $records = foreach ($file in @($entries | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)) {
        [ordered]@{
            path=[IO.Path]::GetRelativePath($base, $file.FullName).Replace('\\','/')
            hash=Get-AgentHubStableFileHash $file.FullName
        }
    }
    if (-not @($records).Count) { throw 'Package backup is empty.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($records) -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash($bytes)) }
    finally { $sha.Dispose() }
}

function Test-PluginRollbackSource([string]$Candidate, [string]$OriginalSource, [string]$Name, [string]$Version) {
    if (-not $Candidate) { return $false }
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub/runtime/plugin-deployment')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($Candidate)
    if (-not $full.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $record = Read-Document "$full.json"
    if ($record.originalSource -ne $OriginalSource -or $record.plugin -ne $Name -or $record.version -ne $Version) { return $false }
    return $record.contentHash -eq (Get-PluginSnapshotHash $full)
}

function Get-PluginObservation($Row, [switch]$Fresh) {
    $name = $Row.plugin
    $market = $Row.marketplace
    $source = $Row.source
    if ($Row.route -eq 'vendor') {
        if ($Row.host -eq 'claude') {
            $reg = Read-Document (Join-Path $UserProfile '.claude/plugins/installed_plugins.json')
            $entry = @($reg.plugins.'repowise@repowise') | Select-Object -Last 1
            if ($entry.version) { return New-Observation $entry.version $entry.installPath 'vendor-managed' }
        } elseif ($Row.host -eq 'codex') {
            $entry = Get-VersionedObservation (Join-Path $UserProfile '.codex/plugins/cache/repowise/codex')
            if ($entry) { $entry.status = 'vendor-managed'; return $entry }
        }
        return New-Observation '' '' 'blocked' 'Verify the approved vendor plugin with its own installer.'
    }
    if ($Row.route -eq 'runtime') {
        $local = Get-AgentHubIsolatedLocalData -TargetUserProfile $UserProfile -InvokingUserProfile $liveProfile -LocalAppData (Get-AgentHubDefaultLocalData) -AlwaysIsolateOnOverride -Platform (Get-AgentHubRequestedPlatform -RepositoryRoot $root)
        $base = Join-Path $local 'AgentHub'
        $runtime = Get-ManifestObservation (Join-Path $base $Row.catalog.runtimeRelativeRoot)
        $authority = Join-Path $base $Row.catalog.authorityRuntimeRelativeRoot
        $installedRegistry = Join-Path $authority 'agents.json'
        if ($runtime -and (-not (Test-Path -LiteralPath $installedRegistry -PathType Leaf) -or
            (Get-AgentHubStableFileHash $installedRegistry) -ne (Get-AgentHubStableFileHash (Join-Path $root 'registry/agents.json')))) {
            $runtime.status = 'drift'
            $runtime.detail = 'Deployed authority registry is missing or differs.'
        }
        return $runtime
    }
    switch ($Row.host) {
        'claude' {
            $reg = Read-Document (Join-Path $UserProfile '.claude/plugins/installed_plugins.json')
            $entry = @($reg.plugins."$name@$market") | Where-Object scope -EQ 'user' | Select-Object -Last 1
            if ($entry.version) { return New-Observation $entry.version $entry.installPath }
        }
        'codex' { return Get-VersionedObservation (Join-Path $UserProfile ".codex/plugins/cache/$market/$name") }
        'qoder' { return Get-VersionedObservation (Join-Path $UserProfile ".qoder/plugins/cache/$market/$name") }
        'cursor' { return Get-ManifestObservation (Join-Path $UserProfile ".cursor/plugins/local/$name") 'plugin.json' $name }
        'amp' {
            $path = Join-Path $UserProfile ".config/amp/plugins/$name"
            $metadata = Read-Document (Join-Path $path '.source.json')
            if ($metadata) {
                if ($metadata.package -ne $Row.relative) { return New-Observation '' '' 'unmanaged' 'Amp registration points at a different package.' }
                return New-Observation $metadata.version $path
            }
            if (Test-Path -LiteralPath $path) { return New-Observation '' '' 'unmanaged' 'Amp folder has no AgentHub source receipt.' }
        }
        'antigravity' {
            if ($live) {
                $entry = Get-ListedPlugin agy $name -Fresh:$Fresh
                if ($entry) { return New-Observation $entry.version $entry.path }
            } else { return Get-ManifestObservation (Join-Path $UserProfile ".gemini/config/plugins/$name") '.antigravity-plugin/plugin.json' }
        }
        'grok' {
            $entry = Get-ListedPlugin grok $name -Fresh:$Fresh
            if ($entry) {
                if ($entry.source -ne $source.Replace('\', '/') -and -not (Test-PluginRollbackSource $entry.source $source $name $entry.version)) {
                    return New-Observation '' '' 'unmanaged' 'Grok registration uses a different source.'
                }
                return New-Observation $entry.version $entry.path
            }
        }
        'copilot' {
            $entry = Get-ListedPlugin copilot $name -Fresh:$Fresh
            if ($entry.marketplace -eq $market) { return New-Observation $entry.version $source }
            if ($entry) { return New-Observation '' '' 'unmanaged' 'Copilot registration uses a different marketplace.' }
        }
        'devin' {
            if ($live -and (Get-Command devin -ErrorAction SilentlyContinue)) {
                $info = & devin plugins info $name 2>$null | Out-String
                if ($LASTEXITCODE -eq 0 -and $info -match '(?m)^\s+version:\s+(\S+)') {
                    $version = $Matches[1]
                    if ($info -notmatch '(?m)^\s+source:\s+(.+?)\s*$' -or $Matches[1] -ne $source) {
                        return New-Observation '' '' 'unmanaged' 'Devin registration uses a different source.'
                    }
                    return New-Observation $version ''
                }
            }
        }
        'factory' {
            $cache = Join-Path $UserProfile '.factory/plugins/cache'
            $candidates = foreach ($marketDir in @(Get-ChildItem -Path (Join-Path $cache "$market-*") -Directory -ErrorAction SilentlyContinue)) {
                foreach ($pluginDir in @(Get-ChildItem -Path (Join-Path $marketDir.FullName "$name-*") -Directory -ErrorAction SilentlyContinue)) {
                    foreach ($revision in Get-ChildItem -LiteralPath $pluginDir.FullName -Directory) {
                        Get-ManifestObservation $revision.FullName 'plugin.json' $name
                    }
                }
            }
            return $candidates | Sort-Object { [version]$_.version } -Descending | Select-Object -First 1
        }
        'cline' { return Get-LinkedObservation (Join-Path $UserProfile ".agents/plugins/$name") $source }
        { $_ -in 'opencode', 'warp' } {
            $hostHome = if ($_ -eq 'warp') { '.warp' } else { '.config/opencode' }
            $expectedLinks = @{}
            foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $source 'skills') -Directory) {
                if (Test-Path (Join-Path $skill.FullName 'SKILL.md')) { $expectedLinks["skills/$($skill.Name)"] = $skill.FullName }
            }
            if ($name -eq 'ah-product') {
                foreach ($folder in 'scripts', 'references', 'kits') { $expectedLinks[$folder] = Join-Path $source $folder }
            }
            $missing = $false
            foreach ($link in $expectedLinks.Keys) {
                $item = Get-LinkedObservation (Join-Path (Join-Path $UserProfile $hostHome) $link) $expectedLinks[$link]
                if ($item.status -eq 'unmanaged') { return $item }
                if (-not $item) { $missing = $true }
            }
            if (-not $missing -and $expectedLinks.Count) { return New-Observation '' $source 'current' }
        }
        'vscode-insiders' {
            $settingsPath = Join-Path $UserProfile 'AppData/Roaming/Code - Insiders/User/settings.json'
            # VS Code uses JSONC. Match just the path entry in chat.pluginLocations.
            if (Test-Path -LiteralPath $settingsPath) {
                $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
                if ($settings -match '(?s)"chat\.pluginLocations"\s*:\s*\{([^}]+)\}') {
                    $locations = $Matches[1]
                    foreach ($path in $source, $source.Replace('\', '/')) {
                        $key = [regex]::Escape(($path | ConvertTo-Json -Compress))
                        if ($locations -match "$key\s*:\s*true\b") { return New-Observation '' $source 'current' }
                    }
                }
            }
        }
    }
}

function Test-SkillCopy([string]$Source, [string]$Destination, [string]$Client) {
    if (-not (Test-Path -LiteralPath (Join-Path $Destination 'skills'))) { return $false }
    $gitFiles = if ($Source.Replace('\','/') -match '/overlays/personal/') {
        @(Get-AgentHubFilesystemRelativeFiles -Path $Source)
    } else { @(Get-AgentHubGitTrackedRelativeFiles -Path $Source) }
    $managed = @($gitFiles | Where-Object {
        $_ -match '^(skills|scripts|references|assets|kits|schemas|policy|kit)/' -or
        ($Client -ne 'amp' -and $_ -in 'mcp.json','.mcp.json') -or
        ($Client -ne 'amp' -and -not ($Client -eq 'antigravity' -and (Split-Path -Leaf $Source) -eq 'product') -and $_ -match '^agents/')
    })
    if (-not $managed.Count) { return $false }
    foreach ($relative in $managed) {
        $file = Join-Path $Source $relative
        $copy = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) { return $false }
        if ((Get-AgentHubStableFileHash $file) -ne (Get-AgentHubStableFileHash $copy)) { return $false }
    }
    $sourceSkills = @(Get-ChildItem -LiteralPath (Join-Path $Source 'skills') -Recurse -File -Filter 'SKILL.md' |
        ForEach-Object { [IO.Path]::GetRelativePath($Source, $_.FullName) })
    $installedSkills = @(Get-ChildItem -LiteralPath (Join-Path $Destination 'skills') -Recurse -File -Filter 'SKILL.md' |
        ForEach-Object { [IO.Path]::GetRelativePath($Destination, $_.FullName) })
    return -not @(Compare-Object $sourceSkills $installedSkills).Count
}

$clients = @{ claude='claude'; codex='codex'; cursor='cursor'; factory='droid'; devin='devin'; antigravity='agy'; grok='grok'; qoder='qodercli'; copilot='copilot'; gemini='gemini'; amp='amp'; opencode='opencode'; warp='warp'; 'vscode-insiders'='code-insiders' }
# These compatibility routes are documented exceptions to a registry's generic
# loose-skill or native mapping. They must never trigger a second install.
$blockedRoutes = @{
    'warp/repowise'='The Warp skill needs a local bridge this host cannot use.'
    'warp/linkedin'='The Warp skill needs a local bridge this host cannot use.'
    'opencode/repowise'='This skill needs a local bridge not carried by the OpenCode link installer.'
    'opencode/linkedin'='This skill needs a local bridge not carried by the OpenCode link installer.'
    'opencode/aws'='The OpenCode link installer excludes this local proxy.'
    'cline/aws'='Cline requires the approved native MCP settings for this proxy.'
}

function Set-PluginStatus($Row, [switch]$Fresh) {
    if ($Row.host -eq 'gemini') { $Row.status = 'blocked'; $Row.detail = 'AgentHub Gemini rollout is disabled pending an entitled CLI.'; return }
    $routeKey = "$($Row.host)/$($Row.capability)"
    if ($blockedRoutes.ContainsKey($routeKey)) { $Row.status = 'blocked'; $Row.detail = $blockedRoutes[$routeKey]; return }
    if ($Row.route -eq 'preprovisioned-loose-skills' -or $Row.host -eq 'windsurf') {
        $Row.status = 'blocked'; $Row.detail = 'Legacy surface. Use the managed Devin host when available.'; return
    }
    if ($Row.route -eq 'managed-loose-skills' -and $Row.host -notin 'opencode','warp','copilot') {
        $Row.status = 'blocked'; $Row.detail = 'Registry maps loose skills on a plugin-only host. Reconcile its approved native owner before installing.'; return
    }
    if ($live -and $clients.ContainsKey($Row.host) -and
        $Row.host -notin 'amp', 'warp', 'vscode-insiders', 'cursor' -and -not (Get-Command $clients[$Row.host] -ErrorAction SilentlyContinue)) {
        $Row.status = 'blocked'; $Row.detail = 'Host CLI unavailable.'; return
    }
    try { $observation = Get-PluginObservation $Row -Fresh:$Fresh } catch {
        $Row.status = 'blocked'; $Row.detail = "Readback failed: $($_.Exception.Message)"; return
    }
    $Row.observed = if ($observation.version) { $observation.version } elseif ($observation.status -eq 'current') { $Row.expected } else { $null }
    $Row.previousPath = $observation.path
    $Row.detail = $observation.detail
    if (-not $observation -and $Row.host -notin 'cursor','amp','cline','opencode','warp') {
        $Row.status = 'blocked'
        $Row.detail = 'Native registration is absent. First install requires verified host activation and ownership.'
        return
    }
    if ($observation.status -and $observation.status -ne 'current') { $Row.status = $observation.status; return }
    if ($observation.status -eq 'current' -and $observation.path -eq $Row.source) { $Row.status = 'current'; return }
    if (-not $observation) { $Row.status = 'missing'; return }
    if ($observation.version -ne $Row.expected -or ($observation.path -and -not (Test-SkillCopy $Row.source $observation.path $Row.host))) {
        $Row.status = 'drift'
    } else { $Row.status = 'current' }
}

$rows = foreach ($cap in Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $overlay) {
    $source = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $cap -OverlayRoot $overlay
    $manifest = Read-Document (Join-Path $source 'plugin.json')
    if (-not $manifest) { continue }
    if ($PluginId -and $PluginId -notin $manifest.name, $cap.id) { continue }
    $private = Test-AgentHubCapabilityPrivate $cap
    foreach ($mapping in $cap.hostMappings) {
        $target = [string]$mapping.hostId
        if (-not $hostCatalog.ContainsKey($target) -or ($HostId -and $HostId -ne $target)) { continue }
        $market = if (-not $private) { 'agenthub' } elseif ($target -eq 'factory') { 'personal' } else { 'sarosh-private' }
        $route = if ($cap.id -eq 'repowise' -and $target -in 'claude','codex') { 'vendor' }
            elseif ($cap.deployedCatalog -and $target -ne 'gemini') { 'runtime' }
            elseif ($target -eq 'grok' -and $cap.id -in 'product', 'media-studio', 'sarosh') { 'native-local-plugin' }
            elseif ($target -eq 'copilot' -and $cap.id -in 'media-studio', 'repowise') { 'native-local-plugin' }
            else { $mapping.deploymentStatus }
        $row = [pscustomobject]@{
            host=$target; plugin=$manifest.name; capability=$cap.id; route=$route
            expected=$manifest.version; observed=$null; status=$null; detail=$null
            source=$source; sourceHash=$cap.contentHash; relative=[string]$cap.canonicalSource; marketplace=$market
            previousPath=$null; catalog=$cap.deployedCatalog
        }
        Set-PluginStatus $row
        $row
    }
}
$rows = @($rows | Sort-Object host, plugin)
if (-not $rows.Count) { throw 'No plugin mappings matched the filters.' }

function Assert-PublishedPluginSource {
    if (-not $live) { throw 'Apply requires the invoking user profile. Use audit for alternate profiles.' }
    $branch = & git -C $root branch --show-current
    $head = & git -C $root rev-parse HEAD
    $origin = & git -C $root remote get-url origin
    if ($branch -ne 'main' -or $origin -notmatch '(^|[/:])shmindmaster/agenthub(\.git)?$' -or
        @(& git -C $root status --porcelain).Count) { throw 'Apply requires the clean AgentHub main checkout.' }
    $remote = & git -C $root ls-remote --exit-code origin refs/heads/main
    if ($LASTEXITCODE -ne 0 -or ($remote -split '\s+')[0] -ne $head) { throw 'The checkout must match published origin/main.' }
    $null = Get-GreenCiRun $head
    $null = Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Validate-AgentHub.ps1'),'-RepositoryRoot',$root)
    return $head
}

function Get-GreenCiRun([string]$Head) {
    $runs = @(Invoke-Client gh @('run','list','--repo','shmindmaster/agenthub','--workflow','CI','--commit',$Head,'--limit','5','--json','conclusion,databaseId') | ConvertFrom-Json)
    $run = $runs | Where-Object conclusion -EQ 'success' | Select-Object -First 1
    if (-not $run) { throw 'Apply requires successful CI for the exact published commit.' }
    return [string]$run.databaseId
}

function Invoke-PluginInstall($Row) {
    $name = $Row.plugin
    $source = $Row.source.Replace('\','/')
    $qualified = "$name@$($Row.marketplace)"
    $present = [bool]($Row.observed -or $Row.previousPath)
    if ($Row.route -eq 'runtime') {
        Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Sync-Capabilities.ps1'),'-Apply','-RepositoryRoot',$root,'-UserProfile',$UserProfile,'-CapabilityId',$Row.capability) | Out-Null
        return
    }
    switch ($Row.host) {
        'claude' {
            Invoke-Client claude @('plugin','marketplace','update',$Row.marketplace) | Out-Null
            $verb = if ($present) { 'update' } else { 'install' }
            Invoke-Client claude @('plugin',$verb,$qualified,'--scope','user') | Out-Null
        }
        'codex' { Invoke-Client codex @('plugin','add',$qualified) | Out-Null }
        'qoder' {
            Invoke-Client qodercli @('plugins','marketplace','update',$Row.marketplace) | Out-Null
            $verb = if ($present) { 'update' } else { 'install' }
            Invoke-Client qodercli @('plugins',$verb,$qualified) | Out-Null
        }
        'factory' {
            Invoke-Client droid @('plugin','marketplace','update',$Row.marketplace) | Out-Null
            if ($present) { Invoke-Client droid @('plugin','update',$qualified) | Out-Null }
            else { Invoke-Client droid @('plugin','install',$qualified,'--scope','user') | Out-Null }
        }
        'cursor' {
            Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Install-CursorLocalPlugins.ps1'),'-Root',$root,'-PackagePaths',$source) | Out-Null
        }
        'amp' { Invoke-Client python @((Join-Path $PSScriptRoot 'Install-AmpPlugins.py'),$name) | Out-Null }
        'devin' {
            if ($present) { Invoke-Client devin @('plugins','update',$name) | Out-Null }
            else { Invoke-Client devin @('plugins','install',$source,'--yes','--local') | Out-Null }
        }
        'copilot' { Invoke-Client copilot @('plugin','install',$qualified) | Out-Null }
        'antigravity' {
            if ($name -eq 'ah-product') {
                Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Install-AntigravityProductPlugin.ps1')) | Out-Null
            } else {
                Invoke-Client agy @('plugin','validate',$source,'--strict') | Out-Null
                if ($present) { Invoke-Client agy @('plugin','uninstall',$name) | Out-Null }
                Invoke-Client agy @('plugin','install',$source) | Out-Null
            }
        }
        'grok' {
            if ($present) { Invoke-Client grok @('plugin','uninstall',$name) | Out-Null }
            Invoke-Client grok @('plugin','install',$source,'--trust') | Out-Null
        }
        'cline' {
            $dest = Join-Path $UserProfile ".agents/plugins/$name"
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            New-Item -ItemType Junction -Path $dest -Target $source | Out-Null
        }
        { $_ -in 'opencode','warp' } {
            $dest = if ($_ -eq 'warp') { '.warp' } else { '.config/opencode' }
            Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Install-WarpSkills.ps1'),'-Root',$root,'-WarpHome',(Join-Path $UserProfile $dest),'-PluginId',$Row.capability) | Out-Null
        }
        default { throw 'No supported installer for this host mapping.' }
    }
}

$conflicts = @()
if (-not $HostId -or $HostId -eq 'claude') {
    $allowed = @($mcpRegistry.activationPolicy.pluginOnly.hosts.claude.PSObject.Properties.Name)
    $claude = Read-Document (Join-Path $UserProfile '.claude.json')
    foreach ($server in $claude.mcpServers.PSObject.Properties) {
        if ($server.Name -notin $allowed -and $server.Value.disabled -ne $true -and $server.Value.enabled -ne $false) {
            $conflicts += [pscustomobject]@{ host='claude'; status='unmanaged'; kind='direct-mcp'; name=$server.Name }
        }
    }
}
if (-not $HostId) {
    foreach ($skill in @(Get-ChildItem -LiteralPath (Join-Path $UserProfile '.agents/skills') -Force -ErrorAction SilentlyContinue)) {
        $conflicts += [pscustomobject]@{ host='shared'; status='unmanaged'; kind='loose-skill'; name=$skill.Name }
    }
}

$changes = [Collections.Generic.List[object]]::new()
$release = $null
$failed = $false
if ($Apply) {
    $release = Assert-PublishedPluginSource
    $receiptRoot = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub/runtime/plugin-deployment'
    $stamp = [guid]::NewGuid().ToString('N')
    [void][IO.Directory]::CreateDirectory($receiptRoot)
    $receiptPath = Join-Path $receiptRoot "$stamp.json"
    $deploymentLock = [IO.File]::Open((Join-Path $receiptRoot 'deployment.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
    [IO.File]::WriteAllText($receiptPath, (@{ release=$release; changes=@() } | ConvertTo-Json))
    foreach ($row in $rows) {
        if ($row.status -notin 'missing', 'drift') { continue }
        if ($row.host -eq 'vscode-insiders') {
            $row.status = 'blocked'
            $row.detail = 'Register the package through chat.pluginLocations or its approved Copilot catalog.'
            continue
        }
        $entry = [pscustomobject]@{ host=$row.host; plugin=$row.plugin; previous=$row.observed; previousPath=$row.previousPath; desired=$row.expected; sourceHash=$row.sourceHash; backup=$null; status='started' }
        $changes.Add($entry)
        [IO.File]::WriteAllText($receiptPath, (@{ release=$release; changes=@($changes.ToArray()) } | ConvertTo-Json -Depth 5))
        $backup = $null
        if ($row.previousPath -and (Test-Path -LiteralPath $row.previousPath -PathType Container) -and
            -not $row.previousPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $backup = Join-Path $receiptRoot "$stamp-$($row.host)-$($row.plugin)"
            Copy-Item -LiteralPath $row.previousPath -Destination $backup -Recurse -Force
            $entry.backup = $backup
            $backupRecord = @{
                originalSource=$row.source; plugin=$row.plugin; version=$row.observed
                contentHash=(Get-PluginSnapshotHash $backup)
            }
            [IO.File]::WriteAllText("$backup.json", ($backupRecord | ConvertTo-Json))
        }
        try {
            $entry.status = Invoke-AgentHubPluginChange -Install { Invoke-PluginInstall $row } -Verify {
                Set-PluginStatus $row -Fresh
                return $row.status -eq 'current'
            } -Rollback {
                if ($backup -and $row.host -in 'cursor','amp') {
                    $destination = [IO.Path]::GetFullPath($entry.previousPath)
                    $prefix = $liveProfile.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
                    if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Rollback destination is outside the invoking profile.' }
                    $item = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Rollback refused a reparse point.' }
                    if ($item) { Remove-Item -LiteralPath $destination -Recurse -Force }
                    Copy-Item -LiteralPath $backup -Destination $destination -Recurse
                } elseif ($backup -and $row.host -in 'grok','antigravity') {
                    $client = if ($row.host -eq 'grok') { 'grok' } else { 'agy' }
                    $null = Invoke-Client $client @('plugin','uninstall',$row.plugin)
                    $arguments = @('plugin','install',$backup.Replace('\','/'))
                    if ($row.host -eq 'grok') { $arguments += '--trust' }
                    $null = Invoke-Client $client $arguments
                } else {
                    throw "Native registration requires host-specific recovery. Previous=$($entry.previous); backup=$backup"
                }
            }
            foreach ($peer in @($rows | Where-Object { $_.plugin -eq $row.plugin -and $_.route -eq 'runtime' })) { Set-PluginStatus $peer -Fresh }
            Set-PluginStatus $row -Fresh
            if ($row.status -ne 'current') { throw "Installer readback is $($row.status)." }
            $entry.status = 'verified'
        } catch {
            $entry.status = 'failed'
            $row.status = 'failed'
            $row.detail = $_.Exception.Message
            $failed = $true
        } finally {
            [IO.File]::WriteAllText($receiptPath, (@{ release=$release; changes=@($changes.ToArray()) } | ConvertTo-Json -Depth 5))
        }
        if ($failed) { break }
    }
    } finally { $deploymentLock.Dispose() }
}
$report = [ordered]@{
    mode = if ($Apply) { 'apply' } else { 'audit' }
    release = $release
    mappings = @($rows | Select-Object host,plugin,route,expected,observed,status,detail)
    conflicts = @($conflicts)
    changes = @($changes.ToArray())
}
if ($Json) { $report | ConvertTo-Json -Depth 6 }
else {
    $report.mappings | Format-Table host,plugin,route,expected,observed,status,detail -AutoSize
    if ($conflicts.Count) { $conflicts | Format-Table -AutoSize }
    Write-Output "Plugin mappings: $($rows.Count); applied and verified: $(@($changes | Where-Object status -EQ 'verified').Count)"
}
if ($failed) { exit 1 }
