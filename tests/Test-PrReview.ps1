#Requires -Version 5.1
<# Synthetic gh and dispatcher only. No network, no GitHub, no model run.
   Covers the SH-4416 ready-only PR reviewer: draft refusal, idempotence,
   stale PASS status, malformed answer retry then BLOCKED, oversized diff
   per-file grouping, author-host routing, and that no write command
   (gh pr merge, gh pr review --approve, git push) is ever issued. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path $repoRoot 'packages\coding-agent-dispatch'
$reviewerScript = Join-Path $packageRoot 'reviewer\Invoke-PrReview.ps1'
$libPath = Join-Path $packageRoot 'reviewer\PrReviewLib.ps1'

$failed = 0; $checked = 0
function Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:checked++
    if ($Passed) { Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name -- $Detail" }
}

$node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $node) { Write-Host 'FAIL: node is required by the synthetic stubs'; exit 1 }
$pwsh = (Get-Process -Id $PID).Path

$repo = 'owner/repo'
$headMain = ('aa11' * 10)
$headNext = ('bb22' * 10)
$riFile = $null
$fixture = $null

function Quote([string]$Value) {
    $v = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    return '"' + ([regex]::Replace($v, '(\\+)$', '$1$1')) + '"'
}

function Run-Reviewer([string[]]$Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.Arguments = ((@('-NoProfile', '-File', $reviewerScript) + $Arguments | ForEach-Object { Quote $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false); $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { $p.Kill(); throw 'reviewer run exceeded 60 seconds' }
    $result = [pscustomobject]@{ Exit = $p.ExitCode; Out = $o.GetAwaiter().GetResult(); Err = $e.GetAwaiter().GetResult() }
    $p.Dispose(); return $result
}

function Read-JsonLines([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $lines = @([IO.File]::ReadAllLines($Path) | Where-Object { $_.Trim() })
    return @($lines | ForEach-Object { $_ | ConvertFrom-Json })
}

function New-Scenario {
    param([string]$Name)
    $dir = Join-Path $fixture ("scn-" + $Name)
    $null = New-Item -ItemType Directory -Path $dir -Force
    return $dir
}

function Write-Scenario {
    param(
        [string]$Dir,
        [bool]$Draft = $false,
        [string]$Head = $headMain,
        [string]$Branch = 'feature/thing',
        [string]$Body = 'Does the thing. SH-4416',
        [object[]]$Comments = @(),
        [string]$Diff = '',
        [bool]$HasAgentsMd = $true,
        [string[]]$Responses = @('{"verdict":"PASS","head":"' + $headMain + '","findings":[],"summary":"ok","covered":["all"],"notCovered":[]}')
    )
    $view = [ordered]@{
        number = 7
        title = 'Add the thing'
        body = $Body
        state = 'OPEN'
        isDraft = $Draft
        headRefName = $Branch
        headRefOid = $Head
        baseRefName = 'main'
        author = @{ login = 'someone' }
        comments = $Comments
    }
    [IO.File]::WriteAllText((Join-Path $Dir 'pr-view.json'), ($view | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Dir 'pr-diff.txt'), $Diff, [Text.UTF8Encoding]::new($false))
    if ($HasAgentsMd) {
        $content = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes('AGENTS-MD-FIXTURE-CONTENT'))
        $api = @{ content = $content; encoding = 'base64' } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText((Join-Path $Dir 'agents-md.json'), $api, [Text.UTF8Encoding]::new($false))
    }
    [IO.File]::WriteAllText((Join-Path $Dir 'responses.json'), (ConvertTo-Json -InputObject @($Responses) -Depth 5), [Text.UTF8Encoding]::new($false))
}

try {
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('prreview fixture ' + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $fixture -Force
    $stubGh = Join-Path $fixture 'gh-stub.cjs'
    $stubDispatch = Join-Path $fixture 'dispatcher-stub.cjs'
    [IO.File]::WriteAllText($stubGh, @'
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const dir = process.env.PRREVIEW_GH_DIR || '.';
const logPath = path.join(dir, 'gh-log.jsonl');
let body = null;
const bi = args.indexOf('--body-file');
if (bi >= 0 && args[bi + 1] && fs.existsSync(args[bi + 1])) body = fs.readFileSync(args[bi + 1], 'utf8');
fs.appendFileSync(logPath, JSON.stringify({ args: args, body: body }) + '\n');
function emit(file) {
  const p = path.join(dir, file);
  if (fs.existsSync(p)) process.stdout.write(fs.readFileSync(p, 'utf8'));
}
if (args[0] === 'pr' && args[1] === 'view') { emit('pr-view.json'); }
else if (args[0] === 'pr' && args[1] === 'diff') { emit('pr-diff.txt'); }
else if (args[0] === 'pr' && args[1] === 'comment') { /* success, no output */ }
else if (args[0] === 'api') {
  if (!fs.existsSync(path.join(dir, 'agents-md.json'))) process.exit(1);
  emit('agents-md.json');
}
else { process.exit(1); }
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stubDispatch, @'
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const dir = process.env.PRREVIEW_DISPATCH_DIR || '.';
const logPath = path.join(dir, 'dispatcher-log.jsonl');
const pi = args.indexOf('-PromptFile');
let prompt = null;
if (pi >= 0 && args[pi + 1] && fs.existsSync(args[pi + 1])) prompt = fs.readFileSync(args[pi + 1], 'utf8');
const hi = args.indexOf('-HostId');
const mi = args.indexOf('-Model');
fs.appendFileSync(logPath, JSON.stringify({ args: args, prompt: prompt, host: hi >= 0 ? args[hi + 1] : null, model: mi >= 0 ? args[mi + 1] : null }) + '\n');
const responsesFile = path.join(dir, 'responses.json');
let responses = [];
if (fs.existsSync(responsesFile)) responses = JSON.parse(fs.readFileSync(responsesFile, 'utf8'));
const lines = fs.readFileSync(logPath, 'utf8').trim().split('\n').filter(Boolean);
const index = lines.length - 1;
const response = index < responses.length ? responses[index] : (responses.length ? responses[responses.length - 1] : '');
if (response === '!EXIT3') process.exit(3);
process.stdout.write(response);
'@, [Text.UTF8Encoding]::new($false))
    $ghCmd = Join-Path $fixture 'gh.cmd'
    [IO.File]::WriteAllText($ghCmd, "@echo off`r`n`"$node`" `"$stubGh`" %*`r`n")
    $dispCmd = Join-Path $fixture 'dispatcher.cmd'
    [IO.File]::WriteAllText($dispCmd, "@echo off`r`n`"$node`" `"$stubDispatch`" %*`r`n")

    $riFile = Join-Path $fixture 'reviewer-instructions.md'
    [IO.File]::WriteAllText($riFile, 'REVIEWER-INSTRUCTIONS-FIXTURE: fresh-context reviewer, read-only.', [Text.UTF8Encoding]::new($false))
    $validAnswer = @{ verdict = 'PASS'; head = $headMain; findings = @(@{ severity = 'minor'; confidence = 'high'; file = 'src/a.js'; line = 12; reproduction = 'npm test'; fix = 'rename variable' }); summary = 'looks good'; covered = @('src/a.js'); notCovered = @() } | ConvertTo-Json -Compress -Depth 5

    # ---------- unit tests: pure functions ----------
    if (Test-Path -LiteralPath $libPath) {
        . $libPath
        $key = Get-PrReviewIdempotenceKey -Repo $repo -PrNumber 7 -HeadSha $headMain -Trigger 'manual'
        Check 'idempotence key format' ($key -eq "agenthub-pr-review|$repo|7|$headMain|manual") $key
        $marker = Get-PrReviewMarker -Key $key -Verdict 'PASS'
        Check 'marker hides key and verdict in an HTML comment' ($marker -match '^<!--' -and $marker -match [regex]::Escape($key) -and $marker -match 'verdict="PASS"') $marker

        $r = Get-PrReviewTriggerAction -Action 'opened' -Draft $false -Key $key -ReviewedKeys @()
        Check 'trigger: opened non-draft reviews' ($r.Action -eq 'review') ($r | Out-String)
        $r = Get-PrReviewTriggerAction -Action 'ready_for_review' -Draft $false -Key $key -ReviewedKeys @()
        Check 'trigger: ready_for_review reviews' ($r.Action -eq 'review') ($r | Out-String)
        $r = Get-PrReviewTriggerAction -Action 'synchronize' -Draft $false -Key $key -ReviewedKeys @()
        Check 'trigger: synchronize skips' ($r.Action -eq 'skip' -and $r.Reason -match 'synchronize') ($r | Out-String)
        $r = Get-PrReviewTriggerAction -Action 'opened' -Draft $true -Key $key -ReviewedKeys @()
        Check 'trigger: draft opened skips' ($r.Action -eq 'skip' -and $r.Reason -match 'draft') ($r | Out-String)
        $r = Get-PrReviewTriggerAction -Action 'manual' -Draft $false -Key $key -ReviewedKeys @()
        Check 'trigger: manual reviews' ($r.Action -eq 'review') ($r | Out-String)
        $r = Get-PrReviewTriggerAction -Action 'manual' -Draft $false -Key $key -ReviewedKeys @($key)
        Check 'trigger: replayed key skips a second review' ($r.Action -eq 'skip' -and $r.Reason -match 'duplicate') ($r | Out-String)

        Check 'author host from body marker' ((Get-PrReviewAuthorHost -BranchName '' -Body '[host: codex]') -eq 'codex')
        Check 'author host from branch prefix' ((Get-PrReviewAuthorHost -BranchName 'claude/fix-thing' -Body '') -eq 'claude')
        Check 'body marker wins over branch prefix' ((Get-PrReviewAuthorHost -BranchName 'codex/fix' -Body '[host: claude]') -eq 'claude')
        Check 'unknown author host is empty' ((Get-PrReviewAuthorHost -BranchName 'worktree-task' -Body 'plain body') -eq '')
        Check 'unknown marker name is ignored' ((Get-PrReviewAuthorHost -BranchName '' -Body '[host: notahost]') -eq '')

        $answer = '{"verdict":"PASS","head":"' + $headMain + '","findings":[{"severity":"minor","confidence":"high","file":"src/a.js","line":12,"reproduction":"npm test","fix":"rename"}],"summary":"s","covered":["a"],"notCovered":[]}'
        $parsed = ConvertFrom-PrReviewAnswer -Text $answer -ExpectedHeadSha $headMain
        Check 'answer parser accepts raw JSON' ($null -ne $parsed -and $parsed.verdict -eq 'PASS' -and @($parsed.findings).Count -eq 1) ($answer)
        $parsed = ConvertFrom-PrReviewAnswer -Text "some prose`n``````json`n$answer`n```````nmore prose" -ExpectedHeadSha $headMain
        Check 'answer parser accepts a fenced JSON block' ($null -ne $parsed -and $parsed.verdict -eq 'PASS') ($parsed | Out-String)
        Check 'answer parser rejects a wrong head' ($null -eq (ConvertFrom-PrReviewAnswer -Text $answer -ExpectedHeadSha $headNext))
        Check 'answer parser rejects an invalid verdict' ($null -eq (ConvertFrom-PrReviewAnswer -Text ('{"verdict":"MAYBE","head":"' + $headMain + '"}') -ExpectedHeadSha $headMain))
        Check 'answer parser rejects a finding without reproduction' ($null -eq (ConvertFrom-PrReviewAnswer -Text ('{"verdict":"PASS","head":"' + $headMain + '","findings":[{"severity":"minor","confidence":"high","file":"a.js","line":1,"fix":"x"}]}') -ExpectedHeadSha $headMain))

        $commentBody = "some summary text`n" + (Get-PrReviewMarker -Key $key -Verdict 'PASS') + "`ntail"
        $tool = Get-PrReviewToolComments -Comments @(@{ author = @{ login = 'app-bot' }; body = $commentBody }) -Repo $repo -PrNumber 7
        Check 'tool comments parse key, head and verdict from the marker' (@($tool).Count -eq 1 -and $tool[0].HeadSha -eq $headMain -and $tool[0].Verdict -eq 'PASS' -and $tool[0].Trigger -eq 'manual') ($tool | Out-String)

        $sections = 1..6 | ForEach-Object {
            "diff --git a/file$_.txt b/file$_.txt`n--- a/file$_.txt`n+++ b/file$_.txt`n" + (('x' * 600) + "`n")
        }
        $split = Split-PrReviewDiff -DiffText ($sections -join '') -MaxChars 1000 -MaxGroups 4
        Check 'chunker splits an oversized diff into bounded groups' (@($split.Groups).Count -eq 4 -and @($split.NotCovered).Count -eq 2) ("groups=$(@($split.Groups).Count) notCovered=$(@($split.NotCovered).Count)")
        Check 'chunker keeps every group under the bound' (@($split.Groups | Where-Object { $_.Text.Length -gt 1000 }).Count -eq 0) (($split.Groups | ForEach-Object { $_.Text.Length }) -join ',')
        $oneBig = "diff --git a/big.txt b/big.txt`n--- a/big.txt`n+++ b/big.txt`n" + ('x' * 1500) + "`n"
        $split = Split-PrReviewDiff -DiffText $oneBig -MaxChars 1000 -MaxGroups 4
        Check 'chunker truncates a single oversized file and names it not covered' (@($split.Groups).Count -eq 1 -and $split.Groups[0].Text.Length -le 1100 -and @($split.NotCovered) -contains 'big.txt') ("groups=$(@($split.Groups).Count) len=$($split.Groups[0].Text.Length) notCovered=$(@($split.NotCovered) -join ',')")
        $split = Split-PrReviewDiff -DiffText (($sections | Select-Object -First 1)) -MaxChars 1000 -MaxGroups 4
        Check 'chunker keeps a small diff whole' (@($split.Groups).Count -eq 1 -and @($split.NotCovered).Count -eq 0) ($split | Out-String)
    } else {
        Check 'reviewer library exists' $false $libPath
    }

    # ---------- behavior tests: synthetic gh + dispatcher ----------
    $runDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AgentHub\runtime\pr-review'
    Remove-Item (Join-Path $runDir 'brief-*.txt') -Force -ErrorAction SilentlyContinue

    function Invoke-Scenario {
        param([string]$Name, [string[]]$Extra = @(), [hashtable]$Files = @{})
        $dir = New-Scenario $Name
        $f = @{ Draft = $false; Head = $headMain; Branch = 'feature/thing'; Body = 'Does the thing. SH-4416'; Comments = @(); Diff = ''; HasAgentsMd = $true; Responses = @($validAnswer) }
        foreach ($k in $Files.Keys) { $f[$k] = $Files[$k] }
        Write-Scenario -Dir $dir -Draft $f.Draft -Head $f.Head -Branch $f.Branch -Body $f.Body -Comments $f.Comments -Diff $f.Diff -HasAgentsMd $f.HasAgentsMd -Responses $f.Responses
        $oldGh = $env:PRREVIEW_GH_DIR; $oldDisp = $env:PRREVIEW_DISPATCH_DIR
        $env:PRREVIEW_GH_DIR = $dir; $env:PRREVIEW_DISPATCH_DIR = $dir
        try {
            return Run-Reviewer (@('-Repo', $repo, '-Pr', '7', '-GhPath', $ghCmd, '-DispatcherPath', $dispCmd, '-ReviewerInstructionsPath', $riFile) + $Extra)
        } finally {
            $env:PRREVIEW_GH_DIR = $oldGh; $env:PRREVIEW_DISPATCH_DIR = $oldDisp
        }
    }

    # Draft refusal.
    $r = Invoke-Scenario 'draft' -Extra @() -Files @{ Draft = $true }
    Check 'draft PR is refused with exit 3 and no model run' ($r.Exit -eq 3 -and $r.Err -match 'draft' -and (Read-JsonLines (Join-Path (New-Scenario 'draft') 'dispatcher-log.jsonl')).Count -eq 0) ("exit=$($r.Exit) err=$($r.Err)")

    # Idempotence: an existing tool comment at the same head skips the model run.
    $keyDup = Get-PrReviewIdempotenceKey -Repo $repo -PrNumber 7 -HeadSha $headMain -Trigger 'opened'
    $dupComment = @{ author = @{ login = 'bot' }; body = "AgentHub PR review`n" + (Get-PrReviewMarker -Key $keyDup -Verdict 'PASS') }
    $r = Invoke-Scenario 'idempotent' -Files @{ Comments = @($dupComment) }
    Check 'existing review at the same head exits 0 without a new model run' ($r.Exit -eq 0 -and $r.Out -match 'already reviewed' -and (Read-JsonLines (Join-Path (New-Scenario 'idempotent') 'dispatcher-log.jsonl')).Count -eq 0) ("exit=$($r.Exit) out=$($r.Out)")
    $r = Invoke-Scenario 'force' -Extra @('-Force') -Files @{ Comments = @($dupComment) }
    Check '-Force re-reviews a head that already has a verdict' ($r.Exit -eq 0 -and (Read-JsonLines (Join-Path (New-Scenario 'force') 'dispatcher-log.jsonl')).Count -ge 1) ("exit=$($r.Exit) out=$($r.Out)")

    # Stale PASS status.
    $oldKey = Get-PrReviewIdempotenceKey -Repo $repo -PrNumber 7 -HeadSha $headMain -Trigger 'opened'
    $statusComment = @{ author = @{ login = 'bot' }; body = (Get-PrReviewMarker -Key $oldKey -Verdict 'PASS') }
    $r = Invoke-Scenario 'stale' -Extra @('-Status') -Files @{ Head = $headNext; Comments = @($statusComment) }
    Check '-Status reports a stale verdict when the head moved' ($r.Exit -eq 0 -and $r.Out -match 'stale') ("exit=$($r.Exit) out=$($r.Out)")
    $r = Invoke-Scenario 'current' -Extra @('-Status') -Files @{ Head = $headMain; Comments = @($statusComment) }
    Check '-Status reports current when the verdict matches the head' ($r.Exit -eq 0 -and $r.Out -match 'current') ("exit=$($r.Exit) out=$($r.Out)")
    $r = Invoke-Scenario 'nostatus' -Extra @('-Status')
    Check '-Status reports none when no tool comment exists' ($r.Exit -eq 0 -and $r.Out -match 'none') ("exit=$($r.Exit) out=$($r.Out)")

    # Malformed answers: retry once, then BLOCKED.
    $r = Invoke-Scenario 'malformed-twice' -Files @{ Responses = @('not json at all', 'still not json') }
    $dispLog = Read-JsonLines (Join-Path (New-Scenario 'malformed-twice') 'dispatcher-log.jsonl')
    Check 'two malformed answers produce BLOCKED after exactly two attempts' ($r.Out -match 'BLOCKED' -and @($dispLog).Count -eq 2) ("out=$($r.Out) calls=$(@($dispLog).Count)")
    $r = Invoke-Scenario 'malformed-once' -Files @{ Responses = @('garbage', $validAnswer) }
    $dispLog = Read-JsonLines (Join-Path (New-Scenario 'malformed-once') 'dispatcher-log.jsonl')
    Check 'one malformed answer retries once and then accepts the shape' ($r.Out -match 'PR review result:\s*PASS' -and @($dispLog).Count -eq 2) ("out=$($r.Out) calls=$(@($dispLog).Count)")
    Check 'the retry prompt carries the malformed-answer corrective note' (@($dispLog).Count -eq 2 -and $dispLog[1].prompt -match 'malformed') ($dispLog[1].prompt)

    # Oversized diff: per-file groups within the bound, remainder reported not covered.
    $bigDiff = 1..30 | ForEach-Object { "diff --git a/file$_.txt b/file$_.txt`n--- a/file$_.txt`n+++ b/file$_.txt`n" + (('x' * 1400) + "`n") }
    $r = Invoke-Scenario 'oversized' -Extra @('-DiffMaxChars', '4000', '-MaxGroups', '5') -Files @{ Diff = ($bigDiff -join '') }
    $dispLog = Read-JsonLines (Join-Path (New-Scenario 'oversized') 'dispatcher-log.jsonl')
    Check 'oversized diff reviews per file group bounded by -MaxGroups' ($r.Exit -eq 0 -and @($dispLog).Count -eq 5) ("exit=$($r.Exit) calls=$(@($dispLog).Count)")
    Check 'oversized diff says what was not covered' ($r.Out -match 'not covered' -and $r.Out -match 'file25\.txt') ($r.Out)
    Check 'a review that left files uncovered is never PASS' ($r.Out -match 'PR review result: BLOCKED' -and $r.Out -notmatch 'PR review result: PASS') ($r.Out)

    # Numeric bound: a 600-character diff is under a 5000 bound even though
    # '600' sorts after '5000' as text.
    $numDiff = "diff --git a/n.txt b/n.txt`n--- a/n.txt`n+++ b/n.txt`n" + ('y' * 560) + "`n"
    $numSplit = Split-PrReviewDiff -DiffText $numDiff -MaxChars 5000 -MaxGroups 4
    Check 'chunker compares the diff length as a number' (@($numSplit.Groups).Count -eq 1 -and @($numSplit.NotCovered).Count -eq 0 -and $numSplit.Groups[0].Text.Length -eq $numDiff.Length) ("groups=$(@($numSplit.Groups).Count) notCovered=$(@($numSplit.NotCovered).Count)")

    # A .ps1 dispatcher takes named parameters and writes its answer with
    # [Console]::Out, as the real dispatcher does. The answer must be captured.
    $ps1Disp = Join-Path $fixture 'dispatcher-console.ps1'
    $ps1Body = @'
param([string]$HostId, [string]$PromptFile, [string]$Cwd, [int]$TimeoutSec, [string]$Model)
if ([string]::IsNullOrWhiteSpace($HostId) -or $HostId.StartsWith('-') -or -not (Test-Path -LiteralPath $PromptFile)) { exit 9 }
[Console]::Out.Write($env:PRREVIEW_PS1_ANSWER)
exit 0
'@
    Set-Content -LiteralPath $ps1Disp -Value $ps1Body -Encoding utf8
    $ps1Dir = New-Scenario 'ps1dispatcher'
    Write-Scenario -Dir $ps1Dir -Draft $false -Head $headMain -Branch 'feature/thing' -Body 'Does the thing. SH-4416' -Comments @() -Diff '' -HasAgentsMd $true -Responses @($validAnswer)
    $oldGh = $env:PRREVIEW_GH_DIR; $env:PRREVIEW_GH_DIR = $ps1Dir; $env:PRREVIEW_PS1_ANSWER = $validAnswer
    try {
        $r = Run-Reviewer @('-Repo', $repo, '-Pr', '7', '-GhPath', $ghCmd, '-DispatcherPath', $ps1Disp, '-ReviewerInstructionsPath', $riFile)
    } finally { $env:PRREVIEW_GH_DIR = $oldGh; Remove-Item Env:PRREVIEW_PS1_ANSWER -ErrorAction SilentlyContinue }
    Check 'a .ps1 dispatcher binds by name and its console output is captured' ($r.Exit -eq 0 -and $r.Out -match 'PR review result: PASS') ("exit=$($r.Exit) out=$($r.Out)")

    # Happy path with -Post: one bounded comment carrying the hidden marker.
    $r = Invoke-Scenario 'post' -Extra @('-Post')
    $ghLog = Read-JsonLines (Join-Path (New-Scenario 'post') 'gh-log.jsonl')
    $commentCalls = @($ghLog | Where-Object { $_.args[0] -eq 'pr' -and $_.args[1] -eq 'comment' })
    Check 'happy path reviews and exits 0 with the verdict' ($r.Exit -eq 0 -and $r.Out -match 'PR review result:\s*PASS') ("exit=$($r.Exit) out=$($r.Out)")
    Check '-Post publishes exactly one comment' (@($commentCalls).Count -eq 1) ("calls=$(@($commentCalls).Count)")
    Check 'the posted comment carries the hidden idempotence marker' (@($commentCalls).Count -eq 1 -and $commentCalls[0].body -match 'agenthub-pr-review:v1' -and $commentCalls[0].body -match [regex]::Escape($headMain) -and $commentCalls[0].body -match 'verdict="PASS"') ($commentCalls[0].body)
    Check 'the posted comment stays bounded' (@($commentCalls).Count -eq 1 -and $commentCalls[0].body.Length -lt 5000) ("len=$(if ($commentCalls.Count) { $commentCalls[0].body.Length } else { 0 })")

    # Without -Post nothing is published.
    $r = Invoke-Scenario 'nopost'
    $ghLog = Read-JsonLines (Join-Path (New-Scenario 'nopost') 'gh-log.jsonl')
    Check 'without -Post no comment call is ever issued' ($r.Exit -eq 0 -and @($ghLog | Where-Object { $_.args[1] -eq 'comment' }).Count -eq 0) ("exit=$($r.Exit) ghLog=$(@($ghLog).Count)")

    # Write-command guard: only read-only gh subcommands, read-only prompt.
    $ghLog = Read-JsonLines (Join-Path (New-Scenario 'post') 'gh-log.jsonl')
    $allowed = $true
    foreach ($entry in $ghLog) {
        if ($entry.args[0] -notin @('pr', 'api')) { $allowed = $false }
        if ($entry.args[0] -eq 'pr' -and $entry.args[1] -notin @('view', 'diff', 'comment')) { $allowed = $false }
        if (($entry.args -join ' ') -match 'merge|--approve|push|pr edit') { $allowed = $false }
    }
    Check 'gh is called only with read-only subcommands' $allowed (($ghLog | ForEach-Object { $_.args -join ' ' }) -join ' | ')
    $dispLog = Read-JsonLines (Join-Path (New-Scenario 'post') 'dispatcher-log.jsonl')
    $promptOk = @($dispLog).Count -eq 1 -and $dispLog[0].prompt -match 'READ-ONLY' -and $dispLog[0].prompt -match 'REVIEWER-INSTRUCTIONS-FIXTURE' -and $dispLog[0].prompt -match 'AGENTS-MD-FIXTURE-CONTENT' -and $dispLog[0].prompt -match 'SH-4416'
    Check 'the review brief carries the read-only contract, reviewer instructions, AGENTS.md, diff and issue ids' $promptOk ($dispLog[0].prompt)
    Check 'no write command appears in any dispatcher invocation' (@($dispLog | Where-Object { ($_.args -join ' ') -match 'merge|--approve|git push' }).Count -eq 0) ($dispLog[0].args -join ' ')
    $leftBriefs = @(Get-ChildItem $runDir -Filter 'brief-*.txt' -ErrorAction SilentlyContinue)
    Check 'temporary brief files are cleaned up' ($leftBriefs.Count -eq 0) ("left=$($leftBriefs.Count)")

    # Author-host routing: never review on the authoring host.
    $r = Invoke-Scenario 'authorhost' -Files @{ Body = 'Does the thing. [host: codex]'; Branch = 'codex/feature' }
    $dispLog = Read-JsonLines (Join-Path (New-Scenario 'authorhost') 'dispatcher-log.jsonl')
    Check 'the default reviewer host differs from the author host' (@($dispLog).Count -eq 1 -and $dispLog[0].host -ne 'codex') ("host=$($dispLog[0].host)")
    $r = Invoke-Scenario 'authorhost-explicit' -Extra @('-HostId', 'codex') -Files @{ Body = 'Does the thing. [host: codex]'; Branch = 'codex/feature' }
    Check 'reviewing on the author host is refused' ($r.Exit -eq 3 -and $r.Err -match 'author') ("exit=$($r.Exit) err=$($r.Err)")

    # Dispatcher failure becomes a BLOCKED verdict.
    $r = Invoke-Scenario 'dispatchfail' -Files @{ Responses = @('!EXIT3') }
    Check 'a dispatcher failure yields BLOCKED without a retry' ($r.Out -match 'BLOCKED' -and (Read-JsonLines (Join-Path (New-Scenario 'dispatchfail') 'dispatcher-log.jsonl')).Count -eq 1) ("out=$($r.Out)")

    # Event trigger wiring: synchronize never reviews.
    $r = Invoke-Scenario 'synctrigger' -Extra @('-Trigger', 'synchronize')
    Check 'synchronize trigger skips the review' ($r.Exit -eq 0 -and $r.Out -match 'synchronize' -and (Read-JsonLines (Join-Path (New-Scenario 'synctrigger') 'dispatcher-log.jsonl')).Count -eq 0) ("exit=$($r.Exit) out=$($r.Out)")
} finally {
    if ($fixture -and (Test-Path -LiteralPath $fixture)) {
        $resolved = [IO.Path]::GetFullPath($fixture)
        if ($resolved.StartsWith([IO.Path]::GetFullPath(([IO.Path]::GetTempPath())).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
