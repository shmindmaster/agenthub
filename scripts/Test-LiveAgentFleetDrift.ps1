#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RegistryRoot,
    [string]$UserProfilePath = $env:USERPROFILE,
    [string]$AppDataPath,
    [string]$LocalAppDataPath,
    [string]$ReposRoot = 'C:\Repos',
    [string]$WorktreeRoot = 'C:\wt',
    [string]$CodexPluginStatePath,
    [string]$ProcessSnapshotPath,
    [switch]$SkipRepositoryScan,
    [string]$ReportPath,
    [switch]$Json
)

if ([string]::IsNullOrWhiteSpace($RegistryRoot)) {
    $RegistryRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($AppDataPath)) {
    $AppDataPath = Join-Path $UserProfilePath 'AppData\Roaming'
}
if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
    $LocalAppDataPath = Join-Path $UserProfilePath 'AppData\Local'
}
if ([string]::IsNullOrWhiteSpace($CodexPluginStatePath)) {
    $CodexPluginStatePath = Join-Path $LocalAppDataPath `
        'AgentHub\state\codex-plugin-install-state.json'
}

$RegistryRoot = [System.IO.Path]::GetFullPath($RegistryRoot)
$canonicalRepositoryRoot = [System.IO.Path]::GetFullPath(
    'C:\Repos\shmindmaster\agenthub'
).TrimEnd('\')
$UserProfilePath = [System.IO.Path]::GetFullPath($UserProfilePath)
$AppDataPath = [System.IO.Path]::GetFullPath($AppDataPath)
$LocalAppDataPath = [System.IO.Path]::GetFullPath($LocalAppDataPath)
$ReposRoot = [System.IO.Path]::GetFullPath($ReposRoot)
$WorktreeRoot = [System.IO.Path]::GetFullPath($WorktreeRoot).TrimEnd('\')
$CodexPluginStatePath = [System.IO.Path]::GetFullPath($CodexPluginStatePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RegistryContentHash.ps1')

trap {
    $line = $_.InvocationInfo.ScriptLineNumber
    $text = $_.InvocationInfo.Line
    Write-Error "Live fleet inventory failed at line $line ($text): $($_.Exception.Message)"
    exit 2
}

$results = New-Object System.Collections.Generic.List[object]
$discoveryRoots = New-Object System.Collections.Generic.List[object]
$pluginRoots = New-Object System.Collections.Generic.List[object]
$skillRecords = New-Object System.Collections.Generic.List[object]
$mcpStates = New-Object System.Collections.Generic.List[object]
$pluginStates = New-Object System.Collections.Generic.List[object]
$worktreeStates = New-Object System.Collections.Generic.List[object]
$processStates = New-Object System.Collections.Generic.List[object]
$runtimeTrees = New-Object System.Collections.Generic.List[object]
$runtimeResourceGroups = New-Object System.Collections.Generic.List[object]
$runtimeSessionStates = New-Object System.Collections.Generic.List[object]
$reviewerBrokerState = $null

function Add-DriftResult {
    param(
        [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [string]$Category,
        [string]$Check,
        [string]$Detail,
        [string]$HostId = '',
        [string[]]$Paths = @()
    )

    $script:results.Add([pscustomobject]@{
        status = $Status
        category = $Category
        check = $Check
        hostId = $HostId
        detail = $Detail
        paths = @($Paths)
    })
}

function Get-PropertyValue {
    param(
        [object]$InputObject,
        [string]$Name,
        [object]$DefaultValue = $null
    )
    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Add-DriftResult FAIL 'configuration' "invalid-json:$Path" $_.Exception.Message '' @($Path)
        return $null
    }
}

function Get-CodexPluginInstallSnapshot {
    param([string]$Path)

    $unknown = [pscustomobject]@{
        available = $false
        reason = ''
        states = @{}
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $unknown.reason = 'authoritative plugin-state snapshot is absent'
        return $unknown
    }
    try {
        $snapshot = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        $unknown.reason = 'authoritative plugin-state snapshot is malformed'
        return $unknown
    }

    $generatedAtText = [string](Get-PropertyValue $snapshot 'generatedAt' '')
    $generatedAt = [DateTimeOffset]::MinValue
    if ([string]::IsNullOrWhiteSpace($generatedAtText) -or
        -not [DateTimeOffset]::TryParse($generatedAtText, [ref]$generatedAt)) {
        $unknown.reason = 'authoritative plugin-state snapshot has no valid generatedAt'
        return $unknown
    }
    $expiresAt = $generatedAt.AddHours(24)
    $expiresAtText = [string](Get-PropertyValue $snapshot 'expiresAt' '')
    if (-not [string]::IsNullOrWhiteSpace($expiresAtText)) {
        $parsedExpiry = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($expiresAtText, [ref]$parsedExpiry)) {
            $unknown.reason = 'authoritative plugin-state snapshot has an invalid expiresAt'
            return $unknown
        }
        $expiresAt = $parsedExpiry
    }
    if ([DateTimeOffset]::UtcNow -gt $expiresAt.ToUniversalTime()) {
        $unknown.reason = 'authoritative plugin-state snapshot is stale'
        return $unknown
    }

    $states = @{}
    foreach ($app in @((Get-PropertyValue $snapshot 'apps' @()))) {
        $state = ([string](Get-PropertyValue $app 'state' '')).ToLowerInvariant()
        if ($state -notin @('installed', 'enabled', 'uninstalled', 'not-installed')) {
            continue
        }
        foreach ($identity in @(
            [string](Get-PropertyValue $app 'appId' ''),
            [string](Get-PropertyValue $app 'name' '')
        )) {
            $normalized = ($identity.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                $states[$normalized] = $state
            }
        }
    }
    return [pscustomobject]@{
        available = $true
        reason = ''
        states = $states
    }
}

function Normalize-FullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Test-PathWithin {
    param(
        [string]$Path,
        [string]$Root
    )
    $fullPath = Normalize-FullPath $Path
    $fullRoot = Normalize-FullPath $Root
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $fullPath.StartsWith(
        $fullRoot + '\',
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Get-SkillId {
    param([string]$SkillPath)
    $raw = Get-Content -LiteralPath $SkillPath -Raw -Encoding UTF8
    $frontmatter = [regex]::Match($raw, '(?ms)\A---\s*\r?\n(?<body>.*?)\r?\n---')
    if ($frontmatter.Success) {
        $name = [regex]::Match(
            $frontmatter.Groups['body'].Value,
            '(?m)^name\s*:\s*[''"]?(?<name>[^''"\r\n]+)[''"]?\s*$'
        )
        if ($name.Success) { return $name.Groups['name'].Value.Trim() }
    }
    return (Split-Path -Leaf (Split-Path -Parent $SkillPath))
}

function Resolve-RegistryOwnedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $fullPath = Normalize-FullPath $Path
    if ($fullPath.Equals(
        $canonicalRepositoryRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return $RegistryRoot
    }
    $canonicalPrefix = $canonicalRepositoryRoot + '\'
    if ($fullPath.StartsWith(
        $canonicalPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        return Join-Path $RegistryRoot $fullPath.Substring(
            $canonicalPrefix.Length
        )
    }
    return $fullPath
}

function Get-SkillTreeHash {
    param([string]$SkillPath)
    return Get-AgentHubRegistryHashBasisValue -Path (Split-Path -Parent $SkillPath)
}

function Expand-SkillOwnershipPath {
    param([string]$Template)
    $expanded = $Template.Replace('${USERPROFILE}', $UserProfilePath).
        Replace('${APPDATA}', $AppDataPath)
    if ($expanded -match '\$\{') {
        throw "Unsupported skill ownership path placeholder: $Template"
    }
    return Normalize-FullPath ($expanded.Replace('/', '\'))
}

function Add-DiscoveryRoot {
    param(
        [string]$HostId,
        [string]$Path,
        [string]$Kind,
        [string]$Source,
        [bool]$Registered,
        [string]$Lifecycle
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $fullPath = Normalize-FullPath $Path
    $existing = @($script:discoveryRoots | Where-Object {
        $_.hostId -eq $HostId -and
        $_.path.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase) -and
        $_.kind -eq $Kind
    })
    if ($existing.Count -gt 0) { return }
    $script:discoveryRoots.Add([pscustomobject]@{
        hostId = $HostId
        path = $fullPath
        kind = $Kind
        source = $Source
        registered = $Registered
        lifecycle = $Lifecycle
        exists = Test-Path -LiteralPath $fullPath -PathType Container
    })
}

function Add-PluginRoot {
    param(
        [string]$HostId,
        [string]$PluginId,
        [string]$Path,
        [string]$ActivationSource,
        [string]$Lifecycle = 'active'
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $fullPath = Normalize-FullPath $Path
    $existing = @($script:pluginRoots | Where-Object {
        $_.hostId -eq $HostId -and
        $_.pluginId -eq $PluginId -and
        $_.path.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($existing.Count -gt 0) { return }
    $script:pluginRoots.Add([pscustomobject]@{
        hostId = $HostId
        pluginId = $PluginId
        path = $fullPath
        activationSource = $ActivationSource
        lifecycle = $Lifecycle
        exists = Test-Path -LiteralPath $fullPath -PathType Container
    })
}

function Add-SkillsFromRoot {
    param(
        [string]$HostId,
        [string]$Root,
        [string]$SourceType,
        [string]$SourceId
    )
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $files = @(
        Get-ChildItem -LiteralPath $Root -Filter 'SKILL.md' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\(?:node_modules|\.git|\.venv|venv|__pycache__|dist|build)\\'
            }
    )
    foreach ($file in $files) {
        $fullPath = Normalize-FullPath $file.FullName
        $existing = @($script:skillRecords | Where-Object {
            $_.hostId -eq $HostId -and
            $_.path.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($existing.Count -gt 0) { continue }
        $script:skillRecords.Add([pscustomobject]@{
            hostId = $HostId
            skillId = Get-SkillId -SkillPath $fullPath
            hash = Get-SkillTreeHash -SkillPath $fullPath
            fileHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash
            path = $fullPath
            root = Normalize-FullPath $Root
            sourceType = $SourceType
            sourceId = $SourceId
        })
    }
}

function Add-CopilotManifestSkills {
    param(
        [string]$PluginRoot,
        [string]$SourceId
    )

    # Copilot plugin packages can retain nested source inputs below skills/.
    # Their generated manifest is the runtime contract: only bodyPath entries
    # are exposed, rather than every SKILL.md that happens to be in the cache.
    $manifestPath = Join-Path $PluginRoot 'generated\skill-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-DriftResult FAIL 'plugin' "copilot-manifest-missing:$SourceId" `
            'Enabled Copilot plugin has no generated skill manifest; runtime skill exposure cannot be resolved' `
            'copilot' @($PluginRoot, $manifestPath)
        return $true
    }
    $manifest = Read-JsonFile -Path $manifestPath
    if ($null -eq $manifest) { return $true }
    $skills = Get-PropertyValue -InputObject $manifest -Name 'skills'
    if ($null -eq $skills) {
        Add-DriftResult FAIL 'plugin' "copilot-manifest-missing-skills:$SourceId" `
            'Copilot plugin skill manifest has no skills object' 'copilot' @($manifestPath)
        return $true
    }

    foreach ($entry in @($skills.PSObject.Properties)) {
        $bodyPath = [string](Get-PropertyValue -InputObject $entry.Value -Name 'bodyPath' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($bodyPath)) {
            Add-DriftResult FAIL 'plugin' "copilot-manifest-missing-body-path:${SourceId}:$($entry.Name)" `
                'Copilot plugin skill manifest entry has no bodyPath' 'copilot' @($manifestPath)
            continue
        }
        $candidate = Normalize-FullPath (Join-Path $PluginRoot $bodyPath)
        if (-not (Test-PathWithin -Path $candidate -Root $PluginRoot)) {
            Add-DriftResult FAIL 'plugin' "copilot-manifest-body-path-outside-plugin:${SourceId}:$($entry.Name)" `
                'Copilot plugin skill manifest bodyPath resolves outside its plugin root' `
                'copilot' @($manifestPath, $candidate)
            continue
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Add-DriftResult FAIL 'plugin' "copilot-manifest-body-missing:${SourceId}:$($entry.Name)" `
                'Copilot plugin manifest-selected skill body is missing' 'copilot' @($manifestPath, $candidate)
            continue
        }
        $existing = @($script:skillRecords | Where-Object {
            $_.hostId -eq 'copilot' -and
            $_.path.Equals($candidate, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($existing.Count -gt 0) { continue }
        $script:skillRecords.Add([pscustomobject]@{
            hostId = 'copilot'
            skillId = Get-SkillId -SkillPath $candidate
            hash = Get-SkillTreeHash -SkillPath $candidate
            fileHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
            path = $candidate
            root = Normalize-FullPath $PluginRoot
            sourceType = 'plugin-manifest'
            sourceId = $SourceId
        })
    }
    return $true
}

function Get-JsonObjectPropertyNames {
    param(
        [object]$Root,
        [string]$PropertyName
    )
    if ($null -eq $Root) { return @() }
    $value = Get-PropertyValue -InputObject $Root -Name $PropertyName
    if ($null -eq $value) { return @() }
    return @($value.PSObject.Properties | ForEach-Object { [string]$_.Name } |
        Sort-Object -Unique)
}

function Get-TomlStringArray {
    param(
        [string]$Raw,
        [string]$Section,
        [string]$Property
    )
    $sectionMatch = [regex]::Match(
        $Raw,
        "(?ms)^\[$([regex]::Escape($Section))\]\s*(?<body>.*?)(?=^\[|\z)"
    )
    if (-not $sectionMatch.Success) { return @() }
    $propertyMatch = [regex]::Match(
        $sectionMatch.Groups['body'].Value,
        "(?ms)^\s*$([regex]::Escape($Property))\s*=\s*\[(?<items>.*?)\]"
    )
    if (-not $propertyMatch.Success) { return @() }
    return @([regex]::Matches(
        $propertyMatch.Groups['items'].Value,
        '"(?<value>[^"]+)"'
    ) | ForEach-Object { $_.Groups['value'].Value })
}

function Get-McpIdsFromConfig {
    param(
        [string]$Path,
        [string]$Format,
        [string]$Property = ''
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    switch ($Format) {
        'json-object' {
            $root = Read-JsonFile -Path $Path
            return @(Get-JsonObjectPropertyNames -Root $root -PropertyName $Property)
        }
        'json-array' {
            $root = Read-JsonFile -Path $Path
            if ($null -eq $root) { return @() }
            $parent = Get-PropertyValue -InputObject $root -Name 'mcp'
            if ($null -eq $parent) { return @() }
            return @((Get-PropertyValue -InputObject $parent -Name 'allowed' -DefaultValue @()) |
                Sort-Object -Unique)
        }
        'toml' {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $matches = [regex]::Matches(
                $raw,
                '(?m)^\[mcp_servers\.(?:"(?<quoted>[^"]+)"|(?<plain>[^\].]+))\]\s*$'
            )
            return @($matches | ForEach-Object {
                if ($_.Groups['quoted'].Success) {
                    $_.Groups['quoted'].Value
                } else {
                    $_.Groups['plain'].Value
                }
            } | Sort-Object -Unique)
        }
        'yaml' {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            $section = [regex]::Match(
                $raw,
                '(?ms)^mcp_servers\s*:\s*\r?\n(?<body>.*?)(?=^[^\s#][^:\r\n]*\s*:|\z)'
            )
            if (-not $section.Success) { return @() }
            return @([regex]::Matches(
                $section.Groups['body'].Value,
                '(?m)^\s{2}(?<name>[A-Za-z0-9_.-]+)\s*:\s*$'
            ) | ForEach-Object { $_.Groups['name'].Value } | Sort-Object -Unique)
        }
        default { return @() }
    }
}

function Resolve-ConnectorRow {
    param(
        [string]$HostId,
        [hashtable]$Rows
    )
    if (-not $Rows.ContainsKey($HostId)) { return $null }
    $row = $Rows[$HostId]
    $inherits = Get-PropertyValue -InputObject $row -Name 'inheritsHostId'
    if (-not [string]::IsNullOrWhiteSpace([string]$inherits)) {
        return Resolve-ConnectorRow -HostId ([string]$inherits) -Rows $Rows
    }
    return $row
}

function Get-PluginSkillRoot {
    param([string]$PluginRoot)
    foreach ($relative in @('skills', '.claude\skills')) {
        $candidate = Join-Path $PluginRoot $relative
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
    }
    foreach ($version in @(
        Get-ChildItem -LiteralPath $PluginRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )) {
        foreach ($relative in @('skills', '.claude\skills')) {
            $candidate = Join-Path $version.FullName $relative
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                return $candidate
            }
        }
    }
    return ''
}

function Protect-ProcessCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }
    $protected = $CommandLine
    $protected = [regex]::Replace(
        $protected,
        '(?i)(--?(?:api[-_]?key|token|password|secret|authorization|auth)\s*(?:=|\s)\s*)("[^"]*"|''[^'']*''|\S+)',
        '$1<redacted>'
    )
    $protected = [regex]::Replace(
        $protected,
        '(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]+',
        '$1<redacted>'
    )
    $protected = [regex]::Replace(
        $protected,
        '(?i)([?&](?:api[_-]?key|token|secret|password)=)[^&\s]+',
        '$1<redacted>'
    )
    return $protected
}

