#Requires -Version 5.1
<#
.SYNOPSIS
  Ready-only independent pull-request reviewer (Linear SH-4416). Replaces the
  Sentry Seer Code Review step for AgentHub PRs from 2026-12-08.

.DESCRIPTION
  Reviews one pull request through the existing windowless dispatcher
  (skills/dispatch/Invoke-CodingAgent.ps1) on a host different from the one
  that authored the PR. The reviewer itself is read-only: it never approves,
  never merges, never pushes and never edits the pull request. It publishes
  at most one bounded summary comment carrying a hidden idempotence marker,
  and only when -Post is passed.

  Flow: gh pr view (refuse a draft, exit 3) -> idempotence (any earlier
  review verdict for the same head SHA exits 0 without a new model run,
  unless -Force) -> trigger filter -> brief (title/body, linked issue ids,
  bounded base-to-head diff in per-file groups, repo AGENTS.md, reviewer
  instructions from packages/product/agents/reviewer.agent.md) -> dispatcher
  run on a subscription host -> fixed-shape answer (verdict PASS|FAIL|BLOCKED,
  exact head SHA, findings with severity, confidence, file, line,
  reproduction, fix rationale); one retry on a malformed answer, then
  BLOCKED.

  -Status prints whether the latest verdict still matches the current head:
  a new head SHA makes an earlier PASS stale.

  Subscription routes only: the model choice is passed to the dispatcher,
  which enforces the subscription-only refusals (no pay-as-you-go wallet).
  This run delivers the reviewer as code and tests; it does not wire
  webhooks, runners or cloud resources (GitHub ready_for_review through AWS
  CodeBuild is SH-4411).

.PARAMETER Repo
  owner/name of the repository.

.PARAMETER Pr
  Pull request number.

.PARAMETER Trigger
  Why the review runs: opened, reopened, ready_for_review, synchronize,
  converted_to_draft or manual (default). Event callers (SH-4411) pass the
  GitHub action; a synchronize trigger never reviews.

.PARAMETER HostId
  Reviewer host for the dispatcher. Refused when it is also the author host
  (branch prefix or PR body marker). Default: codex, then claude, skipping
  the author host.

.PARAMETER Model
  Model id passed through to the dispatcher (shape and subscription rules
  enforced there).

.PARAMETER Force
  Re-review a head SHA that already carries a verdict.

.PARAMETER Post
  Publish one bounded summary comment carrying the hidden idempotence
  marker. Without it the result is printed only.

.PARAMETER Status
  Print whether the latest verdict matches the current head; no review runs.

.PARAMETER GhPath
  Injectable gh command path (tests stub it). Defaults to gh on PATH.

.PARAMETER DispatcherPath
  Injectable dispatcher path (tests stub it). Defaults to the dispatcher
  beside this package.

.PARAMETER ReviewerInstructionsPath
  Injectable reviewer-instructions file (tests stub it). Defaults to
  <agenthub root>/packages/product/agents/reviewer.agent.md.

.PARAMETER DiffMaxChars
  Per-group diff character bound. Default 50000.

.PARAMETER MaxGroups
  Maximum file groups reviewed per run; files beyond it are reported as not
  covered. Default 8.

.PARAMETER TimeoutSec
  Dispatcher timeout per review call. Default 1800.

.EXAMPLE
  pwsh -NoProfile -File packages/coding-agent-dispatch/reviewer/Invoke-PrReview.ps1 -Repo shmindmaster/agenthub -Pr 110 -Trigger ready_for_review -Post
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [int]$Pr,
    [ValidateSet('opened', 'reopened', 'ready_for_review', 'synchronize', 'converted_to_draft', 'manual')]
    [string]$Trigger = 'manual',
    [string]$HostId,
    [string]$Model,
    [switch]$Force,
    [switch]$Post,
    [switch]$Status,
    [string]$GhPath,
    [string]$DispatcherPath,
    [string]$ReviewerInstructionsPath,
    [int]$DiffMaxChars = 50000,
    [int]$MaxGroups = 8,
    [int]$TimeoutSec = 1800
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

