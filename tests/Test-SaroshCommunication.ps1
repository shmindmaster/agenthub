#Requires -Version 5.1
<#
Behavior tests for the fleet-wide Sarosh communication contract.

The capability is intentionally split across two surfaces: the complete skill
contains the communication framework, while global-agent-policy.md makes that
skill mandatory for every user-facing interaction. These tests keep the two
surfaces, registry ownership, deployment reach, and privacy boundary aligned.

Run: pwsh -NoProfile -File tests/Test-SaroshCommunication.ps1
     powershell.exe -NoProfile -File tests/Test-SaroshCommunication.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$skillRoot = Join-Path $repoRoot 'packages\sarosh-communication\skills\sarosh-communication'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$metadataPath = Join-Path $skillRoot 'agents\openai.yaml'
$policyPath = Join-Path $repoRoot 'global-agent-policy.md'
$registryPath = Join-Path $repoRoot 'registry\capabilities.json'

$failures = [Collections.Generic.List[string]]::new()
$reported = 0
function Report([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:reported++
    if ($Passed) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name -- $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
}

function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

$skill = Read-Utf8 $skillPath
$metadata = Read-Utf8 $metadataPath
$policy = Read-Utf8 $policyPath
$registry = if (Test-Path -LiteralPath $registryPath) {
    Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }

# 1. The package exposes the intended public skill and automatic invocation.
$frontmatterOk = $skill -and
    $skill -match '(?m)^name:\s*sarosh-communication\s*$' -and
    $skill -match '(?mi)^description:.*every user-facing interaction'
$metadataOk = $metadata -and
    $metadata -match '(?m)^\s*display_name:\s*"Sarosh Communication"\s*$' -and
    $metadata -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
Report 'skill identity and implicit invocation are explicit' `
    ($frontmatterOk -and $metadataOk) `
    'expected sarosh-communication frontmatter, every-user-facing description, and allow_implicit_invocation: true'

# 2. One capability owns the skill and deploys it to the complete managed set.
$owners = if ($registry) { @($registry.capabilities | Where-Object { 'sarosh-communication' -in @($_.managedSkillNames) }) } else { @() }
$capability = if ($owners.Count -eq 1) { $owners[0] } else { $null }
$expectedHosts = @(
    'amp', 'antigravity', 'claude', 'cline', 'codex', 'copilot', 'cursor',
    'devin', 'factory', 'gemini', 'grok', 'hermes', 'opencode', 'qoder',
    'qwen-code', 'warp', 'windsurf'
)
$actualHosts = if ($capability) { @($capability.hostMappings | ForEach-Object { [string]$_.hostId } | Sort-Object -Unique) } else { @() }
$hostSetOk = $actualHosts.Count -eq $expectedHosts.Count -and
    @(Compare-Object ($expectedHosts | Sort-Object) $actualHosts).Count -eq 0
$mappingModesOk = $capability -and
    @($capability.hostMappings | Where-Object { $_.deploymentStatus -ne 'managed-loose-skills' }).Count -eq 0
$registryOk = $capability -and
    $owners.Count -eq 1 -and
    $capability.id -eq 'sarosh-communication' -and
    $capability.owner -eq 'personal-communication' -and
    $capability.capabilityType -eq 'skills' -and
    $capability.canonicalSource -eq 'packages/sarosh-communication' -and
    $capability.hashBasis -eq 'packages/sarosh-communication' -and
    $capability.status -eq 'active-canonical'
Report 'registry has one owner and all 17 managed host mappings' `
    ($registryOk -and $hostSetOk -and $mappingModesOk) `
    "owners=$($owners.Count), hosts=$($actualHosts.Count), expected owner=personal-communication and managed-loose-skills"

# 3. Global instructions require the full skill for every user-facing message.
$policyOk = $policy -and
    $policy -match '(?m)^## Sarosh communication\s*$' -and
    $policy -match '(?is)before producing every user-facing[^.]*load and apply\s+`sarosh-communication`' -and
    $policy -match '(?is)replies.*progress commentary.*final task reports.*draft'
Report 'global policy mandates the skill for every user-facing interaction' `
    $policyOk `
    'expected mandatory loading for replies, progress commentary, final task reports, and drafts'

# 4. The merged skill preserves the load-bearing communication contract.
$requiredPatterns = @(
    'Bottom Line.*Impact.*Action',
    'No action needed from you\.',
    'Minimum necessary content wins',
    'Machine-generated logs and raw tool output',
    'system, safety,\s+repository, legal, evidence, and task-specific',
    'proposed.*implemented.*tested.*reviewed.*merged.*deployed.*production-verified.*user-validated',
    '\[TK: specific information needed\]',
    '\[TK — requires sign-off:',
    'A blocker stops the \*\*send\*\*, not necessarily the \*\*draft\*\*',
    'Relational Messages'
)
$missingPatterns = @($requiredPatterns | Where-Object { -not ($skill -match "(?is)$_") })
Report 'skill contains the merged framework and hard gates' `
    ($skill -and $missingPatterns.Count -eq 0) `
    "missing required contract patterns: $($missingPatterns -join ', ')"

# 5. Compression cannot erase correctness, evidence, or authorization.
$precedenceOk = $skill -and
    $skill -match '(?is)Accuracy and governing instructions outrank brevity' -and
    $skill -match '(?is)does not authorize an external send' -and
    $skill -match '(?is)do not remove.*risk.*blocker.*citation.*acceptance\s+criterion'
Report 'compression preserves correctness and authorization boundaries' `
    $precedenceOk `
    'expected explicit precedence, external-send, and required-detail protections'

# 6. Mutable contact details and signatures must not become fleet policy.
$forbiddenContactPatterns = @(
    '(?i)mailto:',
    '(?i)[A-Z0-9._%+-]+@(pendoah\.ai|fleekbiz\.com)',
    '(?i)Mobile:\s*\+?\d',
    '(?i)\+1\s*\(\d{3}\)',
    '(?i)CTO,\s*(Pendoah|FleekBiz)',
    '(?is)Default Pendoah sender:'
)
$contactLeaks = @($forbiddenContactPatterns | Where-Object { $skill -match $_ })
Report 'fleet skill contains no fixed contact or signature data' `
    ($skill -and $contactLeaks.Count -eq 0) `
    "matched forbidden contact patterns: $($contactLeaks -join ', ')"

# 7. Written communication and synthetic audio remain separate capabilities.
$separationOk = $skill -and
    $skill -match '(?is)written communication.*not the\s+audio voice' -and
    $skill -match '(?is)Local-AI voice id `sarosh`.*governed by `local-ai-stack`'
Report 'written communication stays separate from owner audio voice' `
    $separationOk `
    'expected an explicit written-text versus Local-AI audio boundary'

Write-Host ''
Write-Host "SCOPE: skill, UI metadata, global policy, registry, 17 host mappings, and contact-data boundary"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