$agentsPath = Join-Path $RegistryRoot 'registry\agents.json'
$capabilitiesPath = Join-Path $RegistryRoot 'registry\capabilities.json'
$mcpsPath = Join-Path $RegistryRoot 'registry\mcps.json'
$connectorsPath = Join-Path $RegistryRoot 'registry\native-connectors.json'
$skillOwnershipPath = Join-Path $RegistryRoot 'registry\skill-ownership.json'
$runtimePolicyPath = Join-Path $RegistryRoot 'registry\runtime-policy.json'
$reviewerBrokerPath = Join-Path $RegistryRoot 'registry\reviewer-execution-broker.json'
foreach ($requiredPath in @($agentsPath, $capabilitiesPath, $mcpsPath, $connectorsPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required registry is missing: $requiredPath"
    }
}

$agentRegistry = Read-JsonFile -Path $agentsPath
$capabilityRegistry = Read-JsonFile -Path $capabilitiesPath
$mcpRegistry = Read-JsonFile -Path $mcpsPath
$connectorRegistry = Read-JsonFile -Path $connectorsPath
$skillOwnershipRegistry = Read-JsonFile -Path $skillOwnershipPath
$runtimePolicy = Read-JsonFile -Path $runtimePolicyPath
$reviewerBroker = Read-JsonFile -Path $reviewerBrokerPath
$agents = @($agentRegistry.activeAgents) + @($agentRegistry.inactiveAgents)
$agentById = @{}
foreach ($agent in $agents) { $agentById[[string]$agent.id] = $agent }

