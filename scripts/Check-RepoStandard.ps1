#Requires -Version 5.1
<#
.SYNOPSIS
    Fleet repository-standard checker. Reports (and optionally repairs) drift
    from the shmindmaster repository knowledge + agent-instruction standard.

.DESCRIPTION
    The standard (registry/repo-standard.json is the machine-readable roster):
      - README.md for humans, AGENTS.md as the ONLY authored agent contract.
      - CLAUDE.md is a thin adapter: '@AGENTS.md' + '@.claude/CLAUDE.md'
        (RepoWise-managed block). Never hand-duplicated rules.
      - docs/ taxonomy: README.md router, current-state.md, product/,
        architecture/, development/, runbooks/, plans/PLANS.md.
      - Nested AGENTS.md files state the root applies and carry local deltas
        only; they never restate the root contract.
      - Forbidden legacy instruction surfaces (GEMINI.md, .cursorrules,
        .windsurfrules, .github/copilot-instructions.md,
        docs/ai/REPO_AGENT_RULES.md, scratch state files) do not exist.
      - RepoWise: repo is a member of the fleet workspace, post-commit hook
        installed, .repowise/ gitignored, index present and not stale.
      - One MCP registration: the fleet workspace server in
        registry/mcps.json. Per-repo repowise MCP entries are drift.
      - Tracker authority is explicit in AGENTS.md.

    Modes:
      check (default)  report drift, exit 1 if any FAIL.
      -Fix             repair deterministic drift only: create missing docs
                       skeleton files, delete forbidden legacy files, add
                       .gitignore entries. Never writes authored content
                       (AGENTS.md sections, prose docs) and never deletes
                       unlisted files.

    Run: pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All
         pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -Repo abacare
         pwsh -NoProfile -File scripts/Check-RepoStandard.ps1 -All -Fix
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo,
    [switch]$All,
    [switch]$Fix,
    [ValidateSet('table','json')]
    [string]$Format = 'table',
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot 'registry\repo-standard.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$fleetRoot = [string]$config.fleetRoot
if ([string]::IsNullOrWhiteSpace($fleetRoot)) { throw "repo-standard.json declares no fleetRoot" }

$results = [Collections.Generic.List[object]]::new()
function Add-Result([string]$RepoName, [string]$Check, [bool]$Passed, [string]$Detail, [bool]$Fixed) {
    $script:results.Add([pscustomobject]@{
        Repo   = $RepoName
        Check  = $Check
        Passed = $Passed
        Fixed  = $Fixed
        Detail = $Detail
    })
}

$requiredRootFiles = @($config.requiredRootFiles)
$requiredDocsFiles = @($config.requiredDocsFiles)
$requiredDocsDirs  = @($config.requiredDocsDirs)
$forbiddenPaths    = @($config.forbiddenPaths)
$rootMdAllowlist   = @($config.rootMarkdownAllowlist)
$agentsAnchors     = @($config.agentsAnchors)
$claudeMaxLines    = [int]$config.claudeMaxAuthoredLines
$workspaceFileName = [string]$config.workspace.file
if ([string]::IsNullOrWhiteSpace($workspaceFileName)) { $workspaceFileName = '.repowise-workspace.yaml' }
$workspaceRoot = [string]$config.workspace.root
if ([string]::IsNullOrWhiteSpace($workspaceRoot)) { $workspaceRoot = $fleetRoot }
$workspaceFile     = Join-Path $workspaceRoot $workspaceFileName

