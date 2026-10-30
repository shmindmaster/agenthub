#Requires -Version 5.1
# Exercise the actual validator retirement block with isolated package documents.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('retired-validation-' + [guid]::NewGuid().ToString('N'))
$pluginRoot = Join-Path $scratch 'packages'
$overlayRoot = Join-Path $scratch 'overlays/personal'
$overlayPackagesRoot = Join-Path $overlayRoot 'packages'
$null = New-Item -ItemType Directory -Path $pluginRoot,$overlayPackagesRoot -Force
function Save-Json($Path, $Value) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Fail([string]$Message) { $script:errors.Add($Message) }
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
try {
    # Extract complete AST statements rather than duplicate the production guard.
    # Parse the exact string that is sliced below: PowerShell 5.1 reads a
    # BOM-less UTF-8 file as ANSI, so a ParseFile AST has different offsets
    # than ReadAllText() whenever the file holds a multi-byte character.
    $source = [IO.File]::ReadAllText((Join-Path $root 'scripts/Validate-AgentHub.ps1'))
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Validator has parse errors' }
    $statements = @($ast.EndBlock.Statements)
    $first = @($statements | Where-Object { $_.Extent.Text -match '^\$retiredMcpIds\s*=' })
    $last = @($statements | Where-Object { $_.Extent.Text -match '^foreach\s*\(\$packageTree in \$mcpPackageRoots\)' })
    if ($first.Count -ne 1 -or $last.Count -ne 1) { throw 'Cannot locate complete production retirement validation block' }
    $guard = [scriptblock]::Create($source.Substring($first[0].Extent.StartOffset, $last[0].Extent.EndOffset - $first[0].Extent.StartOffset))
    $mcps = @{retiredMcpIds=@('chrome-devtools','chrome-devtools-isolated');retiredMcpPackages=@('chrome-devtools-mcp');migrationAliases=@{};mcpServers=@()}
    $public = Join-Path $pluginRoot 'fixture'
    $manifestPath = Join-Path $public '.codex-plugin/plugin.json'
    Save-Json $manifestPath @{name='fixture';mcpServers='./mcp.codex.json'}
    $document = Join-Path $public 'mcp.codex.json'
    Save-Json $document @{mcpServers=@{'owner-custom'=@{command='fixture.exe'}}}
    $script:errors = [Collections.Generic.List[string]]::new()
    . $guard
    if ($errors.Count) { throw 'Clean alternate MCP document rejected' }
    Write-Host 'PASS: clean alternate MCP document accepted'

    Save-Json $document @{mcpServers=@{'renamed-browser'=@{command='npx';args=@('-y','chrome-devtools-mcp@0.0.1')}}}
    $script:errors.Clear(); . $guard
    if (@($errors | Where-Object { $_ -like 'retired MCP package in plugin:*mcp.codex.json' }).Count -ne 1) { throw 'Alternate manifest-selected launcher bypassed retirement validation' }
    Write-Host 'PASS: alternate manifest-selected renamed retired launcher rejected'

    Save-Json $document @{mcpServers=@{}}
    Save-Json $manifestPath @{name='fixture';mcpServers=@{'chrome-devtools'=@{command='fixture.exe'}}}
    $script:errors.Clear(); . $guard
    if (@($errors | Where-Object { $_ -like 'retired MCP in plugin:*plugin.json' }).Count -ne 1) { throw 'Inline retired MCP bypassed retirement validation' }
    Write-Host 'PASS: inline retired MCP identity rejected'

    Save-Json $manifestPath @{name='fixture';mcpServers=@{}}
    $private = Join-Path $overlayPackagesRoot 'private-fixture'
    Save-Json (Join-Path $private 'plugin.json') @{name='private-fixture';mcpServers='./native-mcp.json'}
    Save-Json (Join-Path $private 'native-mcp.json') @{mcpServers=@{'renamed-private-browser'=@{command='npx';args=@('chrome-devtools-mcp')}}}
    $script:errors.Clear(); . $guard
    if (@($errors | Where-Object { $_ -like 'retired MCP package in plugin:*native-mcp.json' }).Count -ne 1) { throw 'Overlay alternate MCP launcher bypassed retirement validation' }
    Write-Host 'PASS: private overlay manifest-selected retired launcher rejected'
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
