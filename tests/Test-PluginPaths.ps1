#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/lib/PluginPaths.ps1')
$scratch = [IO.Directory]::CreateTempSubdirectory('agenthub-plugin-paths-')
try {
    $package = Join-Path $scratch.FullName 'package'
    $outside = Join-Path $scratch.FullName 'outside'
    [void][IO.Directory]::CreateDirectory((Join-Path $package 'skills/example'))
    [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $package 'skills/example/SKILL.md'), '# Synthetic')
    Assert-AgentHubPluginPath -Root $package -Relative './skills/example/SKILL.md'
    foreach ($relative in '../outside', 'skills/example', './skills/../../../outside') {
        $rejected = $false
        try { Assert-AgentHubPluginPath -Root $package -Relative $relative } catch { $rejected = $true }
        if (-not $rejected) { throw "Accepted invalid path: $relative" }
    }
    $link = Join-Path $package 'escape'
    $type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $type -Path $link -Target $outside | Out-Null
    $rejected = $false
    try { Assert-AgentHubPluginPath -Root $package -Relative './escape' } catch { $rejected = $true }
    if (-not $rejected) { throw 'Accepted an external link' }
    [IO.Directory]::Delete($link)
    Write-Host 'RESULT: 5 passed, 0 failed'
} finally {
    $resolved = (Get-Item -LiteralPath $scratch.FullName).FullName
    if ($resolved -eq $scratch.FullName -and (Split-Path -Parent $resolved) -eq $scratch.Parent.FullName) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