. (Join-Path $PSScriptRoot 'PrReviewLib.ps1')

function Write-Refusal {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine($Message)
    exit $Code
}

if ([string]::IsNullOrWhiteSpace($Repo) -or $Repo -notmatch '^[^/\s]+/[^/\s]+$') {
    Write-Refusal 3 'Pass -Repo as owner/name, for example shmindmaster/agenthub.'
}
if ($Pr -lt 1) { Write-Refusal 3 'Pass -Pr as a pull request number of 1 or more.' }
if ($TimeoutSec -lt 1) { Write-Refusal 3 '-TimeoutSec must be at least 1.' }
if ($DiffMaxChars -lt 500) { $DiffMaxChars = 500 }
if ($MaxGroups -lt 1) { $MaxGroups = 1 }

# gh: injectable for tests, resolved on PATH otherwise.
if ([string]::IsNullOrWhiteSpace($GhPath)) {
    $ghCommand = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ghCommand) { Write-Refusal 2 'gh was not found on PATH; the reviewer reads the pull request through gh.' }
    $GhPath = [string]$ghCommand.Source
}

# Dispatcher: injectable for tests, the package dispatcher otherwise.
if ([string]::IsNullOrWhiteSpace($DispatcherPath)) {
    $candidate = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\dispatch\Invoke-CodingAgent.ps1'
    if (-not (Test-Path -LiteralPath $candidate)) {
        Write-Refusal 2 "the dispatch script was not found at $candidate; pass -DispatcherPath."
    }
    $DispatcherPath = $candidate
}

