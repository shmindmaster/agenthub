#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$syncPath = Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($syncPath, [ref]$null, [ref]$null)
$fnAst = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Remove-ManagedJunction'
    }, $true) | Select-Object -First 1

if (-not $fnAst) { throw 'Sync-AgentHub.ps1 does not define Remove-ManagedJunction.' }
. ([scriptblock]::Create($fnAst.Extent.Text))

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-junction-test-' + [guid]::NewGuid().ToString('N'))
$target = Join-Path $scratch 'target'
$junction = Join-Path $scratch 'junction'
$ordinary = Join-Path $scratch 'ordinary'

try {
    New-Item -ItemType Directory -Path $target, $ordinary -Force | Out-Null
    $marker = Join-Path $target 'preserved.txt'
    [IO.File]::WriteAllText($marker, 'preserve target')
    New-Item -ItemType Junction -Path $junction -Target $target | Out-Null

    Remove-ManagedJunction -Path $junction
    if (Test-Path -LiteralPath $junction) { throw 'Managed junction entry still exists.' }
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { throw 'Junction target was traversed or removed.' }

    $rejected = $false
    try { Remove-ManagedJunction -Path $ordinary } catch { $rejected = $true }
    if (-not $rejected) { throw 'Ordinary directory was not rejected.' }
    if (-not (Test-Path -LiteralPath $ordinary -PathType Container)) { throw 'Ordinary directory was changed.' }

    Write-Output 'PASS: managed junction removal preserves its target and rejects ordinary directories.'
} finally {
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