# Root-level recreation is part of fleet drift because several coding-agent
# runtimes translate POSIX absolute paths to the current Windows drive.
$forbiddenRootPaths = @(
    'C:\package.js',
    'C:\.codex-plugin',
    'C:\.playwright-mcp',
    'C:\cache',
    'C:\product-demo-studio',
    'C:\registry',
    'C:\scripts',
    'C:\skills',
    'C:\Temp',
    'C:\tmp',
    'C:\registry-root',
    'C:\canonical-product-demo-studio',
    'C:\canonical-product-experience-engineering',
    'C:\canonical-browser-toolkit',
    'C:\profile'
)
foreach ($forbiddenPath in $forbiddenRootPaths) {
    if (Test-Path -LiteralPath $forbiddenPath) {
        $item = Get-Item -LiteralPath $forbiddenPath -Force
        $children = if ($item.PSIsContainer) {
            @(
                Get-ChildItem -LiteralPath $forbiddenPath -Force -Recurse `
                    -ErrorAction SilentlyContinue
            ).Count
        } else { 0 }
        Add-DriftResult FAIL 'root-path' "forbidden-root-recreated:$forbiddenPath" `
            "forbidden drive-root artifact exists (created $($item.CreationTime.ToString('o')); children $children)" `
            '' @($forbiddenPath)
    } else {
        Add-DriftResult PASS 'root-path' "forbidden-root:$forbiddenPath" 'absent'
    }
}
$expectedTempRoot = Normalize-FullPath (Join-Path $LocalAppDataPath 'AgentHub\tmp')
$configuredTempRoot = [Environment]::GetEnvironmentVariable('TMPDIR', 'User')
if (-not [string]::IsNullOrWhiteSpace($configuredTempRoot) -and
    (Normalize-FullPath $configuredTempRoot).Equals(
        $expectedTempRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    Add-DriftResult PASS 'root-path' 'user-temp-redirection' `
        "TMPDIR resolves below the AgentHub runtime: $expectedTempRoot"
} else {
    Add-DriftResult FAIL 'root-path' 'user-temp-redirection' `
        'user TMPDIR does not resolve below the AgentHub runtime' '' @($configuredTempRoot)
}

# Executable inventory is read-only. Retained-disabled providers are resolved
# but never launched or probed.
foreach ($agent in $agents) {
    $agentId = [string]$agent.id
    $executable = [string](Get-PropertyValue -InputObject $agent -Name 'executable' -DefaultValue '')
    $installed = $false
    $resolvedExecutable = ''
    if (-not [string]::IsNullOrWhiteSpace($executable)) {
        if ([System.IO.Path]::IsPathRooted($executable)) {
            $installed = Test-Path -LiteralPath $executable -PathType Leaf
            if ($installed) { $resolvedExecutable = Normalize-FullPath $executable }
        } else {
            $command = Get-Command $executable -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) {
                $installed = $true
                $resolvedExecutable = [string]$command.Source
            }
        }
    }
    if ($installed) {
        Add-DriftResult PASS 'installation' "agent-executable:$agentId" $resolvedExecutable $agentId @($resolvedExecutable)
    } elseif ([string]$agent.status -eq 'active') {
        Add-DriftResult FAIL 'installation' "agent-executable:$agentId" 'active agent executable is missing' $agentId @($executable)
    } elseif ([string](Get-PropertyValue $agent 'installationExpectation' '') -eq 'not-installed') {
        Add-DriftResult PASS 'installation' "agent-executable:$agentId" `
            'dormant supported adapter is intentionally not installed on this machine' `
            $agentId
    } else {
        Add-DriftResult WARN 'installation' "agent-executable:$agentId" 'inactive or retained agent executable is not resolved' $agentId @($executable)
    }
}

# Registry-declared discovery roots.
foreach ($agent in $agents) {
    $lifecycle = [string]$agent.status
    $nativePaths = Get-PropertyValue -InputObject $agent -Name 'nativePaths'
    if ($null -eq $nativePaths) { continue }
    foreach ($property in $nativePaths.PSObject.Properties) {
        $kind = switch -Regex ($property.Name) {
            'skillsDir|sharedSkillsDir' { 'skills'; break }
            'pluginsDir' { 'plugins'; break }
            'extensionsDir' { 'extensions'; break }
            default { '' }
        }
        if (-not [string]::IsNullOrWhiteSpace($kind)) {
            Add-DiscoveryRoot -HostId ([string]$agent.id) -Path ([string]$property.Value) `
                -Kind $kind -Source "registry/agents.json:$($property.Name)" `
                -Registered $true -Lifecycle $lifecycle
        }
    }
}

# Observed host-native discovery locations. Existing paths not declared by the
# agent registry are real inventory drift, regardless of active/inactive state.
$observedSurfaces = @(
    @{ hostId='codex'; kind='skills'; path=Join-Path $UserProfilePath '.agents\skills'; field='sharedSkillsDir' },
    @{ hostId='gemini'; kind='skills'; path=Join-Path $UserProfilePath '.agents\skills'; field='sharedSkillsDir' },
    @{ hostId='cline'; kind='skills'; path=Join-Path $UserProfilePath '.agents\skills'; field='sharedSkillsDir' },
    @{ hostId='amp'; kind='skills'; path=Join-Path $UserProfilePath '.config\amp\skills'; field='skillsDir' },
    @{ hostId='devin'; kind='skills'; path=Join-Path $AppDataPath 'devin\skills'; field='skillsDir' },
    @{ hostId='devin'; kind='plugins'; path=Join-Path $AppDataPath 'devin\cli\plugins'; field='pluginsDir' },
    @{ hostId='copilot'; kind='plugins'; path=Join-Path $UserProfilePath '.copilot\installed-plugins'; field='pluginsDir' },
    @{ hostId='antigravity'; kind='plugins'; path=Join-Path $UserProfilePath '.gemini\config\plugins'; field='pluginsDir' },
    @{ hostId='cursor'; kind='extensions'; path=Join-Path $UserProfilePath '.cursor\extensions'; field='extensionsDir' }
)
foreach ($surface in $observedSurfaces) {
    if (-not (Test-Path -LiteralPath $surface.path -PathType Container)) { continue }
    $agent = $agentById[[string]$surface.hostId]
    $nativePaths = Get-PropertyValue -InputObject $agent -Name 'nativePaths'
    $registeredValue = if ($null -ne $nativePaths) {
        Get-PropertyValue -InputObject $nativePaths -Name ([string]$surface.field) -DefaultValue ''
    } else { '' }
    $registered = -not [string]::IsNullOrWhiteSpace([string]$registeredValue) -and
        (Normalize-FullPath ([string]$registeredValue)).Equals(
            (Normalize-FullPath ([string]$surface.path)),
            [StringComparison]::OrdinalIgnoreCase
        )
    Add-DiscoveryRoot -HostId ([string]$surface.hostId) -Path ([string]$surface.path) `
        -Kind ([string]$surface.kind) -Source 'live-observed' -Registered $registered `
        -Lifecycle ([string]$agent.status)
    if (-not $registered) {
        Add-DriftResult FAIL 'discovery' `
            "unregistered-discovery-root:$($surface.hostId):$($surface.field)" `
            'existing host discovery root is absent from registry/agents.json' `
            ([string]$surface.hostId) @([string]$surface.path)
    }
}

# Resolve active plugin roots from each host's supported installation registry.
$claudeSettings = Read-JsonFile -Path (Join-Path $UserProfilePath '.claude\settings.json')
$claudeInstalledPath = Join-Path $UserProfilePath '.claude\plugins\installed_plugins.json'
$claudeInstalled = Read-JsonFile -Path $claudeInstalledPath
if ($claudeSettings -and $claudeInstalled) {
    $enabled = Get-PropertyValue -InputObject $claudeSettings -Name 'enabledPlugins'
    $installed = Get-PropertyValue -InputObject $claudeInstalled -Name 'plugins'
    foreach ($entry in @($enabled.PSObject.Properties | Where-Object { [bool]$_.Value })) {
        $versions = Get-PropertyValue -InputObject $installed -Name ([string]$entry.Name) -DefaultValue @()
        $selected = @($versions | Sort-Object installedAt -Descending | Select-Object -First 1)
        if ($selected.Count -eq 1) {
            Add-PluginRoot 'claude' ([string]$entry.Name) ([string]$selected[0].installPath) $claudeInstalledPath
        } else {
            Add-DriftResult FAIL 'plugin' "enabled-plugin-missing:claude:$($entry.Name)" `
                'enabled plugin has no installed package record' 'claude' @($claudeInstalledPath)
        }
    }
}

$codexConfigPath = Join-Path $UserProfilePath '.codex\config.toml'
if (Test-Path -LiteralPath $codexConfigPath -PathType Leaf) {
    $codexRaw = Get-Content -LiteralPath $codexConfigPath -Raw -Encoding UTF8
    $enabledMatches = [regex]::Matches(
        $codexRaw,
        '(?ms)^\[plugins\."(?<plugin>[^"]+)"\]\s*\r?\nenabled\s*=\s*true\s*$'
    )
    foreach ($match in $enabledMatches) {
        $pluginId = $match.Groups['plugin'].Value
        $parts = $pluginId -split '@', 2
        if ($parts.Count -ne 2) { continue }
        $candidateParent = Join-Path $UserProfilePath ".codex\plugins\cache\$($parts[1])\$($parts[0])"
        $version = @(
            Get-ChildItem -LiteralPath $candidateParent -Directory -ErrorAction SilentlyContinue |
                Where-Object Name -notmatch '^latest$|^plugin-backup-' |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
        )
        if ($version.Count -eq 1) {
            Add-PluginRoot 'codex' $pluginId $version[0].FullName $codexConfigPath
        } else {
            Add-DriftResult FAIL 'plugin' "enabled-plugin-missing:codex:$pluginId" `
                'enabled plugin package is absent from the declared marketplace cache' `
                'codex' @($candidateParent)
        }
    }
}

$qwenExtensions = Join-Path $UserProfilePath '.qwen\extensions'
if (Test-Path -LiteralPath $qwenExtensions -PathType Container) {
    foreach ($extension in Get-ChildItem -LiteralPath $qwenExtensions -Directory -ErrorAction SilentlyContinue) {
        Add-PluginRoot 'qwen-code' $extension.Name $extension.FullName $qwenExtensions
    }
}

$copilotConfigPath = Join-Path $UserProfilePath '.copilot\config.json'
if (Test-Path -LiteralPath $copilotConfigPath -PathType Leaf) {
    $copilotRaw = Get-Content -LiteralPath $copilotConfigPath -Raw -Encoding UTF8
    $copilotConfig = $copilotRaw -replace '(?m)^\s*//.*$', '' | ConvertFrom-Json
    foreach ($plugin in @($copilotConfig.installedPlugins | Where-Object enabled -eq $true)) {
        Add-PluginRoot 'copilot' ([string]$plugin.name) ([string]$plugin.cache_path) $copilotConfigPath
    }
}

$qoderSettingsPath = Join-Path $UserProfilePath '.qoder\settings.json'
$qoderSettings = Read-JsonFile -Path $qoderSettingsPath
if ($qoderSettings) {
    $enabled = Get-PropertyValue -InputObject $qoderSettings -Name 'enabledPlugins'
    foreach ($entry in @($enabled.PSObject.Properties | Where-Object { [bool]$_.Value })) {
        $parts = ([string]$entry.Name) -split '@', 2
        if ($parts.Count -ne 2) { continue }
        $candidate = Join-Path $UserProfilePath ".qoder\plugins\cache\$($parts[1])\$($parts[0])"
        Add-PluginRoot 'qoder' ([string]$entry.Name) $candidate $qoderSettingsPath
    }
}

$grokRegistryPath = Join-Path $UserProfilePath '.grok\installed-plugins\registry.json'
$grokRegistry = Read-JsonFile -Path $grokRegistryPath
$grokConfigPath = Join-Path $UserProfilePath '.grok\config.toml'
$grokConfigRaw = if (Test-Path -LiteralPath $grokConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $grokConfigPath -Raw -Encoding UTF8
} else { '' }
$grokEnabledPlugins = @(
    Get-TomlStringArray -Raw $grokConfigRaw -Section 'plugins' -Property 'enabled'
)
if ($grokRegistry) {
    $repos = Get-PropertyValue -InputObject $grokRegistry -Name 'repos'
    foreach ($repo in @($repos.PSObject.Properties)) {
        foreach ($plugin in @($repo.Value.plugins.PSObject.Properties)) {
            $pluginName = [string]$plugin.Name
            if ($pluginName -notin $grokEnabledPlugins) { continue }
            $pluginPath = [string]$repo.Value.path
            $subdir = [string](Get-PropertyValue $plugin.Value 'subdir' '')
            if (-not [string]::IsNullOrWhiteSpace($subdir)) {
                $pluginPath = Join-Path $pluginPath $subdir
            }
            Add-PluginRoot 'grok' $pluginName $pluginPath $grokConfigPath

            $manifestPath = @(
                (Join-Path $pluginPath '.claude-plugin\plugin.json'),
                (Join-Path $pluginPath '.github\plugin\plugin.json')
            ) | Where-Object {
                Test-Path -LiteralPath $_ -PathType Leaf
            } | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace([string]$manifestPath)) {
                continue
            }
            $manifest = Read-JsonFile -Path $manifestPath
            $mcpServers = Get-PropertyValue $manifest 'mcpServers'
            if ($null -eq $mcpServers) { continue }
            $grokConnector = @($connectorRegistry.hosts | Where-Object {
                $_.hostId -eq 'grok'
            } | Select-Object -First 1)
            $supportedMcpIds = if ($grokConnector.Count -eq 1) {
                @(
                    $grokConnector[0].exposures.'plugin-owned' +
                    $grokConnector[0].exposures.'native-connector' +
                    $grokConnector[0].exposures.'shared-gateway' +
                    $grokConnector[0].exposures.'local-only'
                )
            } else { @() }
            foreach ($mcpId in @($mcpServers.PSObject.Properties.Name)) {
                if ($mcpId -notin $supportedMcpIds) {
                    Add-DriftResult FAIL 'plugin' `
                        "unsupported-enabled-local-plugin:grok:${pluginName}:${mcpId}" `
                        'enabled Grok plugin owns a local MCP absent from Grok native-connector ownership' `
                        'grok' @($grokConfigPath, $manifestPath)
                }
            }
        }
    }
}

