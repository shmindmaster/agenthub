#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only inventory of CodeBuild pull-request CI in one account.

.DESCRIPTION
  Prints a dated inventory for the caller's account: masked caller identity,
  CodeBuild projects with source and webhook configuration, CodeConnections
  connection status, the concurrent-build quota, and build minutes for the
  last 30 days. Every AWS call is list, describe, get, or batch-get.

  This file does not provision infrastructure. Run it only from an operator
  session that already has the named profile. See
  docs/runbooks/codebuild-pr-ci.md.

.PARAMETER Profile
  AWS CLI profile name. Required unless -SelfTest is set.

.PARAMETER Region
  AWS region code, for example us-east-1. Required unless -SelfTest is set.

.PARAMETER SelfTest
  Runs local checks of the account mask and the read-only guard. Does not
  call AWS.
#>
[CmdletBinding()]
param(
    [string]$Profile,
    [string]$Region,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$script:ReadOnlyOperationPattern = '^(list-|describe-|get-|batch-get-)'
$script:ReadOnlyServicePattern = '^[a-z][a-z0-9-]*$'
$script:MaxBuildPages = 20

function Hide-AwsAccount {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $arn = [regex]'arn:[A-Za-z0-9-]+:[A-Za-z0-9-]+:[A-Za-z0-9-]*:(\d{12}):'
    $arnEvaluator = [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $id = $m.Groups[1].Value
        $start = $m.Groups[1].Index - $m.Index
        return $m.Value.Substring(0, $start) + ('********' + $id.Substring(8)) + $m.Value.Substring($start + 12)
    }
    $masked = $arn.Replace($Text, $arnEvaluator)
    $bare = [regex]'(?<!\d)(\d{12})(?!\d)'
    $bareEvaluator = [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        return '********' + $m.Groups[1].Value.Substring(8)
    }
    return $bare.Replace($masked, $bareEvaluator)
}

function Format-ReadOnlyAwsError {
    param([string]$Service, [string]$Operation, [int]$Code, [string]$Detail)
    return Hide-AwsAccount ("aws $Service $Operation exited $Code. " + $Detail)
}

function Write-InventoryLine {
    param([string]$Text)
    Write-Host (Hide-AwsAccount $Text)
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function ConvertTo-UtcOffset {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [double]$Value
        if ($number -gt 100000000000) { return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$number) }
        return [DateTimeOffset]::FromUnixTimeSeconds([int64]$number)
    }
    return [DateTimeOffset]::Parse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
}

function Use-ReadOnlyAws {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    if ($ArgumentList.Count -lt 2) { throw 'aws command is missing a service and an operation' }
    $service = $ArgumentList[0]
    $operation = $ArgumentList[1]
    if ($service -notmatch $script:ReadOnlyServicePattern) { throw "blocked service token: $service" }
    if ($operation -notmatch $script:ReadOnlyOperationPattern) { throw "blocked operation: $operation" }
    foreach ($token in $ArgumentList) {
        if ($token -match '[\r\n]') { throw 'blocked argument with a line break' }
    }
    $cli = @($ArgumentList) + @('--profile', $Profile, '--region', $Region, '--output', 'json', '--no-cli-pager')
    $stdoutPath = [IO.Path]::GetTempFileName()
    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & aws @cli 1>$stdoutPath 2>$stderrPath
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previous
        }
        $stdoutText = [IO.File]::ReadAllText($stdoutPath)
        $stderrText = [IO.File]::ReadAllText($stderrPath)
        if ($code -ne 0) {
            $detail = $stderrText.Trim()
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $stdoutText.Trim() }
            throw (Format-ReadOnlyAwsError -Service $service -Operation $operation -Code $code -Detail $detail)
        }
        if ([string]::IsNullOrWhiteSpace($stdoutText)) { return $null }
        try {
            return ($stdoutText | ConvertFrom-Json)
        } catch {
            throw (Hide-AwsAccount ("aws $service $operation returned text that was not JSON. " + $_.Exception.Message))
        }
    } finally {
        [IO.File]::Delete($stdoutPath)
        [IO.File]::Delete($stderrPath)
    }
}

