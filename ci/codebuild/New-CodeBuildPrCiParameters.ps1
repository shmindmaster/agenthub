#Requires -Version 5.1
<#
.SYNOPSIS
  Writes a CloudFormation parameter file for ci/codebuild/pr-ci.template.yaml.

.DESCRIPTION
  Reads one repository description JSON file and writes a CreateStack
  parameter document. Names are checked against the template constraints.
  An IAM role ARN is refused. A field that supplies a deployment role or a
  production role is refused. The template creates its own build-only role.

.PARAMETER DescriptionPath
  Path of the repository description JSON.

.PARAMETER OutPath
  Path of the parameter file to write. Must end in .json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DescriptionPath,
    [Parameter(Mandatory)][string]$OutPath
)

$ErrorActionPreference = 'Stop'

$ComputeTypes = @(
    'BUILD_GENERAL1_SMALL',
    'BUILD_GENERAL1_MEDIUM',
    'BUILD_GENERAL1_LARGE',
    'BUILD_GENERAL1_XLARGE',
    'BUILD_GENERAL1_2XLARGE'
)
$RetentionDays = @(1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)
$ApproverRoleNames = @('GITHUB_READ', 'GITHUB_TRIAGE', 'GITHUB_WRITE', 'GITHUB_MAINTAIN', 'GITHUB_ADMIN')
$AllowedFields = @(
    'GitHubOwner', 'GitHubRepository', 'ConnectionArn', 'BuildSpecPath', 'ComputeType',
    'TimeoutInMinutes', 'QueuedTimeoutInMinutes', 'ConcurrentBuildLimit', 'LogRetentionInDays',
    'ArtifactBucketName', 'ArtifactPrefix', 'ProjectName', 'BaseBranches', 'PrivilegedMode',
    'CiMode', 'RequiresCommentApproval', 'ApproverRoles', 'Image', 'PermissionsBoundaryArn'
)

function Get-Field {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Test-FieldPresent {
    param($Object, [string]$Name)
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Add-StringValue {
    param($Value, $Accumulator)
    if ($null -eq $Value) { return }
    if ($Value -is [string]) { $Accumulator.Add($Value); return }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($item in @($Value)) { Add-StringValue -Value $item -Accumulator $Accumulator }
    }
}

function Assert-NoRoleArn {
    param([string]$Value)
    $match = [regex]::Match($Value, 'arn:(aws|aws-us-gov|aws-cn):iam::\d{12}:role/([A-Za-z0-9+=,.@_\-/]+)')
    if (-not $match.Success) { return }
    $path = $match.Groups[2].Value
    if ($path -match '(?i)deploy') { throw "refusing a deployment role ARN: $path" }
    if ($path -match '(?i)(^|[^A-Za-z])prod(uction)?([^A-Za-z]|$)') { throw "refusing a production role ARN: $path" }
    throw "refusing a supplied IAM role ARN: $path. The stack creates a build-only role."
}

function ConvertTo-StringList {
    param($Value, [string]$Name)
    if ($null -eq $Value) { throw "$Name is empty" }
    if ($Value -is [string]) {
        $items = @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        $items = @($Value | ForEach-Object { [string]$_ })
    }
    if ($items.Count -eq 0) { throw "$Name is empty" }
    return $items
}

function ConvertTo-StrictBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    throw "$Name must be a JSON boolean"
}

function ConvertTo-StrictInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $isNumber = $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]
    if (-not $isNumber) { throw "$Name must be a JSON number" }
    $number = [double]$Value
    if ($number -ne [Math]::Floor($number)) { throw "$Name must be a whole number" }
    $whole = [int]$number
    if ($whole -lt $Min -or $whole -gt $Max) { throw "$Name must be from $Min to $Max" }
    return $whole
}

function Get-SafeToken {
    param([string]$Value)
    $lower = $Value.ToLowerInvariant()
    $safe = [regex]::Replace($lower, '[^a-z0-9-]', '-')
    $safe = [regex]::Replace($safe, '-{2,}', '-').Trim('-')
    if ($safe.Length -lt 2) { throw "repository name does not yield a safe token: $Value" }
    return $safe
}

function ConvertTo-BaseBranchPattern {
    param([string[]]$Branches)
    if ($Branches.Count -lt 1) { throw 'BaseBranches must list at least one branch' }
    $parts = foreach ($branch in $Branches) {
        if ($branch -notmatch '^[A-Za-z0-9._/-]+$') { throw "invalid branch name: $branch" }
        if ($branch.Contains('..')) { throw "invalid branch name: $branch" }
        [regex]::Escape($branch)
    }
    if (@($parts).Count -eq 1) { return "^refs/heads/$($parts[0])$" }
    return '^refs/heads/(' + ($parts -join '|') + ')$'
}

