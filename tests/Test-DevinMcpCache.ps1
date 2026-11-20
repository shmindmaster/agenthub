#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$failed = 0; $checked = 0
function Check([string]$Name, [bool]$Passed) {
    $script:checked++
    if ($Passed) { Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name" }
}
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'packages/coding-agent-dispatch/skills/dispatch'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devin-mcp-' + [guid]::NewGuid().ToString('n'))
$oldFixture = $env:DEVIN_MCP_FIXTURE
$env:DEVIN_MCP_FIXTURE = $fixture
$pwsh = (Get-Process -Id $PID).Path
function Connect {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.Arguments = '-NoProfile -NonInteractive -File "' + (Join-Path $fixture 'Get-DevinMcpHeaders.ps1') + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    [void]$psi.EnvironmentVariables.Remove('DEVIN_CLOUD_API_KEY')
    $psi.EnvironmentVariables['OP_SERVICE_ACCOUNT_TOKEN'] = 'synthetic-service-account'
    $psi.EnvironmentVariables['PATH'] = (Join-Path $fixture 'bin') + [IO.Path]::PathSeparator + $env:PATH
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'Fixture connect timed out' }
    $result = @{ Code = $p.ExitCode; Out = $o.GetAwaiter().GetResult(); Err = $e.GetAwaiter().GetResult() }
    $p.Dispose()
    return $result
}
function OpCalls { return @(Get-Content -LiteralPath (Join-Path $fixture 'calls') -Encoding UTF8).Count }
try {
    $null = New-Item -ItemType Directory -Path $fixture
    Copy-Item (Join-Path $source 'Get-DevinMcpHeaders.ps1') $fixture
    $bin = Join-Path $fixture 'bin'
    $null = New-Item -ItemType Directory -Path $bin
    if ($env:OS -eq 'Windows_NT') {
        $op = @'
@echo off
echo call>>"%DEVIN_MCP_FIXTURE%\calls"
if exist "%DEVIN_MCP_FIXTURE%\error" (echo sensitive diagnostic must not escape 1>&2 & exit /b 1)
if exist "%DEVIN_MCP_FIXTURE%\empty" exit /b 0
echo cog_SYNTHETICfixtureOnly
'@
        [IO.File]::WriteAllText((Join-Path $bin 'op.cmd'), $op.Replace("`n", "`r`n"))
    } else {
        $op = @'
#!/bin/sh
echo call >> "$DEVIN_MCP_FIXTURE/calls"
if [ -f "$DEVIN_MCP_FIXTURE/error" ]; then echo 'sensitive diagnostic must not escape' >&2; exit 1; fi
if [ -f "$DEVIN_MCP_FIXTURE/empty" ]; then exit 0; fi
echo cog_SYNTHETICfixtureOnly
'@
        $opPath = Join-Path $bin 'op'
        [IO.File]::WriteAllText($opPath, $op)
        [IO.File]::SetUnixFileMode($opPath, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
    }
    $lib = [IO.File]::ReadAllText((Join-Path $source 'DevinCloudLib.ps1'))
    $stub = @'
function Get-DevinMcpCacheDirectory { return (Join-Path $env:DEVIN_MCP_FIXTURE 'cache') }
function Get-DevinCloudFleet {
    return [pscustomobject]@{ dispatchPolicy = [pscustomobject]@{ 'devin-cloud' = [pscustomobject]@{
        enabled = -not (Test-Path (Join-Path $env:DEVIN_MCP_FIXTURE 'disabled'))
        cloudBudgetAuthorization = [pscustomobject]@{ apiBase = 'https://example.invalid'; orgId = 'fixture'; keyOpRef = 'op://fixture/item/key'; defaultMaxAcuLimit = 1; maxConcurrentSessions = 1 }
    } } }
}
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'DevinCloudLib.ps1'), $lib + "`n" + $stub)
    $a = Connect; $b = Connect
    Check 'separate helper connects reuse one mocked op read' ($a.Code -eq 0 -and $b.Code -eq 0 -and (OpCalls) -eq 1 -and $a.Out -eq $b.Out -and $a.Err -eq '' -and $b.Err -eq '')
    $cache = @(Get-ChildItem (Join-Path $fixture 'cache') -Filter '*.json')[0].FullName
    if ($env:OS -eq 'Windows_NT') {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        foreach ($path in @((Split-Path $cache), $cache)) {
            $acl = Get-Acl -LiteralPath $path
            $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
            Check 'cache ACL is protected and grants only current user' ($acl.AreAccessRulesProtected -and $rules.Count -eq 1 -and $rules[0].IdentityReference.Value -eq $sid)
        }
        Check 'Windows cache does not contain plaintext key' (-not ([IO.File]::ReadAllText($cache)).Contains('cog_SYNTHETICfixtureOnly'))
    } else {
        Check 'cache directory mode is 0700' ([IO.File]::GetUnixFileMode((Split-Path $cache)) -eq [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
        Check 'cache file mode is 0600' ([IO.File]::GetUnixFileMode($cache) -eq [IO.UnixFileMode]'UserRead, UserWrite')
    }
    $entry = Get-Content $cache -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry.created = [DateTimeOffset]::UtcNow.AddHours(-13).ToUnixTimeSeconds()
    [IO.File]::WriteAllText($cache, ($entry | ConvertTo-Json -Compress))
    $c = Connect
    Check '12-hour TTL expiry rereads op' ($c.Code -eq 0 -and (OpCalls) -eq 2)
    [IO.File]::WriteAllText($cache, '{broken')
    $c = Connect
    Check 'corrupt cache rereads op' ($c.Code -eq 0 -and (OpCalls) -eq 3)
    [IO.File]::WriteAllText((Join-Path $fixture 'disabled'), '')
    $c = Connect
    Check 'disabled policy refuses even with warm cache' ($c.Code -eq 3 -and $c.Out -eq '' -and (OpCalls) -eq 3)
    Remove-Item (Join-Path $fixture 'disabled')
    Remove-Item $cache
    [IO.File]::WriteAllText((Join-Path $fixture 'error'), '')
    $c = Connect
    Check 'op failure has empty stdout and sanitized stderr' ($c.Code -ne 0 -and $c.Out -eq '' -and $c.Err -notmatch 'sensitive|cog_')
    Check 'failed reads are not cached' (-not (Test-Path $cache))
    Remove-Item (Join-Path $fixture 'error')
    [IO.File]::WriteAllText((Join-Path $fixture 'empty'), '')
    $c = Connect
    Check 'empty op result is refused and not cached' ($c.Code -ne 0 -and $c.Out -eq '' -and -not (Test-Path $cache))
} finally {
    $env:DEVIN_MCP_FIXTURE = $oldFixture
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "RESULT: $($checked - $failed) passed, $failed failed"
if ($failed) { exit 1 }
exit 0