function Invoke-PreflightSelfTest {
    $sample = 'arn:aws:iam::000000000000:user/example'
    $masked = Hide-AwsAccount $sample
    $expected = 'arn:aws:iam::********0000:user/example'
    if ($masked -cne $expected) { throw 'account mask did not keep only the last 4 digits of an ARN account' }
    $bare = Hide-AwsAccount 'account 000000000000 end'
    if ($bare -cne 'account ********0000 end') { throw 'account mask did not mask a bare 12 digit account' }
    if ($bare -match '000000000000') { throw 'account mask left a bare account id in place' }
    $iso = Hide-AwsAccount 'arn:aws-iso:iam::000000000000:user/example'
    if ($iso -cne 'arn:aws-iso:iam::********0000:user/example') { throw 'account mask did not mask an aws-iso ARN' }
    $denied = Format-ReadOnlyAwsError -Service 'sts' -Operation 'get-caller-identity' -Code 254 -Detail 'User: arn:aws:iam::000000000000:user/example is not authorized'
    if ($denied -match '000000000000') { throw 'error path left an account id in the message' }
    if ($denied -notmatch 'arn:aws:iam::\*\*\*\*\*\*\*\*0000:user/example') { throw 'error path did not mask the caller ARN' }
    $stdoutShaped = Format-ReadOnlyAwsError -Service 'sts' -Operation 'get-caller-identity' -Code 254 -Detail 'account 000000000000 end'
    if ($stdoutShaped -match '000000000000') { throw 'stdout error path left a bare account id' }
    if ('list-projects' -notmatch $script:ReadOnlyOperationPattern) { throw 'guard blocked list-projects' }
    if ('batch-get-builds' -notmatch $script:ReadOnlyOperationPattern) { throw 'guard blocked batch-get-builds' }
    if ('get-caller-identity' -notmatch $script:ReadOnlyOperationPattern) { throw 'guard blocked get-caller-identity' }
    if ('describe-stacks' -notmatch $script:ReadOnlyOperationPattern) { throw 'guard blocked describe-stacks' }
    $blockedVerb = -join @('s', 't', 'a', 'r', 't')
    $blocked = $blockedVerb + '-build'
    if ($blocked -match $script:ReadOnlyOperationPattern) { throw 'guard allowed a blocked operation' }
    foreach ($serviceName in @('sts', 'codebuild', 'codeconnections', 'codestar-connections', 'service-quotas')) {
        if ($serviceName -notmatch $script:ReadOnlyServicePattern) { throw "guard blocked service $serviceName" }
    }
    Write-Host 'SELFTEST ok'
}

if ($SelfTest) {
    Invoke-PreflightSelfTest
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Profile) -or [string]::IsNullOrWhiteSpace($Region)) {
    throw 'Profile and Region are required. Pass -SelfTest to run the local checks instead.'
}
if ($Profile.StartsWith('-')) { throw 'Profile must not start with a dash' }
if ($Profile -notmatch '^[A-Za-z0-9_+=,.@][A-Za-z0-9_+=,.@-]{0,63}$') { throw 'Profile contains unsupported characters' }
if ($Region -notmatch '^[a-z]{2}(-[a-z]+)+-\d+$') { throw 'Region is not an AWS region code' }
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'aws CLI was not found on PATH' }

function Test-SafeCliValue {
    param([string]$Value, [string]$Label)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:/=+-]{0,512}$') {
        throw "$Label is not a safe CLI value"
    }
}

