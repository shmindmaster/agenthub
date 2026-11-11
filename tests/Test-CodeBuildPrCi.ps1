#Requires -Version 5.1
<#
SH-4411: the CodeBuild pull-request template, the read-only preflight, and the
parameter writer. The template is read with an indent YAML subset parser so
this test does not need a YAML module.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$templatePath = Join-Path $repoRoot 'ci\codebuild\pr-ci.template.yaml'
$buildspecPath = Join-Path $repoRoot 'ci\codebuild\buildspecs\agenthub.yml'
$examplePath = Join-Path $repoRoot 'ci\codebuild\buildspec.example.yml'
$preflightPath = Join-Path $repoRoot 'ci\codebuild\Get-CodeBuildPreflight.ps1'
$writerPath = Join-Path $repoRoot 'ci\codebuild\New-CodeBuildPrCiParameters.ps1'
$runbookPath = Join-Path $repoRoot 'docs\runbooks\codebuild-pr-ci.md'

$passed = 0
$failed = 0
function Report([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Output "PASS: $Name" }
    else { $script:failed++; Write-Output "FAIL: $Name -- $Detail" }
}

function Invoke-Child {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & pwsh -NoProfile @ArgumentList 2>&1 | Out-String
        return @{ Code = $LASTEXITCODE; Output = $output }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText($Path)
}

function Write-Utf8([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

# Indent YAML subset: 2-space maps and lists, full-line comments, no tabs,
# no anchors, no block scalars. A key may contain "::". The separator is
# ": " or a trailing colon. Quoted keys are supported.
function Unquote-YamlScalar([string]$Value) {
    if ($Value.Length -ge 2) {
        $quote = $Value[0]
        if (($quote -eq "'" -or $quote -eq '"') -and $Value[$Value.Length - 1] -eq $quote) {
            $inner = $Value.Substring(1, $Value.Length - 2)
            if ($quote -eq "'") { return $inner.Replace("''", "'") }
            return $inner
        }
    }
    return $Value
}

function Split-YamlKey([string]$Text) {
    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith("'") -or $trimmed.StartsWith('"')) {
        $quote = $trimmed[0]
        $end = 1
        while ($end -lt $trimmed.Length) {
            if ($trimmed[$end] -eq $quote) {
                if (($end + 1) -lt $trimmed.Length -and $trimmed[$end + 1] -eq $quote) { $end += 2; continue }
                break
            }
            $end++
        }
        if ($end -ge $trimmed.Length -or $trimmed[$end] -ne $quote) { return $null }
        $after = $trimmed.Substring($end + 1).Trim()
        if (-not $after.StartsWith(':')) { return $null }
        $key = $trimmed.Substring(1, $end - 1).Replace("$quote$quote", "$quote")
        return @{ Key = $key; Value = $after.Substring(1).Trim() }
    }
    $spaced = $trimmed.IndexOf(': ')
    if ($spaced -ge 0) {
        return @{ Key = $trimmed.Substring(0, $spaced).Trim(); Value = $trimmed.Substring($spaced + 2).Trim() }
    }
    if ($trimmed.EndsWith(':') -and $trimmed.Length -gt 1) {
        return @{ Key = $trimmed.Substring(0, $trimmed.Length - 1).Trim(); Value = '' }
    }
    return $null
}

function New-YamlState([string]$Text) {
    if ($Text.Contains("`t")) { throw 'YAML subset rejects tabs' }
    return @{ Lines = @($Text -split "`r?`n"); Index = 0 }
}

function Skip-Yaml([hashtable]$State) {
    while ($State.Index -lt $State.Lines.Count) {
        $trim = $State.Lines[$State.Index].Trim()
        if ($trim.Length -eq 0 -or $trim.StartsWith('#')) { $State.Index++; continue }
        break
    }
}

function Get-YamlIndent([hashtable]$State) {
    Skip-Yaml $State
    if ($State.Index -ge $State.Lines.Count) { return -1 }
    $line = $State.Lines[$State.Index]
    $count = 0
    while ($count -lt $line.Length -and $line[$count] -eq ' ') { $count++ }
    return $count
}

function Get-YamlContent([hashtable]$State) {
    $line = $State.Lines[$State.Index]
    $count = 0
    while ($count -lt $line.Length -and $line[$count] -eq ' ') { $count++ }
    return $line.Substring($count)
}

function ConvertFrom-IndentYaml([string]$Text) {
    $state = New-YamlState $Text
    $node = Read-YamlNode $state 0
    Skip-Yaml $state
    if ($state.Index -lt $state.Lines.Count) { throw "trailing YAML at line $($state.Index + 1)" }
    return $node
}

function Read-YamlNode([hashtable]$State, [int]$MinIndent) {
    $indent = Get-YamlIndent $State
    if ($indent -lt $MinIndent) { throw "expected a nested block at line $($State.Index + 1)" }
    $content = Get-YamlContent $State
    # Comma-wrap again. Returning a list from this function would enumerate it.
    if ($content.StartsWith('-')) {
        $sequence = Read-YamlSequence $State $indent
        return ,$sequence
    }
    $mapping = Read-YamlMapping $State $indent
    return ,$mapping
}

function Read-YamlMapping([hashtable]$State, [int]$Indent) {
    $map = [ordered]@{}
    while ($true) {
        $next = Get-YamlIndent $State
        if ($next -lt 0 -or $next -lt $Indent) { break }
        if ($next -gt $Indent) { throw "unexpected indent $next at line $($State.Index + 1)" }
        $content = Get-YamlContent $State
        if ($content.StartsWith('-')) { throw "expected a key at line $($State.Index + 1)" }
        $State.Index++
        $pair = Split-YamlKey $content
        if ($null -eq $pair) { throw "expected a key at line $State.Index" }
        if ($map.Contains($pair.Key)) { throw "duplicate key $($pair.Key)" }
        if ($pair.Value -eq '') {
            $map[$pair.Key] = Read-YamlNode $State ($Indent + 1)
        } else {
            if ($pair.Value -eq '|' -or $pair.Value -eq '>') { throw 'block scalars are outside this YAML subset' }
            $map[$pair.Key] = Unquote-YamlScalar $pair.Value
        }
    }
    if ($map.Count -eq 0) { throw "empty mapping at line $($State.Index + 1)" }
    return $map
}

function Read-YamlSequence([hashtable]$State, [int]$Indent) {
    $list = New-Object System.Collections.Generic.List[object]
    while ($true) {
        $next = Get-YamlIndent $State
        if ($next -lt 0 -or $next -lt $Indent) { break }
        if ($next -gt $Indent) { throw "unexpected indent $next in a sequence at line $($State.Index + 1)" }
        $content = Get-YamlContent $State
        if (-not $content.StartsWith('-')) { break }
        $body = $content.Substring(1).Trim()
        $State.Index++
        if ($body.Length -eq 0) {
            $list.Add((Read-YamlNode $State ($Indent + 1)))
            continue
        }
        $pair = Split-YamlKey $body
        if ($null -ne $pair -and $pair.Key -notmatch '\s') {
            $item = [ordered]@{}
            $sibling = $Indent + 2
            if ($pair.Value -eq '') { $item[$pair.Key] = Read-YamlNode $State ($sibling + 1) }
            else { $item[$pair.Key] = Unquote-YamlScalar $pair.Value }
            while ($true) {
                $keyIndent = Get-YamlIndent $State
                if ($keyIndent -ne $sibling) { break }
                $keyContent = Get-YamlContent $State
                if ($keyContent.StartsWith('-')) { break }
                $State.Index++
                $siblingPair = Split-YamlKey $keyContent
                if ($null -eq $siblingPair) { throw "expected a key at line $State.Index" }
                if ($siblingPair.Value -eq '') { $item[$siblingPair.Key] = Read-YamlNode $State ($sibling + 1) }
                else { $item[$siblingPair.Key] = Unquote-YamlScalar $siblingPair.Value }
            }
            $list.Add($item)
        } else {
            $list.Add((Unquote-YamlScalar $body))
        }
    }
    if ($list.Count -eq 0) { throw "empty sequence at line $($State.Index + 1)" }
    # The comma keeps a one-item list from being unwrapped by the pipeline.
    return ,$list
}

function Get-Yaml([object]$Node, [string[]]$Path) {
    $current = $Node
    foreach ($key in $Path) {
        if ($current -isnot [System.Collections.IDictionary] -or -not $current.Contains($key)) { return $null }
        $current = $current[$key]
    }
    # A one-item list would otherwise be unwrapped by return.
    if ($null -eq $current) { return $null }
    return ,$current
}

function Get-FnSubText($Node) {
    $found = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node -or $Node -is [string]) { return ,$found }
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            if ($key -eq 'Fn::Sub') { $found.Add([string]$Node[$key]) }
            else {
                $child = Get-FnSubText $Node[$key]
                for ($i = 0; $i -lt $child.Count; $i++) { $found.Add([string]$child[$i]) }
            }
        }
        return ,$found
    }
    if ($Node -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            $child = Get-FnSubText $Node[$i]
            for ($j = 0; $j -lt $child.Count; $j++) { $found.Add([string]$child[$j]) }
        }
    }
    return ,$found
}

