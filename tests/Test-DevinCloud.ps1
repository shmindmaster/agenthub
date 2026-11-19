#Requires -Version 5.1
<# Devin Cloud adapter (Linear SH-4969). Synthetic only: the one HTTP function,
   Invoke-DevinApi, is replaced by an in-memory mock, `op` is a fixture stub, and
   the only real HTTP attempt targets 127.0.0.1:9, which refuses the connection.
   No Devin API call, no 1Password read, no session and no spend.
   Covers: the create body's max_acu_limit default and override, the agenthub
   and run tags, run-tag dedupe, the 3-session concurrency refusal, the
   missing-key refusal (exit 3), that the key never reaches stdout or stderr,
   wait on waiting_for_user and finished, message and stop routes, repo
   derivation, and the registry records the adapter depends on. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dispatchDir = Join-Path $repoRoot 'packages\coding-agent-dispatch\skills\dispatch'
$libPath = Join-Path $dispatchDir 'DevinCloudLib.ps1'
$entryPath = Join-Path $dispatchDir 'Invoke-DevinCloud.ps1'
$failed = 0; $checked = 0
function Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:checked++
    if ($Passed) { Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name -- $Detail" }
}
function Quote([string]$Value) {
    $v = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    return '"' + ([regex]::Replace($v, '(\\+)$', '$1$1')) + '"'
}
$pwsh = (Get-Process -Id $PID).Path
function Run-Child([string[]]$Arguments, [hashtable]$Environment = @{}) {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.Arguments = (($Arguments | ForEach-Object { Quote $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false); $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($name in $Environment.Keys) {
        if ($null -eq $Environment[$name]) { [void]$psi.EnvironmentVariables.Remove($name) } else { $psi.EnvironmentVariables[$name] = [string]$Environment[$name] }
    }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw 'Devin Cloud child exceeded 60 seconds' }
    $result = [pscustomobject]@{ Exit = $p.ExitCode; Out = $o.GetAwaiter().GetResult(); Err = $e.GetAwaiter().GetResult() }
    $p.Dispose(); return $result
}
function Run-Encoded([string]$Script, [hashtable]$Environment = @{}) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    return Run-Child @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) $Environment
}

