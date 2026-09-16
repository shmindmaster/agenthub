#Requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('all', 'invalid', 'traversal', 'unapproved', 'approved')]
    [string]$Scenario = 'all',
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$demoRoot = $PSScriptRoot
$schemaPath = Join-Path $demoRoot 'decision.schema.json'
$policyPath = Join-Path $demoRoot 'policy.json'
$policyText = Get-Content -LiteralPath $policyPath -Raw
$policy = $policyText | ConvertFrom-Json

function Get-Sha256Text([string]$Text) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-CanonicalJsonHash([string]$Text) {
    $canonical = ($Text | ConvertFrom-Json) | ConvertTo-Json -Depth 100 -Compress
    Get-Sha256Text $canonical
}

function Write-Receipt([Collections.Specialized.OrderedDictionary]$Receipt, [string]$ReceiptRoot) {
    $receiptPath = Join-Path $ReceiptRoot ("{0}.receipt.json" -f $Receipt.scenario)
    $Receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    $receiptPath
}

function Invoke-Scenario([string]$Name, [string]$RunRoot) {
    $fixtureName = if ($Name -in @('invalid', 'traversal')) { $Name } else { 'write-request' }
    $approvalFile = if ($Name -eq 'approved') { 'granted' } else { 'empty' }
    $inputPath = Join-Path $demoRoot "fixtures/$fixtureName.json"
    $inputText = Get-Content -LiteralPath $inputPath -Raw
    $inputHash = Get-CanonicalJsonHash $inputText
    $policyHash = Get-CanonicalJsonHash $policyText

    if (-not ($inputText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
        $receipt = [ordered]@{
            receiptVersion = 1; scenario = $Name; decisionId = "demo-$Name"; result = 'rejected'
            reasonCodes = @('schema-invalid'); inputSha256 = $inputHash; policySha256 = $policyHash
            execution = [ordered]@{ attempted = $false; finalState = 'not-executed'; observedSha256 = $null }
            observedAt = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $path = Write-Receipt $receipt $RunRoot
        return [pscustomobject]@{ Scenario = $Name; Result = 'REJECTED'; Reason = 'schema-invalid'; Receipt = $path }
    }

    $decision = $inputText | ConvertFrom-Json
    $approvalStore = Get-Content -LiteralPath (Join-Path $demoRoot "approvals/$approvalFile.json") -Raw | ConvertFrom-Json
    $trustedApproval = @($approvalStore.approvals | Where-Object {
        $_.decisionId -eq $decision.decisionId -and
        $_.inputSha256 -eq $inputHash -and
        $_.granted -eq $true
    }) | Select-Object -First 1
    $reasons = [Collections.Generic.List[string]]::new()
    if ($decision.action -notin $policy.allowedActions) { $reasons.Add('action-not-allowed') }
    $pathSegments = @($decision.resource.path -split '/')
    if (@($pathSegments | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { $reasons.Add('path-dot-segment') }
    if ([IO.Path]::GetExtension($decision.resource.path) -in $policy.blockedExtensions) { $reasons.Add('extension-blocked') }
    if ([Text.UTF8Encoding]::new($false).GetByteCount($decision.resource.content) -gt $policy.maxWriteBytes) { $reasons.Add('write-too-large') }
    if ($policy.writesRequireApproval -and -not $trustedApproval) { $reasons.Add('approval-required') }
    $contentHash = Get-Sha256Text $decision.resource.content
    if ($contentHash -ne $decision.expectedOutcome.sha256) { $reasons.Add('expected-outcome-mismatch') }

    $attempted = $false
    $finalState = 'not-executed'
    $observedHash = $null
    $result = 'denied'
    if ($reasons.Count -eq 0) {
        $workspaceRoot = Join-Path $RunRoot $policy.allowedDirectory
        $targetPath = Join-Path $workspaceRoot ($decision.resource.path -replace '/', [IO.Path]::DirectorySeparatorChar)
        $resolvedRoot = [IO.Path]::GetFullPath($workspaceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolvedTarget = [IO.Path]::GetFullPath($targetPath)
        if (-not $resolvedTarget.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolved target escaped the bounded demo workspace.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedTarget) -Force | Out-Null
        [IO.File]::WriteAllText($resolvedTarget, $decision.resource.content, [Text.UTF8Encoding]::new($false))
        $attempted = $true
        $observedHash = (Get-FileHash -LiteralPath $resolvedTarget -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($observedHash -eq $decision.expectedOutcome.sha256) {
            $result = 'executed'; $finalState = 'expected-state-observed'
        } else {
            $result = 'failed'; $finalState = 'postcondition-failed'; $reasons.Add('observed-outcome-mismatch')
        }
    }

    $receipt = [ordered]@{
        receiptVersion = 1; scenario = $Name; decisionId = $decision.decisionId; result = $result; reasonCodes = @($reasons)
        inputSha256 = $inputHash; policySha256 = $policyHash; approval = $trustedApproval; evidenceRefs = $decision.evidenceRefs
        execution = [ordered]@{ attempted = $attempted; finalState = $finalState; observedSha256 = $observedHash }
        observedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $receiptPath = Write-Receipt $receipt $RunRoot
    [pscustomobject]@{
        Scenario = $Name; Result = $result.ToUpperInvariant()
        Reason = if ($reasons.Count -eq 0) { $finalState } else { $reasons -join ',' }
        Receipt = $receiptPath
    }
}

if ($OutputRoot -and (Test-Path -LiteralPath $OutputRoot)) {
    throw 'OutputRoot must not already exist. The demo creates and owns a fresh bounded workspace.'
}
if (-not $OutputRoot) { $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-assurance-demo/{0}" -f [guid]::NewGuid().ToString('n')) }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$scenarios = if ($Scenario -eq 'all') { @('invalid', 'traversal', 'unapproved', 'approved') } else { @($Scenario) }
$results = foreach ($name in $scenarios) { Invoke-Scenario -Name $name -RunRoot $OutputRoot }

Write-Host ''
Write-Host 'AgentHub Assurance Loop' -ForegroundColor Cyan
Write-Host 'Model proposes -> schema validates -> policy decides -> executor acts -> receipt proves observed state'
$results | Format-Table Scenario, Result, Reason -AutoSize
Write-Host "Receipts: $OutputRoot"
if (@($results | Where-Object Result -eq 'FAILED').Count -gt 0) { exit 1 }
