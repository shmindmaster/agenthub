#Requires -Version 5.1
<#
Behavior tests for the private sarosh plugin
(overlays/personal/packages/sarosh).

The fail-closed gate is the load-bearing one: a fixture that ships a
numeric claim without a locatable citation would teach every renderer
the wrong default. Each check below has a real failure path.

Run: pwsh -NoProfile -File tests/Test-KnowledgeAccess.ps1
#>
[CmdletBinding()]
param([string]$PythonExecutable = '')

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'lib\PrivateOverlay.ps1')
# sarosh is a private package in the gitignored personal overlay.
$overlay = Resolve-AgentHubTestOverlay -RepositoryRoot $repoRoot
if (-not $overlay.Root) {
    Write-Host "SKIP: sarosh is a private overlay package -- $($overlay.Reason)"
    Write-Host 'RESULT: 0 passed, 0 failed'
    exit 0
}
$pkg = Resolve-AgentHubTestOverlayPath -OverlayRoot $overlay.Root -RelativeToOverlay 'packages/sarosh'
$devTests = Resolve-AgentHubTestOverlayPath -OverlayRoot $overlay.Root -RelativeToOverlay 'tests/sarosh'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$oe = 'skills\opportunity'
$sd = 'skills\search-docs'
$required = @(
    '.claude-plugin\plugin.json',
    'plugin.json',
    'skills\write\SKILL.md',
    "$sd\SKILL.md",
    "$oe\SKILL.md",
    "$sd\scripts\New-KnowledgeIndex.ps1",
    "$sd\scripts\Search-Knowledge.ps1",
    "$sd\scripts\Find-CodeInKnowledge.ps1",
    "$oe\scripts\validate_application_answer_profile.py",
    "$oe\scripts\Install-ValidationRuntime.ps1",
    "$oe\scripts\requirements.txt",
    "$oe\schemas\opportunity.schema.yaml",
    "$oe\schemas\engagement-record.schema.yaml",
    "$oe\schemas\application-answer-profile.schema.yaml",
    "$oe\references\job-search.md",
    "$oe\references\reply-preflight.md"
)
foreach ($rel in $required) {
    $p = Join-Path $pkg $rel
    Report "package file exists: $rel" (Test-Path -LiteralPath $p) "missing $p"
}

$detect = Get-Content -LiteralPath (Join-Path $pkg "$sd\scripts\Find-CodeInKnowledge.ps1") -Raw -Encoding UTF8
Report 'detect script has no -Execute switch' ($detect -notmatch '(?m)\[switch\]\$Execute') `
    'Find-CodeInKnowledge.ps1 grew an -Execute path; detect-only is the contract until the owner authorizes a move.'

$fixtures = @(Get-ChildItem -LiteralPath (Join-Path $devTests 'fixtures\engagements') -Filter '*.yaml' -ErrorAction SilentlyContinue)
Report 'at least one synthetic engagement fixture exists' ($fixtures.Count -gt 0) `
    'fixtures/engagements is empty, so opportunity has nothing legal to match.'

