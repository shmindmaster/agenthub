#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'packages\repowise'
$prior = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & python.exe -m unittest discover -s "$package\tests" -p 'test_bounded*.py' -v 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $prior
$output | ForEach-Object { Write-Host ([string]$_) }
$passed = $code -eq 0 -and (($output | Out-String) -match 'Ran [1-9][0-9]* tests')
if (-not $passed) { Write-Host 'RESULT: 1 failed, 0 passed'; exit 1 }
$tokens = $null; $errors = $null
$null = [Management.Automation.Language.Parser]::ParseFile(
    "$package\scripts\Invoke-RepoWiseBoundedIndex.ps1", [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | Write-Host; Write-Host 'RESULT: 1 failed, 1 passed'; exit 1 }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('bounded-admission-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
try {
    $lease = Join-Path $scratch 'lease.json'
    $params = @{ Workspace = $scratch; RepositoryRoot = $scratch; LeasePath = $lease
        OutputDirectory = (Join-Path $scratch 'output'); MinimumFreeGiB = 4 }
    $refused = $false
    try { & "$package\scripts\Invoke-RepoWiseBoundedIndex.ps1" @params -Deadline ([DateTimeOffset]::Now.AddSeconds(-1)) }
    catch { $refused = $true }
    if (-not $refused -or (Test-Path -LiteralPath $lease)) { throw 'Expired deadline admitted work.' }
    [IO.File]::WriteAllText($lease, 'synthetic foreign lease')
    $refused = $false
    try { & "$package\scripts\Invoke-RepoWiseBoundedIndex.ps1" @params -Deadline ([DateTimeOffset]::Now.AddSeconds(30)) }
    catch { $refused = $true }
    if (-not $refused -or [IO.File]::ReadAllText($lease) -ne 'synthetic foreign lease' -or
        (Test-Path -LiteralPath $params.OutputDirectory)) { throw 'Foreign lease boundary failed.' }
} finally {
    # This tree contains only the synthetic files created by this test.
    [IO.Directory]::Delete($scratch, $true)
}
Write-Host 'RESULT: 4 passed, 0 failed'
exit 0
