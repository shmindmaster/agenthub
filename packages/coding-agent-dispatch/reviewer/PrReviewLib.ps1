#Requires -Version 5.1
<# Pure, dot-sourceable functions for the AgentHub ready-only pull-request
   reviewer (Linear SH-4416). No I/O of its own except reading nothing:
   every function takes its inputs as parameters and returns values, so
   tests can exercise the trigger filter, idempotence keys, diff chunking
   and answer validation without gh, the dispatcher or a model. #>

# Host ids that can author work in this fleet, used to detect the PR author
# host from a branch prefix or an explicit PR-body marker.
$script:PrReviewKnownHosts = @(
    'claude', 'codex', 'cursor-agent', 'cursor', 'mimo-code', 'antigravity',
    'factory', 'windsurf', 'copilot', 'grok', 'opencode', 'devin', 'kilo',
    'cline', 'warp', 'amp', 'kiro'
)

# Event triggers the reviewer accepts from an event-driven caller
# (SH-4411 wires GitHub ready_for_review later) and from -Trigger.
$script:PrReviewTriggers = @(
    'opened', 'reopened', 'ready_for_review', 'synchronize',
    'converted_to_draft', 'manual'
)

function Get-PrReviewIdempotenceKey {
    param([string]$Repo, [int]$PrNumber, [string]$HeadSha, [string]$Trigger)
    return "agenthub-pr-review|$Repo|$PrNumber|$HeadSha|$Trigger"
}

function Get-PrReviewMarker {
    param([string]$Key, [string]$Verdict)
    return "<!-- agenthub-pr-review:v1 key=`"$Key`" verdict=`"$Verdict`" -->"
}

# Comments posted by this tool carry a hidden HTML marker. Parse every
# marker that names this exact repo and PR; anything else is ignored.
function Get-PrReviewToolComments {
    param($Comments, [string]$Repo, [int]$PrNumber)
    $found = @()
    foreach ($comment in @($Comments)) {
        $body = [string]$comment.body
        if (-not $body) { continue }
        foreach ($m in [regex]::Matches($body, 'agenthub-pr-review:v1 key="([^"]+)"(?:\s+verdict="([A-Z]+)")?')) {
            $key = $m.Groups[1].Value
            $parts = $key -split '\|'
            if ($parts.Count -ne 5) { continue }
            if ($parts[0] -ne 'agenthub-pr-review' -or $parts[1] -ne $Repo) { continue }
            if ($parts[2] -ne [string]$PrNumber) { continue }
            $head = $parts[3]
            if ($head -notmatch '^[0-9a-fA-F]{40}$') { continue }
            $found += [pscustomobject]@{
                Key = $key
                Repo = $parts[1]
                PrNumber = [int]$parts[2]
                HeadSha = $head
                Trigger = $parts[4]
                Verdict = $m.Groups[2].Value
            }
        }
    }
    return @($found)
}

# Event trigger filter. Returns Action 'review' or 'skip' with a Reason:
#   opened non-draft -> review          ready_for_review -> review
#   synchronize      -> no review       draft opened     -> no review
#   manual           -> review          replayed same key -> no second review
function Get-PrReviewTriggerAction {
    param([string]$Action, [bool]$Draft, [string]$Key, [string[]]$ReviewedKeys)
    $a = ([string]$Action).Trim().ToLowerInvariant()
    if ($Draft -or $a -eq 'converted_to_draft') {
        return [pscustomobject]@{ Action = 'skip'; Reason = 'draft' }
    }
    if ($a -eq 'synchronize') {
        return [pscustomobject]@{ Action = 'skip'; Reason = 'synchronize' }
    }
    if (@($ReviewedKeys) -contains $Key) {
        return [pscustomobject]@{ Action = 'skip'; Reason = 'duplicate' }
    }
    if ($a -in @('opened', 'reopened', 'ready_for_review', 'manual')) {
        return [pscustomobject]@{ Action = 'review'; Reason = $a }
    }
    return [pscustomobject]@{ Action = 'skip'; Reason = "unknown trigger '$Action'" }
}