# Reviewer instructions: injectable for tests, the AgentHub root otherwise.
if ([string]::IsNullOrWhiteSpace($ReviewerInstructionsPath)) {
    $instructionsFile = 'packages\product\agents\reviewer.agent.md'
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 6 -and $dir; $i++) {
        $candidate = Join-Path $dir $instructionsFile
        if (Test-Path -LiteralPath $candidate) { $ReviewerInstructionsPath = $candidate; break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if ([string]::IsNullOrWhiteSpace($ReviewerInstructionsPath) -and $env:AGENTHUB_ROOT) {
        $candidate = Join-Path $env:AGENTHUB_ROOT $instructionsFile
        if (Test-Path -LiteralPath $candidate) { $ReviewerInstructionsPath = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($ReviewerInstructionsPath)) {
        Write-Refusal 2 'reviewer instructions were not found; pass -ReviewerInstructionsPath.'
    }
}
if (-not (Test-Path -LiteralPath $ReviewerInstructionsPath -PathType Leaf)) {
    Write-Refusal 2 "reviewer instructions not found: $ReviewerInstructionsPath"
}
$reviewerInstructions = [IO.File]::ReadAllText($ReviewerInstructionsPath, [Text.UTF8Encoding]::new($false))

function Invoke-PrGh {
    # Runs one gh invocation and returns stdout as a single string. A
    # non-zero exit is reported by $LASTEXITCODE; callers decide.
    param([string[]]$GhArgs)
    $output = & $GhPath @GhArgs 2>$null
    return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Text = ($output | Out-String) }
}

# 1. Read the pull request.
$prResult = Invoke-PrGh @('pr', 'view', [string]$Pr, '--repo', $Repo, '--json',
    'number,title,body,state,isDraft,headRefName,headRefOid,baseRefName,author,comments')
if (-not $prResult.Ok) {
    Write-Refusal 2 "gh pr view failed for ${Repo}#$($Pr); the pull request was not read: $($prResult.Text.Trim())"
}
try { $prInfo = $prResult.Text | ConvertFrom-Json -ErrorAction Stop } catch {
    Write-Refusal 2 "gh pr view returned unreadable JSON for ${Repo}#$($Pr): $($_.Exception.Message)"
}
$head = [string]$prInfo.headRefOid
if ($head -notmatch '^[0-9a-fA-F]{40}$') {
    Write-Refusal 2 "gh pr view did not return a 40-character head SHA for ${Repo}#$($Pr)."
}
$authorLogin = if ($prInfo.author -and $prInfo.author.login) { [string]$prInfo.author.login } else { 'unknown' }
$comments = @($prInfo.comments | Where-Object { $_ })
$toolComments = Get-PrReviewToolComments -Comments $comments -Repo $Repo -PrNumber $Pr

# 2. -Status: does the latest verdict still match the current head?
if ($Status) {
    if (@($toolComments).Count -eq 0) {
        Write-Output 'status: none (no AgentHub PR review comment found for this pull request)'
    } else {
        $latest = $toolComments[-1]
        if ($latest.HeadSha -ieq $head) {
            Write-Output "status: current (verdict $($latest.Verdict) matches the current head $($head))"
        } else {
            Write-Output "status: stale (verdict $($latest.Verdict) was for head $($latest.HeadSha); the current head is $($head))"
        }
    }
    exit 0
}

# 3. A draft is refused, always (exit 3, clear message).
if ($prInfo.isDraft) {
    Write-Refusal 3 "PR $($Pr) in $Repo is a draft; the AgentHub reviewer runs on ready_for_review only. Mark it ready for review and re-run."
}

# 4. Idempotence: any earlier verdict for this exact head SHA means no new
#    model run, unless -Force.
$existingForHead = @($toolComments | Where-Object { $_.HeadSha -ieq $head })
if ($existingForHead.Count -gt 0 -and -not $Force) {
    Write-Output ("already reviewed: verdict {0} exists for head {1}; no new model run. Use -Force to re-review." -f $existingForHead[0].Verdict, $existingForHead[0].HeadSha)
    exit 0
}

# 5. Trigger filter: synchronize and unknown triggers never review; a
#    replayed event with the same key is a duplicate (bypassed by -Force,
#    which is also how a head-level duplicate is re-reviewed).
$key = Get-PrReviewIdempotenceKey -Repo $Repo -PrNumber $Pr -HeadSha $head -Trigger $Trigger
$triggerAction = Get-PrReviewTriggerAction -Action $Trigger -Draft ([bool]$prInfo.isDraft) -Key $key -ReviewedKeys (@($toolComments | ForEach-Object { $_.Key }))
if ($triggerAction.Action -eq 'skip' -and -not ($Force -and $triggerAction.Reason -eq 'duplicate')) {
    Write-Output ("no review on this run: {0}. Run with -Status to see whether an earlier verdict is still current." -f $triggerAction.Reason)
    exit 0
}

# 6. The reviewer runs on a host different from the authoring host when the
#    author host is known (branch prefix or PR body marker).
$authorHost = Get-PrReviewAuthorHost -BranchName ([string]$prInfo.headRefName) -Body ([string]$prInfo.body)
if ([string]::IsNullOrWhiteSpace($HostId)) {
    $reviewerHost = $null
    foreach ($candidateHost in @('codex', 'claude')) {
        if (-not $authorHost -or $candidateHost -ine $authorHost) { $reviewerHost = $candidateHost; break }
    }
    if ([string]::IsNullOrWhiteSpace($reviewerHost)) {
        Write-Refusal 3 'no default reviewer host is available; pass -HostId.'
    }
} else {
    $reviewerHost = $HostId.Trim()
    if ($authorHost -and $reviewerHost -ieq $authorHost) {
        Write-Refusal 3 "refused: reviewer host '$reviewerHost' is also the author host of this PR; pick a different -HostId."
    }
}

# 7. Base-to-head diff, bounded and grouped per file.
$diffResult = Invoke-PrGh @('pr', 'diff', [string]$Pr, '--repo', $Repo)
if (-not $diffResult.Ok) {
    Write-Refusal 2 "gh pr diff failed for ${Repo}#$($Pr): $($diffResult.Text.Trim())"
}
$split = Split-PrReviewDiff -DiffText ([string]$diffResult.Text) -MaxChars $DiffMaxChars -MaxGroups $MaxGroups
$linkedIssues = Get-PrReviewLinkedIssues -Texts @([string]$prInfo.title, [string]$prInfo.body, [string]$prInfo.headRefName)

# The repo's AGENTS.md at the reviewed head, fetched read-only through gh.
$agentsMd = $null
$apiResult = Invoke-PrGh @('api', ("repos/{0}/contents/AGENTS.md?ref={1}" -f $Repo, $head))
if ($apiResult.Ok) {
    try {
        $apiObj = $apiResult.Text | ConvertFrom-Json -ErrorAction Stop
        if ($apiObj.encoding -eq 'base64' -and $apiObj.content) {
            $agentsMd = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((([string]$apiObj.content) -replace '\s', '')))
        }
    } catch { $agentsMd = $null }
}
$agentsMdText = if ($agentsMd) { $agentsMd } else { "(AGENTS.md was not found in $Repo at head $head; reviewed without it)" }

