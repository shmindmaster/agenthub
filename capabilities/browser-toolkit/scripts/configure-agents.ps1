[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [switch]$SkipTokenPlan,
    [switch]$SkipSkills,
    [ValidateSet('Shared', 'Isolated')]
    [string]$BrowserMode = 'Shared',
    [string]$RollbackFrom
)

$ErrorActionPreference = 'Stop'
$toolkitRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path (Join-Path $env:LOCALAPPDATA 'browser-toolkit\backups') $timestamp
$manifest = [Collections.Generic.List[object]]::new()
$homePath = [Environment]::GetFolderPath('UserProfile')

function Get-ObjectProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    return $Object.PSObject.Properties[$Name]
}

function Merge-Value {
    param([object]$Base, [object]$Overlay)
    if ($null -eq $Base) { return $Overlay }
    if ($null -eq $Overlay) { return $Base }

    if ($Base -is [Collections.IDictionary] -or $Base -is [pscustomobject]) {
        if (-not ($Overlay -is [Collections.IDictionary] -or $Overlay -is [pscustomobject])) {
            return $Overlay
        }
        $result = [ordered]@{}
        foreach ($property in $Base.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }
        foreach ($property in $Overlay.PSObject.Properties) {
            if ($result.Contains($property.Name)) {
                $result[$property.Name] = Merge-Value $result[$property.Name] $property.Value
            } else {
                $result[$property.Name] = $property.Value
            }
        }
        return [pscustomobject]$result
    }

    if ($Base -is [array] -and $Overlay -is [array]) {
        $objectsWithIds = @($Base + $Overlay | Where-Object {
            $_ -is [pscustomobject] -and $null -ne $_.PSObject.Properties['id']
        })
        if ($objectsWithIds.Count -eq ($Base.Count + $Overlay.Count) -and $objectsWithIds.Count -gt 0) {
            $byId = [ordered]@{}
            foreach ($item in $Base) { $byId[[string]$item.id] = $item }
            foreach ($item in $Overlay) {
                $key = [string]$item.id
                $byId[$key] = if ($byId.Contains($key)) { Merge-Value $byId[$key] $item } else { $item }
            }
            return ,@($byId.Values)
        }
        return ,@($Overlay)
    }
    return $Overlay
}

function Set-BrowserPort {
    param([object]$Value, [int]$Port)
    if ($Value -is [string]) {
        return $Value -replace 'http://127\.0\.0\.1:\d+', "http://127.0.0.1:$Port"
    }
    if ($Value -is [array]) {
        return ,@($Value | ForEach-Object { Set-BrowserPort $_ $Port })
    }
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            $property.Value = Set-BrowserPort $property.Value $Port
        }
    }
    return $Value
}

function Add-Backup {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $entry = [ordered]@{ path = $fullPath; existed = Test-Path -LiteralPath $fullPath; backup = $null; kind = 'file' }
    if ($entry.existed) {
        $leaf = Split-Path -Leaf $fullPath
        $safeParent = ((Split-Path -Parent $fullPath) -replace '[:\\/\s]+', '_').Trim('_')
        $destination = Join-Path $backupRoot "$safeParent-$leaf"
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $fullPath -Destination $destination
        $entry.backup = $destination
    }
    $manifest.Add([pscustomobject]$entry)
}

function Merge-JsonFile {
    param([string]$Target, [string]$Fragment, [int]$BrowserPort = 9333)
    Write-Host "MERGE $Target <= $Fragment"
    if (-not $Apply) { return }
    Add-Backup $Target
    $base = if (Test-Path -LiteralPath $Target) {
        Get-Content -LiteralPath $Target -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }
    $overlay = Get-Content -LiteralPath $Fragment -Raw | ConvertFrom-Json
    $overlay = Set-BrowserPort $overlay $BrowserPort
    $merged = Merge-Value $base $overlay
    New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
    $temporary = "$Target.browser-toolkit.tmp"
    $merged | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Target -Force
}