# The authoring host, from an explicit PR-body marker first
# ([host: <id>] or [authored-by: <id>]), then a <host>/ or <host>- branch
# prefix. Returns '' when the author host is not known. Host ids are
# checked longest-first so 'cursor-agent' wins over 'cursor'.
function Get-PrReviewAuthorHost {
    param([string]$BranchName, [string]$Body)
    $bodyMatch = [regex]::Match([string]$Body, '(?i)\[(?:host|authored-by):\s*([a-z0-9-]+)\s*\]')
    if ($bodyMatch.Success) {
        $candidate = $bodyMatch.Groups[1].Value.ToLowerInvariant()
        if ($candidate -in $script:PrReviewKnownHosts) { return $candidate }
    }
    $branch = [string]$BranchName
    foreach ($candidateHost in ($script:PrReviewKnownHosts | Sort-Object { $_.Length } -Descending)) {
        if ($branch -match ('^(?i)' + [regex]::Escape($candidateHost) + '[/-]')) { return $candidateHost }
    }
    return ''
}

# Issue ids from the title, body and branch: SH-1234-style ids and #123.
function Get-PrReviewLinkedIssues {
    param([string[]]$Texts)
    $ids = @()
    foreach ($text in @($Texts)) {
        if (-not $text) { continue }
        foreach ($m in [regex]::Matches([string]$text, '(?i)\b([A-Z][A-Z0-9]{1,14}-\d+)\b')) {
            $ids += $m.Groups[1].Value.ToUpperInvariant()
        }
        foreach ($m in [regex]::Matches([string]$text, '(?<![\w/])#(\d+)\b')) {
            $ids += ('#' + $m.Groups[1].Value)
        }
    }
    return @(@($ids | Select-Object -Unique))
}

# Split a unified diff into per-file groups that each stay under $MaxChars.
# A single file larger than the bound is truncated into its own group and
# also named in NotCovered. When $MaxGroups groups are full, every
# remaining file is named in NotCovered so the report can say what was
# not covered.
function Split-PrReviewDiff {
    param([string]$DiffText, [int]$MaxChars = 50000, [int]$MaxGroups = 8)
    if ($MaxChars -lt 500) { $MaxChars = 500 }
    if ($MaxGroups -lt 1) { $MaxGroups = 1 }

    $sections = @()
    $current = $null
    foreach ($line in ([string]$DiffText -split "`r?`n")) {
        if ($line -match '^diff --git ') {
            if ($null -ne $current) { $sections += $current }
            $fileMatch = [regex]::Match($line, '^diff --git a/(.*?) b/')
            $file = if ($fileMatch.Success) { $fileMatch.Groups[1].Value } else { '(unknown file)' }
            $current = @{ File = $file; Text = $line }
        } elseif ($null -ne $current) {
            $current.Text = $current.Text + "`n" + $line
        }
    }
    if ($null -ne $current) { $sections += $current }

    if ([string]$DiffText.Length -le $MaxChars) {
        return [pscustomobject]@{
            Groups = @(@{ Files = @($sections | ForEach-Object { $_.File }); Text = [string]$DiffText })
            NotCovered = @()
        }
    }

    $groups = @()
    $notCovered = @()
    $curFiles = @()
    $curText = ''
    foreach ($section in $sections) {
        $text = [string]$section.Text
        if ($text.Length -gt $MaxChars) {
            if ($curText.Length -gt 0) {
                if ($groups.Count -lt $MaxGroups) { $groups += @{ Files = $curFiles; Text = $curText } }
                else { $notCovered += $curFiles }
                $curFiles = @(); $curText = ''
            }
            if ($groups.Count -lt $MaxGroups) {
                $cut = $text.Substring(0, $MaxChars)
                $groups += @{
                    Files = @($section.File)
                    Text = $cut + "`n[diff for this file was truncated by the AgentHub PR reviewer at $MaxChars characters]"
                }
                $notCovered += $section.File
            } else {
                $notCovered += $section.File
            }
            continue
        }
        if ($curText.Length -gt 0 -and ($curText.Length + $text.Length + 1) -gt $MaxChars) {
            if ($groups.Count -lt $MaxGroups) { $groups += @{ Files = $curFiles; Text = $curText } }
            else { $notCovered += $curFiles }
            $curFiles = @(); $curText = ''
        }
        $curFiles += $section.File
        $curText = if ($curText.Length -gt 0) { $curText + "`n" + $text } else { $text }
    }
    if ($curText.Length -gt 0) {
        if ($groups.Count -lt $MaxGroups) { $groups += @{ Files = $curFiles; Text = $curText } }
        else { $notCovered += $curFiles }
    }
    return [pscustomobject]@{ Groups = @($groups); NotCovered = @($notCovered) }
}

