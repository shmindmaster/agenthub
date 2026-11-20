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
    # Optional mock knobs: ListPages (an array of pages keyed by the after cursor),
    # ListThrows (the agenthub-tag count fails), MessageSequence (successive
    # message lists). A StatusSequence entry that is an exception is thrown.
    $script:ListPages = $null
    $script:ListThrows = $false
    $script:MessageSequence = [Collections.Generic.Queue[object]]::new()
    $script:DefaultMessages = @([pscustomobject]@{ event_id = 'e1'; source = 'devin'; message = 'Which branch?'; created_at = 3 })
    $script:MessagePosted = $false
    $script:MessagePages = $null
    $script:MessageErrors = [Collections.Generic.Queue[object]]::new()
    $script:ThreadBeforePost = $null
    $script:ThreadAfterPost = $null
    function Invoke-DevinApi {
        param([string]$Method, [string]$Path, [hashtable]$Query, $Body)
        $script:Calls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Query = $Query; Body = $Body })
        if ($Method -eq 'GET' -and $Path -eq '/sessions') {
            if ($script:ListThrows -and @($Query.tags) -contains 'agenthub') { $e = [InvalidOperationException]::new('devin-cloud API GET /sessions failed: HTTP 500.'); $e.Data['ExitCode'] = 1; throw $e }
            if ($script:ListPages) {
                $index = if ($Query.after) { [int]([string]$Query.after).Substring(1) } else { 0 }
                return $script:ListPages[$index]
            }
            return [pscustomobject]@{ items = @($script:ListedSessions); has_next_page = $false; end_cursor = $null }
        }
        if ($Method -eq 'POST' -and $Path -eq '/sessions') { return (New-FakeSession 'devin-created0001' 'new' @($Body.tags) $null) }
        if ($Method -eq 'GET' -and $Path -match '^/sessions/[^/]+$') { $next = $script:StatusSequence.Dequeue(); if ($next -is [Exception]) { throw $next }; return $next }
        if ($Method -eq 'POST' -and $Path -match '/messages$') { $script:MessagePosted = $true; return (New-FakeSession 'devin-w1' 'running' @('agenthub') 'working') }
        if ($Method -eq 'GET' -and $Path -match '/messages$') {
            if ($script:MessageErrors.Count -gt 0) { throw $script:MessageErrors.Dequeue() }
            if ($script:MessagePages) {
                $index = if ($Query.after) { [int]([string]$Query.after).Substring(1) } else { 0 }
                return $script:MessagePages[$index]
            }
            # A thread that changes once the POST lands: Devin can reply at once.
            if ($null -ne $script:ThreadBeforePost) {
                $thread = if ($script:MessagePosted) { $script:ThreadAfterPost } else { $script:ThreadBeforePost }
                return [pscustomobject]@{ items = @($thread); has_next_page = $false; end_cursor = $null }
            }
            $items = if ($script:MessageSequence.Count -gt 0) { $script:MessageSequence.Dequeue() } else { $script:DefaultMessages }
            return [pscustomobject]@{ items = @($items); has_next_page = $false; end_cursor = $null }
        }
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

    # --- Fix round (review of 5f3e318a and the live end-to-end test). ---
    # 7: -MaxAcu is text validated as a positive integer; PowerShell's [int] would round 2.5 and read 1e3.
    $script:ListedSessions = @()
    foreach ($bad in @('abc', '1e3', '2.5', '0', '-1', ' ', '0x10', '+5')) {
        $refused = $null
        try { $null = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-acu' -MaxAcu $bad } catch { $refused = $_.Exception }
        Check "-MaxAcu '$bad' is refused with exit 3" ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3) "$($refused.Message)"
    }
    $script:Calls.Clear()
    $session = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-acu40' -MaxAcu '40'
    $post = @($script:Calls | Where-Object { $_.Method -eq 'POST' })
    Check 'a higher explicit -MaxAcu is still allowed and sent as an integer' ($post.Count -eq 1 -and $post[0].Body.max_acu_limit -eq 40 -and $post[0].Body.max_acu_limit -is [int])

    # 3: without -RunId the run id is derived from the prompt, sorted repos and title, so a retry dedupes.
    $script:Calls.Clear(); $script:ListedSessions = @()
    $a = New-DevinCloudSession -Config $config -Prompt 'same task' -Repos @('o/b', 'o/a') -Title 'T'
    $b = New-DevinCloudSession -Config $config -Prompt 'same task' -Repos @('o/a', 'o/b') -Title 'T'
    $c = New-DevinCloudSession -Config $config -Prompt 'other task' -Repos @('o/a', 'o/b') -Title 'T'
    $d = New-DevinCloudSession -Config $config -Prompt 'same task' -Repos @('o/a', 'o/b') -Title 'U'
    Check 'an omitted -RunId is derived deterministically' ($a.run_id -match '^auto-[0-9a-f]{16}$' -and $a.run_id -eq $b.run_id) "$($a.run_id) vs $($b.run_id)"
    Check 'a different prompt or title derives a different run id' ($c.run_id -ne $a.run_id -and $d.run_id -ne $a.run_id)
    $script:Calls.Clear()
    $script:ListedSessions = @(New-FakeSession 'devin-retry01' 'running' @('agenthub', "run:$($a.run_id)"))
    $retry = New-DevinCloudSession -Config $config -Prompt 'same task' -Repos @('o/a', 'o/b') -Title 'T'
    Check 'an identical re-dispatch without -RunId dedupes' ($retry.deduplicated -eq $true -and $retry.session_id -eq 'devin-retry01' -and @($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 0)
    # 9: the v3 session response has no max_acu_limit, so a dedupe omits the field rather than printing null.
    Check 'a deduplicated result omits max_acu_limit' ($null -eq $retry.PSObject.Properties['max_acu_limit']) ($retry | ConvertTo-Json -Compress)

    # 5: the concurrency count reads every page and fails closed.
    $pages = for ($i = 0; $i -lt 12; $i++) {
        $status = if ($i -in @(0, 5, 11)) { 'running' } else { 'exit' }
        [pscustomobject]@{ items = @(New-FakeSession "devin-p$i" $status @('agenthub', "run:p$i")); has_next_page = ($i -lt 11); end_cursor = $(if ($i -lt 11) { "p$($i + 1)" } else { $null }) }
    }
    $script:ListPages = @($pages)
    $refused = $null
    try { $null = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-pages' } catch { $refused = $_.Exception }
    Check 'active sessions beyond page 10 still count toward the cap' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3 -and $refused.Message -match 'devin-p11') "$($refused.Message)"
    $script:ListPages = @([pscustomobject]@{ items = @(); has_next_page = $true; end_cursor = $null })
    $refused = $null; $script:Calls.Clear()
    try { $null = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-nocursor' } catch { $refused = $_.Exception }
    Check 'a page that promises more without a cursor fails closed with exit 3' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3 -and @($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 0) "$($refused.Message)"
    $script:ListPages = $null; $script:ListedSessions = @(); $script:ListThrows = $true
    $refused = $null; $script:Calls.Clear()
    try { $null = New-DevinCloudSession -Config $config -Prompt 'x' -RunId 'sh4969-counterr' } catch { $refused = $_.Exception }
    Check 'a failed active-session count fails closed with exit 3' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3 -and @($script:Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 0) "$($refused.Message)"
    $script:ListThrows = $false

    # 8: wait retries transient failures, flags abnormal ends, and honours -After.
    function New-FakeApiError([int]$Status, [bool]$Transient) {
        $e = [InvalidOperationException]::new("devin-cloud API GET /sessions/x failed: HTTP $Status."); $e.Data['ExitCode'] = 1; $e.Data['HttpStatus'] = $Status; $e.Data['Transient'] = $Transient; return $e
    }
    $script:Sleeps.Clear(); $script:StatusSequence.Clear()
    $script:StatusSequence.Enqueue((New-FakeApiError 429 $true))
    $script:StatusSequence.Enqueue((New-FakeApiError 503 $true))
    $script:StatusSequence.Enqueue((New-FakeSession 'devin-t1' 'running' @('agenthub') 'finished'))
    $report = $null; $thrown = $null
    try { $report = Wait-DevinCloudSession -SessionId 'devin-t1' -TimeoutSec 600 -PollSec 5 } catch { $thrown = $_.Exception }
    Check 'wait retries a 429 and a 503 and then reports finished' ($null -eq $thrown -and $report.outcome -eq 'finished' -and $script:Sleeps.Count -eq 2) "$($thrown.Message)"
    $script:StatusSequence.Clear(); $script:StatusSequence.Enqueue((New-FakeApiError 404 $false))
    $thrown = $null
    try { $null = Wait-DevinCloudSession -SessionId 'devin-t2' -TimeoutSec 600 -PollSec 5 } catch { $thrown = $_.Exception }
    Check 'wait does not retry a 404' ($null -ne $thrown -and $thrown.Data['HttpStatus'] -eq 404)
    $codes = [ordered]@{ finished = 0; waiting_for_user = 0; waiting_for_approval = 0; suspended = 4; error = 4; timeout = 4 }
    foreach ($outcome in $codes.Keys) {
        $code = Get-DevinCloudWaitExitCode ([pscustomobject]@{ outcome = $outcome; status = 'running'; status_detail = $null })
        Check "wait outcome $outcome exits $($codes[$outcome])" ($code -eq $codes[$outcome]) "got $code"
    }
    Check 'an exit with an error detail exits 4' ((Get-DevinCloudWaitExitCode ([pscustomobject]@{ outcome = 'exit'; status = 'exit'; status_detail = 'out_of_credits' })) -eq 4)
    Check 'an exit the user asked for exits 0' ((Get-DevinCloudWaitExitCode ([pscustomobject]@{ outcome = 'exit'; status = 'exit'; status_detail = 'user_request' })) -eq 0)

    $script:MessageSequence.Clear()
    $script:MessageSequence.Enqueue(@([pscustomobject]@{ event_id = 'e1'; source = 'devin'; message = 'Which branch?'; created_at = 3 }, [pscustomobject]@{ event_id = 'e2'; source = 'user'; message = 'Use main.'; created_at = 10 }))
    $sent = Send-DevinCloudMessage -SessionId 'devin-w1' -Message 'Use main.'
    Check 'message reports the cutoff for a later wait -After' ($sent.cutoff -eq 10 -and $sent.cutoff_event_id -eq 'e2') ($sent | ConvertTo-Json -Compress)

    $oldThread = @([pscustomobject]@{ event_id = 'e1'; source = 'devin'; message = 'Which branch?'; created_at = 3 }, [pscustomobject]@{ event_id = 'e2'; source = 'user'; message = 'Use main.'; created_at = 10 })
    $newThread = $oldThread + @([pscustomobject]@{ event_id = 'e3'; source = 'devin'; message = 'Which test?'; created_at = 12 })
    foreach ($cut in @('10', 'e2')) {
        $script:Sleeps.Clear(); $script:StatusSequence.Clear(); $script:MessageSequence.Clear(); $script:Calls.Clear()
        $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'waiting_for_user'))
        $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'waiting_for_user'))
        $script:MessageSequence.Enqueue($oldThread); $script:MessageSequence.Enqueue($newThread)
        $report = Wait-DevinCloudSession -SessionId 'devin-w1' -TimeoutSec 600 -PollSec 5 -After $cut
        $polls = @($script:Calls | Where-Object { $_.Method -eq 'GET' -and $_.Path -eq '/sessions/devin-w1' }).Count
        Check "wait -After $cut ignores the stale waiting_for_user and returns on Devin's new message" ($report.outcome -eq 'waiting_for_user' -and $polls -eq 2) "polls=$polls outcome=$($report.outcome)"
    }
    $script:Sleeps.Clear(); $script:StatusSequence.Clear(); $script:MessageSequence.Clear(); $script:Calls.Clear()
    foreach ($detail in @('waiting_for_user', 'working', 'waiting_for_user')) { $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') $detail)) }
    $report = Wait-DevinCloudSession -SessionId 'devin-w1' -TimeoutSec 600 -PollSec 5 -After '10'
    $polls = @($script:Calls | Where-Object { $_.Method -eq 'GET' -and $_.Path -eq '/sessions/devin-w1' }).Count
    Check 'wait -After honours waiting_for_user again after a status change' ($report.outcome -eq 'waiting_for_user' -and $polls -eq 3) "polls=$polls"

    # Final round 1: the cutoff is taken before the POST, so Devin's reply never becomes the cutoff.
    function M([string]$Id, [string]$Source, [int]$At) { [pscustomobject]@{ event_id = $Id; source = $Source; message = "$Source $Id"; created_at = $At } }
    $cases = [ordered]@{
        'a reply appended immediately after the POST' = @{ Before = @((M 'e1' 'devin' 3)); After = @((M 'e1' 'devin' 3), (M 'e2' 'user' 10), (M 'e3' 'devin' 11)); Cut = 3; CutId = 'e1' }
        'a reply in the same second' = @{ Before = @((M 'e1' 'devin' 10)); After = @((M 'e1' 'devin' 10), (M 'e2' 'user' 10), (M 'e3' 'devin' 10)); Cut = 10; CutId = 'e1' }
        'a reply to the first message of an empty thread' = @{ Before = @(); After = @((M 'e2' 'user' 10), (M 'e3' 'devin' 10)); Cut = 0; CutId = $null }
    }
    foreach ($case in $cases.GetEnumerator()) {
        $script:MessagePosted = $false; $script:MessageSequence.Clear()
        $script:ThreadBeforePost = $case.Value.Before; $script:ThreadAfterPost = $case.Value.After
        $sent = Send-DevinCloudMessage -SessionId 'devin-w1' -Message 'Use main.'
        Check "message takes the cutoff before the POST ($($case.Key))" ([string]$sent.cutoff -eq [string]$case.Value.Cut -and [string]$sent.cutoff_event_id -eq [string]$case.Value.CutId) ($sent | ConvertTo-Json -Compress)
        foreach ($cut in @([string]$sent.cutoff, [string]$sent.cutoff_event_id) | Where-Object { $_ }) {
            $script:Sleeps.Clear(); $script:StatusSequence.Clear(); $script:Calls.Clear()
            1..3 | ForEach-Object { $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'waiting_for_user')) }
            $report = $null; $thrown = $null
            try { $report = Wait-DevinCloudSession -SessionId 'devin-w1' -TimeoutSec 2 -PollSec 1 -After $cut } catch { $thrown = $_.Exception }
            Check "wait -After $cut returns waiting_for_user with exit 0 for $($case.Key)" ($null -eq $thrown -and $report.outcome -eq 'waiting_for_user' -and (Get-DevinCloudWaitExitCode $report) -eq 0) "outcome=$($report.outcome) $($thrown.Message)"
        }
    }
    $script:ThreadBeforePost = $null; $script:ThreadAfterPost = $null

    # Final round 2: the message read pages to completion, fails closed, and is retried inside wait.
    $script:MessagePages = @(for ($i = 0; $i -lt 12; $i++) { [pscustomobject]@{ items = @((M "e$i" 'devin' $i)); has_next_page = ($i -lt 11); end_cursor = $(if ($i -lt 11) { "p$($i + 1)" } else { $null }) } })
    $thread = @(Get-DevinCloudMessages -SessionId 'devin-w1')
    Check 'messages beyond page 10 are read' ($thread.Count -eq 12 -and $thread[-1].event_id -eq 'e11') "count=$($thread.Count)"
    $script:MessagePages = @([pscustomobject]@{ items = @(); has_next_page = $true; end_cursor = $null })
    $refused = $null
    try { $null = Get-DevinCloudMessages -SessionId 'devin-w1' } catch { $refused = $_.Exception }
    Check 'a message page promising more without a cursor fails closed with exit 3' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3) "$($refused.Message)"
    $script:MessagePages = $null
    $script:Sleeps.Clear(); $script:StatusSequence.Clear(); $script:MessageSequence.Clear(); $script:MessageErrors.Clear()
    1..2 | ForEach-Object { $script:StatusSequence.Enqueue((New-FakeSession 'devin-w1' 'running' @('agenthub') 'waiting_for_user')) }
    $script:MessageErrors.Enqueue((New-FakeApiError 503 $true))
    $script:MessageSequence.Enqueue($newThread)
    $report = $null; $thrown = $null
    try { $report = Wait-DevinCloudSession -SessionId 'devin-w1' -TimeoutSec 600 -PollSec 5 -After 'e2' } catch { $thrown = $_.Exception }
    Check 'wait -After retries a transient failure reading messages' ($null -eq $thrown -and $report.outcome -eq 'waiting_for_user' -and $script:Sleeps.Count -eq 1) "$($thrown.Message) sleeps=$($script:Sleeps.Count)"

    # 10: a key persisted in the User or Machine environment is refused; a Process-only override is consumed.
    $env:DEVIN_CLOUD_API_KEY = $syntheticKey
    function Get-DevinCloudPersistedKeyScopes { param([string]$Name) return @('User') }
    $refused = $null
    try { $null = Resolve-DevinCloudKey -Config $config } catch { $refused = $_.Exception }
    Check 'a User-scope DEVIN_CLOUD_API_KEY is refused with exit 3 and a removal instruction' ($null -ne $refused -and $refused.Data['ExitCode'] -eq 3 -and $refused.Message -match 'User' -and $refused.Message -match 'remove' -and $refused.Message -notmatch [regex]::Escape($syntheticKey)) "$($refused.Message)"
    function Get-DevinCloudPersistedKeyScopes { param([string]$Name) return @() }
    $env:DEVIN_CLOUD_API_KEY = $syntheticKey
    $resolved = Resolve-DevinCloudKey -Config $config
    Check 'a Process-only override is used and then removed from the environment children inherit' ($resolved -eq $syntheticKey -and [string]::IsNullOrEmpty($env:DEVIN_CLOUD_API_KEY))
    $env:DEVIN_CLOUD_API_KEY = $null

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
# Captured before the adapter consumes the in-process override.
`$script:EchoKey = `$env:DEVIN_CLOUD_API_KEY
function Invoke-DevinApi {
    param([string]`$Method, [string]`$Path, [hashtable]`$Query, `$Body)
    if (`$Method -eq 'GET') { return [pscustomobject]@{ items = @(); has_next_page = `$false } }
    if (`$env:MOCK_ECHO_KEY) { throw ('401 Unauthorized for bearer ' + `$script:EchoKey) }
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

    # --- Loopback endpoint: the real Invoke-DevinApi against 127.0.0.1 (plain
    # http is accepted for loopback only). The server logs method, path, body and
    # whether the bearer matched; never the header itself. ---
    $serverJs = Join-Path $fixture 'loopback.cjs'
    $requestLog = Join-Path $fixture 'requests.jsonl'
    @'
