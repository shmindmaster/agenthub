#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('install','tools','call','prompts','prompt','batch')]
    [string]$Operation = 'tools',
    [string]$Name,
    [string]$ArgumentsFile,
    [string]$PlanFile,
    [string]$OutputFile,
    [ValidateRange(1,600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'

function Invoke-Hidden([string]$Executable, [string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new($Executable)
    foreach ($item in $Arguments) { $info.ArgumentList.Add($item) }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        # The research client owns its deadline and MCP child cleanup.
        $process.WaitForExit()
        return [pscustomobject]@{ Code=$process.ExitCode; Out=$stdout.Result; Err=$stderr.Result }
    } finally { $process.Dispose() }
}

$uv = (Get-Command uv -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if ($Operation -eq 'install') {
    $spec = (Get-Content (Join-Path $PSScriptRoot 'requirements.txt') -Raw -Encoding UTF8).Trim()
    $result = Invoke-Hidden $uv @('tool','install','--python','3.12',$spec)
} else {
    $location = Invoke-Hidden $uv @('tool','dir')
    if ($location.Code -ne 0) { throw 'uv tool directory could not be resolved.' }
    $environmentRoot = Join-Path $location.Out.Trim() 'arxiv-mcp-server'
    $relativePython = if ($IsWindows) { 'Scripts/python.exe' } else { 'bin/python' }
    $python = Join-Path $environmentRoot $relativePython
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw 'arXiv MCP is not installed. Run this launcher with -Operation install first.'
    }
    $clientArgs = @((Join-Path $PSScriptRoot 'arxiv_client.py'), $Operation, '--timeout', [string]$TimeoutSeconds)
    foreach ($pair in @(@('--name',$Name),@('--arguments-file',$ArgumentsFile),@('--plan-file',$PlanFile),@('--output-file',$OutputFile))) {
        if ($pair[1]) { $clientArgs += $pair }
    }
    $result = Invoke-Hidden $python $clientArgs
}
if ($result.Out) { [Console]::Out.Write($result.Out) }
if ($result.Err) { [Console]::Error.Write($result.Err) }
exit $result.Code
