[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$RegistryRoot = 'C:\Repos\agent-capabilities'
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $env:LOCALAPPDATA "AgentCapabilities\handoff-skill-backups\$timestamp"
$sourceRoots = @(
    Join-Path $RegistryRoot 'packages\handoff-plugins\plugins\product-demo-studio\skills'
    Join-Path $RegistryRoot 'packages\handoff-plugins\plugins\product-experience-engineering\skills'
)
$targetRoots = @(
    Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config\opencode\skills'
    Join-Path $env:LOCALAPPDATA 'hermes\skills'
)

Write-Host ($(if ($Apply) { 'APPLY MODE' } else { 'DRY RUN — pass -Apply to write' }))
foreach ($sourceRoot in $sourceRoots) {
    foreach ($source in Get-ChildItem -LiteralPath $sourceRoot -Directory) {
        foreach ($targetRoot in $targetRoots) {
            $target = Join-Path $targetRoot $source.Name
            Write-Host "SYNC $target <= $($source.FullName)"
            if (-not $Apply) { continue }

            if (Test-Path -LiteralPath $target) {
                $targetItem = Get-Item -LiteralPath $target -Force
                if ($targetItem.LinkType) {
                    throw "Refusing to overwrite linked skill target: $target"
                }
                $targetLabel = if ($targetRoot -match '\\opencode\\') { 'opencode' } else { 'hermes' }
                $backup = Join-Path $backupRoot ($targetLabel + '-' + $source.Name)
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                Copy-Item -LiteralPath $target -Destination $backup -Recurse
            } else {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }

            foreach ($item in Get-ChildItem -LiteralPath $source.FullName -Force) {
                Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
            }
        }
    }
}

if ($Apply) {
    Write-Host "Loose-skill synchronization complete. Backups: $backupRoot"
} else {
    Write-Host 'Dry run complete. Claude native plugins and Qwen extension junctions are managed separately.'
}
