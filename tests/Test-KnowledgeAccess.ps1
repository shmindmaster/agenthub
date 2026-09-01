#Requires -Version 5.1
<#
Behavior tests for packages/knowledge-access.

The fail-closed gate is the load-bearing one: a fixture that ships a
numeric claim without a locatable citation would teach every renderer
the wrong default. Each check below has a real failure path.

Run: pwsh -NoProfile -File tests/Test-KnowledgeAccess.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$pkg = Join-Path $repoRoot 'packages\knowledge-access'

$failures = [Collections.Generic.List[string]]::new()
$passed = 0
function Report {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) { Write-Host "PASS: $Name" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $failures.Add($Name) }
}

$required = @(
    'skills\use-knowledge-access\SKILL.md',
    'skills\opportunity-engine\SKILL.md',
    'skills\portfolio-enrichment\SKILL.md',
    'scripts\New-KnowledgeIndex.ps1',
    'scripts\Search-Knowledge.ps1',
    'scripts\Find-CodeInKnowledge.ps1',
    'scripts\validate_application_answer_profile.py',
    'schemas\opportunity.schema.yaml',
    'schemas\engagement-record.schema.yaml',
    'schemas\application-answer-profile.schema.yaml',
    'references\knowledge-access-plan.md',
    'references\opportunity-response-engine.md'
)
foreach ($rel in $required) {
    $p = Join-Path $pkg $rel
    Report "package file exists: $rel" (Test-Path -LiteralPath $p) "missing $p"
}

$detect = Get-Content -LiteralPath (Join-Path $pkg 'scripts\Find-CodeInKnowledge.ps1') -Raw -Encoding UTF8
Report 'detect script has no -Execute switch' ($detect -notmatch '(?m)\[switch\]\$Execute') `
    'Find-CodeInKnowledge.ps1 grew an -Execute path; detect-only is the contract until the owner authorizes a move.'

$fixtures = @(Get-ChildItem -LiteralPath (Join-Path $pkg 'fixtures\engagements') -Filter '*.yaml' -ErrorAction SilentlyContinue)
Report 'at least one synthetic engagement fixture exists' ($fixtures.Count -gt 0) `
    'fixtures/engagements is empty, so opportunity-engine has nothing legal to match.'

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

$engine = Get-Content -LiteralPath (Join-Path $pkg 'skills\opportunity-engine\SKILL.md') -Raw -Encoding UTF8
Report 'opportunity-engine fail-closed on invented specifics' ($engine -match 'invented specifics') `
    'the fail-closed sentence is gone from opportunity-engine'
Report 'opportunity-engine owns the complete job lifecycle' (
    $engine -match 'DISCOVER.*VERIFY.*RANK.*RESEARCH.*AUGMENT.*MATCH.*RENDER.*QA' -and
    $engine -match 'ROUTE.*SUBMIT.*FOLLOW THROUGH.*LEARN'
) 'the canonical skill no longer covers discovery through learning'
Report 'opportunity-engine is quality-first rather than LinkedIn-first' (
    $engine -match 'Do not center discovery on LinkedIn' -and
    $engine -match 'application convenience' -and
    $engine -match '`checked`' -and $engine -match '`unavailable`' -and
    $engine -match '`unchecked`'
) 'discovery coverage or quality-first routing is missing'
Report 'opportunity-engine preserves the compensation and geography contract' (
    $engine -match '300K-1M\+' -and $engine -match '250K-299K' -and
    $engine -match 'worldwide target' -and $engine -match 'below USD 250K'
) 'standing compensation bands or geography preferences drifted'
Report 'opportunity-engine deep research names the approved research lanes' (
    $engine -match 'Firecrawl' -and $engine -match 'Exa' -and
    $engine -match 'Tavily' -and $engine -match 'Context7' -and
    $engine -match 'official job, company, team, engineering, and candidate-policy pages'
) 'deep company research routing is incomplete'
Report 'opportunity-engine requires machine parseability and private answer resolution' (
    $engine -match 'DOCX/PDF machine parseability' -and
    $engine -match 'application-answer-profile.yaml' -and
    $engine -match 'Never infer citizenship from work authorization'
) 'ATS parsing or the private answer-profile contract is missing'
Report 'opportunity-engine counts only authoritative submission proof' (
    $engine -match 'Only a confirmation page, confirmation email' -and
    $engine -match 'Prepared, saved, attached, uploaded' -and
    $engine -match 'accepted \| declined'
) 'submission evidence or lifecycle states are incomplete'

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
Report 'Python is available for application profile validation' ($null -ne $pythonCommand) `
    'python is required by validate_application_answer_profile.py'
