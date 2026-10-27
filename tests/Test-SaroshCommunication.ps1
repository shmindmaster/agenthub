#Requires -Version 5.1
<#
Behavior tests for the fleet-wide Sarosh communication contract.

The skill preserves Sarosh's detailed communication framework while routing
long-form authorship and spoken identity to separate global skills. These
tests keep structure, registry ownership, deployment reach, evidence gates,
and mutable-identity boundaries aligned.

Run: pwsh -NoProfile -File tests/Test-SaroshCommunication.ps1
     powershell.exe -NoProfile -File tests/Test-SaroshCommunication.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $repoRoot 'scripts\lib\CapabilityGraph.ps1')
. (Join-Path $PSScriptRoot 'lib\PrivateOverlay.ps1')
# Private package: it lives in the gitignored personal overlay, never under
# packages/. Resolve the overlay from its documented location, or skip.
$overlay = Resolve-AgentHubTestOverlay -RepositoryRoot $repoRoot
if (-not $overlay.Root) {
    Write-Host "SKIP: sarosh-communication is a private overlay package -- $($overlay.Reason)"
    Write-Host 'RESULT: 0 passed, 0 failed'
    exit 0
}
$skillRoot = Resolve-AgentHubTestOverlayPath -OverlayRoot $overlay.Root -RelativeToOverlay 'packages/sarosh-communication/skills/sarosh-communication'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$metadataPath = Join-Path $skillRoot 'agents\openai.yaml'
$policyPath = (Get-AgentHubTestEffectivePolicy -RepositoryRoot $repoRoot).Path
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
$policy = Read-AgentHubTestPolicy -PolicyPath $policyPath -Domains communication
$registry = if (Test-Path -LiteralPath $registryPath) {
    Get-AgentHubMergedCapabilitiesDocument -OverlayRoot $overlay.Root -CapabilitiesDocument (Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
} else { $null }

# 1. The package exposes the intended public skill, an explicit written-only
#    boundary against the audio skill, and automatic invocation.
$frontmatterOk = $skill -and
    $skill -match '(?m)^name:\s*sarosh-communication\s*$' -and
    $skill -match '(?mi)^description:.*Use when' -and
    $skill -match '(?mi)^description:.*sarosh-writing' -and
    $skill -match '(?mi)^description:.*sarosh-audio-voice'
$metadataOk = $metadata -and
    $metadata -match '(?m)^\s*display_name:\s*"Sarosh Communication"\s*$' -and
    $metadata -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
Report 'skill identity, written/audio boundary, and implicit invocation are explicit' `
    ($frontmatterOk -and $metadataOk) `
    'expected sarosh-communication frontmatter naming sarosh-writing and sarosh-audio-voice, plus allow_implicit_invocation: true'

# 2. One capability owns the skill, deploys it to the complete managed set,
#    and no longer manages a sarosh-writing skill (retired from this branch).
$owners = @(if ($registry) { $registry.capabilities | Where-Object { 'sarosh-communication' -in @($_.managedSkillNames) } })
$capability = if ($owners.Count -eq 1) { $owners[0] } else { $null }
$expectedHosts = @(
    'amp', 'antigravity', 'claude', 'cline', 'codex', 'copilot', 'cursor',
    'devin', 'factory', 'gemini', 'grok', 'opencode',
    'warp', 'windsurf'
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
    $capability.canonicalSource -eq 'overlays/personal/packages/sarosh-communication' -and
    $capability.hashBasis -eq 'overlays/personal/packages/sarosh-communication' -and
    $capability.status -eq 'active-canonical'
Report 'registry has one owner, all 14 non-retired managed host mappings, no sarosh-writing' `
    ($registryOk -and $hostSetOk -and $mappingModesOk -and $noSaroshWriting) `
    "owners=$($owners.Count), hosts=$($actualHosts.Count), expected owner=personal-communication, managed-loose-skills, and no sarosh-writing entry"

# 3. The skill applies to authored communication, not routine owner chat.
$policyOk = $policy -and
    $policy -match '(?m)^## Sarosh communication, writing, and audio voice\s*$' -and
    $policy -match '(?is)drafting, editing, or reviewing communication on Sarosh''s behalf or to\s+other people.*`sarosh-communication`' -and
    $policy -match '(?is)Routine direct\s+conversation, progress updates, and task handoffs to Sarosh do not require\s+this skill' -and
    $policy -notmatch '(?is)Before producing every user-facing written interaction with Sarosh' -and
    $skill -match '(?is)Routine direct conversation, progress updates, and task handoffs\s+to Sarosh do not require this skill' -and
    $policy -match '(?is)substantial authored artifacts.*`sarosh-writing`' -and
    $policy -match '(?is)generated speech in Sarosh''s voice.*`sarosh-audio-voice`'
Report 'global policy routes communication, writing, and audio separately' `
    $policyOk `
    'expected authored communication scope and explicit routine owner-chat exclusion'

# The everyday entry stays small and requires the retained professional
# reference only for recipient-specific work. Test safeguards, not templates.
$referencePath = Join-Path $skillRoot 'references\professional-messaging.md'
$reference = Read-Utf8 $referencePath
$referenceRequired = $skill -match '(?is)professional messages, first read\s+`references/professional-messaging.md`'
$contract = $skill + "`n" + $reference
$requiredPatterns = @(
    'proposed.*implemented.*tested.*committed.*reviewed.*merged.*deployed.*production-verified',
    'Missing evidence is UNKNOWN',
    'Owner confirmations outrank',
    'Never invent a metric',
    'Preserve raw machine output',
    'Verify recipient, rendered formatting,\s+exact attachment and actual delivery',
    'No action needed from you',
    '\[TK: specific information needed\]'
)
$missing = @($requiredPatterns | Where-Object { $contract -notmatch "(?is)$_" })
Report 'compact entry mandates professional guidance and retains evidence and delivery gates' `
    ($skill.Length -lt 4500 -and $referenceRequired -and $reference -and $missing.Count -eq 0) `
    "entry chars=$($skill.Length), required reference=$referenceRequired, missing=$($missing -join ', ')"
$precedenceOk = $skill -match '(?is)Correctness, evidence, privacy and task requirements outrank brevity' -and
    $skill -match '(?is)never authorizes a send, publication, commitment, or account change'
Report 'compact entry preserves precedence and authorization boundaries' $precedenceOk 'Missing priority or no-send boundary'
$separationOk = $skill -match '(?is)Use sarosh-writing for substantial artifacts' -and
    $skill -match '(?is)spoken\s+identity belongs to sarosh-audio-voice' -and
    $skill -match '(?is)no fixed framework'
Report 'communication separates authorship and spoken identity without mandatory templates' $separationOk 'Missing routing or current style direction'

# 7. Mutable contact and signature facts are verified at use time, not frozen
#    into fleet policy.
$forbiddenContactPatterns = @(
    '(?i)mailto:',
    '(?i)[A-Z0-9._%+-]+@(?!example\.(com|org|net|test|invalid)\b)[A-Z0-9-]+(\.[A-Z0-9-]+)*\.[A-Z]{2,}',
    '(?i)Mobile:\s*\+?\d',
    '(?i)\+1\s*\(\d{3}\)',
    '(?is)Default [A-Za-z]+ sender:'
)
$contactLeaks = @($forbiddenContactPatterns | Where-Object { $contract -match $_ })
$mutableIdentityOk = $referenceRequired -and $contract -match '(?is)Treat titles, organizations, email addresses, phone numbers, signatures,\s+billing rates, aliases, and availability as mutable facts'
Report 'skill contains no fixed contact data and requires current identity verification' `
    ($contactLeaks.Count -eq 0 -and $mutableIdentityOk) `
    "matched fixed contact patterns: $($contactLeaks -join ', ')"

Write-Host ''
Write-Host "SCOPE: skill, UI metadata, global policy, registry, 14 host mappings, and expression-layer boundaries"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
