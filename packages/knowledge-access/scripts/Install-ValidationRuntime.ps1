#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is required for the local validation runtime.' }
$runtime = Join-Path $env:LOCALAPPDATA 'AgentHub\runtimes\knowledge-access'
$python = Join-Path $runtime 'Scripts\python.exe'
$uv = Get-Command uv -CommandType Application -ErrorAction Stop | Select-Object -First 1
$cursor = $runtime
while ($cursor) {
    if (Test-Path -LiteralPath $cursor) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Validation runtime cannot use linked directories.' }
    }
    $parent = Split-Path -Parent $cursor
    if ($parent -eq $cursor) { break }
    $cursor = $parent
}
if (Test-Path -LiteralPath $runtime) {
    if (-not (Test-Path -LiteralPath (Join-Path $runtime 'pyvenv.cfg'))) { throw 'Existing runtime directory is not a virtual environment; preserve it and investigate.' }
} else {
    & $uv.Source venv --python 3.13 $runtime
    if ($LASTEXITCODE -ne 0) { throw 'Validation virtual environment creation failed.' }
}
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Validation interpreter is missing.' }
& $uv.Source pip install --python $python -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Validation dependency installation failed.' }
& $python -I -c 'import yaml; from jsonschema import Draft202012Validator, FormatChecker'
if ($LASTEXITCODE -ne 0) { throw 'Validation runtime import check failed.' }
Write-Output $python
