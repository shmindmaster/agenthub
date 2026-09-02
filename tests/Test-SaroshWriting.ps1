#Requires -Version 5.1
<# Behavior tests for the fleet-wide Sarosh long-form writing contract. #>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$skillRoot = Join-Path $repoRoot 'packages\sarosh-writing\skills\sarosh-writing'
$skill = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw -Encoding UTF8
$metadata = Get-Content -LiteralPath (Join-Path $skillRoot 'agents\openai.yaml') -Raw -Encoding UTF8
$policy = Get-Content -LiteralPath (Join-Path $repoRoot 'global-agent-policy.md') -Raw -Encoding UTF8
$registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry\capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) { Write-Host "PASS: $Name" -ForegroundColor Green }
    else { Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red; $script:failures.Add($Name) }
}

$identityOk = $skill -match '(?m)^name:\s*sarosh-writing\s*$' -and
    $skill -match '(?m)^description:\s*Use when' -and
    $metadata -match '(?m)^\s*display_name:\s*"Sarosh Writing"\s*$' -and
    $metadata -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
Report 'skill identity and implicit invocation are explicit' $identityOk 'expected frontmatter, display name, and implicit invocation'

$structureOk = $skill -match '(?m)^## 1\. Objective\s*$' -and
    $skill -match '(?m)^## 2\. Scope and routing\s*$' -and
    $skill -match '(?m)^## 3\. Voice\s*$' -and
    $skill -match '(?m)^## 15\. Final check\s*$' -and
    $skill -match '(?is)Prefer:.*Avoid:'
Report 'skill follows the shared objective, routing, examples, and final-check pattern' $structureOk 'expected numbered structure plus Prefer/Avoid examples'

$evidencePatterns = @(
    'Claim.*Evidence.*Meaning.*Decision or action',
    'opportunity-engine',
    'portfolio-enrichment',
    'Qdrant `knowledge`',
    'RepoWise',
    'Do not invoke a local chat LLM',
    'Context.*Constraint.*Decision.*Execution.*Verified result.*Limits',
    'proposed.*implemented.*tested.*committed.*reviewed.*merged.*deployed.*production-verified.*user-validated',
    'owner\s+approval'
)
$missing = @($evidencePatterns | Where-Object { $skill -notmatch "(?is)$_" })
Report 'skill preserves evidence, argument, state, and release gates' ($missing.Count -eq 0) "missing: $($missing -join ', ')"

$routingOk = $skill -match '(?is)Use `sarosh-communication` for the concise message' -and
    $skill -match '(?is)Use `sarosh-audio-voice` if the text will be rendered' -and
    $policy -match '(?is)substantial authored artifacts.*`sarosh-writing`'
Report 'long-form writing routes cleanly to communication and audio layers' $routingOk 'expected all three skill ids in their correct roles'

$owners = @($registry.capabilities | Where-Object { 'sarosh-writing' -in @($_.managedSkillNames) })
$expectedHosts = @('amp','antigravity','claude','cline','codex','copilot','cursor','devin','factory','gemini','grok','hermes','opencode','qoder','qwen-code','warp','windsurf') | Sort-Object
$actualHosts = if ($owners.Count -eq 1) { @($owners[0].hostMappings | ForEach-Object { [string]$_.hostId } | Sort-Object -Unique) } else { @() }
$registryOk = $owners.Count -eq 1 -and $owners[0].id -eq 'sarosh-writing' -and
    $owners[0].owner -eq 'personal-writing' -and
    $owners[0].canonicalSource -eq 'packages/sarosh-writing' -and
    $actualHosts.Count -eq $expectedHosts.Count -and
    @(Compare-Object $expectedHosts $actualHosts).Count -eq 0
Report 'registry has one writing owner and all 17 host mappings' $registryOk "owners=$($owners.Count), hosts=$($actualHosts.Count)"

$forbidden = @('(?i)mailto:', '(?i)[A-Z0-9._%+-]+@(pendoah\.ai|fleekbiz\.com)', '(?i)Mobile:\s*\+?\d')
$leaks = @($forbidden | Where-Object { $skill -match $_ })
Report 'writing skill contains no fixed contact data' ($leaks.Count -eq 0) "matched: $($leaks -join ', ')"

Write-Host ''
Write-Host 'SCOPE: skill, metadata, evidence contract, three-layer routing, registry, and 17 host mappings'
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