function Find-WebhookFilters($Node, $Found) {
    if ($null -eq $Node -or $Node -is [string]) { return }
    if ($Node -is [System.Collections.IDictionary]) {
        $hasType = $false
        foreach ($key in @($Node.Keys)) { if ($key -eq 'Type') { $hasType = $true } }
        if ($hasType -and $Node.Contains('Pattern')) { $Found.Add($Node) }
        foreach ($key in @($Node.Keys)) { Find-WebhookFilters $Node[$key] $Found }
        return
    }
    if ($Node -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Node.Count; $i++) { Find-WebhookFilters $Node[$i] $Found }
    }
}

function Find-EventPatterns($Node, $Found) {
    if ($null -eq $Node -or $Node -is [string]) { return }
    if ($Node -is [System.Collections.IDictionary]) {
        $type = $null
        $pattern = $null
        $hasType = $false
        foreach ($key in $Node.Keys) {
            if ($key -eq 'Type') { $hasType = $true; $type = [string]$Node[$key] }
            if ($key -eq 'Pattern') { $pattern = [string]$Node[$key] }
        }
        if ($hasType -and $type -eq 'EVENT' -and $null -ne $pattern) { $Found.Add($pattern) }
        foreach ($key in $Node.Keys) { Find-EventPatterns $Node[$key] $Found }
        return
    }
    if ($Node -is [System.Collections.IList]) {
        for ($i = 0; $i -lt $Node.Count; $i++) { Find-EventPatterns $Node[$i] $Found }
    }
}

Write-Output 'NOTE: template YAML was read by an indent subset parser in this test. A YAML module was not required and was not loaded.'

$tabRejected = $false
$tabDetail = ''
try {
    $null = ConvertFrom-IndentYaml "A:`n`tB: 1`n"
    $tabDetail = 'a tab was accepted'
} catch {
    $tabRejected = $_.Exception.Message -match 'tab'
    $tabDetail = $_.Exception.Message
}
Report 'the YAML subset rejects a tab' $tabRejected $tabDetail

