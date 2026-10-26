#Requires -Version 7
<#
Provision (idempotently) the shared cloud render path in the owner's own Azure tenant.
Subscription and tenant come from -SubscriptionId/-TenantId or CLOUD_RENDER_SUBSCRIPTION_ID/CLOUD_RENDER_TENANT_ID;
they are never written into this public repository.

Creates, in one resource group:
  - a StorageV2 account (Standard_LRS, shared-key access off, no public blob access) with containers
    runtime / cas / jobs and a lifecycle rule (jobs/ after 7 days, cas/ after 30 days);
  - a consumption-only Container Apps environment (no Log Analytics: the worker writes its own log to Blob);
  - a manual-trigger Container Apps job on mcr.microsoft.com/playwright (scale to zero: it bills only while running);
  - Storage Blob Data Contributor for the job's managed identity and for the signed-in user;
  - an Azure OpenAI (AIServices) account with a gpt-5-mini deployment, key auth disabled, for cloud-ai.mjs;
  - a monthly cost budget on the resource group with e-mail alerts.
Writes the non-secret resource names and list prices to %LOCALAPPDATA%\AgentHub\media-studio\cloud-render.json.

Nothing here bills while idle except Blob capacity (cents per GB-month).
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = $env:CLOUD_RENDER_SUBSCRIPTION_ID,
    [string]$TenantId = $env:CLOUD_RENDER_TENANT_ID,
    [string]$ResourceGroup = 'rg-media-render',
    [string]$Location = 'centralus',
    [string]$Image = 'mcr.microsoft.com/playwright:v1.63.0-noble',
    [double]$Cpu = 4,
    [string]$Memory = '8Gi',
    [int]$BudgetUsd = 20,
    [string]$AoaiLocation = 'eastus2',
    [string]$AoaiModel = 'gpt-5-mini',
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA 'AgentHub\media-studio\cloud-render.json')
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-Az {
    $out = & az @args --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "az $($args[0..2] -join ' ') failed" }
    $out
}
function Invoke-Arm([string]$Method, [string]$Path, $Body) {
    $url = "https://management.azure.com$Path"
    if ($null -eq $Body) { return Invoke-Az rest --method $Method --url $url | ConvertFrom-Json }
    $tmp = New-TemporaryFile
    try {
        $Body | ConvertTo-Json -Depth 30 -Compress | Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
        Invoke-Az rest --method $Method --url $url --body "@$tmp" --headers 'Content-Type=application/json' | ConvertFrom-Json
    } finally { Remove-Item -LiteralPath $tmp -Force }
}

if (-not $SubscriptionId -or -not $TenantId) { throw 'Set -SubscriptionId and -TenantId (or CLOUD_RENDER_SUBSCRIPTION_ID / CLOUD_RENDER_TENANT_ID) to the owner subscription and tenant.' }
$account = Invoke-Az account show --subscription $SubscriptionId -o json | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) { throw "Subscription $SubscriptionId is in tenant $($account.tenantId), not the owner tenant $TenantId. Refusing." }
$user = $account.user.name
$userId = Invoke-Az ad signed-in-user show --query id -o tsv
Write-Host "Subscription: $($account.name) ($SubscriptionId) as $user"

$state = Invoke-Az provider show -n Microsoft.App --subscription $SubscriptionId --query registrationState -o tsv
if ($state -ne 'Registered') {
    Invoke-Az provider register -n Microsoft.App --subscription $SubscriptionId --wait | Out-Null
}

$suffix = $SubscriptionId.Replace('-', '').Substring(0, 8)
$storage = "stmrender$suffix"
$envName = 'cae-media-render'
$jobName = 'caj-media-render'
$rgPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

Invoke-Az group create -n $ResourceGroup -l $Location --subscription $SubscriptionId --tags purpose=media-render owner=owner -o none

if (-not (Invoke-Az storage account list -g $ResourceGroup --subscription $SubscriptionId --query "[?name=='$storage'].name" -o tsv)) {
    Invoke-Az storage account create -n $storage -g $ResourceGroup -l $Location --subscription $SubscriptionId `
        --sku Standard_LRS --kind StorageV2 --access-tier Hot --min-tls-version TLS1_2 `
        --allow-blob-public-access false --allow-shared-key-access false -o none
}
$storageId = "$rgPath/providers/Microsoft.Storage/storageAccounts/$storage"
foreach ($c in 'runtime', 'cas', 'jobs') {
    Invoke-Arm PUT "$storageId/blobServices/default/containers/$c`?api-version=2023-05-01" @{ properties = @{ publicAccess = 'None' } } | Out-Null
}
Invoke-Arm PUT "$storageId/managementPolicies/default?api-version=2023-05-01" @{
    properties = @{ policy = @{ rules = @(
        @{ enabled = $true; name = 'expire-jobs'; type = 'Lifecycle'; definition = @{ filters = @{ blobTypes = @('blockBlob'); prefixMatch = @('jobs/') }; actions = @{ baseBlob = @{ delete = @{ daysAfterModificationGreaterThan = 7 } } } } },
        @{ enabled = $true; name = 'expire-cas'; type = 'Lifecycle'; definition = @{ filters = @{ blobTypes = @('blockBlob'); prefixMatch = @('cas/') }; actions = @{ baseBlob = @{ delete = @{ daysAfterModificationGreaterThan = 30 } } } } }
    ) } }
} | Out-Null

$blobContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
function Grant-BlobRole([string]$PrincipalId, [string]$Type) {
    $existing = Invoke-Az role assignment list --scope $storageId --assignee-object-id $PrincipalId --role $blobContributor --subscription $SubscriptionId --query '[].id' -o tsv
    if (-not $existing) {
        Invoke-Az role assignment create --scope $storageId --assignee-object-id $PrincipalId --assignee-principal-type $Type --role $blobContributor --subscription $SubscriptionId -o none
    }
}
Grant-BlobRole $userId 'User'

$envPath = "$rgPath/providers/Microsoft.App/managedEnvironments/$envName"
Invoke-Arm PUT "$envPath`?api-version=2024-03-01" @{
    location = $Location
    properties = @{ workloadProfiles = @(@{ name = 'Consumption'; workloadProfileType = 'Consumption' }) }
} | Out-Null
for ($i = 0; $i -lt 60; $i++) {
    $envState = (Invoke-Arm GET "$envPath`?api-version=2024-03-01" $null).properties.provisioningState
    if ($envState -eq 'Succeeded') { break }
    if ($envState -eq 'Failed') { throw 'Container Apps environment failed to provision' }
    Start-Sleep -Seconds 10
}

# The loader fetches worker.mjs + blob.mjs from runtime/ with the managed identity, then imports the worker.
$loader = @'
const e=process.env;const fs=await import('node:fs');fs.mkdirSync('/tmp/cr',{recursive:true});
const t=(await(await fetch(e.IDENTITY_ENDPOINT+'?resource=https://storage.azure.com/&api-version=2019-08-01',{headers:{'X-IDENTITY-HEADER':e.IDENTITY_HEADER}})).json()).access_token;
for(const f of ['blob.mjs','worker.mjs']){const r=await fetch('https://'+e.STORAGE_ACCOUNT+'.blob.core.windows.net/runtime/'+f,{headers:{Authorization:'Bearer '+t,'x-ms-version':'2023-11-03'}});if(!r.ok)throw new Error(f+' HTTP '+r.status);fs.writeFileSync('/tmp/cr/'+f,await r.text());}
await import('/tmp/cr/worker.mjs');
'@ -replace "`r?`n", ''

$jobPath = "$rgPath/providers/Microsoft.App/jobs/$jobName"
$job = Invoke-Arm PUT "$jobPath`?api-version=2024-03-01" @{
    location = $Location
    identity = @{ type = 'SystemAssigned' }
    properties = @{
        environmentId = $envPath
        workloadProfileName = 'Consumption'
        configuration = @{ triggerType = 'Manual'; replicaTimeout = 7200; replicaRetryLimit = 0; manualTriggerConfig = @{ parallelism = 1; replicaCompletionCount = 1 } }
        template = @{ containers = @(@{
            name = 'render'; image = $Image
            command = @('node'); args = @('--input-type=module', '-e', $loader)
            env = @(@{ name = 'STORAGE_ACCOUNT'; value = $storage })
            resources = @{ cpu = $Cpu; memory = $Memory }
        }) }
    }
}
for ($i = 0; $i -lt 60 -and -not $job.identity.principalId; $i++) {
    Start-Sleep -Seconds 5
    $job = Invoke-Arm GET "$jobPath`?api-version=2024-03-01" $null
}
Grant-BlobRole $job.identity.principalId 'ServicePrincipal'

# Budget on the resource group: alerts at 50% and 90% actual, 100% forecast.
try {
$start = (Get-Date -Day 1).ToString('yyyy-MM-01')
Invoke-Arm PUT "$rgPath/providers/Microsoft.Consumption/budgets/media-render-monthly?api-version=2023-05-01" @{
    properties = @{
        category = 'Cost'; amount = $BudgetUsd; timeGrain = 'Monthly'
        timePeriod = @{ startDate = "$start`T00:00:00Z"; endDate = '2028-12-31T00:00:00Z' }
        notifications = @{
            actual50 = @{ enabled = $true; operator = 'GreaterThanOrEqualTo'; threshold = 50; thresholdType = 'Actual'; contactEmails = @($user) }
            actual90 = @{ enabled = $true; operator = 'GreaterThanOrEqualTo'; threshold = 90; thresholdType = 'Actual'; contactEmails = @($user) }
            forecast100 = @{ enabled = $true; operator = 'GreaterThanOrEqualTo'; threshold = 100; thresholdType = 'Forecasted'; contactEmails = @($user) }
        }
    }
} | Out-Null
} catch { Write-Warning "Budget not created ($($_.Exception.Message)). Create it in Cost Management for $ResourceGroup." }

