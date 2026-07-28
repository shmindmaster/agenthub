#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PackagesRoot = "C:\Repos\shmindmaster\agenthub\packages\portfolio-plugins"
)

Get-ChildItem $PackagesRoot -Directory | ForEach-Object {
    $plugin = $_.Name
    Write-Host "=== $plugin ==="
    Get-ChildItem $_.FullName -Recurse -File | Where-Object { $_.Name -like '*mcp*' -or $_.Name -eq 'plugin.json' } | ForEach-Object {
        $rel = $_.FullName.Substring($_.FullName.IndexOf($plugin) + $plugin.Length + 1)
        Write-Host "  $rel"
    }
}