$sampleOk = $false
$sampleDetail = ''
try {
    $sample = ConvertFrom-IndentYaml "A:`r`n  B: 1`r`n  C:`r`n    - x`r`n    - y: z`r`n"
    $sampleOk = [string]$sample['A']['B'] -eq '1' -and [string]$sample['A']['C'][0] -eq 'x' -and [string]$sample['A']['C'][1]['y'] -eq 'z'
    if (-not $sampleOk) { $sampleDetail = 'sample tree did not round-trip' }
} catch {
    $sampleDetail = $_.Exception.Message
}
Report 'the YAML subset reads a small map and list' $sampleOk $sampleDetail

$templateText = Read-Utf8 $templatePath
$doc = $null
$parseDetail = ''
try {
    $doc = ConvertFrom-IndentYaml $templateText
} catch {
    $parseDetail = $_.Exception.Message
}
Report 'the CloudFormation template parses as the indent YAML subset' ($null -ne $doc) $parseDetail

$expectedParameters = @(
    'ProjectName', 'GitHubOwner', 'GitHubRepository', 'RepositoryNamePattern', 'ConnectionArn', 'BuildSpecPath',
    'ComputeType', 'Image', 'PrivilegedMode', 'TimeoutInMinutes', 'QueuedTimeoutInMinutes',
    'ConcurrentBuildLimit', 'LogRetentionInDays', 'ArtifactBucketName', 'ArtifactPrefix', 'EnableSharedCache',
    'BaseBranchPattern', 'CiMode', 'RequiresCommentApproval', 'ApproverRoles', 'PermissionsBoundaryArn'
)
if ($null -eq $doc) {
    Report 'the template has the pull-request parameters and resources' $false 'template did not parse'
} else {
    $parameters = Get-Yaml $doc @('Parameters')
    $missing = @($expectedParameters | Where-Object { -not $parameters.Contains($_) })
    $extraParameters = @($parameters.Keys | Where-Object { $expectedParameters -notcontains $_ })
    Report 'the template declares the repository, connection, build, and log parameters' ($missing.Count -eq 0 -and $extraParameters.Count -eq 0) ("missing=$($missing -join ',') extra=$($extraParameters -join ',')")
    $approver = $parameters['ApproverRoles']
    $approverPattern = ''
    if ($approver -is [System.Collections.IDictionary] -and $approver.Contains('AllowedPattern')) { $approverPattern = [string]$approver['AllowedPattern'] }
    Report 'ApproverRoles has no AllowedPattern' ([string]::IsNullOrEmpty($approverPattern)) $approverPattern
    Report 'privileged mode defaults off' ((Get-Yaml $parameters @('PrivilegedMode', 'Default')) -eq 'false') ([string](Get-Yaml $parameters @('PrivilegedMode', 'Default')))
    Report 'the build timeout default is 90 minutes' ((Get-Yaml $parameters @('TimeoutInMinutes', 'Default')) -eq '90') ''
    Report 'the concurrency default is 1' ((Get-Yaml $parameters @('ConcurrentBuildLimit', 'Default')) -eq '1') ''
    Report 'log retention defaults to 14 days' ((Get-Yaml $parameters @('LogRetentionInDays', 'Default')) -eq '14') ''
    Report 'native mode is the default' ((Get-Yaml $parameters @('CiMode', 'Default')) -eq 'native') ''
    Report 'fork pull requests require approval by default' ((Get-Yaml $parameters @('RequiresCommentApproval', 'Default')) -eq 'FORK_PULL_REQUESTS') ''
    Report 'the default compute type is SMALL' ((Get-Yaml $parameters @('ComputeType', 'Default')) -eq 'BUILD_GENERAL1_SMALL') ''
    Report 'the default image is the curated standard image' ((Get-Yaml $parameters @('Image', 'Default')) -eq 'aws/codebuild/standard:8.0') ''
    Report 'the default base branch is main' ((Get-Yaml $parameters @('BaseBranchPattern', 'Default')) -eq '^refs/heads/main$') ''

    $resources = Get-Yaml $doc @('Resources')
    Report 'the template creates a build role, a log group, and a CodeBuild project' (
        (Get-Yaml $resources @('BuildRole', 'Type')) -eq 'AWS::IAM::Role' -and
        (Get-Yaml $resources @('BuildLogGroup', 'Type')) -eq 'AWS::Logs::LogGroup' -and
        (Get-Yaml $resources @('PrCiProject', 'Type')) -eq 'AWS::CodeBuild::Project'
    ) 'one of the three resource types was missing'

    $policyName = Get-Yaml $resources @('BuildRole', 'Properties', 'Policies')
    $firstPolicy = $policyName[0]
    $policyNameText = [string]$firstPolicy['PolicyName']
    Report 'the inline policy is named build-only' ($policyNameText -eq 'build-only') $policyNameText
    $managed = Get-Yaml $resources @('BuildRole', 'Properties')
    $managedKeys = @($managed.Keys)
    Report 'the build role has no managed policies' ($managedKeys -notcontains 'ManagedPolicyArns') 'ManagedPolicyArns is set'

    $statementNode = $firstPolicy['PolicyDocument']['Statement']
    $actions = New-Object System.Collections.Generic.List[string]
    $starResource = $false
    for ($statementIndex = 0; $statementIndex -lt $statementNode.Count; $statementIndex++) {
        $statement = $statementNode[$statementIndex]
        $actionValue = $statement['Action']
        if ($actionValue -is [string]) { $actions.Add($actionValue) }
        elseif ($actionValue -is [System.Collections.IList]) {
            for ($actionIndex = 0; $actionIndex -lt $actionValue.Count; $actionIndex++) {
                $action = $actionValue[$actionIndex]
                if ($action -isnot [string]) { throw "action value was $($action.GetType().FullName)" }
                $actions.Add($action)
            }
        }
        $resource = $statement['Resource']
        if ($resource -is [string] -and $resource -eq '*') { $starResource = $true }
        elseif ($resource -is [System.Collections.IList]) {
            for ($resourceIndex = 0; $resourceIndex -lt $resource.Count; $resourceIndex++) {
                $item = $resource[$resourceIndex]
                if ($item -is [string] -and $item -eq '*') { $starResource = $true }
            }
        }
    }
    $forbidden = @()
    for ($actionIndex = 0; $actionIndex -lt $actions.Count; $actionIndex++) {
        $action = $actions[$actionIndex]
        if ($action -eq '*' -or $action -like 'ecr:*' -or $action -like 'secretsmanager:*' -or $action -like 'ssm:*' -or $action -like 'iam:*') {
            $forbidden += $action
        }
    }
    Report 'the build-only policy has no wildcard action and no forbidden service' ($forbidden.Count -eq 0 -and -not $starResource) (($forbidden + @($(if ($starResource) { 'Resource *' }))) -join ', ')
    $expectedActions = @(
        'logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents',
        's3:GetObject', 's3:PutObject', 's3:AbortMultipartUpload', 's3:ListMultipartUploadParts',
        's3:GetBucketLocation', 's3:GetEncryptionConfiguration', 's3:ListBucket',
        'codeconnections:GetConnectionToken', 'codeconnections:GetConnection', 'codeconnections:UseConnection',
        'codestar-connections:GetConnectionToken', 'codestar-connections:GetConnection', 'codestar-connections:UseConnection'
    )
    $seenActions = @{}
    for ($actionIndex = 0; $actionIndex -lt $actions.Count; $actionIndex++) { $seenActions[$actions[$actionIndex]] = $true }
    $expectedSet = @{}
    foreach ($expected in $expectedActions) { $expectedSet[$expected] = $true }
    $missingActions = @($expectedActions | Where-Object { -not $seenActions.ContainsKey($_) })
    $extraActions = @()
    foreach ($key in $seenActions.Keys) { if (-not $expectedSet.ContainsKey($key)) { $extraActions += $key } }
    Report 'the build-only policy allows only logs, the artifact prefix, and the connection' ($missingActions.Count -eq 0 -and $extraActions.Count -eq 0) ("missing=$($missingActions -join ',') extra=$($extraActions -join ',')")

    $source = Get-Yaml $resources @('PrCiProject', 'Properties', 'Source')
    Report 'the project uses a GitHub source and reports status' (
        [string]$source['Type'] -eq 'GITHUB' -and [string]$source['ReportBuildStatus'] -eq 'true'
    ) "type=$($source['Type']) status=$($source['ReportBuildStatus'])"
    $auth = $source['Auth']
    Report 'GitHub auth is a CodeConnections connection' ([string]$auth['Type'] -eq 'CODECONNECTIONS') ([string]$auth['Type'])
    $environment = Get-Yaml $resources @('PrCiProject', 'Properties', 'Environment')
    Report 'image pulls use CodeBuild credentials' ([string]$environment['ImagePullCredentialsType'] -eq 'CODEBUILD') ([string]$environment['ImagePullCredentialsType'])
    $privileged = $environment['PrivilegedMode']['Fn::If']
    Report 'privileged mode is a boolean chosen by the parameter and defaults to the false branch' (
        $privileged.Count -eq 3 -and [string]$privileged[0] -eq 'UsePrivilegedMode' -and [string]$privileged[2] -eq 'false'
    ) 'Fn::If shape was not the expected true/false pair'

    $filterIf = Get-Yaml $resources @('PrCiProject', 'Properties', 'Triggers', 'FilterGroups', 'Fn::If')
    $events = New-Object System.Collections.Generic.List[string]
    Find-EventPatterns $filterIf $events
    $tokenSet = @{}
    for ($eventIndex = 0; $eventIndex -lt $events.Count; $eventIndex++) {
        foreach ($token in ($events[$eventIndex] -split ',')) { $tokenSet[$token.Trim()] = $true }
    }
    $requiredEvents = @('PULL_REQUEST_CREATED', 'PULL_REQUEST_UPDATED', 'PULL_REQUEST_REOPENED')
    $missingEvents = @($requiredEvents | Where-Object { -not $tokenSet.ContainsKey($_) })
    Report 'webhook filters include the three pull-request events' ($missingEvents.Count -eq 0) ($missingEvents -join ', ')
    Report 'webhook filters include the runner event' ($tokenSet.ContainsKey('WORKFLOW_JOB_QUEUED')) (($tokenSet.Keys -join ', '))
    Report 'webhook filters do not include push' (-not $tokenSet.ContainsKey('PUSH')) (($tokenSet.Keys -join ', '))
    Report 'the template text has no EVENT pattern of PUSH' ($templateText -notmatch '(?m)Pattern:\s*\S*PUSH') ''

    $policyIf = Get-Yaml $resources @('PrCiProject', 'Properties', 'Triggers', 'PullRequestBuildPolicy', 'Fn::If')
    $hasApproval = $false
    if ($policyIf[2] -is [System.Collections.IDictionary]) {
        foreach ($key in $policyIf[2].Keys) { if ($key -eq 'RequiresCommentApproval') { $hasApproval = $true } }
    }
    $runnerOmits = $policyIf.Count -eq 3 -and $policyIf[1] -is [System.Collections.IDictionary] -and [string]$policyIf[1]['Ref'] -eq 'AWS::NoValue'
    Report 'runner mode omits the pull-request approval policy and native mode keeps it' ($runnerOmits -and $hasApproval) 'PullRequestBuildPolicy Fn::If shape was unexpected'

    $assume = Get-Yaml $resources @('BuildRole', 'Properties', 'AssumeRolePolicyDocument', 'Statement')
    $trust = $assume[0]['Condition']['StringEquals']
    $sourceArn = [string]$trust['aws:SourceArn']['Fn::Sub']
    $sourceAccount = [string]$trust['aws:SourceAccount']['Ref']
    Report 'the build role trust policy requires the project ARN and the source account' (
        $sourceArn -eq 'arn:${AWS::Partition}:codebuild:${AWS::Region}:${AWS::AccountId}:project/${ProjectName}' -and
        $sourceAccount -eq 'AWS::AccountId'
    ) "arn=$sourceArn account=$sourceAccount"

    $cache = Get-Yaml $resources @('PrCiProject', 'Properties', 'Cache')
    $cacheType = $cache['Type']['Fn::If']
    Report 'the shared cache is off unless EnableSharedCache is true' (
        [string]$cacheType[0] -eq 'UseSharedCache' -and [string]$cacheType[1] -eq 'S3' -and [string]$cacheType[2] -eq 'NO_CACHE' -and
        (Get-Yaml $parameters @('EnableSharedCache', 'Default')) -eq 'false'
    ) "type=$($cacheType -join ',') default=$(Get-Yaml $parameters @('EnableSharedCache', 'Default'))"
    $cacheLocation = $cache['Location']['Fn::If']
    $cacheOnLocation = [string]$cacheLocation[1]['Fn::Sub']
    Report 'the shared cache location is one prefix and is omitted when the cache is off' (
        $cacheOnLocation -eq '${ArtifactBucketName}/${ArtifactPrefix}/cache' -and [string]$cacheLocation[2]['Ref'] -eq 'AWS::NoValue'
    ) $cacheOnLocation

    $artifacts = Get-Yaml $resources @('PrCiProject', 'Properties', 'Artifacts')
    Report 'each build stores artifacts under its own build id' (
        [string]$artifacts['NamespaceType'] -eq 'BUILD_ID' -and [string]$artifacts['Path']['Fn::Sub'] -eq '${ArtifactPrefix}/artifacts'
    ) "namespace=$($artifacts['NamespaceType']) path=$($artifacts['Path'])"

    $objectStatement = $null
    for ($statementIndex = 0; $statementIndex -lt $statementNode.Count; $statementIndex++) {
        if ([string]$statementNode[$statementIndex]['Sid'] -eq 'ReadWriteArtifactObjects') { $objectStatement = $statementNode[$statementIndex] }
    }
    $resourceIf = $objectStatement['Resource']['Fn::If']
    $artifactOff = @(Get-FnSubText $resourceIf[2] | ForEach-Object { [string]$_ })
    $artifactOn = @(Get-FnSubText $resourceIf[1] | ForEach-Object { [string]$_ })
    $offText = $artifactOff -join ' '
    $onText = $artifactOn -join ' '
    Report 'artifact writes stay on the artifacts prefix and the cache prefix is granted only when the shared cache is on' (
        [string]$resourceIf[0] -eq 'UseSharedCache' -and
        $offText.Contains('/artifacts/*') -and -not $offText.Contains('/cache/') -and
        $onText.Contains('/cache/*') -and $onText.Contains('/artifacts/*')
    ) "off=$offText on=$onText"

    $runnerFilters = New-Object System.Collections.Generic.List[object]
    Find-WebhookFilters $filterIf[1] $runnerFilters
    $repositoryFilter = $false
    foreach ($filter in $runnerFilters) {
        if ([string]$filter['Type'] -eq 'REPOSITORY_NAME' -and [string]$filter['Pattern']['Ref'] -eq 'RepositoryNamePattern' -and [string]$filter['ExcludeMatchedPattern'] -eq 'false') {
            $repositoryFilter = $true
        }
    }
    Report 'runner mode filters the webhook to one repository name' $repositoryFilter (($runnerFilters | ForEach-Object { [string]$_['Type'] }) -join ',')
}

