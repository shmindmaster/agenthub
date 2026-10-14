#Requires -Version 5.1
<#
The dispatcher must list hosts and refuse the ones it cannot launch, without
starting any coding agent.

Run: pwsh -NoProfile -File tests\Test-CodingAgentDispatch.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script = Join-Path $repoRoot 'packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Invoke-Dispatcher {
    param([string[]]$ArgumentList)
    $out = Join-Path $env:TEMP ("cad-out-{0}.txt" -f ([guid]::NewGuid().ToString('n')))
    $err = Join-Path $env:TEMP ("cad-err-{0}.txt" -f ([guid]::NewGuid().ToString('n')))
    $argText = ($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
    $proc = Start-Process -FilePath (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source `
        -ArgumentList (@('-NoProfile', '-File', $script) + $ArgumentList) `
        -Wait -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $stdout = if (Test-Path $out) { [IO.File]::ReadAllText($out) } else { '' }
    $stderr = if (Test-Path $err) { [IO.File]::ReadAllText($err) } else { '' }
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Exit = $proc.ExitCode; Out = $stdout; Err = $stderr; Shown = $argText }
}

if (-not (Test-Path -LiteralPath $script)) {
    Write-Host "FAIL: dispatcher script is missing" -ForegroundColor Red
    exit 1
}

$list = Invoke-Dispatcher -ArgumentList @('-List')
Report 'list exits 0' ($list.Exit -eq 0) "exit=$($list.Exit) stderr=$($list.Err)"
Report 'claude is callable' ($list.Out -match '(?m)^claude\tcallable\t') "stdout did not list claude as callable"
Report 'codex is callable' ($list.Out -match '(?m)^codex\tcallable\t') "stdout did not list codex as callable"
Report 'cursor routes to cursor-agent' ($list.Out -match '(?m)^cursor\trouted\tcursor-agent\s*$') "stdout=$($list.Out)"
Report 'warp is refused' ($list.Out -match '(?m)^warp\trefused\t') 'warp was not refused'
Report 'devin is refused' ($list.Out -match '(?m)^devin\trefused\t') 'devin was not refused'

$unknown = Invoke-Dispatcher -ArgumentList @('-HostId', 'not-a-coding-agent', '-Prompt', 'ping')
Report 'unknown host exits 3' ($unknown.Exit -eq 3 -and $unknown.Err -match 'unknown host') "exit=$($unknown.Exit) err=$($unknown.Err)"

$warp = Invoke-Dispatcher -ArgumentList @('-HostId', 'warp', '-Prompt', 'ping', '-ShowCommand')
Report 'warp show exits 3' ($warp.Exit -eq 3 -and $warp.Err -match 'refused warp') "exit=$($warp.Exit) err=$($warp.Err)"

$claude = Invoke-Dispatcher -ArgumentList @('-HostId', 'claude', '-Prompt', 'ping', '-ShowCommand')
Report 'claude show does not launch' ($claude.Exit -eq 0 -and $claude.Out -match '--print' -and $claude.Out -match 'bypassPermissions' -and $claude.Out -match 'stdin=yes') "exit=$($claude.Exit) out=$($claude.Out) err=$($claude.Err)"

$cursor = Invoke-Dispatcher -ArgumentList @('-HostId', 'cursor', '-Prompt', 'ping', '-ShowCommand')
Report 'cursor show targets cursor-agent print mode' ($cursor.Exit -eq 0 -and $cursor.Out -match 'routed: cursor -> cursor-agent' -and $cursor.Out -match '(^|[\s=])-p(\s|$)') "exit=$($cursor.Exit) out=$($cursor.Out) err=$($cursor.Err)"

$factory = Invoke-Dispatcher -ArgumentList @('-HostId', 'factory', '-Prompt', 'ping', '-ShowCommand')
Report 'factory show uses exec and a prompt file' ($factory.Exit -eq 0 -and $factory.Out -match '--auto' -and $factory.Out -match 'exec' -and $factory.Out -match '(^|\s)-f(\s|$)') "exit=$($factory.Exit) out=$($factory.Out) err=$($factory.Err)"

Write-Host ("{0} checks, {1} failed" -f $reported, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