foreach ($f in $fixtures) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    Report ("fixture '{0}' sets name_cleared false" -f $f.Name) ($text -match '(?m)^name_cleared:\s*false\s*$') `
        'a package fixture must not ship a cleared real client name'
    Report ("fixture '{0}' does not render a rate" -f $f.Name) ($text -match '(?m)^\s+rate_or_value:\s*null\s*$') `
        'rate_or_value must stay null in package fixtures'
    if ($text -match '(?m)^\s+claim:\s+.+$') {
        $unsourcedNumber = [regex]::Matches($text, '(?ms)^\s+- claim:\s+(?!null).+?evidence:\s+NOT_FOUND')
        Report ("fixture '{0}' has no unsourced numeric claim" -f $f.Name) ($unsourcedNumber.Count -eq 0) `
            'claim with evidence NOT_FOUND must stay claim: null'
    }
}

$engine = (Get-Content -LiteralPath (Join-Path $pkg "$oe\SKILL.md") -Raw -Encoding UTF8) + "`n" +
    (Get-Content -LiteralPath (Join-Path $pkg "$oe\references\job-search.md") -Raw -Encoding UTF8)
Report 'opportunity fail-closed on invented specifics' ($engine -match 'invented specifics') `
    'the fail-closed sentence is gone from opportunity'
Report 'opportunity owns the complete job lifecycle' (
    $engine -match 'DISCOVER.*VERIFY.*RANK.*RESEARCH.*AUGMENT.*MATCH.*RENDER.*QA' -and
    $engine -match 'ROUTE.*SUBMIT.*FOLLOW THROUGH.*LEARN'
) 'the canonical skill no longer covers discovery through learning'
Report 'opportunity is quality-first rather than LinkedIn-first' (
    $engine -match 'Do not center discovery on LinkedIn' -and
    $engine -match 'application convenience' -and
    $engine -match '`checked`' -and $engine -match '`unavailable`' -and
    $engine -match '`unchecked`'
) 'discovery coverage or quality-first routing is missing'
Report 'opportunity preserves the compensation and geography contract' (
    $engine -match '300K-1M\+' -and $engine -match '250K-299K' -and
    $engine -match 'worldwide target' -and $engine -match 'below USD 250K'
) 'standing compensation bands or geography preferences drifted'
Report 'opportunity deep research names the approved research lanes' (
    $engine -match 'Firecrawl' -and $engine -match 'Exa' -and
    $engine -match 'Tavily' -and $engine -match 'Context7' -and
    $engine -match 'official job, company, team, engineering, and candidate-policy pages'
) 'deep company research routing is incomplete'
Report 'opportunity requires machine parseability and private answer resolution' (
    $engine -match 'DOCX/PDF machine parseability' -and
    $engine -match 'application-answer-profile.yaml' -and
    $engine -match 'Never infer citizenship from work authorization'
) 'ATS parsing or the private answer-profile contract is missing'
Report 'opportunity counts only authoritative submission proof' (
    $engine -match 'Only a confirmation page, confirmation email' -and
    $engine -match 'Prepared, saved, attached, uploaded' -and
    $engine -match 'accepted \| declined'
) 'submission evidence or lifecycle states are incomplete'

if (-not $PythonExecutable) {
    $runtimePython = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'AgentHub\runtimes\knowledge-access\Scripts\python.exe' }
    $PythonExecutable = if ($runtimePython -and (Test-Path -LiteralPath $runtimePython -PathType Leaf)) { $runtimePython } else { 'python' }
}
$pythonCommand = Get-Command $PythonExecutable -ErrorAction SilentlyContinue
Report 'Python is available for application profile validation' ($null -ne $pythonCommand) `
    'python is required by validate_application_answer_profile.py'
if ($pythonCommand) {
    # Windows PowerShell treats redirected native stderr as an error record.
    # The validator deliberately writes stderr for rejected synthetic fixtures;
    # capture its exit status without terminating the remaining assertions.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
    & $pythonCommand.Source -c 'import yaml; from jsonschema import Draft202012Validator, FormatChecker' *> $null
    $dependenciesReady = $LASTEXITCODE -eq 0
    Report 'application profile validation dependencies are available' $dependenciesReady `
        'run opportunity/scripts/Install-ValidationRuntime.ps1 from the sarosh plugin or pass a provisioned -PythonExecutable'
    if ($dependenciesReady) {
    $validator = Join-Path $pkg "$oe\scripts\validate_application_answer_profile.py"
    $profileFixtures = Join-Path $devTests 'fixtures\application-profiles'

    & $pythonCommand.Source $validator (Join-Path $profileFixtures 'valid-synthetic.yaml') *> $null
    Report 'application profile validator accepts the valid synthetic profile' ($LASTEXITCODE -eq 0) `
        'valid-synthetic.yaml was rejected'

    & $pythonCommand.Source $validator (Join-Path $profileFixtures 'invalid-missing-synthetic.yaml') *> $null
    Report 'application profile validator rejects missing required state' ($LASTEXITCODE -ne 0) `
        'invalid-missing-synthetic.yaml was accepted'

    & $pythonCommand.Source $validator (Join-Path $profileFixtures 'invalid-conflict-synthetic.yaml') *> $null
    Report 'application profile validator rejects ambiguous semantic aliases' ($LASTEXITCODE -ne 0) `
        'invalid-conflict-synthetic.yaml was accepted'

    & $pythonCommand.Source $validator (Join-Path $profileFixtures 'malformed-synthetic.yaml') *> $null
    Report 'application profile validator rejects malformed YAML' ($LASTEXITCODE -ne 0) `
        'malformed-synthetic.yaml was accepted'

    $smokeScript = @'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    cases = yaml.safe_load(handle)["cases"]
for case in cases:
    if not case["live"] or case["credible_total_comp_usd"] < 250000:
        actual = "reject"
    elif case["flagship"] or case["credible_total_comp_usd"] >= 300000:
        actual = "priority_worldwide"
    elif case["country"] == "US" and case["credible_total_comp_usd"] >= 250000:
        actual = "priority_us_secondary"
    else:
        actual = "hold_deeper_research"
    if actual != case["expected"]:
        raise SystemExit(f"{case['id']}: expected {case['expected']}, got {actual}")
'@
    $smokePath = Join-Path $devTests 'fixtures\opportunities\job-search-policy-smoke.yaml'
    $smokeScript | & $pythonCommand.Source - $smokePath *> $null
    Report 'job policy smoke cases preserve worldwide, US secondary, and reject behavior' ($LASTEXITCODE -eq 0) `
        'a synthetic job policy case did not produce the expected lane'
    }
    } finally {
        $ErrorActionPreference = $previousEap
    }
}