$vscodeSettingsPath = Join-Path $AppDataPath 'Code - Insiders\User\settings.json'
$vscodeSettings = Read-JsonFile -Path $vscodeSettingsPath
if ($vscodeSettings) {
    $locations = Get-PropertyValue -InputObject $vscodeSettings -Name 'chat.pluginLocations'
    if ($locations) {
        foreach ($entry in @($locations.PSObject.Properties | Where-Object { [bool]$_.Value })) {
            Add-PluginRoot 'vscode-insiders' (Split-Path -Leaf ([string]$entry.Name)) `
                ([string]$entry.Name) $vscodeSettingsPath 'inactive'
        }
    }
}

# Cursor native local plugins are inventoried without invoking a paid agent run.
$cursorLocalPlugins = Join-Path $UserProfilePath '.cursor\plugins\local'
if (Test-Path -LiteralPath $cursorLocalPlugins -PathType Container) {
    foreach ($plugin in Get-ChildItem -LiteralPath $cursorLocalPlugins -Directory -ErrorAction SilentlyContinue) {
        Add-PluginRoot 'cursor' $plugin.Name $plugin.FullName $cursorLocalPlugins 'installed-observed'
    }
}

# Antigravity CLI and Desktop/IDE have distinct documented plugin roots.
foreach ($antigravityPlugins in @(
    (Join-Path $UserProfilePath '.gemini\antigravity-cli\plugins'),
    (Join-Path $UserProfilePath '.gemini\config\plugins')
)) {
    if (Test-Path -LiteralPath $antigravityPlugins -PathType Container) {
        foreach ($plugin in Get-ChildItem -LiteralPath $antigravityPlugins -Directory -ErrorAction SilentlyContinue) {
            Add-PluginRoot 'antigravity' $plugin.Name $plugin.FullName `
                $antigravityPlugins 'installed-observed'
        }
    }
}

foreach ($plugin in @($pluginRoots.ToArray())) {
    $pluginStates.Add([pscustomobject]@{
        hostId = $plugin.hostId
        pluginId = $plugin.pluginId
        path = $plugin.path
        lifecycle = $plugin.lifecycle
        exists = $plugin.exists
        activationSource = $plugin.activationSource
    })
    if (-not $plugin.exists) {
        Add-DriftResult FAIL 'plugin' "plugin-root-missing:$($plugin.hostId):$($plugin.pluginId)" `
            'registered or enabled plugin root is missing' $plugin.hostId @($plugin.path)
    }
}

# Devin required local plugins must resolve to real sources. Cached symbolic
# links do not make a deleted source registration healthy.
$devinLockPath = Join-Path $AppDataPath 'devin\cli\plugins\lock.json'
$devinLock = Read-JsonFile -Path $devinLockPath
if ($devinLock) {
    foreach ($requirement in @($devinLock.requirements | Where-Object required -eq $true)) {
        $sourcePath = [string]$requirement.spec.path
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        Add-DriftResult FAIL 'plugin' "required-plugin-source-missing:devin:$([System.IO.Path]::GetFileName($sourcePath))" `
                'Devin requires a local plugin source that no longer exists' `
                'devin' @($sourcePath, $devinLockPath)
        }
    }
}

# Scan every declared loose skill root and each active plugin's primary skills
# directory. Package caches that are not activated are deliberately excluded.
foreach ($root in @($discoveryRoots.ToArray() | Where-Object { $_.kind -eq 'skills' -and $_.exists })) {
    Add-SkillsFromRoot -HostId $root.hostId -Root $root.path -SourceType 'loose' -SourceId $root.source
}
foreach ($plugin in @($pluginRoots.ToArray() | Where-Object exists)) {
    if ($plugin.hostId -eq 'copilot' -and
        (Add-CopilotManifestSkills -PluginRoot $plugin.path -SourceId $plugin.pluginId)) {
        continue
    }
    $skillRoot = Get-PluginSkillRoot -PluginRoot $plugin.path
    if (-not [string]::IsNullOrWhiteSpace($skillRoot)) {
        Add-SkillsFromRoot -HostId $plugin.hostId -Root $skillRoot `
            -SourceType 'plugin' -SourceId $plugin.pluginId
    }
}

# Build the canonical skill owner index from actual AgentHub source packages.
$canonicalSkillRecords = New-Object System.Collections.Generic.List[object]
foreach ($capability in @($capabilityRegistry.capabilities)) {
    $source = Resolve-RegistryOwnedPath ([string]$capability.canonicalSource)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
    foreach ($file in @(
        Get-ChildItem -LiteralPath $source -Filter 'SKILL.md' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\(?:node_modules|\.git|\.venv|venv|__pycache__|dist|build)\\'
            }
    )) {
        $canonicalSkillRecords.Add([pscustomobject]@{
            capabilityId = [string]$capability.id
            skillId = Get-SkillId -SkillPath $file.FullName
            hash = Get-SkillTreeHash -SkillPath $file.FullName
            path = Normalize-FullPath $file.FullName
            hostIds = @($capability.hostMappings.hostId)
        })
    }
}
$canonicalBySkill = @{}
foreach ($record in @($canonicalSkillRecords.ToArray())) {
    if (-not $canonicalBySkill.ContainsKey($record.skillId)) {
        $canonicalBySkill[$record.skillId] = @()
    }
    $canonicalBySkill[$record.skillId] += $record
}

$externallyOwnedSkillIds = @()
$retiredUnownedSkillIds = @()
if ($null -ne $skillOwnershipRegistry) {
    foreach ($externalOwner in @($skillOwnershipRegistry.externalOwners)) {
        $skillId = [string]$externalOwner.skillId
        $externallyOwnedSkillIds += $skillId
        $currentHash = ([string]$externalOwner.treeHash).ToUpperInvariant()
        foreach ($target in @($externalOwner.targets)) {
            $hostId = [string]$target.hostId
            $targetPath = Expand-SkillOwnershipPath -Template ([string]$target.path)
            $matches = @($skillRecords.ToArray() | Where-Object {
                $_.hostId -eq $hostId -and
                $_.skillId -eq $skillId -and
                (Normalize-FullPath (Split-Path -Parent $_.path)).Equals(
                    $targetPath,
                    [StringComparison]::OrdinalIgnoreCase
                )
            })
            if ($matches.Count -eq 0) {
                Add-DriftResult FAIL 'skill' "external-skill-missing:${hostId}:${skillId}" `
                    "vendor-owned skill target is missing; expected trusted tree hash $currentHash" `
                    $hostId @($targetPath)
                continue
            }
            foreach ($match in $matches) {
                if ([string]$match.hash -eq $currentHash) {
                    Add-DriftResult PASS 'skill' "external-skill-current:${hostId}:${skillId}" `
                        "vendor-owned skill matches $($externalOwner.owner) version $($externalOwner.currentVersion)" `
                        $hostId @($match.path)
                } else {
                    Add-DriftResult FAIL 'skill' "external-skill-content-drift:${hostId}:${skillId}" `
                        "vendor-owned skill does not match trusted tree hash $currentHash" `
                        $hostId @($match.path)
                }
            }
        }
    }

    foreach ($retired in @($skillOwnershipRegistry.retiredUnownedSkills)) {
        $skillId = [string]$retired.skillId
        $retiredUnownedSkillIds += $skillId
        $observedHashes = @($retired.observedHashes | ForEach-Object {
            ([string]$_).ToUpperInvariant()
        })
        $activePaths = New-Object System.Collections.Generic.List[string]
        $divergentPaths = New-Object System.Collections.Generic.List[string]
        foreach ($template in @($retired.paths)) {
            $targetPath = Expand-SkillOwnershipPath -Template ([string]$template)
            $skillPath = Join-Path $targetPath 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
                continue
            }
            $activePaths.Add($skillPath)
            $actualHash = (Get-FileHash -LiteralPath $skillPath -Algorithm SHA256).Hash
            if ($actualHash -notin $observedHashes) {
                $divergentPaths.Add($skillPath)
            }
        }
        if ($activePaths.Count -eq 0) {
            Add-DriftResult PASS 'skill' "retired-unowned-skill-absent:${skillId}" `
                "retired skill is not exposed from any recorded host path; $($retired.blockerReason)"
        } else {
            $detail = if ($divergentPaths.Count -gt 0) {
                "$($activePaths.Count) retired active copy/copies remain and $($divergentPaths.Count) diverge from preserved evidence; recreation or mutation is prohibited"
            } else {
                "$($activePaths.Count) exact retired active copy/copies remain; preserve evidence outside active skill roots, then remove them"
            }
            Add-DriftResult FAIL 'skill' "retired-unowned-skill-active:${skillId}" `
                $detail '' @($activePaths.ToArray())
        }
    }
}

# Product Demo Studio's multi-agent workflow is not deployed merely because its
# skills are visible. Verify each generated native role surface that AgentHub
# owns, including the six roles that must have mechanical read-only controls.
$productDemoCapability = @($capabilityRegistry.capabilities |
    Where-Object id -eq 'product-demo-studio')
