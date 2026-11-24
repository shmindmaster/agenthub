#Requires -Version 7

function New-AgentHubPluginCleanup($HostId, $Plugin, $Kind, $Target, $Status = 'pending', $Detail = '') {
    [pscustomobject]@{ host=$HostId; plugin=$Plugin; kind=$Kind; target=$Target; status=$Status; detail=$Detail }
}

function Test-AgentHubPluginTree([string]$Root, [string]$Path) {
    try {
        $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        $full = [IO.Path]::GetFullPath($Path)
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if (-not $full.StartsWith($base + [IO.Path]::DirectorySeparatorChar, $comparison)) { return $false }
        $physical = Resolve-AgentHubPhysicalPath $full
        if (-not $physical.Equals($full, $comparison)) { return $false }
        $current = Get-Item -LiteralPath $full -Force
        while (-not $current.FullName.Equals($base, $comparison)) {
            if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
            $current = $current.Parent
        }
        return -not (Get-ChildItem -LiteralPath $full -Recurse -Force | Where-Object {
            $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        } | Select-Object -First 1)
    } catch { return $false }
}

function Read-AgentHubCleanupJson([string]$Path, [switch]$AsHashtable) {
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable:$AsHashtable
        }
    } catch { return $null }
}

function Get-AgentHubOldPluginVersions {
    param([string]$HostId, [string]$Plugin, [string]$Root, [string]$ActivePath,
        [string]$Version, [string[]]$RegisteredPaths = @(), [string]$Manifest = 'plugin.json')
    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or -not $ActivePath -or
        -not (Test-Path -LiteralPath $ActivePath -PathType Container) -or
        -not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $active = [IO.Path]::GetFullPath($ActivePath)
    if (-not (Test-AgentHubPluginTree $Root $active)) { return }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $references = @($RegisteredPaths | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_) }) + $active
    foreach ($item in Get-ChildItem -LiteralPath $Root -Directory -Force) {
        if ($item.Name -notmatch '^\d+\.\d+\.\d+$' -or $item.FullName -in $references -or [version]$item.Name -ge [version]$Version) { continue }
        $prefix = $item.FullName + [IO.Path]::DirectorySeparatorChar
        if ($references | Where-Object { $_.StartsWith($prefix, $comparison) }) { continue }
        if (-not (Test-AgentHubPluginTree $Root $item.FullName)) {
            New-AgentHubPluginCleanup $HostId $Plugin 'old-cache' $item.FullName 'unmanaged' 'Cache ownership could not be verified.'
            continue
        }
        $old = Read-AgentHubCleanupJson (Join-Path $item.FullName $Manifest)
        if ($old.name -eq $Plugin -and $old.version -eq $item.Name) {
            New-AgentHubPluginCleanup $HostId $Plugin 'old-cache' $item.FullName
        } else {
            New-AgentHubPluginCleanup $HostId $Plugin 'old-cache' $item.FullName 'unmanaged' 'Manifest differs from the cache identity.'
        }
    }
}

function Remove-AgentHubPluginTree([string]$Root, [string]$Path) {
    if (-not (Test-AgentHubPluginTree $Root $Path)) { throw 'Plugin cleanup path could not be verified.' }
    if ($IsWindows) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    } else {
        [IO.Directory]::Delete($Path, $true)
    }
    if (Test-Path -LiteralPath $Path) { throw 'Obsolete plugin copy is still present.' }
}

function Test-AgentHubPluginHostBusy([string]$HostId) {
    $processNames = switch ($HostId) {
        'claude' { 'claude'; 'cursor'; 'cursor-agent' }
        'cursor' { 'cursor'; 'cursor-agent' }
        'codex' { 'codex'; 'ChatGPT' }
        'copilot' { 'copilot'; 'Code'; 'Code - Insiders' }
        'factory' { 'droid' }
    }
    return [bool]($processNames -and (Get-Process -Name $processNames -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Get-AgentHubCopilotDirectEntries($Document, [string]$Plugin, [string]$RelativePath) {
    return @($Document['installedPlugins'] | Where-Object {
        $_ -and $_['name'] -eq $Plugin -and $_['source'] -is [System.Collections.IDictionary] -and $_['source']['source'] -eq 'github' -and
        $_['source']['repo'] -eq 'shmindmaster/agenthub' -and $_['source']['path'] -eq $RelativePath
    })
}

function Remove-AgentHubCopilotDirectRegistration([string]$Path, [string]$Plugin, [string]$RelativePath, [scriptblock]$Verify) {
    $original = [IO.File]::ReadAllText($Path)
    $data = ConvertFrom-Json -InputObject $original -AsHashtable
    $duplicate = @(Get-AgentHubCopilotDirectEntries $data $Plugin $RelativePath)
    if ($duplicate.Count -ne 1) { throw 'Expected one AgentHub direct Copilot registration.' }
    $data['installedPlugins'] = @($data['installedPlugins'] | Where-Object {
        -not [object]::ReferenceEquals($_, $duplicate[0])
    })
    $next = (ConvertTo-Json -InputObject $data -Depth 100 -WarningAction Stop) + [Environment]::NewLine
    # Copilot uninstall by bare name selects the live marketplace entry instead.
    # Replace the single owned direct record and restore it if CLI readback fails.
    $temp = Join-Path (Split-Path -Parent $Path) ('.agenthub-plugin-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, $next)
        if ([IO.File]::ReadAllText($Path) -cne $original) { throw 'Copilot configuration changed during cleanup.' }
        [IO.File]::Move($temp, $Path, $true)
        try {
            if (-not (& $Verify)) { throw 'Copilot registration cleanup did not verify.' }
        } catch {
            if ([IO.File]::ReadAllText($Path) -ceq $next) {
                [IO.File]::WriteAllText($temp, $original)
                [IO.File]::Move($temp, $Path, $true)
            }
            throw
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}
