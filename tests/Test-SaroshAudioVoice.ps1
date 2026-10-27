#Requires -Version 5.1
<#
Behavior tests for the fleet-wide Sarosh audio-voice contract.

sarosh-audio-voice is the audio counterpart to sarosh-communication: it
governs Sarosh's spoken/cloned voice (local Qwen3-TTS clone, voice id
`sarosh`, speaker identity ADVISORY ONLY per owner direction 2026-10-27, dictionary-layer pronunciation),
while sarosh-communication governs written tone and structure. These tests
keep the skill identity, registry ownership, deployment reach, policy
cross-reference, scope-separation language, and the approved-existing-clone boundary
aligned.

Run: pwsh -NoProfile -File tests/Test-SaroshAudioVoice.ps1
     powershell.exe -NoProfile -File tests/Test-SaroshAudioVoice.ps1
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
    Write-Host "SKIP: sarosh-audio-voice is a private overlay package -- $($overlay.Reason)"
    Write-Host 'RESULT: 0 passed, 0 failed'
    exit 0
}
$skillRoot = Resolve-AgentHubTestOverlayPath -OverlayRoot $overlay.Root -RelativeToOverlay 'packages/sarosh-audio-voice/skills/sarosh-audio-voice'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$metadataPath = Join-Path $skillRoot 'agents\openai.yaml'
# Owner voice lives only in the overlay's effective policy (this test already skipped without an overlay).
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
$policy = Read-AgentHubTestPolicy -PolicyPath $policyPath -Domains media,communication
$registry = if (Test-Path -LiteralPath $registryPath) {
    Get-AgentHubMergedCapabilitiesDocument -OverlayRoot $overlay.Root -CapabilitiesDocument (Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)
} else { $null }

# 1. Skill identity and trigger description are explicit.
$frontmatterOk = $skill -and
    $skill -match '(?m)^name:\s*sarosh-audio-voice\s*$' -and
    $skill -match '(?mi)^description:.*Use when' -and
    $skill -match '(?mi)^description:.*voice clone' -and
    $skill -match '(?mi)^description:.*speaker-identity'
$metadataOk = $metadata -and
    $metadata -match '(?m)^\s*display_name:\s*"Sarosh Audio Voice"\s*$' -and
    $metadata -match '(?m)^\s*allow_implicit_invocation:\s*true\s*$'
Report 'skill identity and trigger description are explicit' `
    ($frontmatterOk -and $metadataOk) `
    'expected sarosh-audio-voice frontmatter, a "Use when" description naming voice clone and speaker-identity triggers, and allow_implicit_invocation: true'

# 2. One capability owns the skill and deploys it to the complete managed set.
$owners = @(if ($registry) { $registry.capabilities | Where-Object { 'sarosh-audio-voice' -in @($_.managedSkillNames) } })
$capability = if ($owners.Count -eq 1) { $owners[0] } else { $null }
$expectedHosts = @(
    'amp', 'antigravity', 'claude', 'cline', 'codex', 'copilot', 'cursor',
    'devin', 'factory', 'gemini', 'grok', 'opencode',
    'warp', 'windsurf', 'vscode-insiders'
)
$actualHosts = if ($capability) { @($capability.hostMappings | ForEach-Object { [string]$_.hostId } | Sort-Object -Unique) } else { @() }
$hostSetOk = $actualHosts.Count -eq $expectedHosts.Count -and
    @(Compare-Object ($expectedHosts | Sort-Object) $actualHosts).Count -eq 0
$mappingModesOk = $capability -and
    @($capability.hostMappings | Where-Object { $_.deploymentStatus -ne 'managed-loose-skills' }).Count -eq 0
$registryOk = $capability -and
    $owners.Count -eq 1 -and
    $capability.id -eq 'sarosh-audio-voice' -and
    $capability.capabilityType -eq 'skills' -and
    $capability.canonicalSource -eq 'overlays/personal/packages/sarosh-audio-voice' -and
    $capability.hashBasis -eq 'overlays/personal/packages/sarosh-audio-voice' -and
    $capability.status -eq 'active-canonical'
Report 'registry has one owner and all 15 non-retired managed host mappings' `
    ($registryOk -and $hostSetOk -and $mappingModesOk) `
    "owners=$($owners.Count), hosts=$($actualHosts.Count), expected managed-loose-skills on all 15 non-retired hosts"

# 3. Global policy cross-references the skill from Owner voice.
$policyOk = $policy -and
    $policy -match '(?m)^## Owner voice\s*$' -and
    $policy -match '(?is)load and apply\s+`sarosh-audio-voice`' -and
    $policy -match '(?is)generated speech in Sarosh''s voice.*`sarosh-audio-voice`' -and
    $policy -match '(?is)Local-AI voice id `sarosh` under `local-ai-stack`'
Report 'global policy routes owner voice through sarosh-audio-voice and Local-AI' `
    $policyOk `
    'expected Owner voice and the three-layer Sarosh policy to route audio through sarosh-audio-voice and local-ai-stack'