const http = require('node:http'); const fs = require('node:fs');
const log = process.argv[2]; const expected = 'Bearer ' + process.argv[3];
const sess = (id, st, d) => ({ session_id: id, url: 'https://app.devin.ai/sessions/' + id, status: st, status_detail: d, tags: ['agenthub'], org_id: 'o', created_at: 1, updated_at: 2, acus_consumed: 0, pull_requests: [] });
const srv = http.createServer((req, res) => { let b = ''; req.on('data', c => b += c); req.on('end', () => {
  const p = new URL(req.url, 'http://x').pathname.replace(/^\/v3\/organizations\/[^/]+/, '');
  fs.appendFileSync(log, JSON.stringify({ m: req.method, p, body: b, auth: req.headers.authorization === expected }) + '\n');
  let code = 200, out;
  if (/^\/sessions\/devin-503/.test(p)) { code = 503; out = { detail: 'busy' }; }
  else if (/^\/sessions\/devin-404/.test(p)) { code = 404; out = { detail: 'not found' }; }
  else if (p === '/sessions' && req.method === 'GET') out = { items: [], end_cursor: null, has_next_page: false, total: 0 };
  else if (p === '/sessions' && req.method === 'POST') out = sess('devin-loop0001', 'new', null);
  else if (/\/messages$/.test(p) && req.method === 'GET') out = { items: [{ event_id: 'e1', source: 'user', message: 'hi', created_at: 100 }], end_cursor: null, has_next_page: false };
  else if (/\/messages$/.test(p)) out = sess('devin-loop0001', 'running', 'working');
  else if (req.method === 'DELETE') out = sess('devin-loop0001', 'exit', 'user_request');
  else out = sess('devin-loop0001', 'running', 'finished');
  res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(out)); }); });