# Runtime output lives under %LOCALAPPDATA%\AgentHub and is cleaned up.
$runDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AgentHub\runtime\pr-review'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

function Invoke-PrReviewDispatch {
    # One dispatcher run: the brief goes through a prompt file, the answer
    # comes back on stdout. The brief file is removed in every path.
    param([string]$BriefText)
    $briefFile = Join-Path $runDir ("brief-{0}.txt" -f [guid]::NewGuid().ToString('n'))
    [IO.File]::WriteAllText($briefFile, $BriefText, [Text.UTF8Encoding]::new($false))
    try {
        $dispatchArgs = @('-HostId', $reviewerHost, '-PromptFile', $briefFile, '-Cwd', $runDir, '-TimeoutSec', [string]$TimeoutSec)
        if (-not [string]::IsNullOrWhiteSpace($Model)) { $dispatchArgs += @('-Model', $Model) }
        # A .ps1 dispatcher runs in a child pwsh: an array splatted into a
        # script binds positionally (the names would arrive as values), and
        # the real dispatcher writes the child's answer with [Console]::Out,
        # which an in-process call cannot capture. A native or .cmd
        # dispatcher takes the same arguments directly.
        if ([IO.Path]::GetExtension($DispatcherPath) -ieq '.ps1') {
            $pwshExe = (Get-Process -Id $PID).Path
            $output = & $pwshExe -NoProfile -File $DispatcherPath @dispatchArgs 2>$null
        } else {
            $output = & $DispatcherPath @dispatchArgs 2>$null
        }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    } finally {
        Remove-Item -LiteralPath $briefFile -Force -ErrorAction SilentlyContinue
    }
}

