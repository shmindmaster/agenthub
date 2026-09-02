#Requires -Version 5.1
<#
Behavior tests for the fleet-wide Sarosh communication contract.

The capability is intentionally split across two surfaces: the complete skill
contains the communication framework, while global-agent-policy.md makes that
skill mandatory for every user-facing interaction. These tests keep the two
surfaces, registry ownership, deployment reach, and the written/audio boundary
aligned.

The skill body is Sarosh's own authoritative text (2026-09-02), preserved
verbatim except for the frontmatter description and a short intro paragraph
naming `sarosh-audio-voice`. That authoritative text intentionally includes
his real contact and signature data in section 20 (Identity) -- it is his own
personal skill on his own machine, not third-party or customer data -- so,
unlike an earlier draft of this test, this file does not assert the skill is
free of contact data.

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

# 1. The package exposes the intended public skill, an explicit written-only
#    boundary against the audio skill, and automatic invocation.
$frontmatterOk = $skill -and
    $skill -match '(?m)^name:\s*sarosh-communication\s*$' -and
    $skill -match '(?mi)^description:.*Use when' -and
    $skill -match '(?mi)^description:.*sarosh-audio-voice'
$metadataOk = $metadata -and
    $metadata -match '(?m)^\s*display_name:\s*"Sarosh Communication"\s*$' -and
    $metadata -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
Report 'skill identity, written/audio boundary, and implicit invocation are explicit' `
    ($frontmatterOk -and $metadataOk) `
    'expected sarosh-communication frontmatter, a "Use when" description naming sarosh-audio-voice, and allow_implicit_invocation: true'

# 2. One capability owns the skill, deploys it to the complete managed set,
#    and no longer manages a sarosh-writing skill (retired from this branch).
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
$noSaroshWriting = $capability -and ('sarosh-writing' -notin @($capability.managedSkillNames))
$registryOk = $capability -and
    $owners.Count -eq 1 -and
    $capability.id -eq 'sarosh-communication' -and
    $capability.owner -eq 'personal-communication' -and
    $capability.capabilityType -eq 'skills' -and
    $capability.canonicalSource -eq 'packages/sarosh-communication' -and
    $capability.hashBasis -eq 'packages/sarosh-communication' -and
    $capability.status -eq 'active-canonical'
Report 'registry has one owner, all 17 managed host mappings, no sarosh-writing' `
    ($registryOk -and $hostSetOk -and $mappingModesOk -and $noSaroshWriting) `
    "owners=$($owners.Count), hosts=$($actualHosts.Count), expected owner=personal-communication, managed-loose-skills, and no sarosh-writing entry"

# 3. Global instructions require the full skill for every user-facing message.
$policyOk = $policy -and
    $policy -match '(?m)^## Sarosh communication\s*$' -and
    $policy -match '(?is)before producing every user-facing[^.]*load and apply\s+`sarosh-communication`' -and
    $policy -match '(?is)replies.*progress commentary.*final task reports.*draft'
Report 'global policy mandates the skill for every user-facing interaction' `
    $policyOk `
    'expected mandatory loading for replies, progress commentary, final task reports, and drafts'

# 4. The restored authoritative text preserves the load-bearing communication
#    contract and its 28 numbered sections.
$requiredPatterns = @(
    'Bottom Line.*Impact.*Action',
    'No action needed from you\.',
    'Minimum necessary content wins',
    'proposed.*implemented.*tested.*reviewed.*merged.*deployed.*production-verified.*user-validated',
    '\[TK: specific information needed\]',
    '\[TK .{1,3} requires sign-off:',
    'A blocker stops the \*\*send\*\*, not necessarily the \*\*draft\*\*',
    'Relational Messages',
    '(?m)^# 28\. Final Check\s*$'
)
$missingPatterns = @($requiredPatterns | Where-Object { -not ($skill -match "(?is)$_") })
Report 'skill contains the merged framework, hard gates, and all 28 sections' `
    ($skill -and $missingPatterns.Count -eq 0) `
    "missing required contract patterns: $($missingPatterns -join ', ')"

# 5. The added intro paragraph preserves precedence and the no-external-send
#    boundary without expanding beyond what was authorized.
$precedenceOk = $skill -and
    $skill -match '(?is)outrank brevity' -and
    $skill -match '(?is)does not authorize an external send' -and
    $skill -match '(?is)system, safety,\s+repository, legal, evidence, and\s+task-specific'
Report 'intro paragraph preserves precedence and authorization boundaries' `
    $precedenceOk `
    'expected "outrank brevity", "does not authorize an external send", and the system/safety/repository/legal/evidence/task-specific list'

# 6. Written communication and synthetic audio remain separate capabilities,
#    routed to the dedicated sarosh-audio-voice skill rather than duplicating
#    Local-AI routing detail inline.
$separationOk = $skill -and
    $skill -match '(?is)written communication only' -and
    $skill -match '(?is)spoken or cloned voice is\s+a separate capability,\s+`sarosh-audio-voice`'
Report 'written communication stays separate from owner audio voice' `
    $separationOk `
    'expected an explicit written-only statement naming sarosh-audio-voice as the separate capability'

Write-Host ''
Write-Host "SCOPE: skill, UI metadata, global policy, registry, 17 host mappings, and the written/audio boundary"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
