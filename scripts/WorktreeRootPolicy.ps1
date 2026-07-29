#Requires -Version 5.1

function ConvertTo-AgentHubPolicyPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/').ToLowerInvariant()
}

function Get-AgentHubOrphanedWorktreeDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfiguredRoot,
        [hashtable]$KnownPaths = @{}
    )

    if (-not (Test-Path -LiteralPath $ConfiguredRoot -PathType Container)) {
        return @()
    }

    $knownNormalized = @{}
    foreach ($knownPath in @($KnownPaths.Keys)) {
        $knownNormalized[(ConvertTo-AgentHubPolicyPath -Path ([string]$knownPath))] = $true
    }

    $orphans = [System.Collections.Generic.List[string]]::new()
    foreach ($repositoryDirectory in @(Get-ChildItem -LiteralPath $ConfiguredRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($taskDirectory in @(Get-ChildItem -LiteralPath $repositoryDirectory.FullName -Directory -ErrorAction SilentlyContinue)) {
            $normalizedTaskPath = ConvertTo-AgentHubPolicyPath -Path $taskDirectory.FullName
            if ($knownNormalized.ContainsKey($normalizedTaskPath)) { continue }
            if (Test-Path -LiteralPath (Join-Path $taskDirectory.FullName '.git')) {
                $orphans.Add([System.IO.Path]::GetFullPath($taskDirectory.FullName))
            }
        }
    }
    return @($orphans.ToArray())
}