if ($productDemoCapability.Count -eq 1) {
    $productDemoSource = Resolve-RegistryOwnedPath (
        [string]$productDemoCapability[0].canonicalSource
    )
    $canonicalProductDemoAgents = Join-Path $productDemoSource 'agents'
    if (Test-Path -LiteralPath $canonicalProductDemoAgents -PathType Container) {
        $expectedRoleNames = @(
            Get-ChildItem -LiteralPath $canonicalProductDemoAgents -Filter '*.md' -File |
                Sort-Object BaseName |
                ForEach-Object BaseName
        )
        $readOnlyRoleNames = @(
            Get-ChildItem -LiteralPath $canonicalProductDemoAgents -Filter '*.md' -File |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match
                        '(?m)^readonly:\s*true\s*$'
                } |
                ForEach-Object BaseName
        )
        if ($expectedRoleNames.Count -ne 13 -or $readOnlyRoleNames.Count -ne 6) {
            Add-DriftResult FAIL 'role' 'product-demo-studio:canonical-role-contract' `
                "canonical role inventory must contain 13 roles and six read-only roles; found $($expectedRoleNames.Count) and $($readOnlyRoleNames.Count)" `
                '' @($canonicalProductDemoAgents)
        } else {
            Add-DriftResult PASS 'role' 'product-demo-studio:canonical-role-contract' `
                'canonical role inventory contains 13 roles and six read-only roles' `
                '' @($canonicalProductDemoAgents)
        }

        $managedRoleTargets = @(
            @{
                hostId='codex'
                root=(Join-Path $UserProfilePath '.codex\agents')
                prefix='product-demo-studio-'
                extension='.toml'
                readOnlyPattern='(?m)^sandbox_mode\s*=\s*"read-only"\s*$'
            },
            @{
                hostId='opencode'
                root=(Join-Path $UserProfilePath '.config\opencode\agents')
                prefix='product-demo-studio-'
                extension='.md'
                readOnlyPattern='(?ms)^permission:\s*\r?\n(?:\s+.*\r?\n)*?\s+edit:\s*deny\s*$[\s\S]*?\s+bash:\s*deny\s*$'
            },
            @{
                hostId='gemini'
                root=(Join-Path $UserProfilePath '.gemini\extensions\agenthub-product-demo-studio\agents')
                prefix='product-demo-studio-'
                extension='.md'
                readOnlyPattern='(?ms)^tools:\s*\r?\n(?:\s+-\s+(?:read_file|grep_search|glob)\s*\r?\n)+'
            },
            @{
                hostId='antigravity'
                root=(Join-Path $UserProfilePath '.gemini\antigravity-cli\plugins\product-demo-studio\agents')
                prefix='product-demo-studio-'
                extension='.md'
                readOnlyPattern='(?m)^commandExecutionPolicy:\s*off\s*$'
            }
        )
        foreach ($target in $managedRoleTargets) {
            $mapping = @($productDemoCapability[0].hostMappings |
                Where-Object hostId -eq $target.hostId)
            if ($mapping.Count -ne 1) { continue }
            $missing = @()
            $unenforced = @()
            foreach ($roleName in $expectedRoleNames) {
                $path = Join-Path $target.root (
                    "$($target.prefix)$roleName$($target.extension)"
                )
                if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
                    $missing += $path
                    continue
                }
                if ($roleName -in $readOnlyRoleNames) {
                    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
                    if ($raw -notmatch $target.readOnlyPattern) {
                        $unenforced += $path
                    }
                }
            }
            if ($missing.Count -gt 0 -or $unenforced.Count -gt 0) {
                Add-DriftResult FAIL 'role' `
                    "product-demo-studio:native-roles:$($target.hostId)" `
                    "native Product Demo Studio role drift: $($missing.Count) missing, $($unenforced.Count) without expected read-only restriction" `
                    $target.hostId @($missing + $unenforced)
            } else {
                Add-DriftResult PASS 'role' `
                    "product-demo-studio:native-roles:$($target.hostId)" `
                    '13 native roles present; six read-only roles carry the expected host restriction' `
                    $target.hostId @($target.root)
            }
        }

        $qwenExtensionRoot = Join-Path $UserProfilePath `
            '.qwen\extensions\agenthub-product-demo-studio'
        $qwenManifestPath = Join-Path $qwenExtensionRoot 'qwen-extension.json'
        $qwenAgentsRoot = Join-Path $qwenExtensionRoot 'agents'
        $qwenManifest = Read-JsonFile -Path $qwenManifestPath
        $qwenMissing = @($expectedRoleNames | Where-Object {
            !(Test-Path -LiteralPath (Join-Path $qwenAgentsRoot "$_.md") -PathType Leaf)
        })
        if ($qwenManifest -and [string]$qwenManifest.agents -eq 'agents' -and
            $qwenMissing.Count -eq 0) {
            Add-DriftResult PASS 'role' 'product-demo-studio:native-roles:qwen-code' `
                'Qwen extension exposes all 13 Product Demo Studio agents' `
                'qwen-code' @($qwenManifestPath, $qwenAgentsRoot)
        } else {
            Add-DriftResult FAIL 'role' 'product-demo-studio:native-roles:qwen-code' `
                "Qwen Product Demo Studio agent extension is missing its agents declaration or $($qwenMissing.Count) roles" `
                'qwen-code' @($qwenManifestPath, $qwenAgentsRoot)
        }
    }
}

# Independent review is release-eligible only when a host/operator-owned
# execution broker can emit signed receipts. The broker is on-demand and must
# never become another resident Node/Python daemon or expose a signing key to
# an agent process.
if ($null -ne $reviewerBroker) {
    $trust = Get-PropertyValue $reviewerBroker 'trust' $null
    $execution = Get-PropertyValue $reviewerBroker 'execution' $null
    $trustVariable = [string](
        Get-PropertyValue $trust 'registryEnvironmentVariable' ''
    )
    $contractValid =
        [string]$reviewerBroker.mode -eq 'on-demand' -and
        (Get-PropertyValue $reviewerBroker 'persistentProcessAllowed' $true) -eq $false -and
        (Get-PropertyValue $trust 'agentsMayAuthorReceipts' $true) -eq $false -and
        (Get-PropertyValue $trust 'agentsMaySignReceipts' $true) -eq $false -and
        (Get-PropertyValue $trust 'privateKeyMaterialAllowedInAgentHub' $true) -eq $false -and
        (Get-PropertyValue $trust 'privateKeyMaterialAllowedInAgentEnvironment' $true) -eq $false -and
        [string](Get-PropertyValue $trust 'missingTrustDecision' '') -eq 'PIPELINE_BLOCKED' -and
        (Get-PropertyValue $execution 'spawnOnlyWhenRoleIsDispatched' $false) -eq $true -and
        (Get-PropertyValue $execution 'terminateAfterReceiptIsEmitted' $false) -eq $true -and
        (Get-PropertyValue $execution 'sharedDaemonRequired' $true) -eq $false -and
        $trustVariable -eq 'AGENTHUB_EXECUTION_HOST_TRUST_CONFIG'
    if (-not $contractValid) {
        Add-DriftResult FAIL 'role' 'reviewer-execution-broker:contract' `
            'reviewer broker must be on-demand, fail closed, keep private keys outside agent access, and prohibit agent-authored signatures' `
            '' @($reviewerBrokerPath)
    } else {
        Add-DriftResult PASS 'role' 'reviewer-execution-broker:contract' `
            'on-demand broker contract prohibits resident daemons and agent-owned signing keys' `
            '' @($reviewerBrokerPath)
    }

    $trustPath = [Environment]::GetEnvironmentVariable($trustVariable, 'Process')
    if ([string]::IsNullOrWhiteSpace($trustPath)) {
        $trustPath = [Environment]::GetEnvironmentVariable($trustVariable, 'User')
    }
    $trustAvailable = -not [string]::IsNullOrWhiteSpace($trustPath) -and
        (Test-Path -LiteralPath $trustPath -PathType Leaf)
    $reviewerBrokerState = [pscustomobject]@{
        mode = [string]$reviewerBroker.mode
        persistentProcessAllowed = [bool]$reviewerBroker.persistentProcessAllowed
        trustEnvironmentVariable = $trustVariable
        trustConfigured = $trustAvailable
        releaseEligible = $contractValid -and $trustAvailable
    }
    if ($trustAvailable) {
        $trustDocument = Read-JsonFile -Path $trustPath
        if ($null -ne $trustDocument -and
            [int](Get-PropertyValue $trustDocument 'schemaVersion' 0) -ge 1 -and
            @((Get-PropertyValue $trustDocument 'hosts' @())).Count -gt 0) {
            Add-DriftResult PASS 'role' 'reviewer-execution-broker:operator-trust' `
                'operator-owned trust registry is configured; live receipts still require per-run signature validation' `
                '' @($trustPath)
        } else {
            Add-DriftResult FAIL 'role' 'reviewer-execution-broker:operator-trust' `
                'configured operator trust registry is malformed or has no enabled host inventory' `
                '' @($trustPath)
        }
    } else {
        Add-DriftResult WARN 'role' 'reviewer-execution-broker:operator-trust' `
            'operator-owned trust registry is not configured; Product Demo Studio review, arbitration, final verification, and delivery correctly remain PIPELINE_BLOCKED' `
            '' @($trustPath)
    }
}

$retiredSkillIds = @('agent-fleet-ops', 'agent-capabilities')
foreach ($capability in @($capabilityRegistry.capabilities)) {
    foreach ($retired in @((Get-PropertyValue $capability 'retiredSkills' @()))) {
        $retiredSkillIds += [string]$retired.name
    }
    foreach ($retiredName in @((Get-PropertyValue $capability 'retiredSkillNames' @()))) {
        $retiredSkillIds += [string]$retiredName
    }
}
$retiredSkillIds = @($retiredSkillIds | Where-Object { $_ } | Sort-Object -Unique)
foreach ($retiredId in $retiredSkillIds) {
    $matches = @($skillRecords.ToArray() | Where-Object skillId -eq $retiredId)
    if ($matches.Count -gt 0) {
        $retiredHosts = @($matches.hostId | Sort-Object -Unique)
        $retiredHostId = if ($retiredHosts.Count -eq 1) {
            [string]$retiredHosts[0]
        } else { '' }
        Add-DriftResult FAIL 'skill' "retired-skill:$retiredId" `
            "retired skill remains visible through $($matches.Count) host discovery exposure(s): $($retiredHosts -join ', ')" `
            $retiredHostId @($matches.path)
    } else {
        Add-DriftResult PASS 'skill' "retired-skill:$retiredId" 'absent from inventoried discovery roots'
    }
}

foreach ($group in @($skillRecords.ToArray() | Group-Object hostId, skillId | Where-Object Count -gt 1)) {
    $items = @($group.Group)
    $hashes = @($items.hash | Sort-Object -Unique)
    $hostId = [string]$items[0].hostId
    $skillId = [string]$items[0].skillId
    $shape = if ($hashes.Count -eq 1) { 'byte-equivalent' } else { 'content-divergent' }
    $agentLifecycle = if ($agentById.ContainsKey($hostId)) {
        [string]$agentById[$hostId].status
    } else { 'unknown' }
    $duplicateStatus = if ($agentLifecycle -eq 'active') { 'FAIL' } else { 'WARN' }
    Add-DriftResult $duplicateStatus 'skill' "duplicate-skill-exposure:${hostId}:${skillId}" `
        "$($items.Count) configured discovery sources expose the same skill ID ($shape; host lifecycle $agentLifecycle)" `
        $hostId @($items.path)
}

foreach ($record in @($skillRecords.ToArray())) {
    if (-not $canonicalBySkill.ContainsKey($record.skillId)) { continue }
    $applicableOwners = @($canonicalBySkill[$record.skillId] | Where-Object {
        $record.hostId -in @($_.hostIds)
    })
    if ($applicableOwners.Count -eq 0) { continue }
    $canonicalHashes = @($applicableOwners.hash | Sort-Object -Unique)
    if ($record.hash -notin $canonicalHashes) {
        Add-DriftResult FAIL 'skill' "canonical-skill-content-drift:$($record.hostId):$($record.skillId)" `
            'deployed skill ID is canonical but its content does not match any canonical owner copy' `
            $record.hostId @($record.path, @($applicableOwners.path))
    }
}

$unownedLoose = @($skillRecords.ToArray() | Where-Object {
    $_.sourceType -eq 'loose' -and
    -not $canonicalBySkill.ContainsKey($_.skillId) -and
    $_.skillId -notin $externallyOwnedSkillIds -and
    $_.skillId -notin $retiredUnownedSkillIds
})
foreach ($group in @($unownedLoose | Group-Object skillId)) {
    $uniquePaths = @($group.Group.path | Sort-Object -Unique)
    if ($uniquePaths.Count -lt 2) { continue }
    $hashes = @($group.Group.hash | Sort-Object -Unique)
    $hosts = @($group.Group.hostId | Sort-Object -Unique)
    if ($hashes.Count -gt 1) {
        Add-DriftResult FAIL 'skill' "unowned-cross-host-content-drift:$($group.Name)" `
            "unregistered loose skill has divergent copies across hosts: $($hosts -join ', ')" `
            '' $uniquePaths
    } else {
        Add-DriftResult WARN 'skill' "unowned-repeated-loose-skill:$($group.Name)" `
            "unregistered loose skill is copied outside a canonical capability owner: $($hosts -join ', ')" `
            '' $uniquePaths
    }
}

# Validate all known reparse points without following them as authority.
$reparseRoots = @(
    @($discoveryRoots.ToArray() | Where-Object exists | ForEach-Object path) +
    @($pluginRoots.ToArray() | Where-Object exists | ForEach-Object path)
) | Sort-Object -Unique
$seenReparse = @{}
foreach ($root in $reparseRoots) {
    foreach ($item in @(
        Get-ChildItem -LiteralPath $root -Force -Recurse -Attributes ReparsePoint `
            -ErrorAction SilentlyContinue
    )) {
        $fullPath = Normalize-FullPath $item.FullName
        if ($seenReparse.ContainsKey($fullPath)) { continue }
        $seenReparse[$fullPath] = $true
        $targets = @($item.Target)
        foreach ($target in $targets) {
            if ([string]::IsNullOrWhiteSpace([string]$target)) { continue }
            $resolvedTarget = if ([System.IO.Path]::IsPathRooted([string]$target)) {
                Normalize-FullPath ([string]$target)
            } else {
                Normalize-FullPath (Join-Path (Split-Path -Parent $fullPath) ([string]$target))
            }
            if (-not (Test-Path -LiteralPath $resolvedTarget)) {
                Add-DriftResult FAIL 'filesystem' "dangling-reparse-point:$fullPath" `
                    'agent discovery or plugin reparse point targets a missing path' `
                    $(if (Test-PathWithin -Path $fullPath -Root (Join-Path $AppDataPath 'devin')) {
                        'devin'
                    } else { '' }) @($fullPath, $resolvedTarget)
            }
        }
    }
}

