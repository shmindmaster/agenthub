#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$test = Join-Path $PSScriptRoot 'test_client.py'
$python = $null
if (Get-Command uv -ErrorAction SilentlyContinue) {
    $toolRoot = (& uv tool dir).Trim()
    $relative = if ($IsWindows) { 'arxiv-mcp-server/Scripts/python.exe' } else { 'arxiv-mcp-server/bin/python' }
    $candidate = Join-Path $toolRoot $relative
    if (Test-Path -LiteralPath $candidate) { $python = $candidate }
}
if (-not $python) { $python = (Get-Command python -ErrorAction Stop).Source }
$start = [Diagnostics.ProcessStartInfo]::new($python)
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.ArgumentList.Add('-B')
$start.ArgumentList.Add($test)
$process = [Diagnostics.Process]::Start($start)
try {
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    Write-Output $stdout.Result
    Write-Output $stderr.Result
    if ($process.ExitCode -ne 0) { throw 'arXiv research client tests failed.' }
} finally { $process.Dispose() }
Write-Output 'PASS: arXiv research lifecycle and client tests.'
