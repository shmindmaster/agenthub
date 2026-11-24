#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$UserProfile,
    [string]$HostId,
    [string]$PluginId,
    [string]$AutoClawAccount,
    [switch]$IncludePrivateOverlay,
    [switch]$Json,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/CapabilityGraph.ps1')
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')
. (Join-Path $PSScriptRoot 'lib/PathBinding.ps1')
. (Join-Path $PSScriptRoot 'lib/HostCatalog.ps1')
. (Join-Path $PSScriptRoot 'lib/PluginTransaction.ps1')
. (Join-Path $PSScriptRoot 'lib/PluginPaths.ps1')
. (Join-Path $PSScriptRoot 'lib/PluginCleanup.ps1')
. (Join-Path $PSScriptRoot 'lib/SharedSkillOwnership.ps1')
$liveProfile = [IO.Path]::GetFullPath((Get-AgentHubDefaultHome))
# Normalize only profile roots. Cache paths beneath them must be actual directories.
if (Test-Path -LiteralPath $liveProfile -PathType Container) { $liveProfile = Resolve-AgentHubPhysicalPath $liveProfile }
if (Test-Path -LiteralPath $UserProfile -PathType Container) { $UserProfile = Resolve-AgentHubPhysicalPath $UserProfile }
$live = $UserProfile.TrimEnd('\', '/') -eq $liveProfile.TrimEnd('\', '/')
$root = $RepositoryRoot.Replace('\', '/')
$overlay = Get-AgentHubOverlayRoot -RepositoryRoot $root
$agents = Get-Content (Join-Path $root 'registry/agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$capabilities = Get-Content (Join-Path $root 'registry/capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mcpRegistry = Get-Content (Join-Path $root 'registry/mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$hostCatalog = @{}
foreach ($agent in $agents.activeAgents) {
    if (Test-AgentHubHostSyncEnabled -Agent $agent) { $hostCatalog[$agent.id] = $agent }
}
$nativeMarketplaceHosts = @('autoclaw', 'zcode')
$nativeMarketplace = $HostId -in $nativeMarketplaceHosts
if ($HostId -and -not $nativeMarketplace -and -not $hostCatalog.ContainsKey($HostId)) { throw "Unknown active host: $HostId" }
if ($AutoClawAccount -and $HostId -ne 'autoclaw') { throw '-AutoClawAccount requires -HostId autoclaw.' }
if ($IncludePrivateOverlay -and -not $nativeMarketplace) { throw '-IncludePrivateOverlay requires -HostId autoclaw or zcode.' }

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

function Get-VersionedObservation([string]$Path, [string]$Manifest = 'plugin.json') {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Path -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending)
    if ($dirs.Count) { return Get-ManifestObservation $dirs[0].FullName $Manifest (Split-Path -Leaf $Path) }
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
function Get-PluginClientList([string]$Command, [switch]$Fresh) {
    if (-not $live) { return }
    if ($Fresh -or -not $clientLists.ContainsKey($Command)) {
        $inventory = Invoke-Client $Command @('plugin','list','--json') | ConvertFrom-Json
        $clientLists[$Command] = if ($Command -eq 'codex') { @($inventory.installed) } else { @($inventory) }
    }
    return $clientLists[$Command]
}

function Get-ListedPlugin([string]$Command, [string]$Name, [string]$Marketplace, [switch]$Fresh) {
    $entries = @(Get-PluginClientList $Command -Fresh:$Fresh | Where-Object name -eq $Name)
    if ($Marketplace) { $entries = @($entries | Where-Object marketplace -eq $Marketplace) }
    if ($entries.Count -gt 1) { throw "Multiple registrations for $Name; cannot choose an owner." }
    return $entries | Select-Object -First 1
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
    switch (Get-RowNativeHost $Row) {
        'claude' {
            $reg = Read-Document (Join-Path $UserProfile '.claude/plugins/installed_plugins.json')
            $entry = @($reg.plugins."$name@$market") | Where-Object scope -EQ 'user' | Select-Object -Last 1
            if ($entry.version) { return New-Observation $entry.version $entry.installPath }
        }
        'codex' {
            $base = Join-Path $UserProfile ".codex/plugins/cache/$market/$name"
            if (-not $live) { return Get-VersionedObservation $base }
            $entries = @(Get-PluginClientList codex -Fresh:$Fresh | Where-Object pluginId -eq "$name@$market")
            if ($entries.Count -gt 1) { return New-Observation '' '' 'unmanaged' 'Duplicate canonical Codex registration.' }
            if ($entries.Count -eq 1 -and $entries[0].version -match '^\d+\.\d+\.\d+$') {
                $installed = Join-Path $base $entries[0].version
                $copy = Get-ManifestObservation $installed 'plugin.json' $name
                if (-not $copy) { return New-Observation $entries[0].version '' 'drift' 'Registered Codex cache is missing.' }
                if ($copy.version -and $copy.version -ne $entries[0].version) {
                    return New-Observation $entries[0].version $installed 'drift' 'Codex registration and cache versions differ.'
                }
                return $copy
            }
        }
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
            $entry = Get-ListedPlugin copilot $name -Marketplace $market -Fresh:$Fresh
            if ($entry.marketplace -eq $market) {
                if ($entry.enabled -eq $false) { return New-Observation $entry.version $source 'blocked' 'Native Copilot plugin is installed but disabled; explicit host activation is required.' }
                return New-Observation $entry.version $source
            }
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
        { $_ -in 'opencode', 'warp', 'kilo', 'mimo-code', 'qwen' } {
            $hostHome = switch ($_) { 'warp' { '.warp' } 'kilo' { '.kilocode' } 'mimo-code' { '.mimocode' } 'qwen' { '.qwen' } default { '.config/opencode' } }
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
            if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { return }
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
            $locations = $settings['chat.pluginLocations']
            if ($null -eq $locations) { return }
            if ($locations -isnot [System.Collections.IDictionary]) {
                return New-Observation '' '' 'blocked' 'chat.pluginLocations must be a path-to-Boolean object.'
            }
            $sourcePath = $source.Replace('\', '/')
            $paths = @($locations.Keys | Where-Object { $_.Replace('\', '/') -ieq $sourcePath })
            if (-not $paths.Count) { return }
            foreach ($path in $paths) {
                $enabled = $locations[$path]
                if ($enabled -isnot [bool] -or $enabled -ne $Row.expectedEnabled) {
                    return New-Observation '' $source 'drift' "chat.pluginLocations requires enabled=$($Row.expectedEnabled) for this package."
                }
            }
            if (-not $Row.expectedEnabled) { return New-Observation '' $source 'current' 'Registered and disabled as configured.' }
            return New-Observation '' $source 'current'
        }
    }
}

function Test-SkillCopy([string]$Source, [string]$Destination, [string]$Client) {
    if (-not (Test-Path -LiteralPath (Join-Path $Destination 'skills'))) { return $false }
    $gitFiles = if ($Source.Replace('\','/') -match '/(overlays/personal|agenthub-private)/') {
        @(Get-AgentHubFilesystemRelativeFiles -Path $Source)
    } else { @(Get-AgentHubGitTrackedRelativeFiles -Path $Source) }
    # Antigravity installs a projection without other hosts' MCP files (see Invoke-PluginInstall),
    # so its MCP surface is mcp_config.json. Droid renames .mcp.json to mcp.json and agents/ to
    # droids/ on install, re-serializing the JSON.
    $managed = @($gitFiles | Where-Object {
        $_ -match '^(skills|scripts|references|assets|kits|schemas|policy|kit)/' -or
        ($Client -notin 'amp','antigravity' -and $_ -in 'mcp.json','.mcp.json') -or
        ($Client -eq 'antigravity' -and $_ -eq 'mcp_config.json') -or
        ($Client -ne 'amp' -and -not ($Client -eq 'antigravity' -and (Split-Path -Leaf $Source) -eq 'product') -and $_ -match '^agents/')
    })
    if ($Client -eq 'factory' -and 'mcp.json' -in $gitFiles) { $managed = @($managed | Where-Object { $_ -ne '.mcp.json' }) }
    if (-not $managed.Count) { return $false }
    foreach ($relative in $managed) {
        $file = Join-Path $Source $relative
        $copy = Join-Path $Destination $relative
        $renamed = $false
        if ($Client -eq 'factory' -and -not (Test-Path -LiteralPath $copy -PathType Leaf)) {
            $alternate = if ($relative -eq '.mcp.json') { 'mcp.json' } elseif ($relative -match '^agents/(.+)$') { "droids/$($Matches[1])" }
            if ($alternate) { $copy = Join-Path $Destination $alternate; $renamed = $relative -eq '.mcp.json' }
        }
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) { return $false }
        if ($renamed) {
            $expected = [IO.File]::ReadAllText($file, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json | ConvertTo-Json -Depth 64 -Compress
            $actual = [IO.File]::ReadAllText($copy, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json | ConvertTo-Json -Depth 64 -Compress
            if ($expected -ne $actual) { return $false }
        } elseif ((Get-AgentHubStableFileHash $file) -ne (Get-AgentHubStableFileHash $copy)) { return $false }
    }
    $sourceSkills = @(Get-ChildItem -LiteralPath (Join-Path $Source 'skills') -Recurse -File -Filter 'SKILL.md' |
        ForEach-Object { [IO.Path]::GetRelativePath($Source, $_.FullName) })
    $installedSkills = @(Get-ChildItem -LiteralPath (Join-Path $Destination 'skills') -Recurse -File -Filter 'SKILL.md' |
        ForEach-Object { [IO.Path]::GetRelativePath($Destination, $_.FullName) })
    return -not @(Compare-Object $sourceSkills $installedSkills).Count
}

$clients = @{ claude='claude'; codex='codex'; cursor='cursor'; factory='droid'; devin='devin'; antigravity='agy'; grok='grok'; copilot='copilot'; amp='amp'; opencode='opencode'; 'vscode-insiders'='code-insiders'; kilo='kilo'; 'mimo-code'='mimo'; qwen='qwen' }

# A mapping may declare nativeOwnerHost: the surface row is reported under its
# own hostId but every observation, client call and install resolves through
# the owner host, so one owner install satisfies both rows. Default is self.
function Get-RowNativeHost($Row) {
    if ($Row.nativeOwnerHost) { return [string]$Row.nativeOwnerHost }
    return [string]$Row.host
}
# These compatibility routes are documented exceptions to a registry's generic
# loose-skill or native mapping. They must never trigger a second install.
$blockedRoutes = @{
    'opencode/aws'='The OpenCode link installer excludes this local proxy.'
    'cline/aws'='Cline requires the approved native MCP settings for this proxy.'
}

function Set-PluginStatus($Row, [switch]$Fresh) {
    # Every owner-bound policy resolves through the native owner, so an alias
    # can never escape its owner's disable, blocked route or loose-skill rule.
    $nativeHost = Get-RowNativeHost $Row
    $routeKey = "$nativeHost/$($Row.capability)"
    if ($blockedRoutes.ContainsKey($routeKey)) { $Row.status = 'blocked'; $Row.detail = $blockedRoutes[$routeKey]; return }
    if ($Row.route -eq 'preprovisioned-loose-skills' -or $nativeHost -eq 'windsurf') {
        $Row.status = 'blocked'; $Row.detail = 'Legacy surface. Use the managed Devin host when available.'; return
    }
    if ($Row.route -eq 'managed-loose-skills' -and $nativeHost -notin 'opencode','warp','copilot','kilo','mimo-code','qwen','cline','amp') {
        $Row.status = 'blocked'; $Row.detail = 'Registry maps loose skills on a plugin-only host. Reconcile its approved native owner before installing.'; return
    }
    if ($live -and $clients.ContainsKey($nativeHost) -and
        $nativeHost -notin 'amp', 'warp', 'vscode-insiders', 'cursor' -and -not (Get-Command $clients[$nativeHost] -ErrorAction SilentlyContinue)) {
        $Row.status = 'blocked'; $Row.detail = 'Host CLI unavailable.'; return
    }
    try { $observation = Get-PluginObservation $Row -Fresh:$Fresh } catch {
        $Row.status = 'blocked'; $Row.detail = "Readback failed: $($_.Exception.Message)"; return
    }
    $Row.observed = if ($observation.version) { $observation.version } elseif ($observation.status -eq 'current') { $Row.expected } else { $null }
    $Row.previousPath = $observation.path
    $Row.detail = $observation.detail
    if (-not $observation -and $nativeHost -notin 'cursor','amp','cline','opencode','warp','kilo','mimo-code','qwen') {
        $Row.status = 'blocked'
        $Row.detail = 'Native registration is absent. First install requires verified host activation and ownership.'
        return
    }
    if ($observation.status -and $observation.status -ne 'current') { $Row.status = $observation.status; $Row.detail = $observation.detail; return }
    if ($observation.status -eq 'current' -and $observation.path -eq $Row.source) { $Row.status = 'current'; return }
    if (-not $observation) { $Row.status = 'missing'; return }
    if ($observation.version -ne $Row.expected -or ($observation.path -and -not (Test-SkillCopy $Row.source $observation.path $nativeHost))) {
        $Row.status = 'drift'
    } else { $Row.status = 'current' }
}

function Get-MappingMarketplace([bool]$Private, [string]$OwnerHost) {
    if (-not $Private) { return 'agenthub' }
    if ($OwnerHost -eq 'factory') { return 'agenthub-private' }
    return 'sarosh-private'
}

function Get-MappingRoute($Cap, [string]$OwnerHost, [string]$DeploymentStatus) {
    # A deployed catalog travels on the loose-skill hosts' runtime rows; hosts with a native
    # plugin install still get the plugin so it appears in their plugin picker.
    if ($Cap.deployedCatalog -and $DeploymentStatus -eq 'managed-loose-skills') { return 'runtime' }
    if ($OwnerHost -eq 'grok' -and $Cap.id -in 'product', 'media-studio', 'sarosh', 'coding-agent-dispatch') { return 'native-local-plugin' }
    if ($OwnerHost -eq 'copilot' -and $Cap.id -eq 'media-studio') { return 'native-local-plugin' }
    return $DeploymentStatus
}

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

if ($nativeMarketplace) {
    if (-not $IsWindows -or -not $live) { throw "$HostId requires the invoking Windows profile." }
    if ($HostId -eq 'autoclaw' -and ($Apply -or $IncludePrivateOverlay) -and -not $AutoClawAccount) {
        throw 'AutoClaw apply or private overlay selection requires -AutoClawAccount.'
    }
    $arguments = @((Join-Path $PSScriptRoot 'sync-autoclaw-plugins.mjs'), '--root', $root, '--host', $HostId.ToLowerInvariant())
    if ($AutoClawAccount) { $arguments += @('--account', $AutoClawAccount) }
    if ($IncludePrivateOverlay) {
        if (-not $overlay) { throw 'A private AgentHub overlay was not found.' }
        $arguments += @('--overlay', $overlay)
    }
    if ($PluginId) { $arguments += @('--plugin', $PluginId) }
    if ($Json) { $arguments += '--json' }
    $lock = $null
    try {
        if ($Apply) {
            $null = Assert-PublishedPluginSource
            if ($IncludePrivateOverlay) {
                $overlayOrigin = Invoke-Client git @('-C', $overlay, 'remote', 'get-url', 'origin')
                $overlayHead = Invoke-Client git @('-C', $overlay, 'rev-parse', 'HEAD')
                if ($overlayOrigin -notmatch '(^|[/:])shmindmaster/agenthub-private(\.git)?$') {
                    throw 'Apply requires the canonical private overlay checkout.'
                }
                $overlayRemote = Invoke-Client git @('-C', $overlay, 'ls-remote', '--exit-code', 'origin', 'refs/heads/main')
                if (($overlayRemote -split '\s+')[0] -ne $overlayHead) {
                    throw 'The private overlay must match its published main.'
                }
            }
            $deploymentDirectory = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub/runtime/plugin-deployment'
            [void][IO.Directory]::CreateDirectory($deploymentDirectory)
            $lock = [IO.File]::Open((Join-Path $deploymentDirectory 'deployment.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $processName = if ($HostId -eq 'autoclaw') { '*AutoClaw*' } else { 'ZCode' }
            if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
                throw "Close $HostId before applying native plugin changes."
            }
            $arguments += '--apply'
        }
        & node @arguments
        $code = $LASTEXITCODE
    } finally {
        if ($lock) { $lock.Dispose() }
    }
    exit $code
}

$rows = foreach ($cap in Get-AgentHubEffectiveCapabilities -CapabilitiesDocument $capabilities -OverlayRoot $overlay) {
    $source = Resolve-AgentHubPackageRoot -RepositoryRoot $root -Capability $cap -OverlayRoot $overlay
    $manifest = Read-Document (Join-Path $source 'plugin.json')
    if (-not $manifest) { continue }
    if ($PluginId -and $PluginId -notin $manifest.name, $cap.id) { continue }
    $private = Test-AgentHubCapabilityPrivate $cap
    foreach ($mapping in $cap.hostMappings) {
        $target = [string]$mapping.hostId
        if ($target -in $nativeMarketplaceHosts -or -not $hostCatalog.ContainsKey($target) -or ($HostId -and $HostId -ne $target)) { continue }
        $nativeOwner = if ($mapping.nativeOwnerHost) { [string]$mapping.nativeOwnerHost } else { $target }
        # Route and marketplace always follow the owner, never the surface:
        # an alias inherits its owner's effective route so a misleading
        # declaration on the surface row cannot widen what runs.
        $ownerMapping = if ($nativeOwner -ne $target) { @($cap.hostMappings | Where-Object { [string]$_.hostId -eq $nativeOwner }) | Select-Object -First 1 } else { $mapping }
        $route = Get-MappingRoute $cap $nativeOwner ([string]$ownerMapping.deploymentStatus)
        $market = Get-MappingMarketplace $private $nativeOwner
        $row = [pscustomobject]@{
            host=$target; plugin=$manifest.name; capability=$cap.id; route=$route
            nativeOwnerHost=$nativeOwner
            expectedEnabled=($ownerMapping.nativePluginEnabled ?? $true)
            expected=$manifest.version; observed=$null; status=$null; detail=$null
            source=$source; sourceHash=$cap.contentHash; relative=[string]$cap.canonicalSource; marketplace=$market
            previousPath=$null; catalog=$cap.deployedCatalog
        }
        # The owner must be an active host with a self-owned mapping for the
        # same capability; unknown, chained or cyclic owners refuse before any
        # observation or mutation can run under the wrong identity.
        if ($nativeOwner -ne $target) {
            $ownerMapping = @($cap.hostMappings | Where-Object { [string]$_.hostId -eq $nativeOwner }) | Select-Object -First 1
            $ownerSelfOwned = $ownerMapping -and (-not $ownerMapping.nativeOwnerHost -or [string]$ownerMapping.nativeOwnerHost -eq $nativeOwner)
            if (-not $hostCatalog.ContainsKey($nativeOwner)) {
                $row.status = 'blocked'; $row.detail = "nativeOwnerHost '$nativeOwner' is not an active host."
            } elseif (-not $ownerSelfOwned) {
                $row.status = 'blocked'; $row.detail = "nativeOwnerHost '$nativeOwner' has no self-owned $($cap.id) mapping; chained or cyclic owners are refused."
            }
        }
        if (-not $row.status -and $nativeOwner -eq 'vscode-insiders' -and $row.expectedEnabled -isnot [bool]) {
            $row.status = 'blocked'; $row.detail = 'nativePluginEnabled must be a Boolean.'
        }
        if (-not $row.status) { Set-PluginStatus $row }
        $row
    }
}
$rows = @($rows | Sort-Object host, plugin)
if (-not $rows.Count) { throw 'No plugin mappings matched the filters.' }

function Invoke-PluginInstall($Row) {
    $name = $Row.plugin
    $source = $Row.source.Replace('\','/')
    $qualified = "$name@$($Row.marketplace)"
    $present = [bool]($Row.observed -or $Row.previousPath)
    if ($Row.route -eq 'runtime') {
        Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Sync-Capabilities.ps1'),'-Apply','-RepositoryRoot',$root,'-UserProfile',$UserProfile,'-CapabilityId',$Row.capability) | Out-Null
        return
    }
    switch (Get-RowNativeHost $Row) {
        'claude' {
            Invoke-Client claude @('plugin','marketplace','update',$Row.marketplace) | Out-Null
            $verb = if ($present) { 'update' } else { 'install' }
            Invoke-Client claude @('plugin',$verb,$qualified,'--scope','user') | Out-Null
        }
        'codex' { Invoke-Client codex @('plugin','add',$qualified) | Out-Null }
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
                # Strict validation rejects other hosts' root manifest and MCP files, so install
                # a projection of the tracked package without them.
                $projection = [IO.Directory]::CreateTempSubdirectory('agenthub-antigravity-').FullName
                try {
                    $files = if ($source.Replace('\','/') -match '/(overlays/personal|agenthub-private)/') {
                        @(Get-AgentHubFilesystemRelativeFiles -Path $source)
                    } else { @(Get-AgentHubGitTrackedRelativeFiles -Path $source) }
                    foreach ($relative in $files | Where-Object { $_ -notin 'plugin.json','mcp.json','.mcp.json' }) {
                        $target = Join-Path $projection $relative
                        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
                        Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $target
                    }
                    Invoke-Client agy @('plugin','validate',$projection,'--strict') | Out-Null
                    if ($present) { Invoke-Client agy @('plugin','uninstall',$name) | Out-Null }
                    Invoke-Client agy @('plugin','install',$projection) | Out-Null
                } finally { [IO.Directory]::Delete($projection, $true) }
            }
        }
        'grok' {
            if ($present) { Invoke-Client grok @('plugin','uninstall',$name) | Out-Null }
            Invoke-Client grok @('plugin','install',$source,'--trust') | Out-Null
        }
        'cline' {
            $dest = Join-Path $UserProfile ".agents/plugins/$name"
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            $linkKind = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkKind -Path $dest -Target $source | Out-Null
        }
        { $_ -in 'opencode','warp','kilo','mimo-code','qwen' } {
            $dest = switch ($_) { 'warp' { '.warp' } 'kilo' { '.kilocode' } 'mimo-code' { '.mimocode' } 'qwen' { '.qwen' } default { '.config/opencode' } }
            Invoke-Client pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Install-WarpSkills.ps1'),'-Root',$root,'-WarpHome',(Join-Path $UserProfile $dest),'-PluginId',$Row.capability) | Out-Null
        }
        default { throw 'No supported installer for this host mapping.' }
    }
}

# Rollback follows the same owner rule as install: a failed change on a
# surface row restores through its native owner's recovery branch.
function Invoke-PluginRollback($Row, $Entry, $Backup) {
    $nativeHost = Get-RowNativeHost $Row
    if ($Backup -and $nativeHost -in 'cursor','amp') {
        $destination = [IO.Path]::GetFullPath($Entry.previousPath)
        $prefix = $liveProfile.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Rollback destination is outside the invoking profile.' }
        $item = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Rollback refused a reparse point.' }
        if ($item) { Remove-Item -LiteralPath $destination -Recurse -Force }
        Copy-Item -LiteralPath $Backup -Destination $destination -Recurse
    } elseif ($Backup -and $nativeHost -in 'grok','antigravity') {
        $client = if ($nativeHost -eq 'grok') { 'grok' } else { 'agy' }
        $null = Invoke-Client $client @('plugin','uninstall',$Row.plugin)
        $arguments = @('plugin','install',$Backup.Replace('\','/'))
        if ($nativeHost -eq 'grok') { $arguments += '--trust' }
        $null = Invoke-Client $client $arguments
    } else {
        throw "Native registration requires host-specific recovery. Previous=$($Entry.previous); backup=$Backup"
    }
}

# A pending row is re-observed fresh before installing: a surface row whose
# owner install just verified is already current and must not install twice.
function Test-PluginRowPending($Row) {
    Set-PluginStatus $Row -Fresh
    return ($Row.status -in 'missing','drift')
}

function Get-PluginCleanup($Row) {
    if ($Row.status -ne 'current' -or $Row.plugin -notmatch '^ah-[a-z0-9-]+$') { return }
    $name = $Row.plugin
    $market = $Row.marketplace
    $owner = Get-RowNativeHost $Row
    $version = $Row.expected
    if ($version -notmatch '^\d+\.\d+\.\d+$') { return }

    if ($owner -eq 'claude') {
        $registryPath = Join-Path $UserProfile '.claude/plugins/installed_plugins.json'
        $registry = Read-AgentHubCleanupJson $registryPath
        if (-not $registry.plugins) {
            New-AgentHubPluginCleanup claude $name 'cleanup-inventory' $registryPath 'unmanaged' 'Claude registry could not be read.'
            return
        }
        $refs = @($registry.plugins.PSObject.Properties.Value | ForEach-Object { $_ } | ForEach-Object { $_.installPath })
        if (-not $HostId -or $HostId -eq 'claude') {
            foreach ($key in $registry.plugins.PSObject.Properties.Name) {
                if ($key -like "$name@*" -and $key -ne "$name@$market") {
                    New-AgentHubPluginCleanup claude $name 'alternate-registration' $key 'unmanaged' 'Another marketplace owns this registration.'
                }
            }
        }
        $base = Join-Path $UserProfile ".claude/plugins/cache/$market/$name"
        if (-not $HostId -or $HostId -eq 'claude') {
            Get-AgentHubOldPluginVersions -HostId claude -Plugin $name -Root $base -ActivePath $Row.previousPath -Version $version -RegisteredPaths $refs -Manifest '.claude-plugin/plugin.json'
        }
        if ($Row.host -in 'cursor','cursor-agent') {
            $cursorBase = Join-Path $UserProfile '.cursor/plugins/local'
            $path = Join-Path $cursorBase $name
            if (Test-Path -LiteralPath $path -PathType Container) {
                $settings = Read-AgentHubCleanupJson (Join-Path $UserProfile '.claude/settings.json')
                $source = Read-AgentHubCleanupJson (Join-Path $Row.source 'plugin.json')
                $copy = if (Test-AgentHubPluginTree $cursorBase $path) { Read-AgentHubCleanupJson (Join-Path $path 'plugin.json') }
                $projection = if ($copy) { Read-AgentHubCleanupJson (Join-Path $path '.cursor-plugin/plugin.json') }
                if ($settings.enabledPlugins."$name@$market" -eq $true -and $copy.name -eq $name -and
                    $copy.author.name -and $copy.author.name -ceq $source.author.name -and $projection.name -eq $name -and
                    $copy.version -eq $projection.version -and $copy.version -match '^\d+\.\d+\.\d+$' -and [version]$copy.version -le [version]$version) {
                    New-AgentHubPluginCleanup cursor $name 'cursor-import-duplicate' $path
                } else {
                    New-AgentHubPluginCleanup cursor $name 'cursor-import-duplicate' $path 'unmanaged' 'Local copy or enabled Claude import could not be verified.'
                }
            }
        }
    }

    if ($owner -eq 'codex') {
        $base = Join-Path $UserProfile ".codex/plugins/cache/$market/$name"
        Get-AgentHubOldPluginVersions -HostId codex -Plugin $name -Root $base -ActivePath $Row.previousPath -Version $version
        $entries = @(Get-PluginClientList codex | Where-Object { $_.name -eq $name -and $_.pluginId -ne "$name@$market" })
        if ($market -eq 'agenthub' -and $name -eq 'ah-media-studio') {
            $legacyId = 'ah-media-studio@created-by-me-remote'
            $legacyMarket = Join-Path $UserProfile '.codex/plugins/cache/created-by-me-remote'
            $legacyPath = Join-Path $legacyMarket $name
            $exists = Test-Path -LiteralPath $legacyPath
            if ($exists -or $legacyId -in $entries.pluginId) {
                $cacheSafe = -not $exists
                if ($exists -and (Test-AgentHubPluginTree $legacyMarket $legacyPath)) {
                    $copies = @(Get-ChildItem -LiteralPath $legacyPath -Force)
                    $invalid = @($copies | Where-Object {
                        $manifest = if ($_.PSIsContainer) { Read-AgentHubCleanupJson (Join-Path $_.FullName 'plugin.json') }
                        -not $_.PSIsContainer -or $_.Name -notmatch '^\d+\.\d+\.\d+$' -or
                            $manifest.name -ne $name -or $manifest.version -ne $_.Name -or [version]$_.Name -gt [version]$version
                    })
                    $cacheSafe = $copies.Count -gt 0 -and -not $invalid.Count
                }
                if ($cacheSafe) {
                    New-AgentHubPluginCleanup codex $name 'codex-retired-registration' $legacyId
                } else {
                    New-AgentHubPluginCleanup codex $name 'codex-retired-registration' $legacyId 'unmanaged' 'Legacy cache ownership could not be verified.'
                }
                $entries = @($entries | Where-Object pluginId -ne $legacyId)
            }
        }
        foreach ($other in $entries) {
            New-AgentHubPluginCleanup codex $name 'alternate-registration' $other.pluginId 'unmanaged' 'Another marketplace owns this registration.'
        }
    }

    if ($owner -eq 'copilot' -and $market -eq 'agenthub' -and $live) {
        $config = Join-Path $UserProfile '.copilot/config.json'
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            $document = Read-AgentHubCleanupJson $config -AsHashtable
            if ($document -isnot [System.Collections.IDictionary]) {
                New-AgentHubPluginCleanup copilot $name 'cleanup-inventory' $config 'unmanaged' 'Copilot configuration could not be read.'
                return
            }
            $owned = @(Get-AgentHubCopilotDirectEntries $document $name $Row.relative)
            $entries = @(Get-PluginClientList copilot | Where-Object { $_.name -eq $name -and $_.marketplace -ne $market })
            if ($owned.Count -eq 1 -and $entries.Count -eq 1 -and $entries[0].source -eq 'installed' -and -not $entries[0].marketplace) {
                New-AgentHubPluginCleanup copilot $name 'copilot-direct-registration' $config
            } elseif ($owned.Count -or $entries.Count) {
                New-AgentHubPluginCleanup copilot $name 'alternate-registration' $name 'unmanaged' 'Direct registration ownership is ambiguous.'
            }
            if (-not $owned.Count -and -not $entries.Count) {
                $base = Join-Path $UserProfile '.copilot/installed-plugins/_direct'
                $pattern = '^shmindmaster--agenthub--' + [regex]::Escape($Row.relative.Replace('/','-')) + '-[0-9a-f]{8}$'
                foreach ($cache in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object Name -match $pattern) {
                    $copy = if (Test-AgentHubPluginTree $base $cache.FullName) { Read-AgentHubCleanupJson (Join-Path $cache.FullName 'plugin.json') }
                    if ($copy.name -eq $name -and $copy.version -match '^\d+\.\d+\.\d+$' -and [version]$copy.version -le [version]$version) {
                        New-AgentHubPluginCleanup copilot $name 'copilot-direct-cache' $cache.FullName
                    }
                }
            }
        }
    }
}

function Invoke-PluginCleanup($Row, $Candidate) {
    $owner = Get-RowNativeHost $Row
    switch ($Candidate.kind) {
        'codex-retired-registration' {
            Invoke-Client codex @('plugin','remove',$Candidate.target) | Out-Null
            $remaining = @(Get-PluginClientList codex -Fresh | Where-Object pluginId -eq $Candidate.target)
            $legacy = Join-Path $UserProfile '.codex/plugins/cache/created-by-me-remote/ah-media-studio'
            if ($remaining.Count -or (Test-Path -LiteralPath $legacy)) { throw 'Retired Codex registration or cache is still present.' }
            Set-PluginStatus $Row
            if ($Row.status -ne 'current') { throw 'Canonical Codex registration did not verify after removing the retired registration.' }
        }
        'copilot-direct-registration' {
            Remove-AgentHubCopilotDirectRegistration $Candidate.target $Row.plugin $Row.relative {
                $installed = @(Get-PluginClientList copilot -Fresh | Where-Object name -eq $Row.plugin)
                $installed.Count -eq 1 -and $installed[0].marketplace -eq $Row.marketplace -and
                    $installed[0].version -eq $Row.expected -and $installed[0].enabled
            }
        }
        'old-cache' {
            Remove-AgentHubPluginTree (Join-Path $UserProfile ".$owner/plugins/cache/$($Row.marketplace)/$($Row.plugin)") $Candidate.target
        }
        'cursor-import-duplicate' {
            Remove-AgentHubPluginTree (Join-Path $UserProfile '.cursor/plugins/local') $Candidate.target
        }
        'copilot-direct-cache' {
            Remove-AgentHubPluginTree (Join-Path $UserProfile '.copilot/installed-plugins/_direct') $Candidate.target
        }
        default { throw 'No verified cleanup route.' }
    }
}

function Get-PluginCleanupPlan($Rows, [switch]$Execute) {
    $seen = @{}
    $refreshed = @{}
    foreach ($row in $Rows) {
        $planned = @(Get-PluginCleanup $row)
        if ($Execute -and $planned.Count) {
            $ownerKey = "$(Get-RowNativeHost $row)/$($row.plugin)"
            $fresh = -not $refreshed.ContainsKey($ownerKey)
            if ($fresh) { $refreshed[$ownerKey] = $true }
            Set-PluginStatus $row -Fresh:$fresh
            $planned = @(Get-PluginCleanup $row)
        }
        # Repeat once after direct registration removal to pick up its orphaned cache.
        for ($pass = 0; $pass -lt 2 -and $planned.Count; $pass++) {
            $removedRegistration = $false
            foreach ($candidate in $planned) {
                $key = "$($candidate.host)/$($candidate.kind)/$($candidate.target)/$($candidate.plugin)"
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                if ($candidate.status -eq 'pending' -and $candidate.kind -ne 'codex-retired-registration' -and
                    (Test-AgentHubPluginHostBusy $candidate.host)) {
                    $candidate.status = 'deferred'
                    $candidate.detail = 'Close the host before cleanup. The next apply will retry.'
                }
                if ($Execute -and $candidate.status -eq 'pending') {
                    try {
                        if (-not (Get-PluginCleanup $row | Where-Object {
                            $_.kind -eq $candidate.kind -and $_.target -eq $candidate.target -and $_.status -eq 'pending'
                        })) {
                            $candidate.status = 'deferred'
                            $candidate.detail = 'Cleanup ownership changed. Recheck on the next apply.'
                            $candidate
                            continue
                        }
                        Invoke-PluginCleanup $row $candidate
                        $candidate.status = 'removed'
                        $removedRegistration = $removedRegistration -or $candidate.kind -eq 'copilot-direct-registration'
                    } catch {
                        $candidate.status = 'failed'
                        $candidate.detail = $_.Exception.Message
                    }
                }
                $candidate
            }
            $planned = if ($removedRegistration) { @(Get-PluginCleanup $row) } else { @() }
        }
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
    $nativeConnectors = Read-Document (Join-Path $root 'registry/native-connectors.json')
    foreach ($skill in @(Get-UnmanagedSharedSkills -UserProfile $UserProfile -NativeConnectors $nativeConnectors)) {
        $conflicts += [pscustomobject]@{ host='shared'; status='unmanaged'; kind='loose-skill'; name=$skill.Name }
    }
}

$changes = [Collections.Generic.List[object]]::new()
$release = $null
$failed = $false
$cleanup = @()
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
        # Rows sharing a native owner install once: before attempting, re-observe
        # fresh so a surface whose owner install just verified is skipped.
        if (-not (Test-PluginRowPending $row)) { continue }
        if ((Get-RowNativeHost $row) -eq 'vscode-insiders') {
            if (-not $row.detail) {
                $row.detail = 'Register the package through chat.pluginLocations or its approved Copilot catalog.'
            }
            $row.status = 'blocked'
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
                Invoke-PluginRollback -Row $row -Entry $entry -Backup $backup
            }
            foreach ($peer in @($rows | Where-Object { $_.plugin -eq $row.plugin -and $_.route -eq 'runtime' })) { Set-PluginStatus $peer -Fresh }
            Set-PluginStatus $row -Fresh
            if ($row.status -ne 'current') { throw "Installer readback is $($row.status)." }
            $entry.status = 'verified'
            # A verified install needs no rollback copy; only a failed one keeps its backup.
            if ($backup -and (Test-Path -LiteralPath $backup)) { [IO.Directory]::Delete($backup, $true) }
            if ($backup -and (Test-Path -LiteralPath "$backup.json")) { [IO.File]::Delete("$backup.json") }
            $entry.backup = $null
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
    if (-not $failed) {
        $cleanup = @(Get-PluginCleanupPlan $rows -Execute)
        if ($cleanup.status -contains 'failed') {
            $failed = $true
            [IO.File]::WriteAllText($receiptPath, (@{ release=$release; changes=@($changes.ToArray()); cleanup=$cleanup } | ConvertTo-Json -Depth 6))
        }
    }
    # A run whose every change verified leaves no receipt; a failed run keeps it for recovery.
    if (-not $failed -and (Test-Path -LiteralPath $receiptPath)) { [IO.File]::Delete($receiptPath) }
    } finally { $deploymentLock.Dispose() }
} else {
    $cleanup = @(Get-PluginCleanupPlan $rows)
}
$report = [ordered]@{
    mode = if ($Apply) { 'apply' } else { 'audit' }
    release = $release
    mappings = @($rows | Select-Object host,plugin,route,nativeOwnerHost,expected,observed,status,detail)
    conflicts = @($conflicts)
    changes = @($changes.ToArray())
    cleanup = $cleanup
}
if ($Json) { $report | ConvertTo-Json -Depth 6 }
else {
    $report.mappings | Format-Table host,plugin,route,expected,observed,status,detail -AutoSize
    if ($conflicts.Count) { $conflicts | Format-Table -AutoSize }
    if ($cleanup.Count) { $cleanup | Format-Table host,plugin,kind,status,detail -AutoSize }
    Write-Output "Plugin mappings: $($rows.Count); applied and verified: $(@($changes | Where-Object status -EQ 'verified').Count)"
}
if ($failed) { exit 1 }