# Azure OpenAI for cloud-ai.mjs (client-safe QA/review in this tenant). Pay per token, nothing idle; key auth is
# disabled, so callers use Entra tokens. Only gpt-5-mini has GlobalStandard quota on this subscription (2026-10-26).
$aoai = "aoai-mrender-$suffix"
if (-not (Invoke-Az cognitiveservices account list -g $ResourceGroup --subscription $SubscriptionId --query "[?name=='$aoai'].name" -o tsv)) {
    Invoke-Az cognitiveservices account create -n $aoai -g $ResourceGroup -l $AoaiLocation --kind AIServices --sku S0 --custom-domain $aoai --subscription $SubscriptionId --tags purpose=media-render owner=owner --yes -o none
}
$aoaiId = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$aoai"
Invoke-Az resource update --ids $aoaiId --set properties.disableLocalAuth=true -o none
if (-not (Invoke-Az cognitiveservices account deployment list -n $aoai -g $ResourceGroup --subscription $SubscriptionId --query "[?name=='$AoaiModel'].name" -o tsv)) {
    $aoaiVersion = (Invoke-Az cognitiveservices model list -l $AoaiLocation --subscription $SubscriptionId -o json | ConvertFrom-Json | Where-Object { $_.model.name -eq $AoaiModel -and $_.model.format -eq 'OpenAI' } | Select-Object -First 1).model.version
    Invoke-Az cognitiveservices account deployment create -n $aoai -g $ResourceGroup --subscription $SubscriptionId --deployment-name $AoaiModel --model-name $AoaiModel --model-version $aoaiVersion --model-format OpenAI --sku-name GlobalStandard --sku-capacity 100 -o none
}
if (-not (Invoke-Az role assignment list --scope $aoaiId --assignee-object-id $userId --role 'Cognitive Services OpenAI User' --subscription $SubscriptionId --query '[].id' -o tsv)) {
    Invoke-Az role assignment create --scope $aoaiId --assignee-object-id $userId --assignee-principal-type User --role 'Cognitive Services OpenAI User' --subscription $SubscriptionId -o none
}

# List prices for the cost estimate (consumption plan, this region).
$filter = [uri]::EscapeDataString("serviceName eq 'Azure Container Apps' and armRegionName eq '$Location' and priceType eq 'Consumption'")
$items = (Invoke-RestMethod "https://prices.azure.com/api/retail/prices?`$filter=$filter").Items
$vcpu = ($items | Where-Object { $_.meterName -match 'vCPU Active Usage' -and $_.skuName -eq 'Standard' -and $_.unitPrice -gt 0 } | Select-Object -First 1)
$mem = ($items | Where-Object { $_.meterName -match 'Memory Active Usage' -and $_.skuName -eq 'Standard' -and $_.unitPrice -gt 0 } | Select-Object -First 1)
$pricing = [ordered]@{
    vcpuSecond = if ($vcpu) { [double]$vcpu.unitPrice / ($(if ($vcpu.unitOfMeasure -match 'Hour') { 3600 } else { 1 })) } else { 0.000024 }
    gibSecond = if ($mem) { [double]$mem.unitPrice / ($(if ($mem.unitOfMeasure -match 'Hour') { 3600 } else { 1 })) } else { 0.000003 }
    source = if ($vcpu -and $mem) { "prices.azure.com $Location $((Get-Date).ToString('yyyy-MM-dd')): $($vcpu.meterName) $($vcpu.unitPrice)/$($vcpu.unitOfMeasure); $($mem.meterName) $($mem.unitPrice)/$($mem.unitOfMeasure)" } else { 'fallback list price' }
    monthlyFreeGrant = '180000 vCPU-s + 360000 GiB-s per subscription'
}

$config = [ordered]@{
    subscriptionId = $SubscriptionId; tenantId = $TenantId; resourceGroup = $ResourceGroup; location = $Location
    storageAccount = $storage; environment = $envName; jobName = $jobName; image = $Image
    azureOpenAI = [ordered]@{ account = $aoai; endpoint = "https://$aoai.cognitiveservices.azure.com/"; deployment = $AoaiModel; location = $AoaiLocation; auth = 'entra' }
    pricing = $pricing; provisionedAt = (Get-Date).ToString('o')
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath -Encoding utf8NoBOM
Write-Host "Provisioned. Config: $ConfigPath"
$config | ConvertTo-Json -Depth 5