$preflight = Read-Utf8 $preflightPath
$mutatingCli = [regex]::Matches($preflight, '(?i)(?<![A-Za-z])(create|update|delete|put|start|stop)-[a-z0-9-]+')
$mutatingApi = [regex]::Matches($preflight, '(?-i)\b(Create|Update|Delete|Put|Start|Stop)[A-Z][A-Za-z0-9]+\b')
$mutatingDetail = @(
    @($mutatingCli | ForEach-Object { $_.Value })
    @($mutatingApi | ForEach-Object { $_.Value })
) | Where-Object { $_ }
Report 'the preflight source contains no create, update, delete, put, start, or stop AWS operation' (@($mutatingDetail).Count -eq 0) (@($mutatingDetail) -join ', ')

$requiredReads = @(
    'get-caller-identity', 'list-projects', 'batch-get-projects', 'list-builds-for-project',
    'batch-get-builds', 'list-connections', 'list-service-quotas'
)
$missingReads = @($requiredReads | Where-Object { $preflight -notlike "*$_*" })
Report 'the preflight names the read operations it is allowed to call' ($missingReads.Count -eq 0) ($missingReads -join ', ')

$operationMatch = [regex]::Match($preflight, "\`$script:ReadOnlyOperationPattern = '([^']+)'")
$operationPattern = $operationMatch.Groups[1].Value
$blockedOperation = (-join @('s', 't', 'a', 'r', 't')) + '-build'
Report 'the read-only guard allows list and batch-get and rejects a mutating operation' (
    $operationMatch.Success -and ('list-projects' -match $operationPattern) -and ('batch-get-builds' -match $operationPattern) -and ($blockedOperation -notmatch $operationPattern)
) "pattern=$operationPattern"