srv.listen(0, '127.0.0.1', () => console.log(srv.address().port));
'@ | Set-Content -LiteralPath $serverJs -Encoding UTF8
    $node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    $serverInfo = [Diagnostics.ProcessStartInfo]::new()
    $serverInfo.FileName = $node
    $serverInfo.Arguments = (@($serverJs, $requestLog, $syntheticKey) | ForEach-Object { Quote $_ }) -join ' '
    $serverInfo.UseShellExecute = $false; $serverInfo.CreateNoWindow = $true; $serverInfo.RedirectStandardOutput = $true
    $server = [Diagnostics.Process]::Start($serverInfo)
    try {
        $portTask = $server.StandardOutput.ReadLineAsync()
        if (-not $portTask.Wait(15000)) { throw 'loopback server did not report a port' }
        $port = [int]$portTask.Result
        $loopFleet = $liveFleet | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $loopFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization.apiBase = "http://127.0.0.1:$port/v3"
        $loopFleet | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8

        # 1: every action under -Debug and -Verbose, through the entry script and
        # with streams 1-6 merged in-process; the synthetic key must appear nowhere.
        $actions = [ordered]@{
            create = @('-Prompt', 'ok', '-RunId', 'sh4969-dbg', '-Repo', 'o/r')
            status = @('-SessionId', 'devin-loop0001')
            messages = @('-SessionId', 'devin-loop0001')
            message = @('-SessionId', 'devin-loop0001', '-Message', 'hi')
            stop = @('-SessionId', 'devin-loop0001')
            wait = @('-SessionId', 'devin-loop0001', '-TimeoutSec', '5', '-PollSec', '1')
            list = @()
        }
        foreach ($action in $actions.Keys) {
            $r = Run-Child (@('-NoProfile', '-NonInteractive', '-File', $entryPath, '-Action', $action) + $actions[$action] + @('-Debug', '-Verbose', '-InformationAction', 'Continue')) $envKey
            Check "$action under -Debug -Verbose succeeds against the loopback endpoint" ($r.Exit -eq 0) "exit=$($r.Exit) err=$(Protect-DevinCloudText $r.Err)"
            Check "$action under -Debug -Verbose never prints the key" (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey) -and ($r.Out + $r.Err) -notmatch '\*\*\*\*WXYZ')
            $argText = (@($actions[$action]) | ForEach-Object { if ($_ -match '^-[A-Za-z]+$') { $_ } else { "'" + $_.Replace("'", "''") + "'" } }) -join ' '
            $merged = @"
`$ErrorActionPreference = 'Stop'
. '$($libPath.Replace("'", "''"))'
`$all = & { Invoke-DevinCloudMain -Action $action $argText -Debug -Verbose -InformationAction Continue -WarningAction Continue } *>&1 | Out-String -Width 4096
[Console]::Out.Write(`$all)
"@
            $r = Run-Encoded $merged $envKey
            Check "$action with streams 1-6 merged never carries the key" (($r.Out + $r.Err) -notmatch [regex]::Escape($syntheticKey)) ''
        }
        $logged = @(Get-Content -LiteralPath $requestLog -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
        Check 'the loopback endpoint saw authenticated requests for every action' ($logged.Count -ge 7 -and @($logged | Where-Object { -not $_.auth }).Count -eq 0) "requests=$($logged.Count)"

        # 8: the real HTTP function marks 429, 5xx and transport failures transient, and 404 not.
        $classify = @"
. '$($libPath.Replace("'", "''"))'
`$config = Get-DevinCloudConfig -Fleet (Get-DevinCloudFleet)
Set-DevinCloudContext -Config `$config -Key `$env:DEVIN_CLOUD_API_KEY
foreach (`$id in @('devin-503aa', 'devin-404aa')) {
    try { `$null = Get-DevinCloudSession -SessionId `$id } catch { [Console]::Out.WriteLine(`$id + '=' + `$_.Exception.Data['HttpStatus'] + ':' + `$_.Exception.Data['Transient']) }
}
"@
        $r = Run-Encoded $classify $envKey
        Check 'Invoke-DevinApi marks a 503 transient and a 404 not' ($r.Out -match 'devin-503aa=503:True' -and $r.Out -match 'devin-404aa=404:False') "$($r.Out) $($r.Err)"

        # 2: the adapter's git child never sees DEVIN_CLOUD_API_KEY.
        $fakeGit = Join-Path $fixture 'bin-git'; $gitReport = Join-Path $fixture 'git-env.txt'
        $null = New-Item -ItemType Directory -Path $fakeGit -Force
        if ($env:OS -eq 'Windows_NT') {
            [IO.File]::WriteAllText((Join-Path $fakeGit 'git.cmd'), "@echo off`r`nif defined DEVIN_CLOUD_API_KEY (echo present>`"$gitReport`") else (echo absent>`"$gitReport`")`r`necho https://github.com/fixture-owner/fixture-repo.git`r`n")
        } else {
            [IO.File]::WriteAllText((Join-Path $fakeGit 'git'), "#!/bin/sh`nif [ -n `"`${DEVIN_CLOUD_API_KEY+x}`" ]; then echo present > '$gitReport'; else echo absent > '$gitReport'; fi`necho https://github.com/fixture-owner/fixture-repo.git`n")
            [IO.File]::SetUnixFileMode((Join-Path $fakeGit 'git'), [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
        }
        $envGit = $envKey.Clone(); $envGit.PATH = $fakeGit + $sep + $env:PATH
        $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $entryPath, '-Action', 'create', '-Prompt', 'derive my repo', '-RunId', 'sh4969-git', '-Cwd', $fixture) $envGit
        $posted = @(Get-Content -LiteralPath $requestLog -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.m -eq 'POST' -and $_.p -eq '/sessions' -and $_.body -match 'derive my repo' })
        Check 'create derives the repo from the git remote' ($r.Exit -eq 0 -and $posted.Count -eq 1 -and $posted[0].body -match 'fixture-owner/fixture-repo') "exit=$($r.Exit) $($r.Err)"
        Check "the adapter's git child does not inherit DEVIN_CLOUD_API_KEY" ((Test-Path -LiteralPath $gitReport) -and ([IO.File]::ReadAllText($gitReport)).Trim() -eq 'absent') $(if (Test-Path -LiteralPath $gitReport) { [IO.File]::ReadAllText($gitReport) } else { 'no report' })

        # 7: through the entry script, a fractional or exponent -MaxAcu refuses before any request.
        foreach ($bad in @('2.5', '1e3', 'abc')) {
            $before = @(Get-Content -LiteralPath $requestLog -Encoding UTF8).Count
            $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $entryPath, '-Action', 'create', '-Prompt', 'ok', '-RunId', 'sh4969-acu', '-Repo', 'o/r', '-MaxAcu', $bad) $envKey
            Check "the entry script refuses -MaxAcu $bad with exit 3 and no request" ($r.Exit -eq 3 -and @(Get-Content -LiteralPath $requestLog -Encoding UTF8).Count -eq $before) "exit=$($r.Exit) $($r.Err)"
        }
    } finally {
        try { $server.Kill() } catch { }
        $server.Dispose()
    }

    # 4: creates are serialized by a machine-wide mutex, so dedupe and the cap hold under a race.
    $raceState = Join-Path $fixture 'race-state.json'; $racePosts = Join-Path $fixture 'race-posts.txt'
    $raceScript = @"