function Remove-ToolkitQwenSchemaArtifact {
    param([string]$Target, [int]$BrowserPort)
    if (-not $Apply -or -not (Test-Path -LiteralPath $Target)) { return }
    $settings = Get-Content -LiteralPath $Target -Raw | ConvertFrom-Json
    if ($settings.modelProviders.openai) {
        $settings.modelProviders.openai = @($settings.modelProviders.openai | Where-Object { $_.id -ne 'qwen-token-plan' })
        foreach ($modelProvider in $settings.modelProviders.openai) {
            if ($modelProvider.baseUrl -eq 'https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1') {
                $modelProvider.envKey = 'QWEN_API_KEY'
            }
        }
    }
    if ($settings.model -is [string]) {
        $name = ([string]$settings.model).Split('/')[-1]
        $settings.model = [pscustomobject]@{ name = $name }
    }
    $allowed = @($settings.mcp.allowed)
    if ('chrome-devtools' -notin $allowed) { $allowed += 'chrome-devtools' }
    $settings.mcp.allowed = [object[]]@($allowed | Select-Object -Unique)
    $settings.mcpServers.'chrome-devtools'.args = [object[]]@(
        '-y',
        'chrome-devtools-mcp@1.6.0',
        "--browser-url=http://127.0.0.1:$BrowserPort",
        '--no-usage-statistics',
        '--no-performance-crux',
        '--redact-network-headers'
    )
    $temporary = "$Target.browser-toolkit.normalize.tmp"
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Target -Force
}

function Normalize-ChromeMcpCommand {
    param(
        [string]$Target,
        [ValidateSet('Claude', 'OpenCode')]
        [string]$AgentHost,
        [int]$BrowserPort
    )
    if (-not $Apply -or -not (Test-Path -LiteralPath $Target)) { return }
    $settings = Get-Content -LiteralPath $Target -Raw | ConvertFrom-Json
    $args = [object[]]@(
        '-y',
        'chrome-devtools-mcp@1.6.0',
        "--browser-url=http://127.0.0.1:$BrowserPort",
        '--no-usage-statistics',
        '--no-performance-crux',
        '--redact-network-headers'
    )
    if ($AgentHost -eq 'Claude') {
        $settings.mcpServers.'chrome-devtools'.args = $args
    } else {
        $settings.mcp.'chrome-devtools'.command = [object[]]@('npx') + $args
        $legacyProvider = $settings.provider.PSObject.Properties['bailian-token-plan-personal']
        if ($legacyProvider -and
            $legacyProvider.Value.options.baseURL -eq 'https://token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic/v1') {
            $settings.provider.PSObject.Properties.Remove('bailian-token-plan-personal')
        }
    }
    $temporary = "$Target.browser-toolkit.normalize.tmp"
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Target -Force
}

function Add-SkillJunction {
    param([string]$TargetRoot, [string]$SkillSource)
    $name = Split-Path -Leaf $SkillSource
    $target = Join-Path $TargetRoot $name
    Write-Host "LINK $target => $SkillSource"
    if (-not $Apply) { return }
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    if (Test-Path -LiteralPath $target) {
        $item = Get-Item -LiteralPath $target -Force
        if ($item.LinkType -eq 'Junction' -and [IO.Path]::GetFullPath($item.Target) -eq [IO.Path]::GetFullPath($SkillSource)) {
            return
        }
        throw "Skill target already exists and is not the expected junction: $target"
    }
    New-Item -ItemType Junction -Path $target -Target $SkillSource | Out-Null
    $manifest.Add([pscustomobject]@{ path = $target; existed = $false; backup = $null; kind = 'junction' })
}

