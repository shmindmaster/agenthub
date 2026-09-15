#Requires -Version 5.1
<#
Behavior tests for the fleet-wide Sarosh audio-voice contract.

sarosh-audio-voice is the audio counterpart to sarosh-communication: it
governs Sarosh's spoken/cloned voice (local Qwen3-TTS clone, voice id
`sarosh`, mandatory speaker-identity gate, dictionary-layer pronunciation),
while sarosh-communication governs written tone and structure. These tests
keep the skill identity, registry ownership, deployment reach, policy
cross-reference, scope-separation language, and the no-hosted-TTS boundary
aligned.

Run: pwsh -NoProfile -File tests/Test-SaroshAudioVoice.ps1
     powershell.exe -NoProfile -File tests/Test-SaroshAudioVoice.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$skillRoot = Join-Path $repoRoot 'packages\sarosh-audio-voice\skills\sarosh-audio-voice'
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
$owners = if ($registry) { @($registry.capabilities | Where-Object { 'sarosh-audio-voice' -in @($_.managedSkillNames) }) } else { @() }
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
    $capability.id -eq 'sarosh-audio-voice' -and
    $capability.capabilityType -eq 'skills' -and
    $capability.canonicalSource -eq 'packages/sarosh-audio-voice' -and
    $capability.hashBasis -eq 'packages/sarosh-audio-voice' -and
    $capability.status -eq 'active-canonical'
Report 'registry has one owner and all 17 managed host mappings' `
    ($registryOk -and $hostSetOk -and $mappingModesOk) `
    "owners=$($owners.Count), hosts=$($actualHosts.Count), expected managed-loose-skills on all 17 hosts"

# 3. Global policy cross-references the skill from Owner voice.
$policyOk = $policy -and
    $policy -match '(?m)^## Owner voice\s*$' -and
    $policy -match '(?is)load and apply\s+`sarosh-audio-voice`' -and
    $policy -match '(?is)generated speech in Sarosh''s voice.*`sarosh-audio-voice`' -and
    $policy -match '(?is)Local-AI voice id `sarosh` under `local-ai-stack`'
Report 'global policy routes owner voice through sarosh-audio-voice and Local-AI' `
    $policyOk `
    'expected Owner voice and the three-layer Sarosh policy to route audio through sarosh-audio-voice and local-ai-stack'

# 4. The skill encodes the hard local-only / no-hosted-TTS boundary.
$localOnlyOk = $skill -and
    $skill -match '(?is)Local-AI control plane' -and
    $skill -match '(?is)voice id \*\*`sarosh`\*\*' -and
    $skill -match '(?is)Never generate or\s+approximate this speaker through a hosted TTS provider' -and
    $skill -match '(?i)ElevenLabs'
Report 'skill states the local-only / no-hosted-TTS boundary' `
    $localOnlyOk `
    'expected explicit Local-AI-only routing for voice id sarosh and a no-hosted-TTS (ElevenLabs or other) rule'

# 5. The skill encodes the mandatory speaker-identity gate and expression vs.
#    identity distinction.
$identityGateOk = $skill -and
    $skill -match '(?is)speaker-identity gate' -and
    $skill -match '(?i)voice score --voice sarosh' -and
    $skill -match '(?is)Expression, emotion, and pacing are adjustable' -and
    $skill -match '(?is)Speaker identity is the fixed\s+constraint'
Report 'skill states the mandatory speaker-identity gate' `
    $identityGateOk `
    'expected the identity-gate command form and the expression-adjustable/identity-fixed distinction'

# 6. The skill states the pronunciation-is-a-dictionary-layer rule and never
#    training data / benchmarking-needs-approval rules from global policy.
$otherRulesOk = $skill -and
    $skill -match '(?is)Do not correct pronunciation by respelling' -and
    $skill -match '(?is)dictionary layer applied at\s+render time' -and
    $skill -match '(?is)not training data for an\s+external service' -and
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
    $skill -match '(?is)both enrolled identity backends' -and
    $skill -match '(?is)exact mixed and encoded delivery artifact' -and
    $skill -match '(?is)full-program `ai\.ps1 listen`'
Report 'skill follows the shared pattern and proves the exact delivery artifact' `
    $patternOk `
    'expected objective, routing, examples, exact-encoded proof, full-program listening, and final check'

Write-Host ''
Write-Host "SCOPE: skill, UI metadata, global policy cross-references, registry, 17 host mappings, and the local-only/identity-gate boundary"
Write-Host "RESULT: $($reported - $failures.Count) passed, $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