# 4. Owner authorized only the existing clone, with cost-aware local routing.
$routingOk = $skill -and
    $skill -match '(?is)existing hosted Sarosh clone' -and
    $skill -match '(?is)Local-AI voice id `sarosh`' -and
    $skill -match '(?is)Use adequate\s+local speech' -and
    $skill -match '(?is)credits and per-model clone readiness' -and
    $skill -match '(?is)Never substitute a generic voice' -and
    $skill -match '(?is)Do not upload new private\s+recordings or corpus' -and
    $skill -match '(?is)change billing or enable overages without separate authority'
Report 'skill limits hosted authority to the existing clone with cost and privacy gates' `
    $routingOk `
    'expected existing-clone authorization, adequate local speech, readiness, identity, no new private uploads and no billing changes'

# 5. Owner direction 2026-10-27: speaker identity is ADVISORY ONLY. The skill must say so, keep the
#    informational command form, and must not carry any language that makes identity a gate or a re-voice trigger.
$identityAdvisoryOk = $skill -and
    $skill -match '(?is)identity is advisory only; never fail, block or re-voice on speaker similarity' -and
    $skill -match '(?is)2026-10-27' -and
    $skill -match '(?i)voice score --voice sarosh' -and
    $skill -match '(?is)optional, informational only' -and
    $skill -match '(?is)Expression, emotion, and pacing are adjustable' -and
    $skill -match '(?is)never a failure class'
Report 'skill states that speaker identity is advisory only' `
    $identityAdvisoryOk `
    'expected the owner-direction rule, the informational command form and the never-a-failure-class language'
$identityGateGone = $skill -and
    $skill -notmatch '(?i)passes a speaker-identity gate' -and
    $skill -notmatch '(?i)(both|enrolled) identity backends' -and
    $skill -notmatch '(?i)do not waive the identity gate' -and
    $skill -notmatch '(?i)source-identity-passed' -and
    $skill -notmatch '(?i)optimize order: 1 speaker identity' -and
    $skill -notmatch '(?i)floors?:\s*ReDimNet'
Report 'skill no longer treats speaker identity as a gate or a failure class' `
    $identityGateGone `
    'a speaker-identity gate, identity-backend proof step, identity release state or similarity floor is still in the skill'
$guidanceMedia = Read-Utf8 (Join-Path $overlay.Root 'guidance\media.md')
Report 'owner-voice media guidance states identity is advisory and does not demand an identity gate' `
    ($guidanceMedia -and $guidanceMedia -match '(?is)identity is advisory only; never fail, block or re-voice on speaker similarity' -and $guidanceMedia -notmatch '(?i)passes a speaker-identity gate') `
    'guidance/media.md still demands a speaker-identity gate'

# 6. The skill states the pronunciation-is-a-dictionary-layer rule and never
#    training data / benchmarking-needs-approval rules from global policy.
$otherRulesOk = $skill -and
    $skill -match '(?is)Do not correct pronunciation by respelling' -and
    $skill -match '(?is)dictionary layer applied at\s+render time' -and
    $skill -match '(?is)not training data for an\s+external\s+service' -and
    $skill -match '(?is)benchmark \*text\*'
Report 'skill states the pronunciation-dictionary and no-training-data/benchmark-approval rules' `
    $otherRulesOk `
    'expected the pronunciation dictionary-layer rule and the training-data/benchmark-approval rule'

# 7. Scope separation from sarosh-communication and from the media pipeline
#    is explicit.
$separationOk = $skill -and
    $skill -match '(?is)`sarosh-writing` governs the\s+canonical script' -and
    $skill -match '(?is)`sarosh-communication` governs the concise handoff message' -and
    $skill -match '(?is)media-studio' -and
    $skill -match '(?is)long-running-generation'
Report 'skill states scope separation from sarosh-communication and the media pipeline' `
    $separationOk `
    'expected an explicit split naming sarosh-writing, sarosh-communication, media-studio, and long-running-generation'

# 8. The skill follows the shared detailed authoring pattern and exact-delivery
#    evidence contract.
$patternOk = $skill -and
    $skill -match '(?m)^## 1\. Objective\s*$' -and
    $skill -match '(?m)^## 2\. Scope and routing\s*$' -and
    $skill -match '(?m)^## 11\. Final check\s*$' -and
    $skill -match '(?is)Prefer:.*Avoid:' -and
    $skill -match '(?is)exact mixed and encoded delivery artifact' -and
    $skill -match '(?is)full-program `ai\.ps1 listen`'
Report 'skill follows the shared pattern and proves the exact delivery artifact' `
    $patternOk `
    'expected objective, routing, examples, exact-encoded proof, full-program listening, and final check'

Write-Host ''
Write-Host "SCOPE: skill, UI metadata, global policy cross-references, registry, 18 host mappings, and the approved-existing-clone/identity-gate boundary"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