$self = Invoke-Child -ArgumentList @('-File', $preflightPath, '-SelfTest')
Report 'the preflight self-test passes without AWS' ($self.Code -eq 0 -and $self.Output -match 'SELFTEST ok') "exit=$($self.Code) $($self.Output.Trim())"
$missingArgs = Invoke-Child -ArgumentList @('-File', $preflightPath)
Report 'the preflight refuses to run without a profile and a region' ($missingArgs.Code -ne 0 -and $missingArgs.Output -match 'Profile and Region are required') "exit=$($missingArgs.Code)"
$dashedProfile = Invoke-Child -ArgumentList @('-File', $preflightPath, '-Profile:-example', '-Region', 'us-east-1')
Report 'the preflight refuses a profile that starts with a dash' (
    $dashedProfile.Code -ne 0 -and $dashedProfile.Output -match 'Profile must not start with a dash'
) "exit=$($dashedProfile.Code) $($dashedProfile.Output.Trim())"
$preflightTokens = $null
$preflightErrors = $null
$preflightAst = [System.Management.Automation.Language.Parser]::ParseFile($preflightPath, [ref]$preflightTokens, [ref]$preflightErrors)
$readOnly = $preflightAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Use-ReadOnlyAws'
    }, $false)
$readOnlyBody = if ($readOnly) { $readOnly.Body.Extent.Text } else { '' }
$throws = @()
if ($readOnly) {
    $throws = @($readOnly.Body.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.ThrowStatementAst]
            }, $true))
}
$outputThrows = @($throws | Where-Object { $_.Extent.Text -match 'stderr|stdout|\$detail|Exception' })
$unmaskedThrow = @($outputThrows | Where-Object { $_.Extent.Text -notmatch 'Hide-AwsAccount|Format-ReadOnlyAwsError' })
Report 'preflight errors mask stderr and stdout before they are thrown' (
    $null -ne $readOnly -and
    $readOnlyBody.Contains('ReadAllText($stderrPath)') -and
    $readOnlyBody.Contains('ReadAllText($stdoutPath)') -and
    $readOnlyBody.Contains('Format-ReadOnlyAwsError') -and
    $outputThrows.Count -ge 2 -and
    $unmaskedThrow.Count -eq 0
) "outputThrows=$($outputThrows.Count) unmasked=$($unmaskedThrow.Count)"

