#Requires -Version 5.1

function Assert-AgentHubSafeWritePath {
    <#
    .SYNOPSIS
    Returns a normalized write path after rejecting unsafe root-level targets.

    .DESCRIPTION
    AgentHub maintenance scripts may create paths that do not exist yet, so
    this guard deliberately normalizes with System.IO.Path rather than resolving
    the path against the filesystem. Drive roots, empty paths, and direct,
    unapproved children of C:\ are rejected before any write command is called.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Purpose,
        [string[]]$ApprovedTopLevelPath = @('C:\wt')
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Refusing to write ${Purpose}: the target path is empty."
    }

    try {
        $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
        $normalizedPath = [System.IO.Path]::GetFullPath($expandedPath)
    } catch {
        throw "Refusing to write ${Purpose}: '$Path' is not a valid path."
    }

    $pathRoot = [System.IO.Path]::GetPathRoot($normalizedPath)
    $trimmedPath = $normalizedPath.TrimEnd([char[]]@('\', '/'))
    $trimmedRoot = if ($pathRoot) { $pathRoot.TrimEnd([char[]]@('\', '/')) } else { '' }
    if ([string]::IsNullOrWhiteSpace($pathRoot) -or $trimmedPath -eq $trimmedRoot) {
        throw "Refusing to write ${Purpose}: '$normalizedPath' is a drive or share root."
    }

    if ($normalizedPath -match '^[cC]:\\[^\\/]+$') {
        $approved = @(
            foreach ($candidate in $ApprovedTopLevelPath) {
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                try {
                    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($candidate)).TrimEnd([char[]]@('\', '/'))
                } catch {
                    throw "Refusing to write ${Purpose}: approved top-level path '$candidate' is not valid."
                }
            }
        )
        if ($trimmedPath -notin $approved) {
            throw "Refusing to write ${Purpose}: '$normalizedPath' is an unapproved top-level C:\ target."
        }
    }

    return $normalizedPath
}