$workspaceRepos = @()
if (Test-Path -LiteralPath $workspaceFile) {
    $workspaceText = Get-Content -LiteralPath $workspaceFile -Raw -Encoding UTF8
    $ids = [Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($workspaceText, '(?m)^\s*-\s+path:\s*(\S+)\s*$')) {
        $p = $m.Groups[1].Value.Trim("`"'")
        $ids.Add($p)
        $ids.Add(([IO.Path]::GetFileName($p.Replace('/', '\'))))
    }
    foreach ($m in [regex]::Matches($workspaceText, '(?m)^\s+alias:\s*(\S+)\s*$')) {
        $ids.Add($m.Groups[1].Value.Trim("`"'"))
    }
    $workspaceRepos = @($ids | Select-Object -Unique)
}
function Test-MarkdownLinks([string]$RepoPath) {
    # Resolve relative markdown links in root README/AGENTS and docs/**.md.
    # Only relative links are checked; http(s), mailto and pure #anchors skip.
    $broken = [Collections.Generic.List[string]]::new()
    $mdFiles = [Collections.Generic.List[string]]::new()
    foreach ($f in @('README.md','AGENTS.md')) {
        $p = Join-Path $RepoPath $f
        if (Test-Path -LiteralPath $p) { $mdFiles.Add($p) }
    }
    $docsDir = Join-Path $RepoPath 'docs'
    if (Test-Path -LiteralPath $docsDir) {
        Get-ChildItem -LiteralPath $docsDir -Recurse -File -Filter '*.md' |
            ForEach-Object { $mdFiles.Add($_.FullName) }
    }
    foreach ($file in $mdFiles) {
        $text = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($text, '\]\(([^)\s]+)\)')) {
            $target = $m.Groups[1].Value
            if ($target -match '^(https?://|mailto:|#|ftp://|/)') { continue }
            $targetNoAnchor = ($target -split '#')[0]
            if ([string]::IsNullOrWhiteSpace($targetNoAnchor)) { continue }
            $decoded = [uri]::UnescapeDataString($targetNoAnchor).TrimEnd('/', '\')
            # Markdown directory links conventionally end in '/'. Join-Path
            # mangles a child with a trailing separator ('a\b\c\' joins as
            # 'a\b\c\'), so the link fails even when the directory exists.
            # Trim it; Test-MarkdownLinks fixtures in Test-RepoStandard.ps1
            # pin this behavior.
            $resolved = Join-Path (Split-Path -Parent $file) $decoded
            if (-not (Test-Path -LiteralPath $resolved)) {
                $broken.Add("$($file.Substring($RepoPath.Length + 1)) -> $target")
            }
        }
    }
    return $broken
}
function Invoke-RepoCheck {
    # SupportsShouldProcess here (rather than only on the top-level script)
    # is what makes $PSCmdlet.ShouldProcess available at each mutating call
    # site below. It cascades correctly: the ambient $WhatIfPreference set
    # by the top-level script's own -WhatIf switch is visible to this
    # function without needing to be passed explicitly.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [object]$Entry)
    $path = Join-Path $fleetRoot $Name
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) {
        Add-Result $Name 'repo-exists' $false 'no .git directory' $false
        return
    }

    foreach ($f in $requiredRootFiles) {
        $exists = Test-Path -LiteralPath (Join-Path $path $f)
        Add-Result $Name "root-file:$f" $exists $(if (-not $exists) { 'missing' } else { '' }) $false
    }

    # forbiddenPaths is config data and $path is a SIBLING repository, so a
    # bad entry here runs Remove-Item -Recurse -Force somewhere unintended.
    # Demonstrated 2026-08-19: a blank entry makes Join-Path return the repo
    # root, and -Fix deleted the fixture repo. A ".." or absolute entry
    # escapes the repo entirely. Same containment pattern as
    # Sync-AgentHub.ps1 refusing to prune outside its managed runtime.
    $repoFull = [IO.Path]::GetFullPath($path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    foreach ($f in $forbiddenPaths) {
        if ([string]::IsNullOrWhiteSpace($f)) {
            Add-Result $Name "forbidden:<blank>" $false 'refused: blank forbiddenPaths entry resolves to the repository root' $false
            continue
        }
        # Refuse BEFORE Join-Path. On Windows Join-Path concatenates an
        # absolute second argument ("C:\repo" + "C:\abs\f" -> "C:\repo\C:\abs\f"),
        # so the containment check below would see a path that still starts
        # with the repo prefix, pass it, and skip the refusal entirely.
        if ([IO.Path]::IsPathRooted($f)) {
            Add-Result $Name "forbidden:$f" $false "refused: forbiddenPaths entry is absolute ($f)" $false
            continue
        }
        $fp = Join-Path $path $f
        $fpFull = try { [IO.Path]::GetFullPath($fp) } catch { $null }
        if (-not $fpFull -or -not $fpFull.StartsWith($repoFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Result $Name "forbidden:$f" $false "refused: resolves outside the repository ($fpFull)" $false
            continue
        }
        if (Test-Path -LiteralPath $fp) {
            $item = Get-Item -LiteralPath $fp -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                # -Recurse -Force deletes THROUGH a junction, into the target.
                Add-Result $Name "forbidden:$f" $false 'refused: path is a reparse point' $false
                continue
            }
            $fixed = $false
            if ($Fix -and $PSCmdlet.ShouldProcess($fp, 'Remove forbidden path')) {
                Remove-Item -LiteralPath $fp -Recurse -Force
                $fixed = -not (Test-Path -LiteralPath $fp)
            }
            Add-Result $Name "forbidden:$f" $fixed 'present' $fixed
        }
    }

    $rootTextAllowlist = @('robots.txt', 'llms.txt')
    $rootDocs = Get-ChildItem -LiteralPath $path -File |
        Where-Object { $_.Extension -in '.txt', '.out', '.log' } |
        Where-Object { $_.Name -notin $rootTextAllowlist -and $_.Name -notin $forbiddenPaths }
    foreach ($f in $rootDocs) {
        Add-Result $Name 'root-scratch' $false $f.Name $false
    }

    foreach ($d in $requiredDocsDirs) {
        $exists = Test-Path -LiteralPath (Join-Path $path $d)
        $fixed = $false
        if (-not $exists -and $Fix -and $PSCmdlet.ShouldProcess((Join-Path $path $d), 'Create missing docs directory')) {
            New-Item -ItemType Directory -Force (Join-Path $path $d) | Out-Null
            $fixed = Test-Path -LiteralPath (Join-Path $path $d)
        }
        Add-Result $Name "docs-dir:$d" ($exists -or $fixed) $(if (-not $exists) { 'missing' } else { '' }) $fixed
    }

    foreach ($f in $requiredDocsFiles) {
        $fp = Join-Path $path $f
        $exists = Test-Path -LiteralPath $fp
        $fixed = $false
        if (-not $exists -and $Fix -and $PSCmdlet.ShouldProcess($fp, 'Create missing docs file')) {
            $parent = Split-Path -Parent $fp
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
            $leaf = Split-Path -Leaf $fp
            $template = switch ($leaf) {
                'README.md'        { "# Documentation Map`r`n`r`nStart with [current-state.md](./current-state.md) for verified repository reality.`r`n" }
                'current-state.md' { "# Current State`r`n`r`n> Bootstrap pending: this file must record verified reality, not intent. Update on first real task.`r`n" }
                'PLANS.md'         { "# Execution Plans`r`n`r`nComplex, multi-session work gets a resumable plan under ``docs/plans/active/``. Completed plans move to ``docs/plans/completed/``. A plan records: purpose, verified current behavior, target behavior, progress, discoveries, decisions, milestones with validation, risks, and final evidence.`r`n" }
                default            { "# Placeholder`r`n" }
            }
            [IO.File]::WriteAllText($fp, $template, [Text.UTF8Encoding]::new($false))
            $fixed = Test-Path -LiteralPath $fp
        }
        Add-Result $Name "docs-file:$f" ($exists -or $fixed) $(if (-not $exists) { 'missing' } else { '' }) $fixed
    }
    $agentsPath = Join-Path $path 'AGENTS.md'
    if (Test-Path -LiteralPath $agentsPath) {
        $agentsText = Get-Content -LiteralPath $agentsPath -Raw -Encoding UTF8
        $agentSignals = @(
            @{ Id = 'mission';   Pattern = '(?im)^#{1,6}\s*(Mission|Purpose|Purpose and current outcome|What this is|Product direction|.+repository guide)\b' },
            @{ Id = 'authority'; Pattern = '(?im)(Knowledge authority|source of truth|canonical source|code and runtime configuration win when documentation drifts|Executable code.*describe.*reality|GitHub\s+`?main`?\s+owns code|This file is the repository-specific source of truth)' },
            @{ Id = 'start';     Pattern = '(?im)^#{1,6}\s*(Start here|Read first|First-read context|Operating rules)\b' },
            @{ Id = 'repowise';  Pattern = '(?im)\bRepoWise\b|(?im)\brepowise\b' },
            @{ Id = 'commands';  Pattern = '(?im)^#{1,6}\s*(Canonical commands|Commands|Command map|Windows-first commands|Command contract)\b' },
            @{ Id = 'tracker';   Pattern = '(?im)^#{1,6}\s*Tracker\b|(?im)\bLinear\b.*\b(outcome|outcomes|acceptance|track|tracks)\b|(?im)\bGitHub Issues\b|(?im)\bNo external tracker\b|(?im)\bLinear owns\b' },
            @{ Id = 'done';      Pattern = '(?im)^#{1,6}\s*(Definition of done|Completion criteria|Verification and completion)\b|(?im)\bA change is complete when\b' },
            @{ Id = 'safety';    Pattern = '(?im)^#{1,6}\s*(Safety|Sensitive areas|Secrets and safety|Hard boundaries|Hard constraints|Core constraints)\b' }
        )
        foreach ($signal in $agentSignals) {
            $has = $agentsText -match $signal.Pattern
            Add-Result $Name "agents-signal:$($signal.Id)" $has $(if (-not $has) { 'signal missing' } else { '' }) $false
        }
        $lineCount = ($agentsText -split "`n").Count
        Add-Result $Name 'agents-length' ($lineCount -le 400) $(if ($lineCount -gt 400) { "$lineCount lines exceeds 400-line contract ceiling" } else { '' }) $false
        $tracker = [string]$Entry.tracker
        $trackerPattern = switch ($tracker) {
            'linear' { '(?im)\bLinear\b' }
            'github-issues' { '(?im)\bGitHub Issues\b|\bGitHub\b' }
            default { '(?im)\bNo external tracker\b|\btracker\b|\bnone\b' }
        }
        $hasTracker = $agentsText -match $trackerPattern
        Add-Result $Name 'tracker-section' $hasTracker $(if (-not $hasTracker) { "AGENTS.md must name its tracker authority (declared: $tracker)" } else { '' }) $false
    }

    $claudePath = Join-Path $path 'CLAUDE.md'
    if (Test-Path -LiteralPath $claudePath) {
        $claudeText = Get-Content -LiteralPath $claudePath -Raw -Encoding UTF8
        $imports = ($claudeText -match '(?m)^@AGENTS\.md\s*$')
        Add-Result $Name 'claude-imports-agents' $imports $(if (-not $imports) { 'CLAUDE.md must import @AGENTS.md' } else { '' }) $false
        $authored = $claudeText
        if ($authored -match '(?s)<!--\s*REPOWISE:START.*$') { $authored = ($authored -split '(?s)<!--\s*REPOWISE:START')[0] }
        $authoredLines = @($authored -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*(#|@|<!--)' })
        Add-Result $Name 'claude-no-duplication' ($authoredLines.Count -le $claudeMaxLines) $(if ($authoredLines.Count -gt $claudeMaxLines) { "$($authoredLines.Count) authored content lines in CLAUDE.md; rules belong in AGENTS.md" } else { '' }) $false
    }

    # Canonicalize before comparing. $path is built from the configured fleetRoot,
    # which may be spelled differently than the filesystem's own answer -- an 8.3
    # short root (C:\Users\SAROSH~1\...), a substituted drive, a symlink. Get-ChildItem
    # always returns the long form, so a raw string compare left the root AGENTS.md
    # failing the -ne test and audited as if it were nested, with $rel sliced at the
    # wrong offset ("iant\AGENTS.md"). Get-Item expands 8.3; Resolve-Path does not.
    $rootFull = (Get-Item -LiteralPath $path).FullName.TrimEnd('\', '/')
    $agentsFull = if (Test-Path -LiteralPath $agentsPath) { (Get-Item -LiteralPath $agentsPath).FullName } else { $agentsPath }
    $nested = Get-ChildItem -LiteralPath $path -Recurse -File -Filter 'AGENTS.md' |
        Where-Object { $_.FullName -ne $agentsFull } |
        Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|\.repowise)[\\/]' } |
        Where-Object {
            $relative = $_.FullName.Substring($rootFull.Length + 1)
            & git -C $path check-ignore --quiet -- $relative 2>$null
            $LASTEXITCODE -ne 0
        }
    $exemptions = @($Entry.agentsExemptions | ForEach-Object { [string]$_ -replace '/', '\' })
    foreach ($n in $nested) {
        $rel = $n.FullName.Substring($rootFull.Length + 1)
        if ($rel -in $exemptions) { continue }
        $nText = Get-Content -LiteralPath $n.FullName -Raw -Encoding UTF8
        # Any of: "root AGENTS.md", "root file/contract (still) applies", or a link
        # up to the root AGENTS.md. The rule is that the nested file defers to the
        # root -- not that it defers in one exact phrasing.
        $refsRoot = ($nText -match '(?i)root\s+AGENTS\.md') -or
                    ($nText -match '(?i)root\s+(file|contract)\s+(still\s+)?applies') -or
                    ($nText -match '(?i)\]\(\s*(\.\./)+AGENTS\.md\s*\)')
        Add-Result $Name "nested-refs-root:$rel" $refsRoot $(if (-not $refsRoot) { 'nested AGENTS.md must state the root AGENTS.md applies' } else { '' }) $false
        $dupes = (($nText -match '(?im)^#+\s*Mission') -and ($nText -match 'Knowledge authority') -and ($nText -match 'Definition of done'))
        Add-Result $Name "nested-no-duplication:$rel" (-not $dupes) $(if ($dupes) { 'nested AGENTS.md restates the root contract' } else { '' }) $false
    }

    $broken = Test-MarkdownLinks $path
    foreach ($b in $broken) { Add-Result $Name 'broken-link' $false $b $false }
    $inWorkspace = $workspaceRepos -contains $Name
    Add-Result $Name 'repowise-membership' $inWorkspace $(if (-not $inWorkspace) { "not in $workspaceFileName" } else { '' }) $false

    $hookPath = Join-Path $path '.git\hooks\post-commit'
    $hookOk = (Test-Path -LiteralPath $hookPath) -and ((Get-Content -LiteralPath $hookPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) -match 'repowise')
    Add-Result $Name 'repowise-hook' $hookOk $(if (-not $hookOk) { 'run: repowise hook install -w from C:\Repos' } else { '' }) $false

    $gitignorePath = Join-Path $path '.gitignore'
    $gi = if (Test-Path -LiteralPath $gitignorePath) { Get-Content -LiteralPath $gitignorePath -Raw -Encoding UTF8 } else { '' }
    $giOk = $gi -match '(?m)^\.repowise/?\r?$'
    $giFixed = $false
    if (-not $giOk -and $Fix -and $PSCmdlet.ShouldProcess($gitignorePath, 'Append RepoWise gitignore entries')) {
        [IO.File]::AppendAllText($gitignorePath, "`r`n# RepoWise generated index state`r`n.repowise/`r`n.claude/CLAUDE.md`r`n", [Text.UTF8Encoding]::new($false))
        $giFixed = $true
        $giOk = $true
    }
    Add-Result $Name 'gitignore-repowise' $giOk $(if (-not $giOk) { '.gitignore must exclude .repowise/ and .claude/CLAUDE.md' } else { '' }) $giFixed

    $statePath = Join-Path $path '.repowise\state.json'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $syncCommit = [string]$state.last_sync_commit
            # Never discard git's stderr into $null: a failed `git rev-parse`
            # (corrupt .git, git missing from PATH, etc.) must surface as its
            # own failure, not silently collapse $head to an empty string and
            # get misdiagnosed as ordinary staleness ("index not at HEAD") --
            # a signal only tracks what it claims to watch when git actually ran.
            $head = (git -C $path rev-parse HEAD 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "git rev-parse HEAD failed (exit $LASTEXITCODE): $head"
            }
            $stale = ($syncCommit -ne $head)
            Add-Result $Name 'repowise-freshness' (-not $stale) $(if ($stale) { "index not at HEAD; run repowise update --repo $Name" } else { '' }) $false
        } catch {
            Add-Result $Name 'repowise-freshness' $false "unable to verify freshness: $($_.Exception.Message)" $false
        }
    } else {
        Add-Result $Name 'repowise-indexed' $false 'no .repowise/state.json; run repowise update --repo <name>' $false
    }

    $mcpPath = Join-Path $path '.mcp.json'
    if (Test-Path -LiteralPath $mcpPath) {
        $mcpText = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8
        if ($mcpText -match 'repowise') {
            Add-Result $Name 'no-per-repo-repowise-mcp' $false '.mcp.json registers repowise; the fleet uses ONE workspace MCP registered in agenthub' $false
        }
    }
}
# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
$roster = $config.repos.PSObject.Properties
$targets = @()
if ($All) {
    $targets = @($roster | ForEach-Object { $_.Name })
} elseif (-not [string]::IsNullOrWhiteSpace($Repo)) {
    $targets = @($Repo)
} else {
    throw 'Pass -Repo <name> or -All.'
}
if ($targets.Count -eq 0) { throw 'roster is empty; a checker that checks nothing passes nothing.' }

foreach ($name in $targets) {
    $entry = $roster | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -eq $entry) { Add-Result $name 'roster-membership' $false 'not in repo-standard.json roster' $false; continue }
    Invoke-RepoCheck $name $entry.Value
}

$failed = @($results | Where-Object { -not $_.Passed })
$fixedCount = @($results | Where-Object { $_.Fixed }).Count

if ($Format -eq 'json') {
    [pscustomobject]@{
        fleet   = $fleetRoot
        repos   = $targets
        checks  = $results.Count
        failed  = $failed.Count
        fixed   = $fixedCount
        results = $results
    } | ConvertTo-Json -Depth 5
} else {
    $results | Group-Object Repo | ForEach-Object {
        $repoFailed = @($_.Group | Where-Object { -not $_.Passed })
        $marker = if ($repoFailed.Count -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Output ("{0,-18} {1} ({2} checks, {3} failed)" -f $_.Name, $marker, $_.Group.Count, $repoFailed.Count)
        foreach ($f in $repoFailed) {
            Write-Output ("    {0}: {1} {2}" -f $f.Check, $f.Detail, $(if ($f.Fixed) { '[FIXED]' } else { '' }))
        }
    }
    Write-Output ''
    Write-Output ("RESULT: {0} repos checked, {1} checks, {2} failures, {3} auto-fixed" -f $targets.Count, $results.Count, $failed.Count, $fixedCount)
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