# 8. One review call per bounded file group; malformed answers are retried
#    once, then the group is BLOCKED.
$rank = @{ PASS = 0; BLOCKED = 1; FAIL = 2 }
$overallVerdict = 'PASS'
$allFindings = @()
$covered = @()
$notCovered = @($split.NotCovered)
$groupIndex = 0
foreach ($group in @($split.Groups)) {
    $groupIndex++
    $filesLabel = (@($group.Files) -join ', ')
    if ([string]::IsNullOrWhiteSpace($filesLabel)) { $filesLabel = 'whole diff' }
    $groupLabel = "file group $groupIndex of $(@($split.Groups).Count): $filesLabel"
    $notCoveredNote = if (@($split.NotCovered).Count -gt 0) { (@($split.NotCovered) -join ', ') } else { '' }

    $briefParams = @{
        Repo = $Repo; PrNumber = $Pr; HeadSha = $head
        Title = [string]$prInfo.title; Body = [string]$prInfo.body; Author = $authorLogin
        Branch = [string]$prInfo.headRefName; BaseRef = [string]$prInfo.baseRefName
        LinkedIssues = $linkedIssues
        DiffText = [string]$group.Text; GroupLabel = $groupLabel
        NotCoveredNote = $notCoveredNote
        RepoAgentsMd = $agentsMdText; ReviewerInstructions = $reviewerInstructions
    }
    $answer = $null
    $run = Invoke-PrReviewDispatch -BriefText (New-PrReviewBrief @briefParams)
    if ($run.ExitCode -eq 0) { $answer = ConvertFrom-PrReviewAnswer -Text $run.Output -ExpectedHeadSha $head }
    if (-not $answer -and $run.ExitCode -eq 0) {
        # Reject and retry once on a malformed answer; then BLOCKED.
        $briefParams.RetryNote = 'Your previous answer was malformed: it did not match the required JSON shape (verdict, exact head SHA, findings with severity, confidence, file, line, reproduction, fix).'
        $retry = Invoke-PrReviewDispatch -BriefText (New-PrReviewBrief @briefParams)
        if ($retry.ExitCode -eq 0) { $answer = ConvertFrom-PrReviewAnswer -Text $retry.Output -ExpectedHeadSha $head }
    }
    $groupVerdict = if ($answer) { [string]$answer.verdict } else { 'BLOCKED' }
    if ($answer) {
        $allFindings += @($answer.findings)
        $covered += @($answer.covered)
        $notCovered += @($answer.notCovered)
    }
    if ([int]$rank[$groupVerdict] -gt [int]$rank[$overallVerdict]) { $overallVerdict = $groupVerdict }
}
$covered = @($covered | Select-Object -Unique)
$notCovered = @($notCovered | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
# A PASS only covers what was read. When any file was truncated or left out,
# the overall verdict cannot be PASS.
if ($overallVerdict -eq 'PASS' -and @($notCovered).Count -gt 0) { $overallVerdict = 'BLOCKED' }

# 9. The result, printed always, posted only with -Post.
Write-Output ("PR review result: {0}" -f $overallVerdict)
Write-Output ("repo: {0} pr: {1} head: {2}" -f $Repo, $Pr, $head)
Write-Output ("reviewer host: {0} (author host: {1})" -f $reviewerHost, $(if ($authorHost) { $authorHost } else { 'unknown' }))
Write-Output ("findings: {0}" -f @($allFindings).Count)
foreach ($finding in (@($allFindings) | Select-Object -First 20)) {
    Write-Output (" - {0}/{1} {2}:{3} reproduction: {4} fix: {5}" -f $finding.severity, $finding.confidence, $finding.file, $finding.line, $finding.reproduction, $finding.fix)
}
Write-Output ("covered: {0}" -f $(if (@($covered).Count -gt 0) { (@($covered) | Select-Object -First 20) -join ', ' } else { '(not recorded)' }))
Write-Output ("not covered: {0}" -f $(if (@($notCovered).Count -gt 0) { (@($notCovered) -join ', ') } else { 'nothing' }))

if ($Post) {
    $resultForComment = [pscustomobject]@{
        Verdict = $overallVerdict; HeadSha = $head
        Findings = @($allFindings); Covered = $covered; NotCovered = $notCovered
        ReviewerHost = $reviewerHost; AuthorHost = $authorHost
    }
    $commentBody = New-PrReviewCommentBody -Result $resultForComment -Key $key
    $commentFile = Join-Path $runDir ("comment-{0}.txt" -f [guid]::NewGuid().ToString('n'))
    [IO.File]::WriteAllText($commentFile, $commentBody, [Text.UTF8Encoding]::new($false))
    try {
        $posted = Invoke-PrGh @('pr', 'comment', [string]$Pr, '--repo', $Repo, '--body-file', $commentFile)
        if (-not $posted.Ok) {
            Write-Refusal 2 "posting the review comment failed (gh exit code); the verdict above was NOT published to the pull request."
        }
        Write-Output "posted the bounded summary comment to PR $($Pr)."
    } finally {
        Remove-Item -LiteralPath $commentFile -Force -ErrorAction SilentlyContinue
    }
}
exit 0