if (-not (Test-Path -LiteralPath $DescriptionPath -PathType Leaf)) { throw "description file not found: $DescriptionPath" }
if ([IO.Path]::GetExtension($OutPath) -ne '.json') { throw 'OutPath must end with .json' }

$description = [IO.File]::ReadAllText($DescriptionPath) | ConvertFrom-Json
if ($description -isnot [pscustomobject]) {
    throw 'description JSON must be an object'
}

foreach ($property in @($description.PSObject.Properties)) {
    if ($property.Name -match '(?i)(^Role$|RoleArn|ServiceRole|DeploymentRole|ProductionRole|DeployRole)') {
        throw "refusing a deployment role: '$($property.Name)' is not accepted. The stack creates a build-only role and does not accept a deployment role or a production role ARN."
    }
    if ($property.Value -is [pscustomobject]) { throw "nested objects are not accepted: $($property.Name)" }
    if (@($AllowedFields) -notcontains $property.Name) { throw "unknown field: $($property.Name)" }
}

$strings = New-Object System.Collections.Generic.List[string]
foreach ($property in @($description.PSObject.Properties)) {
    Add-StringValue -Value $property.Value -Accumulator $strings
}
foreach ($value in $strings) { Assert-NoRoleArn -Value $value }

foreach ($name in @('GitHubOwner', 'GitHubRepository', 'ConnectionArn', 'BuildSpecPath', 'ArtifactBucketName')) {
    $value = Get-Field -Object $description -Name $name
    if ([string]::IsNullOrWhiteSpace([string]$value)) { throw "missing field: $name" }
}

$owner = [string](Get-Field -Object $description -Name 'GitHubOwner')
$repository = [string](Get-Field -Object $description -Name 'GitHubRepository')
$connection = [string](Get-Field -Object $description -Name 'ConnectionArn')
$buildspec = [string](Get-Field -Object $description -Name 'BuildSpecPath')
$bucket = [string](Get-Field -Object $description -Name 'ArtifactBucketName')

