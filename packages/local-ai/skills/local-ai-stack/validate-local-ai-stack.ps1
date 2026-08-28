#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$Root = $(if ($env:LOCAL_AI_ROOT) { $env:LOCAL_AI_ROOT } else { 'D:\Local-AI' })
)

$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($Root)
$RegistryPath = Join-Path $Root 'registry.json'
$AiPs1Path = Join-Path $Root 'ai.ps1'
$Result = [ordered]@{}
$Failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $Root)) {
    $Failures.Add("Control root missing: $Root")
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    $Failures.Add("registry.json missing: $RegistryPath")
}

if (-not (Test-Path -LiteralPath $AiPs1Path)) {
    $Failures.Add("Canonical control interface missing: $AiPs1Path")
}

if ($Failures.Count -gt 0) {
    $Result = [ordered]@{ passed = $false; failures = $Failures.ToArray() }
    Write-Output ($Result | ConvertTo-Json -Depth 8)
    exit 1
}

try {
    $Registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    $Failures.Add("registry.json unreadable: $($_.Exception.Message)")
    $Result = [ordered]@{ passed = $false; failures = $Failures.ToArray() }
    Write-Output ($Result | ConvertTo-Json -Depth 8)
    exit 1
}

$ExpectedPolicy = @{
    single_control_plane = $AiPs1Path
    single_model_root = Join-Path $Root 'models'
    single_artifact_root = Join-Path $Root 'data\artifacts'
    single_vector_engine = 'qdrant'
    gpu_heavy_jobs = 'serialized'
}

foreach ($entry in $ExpectedPolicy.GetEnumerator()) {
    $actual = $Registry.policy.($entry.Key)
    if ([string]::IsNullOrWhiteSpace($actual) -or ($actual -notin @($entry.Value))) {
        $Failures.Add("policy.$($entry.Key) must be '$($entry.Value)', found '$actual'")
    }
}

if ($Registry.policy.external_data_transmission -ne 'explicit-approval-required') {
    $Failures.Add("policy.external_data_transmission must be explicit-approval-required")
}

if ([int]$Registry.schema_version -lt 4) {
    $Failures.Add("registry.schema_version must be 4 or newer for the durable platform contract")
}

$Platform = $Registry.platform
if (-not $Platform -or [string]::IsNullOrWhiteSpace([string]$Platform.registry_revision)) {
    $Failures.Add('platform.registry_revision is required')
} else {
    $ExpectedTiers = @('preview', 'standard', 'high', 'identity-critical')
    foreach ($tier in $ExpectedTiers) {
        if (-not $Platform.quality_tiers.PSObject.Properties[$tier]) {
            $Failures.Add("platform.quality_tiers missing stable tier '$tier'")
        }
    }
    if ($Platform.execution_policy -ne 'local-only') {
        $Failures.Add("platform.execution_policy must be local-only")
    }
    if ($Platform.job_database -ne (Join-Path $Root 'data\runtime\platform\jobs.sqlite')) {
        $Failures.Add("platform.job_database must be under the Local-AI runtime root")
    }
    if ($Platform.job_artifact_root -ne (Join-Path $Root 'data\artifacts\jobs')) {
        $Failures.Add("platform.job_artifact_root must be under the declared artifact root")
    }
    $RequiredGatewayEndpoints = @('/local/chat', '/local/retrieve', '/local/voice', '/local/image', '/local/asr', '/local/jobs')
    foreach ($endpoint in $RequiredGatewayEndpoints) {
        if ($endpoint -notin @($Platform.gateway.endpoints)) {
            $Failures.Add("platform.gateway.endpoints missing '$endpoint'")
        }
    }
    if ($Platform.gateway.cloud_fallback -ne 'forbidden') {
        $Failures.Add('platform.gateway.cloud_fallback must be forbidden')
    }
}

$AiSource = Get-Content -LiteralPath $AiPs1Path -Raw -Encoding UTF8
foreach ($surface in @('capabilities', 'capability', 'doctor', 'job', 'route', 'qa', 'knowledge', 'docs')) {
    if ($AiSource -notmatch "'$([regex]::Escape($surface))'") {
        $Failures.Add("ai.ps1 does not expose required platform surface '$surface'")
    }
}