$skill = Get-Content -LiteralPath (Join-Path $pkg "$sd\SKILL.md") -Raw -Encoding UTF8
Report 'opportunity routes evidence to search-docs and RepoWise' (
    $engine -match 'search-docs' -and $engine -match 'RepoWise' -and $engine -match 'client-facing handling' -and
    $engine -notmatch 'knowledge_v\d'
) 'skill must route documents to search-docs, code to RepoWise, with client-facing handling'
Report 'document search refuses legal, Duckie Qdrant, and a local model' (
    $skill -match '20_Legal_Matters' -and $skill -match ':6333' -and $skill -match 'local model' -and
    $engine -match 'You are the writer'
) 'skill dropped a hard exclusion or the writer rule'
Report 'opportunity rewrites the actual asset' (
    $engine -match 'Rewrite and enhance the actual asset' -and
    $engine -match 'credible synthesis'
) 'skill no longer requires rewriting the asset from retrieved knowledge'

$search = Get-Content -LiteralPath (Join-Path $pkg "$sd\scripts\Search-Knowledge.ps1") -Raw -Encoding UTF8
Report 'Search-Knowledge exposes -Semantic' ($search -match '(?m)\[switch\]\$Semantic') `
    'semantic search flag missing from Search-Knowledge.ps1'
Report 'Search-Knowledge semantic path calls docwise, not Local-AI' (
    $search -match 'Get-Command docwise' -and $search -match 'engine=docwise' -and
    $search -match 'docwise is not installed yet' -and $search -notmatch 'rag-index'
) 'semantic search must call the docwise CLI when installed and throw a clear message otherwise'

Report 'search-docs routes semantic to docwise with exact-search/RepoWise fallback' (
    $skill -match '-Semantic' -and $skill -match 'docwise' -and $skill -match 'RepoWise'
) 'skill must route -Semantic to docwise and fall back to exact search and RepoWise'

$localAiScanned = @(
    "$sd\SKILL.md",
    "$oe\SKILL.md",
    "$oe\references\job-search.md",
    "$oe\references\reply-preflight.md",
    "$sd\scripts\Search-Knowledge.ps1",
    "$sd\scripts\New-KnowledgeIndex.ps1"
)
foreach ($rel in $localAiScanned) {
    $text = Get-Content -LiteralPath (Join-Path $pkg $rel) -Raw -Encoding UTF8
    Report "no Local-AI dependency in $rel" (
        $text -notmatch 'D:\\Local-AI' -and $text -notmatch 'query\.ps1' -and
        $text -notmatch 'LOCAL_AI_ROOT' -and $text -notmatch 'LocalAiRoot' -and $text -notmatch 'ai\.ps1'
    ) 'Local AI is off: no D:\Local-AI, query.ps1, ai.ps1 or LocalAiRoot reference may remain'
}
Report 'search-docs includes 01' (
    $skill -match '01_Business_and_Entities'
) '01 must be in scope'
Report 'Search-Knowledge aliases 01' (
    $search -match "'01'\s*=\s*'01_Business_and_Entities'"
) 'Search-Knowledge.ps1 missing the 01 alias'
Report 'package no longer ships New-KnowledgeMap.ps1' (
    -not (Test-Path -LiteralPath (Join-Path $pkg "$sd\scripts\New-KnowledgeMap.ps1"))
) 'New-KnowledgeMap.ps1 is the old 6k-line map writer; New-KnowledgeIndex.ps1 replaced it'

$replyTests = Join-Path $devTests 'test_reply_preflight.py'
Report 'reply preflight behavior tests exist' (Test-Path -LiteralPath $replyTests -PathType Leaf) `
    'the opportunity reply gate needs executable synthetic regression cases'
if ($pythonCommand -and (Test-Path -LiteralPath $replyTests -PathType Leaf)) {
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $pythonCommand.Source -B $replyTests
        Report 'reply preflight synthetic behavior regressions pass' ($LASTEXITCODE -eq 0) `
            'closed-role, freshness, identity, duplicate and valid-reply cases must pass'
    } finally { $ErrorActionPreference = $previousEap }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