$buildspec = Read-Utf8 $buildspecPath
Report 'the AgentHub buildspec calls Validate-AgentHub.ps1' ($buildspec.Contains('pwsh -NoProfile -File ./scripts/Validate-AgentHub.ps1')) ''
Report 'the AgentHub buildspec calls the suite with ci-skip.json' ($buildspec.Contains('pwsh -NoProfile -File ./tests/Run-AllTests.ps1 -SkipListPath ./tests/ci-skip.json')) ''
Report 'the AgentHub buildspec audits sync against a synthetic profile' ($buildspec.Contains('pwsh -NoProfile -File ./scripts/AgentHub.ps1 sync -UserProfile')) ''
$pins = @('python: 3.12', 'nodejs: 22', 'python3.12', 'ripgrep', 'ffmpeg', '@anthropic-ai/claude-code@2.1.310', 'typescript@5.9.3', '@types/node@24.10.1', 'sha256sum -c', 'aws/codebuild/standard:8.0')
$missingPins = @($pins | Where-Object { -not $buildspec.Contains($_) })
Report 'the AgentHub buildspec installs the same tools the Linux CI job installs' ($missingPins.Count -eq 0) ($missingPins -join ', ')
$unpinned = New-Object System.Collections.Generic.List[string]
if ($buildspec -match 'nodejs\.org/dist/index\.json') { $unpinned.Add('nodejs index.json') }
if ($buildspec -match 'packages\.microsoft\.com') { $unpinned.Add('packages.microsoft.com') }
if ($buildspec -match '(?m)\b(apt-get|apt|dnf|yum)\s+install\b[^\n]*\spowershell(\s|$)') { $unpinned.Add('unversioned powershell package') }
if ($buildspec -match 'curl\s' -and $buildspec -notmatch 'sha256sum -c') { $unpinned.Add('curl without sha256sum') }
if ($buildspec -match 'nodejs\.org' -and $buildspec -notmatch 'SHASUMS256\.txt') { $unpinned.Add('node download without SHASUMS256') }
foreach ($sha in @(
        'becb565095ba0569e1b6d18055ce1114a426523145e6e5ac856928f6b9b013c4',
        '5756f51b51dd9d7895b178e80bbb65bd2f481d8c036cb2d5f8c284368f5040a2'
    )) {
    if (-not $buildspec.Contains($sha)) { $unpinned.Add('missing powershell checksum') }
}
if ($buildspec -notmatch 'releases/download/v7\.7\.0/') { $unpinned.Add('powershell download is not pinned to 7.7.0') }
Report 'the AgentHub buildspec has no unpinned PowerShell or Node download' ($unpinned.Count -eq 0) ($unpinned -join ', ')
$example = Read-Utf8 $examplePath
Report 'the example buildspec publishes the required artifact file' ($example.Contains('ci-out/source-version.txt')) ''