# Services are derived from the registry's own `required` flag, not a list
# frozen here. The frozen list said ollama, qdrant, retrieval, local-ai-api,
# open-webui, comfyui. Two problems, both real as of 2026-08-04:
#   - it demanded comfyui, which the registry marks required=false, so this
#     validator would fail a stack the stack itself considers valid;
#   - it never mentioned knowledge-workbench or llama-cpp, which the live stack
#     has run for some time -- their appearance went unnoticed, and their
#     disappearance would too.
# A validator that pins an inventory goes stale silently and constrains the
# stack to whatever was true the day it was written. The registry already
# declares which services are load-bearing; this reads that declaration.
$declaredServices = @($Registry.services)
if ($declaredServices.Count -eq 0) {
    $Failures.Add('registry declares zero services; refusing to pass an empty service contract')
}
$requiredServices = @($declaredServices | Where-Object { $_.required -eq $true })
if ($declaredServices.Count -gt 0 -and $requiredServices.Count -eq 0) {
    # Every service optional means this check would pass no matter what the
    # stack looked like. That is not a contract.
    $Failures.Add('no service is marked required=true; the registry declares no load-bearing service contract to check against')
}
foreach ($service in $requiredServices) {
    if ([string]::IsNullOrWhiteSpace([string]$service.id)) {
        $Failures.Add('a service marked required=true has no id')
        continue
    }
    foreach ($field in @('port', 'health')) {
        if (-not $service.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$service.$field)) {
            $Failures.Add("required service '$($service.id)' declares no $field")
        }
    }
}

$RequiredIndexes = @('knowledge', 'legal')
foreach ($alias in $RequiredIndexes) {
    $index = $Registry.indexes | Where-Object { $_.stable_alias -eq $alias }
    if (-not $index) {
        $Failures.Add("required index alias missing: $alias")
    } elseif ($index.source_database -ne (Join-Path $Root 'data\catalog\corpus-v2.sqlite')) {
        $Failures.Add("index '$alias' must use the corpus-v2 catalog, found '$($index.source_database)'")
    }
}

# The capability inventory is OPEN and expected to grow. The frozen list here
# named five capabilities while the live stack declares fourteen -- so nine
# were invisible to validation, including every video and music capability and
# the whole llama-cpp provider. Pinning an inventory does not just go stale; it
# quietly discourages adopting anything newer, because new entries are neither
# checked nor acknowledged.
#
# So only the retrieval spine is asserted by id, and only because the RAG route
# this skill documents cannot function without it. Everything else -- image,
# voice, STT, video, music, providers, and whatever open-source model is
# adopted next -- is discretionary inventory: validated for SHAPE so a new
# entry is properly described, never for membership.
$declaredCapabilities = @($Registry.capabilities)
if ($declaredCapabilities.Count -eq 0) {
    $Failures.Add('registry declares zero capabilities; refusing to pass an empty capability contract')
}
$capabilitiesSeen = @{}
foreach ($capability in $declaredCapabilities) { $capabilitiesSeen[$capability.id] = $capability.status }

# Load-bearing floor: the documented retrieval route depends on these two.
$RetrievalSpine = @('retrieval.text', 'retrieval.reranker')
foreach ($capability in $RetrievalSpine) {
    if (-not $capabilitiesSeen.ContainsKey($capability)) {
        $Failures.Add("retrieval spine capability missing: $capability (the RAG route documented in SKILL.md cannot resolve without it)")
    } elseif ($capabilitiesSeen[$capability] -ne 'enabled') {
        $Failures.Add("retrieval spine capability not enabled: $capability")
    }
}