$liveFleet = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devin-cloud fixture ' + [guid]::NewGuid().ToString('n'))
$syntheticKey = 'cog_SYNTHETICfixtureKEY0123456789abcdWXYZ'
try {
    # --- In-process: dot-source the library and replace its one HTTP function. ---
    Check 'adapter library exists' (Test-Path -LiteralPath $libPath -PathType Leaf) $libPath
    Check 'adapter entry script exists' (Test-Path -LiteralPath $entryPath -PathType Leaf) $entryPath
    . $libPath

    $script:Calls = [Collections.Generic.List[object]]::new()
    $script:ListedSessions = @()
    $script:StatusSequence = [Collections.Generic.Queue[object]]::new()
    function New-FakeSession([string]$Id, [string]$Status, [string[]]$Tags, [string]$Detail = 'working') {
        [pscustomobject]@{ session_id = $Id; url = "https://app.devin.ai/sessions/$Id"; status = $Status; status_detail = $Detail; tags = $Tags
            acus_consumed = 1.5; pull_requests = @(); structured_output = $null; title = 'fixture'; created_at = 1; updated_at = 2 }
    }
    function Invoke-DevinApi {
        param([string]$Method, [string]$Path, [hashtable]$Query, $Body)
        $script:Calls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Query = $Query; Body = $Body })
        if ($Method -eq 'GET' -and $Path -eq '/sessions') { return [pscustomobject]@{ items = @($script:ListedSessions); has_next_page = $false; end_cursor = $null } }
        if ($Method -eq 'POST' -and $Path -eq '/sessions') { return (New-FakeSession 'devin-created0001' 'new' @($Body.tags) $null) }
        if ($Method -eq 'GET' -and $Path -match '^/sessions/[^/]+$') { return $script:StatusSequence.Dequeue() }
        if ($Method -eq 'POST' -and $Path -match '/messages$') { return $null }
        if ($Method -eq 'GET' -and $Path -match '/messages$') { return [pscustomobject]@{ items = @([pscustomobject]@{ event_id = 'e1'; source = 'devin'; message = 'Which branch?'; created_at = 3 }); has_next_page = $false } }
        if ($Method -eq 'DELETE') { return (New-FakeSession 'devin-stopped0001' 'exit' @('agenthub') 'user_request') }
        throw "unexpected mock call $Method $Path"
    }
    $script:Sleeps = [Collections.Generic.List[int]]::new()
    function Start-DevinCloudSleep { param([int]$Seconds) $script:Sleeps.Add($Seconds) }
    $config = Get-DevinCloudConfig -Fleet $liveFleet
    Set-DevinCloudContext -Config $config -Key $syntheticKey

    $session = New-DevinCloudSession -Config $config -Prompt 'fix the flaky test' -RunId 'sh4969-a' -Repos @('shmindmaster/agenthub')
    $post = @($script:Calls | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/sessions' })
    Check 'create sends max_acu_limit 10 by default' ($post.Count -eq 1 -and $post[0].Body.max_acu_limit -eq 10 -and $session.max_acu_limit -eq 10) ($post | ConvertTo-Json -Depth 6 -Compress)
    Check 'create sends prompt, repos and a title' ($post[0].Body.prompt -eq 'fix the flaky test' -and @($post[0].Body.repos) -contains 'shmindmaster/agenthub' -and -not [string]::IsNullOrWhiteSpace([string]$post[0].Body.title))
    Check 'create tags the session agenthub and run:<runId>' (@($post[0].Body.tags) -contains 'agenthub' -and @($post[0].Body.tags) -contains 'run:sh4969-a' -and @($session.tags) -contains 'run:sh4969-a') (@($post[0].Body.tags) -join ',')
    Check 'create output names session_id, url, status, max_acu_limit and tags' ($session.session_id -eq 'devin-created0001' -and $session.url -match '^https://app\.devin\.ai/sessions/' -and $session.status -eq 'new' -and $null -ne $session.tags -and $session.deduplicated -eq $false)

    $script:Calls.Clear()
    $session = New-DevinCloudSession -Config $config -Prompt 'bigger task' -RunId 'sh4969-b' -MaxAcu 25 -Tags @('SH-4969')
    $post = @($script:Calls | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/sessions' })
    Check 'an explicit -MaxAcu overrides the default cap' ($post[0].Body.max_acu_limit -eq 25 -and $session.max_acu_limit -eq 25)
    Check 'extra tags are added after agenthub and the run tag' ((@($post[0].Body.tags) -join ',') -eq 'agenthub,run:sh4969-b,SH-4969') (@($post[0].Body.tags) -join ',')
    Check 'create omits structured_output_schema unless a schema is given' (-not $post[0].Body.Contains('structured_output_schema'))

    $schemaFile = Join-Path ([IO.Path]::GetTempPath()) ('devin-schema-' + [guid]::NewGuid().ToString('n') + '.json')
    [IO.File]::WriteAllText($schemaFile, '{"type":"object","properties":{"verdict":{"type":"string"}},"required":["verdict"]}')
    $script:Calls.Clear()
    $null = New-DevinCloudSession -Config $config -Prompt 'review' -RunId 'sh4969-s' -SchemaFile $schemaFile
    Remove-Item -LiteralPath $schemaFile -Force
    $post = @($script:Calls | Where-Object { $_.Method -eq 'POST' -and $_.Path -eq '/sessions' })
    Check 'a schema file becomes structured_output_schema' ($post[0].Body.structured_output_schema.required -contains 'verdict')

    $refused = $null
    try { $null = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-z' -MaxAcu -1 } catch { $refused = $_.Exception }
    Check 'a non-positive -MaxAcu is refused with exit 3' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3)

    $script:Calls.Clear()
    $script:ListedSessions = @(New-FakeSession 'devin-existing01' 'running' @('agenthub', 'run:sh4969-dup'))
    $session = New-DevinCloudSession -Config $config -Prompt 'again' -RunId 'sh4969-dup'
    Check 'an existing run tag returns that session' ($session.session_id -eq 'devin-existing01' -and $session.deduplicated -eq $true)
    Check 'dedupe makes no create request' (@($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 0)
    Check 'dedupe asks the API for the run tag' (@($script:Calls | Where-Object { $_.Method -eq 'GET' -and @($_.Query.tags) -contains 'run:sh4969-dup' }).Count -ge 1)

    $script:Calls.Clear()
    $script:ListedSessions = @(
        (New-FakeSession 'devin-a1' 'running' @('agenthub', 'run:a')),
        (New-FakeSession 'devin-a2' 'claimed' @('agenthub', 'run:b')),
        (New-FakeSession 'devin-a3' 'resuming' @('agenthub', 'run:c')),
        (New-FakeSession 'devin-a4' 'exit' @('agenthub', 'run:d') 'finished')
    )
    $refused = $null
    try { $null = New-DevinCloudSession -Config $config -Prompt 'fourth' -RunId 'sh4969-cap' } catch { $refused = $_.Exception }
    Check 'a fourth concurrent agenthub session is refused with exit 3' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3 -and $refused.Message -match '3' -and $refused.Message -match 'devin-a1') "$($refused.Message)"
    Check 'the concurrency refusal makes no create request' (@($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 0)

    $script:Calls.Clear()
    $script:ListedSessions = @(
        (New-FakeSession 'devin-a1' 'running' @('agenthub', 'run:a')),
        (New-FakeSession 'devin-a2' 'new' @('agenthub', 'run:b')),
        (New-FakeSession 'devin-a4' 'exit' @('agenthub', 'run:d') 'finished'),
        (New-FakeSession 'devin-other' 'running' @('someone-else'))
    )
    $session = New-DevinCloudSession -Config $config -Prompt 'third' -RunId 'sh4969-ok'
    Check 'two active agenthub sessions still allow a third (finished and untagged ones are not counted)' ($session.session_id -eq 'devin-created0001')

    $script:Calls.Clear(); $script:Sleeps.Clear(); $script:StatusSequence.Clear()
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'working'))
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'waiting_for_user'))
    $report = Wait-DevinCloudSession -SessionId 'devin-w1' -TimeoutSec 600 -PollSec 5
    Check 'wait returns waiting_for_user so the orchestrator can answer' ($report.outcome -eq 'waiting_for_user' -and $report.status_detail -eq 'waiting_for_user' -and $script:StatusSequence.Count -eq 0) ($report | ConvertTo-Json -Compress)
    Check 'wait backs off between polls' ($script:Sleeps.Count -eq 1 -and $script:Sleeps[0] -ge 5)

    $script:Sleeps.Clear(); $script:StatusSequence.Clear()
    $done = New-FakeSession 'devin-w2' 'running' @('agenthub') 'finished'
    $done.acus_consumed = 4.25
    $done.pull_requests = @([pscustomobject]@{ pr_url = 'https://github.com/o/r/pull/7'; pr_state = 'open' })
    $done.structured_output = [pscustomobject]@{ verdict = 'PASS' }
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-w2' 'new' @('agenthub') $null))
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-w2' 'running' @('agenthub') 'working'))
    $script:StatusSequence.Enqueue($done)
    $report = Wait-DevinCloudSession -SessionId 'devin-w2' -TimeoutSec 600 -PollSec 5
    Check 'wait stops on finished and reports acus_consumed, pull_requests and structured_output' ($report.outcome -eq 'finished' -and $report.acus_consumed -eq 4.25 -and @($report.pull_requests).Count -eq 1 -and $report.structured_output.verdict -eq 'PASS')
    Check 'wait backoff grows' ($script:Sleeps.Count -eq 2 -and $script:Sleeps[1] -gt $script:Sleeps[0]) (($script:Sleeps) -join ',')

    $script:Sleeps.Clear(); $script:StatusSequence.Clear()
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-w3' 'suspended' @('agenthub') 'usage_limit_exceeded'))
    $report = Wait-DevinCloudSession -SessionId 'devin-w3' -TimeoutSec 600 -PollSec 5
    Check 'wait stops on a suspended session' ($report.outcome -eq 'suspended' -and $script:Sleeps.Count -eq 0)

    $script:Calls.Clear()
    $null = Send-DevinCloudMessage -SessionId 'devin-w1' -Message 'Use main.'
    $msg = @($script:Calls | Where-Object { $_.Method -eq 'POST' })
    Check 'message posts {message} to the session messages route' ($msg.Count -eq 1 -and $msg[0].Path -eq '/sessions/devin-w1/messages' -and $msg[0].Body.message -eq 'Use main.')
    $script:Calls.Clear()
    $null = Stop-DevinCloudSession -SessionId 'devin-w1'
    Check 'stop deletes the session' (@($script:Calls | Where-Object { $_.Method -eq 'DELETE' -and $_.Path -eq '/sessions/devin-w1' }).Count -eq 1)
    $refused = $null
    try { $null = Stop-DevinCloudSession -SessionId '../../organizations' } catch { $refused = $_.Exception }
    Check 'a session id shaped like a path is refused' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3)

    Check 'repo derives from an https GitHub remote' ((ConvertTo-DevinCloudRepoName 'https://github.com/shmindmaster/agenthub.git') -eq 'shmindmaster/agenthub')
    Check 'repo derives from an ssh GitHub remote' ((ConvertTo-DevinCloudRepoName 'git@github.com:shmindmaster/agenthub.git') -eq 'shmindmaster/agenthub')
    Check 'a non-GitHub remote derives no repo' ($null -eq (ConvertTo-DevinCloudRepoName 'https://example.com/x.git'))

    Check 'masking keeps only the last four characters' ((Protect-DevinCloudText "token $syntheticKey here") -eq 'token ****WXYZ here')

    # --- Child processes: real entry script and real refusal/exit paths. ---
    foreach ($dir in @('registry', 'bin')) { $null = New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force }
    '{}' | Set-Content -LiteralPath (Join-Path $fixture 'registry\agents.json') -Encoding UTF8
    $fixtureFleet = $liveFleet | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $fixtureFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization.apiBase = 'https://127.0.0.1:9/v3'
    $fixtureFleet | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    $failingOp = Join-Path $fixture 'bin-fail'; $keyOp = Join-Path $fixture 'bin-key'
    foreach ($dir in @($failingOp, $keyOp)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    # The key-bearing stub records its arguments (the op reference, never a key)
    # so the test can prove the adapter asked for the registry's reference.
    $opArgsFile = Join-Path $fixture 'op-args.txt'
    if ($env:OS -eq 'Windows_NT') {
        [IO.File]::WriteAllText((Join-Path $failingOp 'op.cmd'), "@echo off`r`necho [ERROR] item not found 1>&2`r`nexit /b 1`r`n")
        [IO.File]::WriteAllText((Join-Path $keyOp 'op.cmd'), "@echo off`r`n>`"$opArgsFile`" echo %*`r`necho $syntheticKey`r`n")
    } else {
        [IO.File]::WriteAllText((Join-Path $failingOp 'op'), "#!/bin/sh`necho '[ERROR] item not found' >&2`nexit 1`n")
        [IO.File]::WriteAllText((Join-Path $keyOp 'op'), "#!/bin/sh`necho `"`$*`" > '$opArgsFile'`necho '$syntheticKey'`n")
        foreach ($f in @((Join-Path $failingOp 'op'), (Join-Path $keyOp 'op'))) { [IO.File]::SetUnixFileMode($f, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }
    }
    $sep = [IO.Path]::PathSeparator
    # A synthetic service-account token: the real one is never handed to a stub.
    $childLocal = Join-Path $fixture 'localappdata'
    $null = New-Item -ItemType Directory -Path $childLocal -Force
    $baseEnv = @{ AGENTHUB_ROOT = $fixture; DEVIN_CLOUD_API_KEY = $null; DEVIN_API_KEY = $null; OP_SERVICE_ACCOUNT_TOKEN = 'ops_synthetic-fixture-token'; LOCALAPPDATA = $childLocal }

    $envNoKey = $baseEnv.Clone(); $envNoKey.PATH = $failingOp + $sep + $env:PATH
    $r = Run-Child @('-NoProfile', '-File', $entryPath, '-Action', 'create', '-Prompt', 'ok', '-RunId', 'sh4969-nokey') $envNoKey
    Check 'a missing key refuses with exit 3' ($r.Exit -eq 3) "exit=$($r.Exit) err=$($r.Err)"
    Check 'the missing-key refusal names the env variable and the 1Password item to create' ($r.Err -match 'DEVIN_CLOUD_API_KEY' -and $r.Err -match 'Business & Apps' -and $r.Err -match 'Devin Cloud API service user') $r.Err
    Check 'the missing-key refusal prints no JSON' ([string]::IsNullOrWhiteSpace($r.Out)) $r.Out

    $envNoOp = $baseEnv.Clone(); $envNoOp.PATH = (Join-Path $fixture 'bin')
    $r = Run-Child @('-NoProfile', '-File', $entryPath, '-Action', 'list') $envNoOp
    Check 'a missing key with no op CLI also refuses with exit 3' ($r.Exit -eq 3 -and $r.Err -match 'Business & Apps' -and $r.Err -match 'not on PATH') "exit=$($r.Exit) err=$($r.Err)"

    # Owner direction 2026-11-19: the key comes only through the 1Password service account.
    $envNoToken = $baseEnv.Clone(); $envNoToken.OP_SERVICE_ACCOUNT_TOKEN = $null; $envNoToken.PATH = $keyOp + $sep + $env:PATH
    if (Test-Path -LiteralPath $opArgsFile) { Remove-Item -LiteralPath $opArgsFile -Force }
    $r = Run-Child @('-NoProfile', '-File', $entryPath, '-Action', 'list') $envNoToken
    Check 'a missing OP_SERVICE_ACCOUNT_TOKEN refuses with exit 3 before op runs' ($r.Exit -eq 3 -and $r.Err -match 'OP_SERVICE_ACCOUNT_TOKEN' -and $r.Err -match 'Business & Apps' -and -not (Test-Path -LiteralPath $opArgsFile)) "exit=$($r.Exit) err=$($r.Err)"
    Check 'the missing-token refusal never prints the key' (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey))

    $envKey = $baseEnv.Clone(); $envKey.DEVIN_CLOUD_API_KEY = $syntheticKey; $envKey.PATH = $failingOp + $sep + $env:PATH
    $r = Run-Child @('-NoProfile', '-File', $entryPath, '-Action', 'status', '-SessionId', 'devin-netfail01') $envKey
    Check 'a transport failure exits non-zero without a refusal code' ($r.Exit -eq 1) "exit=$($r.Exit) err=$($r.Err)"
    Check 'the real HTTP error path never prints the key' (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey)) $r.Err

    $mockScript = @"
`$ErrorActionPreference = 'Stop'
. '$($libPath.Replace("'", "''"))'
function Invoke-DevinApi {
    param([string]`$Method, [string]`$Path, [hashtable]`$Query, `$Body)
    if (`$Method -eq 'GET') { return [pscustomobject]@{ items = @(); has_next_page = `$false } }
    if (`$env:MOCK_ECHO_KEY) { throw ('401 Unauthorized for bearer ' + `$env:DEVIN_CLOUD_API_KEY) }
    return [pscustomobject]@{ session_id = 'devin-mock0001'; url = 'https://app.devin.ai/sessions/devin-mock0001'; status = 'new'; tags = @(`$Body.tags); acus_consumed = 0; pull_requests = @() }
}
exit (Invoke-DevinCloudMain -Action create -Prompt 'ok' -RunId 'sh4969-leak')
"@
    $r = Run-Encoded $mockScript $envKey
    $json = if ($r.Exit -eq 0) { try { $r.Out | ConvertFrom-Json } catch { $null } } else { $null }
    Check 'create prints one JSON object with the session' ($null -ne $json -and $json.session_id -eq 'devin-mock0001' -and $json.max_acu_limit -eq 10 -and @($json.tags) -contains 'run:sh4969-leak') "exit=$($r.Exit) out=$($r.Out) err=$($r.Err)"
    Check 'a successful create never prints the key' (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey))

    $envEcho = $envKey.Clone(); $envEcho.MOCK_ECHO_KEY = '1'
    $r = Run-Encoded $mockScript $envEcho
    Check 'an API error that echoes the key exits non-zero' ($r.Exit -ne 0) "exit=$($r.Exit)"
    Check 'an API error that echoes the key prints it masked to the last four' (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey) -and $r.Err -match '\*\*\*\*WXYZ') $r.Err

    $envOp = $baseEnv.Clone(); $envOp.PATH = $keyOp + $sep + $env:PATH
    if (Test-Path -LiteralPath $opArgsFile) { Remove-Item -LiteralPath $opArgsFile -Force }
    $r = Run-Encoded $mockScript $envOp
    Check 'the key resolves from op read when the env variable is unset' ($r.Exit -eq 0 -and $r.Out -match 'devin-mock0001') "exit=$($r.Exit) err=$($r.Err)"
    $opArgs = if (Test-Path -LiteralPath $opArgsFile) { ([IO.File]::ReadAllText($opArgsFile)).Trim() } else { '' }
    $expectedRef = [string]$liveFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization.keyOpRef
    Check 'op read is called with the registry keyOpRef' ($opArgs -match '^read\b' -and $opArgs.Contains($expectedRef)) "args=$opArgs"
    Check 'a key read from op never reaches stdout or stderr' (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey))
    # Nothing the adapter (or its children) wrote under the fixture or the child's
    # LOCALAPPDATA may hold the key. The op stub's own fixture lines are excluded.
    $leaks = @(Get-ChildItem -LiteralPath $fixture -Recurse -File | Where-Object { $_.Directory.FullName -notin @($failingOp, $keyOp) } |
        Where-Object { [IO.File]::ReadAllText($_.FullName).Contains($syntheticKey) } | ForEach-Object { $_.FullName })
    Check 'the adapter writes the key to no file' ($leaks.Count -eq 0) ($leaks -join '; ')

    $disabled = $liveFleet | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $disabled.dispatchPolicy.'devin-cloud'.enabled = $false
    $disabled | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    $r = Run-Child @('-NoProfile', '-File', $entryPath, '-Action', 'list') $envKey
    Check 'a disabled devin-cloud policy refuses with exit 3' ($r.Exit -eq 3 -and $r.Err -match 'devin-cloud') "exit=$($r.Exit) err=$($r.Err)"

    # --- Registry records the adapter depends on. ---
    $mcps = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $devinMcp = @($mcps.mcpServers | Where-Object { $_.id -eq 'devin' })
    Check 'registry/mcps.json carries one devin server' ($devinMcp.Count -eq 1)
    if ($devinMcp.Count -eq 1) {
        $m = $devinMcp[0]
        Check 'devin MCP is the official Streamable HTTP endpoint' ($m.url -eq 'https://mcp.devin.ai/mcp' -and $m.transport -eq 'http' -and $m.activationMode -eq 'shared-remote')
        # Owner direction 2026-11-19: no persisted secret and no key-bearing env var in a host config.
        Check 'devin MCP carries no static or env-expanded auth header' ($null -eq $m.headers -and ($m | ConvertTo-Json -Depth 10) -notmatch '\$\{env:|\{env:|DEVIN_CLOUD_API_KEY|DEVIN_API_KEY|cog_[A-Za-z0-9_-]{8,}')
        Check 'devin MCP authenticates through the headers helper' ($m.credentialPolicy -eq 'native-headers-helper' -and [string]$m.headersHelper.claude -match 'Get-DevinMcpHeaders\.ps1')
        Check 'devin MCP is declared for claude only, with a plugin-only exception' ((@($m.hosts) -join ',') -eq 'claude' -and -not [string]::IsNullOrWhiteSpace([string]$mcps.activationPolicy.pluginOnly.hosts.claude.devin))
        Check 'devin MCP is never written by a default-scope sync' ([string]$m.scope -ne 'global-default')
        Check 'devin MCP records no invented protocol verification' ($null -eq $m.protocol.revision -and [string]$m.protocol.verification -match 'cannot be established' -and [string]$m.notes -match 'docs\.devin\.ai/work-with-devin/devin-mcp')
    }

    # --- The MCP headers helper: op read at connect time, headers on stdout only. ---
    $helperPath = Join-Path $dispatchDir 'Get-DevinMcpHeaders.ps1'
    Check 'the Devin MCP headers helper exists' (Test-Path -LiteralPath $helperPath -PathType Leaf) $helperPath
    $liveFleet | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $helperPath) $envOp
    $headers = if ($r.Exit -eq 0) { try { $r.Out | ConvertFrom-Json } catch { $null } } else { $null }
    Check 'the helper prints the Authorization and X-Org-Id headers as one JSON object' ($null -ne $headers -and $headers.Authorization -eq "Bearer $syntheticKey" -and $headers.'X-Org-Id' -eq $liveFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization.orgId -and @($headers.PSObject.Properties).Count -eq 2) "exit=$($r.Exit) err=$($r.Err)"
    Check 'the helper keeps the key off stderr' ($r.Err -notmatch [regex]::Escape($syntheticKey))
    $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $helperPath) $envNoToken
    Check 'the helper refuses with exit 3 and no headers when the service-account token is unset' ($r.Exit -eq 3 -and [string]::IsNullOrWhiteSpace($r.Out) -and $r.Err -match 'OP_SERVICE_ACCOUNT_TOKEN') "exit=$($r.Exit) err=$($r.Err)"
    $leaks = @(Get-ChildItem -LiteralPath $fixture -Recurse -File | Where-Object { $_.Directory.FullName -notin @($failingOp, $keyOp) } |
        Where-Object { [IO.File]::ReadAllText($_.FullName).Contains($syntheticKey) } | ForEach-Object { $_.FullName })
    Check 'the helper writes the key to no file' ($leaks.Count -eq 0) ($leaks -join '; ')
    $localPolicy = $liveFleet.dispatchPolicy.devin
    Check 'the local Devin lane stays local-only and points cloud work at devin-cloud' ([string]$localPolicy.scope -match '^local-only' -and [string]$localPolicy.scope -match 'devin-cloud')
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ((Test-Path -LiteralPath $resolved) -and $resolved.StartsWith([IO.Path]::GetFullPath(([IO.Path]::GetTempPath())).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