$runbook = Read-Utf8 $runbookPath
$runbookNeedles = @(
    'delete-stack', 'FORK_PULL_REQUESTS', 'ABACare', 'test_ci_release_gate.py', 'SH-4400',
    'coding-agent-dispatch/reviewer', 'billed_minutes', 'break_even_minutes', '0.005',
    '100 build minutes', 'WORKFLOW_JOB_QUEUED', 'CAPABILITY_NAMED_IAM'
)
$missingNeedles = @($runbookNeedles | Where-Object { -not $runbook.Contains($_) })
Report 'the runbook covers deploy, the IAM boundary, forks, cost, rollback, ABACare, and the reviewer' ($missingNeedles.Count -eq 0) ($missingNeedles -join ', ')
$residualStart = $runbook.IndexOf("## Residual risk")
$residualNext = if ($residualStart -ge 0) { $runbook.IndexOf("`n## ", $residualStart + 4) } else { -1 }
$residual = if ($residualStart -ge 0 -and $residualNext -gt $residualStart) { $runbook.Substring($residualStart, $residualNext - $residualStart) } else { '' }
$residualNeed = @(
    'Approved pull-request code runs with the build role',
    'fetch the role credentials',
    'GitHub App token',
    'GetConnectionToken',
    'UseConnection',
    'one connection',
    'fork and actor approval gate is the only barrier',
    'least repository access'
)
$residualMissing = @($residualNeed | Where-Object { -not $residual.Contains($_) })
Report 'the runbook has a Residual risk section' ($residualStart -ge 0 -and $residualMissing.Count -eq 0) ($residualMissing -join ', ')
Report 'the runbook says the shared cache must stay off for outside pull requests' (
    $runbook.Contains('EnableSharedCache') -and
    $runbook.Contains('must not be enabled for repositories that accept outside pull requests') -and
    $runbook.Contains('That prefix is shared by every build')
) ''
Report 'the runbook says runner mode depends on GitHub approval for all outside collaborators' (
    $runbook.Contains('REPOSITORY_NAME') -and
    $runbook.Contains('require approval for all outside collaborators') -and
    $runbook.Contains('OutsideCollaboratorForkApproval') -and
    $runbook.Contains('require-approval-for-all-outside-collaborators')
) ''
Report 'the runbook records that validate-template has still not been run' ($runbook.Contains('CloudFormation `validate-template` has still not been run.')) ''

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("codebuild-pr-ci-" + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    $description = @{
        GitHubOwner = 'example-owner'
        GitHubRepository = 'example-repo'
        ConnectionArn = 'arn:aws:codeconnections:us-east-1:000000000000:connection/00000000-0000-0000-0000-000000000000'
        BuildSpecPath = 'ci/codebuild/buildspecs/agenthub.yml'
        ArtifactBucketName = 'example-ci-artifacts'
        BaseBranches = @('main', 'release.1')
        PrivilegedMode = $false
    }
    $descriptionPath = Join-Path $scratch 'repo.json'
    $parameterPath = Join-Path $scratch 'params.json'
    Write-Utf8 $descriptionPath (($description | ConvertTo-Json -Depth 4) + "`n")
    $happy = Invoke-Child -ArgumentList @('-File', $writerPath, '-DescriptionPath', $descriptionPath, '-OutPath', $parameterPath)
    $rows = @()
    if ($happy.Code -eq 0 -and (Test-Path -LiteralPath $parameterPath)) {
        $rows = @((Read-Utf8 $parameterPath) | ConvertFrom-Json)
    }
    $byKey = @{}
    foreach ($row in $rows) { $byKey[[string]$row.ParameterKey] = [string]$row.ParameterValue }
    $missingKeys = @($expectedParameters | Where-Object { -not $byKey.ContainsKey($_) })
    Report 'the parameter writer accepts one repository description' ($happy.Code -eq 0 -and $rows.Count -eq $expectedParameters.Count -and $missingKeys.Count -eq 0) "exit=$($happy.Code) count=$($rows.Count) missing=$($missingKeys -join ',') $($happy.Output.Trim())"
    Report 'the parameter file keeps privileged mode off and carries no role ARN' (
        $byKey['PrivilegedMode'] -eq 'false' -and $byKey['EnableSharedCache'] -eq 'false' -and (($byKey.Values | Where-Object { $_ -match ':role/' }).Count -eq 0)
    ) "privileged=$($byKey['PrivilegedMode']) cache=$($byKey['EnableSharedCache'])"
    Report 'branch names are escaped into one anchored base-ref pattern' ($byKey['BaseBranchPattern'] -eq '^refs/heads/(main|release\.1)$') $byKey['BaseBranchPattern']
    Report 'the repository name pattern is anchored' ($byKey['RepositoryNamePattern'] -eq '^example-repo$') $byKey['RepositoryNamePattern']
    $bytes = [IO.File]::ReadAllBytes($parameterPath)
    $noBom = $bytes.Length -lt 3 -or -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Report 'the parameter file is UTF-8 without a BOM' $noBom ''

    function Assert-WriterRefuses([string]$Name, [string]$Json, [string]$Needle) {
        $path = Join-Path $scratch ($Name + '.json')
        $out = Join-Path $scratch ($Name + '-out.json')
        Write-Utf8 $path ($Json.Trim() + "`n")
        $result = Invoke-Child -ArgumentList @('-File', $writerPath, '-DescriptionPath', $path, '-OutPath', $out)
        Report $Name ($result.Code -ne 0 -and $result.Output -match $Needle) "exit=$($result.Code) $($result.Output.Trim())"
    }

    $base = @'
{
  "GitHubOwner": "example-owner",
  "GitHubRepository": "example-repo",
  "ConnectionArn": "arn:aws:codeconnections:us-east-1:000000000000:connection/00000000-0000-0000-0000-000000000000",
  "BuildSpecPath": "ci/codebuild/buildspec.example.yml",
  "ArtifactBucketName": "example-ci-artifacts"
}
'@
    $withRoleField = $base.Replace('"ArtifactBucketName": "example-ci-artifacts"', '"ArtifactBucketName": "example-ci-artifacts", "DeploymentRole": "arn:aws:iam::000000000000:role/app-deployment-role"')
    Assert-WriterRefuses 'the parameter writer refuses a deployment role field' $withRoleField 'refusing a deployment role'
    $withDeployArn = $base.Replace('example-ci-artifacts', 'arn:aws:iam::000000000000:role/app-deployment-role')
    Assert-WriterRefuses 'the parameter writer refuses a deployment role ARN' $withDeployArn 'refusing a deployment role ARN'
    $withProdArn = $base.Replace('example-ci-artifacts', 'arn:aws:iam::000000000000:role/production-app')
    Assert-WriterRefuses 'the parameter writer refuses a production role ARN' $withProdArn 'refusing a production role ARN'
    $withOtherArn = $base.Replace('example-ci-artifacts', 'arn:aws:iam::000000000000:role/example-build')
    Assert-WriterRefuses 'the parameter writer refuses a supplied build role ARN' $withOtherArn 'refusing a supplied IAM role ARN'
    $withIsoArn = $base.Replace('example-ci-artifacts', 'arn:aws-iso:iam::000000000000:role/x')
    Assert-WriterRefuses 'the parameter writer refuses a role ARN in another partition' $withIsoArn 'refusing a supplied IAM role ARN'
    $withEmptyAccount = $base.Replace('example-ci-artifacts', 'arn:aws:iam:::role/x')
    Assert-WriterRefuses 'the parameter writer refuses an account-less role ARN' $withEmptyAccount 'refusing a supplied IAM role ARN'
    $runnerBare = $base.TrimEnd().TrimEnd('}').TrimEnd() + ",`n  `"CiMode`": `"runner`"`n}`n"
    Assert-WriterRefuses 'the parameter writer refuses runner mode without the outside-collaborator confirmation' $runnerBare 'require-approval-for-all-outside-collaborators'
    $runnerWrong = $base.TrimEnd().TrimEnd('}').TrimEnd() + ",`n  `"CiMode`": `"runner`",`n  `"OutsideCollaboratorForkApproval`": `"first-time-contributors`"`n}`n"
    Assert-WriterRefuses 'the parameter writer refuses runner mode unless the confirmation names all outside collaborators' $runnerWrong 'require-approval-for-all-outside-collaborators'

    $runnerOkJson = $base.TrimEnd().TrimEnd('}').TrimEnd() + ",`n  `"CiMode`": `"runner`",`n  `"OutsideCollaboratorForkApproval`": `"require-approval-for-all-outside-collaborators`"`n}`n"
    $runnerPath = Join-Path $scratch 'runner.json'
    $runnerOut = Join-Path $scratch 'runner-out.json'
    Write-Utf8 $runnerPath ($runnerOkJson.Trim() + "`n")
    $runnerOk = Invoke-Child -ArgumentList @('-File', $writerPath, '-DescriptionPath', $runnerPath, '-OutPath', $runnerOut)
    $runnerRows = @{}
    if ($runnerOk.Code -eq 0 -and (Test-Path -LiteralPath $runnerOut)) {
        foreach ($row in @((Read-Utf8 $runnerOut) | ConvertFrom-Json)) { $runnerRows[[string]$row.ParameterKey] = [string]$row.ParameterValue }
    }
    Report 'the parameter writer accepts runner mode when the outside-collaborator confirmation is present' (
        $runnerOk.Code -eq 0 -and $runnerRows['CiMode'] -eq 'runner' -and $runnerRows['RepositoryNamePattern'] -eq '^example-repo$' -and -not $runnerRows.ContainsKey('OutsideCollaboratorForkApproval')
    ) "exit=$($runnerOk.Code) $($runnerOk.Output.Trim())"

    $dottedJson = $base.Replace('"GitHubRepository": "example-repo"', '"GitHubRepository": "example.repo"')
    $dottedPath = Join-Path $scratch 'dotted.json'
    $dottedOut = Join-Path $scratch 'dotted-out.json'
    Write-Utf8 $dottedPath ($dottedJson.Trim() + "`n")
    $dotted = Invoke-Child -ArgumentList @('-File', $writerPath, '-DescriptionPath', $dottedPath, '-OutPath', $dottedOut)
    $dottedPattern = ''
    if ($dotted.Code -eq 0 -and (Test-Path -LiteralPath $dottedOut)) {
        foreach ($row in @((Read-Utf8 $dottedOut) | ConvertFrom-Json)) {
            if ([string]$row.ParameterKey -eq 'RepositoryNamePattern') { $dottedPattern = [string]$row.ParameterValue }
        }
    }
    Report 'the repository name pattern escapes a dot' ($dotted.Code -eq 0 -and $dottedPattern -eq '^example\.repo$') "exit=$($dotted.Code) pattern=$dottedPattern $($dotted.Output.Trim())"

    $cacheJson = $base.TrimEnd().TrimEnd('}').TrimEnd() + ",`n  `"EnableSharedCache`": true`n}`n"
    $cachePath = Join-Path $scratch 'cache.json'
    $cacheOut = Join-Path $scratch 'cache-out.json'
    Write-Utf8 $cachePath ($cacheJson.Trim() + "`n")
    $cacheOn = Invoke-Child -ArgumentList @('-File', $writerPath, '-DescriptionPath', $cachePath, '-OutPath', $cacheOut)
    $cacheValue = ''
    if ($cacheOn.Code -eq 0 -and (Test-Path -LiteralPath $cacheOut)) {
        foreach ($row in @((Read-Utf8 $cacheOut) | ConvertFrom-Json)) {
            if ([string]$row.ParameterKey -eq 'EnableSharedCache') { $cacheValue = [string]$row.ParameterValue }
        }
    }
    Report 'the parameter writer can turn the shared cache on and says it is shared' (
        $cacheOn.Code -eq 0 -and $cacheValue -eq 'true' -and $cacheOn.Output -match 'must not be enabled for repositories that accept outside pull requests'
    ) "exit=$($cacheOn.Code) value=$cacheValue $($cacheOn.Output.Trim())"
    $withCompute = $base.TrimEnd().TrimEnd('}').TrimEnd() + ",`n  `"ComputeType`": `"BUILD_GENERAL1_HUGE`"`n}`n"
    Assert-WriterRefuses 'the parameter writer refuses an unknown compute type' $withCompute 'invalid ComputeType'
    $withBucket = $base.Replace('example-ci-artifacts', 'BAD_BUCKET')
    Assert-WriterRefuses 'the parameter writer refuses an invalid bucket name' $withBucket 'invalid ArtifactBucketName'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Output "RESULT: $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