# Shape contract for everything declared. This is what keeps an open inventory
# honest: adopt any model you like, but describe it the same way as the rest,
# so routing and GPU planning can reason about it.
foreach ($capability in $declaredCapabilities) {
    $id = [string]$capability.id
    if ([string]::IsNullOrWhiteSpace($id)) {
        $Failures.Add('a declared capability has no id')
        continue
    }
    foreach ($field in @('category', 'status')) {
        if (-not $capability.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$capability.$field)) {
            $Failures.Add("capability '$id' declares no $field")
        }
    }
    # An enabled capability is one an agent may route to, so it has to say how
    # it is reached and how its presence was established.
    if ([string]$capability.status -eq 'enabled') {
        if (-not $capability.PSObject.Properties['verification'] -or [string]::IsNullOrWhiteSpace([string]$capability.verification)) {
            $Failures.Add("enabled capability '$id' declares no verification")
        }
        $hasEntrypoint = $capability.PSObject.Properties['entrypoint'] -and -not [string]::IsNullOrWhiteSpace([string]$capability.entrypoint)
        $hasFiles = $capability.PSObject.Properties['required_files'] -and @($capability.required_files).Count -gt 0
        if (-not $hasEntrypoint -and -not $hasFiles) {
            $Failures.Add("enabled capability '$id' declares neither an entrypoint nor required_files, so nothing can confirm it is actually reachable")
        }
        $override = $Platform.capability_overrides.PSObject.Properties[$id].Value
        if (-not $override) {
            $Failures.Add("enabled capability '$id' has no platform.capability_overrides contract")
        } else {
            foreach ($field in @('required_services', 'resource_profile', 'privacy_classes', 'quality_tiers', 'fallback')) {
                if (-not $override.PSObject.Properties[$field]) {
                    $Failures.Add("platform override '$id' declares no $field")
                }
            }
        }
    }
}

if (-not ($Registry.storage.legal_evidence_roots -and $Registry.storage.legal_evidence_roots.Count -gt 0)) {
    $Failures.Add('legal_evidence_roots must be a non-empty list')
}

if ($Registry.storage.legal_evidence_policy -ne 'read-only') {
    $Failures.Add("legal_evidence_policy must be read-only, found '$($Registry.storage.legal_evidence_policy)'")
}

$forbiddenRoots = @('D:\AI-Platform', 'D:\ai-platform', 'D:\AIPlatform', 'D:\AI_PLAT')
$jsonBlob = (Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8)
foreach ($forbidden in $forbiddenRoots) {
    if ($Registry.root -like "*$forbidden*") {
        $Failures.Add("forbidden root value in registry.root: $forbidden")
    }
    if ($jsonBlob -match [regex]::Escape($forbidden)) {
        $Failures.Add("forbidden stack reference in registry content: $forbidden")
        break
    }
}

$Result = [ordered]@{
    passed = ($Failures.Count -eq 0)
    stack_id = $Registry.stack_id
    root = $Registry.root
    policy_single_control_plane = $Registry.policy.single_control_plane
    gpu_model = $Registry.policy.gpu_heavy_jobs
    registry_revision = $Platform.registry_revision
    execution_policy = $Platform.execution_policy
    legal_evidence_policy = $Registry.storage.legal_evidence_policy
    # Report what was actually checked, derived the same way the checks were.
    # These fields previously named variables that no longer existed and
    # serialized as null -- a report claiming to have verified nothing while
    # exiting 0.
    required_services = @($requiredServices | ForEach-Object { [string]$_.id })
    optional_services = @($declaredServices | Where-Object { $_.required -ne $true } | ForEach-Object { [string]$_.id })
    required_indexes = $RequiredIndexes
    retrieval_spine = $RetrievalSpine
    # Discretionary inventory: shape-checked, never membership-checked, so the
    # stack stays free to adopt newer models without editing this validator.
    declared_capabilities = @($declaredCapabilities | ForEach-Object { [string]$_.id })
    enabled_capability_count = @($declaredCapabilities | Where-Object { [string]$_.status -eq 'enabled' }).Count
}

if ($Failures.Count -gt 0) {
    $Result['failures'] = $Failures.ToArray()
    Write-Output ($Result | ConvertTo-Json -Depth 8)
    exit 1
}

Write-Output ($Result | ConvertTo-Json -Depth 8)
Write-Output 'PASS: local-ai stack contract checks passed.'
exit 0