`$ErrorActionPreference = 'Stop'
. '$($libPath.Replace("'", "''"))'
function Invoke-DevinApi {
    param([string]`$Method, [string]`$Path, [hashtable]`$Query, `$Body)
    if (`$Method -eq 'GET' -and `$Path -eq '/sessions') {
        `$items = @([IO.File]::ReadAllText(`$env:RACE_STATE) | ConvertFrom-Json)
        Start-Sleep -Milliseconds 1500
        return [pscustomobject]@{ items = `$items; has_next_page = `$false; end_cursor = `$null }
    }
    if (`$Method -eq 'POST') {
        for (`$try = 0; `$try -lt 50; `$try++) { try { [IO.File]::AppendAllText(`$env:RACE_POSTS, "post`n"); break } catch [IO.IOException] { Start-Sleep -Milliseconds 20 } }
        `$items = @([IO.File]::ReadAllText(`$env:RACE_STATE) | ConvertFrom-Json)
        `$new = [pscustomobject]@{ session_id = 'devin-r' + [guid]::NewGuid().ToString('n').Substring(0, 8); url = 'https://app.devin.ai/sessions/x'; status = 'new'; tags = @(`$Body.tags); created_at = 5 }
        [IO.File]::WriteAllText(`$env:RACE_STATE, (ConvertTo-Json -InputObject @(`$items + `$new) -Depth 5))
        return `$new
    }
    throw "unexpected `$Method `$Path"
}
exit (Invoke-DevinCloudMain -Action create -Prompt 'race' -RunId `$env:RACE_RUN -Repo 'o/r')
"@
    $raceEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($raceScript))
    function Start-RaceChild([string]$RunId) {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $pwsh; $psi.Arguments = "-NoProfile -NonInteractive -EncodedCommand $raceEncoded"
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        foreach ($name in $envKey.Keys) { if ($null -eq $envKey[$name]) { [void]$psi.EnvironmentVariables.Remove($name) } else { $psi.EnvironmentVariables[$name] = [string]$envKey[$name] } }
        $psi.EnvironmentVariables['RACE_STATE'] = $raceState; $psi.EnvironmentVariables['RACE_POSTS'] = $racePosts; $psi.EnvironmentVariables['RACE_RUN'] = $RunId
        $p = [Diagnostics.Process]::Start($psi)
        return [pscustomobject]@{ P = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
    }
    function Wait-RaceChild($Child) {
        if (-not $Child.P.WaitForExit(90000)) { $Child.P.Kill(); throw 'race child exceeded 90 seconds' }
        $result = [pscustomobject]@{ Exit = $Child.P.ExitCode; Out = $Child.Out.GetAwaiter().GetResult(); Err = $Child.Err.GetAwaiter().GetResult() }
        $Child.P.Dispose(); return $result
    }
    [IO.File]::WriteAllText($raceState, '[]'); [IO.File]::WriteAllText($racePosts, '')
    $one = Start-RaceChild 'sh4969-race'; $two = Start-RaceChild 'sh4969-race'
    $results = @((Wait-RaceChild $one), (Wait-RaceChild $two))
    $postCount = @([IO.File]::ReadAllLines($racePosts) | Where-Object { $_ }).Count
    Check 'two parallel creates with one run id make one POST' ($postCount -eq 1 -and @($results | Where-Object { $_.Exit -eq 0 }).Count -eq 2 -and @($results | Where-Object { $_.Out -match '"deduplicated":true' }).Count -eq 1) "posts=$postCount exits=$(@($results.Exit) -join ',') $(@($results.Err) -join ' | ')"
    [IO.File]::WriteAllText($raceState, '[{"session_id":"devin-busy1","status":"running","tags":["agenthub","run:x1"],"created_at":1},{"session_id":"devin-busy2","status":"running","tags":["agenthub","run:x2"],"created_at":1}]')
    [IO.File]::WriteAllText($racePosts, '')
    $one = Start-RaceChild 'sh4969-cap-a'; $two = Start-RaceChild 'sh4969-cap-b'
    $results = @((Wait-RaceChild $one), (Wait-RaceChild $two))
    $postCount = @([IO.File]::ReadAllLines($racePosts) | Where-Object { $_ }).Count
    Check 'with 2 sessions active, parallel creates stop at the cap of 3' ($postCount -eq 1 -and @($results | Where-Object { $_.Exit -eq 3 -and $_.Err -match 'cap is 3' }).Count -eq 1) "posts=$postCount exits=$(@($results.Exit) -join ',') $(@($results.Err) -join ' | ')"

    # --- Registry records the adapter depends on. ---
    $mcps = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $devinMcp = @($mcps.mcpServers | Where-Object { $_.id -eq 'devin' })
    Check 'registry/mcps.json carries one devin server' ($devinMcp.Count -eq 1)
    if ($devinMcp.Count -eq 1) {
        $m = $devinMcp[0]
        Check 'devin MCP is the official Streamable HTTP endpoint' ($m.url -eq 'https://mcp.devin.ai/mcp' -and $m.transport -eq 'http' -and $m.activationMode -eq 'shared-remote')
        # Owner direction 2026-11-19: no persisted secret and no key-bearing env var in a host config.
        Check 'devin MCP carries no static or env-expanded auth header' ($null -eq $m.headers -and ($m | ConvertTo-Json -Depth 10) -notmatch '\$\{env:|\{env:|DEVIN_CLOUD_API_KEY|DEVIN_API_KEY|cog_[A-Za-z0-9_-]{8,}')
        Check 'devin MCP authenticates through the same native headers helper on both hosts' ($m.credentialPolicy -eq 'native-headers-helper' -and [string]$m.headersHelper.claude -match 'Get-DevinMcpHeaders\.ps1' -and $m.headersHelper.codex -ceq $m.headersHelper.claude)
        Check 'devin MCP is declared for Claude and Codex with native exceptions' ((@($m.hosts | Sort-Object) -join ',') -eq 'claude,codex' -and -not [string]::IsNullOrWhiteSpace([string]$mcps.activationPolicy.pluginOnly.hosts.claude.devin) -and -not [string]::IsNullOrWhiteSpace([string]$mcps.activationPolicy.pluginOnly.hosts.codex.devin))
        Check 'devin MCP is owner-configured' ([string]$m.scope -eq 'owner-configured')
        # A revision is accepted only when its verification records the authenticated probe that returned it.
        $protoOk = if ($null -eq $m.protocol.revision) { [string]$m.protocol.verification -match 'cannot be established' } else { ([string]$m.protocol.revision -match '^\d{4}-\d{2}-\d{2}$') -and ([string]$m.protocol.verification -match 'Authenticated probe') -and ([string]$m.protocol.verification -match ('protocolVersion ' + [regex]::Escape([string]$m.protocol.revision))) }
        Check 'devin MCP records no invented protocol verification (null, or a revision backed by a recorded authenticated probe)' ($protoOk -and [string]$m.notes -match 'docs\.devin\.ai/work-with-devin/devin-mcp')
        # 6: the MCP client holds the raw key, so the adapter's caps do not apply there.
        # Final round 4: only documented limits are named as the backstop, and none is claimed as set.
        Check 'devin MCP notes name only documented ACU limits and claim no per-session limit is set' ([string]$m.notes -match 'enforced only by the dispatcher adapter' -and [string]$m.notes -match 'max_acu_limit 10' -and [string]$m.notes -match 'docs\.devin\.ai/admin/billing/org-acu-limits' -and [string]$m.notes -match 'docs\.devin\.ai/admin/billing/user-acu-limits' -and [string]$m.notes -match 'max_session_acu_limit' -and [string]$m.notes -match 'not yet set' -and [string]$m.notes -notmatch 'default session spending limit')
    }

    # --- The MCP headers helper: op read at connect time, headers on stdout only. ---
    $helperPath = Join-Path $dispatchDir 'Get-DevinMcpHeaders.ps1'
    Check 'the Devin MCP headers helper exists' (Test-Path -LiteralPath $helperPath -PathType Leaf) $helperPath
    $helperFixture = Join-Path $fixture 'helper'
    $null = New-Item -ItemType Directory -Path $helperFixture
    Copy-Item -LiteralPath $helperPath -Destination $helperFixture
    $helperLib = [IO.File]::ReadAllText($libPath) + "`nfunction Get-DevinMcpCacheDirectory { return (Join-Path `$env:AGENTHUB_ROOT 'mcp-cache') }`n"
    [IO.File]::WriteAllText((Join-Path $helperFixture 'DevinCloudLib.ps1'), $helperLib)
    $helperPath = Join-Path $helperFixture 'Get-DevinMcpHeaders.ps1'
    $liveFleet | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $helperPath) $envOp
    $headers = if ($r.Exit -eq 0) { try { $r.Out | ConvertFrom-Json } catch { $null } } else { $null }
    Check 'the helper prints the Authorization and X-Org-Id headers as one JSON object' ($null -ne $headers -and $headers.Authorization -eq "Bearer $syntheticKey" -and $headers.'X-Org-Id' -eq $liveFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization.orgId -and @($headers.PSObject.Properties).Count -eq 2) "exit=$($r.Exit) err=$($r.Err)"
    Check 'the helper keeps the key off stderr' ($r.Err -notmatch [regex]::Escape($syntheticKey))
    $r = Run-Child @('-NoProfile', '-NonInteractive', '-File', $helperPath) $envNoToken
    Check 'the helper refuses with exit 3 and no headers when the service-account token is unset' ($r.Exit -eq 3 -and [string]::IsNullOrWhiteSpace($r.Out) -and $r.Err -match 'OP_SERVICE_ACCOUNT_TOKEN') "exit=$($r.Exit) err=$($r.Err)"
    $leaks = @(Get-ChildItem -LiteralPath $fixture -Recurse -File | Where-Object { $_.Directory.FullName -notin @($failingOp, $keyOp, (Join-Path $fixture 'mcp-cache')) } |
        Where-Object { [IO.File]::ReadAllText($_.FullName).Contains($syntheticKey) } | ForEach-Object { $_.FullName })
    Check 'the helper writes the key to no file outside its protected cache' ($leaks.Count -eq 0) ($leaks -join '; ')
    $hostsDoc = [IO.File]::ReadAllText((Join-Path $dispatchDir 'references\hosts.md'))
    $planDoc = [IO.File]::ReadAllText((Join-Path $repoRoot 'docs\plans\active\devin-peer-orchestration.md'))
    foreach ($doc in @(@{ Name = 'hosts.md'; Text = $hostsDoc }, @{ Name = 'devin-peer-orchestration.md'; Text = $planDoc })) {
        Check "$($doc.Name) uses the documented Linear wording" ($doc.Text -match 'Assign the ticket to Devin' -and $doc.Text -notmatch 'delegate to the "Devin" app user') ''
        Check "$($doc.Name) says the MCP lane is not capped by the adapter and names only documented limits" ($doc.Text -match 'enforced only by the dispatcher adapter' -and $doc.Text -match 'admin/billing/org-acu-limits' -and $doc.Text -match 'admin/billing/user-acu-limits' -and $doc.Text -match 'max_session_acu_limit' -and $doc.Text -match 'not yet set' -and $doc.Text -notmatch 'default session spending limit') ''
        Check "$($doc.Name) documents the wait exit codes and -After" ($doc.Text -match '-After' -and $doc.Text -match 'exit 4|exits 4') ''
    }
    $cloudAuth = $liveFleet.dispatchPolicy.'devin-cloud'.cloudBudgetAuthorization
    Check 'the fleet-profile ACU note names only documented limits and claims no per-session limit is set' ([string]$cloudAuth.defaultMaxAcuLimitNote -match 'org-acu-limits' -and [string]$cloudAuth.defaultMaxAcuLimitNote -match 'user-acu-limits' -and [string]$cloudAuth.defaultMaxAcuLimitNote -match 'max_session_acu_limit' -and [string]$cloudAuth.defaultMaxAcuLimitNote -match 'not yet set' -and [string]$cloudAuth.defaultMaxAcuLimitNote -notmatch 'default session spending limit')
    # Final round 3: the orchestrator's live run is recorded as orchestrator-verified.
    $cloudReason = [string]$liveFleet.dispatchPolicy.'devin-cloud'.reason
    Check 'devin-cloud records the orchestrator-verified live run' ($cloudReason -match 'orchestrator-verified' -and $cloudReason -match 'ba31db7d8d394a7dbeb38009dd1310a4' -and $cloudReason -match 'max_acu_limit 2' -and $cloudReason -match 'deduplicated' -and $cloudReason -match 'waiting_for_user' -and $cloudReason -match '13' -and $cloudReason -match 'acus_consumed 0\.0' -and $cloudReason -notmatch 'No session has been created') $cloudReason
    $localPolicy = $liveFleet.dispatchPolicy.devin
    Check 'the local Devin lane stays local-only and points cloud work at devin-cloud' ([string]$localPolicy.scope -match '^local-only' -and [string]$localPolicy.scope -match 'devin-cloud')
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ((Test-Path -LiteralPath $resolved) -and $resolved.StartsWith([IO.Path]::GetFullPath(([IO.Path]::GetTempPath())).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