function Get-PagedList {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$ItemProperty,
        [string]$TokenProperty = 'nextToken',
        [int]$PageCap = 50
    )
    $items = New-Object System.Collections.Generic.List[object]
    $token = $null
    $pages = 0
    do {
        $pages++
        if ($pages -gt $PageCap) { throw "page cap reached for $($ArgumentList[0]) $($ArgumentList[1])" }
        $args = @($ArgumentList)
        if (-not [string]::IsNullOrWhiteSpace($token)) { $args += @('--next-token', $token) }
        $page = Use-ReadOnlyAws -ArgumentList $args
        $batch = @(Get-Prop $page $ItemProperty)
        if ($batch.Count -eq 1 -and $null -eq $batch[0]) { $batch = @() }
        foreach ($item in $batch) { if ($null -ne $item) { $items.Add($item) } }
        $token = [string](Get-Prop $page $TokenProperty)
        if ([string]::IsNullOrWhiteSpace($token)) { $token = [string](Get-Prop $page 'NextToken') }
    } while (-not [string]::IsNullOrWhiteSpace($token))
    return $items
}

$now = [DateTimeOffset]::UtcNow
$cutoff = $now.AddDays(-30)
Write-InventoryLine 'CodeBuild preflight'
Write-InventoryLine ('date-utc: ' + $now.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-InventoryLine ('region: ' + $Region)
Write-InventoryLine ('profile: ' + $Profile)
Write-InventoryLine 'window-days: 30'
Write-InventoryLine 'mode: read-only'

$identity = Use-ReadOnlyAws -ArgumentList @('sts', 'get-caller-identity')
$account = [string](Get-Prop $identity 'Account')
if ($account -notmatch '^\d{12}$') { throw 'caller account was not a 12 digit id' }
Write-InventoryLine ('caller-account: ********' + $account.Substring(8))
Write-InventoryLine ('caller-arn: ' + (Hide-AwsAccount ([string](Get-Prop $identity 'Arn'))))

$projectNames = @(Get-PagedList -ArgumentList @('codebuild', 'list-projects', '--sort-by', 'NAME') -ItemProperty 'projects')
Write-InventoryLine ('projects: ' + $projectNames.Count)

for ($offset = 0; $offset -lt $projectNames.Count; $offset += 100) {
    $end = [Math]::Min($offset + 99, $projectNames.Count - 1)
    $slice = @($projectNames[$offset..$end])
    foreach ($name in $slice) { Test-SafeCliValue -Value ([string]$name) -Label 'project name' }
    $batch = Use-ReadOnlyAws -ArgumentList (@('codebuild', 'batch-get-projects', '--names') + $slice)
    foreach ($project in @(Get-Prop $batch 'projects')) {
        if ($null -eq $project) { continue }
        $name = [string](Get-Prop $project 'name')
        Write-InventoryLine ('--- project ' + $name + ' ---')
        $source = Get-Prop $project 'source'
        Write-InventoryLine ('source-type: ' + [string](Get-Prop $source 'type'))
        Write-InventoryLine ('source-location: ' + [string](Get-Prop $source 'location'))
        Write-InventoryLine ('source-buildspec: ' + [string](Get-Prop $source 'buildspec'))
        Write-InventoryLine ('report-build-status: ' + [string](Get-Prop $source 'reportBuildStatus'))
        $auth = Get-Prop $source 'auth'
        Write-InventoryLine ('auth-type: ' + [string](Get-Prop $auth 'type'))
        $authResource = [string](Get-Prop $auth 'resource')
        if (-not [string]::IsNullOrWhiteSpace($authResource)) {
            Write-InventoryLine ('auth-resource: ' + (Hide-AwsAccount $authResource))
        } else {
            Write-InventoryLine 'auth-resource: none'
        }
        $environment = Get-Prop $project 'environment'
        Write-InventoryLine ('environment-type: ' + [string](Get-Prop $environment 'type'))
        Write-InventoryLine ('compute-type: ' + [string](Get-Prop $environment 'computeType'))
        Write-InventoryLine ('image: ' + [string](Get-Prop $environment 'image'))
        Write-InventoryLine ('privileged-mode: ' + [string](Get-Prop $environment 'privilegedMode'))
        Write-InventoryLine ('timeout-minutes: ' + [string](Get-Prop $project 'timeoutInMinutes'))
        Write-InventoryLine ('queued-timeout-minutes: ' + [string](Get-Prop $project 'queuedTimeoutInMinutes'))
        Write-InventoryLine ('concurrent-build-limit: ' + [string](Get-Prop $project 'concurrentBuildLimit'))
        $cache = Get-Prop $project 'cache'
        Write-InventoryLine ('cache-type: ' + [string](Get-Prop $cache 'type'))
        Write-InventoryLine ('cache-location: ' + [string](Get-Prop $cache 'location'))
        $artifacts = Get-Prop $project 'artifacts'
        Write-InventoryLine ('artifact-type: ' + [string](Get-Prop $artifacts 'type'))
        Write-InventoryLine ('artifact-location: ' + [string](Get-Prop $artifacts 'location'))
        $logs = Get-Prop (Get-Prop $project 'logsConfig') 'cloudWatchLogs'
        Write-InventoryLine ('log-group: ' + [string](Get-Prop $logs 'groupName'))

        $hook = Get-Prop $project 'webhook'
        if ($null -eq $hook) {
            Write-InventoryLine 'webhook: not returned by batch-get-projects'
        } else {
            Write-InventoryLine 'webhook: present'
            $groups = @(Get-Prop $hook 'filterGroups')
            if ($groups.Count -eq 1 -and $null -eq $groups[0]) { $groups = @() }
            if ($groups.Count -eq 0) {
                Write-InventoryLine 'webhook-filters: not returned'
            } else {
                $groupIndex = 0
                foreach ($group in $groups) {
                    $groupIndex++
                    $parts = New-Object System.Collections.Generic.List[string]
                    foreach ($filter in @($group)) {
                        if ($null -eq $filter) { continue }
                        $parts.Add(('{0}={1} exclude={2}' -f [string](Get-Prop $filter 'type'), [string](Get-Prop $filter 'pattern'), [string](Get-Prop $filter 'excludeMatchedPattern')))
                    }
                    Write-InventoryLine (('webhook-filter-group-{0}: {1}' -f $groupIndex, ($parts -join ' ; ')))
                }
            }
            $policy = Get-Prop $hook 'pullRequestBuildPolicy'
            if ($null -eq $policy) {
                Write-InventoryLine 'pull-request-build-policy: not returned'
            } else {
                $roles = @(Get-Prop $policy 'approverRoles' | ForEach-Object { [string]$_ })
                Write-InventoryLine ('pull-request-build-policy: approval={0} roles={1}' -f [string](Get-Prop $policy 'requiresCommentApproval'), ($roles -join ','))
            }
        }

        Test-SafeCliValue -Value $name -Label 'project name'
        $finished = 0
        $inProgress = 0
        $rawSeconds = [double]0
        $billedMinutes = [double]0
        $truncated = $false
        $token = $null
        $pages = 0
        $keepPaging = $true
        while ($keepPaging) {
            $pages++
            if ($pages -gt $script:MaxBuildPages) { $truncated = $true; break }
            $buildArgs = @('codebuild', 'list-builds-for-project', '--project-name', $name, '--sort-order', 'DESCENDING')
            if (-not [string]::IsNullOrWhiteSpace($token)) { $buildArgs += @('--next-token', $token) }
            $listed = Use-ReadOnlyAws -ArgumentList $buildArgs
            $ids = @(Get-Prop $listed 'ids')
            if ($ids.Count -eq 1 -and $null -eq $ids[0]) { $ids = @() }
            $sawRecent = $false
            for ($idOffset = 0; $idOffset -lt $ids.Count; $idOffset += 100) {
                $idEnd = [Math]::Min($idOffset + 99, $ids.Count - 1)
                $idSlice = @($ids[$idOffset..$idEnd] | ForEach-Object { [string]$_ } | Where-Object { $_ })
                foreach ($buildId in $idSlice) { Test-SafeCliValue -Value $buildId -Label 'build id' }
                if ($idSlice.Count -eq 0) { continue }
                $got = Use-ReadOnlyAws -ArgumentList (@('codebuild', 'batch-get-builds', '--ids') + $idSlice)
                foreach ($build in @(Get-Prop $got 'builds')) {
                    if ($null -eq $build) { continue }
                    $ended = ConvertTo-UtcOffset (Get-Prop $build 'endTime')
                    $began = ConvertTo-UtcOffset (Get-Prop $build 'startTime')
                    if ($null -eq $ended) {
                        if ($null -eq $began -or $began -ge $cutoff) { $inProgress++ }
                        $sawRecent = $true
                        continue
                    }
                    if ($ended -lt $cutoff) { continue }
                    $sawRecent = $true
                    if ($null -eq $began) { continue }
                    $seconds = ($ended - $began).TotalSeconds
                    if ($seconds -le 0) { continue }
                    $finished++
                    $rawSeconds += $seconds
                    $billedMinutes += [Math]::Ceiling($seconds / 60.0)
                }
            }
            $token = [string](Get-Prop $listed 'nextToken')
            if ([string]::IsNullOrWhiteSpace($token) -or -not $sawRecent) { $keepPaging = $false }
        }
        Write-InventoryLine ('finished-builds-30d: ' + $finished)
        Write-InventoryLine ('in-progress: ' + $inProgress)
        Write-InventoryLine ('raw-seconds-30d: ' + [Math]::Round($rawSeconds, 0))
        Write-InventoryLine ('billed-minutes-30d: ' + [int]$billedMinutes)
        Write-InventoryLine ('history-truncated: ' + $truncated)
    }
}

$connectionService = $null
$connections = $null
foreach ($service in @('codeconnections', 'codestar-connections')) {
    try {
        $connections = Use-ReadOnlyAws -ArgumentList @($service, 'list-connections')
        $connectionService = $service
        break
    } catch {
        Write-InventoryLine ('{0} list-connections failed: {1}' -f $service, $_.Exception.Message)
    }
}
if (-not $connectionService) { throw 'connection inventory is not established' }
$rows = @(Get-Prop $connections 'Connections')
if ($rows.Count -eq 1 -and $null -eq $rows[0]) { $rows = @(Get-Prop $connections 'connections') }
if ($rows.Count -eq 1 -and $null -eq $rows[0]) { $rows = @() }
Write-InventoryLine ('connections-via: ' + $connectionService)
Write-InventoryLine ('connections: ' + $rows.Count)
foreach ($row in $rows) {
    if ($null -eq $row) { continue }
    Write-InventoryLine ('connection-provider: ' + [string](Get-Prop $row 'ProviderType'))
    Write-InventoryLine ('connection-status: ' + [string](Get-Prop $row 'ConnectionStatus'))
    Write-InventoryLine ('connection-arn: ' + (Hide-AwsAccount ([string](Get-Prop $row 'ConnectionArn'))))
}

$quotaRows = @(Get-PagedList -ArgumentList @('service-quotas', 'list-service-quotas', '--service-code', 'codebuild') -ItemProperty 'Quotas' -TokenProperty 'NextToken')
if ($quotaRows.Count -eq 0) {
    $quotaRows = @(Get-PagedList -ArgumentList @('service-quotas', 'list-service-quotas', '--service-code', 'codebuild') -ItemProperty 'quotas' -TokenProperty 'nextToken')
}
$concurrent = @($quotaRows | Where-Object { [string](Get-Prop $_ 'QuotaName') -match '(?i)concurrent' })
Write-InventoryLine ('service-quotas-inspected: ' + $quotaRows.Count)
if ($concurrent.Count -eq 0) {
    Write-InventoryLine 'concurrent-build quota: not identified in list-service-quotas'
} else {
    foreach ($quota in $concurrent) {
        Write-InventoryLine ('quota: {0} value={1} adjustable={2}' -f [string](Get-Prop $quota 'QuotaName'), [string](Get-Prop $quota 'Value'), [string](Get-Prop $quota 'Adjustable'))
    }
}

Write-InventoryLine 'preflight-complete'
exit 0