if ($owner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$') { throw "invalid GitHubOwner: $owner" }
if ($repository -notmatch '^[A-Za-z0-9._-]{1,100}$') { throw "invalid GitHubRepository: $repository" }
if ($connection -notmatch '^arn:(aws|aws-us-gov|aws-cn):(codeconnections|codestar-connections):[a-z0-9-]+:[0-9]{12}:connection/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'ConnectionArn must be a CodeConnections or CodeStar Connections ARN'
}
if ($buildspec -notmatch '^([A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.ya?ml$') { throw "invalid BuildSpecPath: $buildspec" }
if ($buildspec.Contains('..')) { throw "invalid BuildSpecPath: $buildspec" }
if ($bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw "invalid ArtifactBucketName: $bucket" }

$projectName = if (Test-FieldPresent -Object $description -Name 'ProjectName') { [string](Get-Field -Object $description -Name 'ProjectName') } else { $null }
if ([string]::IsNullOrWhiteSpace($projectName)) {
    $token = Get-SafeToken -Value $repository
    $projectName = "$token-pr-ci"
    if ($projectName.Length -gt 48) { $projectName = $projectName.Substring(0, 48).Trim('-') }
}
if ($projectName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{1,47}$') { throw "invalid ProjectName: $projectName" }

$prefix = if (Test-FieldPresent -Object $description -Name 'ArtifactPrefix') { [string](Get-Field -Object $description -Name 'ArtifactPrefix') } else { $null }
if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = Get-SafeToken -Value $repository }
if ($prefix -notmatch '^[a-z0-9]([a-z0-9-]{0,62})(/[a-z0-9][a-z0-9-]{0,62})*$') { throw "invalid ArtifactPrefix: $prefix" }

$compute = if (Test-FieldPresent -Object $description -Name 'ComputeType') { [string](Get-Field -Object $description -Name 'ComputeType') } else { 'BUILD_GENERAL1_SMALL' }
if (@($ComputeTypes) -notcontains $compute) { throw "invalid ComputeType: $compute" }

$image = if (Test-FieldPresent -Object $description -Name 'Image') { [string](Get-Field -Object $description -Name 'Image') } else { 'aws/codebuild/standard:8.0' }
if ($image -notmatch '^aws/codebuild/[A-Za-z0-9._:/-]+$') { throw "invalid Image: $image" }

$privileged = if (Test-FieldPresent -Object $description -Name 'PrivilegedMode') { ConvertTo-StrictBool -Value (Get-Field -Object $description -Name 'PrivilegedMode') -Name 'PrivilegedMode' } else { $false }
$mode = if (Test-FieldPresent -Object $description -Name 'CiMode') { [string](Get-Field -Object $description -Name 'CiMode') } else { 'native' }
if (@('native', 'runner') -notcontains $mode) { throw "invalid CiMode: $mode" }
$approval = if (Test-FieldPresent -Object $description -Name 'RequiresCommentApproval') { [string](Get-Field -Object $description -Name 'RequiresCommentApproval') } else { 'FORK_PULL_REQUESTS' }
if (@('DISABLED', 'ALL_PULL_REQUESTS', 'FORK_PULL_REQUESTS') -notcontains $approval) { throw "invalid RequiresCommentApproval: $approval" }

$timeout = if (Test-FieldPresent -Object $description -Name 'TimeoutInMinutes') { ConvertTo-StrictInt -Value (Get-Field -Object $description -Name 'TimeoutInMinutes') -Name 'TimeoutInMinutes' -Min 5 -Max 480 } else { 90 }
$queued = if (Test-FieldPresent -Object $description -Name 'QueuedTimeoutInMinutes') { ConvertTo-StrictInt -Value (Get-Field -Object $description -Name 'QueuedTimeoutInMinutes') -Name 'QueuedTimeoutInMinutes' -Min 5 -Max 480 } else { 30 }
$concurrent = if (Test-FieldPresent -Object $description -Name 'ConcurrentBuildLimit') { ConvertTo-StrictInt -Value (Get-Field -Object $description -Name 'ConcurrentBuildLimit') -Name 'ConcurrentBuildLimit' -Min 1 -Max 20 } else { 1 }
$retention = if (Test-FieldPresent -Object $description -Name 'LogRetentionInDays') { ConvertTo-StrictInt -Value (Get-Field -Object $description -Name 'LogRetentionInDays') -Name 'LogRetentionInDays' -Min 1 -Max 3653 } else { 14 }
if (@($RetentionDays) -notcontains $retention) { throw "invalid LogRetentionInDays: $retention" }

$branches = if (Test-FieldPresent -Object $description -Name 'BaseBranches') { ConvertTo-StringList -Value (Get-Field -Object $description -Name 'BaseBranches') -Name 'BaseBranches' } else { @('main') }
$branchPattern = ConvertTo-BaseBranchPattern -Branches $branches
if ($branchPattern -notmatch '^\^refs/heads/\S+\$$') { throw "invalid BaseBranchPattern: $branchPattern" }

$roles = if (Test-FieldPresent -Object $description -Name 'ApproverRoles') { ConvertTo-StringList -Value (Get-Field -Object $description -Name 'ApproverRoles') -Name 'ApproverRoles' } else { @('GITHUB_WRITE', 'GITHUB_MAINTAIN', 'GITHUB_ADMIN') }
foreach ($role in $roles) {
    if (@($ApproverRoleNames) -notcontains $role) { throw "invalid ApproverRoles entry: $role" }
}

$boundary = if (Test-FieldPresent -Object $description -Name 'PermissionsBoundaryArn') { [string](Get-Field -Object $description -Name 'PermissionsBoundaryArn') } else { '' }
if (-not [string]::IsNullOrWhiteSpace($boundary) -and $boundary -notmatch '^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$') {
    throw 'PermissionsBoundaryArn must be an IAM policy ARN or empty'
}

$rows = New-Object System.Collections.Generic.List[object]
function Add-Parameter {
    param([string]$Key, [string]$Value)
    $script:rows.Add([pscustomobject]@{ ParameterKey = $Key; ParameterValue = $Value })
}
Add-Parameter 'ProjectName' $projectName
Add-Parameter 'GitHubOwner' $owner
Add-Parameter 'GitHubRepository' $repository
Add-Parameter 'ConnectionArn' $connection
Add-Parameter 'BuildSpecPath' $buildspec
Add-Parameter 'ComputeType' $compute
Add-Parameter 'Image' $image
Add-Parameter 'PrivilegedMode' $(if ($privileged) { 'true' } else { 'false' })
Add-Parameter 'TimeoutInMinutes' ([string]$timeout)
Add-Parameter 'QueuedTimeoutInMinutes' ([string]$queued)
Add-Parameter 'ConcurrentBuildLimit' ([string]$concurrent)
Add-Parameter 'LogRetentionInDays' ([string]$retention)
Add-Parameter 'ArtifactBucketName' $bucket
Add-Parameter 'ArtifactPrefix' $prefix
Add-Parameter 'BaseBranchPattern' $branchPattern
Add-Parameter 'CiMode' $mode
Add-Parameter 'RequiresCommentApproval' $approval
Add-Parameter 'ApproverRoles' ($roles -join ',')
Add-Parameter 'PermissionsBoundaryArn' $boundary

$fullOut = [IO.Path]::GetFullPath($OutPath)
$parent = Split-Path -Parent $fullOut
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    [IO.Directory]::CreateDirectory($parent) | Out-Null
}
$json = ($rows | ConvertTo-Json -Depth 4)
if (-not $json.EndsWith("`n")) { $json += "`n" }
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($fullOut, $json, $utf8)
Write-Host ("wrote {0} parameters to {1}" -f $rows.Count, $fullOut)
exit 0
