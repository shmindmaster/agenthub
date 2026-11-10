#Requires -Version 5.1
<#
Pins two containment rules for this checkout:

- git ls-files contains no generated tree (node_modules, __pycache__,
  .pytest_cache, .cloud-render-chunks-*).
- the working tree has no .cloud-render-chunks-* directory and no
  mobile-development smoke-app node_modules. The kit's node_modules is a
  local Remotion install and is allowed.
- Cursor and Amp installers skip the same generated names, so a dirty
  package is not copied into a host.

Run: pwsh -NoProfile -File tests/Test-RepoScratch.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = [Collections.Generic.List[string]]::new()
$passed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$git = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $git) 'git is required to enumerate tracked files'
if ($git) {
    $raw = & $git.Source -C $repoRoot ls-files -z
    if ($LASTEXITCODE -ne 0) {
        Assert-True $false "git ls-files failed with exit $LASTEXITCODE"
    } else {
        $paths = @((($raw -join '') -split [string][char]0) | Where-Object { $_.Length -gt 0 })
        Assert-True ($paths.Count -gt 0) 'git ls-files returned no tracked files'
        $generated = @($paths | Where-Object {
            $_ -match '(^|/)(node_modules|__pycache__|\.pytest_cache)(/|$)' -or
            $_ -match '(^|/)\.cloud-render-chunks-'
        })
        Assert-True ($generated.Count -eq 0) ("tracked generated paths: " + ($generated -join ', '))
    }
}

$scratch = [Collections.Generic.List[string]]::new()
function Find-ChunkScratch([string]$Dir, [int]$Depth) {
    if ($Depth -gt 5) { return }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Dir -Force -Directory -ErrorAction SilentlyContinue)) {
        if ($entry.Name -like '.cloud-render-chunks-*') { $script:scratch.Add($entry.FullName) }
        if ($entry.Name -in @('.git', 'node_modules', '.repowise')) { continue }
        Find-ChunkScratch $entry.FullName ($Depth + 1)
    }
}
Find-ChunkScratch $repoRoot 0
Assert-True ($scratch.Count -eq 0) ("chunk scratch directories: " + ($scratch -join ', '))

$smokeModules = Join-Path $repoRoot 'packages\mobile-development\fixtures\smoke-app\node_modules'
Assert-True (-not (Test-Path -LiteralPath $smokeModules)) "smoke fixture must not keep node_modules: $smokeModules"

$cursor = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Install-CursorLocalPlugins.ps1'))
$amp = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\Install-AmpPlugins.py'))
foreach ($name in @('node_modules', '__pycache__', '.pytest_cache', 'logs', 'dist', 'coverage', '.cloud-render-chunks-')) {
    Assert-True ($cursor.Contains($name)) "Cursor installer does not name $name"
    Assert-True ($amp.Contains($name)) "Amp installer does not name $name"
}

foreach ($failure in $failures) { Write-Output "FAIL: $failure" }
Write-Output "RESULT: $passed passed, $($failures.Count) failed"
if ($failures.Count) { exit 1 }
