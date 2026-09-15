#Requires -Version 5.1
<#
.SYNOPSIS
Reports local MCP servers that declare single-shared-process but have more
than one live process.

.DESCRIPTION
registry/mcps.json lets an on-demand-local server declare
`localProcessPolicy.instancing`, and activationPolicy states the rule plainly:
"A local server runs as one process shared across agents; multiple hosts must
not each spawn their own instance of the same server."

Nothing enforced that. Validate-AgentHub.ps1 checks only that the field is
non-empty -- a check whose signal does not track the thing it claims to watch,
so it passes while the policy is violated. Measured 2026-08-19: seven live
appium-mcp processes from four separate sessions, against a declared
single-shared-process.

This is a diagnostic, not a Test-*.ps1 behavior test, precisely because its
result depends on what is running right now. A suite that goes red because the
owner happens to have three editors open would train people to ignore it.

Exit code is 0 unless -FailOnViolation is passed, so it is safe to call from an
audit path.

.EXAMPLE
pwsh -NoProfile -File scripts/Check-LocalMcpInstancing.ps1
#>
[CmdletBinding()]
param(
    # Exit 1 when a violation is found. Off by default: live process count is
    # environment state, not a repository defect.
    [switch]$FailOnViolation
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$mcp = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Match on a token distinctive enough to identify the server in a command line.
# The package name in args beats the id, which often does not appear at all.
function Get-MatchToken {
    param($Server)
    foreach ($a in @($Server.args)) {
        $a = [string]$a
        if ($a -and $a -notmatch '^-' -and $a -notmatch '^[A-Za-z]:[\/]' -and $a -ne 'mcp') {
            return ($a -replace '@[^@/]*$', '')   # drop a trailing @version pin
        }
    }
    return [string]$Server.command
}

$procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine })

$violations = 0
$checked = 0

foreach ($server in @($mcp.mcpServers)) {
    if ($server.activationMode -ne 'on-demand-local') { continue }
    $instancing = [string]$server.localProcessPolicy.instancing
    if ($instancing -ne 'single-shared-process') { continue }
    $checked++

    $token = Get-MatchToken -Server $server
    if (-not $token) { continue }

    # npx bootstraps the real server, so a wrapper and its child both match the
    # token. Count them separately: two processes for one logical server is
    # expected, seven is not.
    $live = @($procs | Where-Object { $_.CommandLine -like "*$token*" })
    $wrappers = @($live | Where-Object { $_.CommandLine -match 'npx-cli|npm-cli' })
    $servers  = @($live | Where-Object { $_.CommandLine -notmatch 'npx-cli|npm-cli' })

    if ($servers.Count -gt 1) {
        $violations++
        Write-Host ("VIOLATION: '{0}' declares {1} but has {2} live server processes ({3} npx wrapper(s))." -f `
            $server.id, $instancing, $servers.Count, $wrappers.Count) -ForegroundColor Red
        foreach ($p in $servers) {
            $parent = try { (Get-Process -Id $p.ParentProcessId -ErrorAction Stop).ProcessName } catch { '<dead>' }
            Write-Host ("    pid {0,-7} parent {1,-16} started {2}" -f $p.ProcessId, $parent, $p.CreationDate)
        }
        Write-Host "    Each was spawned by a separate session. Restart those hosts to reclaim them; the registry host scope prevents new ones." -ForegroundColor DarkGray
    } elseif ($servers.Count -eq 1) {
        Write-Host ("OK: '{0}' has exactly 1 live process." -f $server.id) -ForegroundColor Green
    } else {
        Write-Host ("OK: '{0}' is not running (on-demand, nothing spawned)." -f $server.id) -ForegroundColor Green
    }
}

Write-Host ''
if ($checked -eq 0) {
    Write-Host 'No server declares single-shared-process; nothing to check.' -ForegroundColor Yellow
    exit 0
}
if ($violations -gt 0) {
    Write-Host "RESULT: $violations of $checked single-shared-process server(s) violated." -ForegroundColor Red
    if ($FailOnViolation) { exit 1 }
    exit 0
}
Write-Host "RESULT: all $checked single-shared-process server(s) hold the policy." -ForegroundColor Green
exit 0