function Remove-ObsoleteToolkitSkillJunction {
    param([string]$TargetRoot, [string]$Name)
    $target = Join-Path $TargetRoot $Name
    if (-not (Test-Path -LiteralPath $target)) { return }
    $item = Get-Item -LiteralPath $target -Force
    $expectedTarget = Join-Path (Join-Path $toolkitRoot 'skills') $Name
    $actualTarget = [string]$item.Target
    if ($item.LinkType -ne 'Junction' -or
        -not [IO.Path]::GetFullPath($actualTarget).Equals([IO.Path]::GetFullPath($expectedTarget), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an obsolete skill path not owned by this toolkit: $target"
    }
    Write-Host "REMOVE OBSOLETE LINK $target"
    if ($Apply) { Remove-Item -LiteralPath $target -Force }
}

function Restore-Backup {
    param([string]$Directory)
    $manifestPath = Join-Path $Directory 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Backup manifest not found: $manifestPath" }
    $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($entry in @($entries)) {
        $target = [IO.Path]::GetFullPath([string]$entry.path)
        if ($entry.existed) {
            if (-not $entry.backup -or -not (Test-Path -LiteralPath $entry.backup)) {
                throw "Missing backup for $target"
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $entry.backup -Destination $target -Force
            Write-Host "RESTORED $target"
        } elseif (Test-Path -LiteralPath $target) {
            $item = Get-Item -LiteralPath $target -Force
            if ($entry.kind -eq 'junction' -and $item.LinkType -ne 'Junction') {
                throw "Refusing to remove non-junction rollback target: $target"
            }
            Remove-Item -LiteralPath $target -Force
            Write-Host "REMOVED CREATED TARGET $target"
        }
    }
}

if ($RollbackFrom) {
    Restore-Backup ([IO.Path]::GetFullPath($RollbackFrom))
    return
}

Write-Host ($(if ($Apply) { 'APPLY MODE' } else { 'DRY RUN — pass -Apply to write' }))
Write-Host "BROWSER MODE $BrowserMode"

$browserPorts = if ($BrowserMode -eq 'Isolated') {
    @{
        claude = 9341
        qwen = 9342
        opencode = 9343
        hermes = 9344
    }
} else {
    @{
        claude = 9333
        qwen = 9333
        opencode = 9333
        hermes = 9333
    }
}

$claudeSettings = Join-Path $homePath '.claude\settings.json'
$claudeMcp = Join-Path $homePath '.claude.json'
$qwenSettings = Join-Path $homePath '.qwen\settings.json'
$openCodeSettings = Join-Path $homePath '.config\opencode\opencode.json'

if (-not $SkipTokenPlan) {
    $canonicalToken = [Environment]::GetEnvironmentVariable('QWEN_API_KEY', 'User')
    $documentedAlias = [Environment]::GetEnvironmentVariable('BAILIAN_TOKEN_PLAN_API_KEY', 'User')
    $claudeToken = [Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'User')
    if (-not $canonicalToken -and -not $documentedAlias) {
        Write-Warning 'No Qwen Token Plan key is present. Configure QWEN_API_KEY before model validation.'
    } elseif (-not $canonicalToken) {
        Write-Host 'MIGRATE BAILIAN_TOKEN_PLAN_API_KEY to canonical QWEN_API_KEY without printing the value'
        if ($Apply) { [Environment]::SetEnvironmentVariable('QWEN_API_KEY', $documentedAlias, 'User') }
        $canonicalToken = $documentedAlias
    }
    if (-not $claudeToken -and $canonicalToken) {
        Write-Host 'SET Claude compatibility alias ANTHROPIC_AUTH_TOKEN from QWEN_API_KEY without printing the value'
        if ($Apply) { [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $canonicalToken, 'User') }
    } elseif ($claudeToken -and $canonicalToken -and $claudeToken -ne $canonicalToken) {
        Write-Warning 'ANTHROPIC_AUTH_TOKEN differs from QWEN_API_KEY. Claude will not use the canonical Qwen credential until the alias is explicitly synchronized.'
    }

    Merge-JsonFile $claudeSettings (Join-Path $toolkitRoot 'adapters\claude-code\settings.fragment.json') $browserPorts.claude
    Merge-JsonFile $qwenSettings (Join-Path $toolkitRoot 'adapters\qwen-code\settings.fragment.json') $browserPorts.qwen
    Remove-ToolkitQwenSchemaArtifact $qwenSettings $browserPorts.qwen
    Merge-JsonFile $openCodeSettings (Join-Path $toolkitRoot 'adapters\opencode\opencode.fragment.json') $browserPorts.opencode
    Normalize-ChromeMcpCommand $openCodeSettings -AgentHost OpenCode -BrowserPort $browserPorts.opencode
}

Merge-JsonFile $claudeMcp (Join-Path $toolkitRoot 'adapters\claude-code\mcp.fragment.json') $browserPorts.claude
Normalize-ChromeMcpCommand $claudeMcp -AgentHost Claude -BrowserPort $browserPorts.claude
if ($SkipTokenPlan) {
    $qwenMcpOnly = Join-Path $toolkitRoot 'mcp\chrome-devtools.json'
    Merge-JsonFile $qwenSettings $qwenMcpOnly $browserPorts.qwen
    Merge-JsonFile $openCodeSettings (Join-Path $toolkitRoot 'adapters\opencode\opencode.fragment.json') $browserPorts.opencode
}

Write-Host 'DEFER Cursor mutation to AgentHub full-profile reconciliation to preserve one configuration owner.'

$hermes = Get-Command hermes -ErrorAction SilentlyContinue
if ($hermes) {
    $hermesConfig = (& hermes config path).Trim()
    Write-Host "CONFIGURE Hermes at $hermesConfig"
    if ($Apply) {
        Add-Backup $hermesConfig
        if (-not [Environment]::GetEnvironmentVariable('QWEN_API_KEY', 'User') -and
            -not [Environment]::GetEnvironmentVariable('QWEN_API_KEY', 'Process')) {
            throw 'Refusing to remove the Hermes inline key until QWEN_API_KEY exists.'
        }
        $hermesPython = Join-Path (Split-Path -Parent $hermes.Source) 'python.exe'
        if (-not (Test-Path -LiteralPath $hermesPython)) {
            throw "Hermes Python runtime was not found: $hermesPython"
        }
        & $hermesPython (Join-Path $PSScriptRoot 'merge-hermes-config.py') --config $hermesConfig --port $browserPorts.hermes
        if ($LASTEXITCODE -ne 0) { throw 'Hermes configuration merge failed.' }
    }
} else {
    Write-Warning 'Hermes is not installed; adapter remains staged only.'
}

if (-not $SkipSkills) {
    $skillSources = Get-ChildItem -LiteralPath (Join-Path $toolkitRoot 'skills') -Directory |
        Where-Object Name -NotIn @('browser-audit', 'product-demo')
    $skillRoots = @(
        (Join-Path $homePath '.claude\skills'),
        (Join-Path $homePath '.qwen\skills'),
        (Join-Path $homePath '.config\opencode\skills'),
        (Join-Path $env:LOCALAPPDATA 'hermes\skills')
    )
    foreach ($root in $skillRoots) {
        foreach ($obsoleteName in @('browser-audit', 'product-demo')) {
            Remove-ObsoleteToolkitSkillJunction $root $obsoleteName
        }
        foreach ($source in $skillSources) { Add-SkillJunction $root $source.FullName }
    }
}

if ($Apply) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8
    Write-Host "Configuration complete. Backup manifest: $(Join-Path $backupRoot 'manifest.json')"
    Write-Host 'Cursor is reconciled by AgentHub full-profile deployment; no duplicate Cursor MCP configuration was written.'
} else {
    Write-Host 'Dry run complete. No files, variables, or links were changed.'
    Write-Host 'Cursor is reconciled by AgentHub full-profile deployment; this package does not independently mutate it.'
}