# Compare every supported persisted MCP configuration, including the hosts
# omitted by the older profile checker.
$mcpConfigDefinitions = @(
    @{ hostId='claude'; path=Join-Path $UserProfilePath '.claude.json'; format='json-object'; property='mcpServers' },
    @{ hostId='codex'; path=Join-Path $UserProfilePath '.codex\config.toml'; format='toml'; property='' },
    @{ hostId='qwen-code'; path=Join-Path $UserProfilePath '.qwen\settings.json'; format='json-array'; property='' },
    @{ hostId='opencode'; path=Join-Path $UserProfilePath '.config\opencode\opencode.json'; format='json-object'; property='mcp' },
    @{ hostId='gemini'; path=Join-Path $UserProfilePath '.gemini\settings.json'; format='json-object'; property='mcpServers' },
    @{ hostId='hermes'; path=Join-Path $LocalAppDataPath 'hermes\config.yaml'; format='yaml'; property='' },
    @{ hostId='copilot'; path=Join-Path $UserProfilePath '.copilot\mcp-config.json'; format='json-object'; property='mcpServers' },
    @{ hostId='antigravity'; path=Join-Path $UserProfilePath '.gemini\antigravity\mcp_config.json'; format='json-object'; property='mcpServers' },
    @{ hostId='antigravity'; path=Join-Path $UserProfilePath '.gemini\config\mcp_config.json'; format='json-object'; property='mcpServers'; surface='legacy' },
    @{ hostId='grok'; path=Join-Path $UserProfilePath '.grok\config.toml'; format='toml'; property='' },
    @{ hostId='warp'; path=Join-Path $UserProfilePath '.warp\.mcp.json'; format='json-object'; property='mcpServers' },
    @{ hostId='cline'; path=Join-Path $UserProfilePath '.cline\data\settings\cline_mcp_settings.json'; format='json-object'; property='mcpServers' },
    @{ hostId='qoder'; path=Join-Path $UserProfilePath '.qoder\settings.json'; format='json-object'; property='mcpServers' },
    @{ hostId='cursor'; path=Join-Path $UserProfilePath '.cursor\mcp.json'; format='json-object'; property='mcpServers' },
    @{ hostId='amp'; path=Join-Path $UserProfilePath '.config\amp\settings.json'; format='json-object'; property='amp.mcpServers' },
    @{ hostId='devin'; path=Join-Path $AppDataPath 'devin\config.json'; format='json-object'; property='mcpServers' },
    @{ hostId='factory'; path=Join-Path $UserProfilePath '.factory\mcp.json'; format='json-object'; property='mcpServers' },
    @{ hostId='vscode-insiders'; path=Join-Path $AppDataPath 'Code - Insiders\User\mcp.json'; format='json-object'; property='servers' },
    @{ hostId='windsurf'; path=Join-Path $UserProfilePath '.codeium\windsurf\mcp_config.json'; format='json-object'; property='mcpServers' }
)
$connectorRows = @{}
foreach ($row in @($connectorRegistry.hosts)) {
    $connectorRows[[string]$row.hostId] = $row
}
$registeredMcpIds = @($mcpRegistry.mcpServers | ForEach-Object { [string]$_.id })
$onDemandMcpIds = @($connectorRegistry.lifecyclePolicy.onDemandLocalMcpIds)
$allowedHostExtras = @{
    codex = @('node_repl')
}
foreach ($definition in $mcpConfigDefinitions) {
    $hostId = [string]$definition.hostId
    $path = Normalize-FullPath ([string]$definition.path)
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actual = @(
        if ($exists) {
            Get-McpIdsFromConfig -Path $path -Format ([string]$definition.format) `
                -Property ([string]$definition.property)
        }
    )
    $connector = Resolve-ConnectorRow -HostId $hostId -Rows $connectorRows
    $expected = if ($connector) {
        @($connector.exposures.'shared-gateway' | Sort-Object -Unique)
    } else { @() }
    $pluginOwned = if ($connector) {
        @($connector.exposures.'plugin-owned' | Sort-Object -Unique)
    } else { @() }
    $extrasAllowed = if ($allowedHostExtras.ContainsKey($hostId)) {
        @($allowedHostExtras[$hostId])
    } else { @() }
    $surface = if ($definition.ContainsKey('surface')) {
        [string]$definition.surface
    } else { 'primary' }
    $mcpStates.Add([pscustomobject]@{
        hostId = $hostId
        surface = $surface
        path = $path
        exists = $exists
        expectedDirect = @($expected)
        actualDirect = @($actual)
        pluginOwned = @($pluginOwned)
    })
    if (-not $exists) {
        $agent = $agentById[$hostId]
        if ($agent -and [string]$agent.status -eq 'active') {
            Add-DriftResult FAIL 'mcp' "mcp-config-missing:${hostId}:${surface}" `
                'active host MCP configuration is missing' $hostId @($path)
        } else {
            Add-DriftResult WARN 'mcp' "mcp-config-missing:${hostId}:${surface}" `
                'inactive or retained host MCP configuration is missing' $hostId @($path)
        }
        continue
    }
    $missing = @($expected | Where-Object { $_ -notin $actual })
    $unexpected = @($actual | Where-Object {
        $_ -notin $expected -and $_ -notin $extrasAllowed
    })
    $localLeaks = @($actual | Where-Object { $_ -in $onDemandMcpIds })
    $pluginDuplicates = @($actual | Where-Object { $_ -in $pluginOwned })
    $unregistered = @($unexpected | Where-Object { $_ -notin $registeredMcpIds })
    if ($missing.Count -gt 0) {
        Add-DriftResult FAIL 'mcp' "mcp-direct-missing:${hostId}:${surface}" `
            "missing canonical direct remote MCPs: $($missing -join ', ')" $hostId @($path)
    }
    if ($localLeaks.Count -gt 0) {
        Add-DriftResult FAIL 'mcp' "mcp-local-persisted:${hostId}:${surface}" `
            "on-demand local MCPs are persisted: $($localLeaks -join ', ')" $hostId @($path)
    }
    if ($pluginDuplicates.Count -gt 0) {
        Add-DriftResult FAIL 'mcp' "mcp-plugin-owner-duplicated:${hostId}:${surface}" `
            "plugin-owned MCPs are also directly registered: $($pluginDuplicates -join ', ')" `
            $hostId @($path)
    }
    if ($unregistered.Count -gt 0) {
        Add-DriftResult FAIL 'mcp' "mcp-unregistered:${hostId}:${surface}" `
            "MCP IDs have no AgentHub registry owner: $($unregistered -join ', ')" $hostId @($path)
    }
    $otherUnexpected = @($unexpected | Where-Object {
        $_ -notin $localLeaks -and $_ -notin $pluginDuplicates -and $_ -notin $unregistered
    })
    if ($otherUnexpected.Count -gt 0) {
        Add-DriftResult FAIL 'mcp' "mcp-unexpected-direct:${hostId}:${surface}" `
            "registered MCPs are exposed through the wrong direct surface: $($otherUnexpected -join ', ')" `
            $hostId @($path)
    }
    if ($missing.Count -eq 0 -and $unexpected.Count -eq 0) {
        Add-DriftResult PASS 'mcp' "mcp-direct-set:${hostId}:${surface}" `
            "$($actual.Count) direct registrations match connector ownership" $hostId @($path)
    }
}

# Codex remote connector packages can overlap direct registrations even though
# they create no local Node process. Inventory this as logical tool duplication.
$codexRemoteRoot = Join-Path $UserProfilePath '.codex\plugins\cache\openai-curated-remote'
$codexPluginSnapshot = Get-CodexPluginInstallSnapshot -Path $CodexPluginStatePath
if (Test-Path -LiteralPath $codexRemoteRoot -PathType Container) {
    $codexDirectState = @($mcpStates.ToArray() | Where-Object {
        $_.hostId -eq 'codex' -and $_.surface -eq 'primary'
    } | Select-Object -First 1)
    $codexDirect = if ($codexDirectState.Count -eq 1) {
        @($codexDirectState[0].actualDirect)
    } else { @() }
    $mcpAliases = @{
        adobe = 'adobe-for-creativity'
        'adobe-formerly-photoshop' = 'adobe-for-creativity'
        'tavily-ai' = 'tavily'
        'tavily' = 'tavily'
        'github' = 'github'
        'context7' = 'context7'
        'exa' = 'exa'
        'notion' = 'notion'
        'linear' = 'linear'
        'descript' = 'descript'
        'canva' = 'canva'
    }
    foreach ($package in Get-ChildItem -LiteralPath $codexRemoteRoot -Directory -ErrorAction SilentlyContinue) {
        $version = Get-ChildItem -LiteralPath $package.FullName -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $version) { continue }
        $manifestPath = Join-Path $version.FullName '.codex-plugin\plugin.json'
        $manifest = Read-JsonFile -Path $manifestPath
        $displayName = if ($manifest) {
            [string](Get-PropertyValue (Get-PropertyValue $manifest 'interface') 'displayName' $package.Name)
        } else { $package.Name }
        $normalized = ($displayName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        $candidateId = if ($mcpAliases.ContainsKey($normalized)) {
            [string]$mcpAliases[$normalized]
        } elseif ($mcpAliases.ContainsKey($package.Name.ToLowerInvariant())) {
            [string]$mcpAliases[$package.Name.ToLowerInvariant()]
        } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($candidateId) -and $candidateId -in $codexDirect) {
            $installState = if ($codexPluginSnapshot.available -and
                $codexPluginSnapshot.states.ContainsKey($candidateId)) {
                [string]$codexPluginSnapshot.states[$candidateId]
            } else { 'unknown' }
            switch ($installState) {
                'installed' {
                    Add-DriftResult FAIL 'mcp' "codex-remote-and-direct-duplicate:$candidateId" `
                        'Codex has both a direct MCP registration and an installed remote connector package' `
                        'codex' @($package.FullName, $codexConfigPath, $CodexPluginStatePath)
                }
                'enabled' {
                    Add-DriftResult FAIL 'mcp' "codex-remote-and-direct-duplicate:$candidateId" `
                        'Codex has both a direct MCP registration and an enabled remote connector package' `
                        'codex' @($package.FullName, $codexConfigPath, $CodexPluginStatePath)
                }
                'uninstalled' {
                    Add-DriftResult PASS 'mcp' "codex-remote-and-direct-duplicate:$candidateId" `
                        'direct MCP registration is canonical; retained remote-package cache is uninstalled per authoritative state' `
                        'codex' @($package.FullName, $codexConfigPath, $CodexPluginStatePath)
                }
                'not-installed' {
                    Add-DriftResult PASS 'mcp' "codex-remote-and-direct-duplicate:$candidateId" `
                        'direct MCP registration is canonical; retained remote-package cache is not installed per authoritative state' `
                        'codex' @($package.FullName, $codexConfigPath, $CodexPluginStatePath)
                }
                default {
                    $reason = if ($codexPluginSnapshot.available) {
                        'authoritative plugin-state snapshot has no state for this package'
                    } else { $codexPluginSnapshot.reason }
                    Add-DriftResult WARN 'mcp' "codex-remote-and-direct-duplicate:$candidateId" `
                        "retained remote-package cache cannot establish an active duplicate: $reason" `
                        'codex' @($package.FullName, $codexConfigPath, $CodexPluginStatePath)
                }
            }
        }
    }
}

# Registered and host-native worktrees are report-only discoveries here. This
# validator never removes, moves, prunes, or checks out a worktree.
if (-not $SkipRepositoryScan -and (Test-Path -LiteralPath $ReposRoot -PathType Container)) {
    $repositoryRoots = @(
        Get-ChildItem -LiteralPath $ReposRoot -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') -PathType Container }
    )
    foreach ($repository in $repositoryRoots) {
        $porcelain = @(& git -C $repository.FullName worktree list --porcelain 2>$null)
        if ($LASTEXITCODE -ne 0) { continue }
        $current = $null
        foreach ($line in $porcelain + @('')) {
            if ($line -match '^worktree\s+(?<path>.+)$') {
                if ($current) { $worktreeStates.Add([pscustomobject]$current) }
                $current = [ordered]@{
                    repository = Normalize-FullPath $repository.FullName
                    path = Normalize-FullPath $Matches.path
                    head = ''
                    branch = ''
                    registered = $true
                    approvedRoot = $false
                    dirty = $false
                    status = ''
                }
            } elseif ($current -and $line -match '^HEAD\s+(?<head>.+)$') {
                $current.head = $Matches.head
            } elseif ($current -and $line -match '^branch\s+(?<branch>.+)$') {
                $current.branch = $Matches.branch
            } elseif ($current -and [string]::IsNullOrWhiteSpace($line)) {
                $current.approvedRoot = Test-PathWithin -Path $current.path -Root $WorktreeRoot
                if (-not $current.path.Equals(
                    (Normalize-FullPath $repository.FullName),
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                    $status = @(& git -C $current.path status --porcelain=v1 --branch 2>$null)
                    $current.status = $status -join "`n"
                    $current.dirty = @($status | Where-Object {
                        $_ -notmatch '^##'
                    }).Count -gt 0
                }
                $worktreeStates.Add([pscustomobject]$current)
                $current = $null
            }
        }
    }
    $deduplicatedWorktreeStates = New-Object System.Collections.Generic.List[object]
    foreach ($worktree in @($worktreeStates.ToArray() | Sort-Object path -Unique)) {
        $deduplicatedWorktreeStates.Add($worktree)
    }
    $worktreeStates = $deduplicatedWorktreeStates
    foreach ($worktree in @($worktreeStates.ToArray())) {
        $isPrimary = $worktree.path.Equals(
            $worktree.repository,
            [StringComparison]::OrdinalIgnoreCase
        )
        if (-not $isPrimary -and -not $worktree.approvedRoot) {
            $wip = if ($worktree.dirty) { 'dirty protected WIP' } else { 'clean' }
            Add-DriftResult FAIL 'worktree' "registered-worktree-outside-approved-root:$($worktree.path)" `
                "registered secondary worktree is outside C:\wt ($wip)" `
                '' @($worktree.path, $worktree.repository)
        }
    }
}

