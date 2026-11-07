#Requires -Version 7
function Resolve-AgentHubPhysicalPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volume = [IO.Path]::GetPathRoot($full)
    $current = $volume
    foreach ($segment in $full.Substring($volume.Length).Split([char[]]@('\','/'), [StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $segment
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $target = $item.ResolveLinkTarget($true)
            if (-not $target) { throw "Unresolved package link: $current" }
            $current = $target.FullName
        }
    }
    return [IO.Path]::GetFullPath($current)
}

function Assert-AgentHubPluginPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Relative
    )
    if (-not $Relative.StartsWith('./') -or $Relative.Contains('\')) {
        throw "Expected a plugin-relative path starting with './': $Relative"
    }
    $physicalRoot = (Resolve-AgentHubPhysicalPath $Root).TrimEnd('\','/')
    $physical = Resolve-AgentHubPhysicalPath (Join-Path $Root $Relative)
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($physical -ne $physicalRoot -and -not $physical.StartsWith($physicalRoot + [IO.Path]::DirectorySeparatorChar, $comparison)) {
        throw "Package path escapes the plugin root: $Relative"
    }
}