# Validate the reviewer's fixed-shape answer. Returns a normalized object
# or $null when the answer is malformed: verdict PASS|FAIL|BLOCKED, the
# exact head SHA, and findings each carrying severity, confidence, file,
# line, reproduction and fix.
function ConvertFrom-PrReviewAnswer {
    param([string]$Text, [string]$ExpectedHeadSha)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $json = $null
    $fenced = [regex]::Match([string]$Text, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
    if ($fenced.Success) {
        $json = $fenced.Groups[1].Value
    } else {
        $start = [string]$Text.IndexOf('{')
        $end = [string]$Text.LastIndexOf('}')
        if ($start -ge 0 -and $end -gt $start) { $json = [string]$Text.Substring($start, $end - $start + 1) }
    }
    if (-not $json) { return $null }
    try { $obj = $json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $obj) { return $null }

    $verdict = [string]$obj.verdict
    if ($verdict -cnotmatch '^(PASS|FAIL|BLOCKED)$') { return $null }
    $head = [string]$obj.head
    if ($head -notmatch '^[0-9a-fA-F]{40}$' -or $head -cne $ExpectedHeadSha) { return $null }

    $findings = @()
    if ($obj.PSObject.Properties['findings'] -and $null -ne $obj.findings) {
        foreach ($f in @($obj.findings)) {
            $severity = [string]$f.severity
            $confidence = [string]$f.confidence
            $file = [string]$f.file
            $line = 0
            $reproduction = [string]$f.reproduction
            $fix = [string]$f.fix
            if ($severity -cnotmatch '^(critical|major|minor|info)$') { return $null }
            if ($confidence -cnotmatch '^(high|medium|low)$') { return $null }
            if ([string]::IsNullOrWhiteSpace($file)) { return $null }
            if (-not [int]::TryParse([string]$f.line, [ref]$line) -or $line -lt 0) { return $null }
            if ([string]::IsNullOrWhiteSpace($reproduction)) { return $null }
            if ([string]::IsNullOrWhiteSpace($fix)) { return $null }
            $findings += [pscustomobject]@{
                severity = $severity; confidence = $confidence; file = $file
                line = $line; reproduction = $reproduction; fix = $fix
            }
        }
    }
    $covered = @(); $notCovered = @()
    if ($obj.PSObject.Properties['covered'] -and $null -ne $obj.covered) { $covered = @($obj.covered | ForEach-Object { [string]$_ }) }
    if ($obj.PSObject.Properties['notCovered'] -and $null -ne $obj.notCovered) { $notCovered = @($obj.notCovered | ForEach-Object { [string]$_ }) }
    return [pscustomobject]@{
        verdict = $verdict
        head = $head
        findings = @($findings)
        summary = [string]$obj.summary
        covered = $covered
        notCovered = $notCovered
    }
}

function ConvertTo-PrReviewBounded {
    param([string]$Text, [int]$MaxChars)
    $t = ([string]$Text) -replace '\s+', ' '
    if ($t.Length -le $MaxChars) { return $t }
    return ($t.Substring(0, [Math]::Max(0, $MaxChars - 3)) + '...')
}

# The review brief: PR metadata, linked issues, one diff group, the repo's
# AGENTS.md, the reviewer instructions, the read-only contract and the
# fixed answer shape. $RetryNote is appended on the single retry after a
# malformed answer.
function New-PrReviewBrief {
    param(
        [string]$Repo, [int]$PrNumber, [string]$HeadSha,
        [string]$Title, [string]$Body, [string]$Author,
        [string]$Branch, [string]$BaseRef,
        [string[]]$LinkedIssues,
        [string]$DiffText, [string]$GroupLabel, [string]$NotCoveredNote,
        [string]$RepoAgentsMd, [string]$ReviewerInstructions,
        [string]$RetryNote
    )
    $bodyText = ConvertTo-PrReviewBounded -Text $Body -MaxChars 8000
    $agentsText = ConvertTo-PrReviewBounded -Text $RepoAgentsMd -MaxChars 12000
    $issues = if (@($LinkedIssues).Count -gt 0) { @($LinkedIssues) -join ', ' } else { '(none found)' }
    $notCovered = if ([string]::IsNullOrWhiteSpace($NotCoveredNote)) { '(none)' } else { $NotCoveredNote }
    $retry = if ([string]::IsNullOrWhiteSpace($RetryNote)) { '' } else { "`n[RETRY] $RetryNote Reply with ONLY the JSON object in the ANSWER FORMAT below.`n" }

    return @"
You are the AgentHub independent pull-request reviewer. You did not author this change; take nothing about it on trust.

HARD RULES - READ-ONLY REVIEW:
- READ-ONLY: never edit project files, never run gh pr merge, gh pr review --approve, gh pr edit, git push, or any other write, mutating or outward-facing command, and never post or modify anything on the pull request. Analysis and report only.
- Base every finding on the material below; run nothing that writes.

PR UNDER REVIEW: $Repo#$PrNumber
head: $HeadSha
base: $BaseRef branch: $Branch author: $Author
linked issues: $issues
coverage group: $GroupLabel
not covered in this review: $notCovered

PR TITLE:
$Title

PR BODY:
$bodyText

REVIEWER INSTRUCTIONS (AgentHub reviewer.agent.md):
$ReviewerInstructions

REPOSITORY AGENTS.md (at the reviewed head):
$agentsText

DIFF ($GroupLabel):
$DiffText
$retry
ANSWER FORMAT - reply with ONLY this JSON object and no other text:
{"verdict":"PASS|FAIL|BLOCKED","head":"<the full 40-character head SHA above>","findings":[{"severity":"critical|major|minor|info","confidence":"high|medium|low","file":"path","line":0,"reproduction":"the command or failing test that shows the defect","fix":"why the fix is right"}],"summary":"one short paragraph","covered":["what this review covered"],"notCovered":["what this review could not cover"]}
A finding with no reproduction or no fix rationale is not a finding. PASS requires every file in the coverage group to have been considered.
"@
}

# The bounded summary comment posted with -Post. Carries the hidden
# idempotence marker; never approves, never merges.
function New-PrReviewCommentBody {
    param($Result, [string]$Key)
    $verdict = [string]$Result.Verdict
    $marker = Get-PrReviewMarker -Key $Key -Verdict $verdict
    $findings = @($Result.Findings)
    $shown = @($findings | Select-Object -First 10)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add($marker)
    [void]$lines.Add('## AgentHub PR review (independent, read-only)')
    [void]$lines.Add('')
    [void]$lines.Add("- verdict: **$verdict**")
    [void]$lines.Add("- head: ``$([string]$Result.HeadSha)``")
    [void]$lines.Add("- reviewer host: $([string]$Result.ReviewerHost)$(if ([string]$Result.AuthorHost) { " (author host: $([string]$Result.AuthorHost))" })")
    [void]$lines.Add("- findings: $($findings.Count)")
    if ($shown.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('| severity | confidence | file:line | reproduction | fix rationale |')
        [void]$lines.Add('| --- | --- | --- | --- | --- |')
        foreach ($f in $shown) {
            $sev = ConvertTo-PrReviewBounded -Text ([string]$f.severity) -MaxChars 20
            $conf = ConvertTo-PrReviewBounded -Text ([string]$f.confidence) -MaxChars 20
            $loc = ConvertTo-PrReviewBounded -Text ("$([string]$f.file):$([string]$f.line)") -MaxChars 120
            $rep = ConvertTo-PrReviewBounded -Text ([string]$f.reproduction) -MaxChars 200
            $fix = ConvertTo-PrReviewBounded -Text ([string]$f.fix) -MaxChars 200
            [void]$lines.Add("| $sev | $conf | $loc | $rep | $fix |")
        }
        if ($findings.Count -gt $shown.Count) {
            [void]$lines.Add('')
            [void]$lines.Add("_$($findings.Count - $shown.Count) more finding(s) omitted from this bounded summary._")
        }
    }
    $coveredNote = if (@($Result.Covered).Count -gt 0) { (@($Result.Covered) | Select-Object -First 20) -join ', ' } else { '(not recorded)' }
    [void]$lines.Add('')
    [void]$lines.Add("- covered: $coveredNote")
    $notCoveredNote = if (@($Result.NotCovered).Count -gt 0) { (@($Result.NotCovered) | Select-Object -First 20) -join ', ' } else { 'nothing' }
    [void]$lines.Add("- not covered: $notCoveredNote")
    [void]$lines.Add('')
    [void]$lines.Add('_Posted by the AgentHub ready-only PR reviewer. This comment never approves, never merges and never pushes; the owner keeps merge control. A new head SHA makes this verdict stale._')
    return ($lines -join "`n")
}