$nativeWorktreeRoots = @(
    (Join-Path $UserProfilePath '.grok\worktrees'),
    (Join-Path $UserProfilePath '.cursor\worktrees'),
    (Join-Path $UserProfilePath '.cline\worktrees'),
    (Join-Path $UserProfilePath '.local\share\opencode\worktree')
)
foreach ($nativeRoot in $nativeWorktreeRoots) {
    if (-not (Test-Path -LiteralPath $nativeRoot -PathType Container)) { continue }
    $gitMarkers = @(
        Get-ChildItem -LiteralPath $nativeRoot -Force -Recurse -Depth 5 -ErrorAction SilentlyContinue |
            Where-Object Name -eq '.git'
    )
    foreach ($marker in $gitMarkers) {
        $repoPath = Normalize-FullPath (Split-Path -Parent $marker.FullName)
        $status = @(& git -C $repoPath status --porcelain=v1 --branch 2>$null)
        if ($LASTEXITCODE -ne 0) { continue }
        $dirty = @($status | Where-Object { $_ -notmatch '^##' }).Count -gt 0
        $worktreeStates.Add([pscustomobject]@{
            repository = ''
            path = $repoPath
            head = ''
            branch = if ($status.Count -gt 0) { [string]$status[0] } else { '' }
            registered = $false
            approvedRoot = $false
            dirty = $dirty
            status = $status -join "`n"
        })
        $wip = if ($dirty) { 'dirty protected WIP' } else { 'clean' }
        Add-DriftResult FAIL 'worktree' "native-worktree-outside-approved-root:$repoPath" `
            "standalone agent-created repository exists below a prohibited native worktree root ($wip)" `
            '' @($repoPath, $nativeRoot)
    }
}

