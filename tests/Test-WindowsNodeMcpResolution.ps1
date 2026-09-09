#Requires -Version 5.1
# Synthetic resolution tests. No executable is launched and no host config is changed.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts\Sync-AgentHub.ps1'), [ref]$null, [ref]$null)
foreach ($name in @('Resolve-WindowsNodeExecutable','Resolve-WindowsHiddenStdioEntry')) {
    $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    if (-not $node) { throw "Missing canonical function: $name" }
    . ([scriptblock]::Create($node.Extent.Text))
}
$saved = @{OS=$env:OS; ProgramFiles=$env:ProgramFiles; APPDATA=$env:APPDATA}
$passed = 0
function Assert([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
# Mock filesystem and command discovery at their boundary, using absolute synthetic paths.
$script:files = @{}
$script:commands = @()
function Test-Path { param($LiteralPath,$PathType) return $null -ne $LiteralPath -and $script:files.ContainsKey([string]$LiteralPath) }
function Get-Command { param($Name,$CommandType,$ErrorAction) return $script:commands }
try {
    $env:OS='Windows_NT'
    $env:ProgramFiles='C:\fixture\programs'
    $env:APPDATA='C:\fixture\roaming'
    $RuntimeDir='C:\fixture\runtime'
    $standard=Join-Path $env:ProgramFiles 'nodejs\node.exe'
    $managed='C:\fixture\mise\node\24.20.0\node.exe'
    $hide=Join-Path $RuntimeDir 'bin\Hide-Stdio.exe'
    $playwright=Join-Path $env:APPDATA 'npm\node_modules\@playwright\mcp\cli.js'
    $npm=Join-Path (Split-Path -Parent $managed) 'node_modules\npm\bin\npx-cli.js'
    $script:commands=@([pscustomobject]@{Source=$managed})
    $script:files=@{ $standard=$true; $managed=$true; $hide=$true; $playwright=$true; $npm=$true }
    Assert ((Resolve-WindowsNodeExecutable) -eq $standard) 'MSI Node remains preferred when installed'
    $script:files.Remove($standard)
    Assert ((Resolve-WindowsNodeExecutable) -eq $managed) 'managed Node resolves when MSI installation is absent'
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','@playwright/mcp@0.0.79','--extension','--port','1234');enabled=$false}
    Assert ($r.command -eq $hide -and ($r.args -join '|') -eq (@($managed,$playwright,'--extension','--port','1234') -join '|') -and $r.enabled -eq $false) 'Playwright launches directly with all flags and disabled startup retained'
    $script:files.Remove($playwright)
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','@playwright/mcp@0.0.79','--extension')}
    Assert ($r.command -eq $hide -and $r.args[1] -eq $npm -and $r.args[-1] -eq '--extension') 'missing global package uses npm beside the resolved Node'
    $script:files.Remove($npm)
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','uninstalled-package')}
    Assert ($r.command -eq 'npx') 'absent npm entry never creates a broken absolute launcher'
    $script:files.Remove($managed)
    Assert ($null -eq (Resolve-WindowsNodeExecutable)) 'unresolved Node stays absent'
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','@playwright/mcp')}
    Assert ($r.command -eq 'npx') 'missing interpreter does not cause a null-path exception'
    $script:files[$playwright]=$true
    $script:files[$managed]=$true
    $script:commands=@([pscustomobject]@{Source='relative-node.exe'},[pscustomobject]@{Source=$managed})
    Assert ((Resolve-WindowsNodeExecutable) -eq $managed) 'relative command candidates are rejected'
    $script:files.Remove($hide)
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','@playwright/mcp')}
    Assert ($r.command -eq 'npx') 'missing hidden launcher leaves the original command intact'
    $env:OS='non-windows'
    $r=Resolve-WindowsHiddenStdioEntry @{command='npx';args=@('-y','@playwright/mcp')}
    Assert ($r.command -eq 'npx') 'non-Windows behavior is unchanged'
    Write-Host "RESULT: $passed passed, 0 failed"
} finally {
    $env:OS=$saved.OS; $env:ProgramFiles=$saved.ProgramFiles; $env:APPDATA=$saved.APPDATA
}