if ($pythonCommand) {
    $validator = Join-Path $pkg 'scripts\validate_application_answer_profile.py'
    $profileFixtures = Join-Path $pkg 'fixtures\application-profiles'

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
    $smokePath = Join-Path $pkg 'fixtures\opportunities\job-search-policy-smoke.yaml'
    $smokeScript | & $pythonCommand.Source - $smokePath *> $null
    Report 'job policy smoke cases preserve worldwide, US secondary, and reject behavior' ($LASTEXITCODE -eq 0) `
        'a synthetic job policy case did not produce the expected lane'
}

$enrich = Get-Content -LiteralPath (Join-Path $pkg 'skills\portfolio-enrichment\SKILL.md') -Raw -Encoding UTF8
Report 'portfolio-enrichment uses Qdrant knowledge alias' (
    $enrich -match '-Index knowledge' -and $enrich -match 'client-facing' -and $enrich -notmatch 'knowledge_v\d'
) 'skill must query alias knowledge with client-facing, never a versioned collection name'
Report 'portfolio-enrichment refuses legal, Duckie Qdrant, and local chat draft' (
    $enrich -match 'legal' -and $enrich -match ':6333' -and
    $enrich -match 'llama\.cpp' -and $enrich -match 'You are the writer'
) 'skill dropped a hard exclusion or the writer rule'
Report 'portfolio-enrichment rewrites the actual asset' (
    $enrich -match 'Rewrite and enhance the actual asset' -and
    $enrich -match 'credible synthesis'
) 'skill no longer requires rewriting the asset from retrieved knowledge'

$search = Get-Content -LiteralPath (Join-Path $pkg 'scripts\Search-Knowledge.ps1') -Raw -Encoding UTF8
Report 'Search-Knowledge exposes -Semantic' ($search -match '(?m)\[switch\]\$Semantic') `
    'semantic search flag missing from Search-Knowledge.ps1'
Report 'Search-Knowledge semantic path is Local-AI Qdrant' (
    $search -match 'query\.ps1' -and $search -match 'local-ai-qdrant' -and $search -notmatch 'rag-index'
) 'semantic search must call Local-AI query.ps1, not a second index'

$skill = Get-Content -LiteralPath (Join-Path $pkg 'skills\use-knowledge-access\SKILL.md') -Raw -Encoding UTF8
Report 'use-knowledge-access routes semantic to Local-AI Qdrant' (
    $skill -match '-Semantic' -and $skill -match 'Local-AI Qdrant' -and $skill -notmatch 'D:\\rag-index'
) 'skill still points at D:\rag-index or dropped -Semantic'

$plan = Get-Content -LiteralPath (Join-Path $pkg 'references\knowledge-access-plan.md') -Raw -Encoding UTF8
Report 'plan phase 4 is Local-AI Qdrant not a second store' (
    $plan -match 'Local-AI Qdrant' -and $plan -match 'Do not stand up a second vector engine'
) 'knowledge-access-plan.md must reuse Local-AI Qdrant and refuse a second store'
Report 'plan and skill include 01 and 10' (
    $skill -match '01_Business_and_Entities' -and $skill -match '10_Certifications_Prep' -and
    $plan -match '01_Business_and_Entities' -and $plan -match '10_Certifications_Prep' -and
    $skill -notmatch 'Folders ``00``, ``01``'
) '01/10 must be in-scope; 01 must not be listed as out of scope'
Report 'Search-Knowledge aliases 01 and 10' (
    $search -match "'01'\s*=\s*'01_Business_and_Entities'" -and
    $search -match "'10'\s*=\s*'10_Certifications_Prep'"
) 'Search-Knowledge.ps1 missing 01 or 10 aliases'
Report 'package no longer ships New-KnowledgeMap.ps1' (
    -not (Test-Path -LiteralPath (Join-Path $pkg 'scripts\New-KnowledgeMap.ps1'))
) 'New-KnowledgeMap.ps1 is the old 6k-line map writer; New-KnowledgeIndex.ps1 replaced it'

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "RESULT: $passed passed, $($failures.Count) failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: $passed passed, 0 failed" -ForegroundColor Green
exit 0