# Runtime inventory distinguishes normal agent/Cowork/LSP processes from
# actual local MCP workers. Normal autostart runtimes are not drift.
try {
    $allProcesses = if (-not [string]::IsNullOrWhiteSpace($ProcessSnapshotPath)) {
        @((Get-Content -LiteralPath $ProcessSnapshotPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop).processes)
    } else {
        @(Get-CimInstance Win32_Process -ErrorAction Stop)
    }
    $candidateProcesses = @($allProcesses | Where-Object {
        [int]$_.ProcessId -ne $PID -and (
            $_.Name -match '^(node|node\.exe|python|python\.exe|pythonw\.exe|npx|npx\.cmd|uvx|uvx\.exe)$' -or
            $_.CommandLine -match '(?i)claude|codex|qwen|opencode|gemini|hermes|copilot|antigravity|grok|warp|cline|qoder|cursor|devin|factory|windsurf'
        )
    })
    foreach ($process in $candidateProcesses) {
        $commandLine = [string]$process.CommandLine
        $workingSetBytes = [uint64](Get-PropertyValue $process 'WorkingSetSize' 0)
        $classification = if ($commandLine -match '(?i)playwright-mcp|chrome-devtools-mcp|brave-search-mcp|context7-mcp|firecrawl-mcp|repocontext.+mcp') {
            'local-mcp-worker'
        } elseif ($commandLine -match '(?i)cowork|language-server|typescript-language-server|pyright|node_repl|codex|claude|qwen|opencode|gemini|hermes|copilot|antigravity|grok|warp|cline|qoder') {
            'agent-runtime'
        } else {
            'unclassified-runtime'
        }
        $processStates.Add([pscustomobject]@{
            processId = [int]$process.ProcessId
            parentProcessId = [int]$process.ParentProcessId
            name = [string]$process.Name
            classification = $classification
            workingSetMb = [math]::Round($workingSetBytes / 1MB, 1)
            commandLine = Protect-ProcessCommandLine -CommandLine $commandLine
        })
    }

    # Deployment freshness on disk does not prove that an already-running host
    # loaded those bytes. Version-pinned plugin cache paths in process command
    # lines provide deterministic restart-required evidence.
    foreach ($freshnessRule in @(
        Get-PropertyValue (
            Get-PropertyValue $runtimePolicy 'sessionFreshness' $null
        ) 'versionedCapabilities' @()
    )) {
        $capabilityId = [string](Get-PropertyValue $freshnessRule 'capabilityId' '')
        $capability = @($capabilityRegistry.capabilities |
            Where-Object id -eq $capabilityId)
        if ($capability.Count -ne 1) { continue }
        $source = Resolve-RegistryOwnedPath ([string]$capability[0].canonicalSource)
        $canonicalVersion = ''
        foreach ($manifestPath in @(
            Get-PropertyValue $freshnessRule 'manifestPaths' @()
        )) {
            $manifest = Read-JsonFile -Path (Join-Path $source ([string]$manifestPath))
            $version = [string](Get-PropertyValue $manifest 'version' '')
            if (-not [string]::IsNullOrWhiteSpace($version)) {
                $canonicalVersion = $version
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($canonicalVersion)) {
            Add-DriftResult FAIL 'runtime' "runtime-version-unresolved:${capabilityId}" `
                'canonical capability version could not be resolved from its registered manifests'
            continue
        }

        $escapedCapabilityId = [regex]::Escape($capabilityId)
        $versionPattern = "(?i)[\\/]$escapedCapabilityId[\\/](?<version>[0-9]+\.[0-9]+\.[0-9]+(?:[-+][^\\/\s`"]+)?)"
        $matchingSessions = @()
        foreach ($process in $candidateProcesses) {
            $commandLine = [string]$process.CommandLine
            $match = [regex]::Match($commandLine, $versionPattern)
            if (-not $match.Success) { continue }
            $loadedVersion = $match.Groups['version'].Value
            $hostId = switch -Regex ($commandLine) {
                '(?i)[\\/]\.claude[\\/]' { 'claude'; break }
                '(?i)[\\/]\.codex[\\/]' { 'codex'; break }
                '(?i)[\\/]\.qoder[\\/]' { 'qoder'; break }
                '(?i)[\\/]\.grok[\\/]' { 'grok'; break }
                default { 'unknown' }
            }
            $isCurrent = $loadedVersion -eq $canonicalVersion
            $state = [pscustomobject]@{
                capabilityId = $capabilityId
                hostId = $hostId
                processId = [int]$process.ProcessId
                loadedVersion = $loadedVersion
                canonicalVersion = $canonicalVersion
                current = $isCurrent
                restartRequired = -not $isCurrent
            }
            $runtimeSessionStates.Add($state)
            $matchingSessions += $state
        }
        $staleSessions = @($matchingSessions | Where-Object { -not $_.current })
        if ($staleSessions.Count -gt 0) {
            foreach ($session in $staleSessions) {
                Add-DriftResult WARN 'runtime' `
                    "stale-loaded-capability:$($session.hostId):${capabilityId}:$($session.processId)" `
                    "running session loaded $($session.loadedVersion), canonical is $canonicalVersion; restart that host before claiming runtime parity" `
                    $session.hostId
            }
        } else {
            Add-DriftResult PASS 'runtime' "stale-loaded-capability:${capabilityId}" `
                "no running version-pinned session was found below canonical version $canonicalVersion"
        }
    }

    # Resource budgets are intentionally advisory and aggregate evidence only.
    # They never auto-terminate processes because ownership must be traced first.
    foreach ($budget in @(Get-PropertyValue $runtimePolicy 'resourceBudgets' @())) {
        $budgetId = [string](Get-PropertyValue $budget 'id' '')
        $pattern = [string](Get-PropertyValue $budget 'commandLinePattern' '')
        if ([string]::IsNullOrWhiteSpace($budgetId) -or
            [string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }
        $members = @($allProcesses | Where-Object {
            [int]$_.ProcessId -ne $PID -and
            [string]$_.CommandLine -match $pattern
        })
        $workingSetMb = [math]::Round(((
            $members | ForEach-Object {
                [uint64](Get-PropertyValue $_ 'WorkingSetSize' 0)
            } | Measure-Object -Sum
        ).Sum) / 1MB, 1)
        $warningWorkingSetMb = [double](
            Get-PropertyValue $budget 'warningWorkingSetMb' 0
        )
        $warningProcessCount = [int](
            Get-PropertyValue $budget 'warningProcessCount' 0
        )
        $overMemory = $warningWorkingSetMb -gt 0 -and
            $workingSetMb -gt $warningWorkingSetMb
        $overCount = $warningProcessCount -gt 0 -and
            $members.Count -gt $warningProcessCount
        $runtimeResourceGroups.Add([pscustomobject]@{
            id = $budgetId
            processCount = $members.Count
            workingSetMb = $workingSetMb
            warningProcessCount = $warningProcessCount
            warningWorkingSetMb = $warningWorkingSetMb
            overBudget = $overMemory -or $overCount
        })
        $status = if ($overMemory -or $overCount) { 'WARN' } else { 'PASS' }
        Add-DriftResult $status 'runtime' "resource-budget:${budgetId}" `
            "$($members.Count)/$warningProcessCount processes; $workingSetMb/$warningWorkingSetMb MB working set; observation only, auto-termination disabled"
    }
    $processById = @{}
    foreach ($process in $allProcesses) {
        $processById[[int]$process.ProcessId] = $process
    }
    $mcpPattern = '(?i)playwright-mcp|chrome-devtools-mcp|brave-search-mcp|context7-mcp|firecrawl-mcp|repocontext.+mcp'
    $mcpProcesses = @($allProcesses | Where-Object {
        [int]$_.ProcessId -ne $PID -and
        [string]$_.CommandLine -match $mcpPattern
    })
    $rootIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($mcpProcess in $mcpProcesses) {
        $highest = $mcpProcess
        $ancestorId = [int]$mcpProcess.ParentProcessId
        while ($processById.ContainsKey($ancestorId)) {
            $ancestor = $processById[$ancestorId]
            if ([string]$ancestor.CommandLine -match $mcpPattern) {
                $highest = $ancestor
            }
            $ancestorId = [int]$ancestor.ParentProcessId
        }
        [void]$rootIds.Add([int]$highest.ProcessId)
    }
    foreach ($rootId in $rootIds) {
        $root = $processById[$rootId]
        $descendantIds = New-Object System.Collections.Generic.HashSet[int]
        [void]$descendantIds.Add($rootId)
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($process in $allProcesses) {
                if ($descendantIds.Contains([int]$process.ParentProcessId) -and
                    -not $descendantIds.Contains([int]$process.ProcessId)) {
                    [void]$descendantIds.Add([int]$process.ProcessId)
                    $changed = $true
                }
            }
        }
        $ownerHostId = ''
        $ancestorId = [int]$root.ParentProcessId
        while ($processById.ContainsKey($ancestorId)) {
            $ancestor = $processById[$ancestorId]
            foreach ($agent in $agents) {
                $registeredExecutable = [string]$agent.executable
                if ([string]::IsNullOrWhiteSpace($registeredExecutable)) {
                    continue
                }
                $registeredName = [IO.Path]::GetFileName($registeredExecutable)
                $actualExecutable = [string](
                    Get-PropertyValue $ancestor 'ExecutablePath' ''
                )
                if (
                    (-not [string]::IsNullOrWhiteSpace($actualExecutable) -and
                        (Normalize-FullPath $actualExecutable).Equals(
                            (Normalize-FullPath $registeredExecutable),
                            [StringComparison]::OrdinalIgnoreCase
                        )) -or
                    ([string]$ancestor.Name).Equals(
                        $registeredName,
                        [StringComparison]::OrdinalIgnoreCase
                    )
                ) {
                    $ownerHostId = [string]$agent.id
                    break
                }
            }
            if ($ownerHostId) { break }
            $ancestorId = [int]$ancestor.ParentProcessId
        }
        $rootCommand = [string]$root.CommandLine
        $mcpId = switch -Regex ($rootCommand) {
            'chrome-devtools-mcp' { 'chrome-devtools'; break }
            'playwright-mcp' { 'playwright'; break }
            'brave-search-mcp' { 'brave-search'; break }
            'context7-mcp' { 'context7'; break }
            'firecrawl-mcp' { 'firecrawl'; break }
            'repocontext.+mcp' { 'repocontext'; break }
            default { 'unknown-local-mcp' }
        }
        $runtimeTrees.Add([pscustomobject]@{
            rootProcessId = $rootId
            ownerHostId = $ownerHostId
            mcpId = $mcpId
            processIds = @($descendantIds | Sort-Object)
            processCount = $descendantIds.Count
            commandLine = Protect-ProcessCommandLine -CommandLine $rootCommand
        })
    }
    if ($runtimeTrees.Count -gt 0) {
        $workerCount = [int]((
            $runtimeTrees.ToArray() |
                Measure-Object -Property processCount -Sum
        ).Sum)
        Add-DriftResult WARN 'runtime' 'local-mcp-workers-running' `
            "$($runtimeTrees.Count) logical local MCP runtime tree(s) own $workerCount process(es)"
    } else {
        Add-DriftResult PASS 'runtime' 'local-mcp-workers-running' `
            'no known local MCP worker process is running'
    }
} catch {
    Add-DriftResult WARN 'runtime' 'process-inventory-unavailable' $_.Exception.Message
}

$summary = [ordered]@{
    pass = @($results.ToArray() | Where-Object status -eq 'PASS').Count
    warn = @($results.ToArray() | Where-Object status -eq 'WARN').Count
    fail = @($results.ToArray() | Where-Object status -eq 'FAIL').Count
}
$inventory = [ordered]@{
    generatedAt = [DateTimeOffset]::Now.ToString('o')
    registryRoot = $RegistryRoot
    userProfile = $UserProfilePath
    agents = @($agents | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            name = [string]$_.name
            version = [string]$_.version
            status = [string]$_.status
            executable = [string](Get-PropertyValue $_ 'executable' '')
        }
    })
    discoveryRoots = @($discoveryRoots.ToArray())
    plugins = @($pluginStates.ToArray())
    skills = @($skillRecords.ToArray())
    canonicalSkills = @($canonicalSkillRecords.ToArray())
    mcpConfigurations = @($mcpStates.ToArray())
    worktrees = @($worktreeStates.ToArray())
    processes = @($processStates.ToArray())
    runtimeTrees = @($runtimeTrees.ToArray())
    runtimeSessions = @($runtimeSessionStates.ToArray())
    runtimeResourceGroups = @($runtimeResourceGroups.ToArray())
    reviewerExecutionBroker = $reviewerBrokerState
}
$output = [ordered]@{
    schemaVersion = 1
    summary = $summary
    inventory = $inventory
    results = @($results.ToArray())
}
$serialized = $output | ConvertTo-Json -Depth 12

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportParent = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportParent) -and
        -not (Test-Path -LiteralPath $reportParent -PathType Container)) {
        New-Item -ItemType Directory -Path $reportParent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $ReportPath,
        $serialized + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

if ($Json) {
    Write-Output $serialized
} else {
    $results | Sort-Object status, category, hostId, check |
        Format-Table status, category, hostId, check, detail -Wrap -AutoSize
    Write-Output "Inventory: agents=$($inventory.agents.Count) roots=$($inventory.discoveryRoots.Count) plugins=$($inventory.plugins.Count) skills=$($inventory.skills.Count) MCP-configs=$($inventory.mcpConfigurations.Count) worktrees=$($inventory.worktrees.Count) processes=$($inventory.processes.Count)"
    Write-Output "Summary: pass=$($summary.pass) warn=$($summary.warn) fail=$($summary.fail)"
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        Write-Output "Report: $ReportPath"
    }
}

if ($summary.fail -gt 0) { exit 1 }
exit 0
