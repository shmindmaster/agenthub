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
    $Registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
} catch {
    $Failures.Add("registry.json unreadable: $($_.Exception.Message)")
    $Result = [ordered]@{ passed = $false; failures = $Failures.ToArray() }
    Write-Output ($Result | ConvertTo-Json -Depth 8)
    exit 1
}

$ExpectedPolicy = @{
    single_control_plane = $AiPs1Path
    single_model_root = Join-Path $Root 'models'
    single_artifact_root = Join-Path $Root 'artifacts'
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

$RequiredServiceIds = @('ollama', 'qdrant', 'retrieval', 'local-ai-api', 'open-webui', 'comfyui')
$servicesSeen = @{}
foreach ($service in $Registry.services) { $servicesSeen[$service.id] = $true }
foreach ($id in $RequiredServiceIds) {
    if (-not $servicesSeen.ContainsKey($id)) {
        $Failures.Add("required service missing from registry: $id")
    }
}

$RequiredIndexes = @('knowledge', 'legal')
foreach ($alias in $RequiredIndexes) {
    $index = $Registry.indexes | Where-Object { $_.stable_alias -eq $alias }
    if (-not $index) {
        $Failures.Add("required index alias missing: $alias")
    } elseif ($index.source_database -ne (Join-Path $Root 'shared\catalogs\corpus-v2.sqlite')) {
        $Failures.Add("index '$alias' must use the corpus-v2 catalog, found '$($index.source_database)'")
    }
}

$RequiredCapabilityIds = @('retrieval.text', 'retrieval.reranker', 'voice.qwen-design', 'voice.chatterbox', 'image.z-image-turbo')
$capabilitiesSeen = @{}
foreach ($capability in $Registry.capabilities) { $capabilitiesSeen[$capability.id] = $capability.status }
foreach ($capability in $RequiredCapabilityIds) {
    if (-not $capabilitiesSeen.ContainsKey($capability)) {
        $Failures.Add("required capability missing: $capability")
    } elseif ($capabilitiesSeen[$capability] -ne 'enabled') {
        $Failures.Add("required capability not enabled: $capability")
    }
}

if (-not ($Registry.storage.legal_evidence_roots -and $Registry.storage.legal_evidence_roots.Count -gt 0)) {
    $Failures.Add('legal_evidence_roots must be a non-empty list')
}

if ($Registry.storage.legal_evidence_policy -ne 'read-only') {
    $Failures.Add("legal_evidence_policy must be read-only, found '$($Registry.storage.legal_evidence_policy)'")
}

$forbiddenRoots = @('D:\AI-Platform', 'D:\ai-platform', 'D:\AIPlatform', 'D:\AI_PLAT')
$jsonBlob = (Get-Content -LiteralPath $RegistryPath -Raw)
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
    legal_evidence_policy = $Registry.storage.legal_evidence_policy
    required_services = $RequiredServiceIds
    required_indexes = $RequiredIndexes
    required_capabilities = $RequiredCapabilityIds
}

if ($Failures.Count -gt 0) {
    $Result['failures'] = $Failures.ToArray()
    Write-Output ($Result | ConvertTo-Json -Depth 8)
    exit 1
}

Write-Output ($Result | ConvertTo-Json -Depth 8)
Write-Output 'PASS: local-ai stack contract checks passed.'
exit 0
