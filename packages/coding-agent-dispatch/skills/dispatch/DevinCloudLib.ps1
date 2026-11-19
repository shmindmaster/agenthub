#Requires -Version 5.1
<#
  Devin Cloud v3 adapter library (Linear SH-4969). Dot-sourced by
  Invoke-DevinCloud.ps1 (session actions) and Get-DevinMcpHeaders.ps1 (the
  Devin MCP headers helper). Defines functions only; running this file does
  nothing.

  Policy comes from registry/fleet-profile.json dispatchPolicy.devin-cloud and
  its cloudBudgetAuthorization record: apiBase, orgId, the per-session
  max_acu_limit default, the concurrency cap and the 1Password reference for
  the key. Nothing here hard-codes those values.

  Key path (owner direction 2026-11-19): `op read <keyOpRef>` through the
  1Password service account (OP_SERVICE_ACCOUNT_TOKEN), run as a windowless
  child whose stdout is captured into memory only. The key is never written to
  disk, a log or the User/Machine environment. DEVIN_CLOUD_API_KEY is honoured
  only as an explicit in-process override (a caller that already resolved the
  key, or a test). Every line this library prints passes through
  Protect-DevinCloudText, which masks the key, and anything shaped like a cog_
  key, to its last four characters.

  Every HTTP request goes through Invoke-DevinApi, so tests replace that one
  function and make no network call. A refusal is an exception whose
  Data['ExitCode'] is 3, matching the dispatcher's policy refusals.
#>

$script:DevinCloudActiveStatuses = @('new', 'claimed', 'running', 'resuming')
$script:DevinCloudEndStatuses = @('exit', 'error', 'suspended')
$script:DevinCloudWaitingDetails = @('waiting_for_user', 'waiting_for_approval')
$script:DevinCloudContext = $null
$script:DevinCloudKey = $null

function New-DevinCloudRefusal {
    param([string]$Message, [int]$Code = 3)
    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $Code
    return $exception
}

function Protect-DevinCloudText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $masked = $Text
    if (-not [string]::IsNullOrEmpty($script:DevinCloudKey) -and $script:DevinCloudKey.Length -ge 4) {
        $masked = $masked.Replace($script:DevinCloudKey, '****' + $script:DevinCloudKey.Substring($script:DevinCloudKey.Length - 4))
    }
    return [regex]::Replace($masked, 'cog_[A-Za-z0-9_\-]{8,}', { param($m) '****' + $m.Value.Substring($m.Value.Length - 4) })
}

function Find-DevinCloudAgentHubRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_ROOT) -and (Test-Path -LiteralPath (Join-Path $env:AGENTHUB_ROOT 'registry\agents.json'))) {
        return (Resolve-Path -LiteralPath $env:AGENTHUB_ROOT).Path
    }
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8 -and $dir; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir 'registry\agents.json')) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    $fallback = 'C:\Repos\shmindmaster\agenthub'
    if (Test-Path -LiteralPath (Join-Path $fallback 'registry\agents.json')) { return $fallback }
    throw (New-DevinCloudRefusal 'refused devin-cloud: AgentHub registry was not found. Set AGENTHUB_ROOT to the agenthub checkout.')
}

function Get-DevinCloudFleet {
    $root = Find-DevinCloudAgentHubRoot
    return (Get-Content -LiteralPath (Join-Path $root 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# Reads dispatchPolicy.devin-cloud. Refuses unless the policy is explicitly
# enabled and its cloudBudgetAuthorization names every value this adapter uses.
function Get-DevinCloudConfig {
    param([Parameter(Mandatory)] $Fleet)
    $entry = if ($Fleet.dispatchPolicy) { $Fleet.dispatchPolicy.PSObject.Properties['devin-cloud'] } else { $null }
    if ($null -eq $entry -or $entry.Value.enabled -ne $true) {
        $why = if ($entry) { (@([string]$entry.Value.reason, [string]$entry.Value.ownerAction) | Where-Object { $_ }) -join ' ' } else { 'no policy record' }
        throw (New-DevinCloudRefusal "refused devin-cloud: dispatchPolicy.devin-cloud is not enabled. $why".TrimEnd())
    }
    $auth = $entry.Value.cloudBudgetAuthorization
    if ($auth -isnot [pscustomobject]) { throw (New-DevinCloudRefusal 'refused devin-cloud: dispatchPolicy.devin-cloud has no cloudBudgetAuthorization record') }
    $missing = @('apiBase', 'orgId', 'keyOpRef', 'defaultMaxAcuLimit', 'maxConcurrentSessions') | Where-Object { [string]::IsNullOrWhiteSpace([string]$auth.$_) }
    if (@($missing).Count -gt 0) { throw (New-DevinCloudRefusal "refused devin-cloud: cloudBudgetAuthorization is missing $(@($missing) -join ', ')") }
    if ([string]$auth.apiBase -notmatch '^https://[^/\s]+(/\S*)?$') { throw (New-DevinCloudRefusal 'refused devin-cloud: cloudBudgetAuthorization.apiBase is not an https URL') }
    if ([string]$auth.orgId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (New-DevinCloudRefusal 'refused devin-cloud: cloudBudgetAuthorization.orgId is malformed') }
    if ([int]$auth.defaultMaxAcuLimit -lt 1 -or [int]$auth.maxConcurrentSessions -lt 1) { throw (New-DevinCloudRefusal 'refused devin-cloud: the ACU and concurrency caps must be positive integers') }
    $keyEnv = if ([string]::IsNullOrWhiteSpace([string]$auth.keyEnv)) { 'DEVIN_CLOUD_API_KEY' } else { [string]$auth.keyEnv }
    return [pscustomobject]@{
        ApiBase = ([string]$auth.apiBase).TrimEnd('/')
        OrgId = [string]$auth.orgId
        KeyEnv = $keyEnv
        KeyOpRef = [string]$auth.keyOpRef
        KeyOpRefNote = [string]$auth.keyOpRefNote
        DefaultMaxAcu = [int]$auth.defaultMaxAcuLimit
        MaxConcurrent = [int]$auth.maxConcurrentSessions
    }
}

function Get-DevinCloudOpCommand {
    $command = Get-Command op -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return [string]$command.Source }
    return $null
}

# The reference uses vault and item ids (op read rejects '&', so the vault name
# "Business & Apps" cannot appear in it); the human-readable names come from
# cloudBudgetAuthorization.keyOpRefNote in the registry, not from this code.
function Get-DevinCloudKeyRefusalText {
    param($Config, [string]$Why)
    $where = if ([string]::IsNullOrWhiteSpace([string]$Config.KeyOpRefNote)) { '' } else { " Item: $($Config.KeyOpRefNote)" }
    return "refused devin-cloud: no Devin Cloud API key ($Why). The adapter reads an org-scoped Devin service-user key (cog_ prefix, session permissions) with op read `"$($Config.KeyOpRef)`" through the 1Password service account (OP_SERVICE_ACCOUNT_TOKEN); create or repair that item.$where $($Config.KeyEnv) is honoured only as an in-process override."
}

# op read through the service account, windowless, stdout kept in memory only.
function Read-DevinCloudKeyFromOp {
    param([Parameter(Mandatory)] $Config, [int]$TimeoutSec = 30)
    $op = Get-DevinCloudOpCommand
    if (-not $op) { throw (New-DevinCloudRefusal (Get-DevinCloudKeyRefusalText $Config 'the 1Password CLI op is not on PATH')) }
    # Service account only: without its token op would fall back to an
    # interactive desktop-app sign-in, which an unattended run must not open.
    if ([string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)) {
        throw (New-DevinCloudRefusal (Get-DevinCloudKeyRefusalText $Config 'OP_SERVICE_ACCOUNT_TOKEN is not set, and the adapter reads the key only through the 1Password service account'))
    }
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $op
    $psi.Arguments = 'read --no-newline "' + ([string]$Config.KeyOpRef).Replace('"', '') + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSec * 1000)) {
            try { $process.Kill() } catch { }
            throw (New-DevinCloudRefusal (Get-DevinCloudKeyRefusalText $Config "op read did not finish within $TimeoutSec s"))
        }
        $key = ([string]$stdout.GetAwaiter().GetResult()).Trim()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($key)) {
            throw (New-DevinCloudRefusal (Get-DevinCloudKeyRefusalText $Config "op read exited $($process.ExitCode) without a value; the item is probably absent"))
        }
        return $key
    } finally {
        $process.Dispose()
    }
}

function Resolve-DevinCloudKey {
    param([Parameter(Mandatory)] $Config)
    $override = [Environment]::GetEnvironmentVariable($Config.KeyEnv, 'Process')
    $key = if (-not [string]::IsNullOrWhiteSpace($override)) { $override.Trim() } else { Read-DevinCloudKeyFromOp -Config $Config }
    $script:DevinCloudKey = $key
    if ($key -notmatch '^cog_') {
        throw (New-DevinCloudRefusal (Get-DevinCloudKeyRefusalText $Config 'the value found is not a cog_ service-user key'))
    }
    return $key
}

function Set-DevinCloudContext {
    param([Parameter(Mandatory)] $Config, [Parameter(Mandatory)] [string]$Key)
    $script:DevinCloudKey = $Key
    $script:DevinCloudContext = [pscustomobject]@{ ApiBase = $Config.ApiBase; OrgId = $Config.OrgId; Key = $Key }
}

function ConvertTo-DevinCloudQueryString {
    param([hashtable]$Query)
    if (-not $Query -or $Query.Count -eq 0) { return '' }
    $pairs = foreach ($name in ($Query.Keys | Sort-Object)) {
        foreach ($value in @($Query[$name])) {
            if ($null -eq $value) { continue }
            [uri]::EscapeDataString([string]$name) + '=' + [uri]::EscapeDataString([string]$value)
        }
    }
    if (@($pairs).Count -eq 0) { return '' }
    return '?' + (@($pairs) -join '&')
}

# The one HTTP function. Path is relative to /organizations/{org}. Errors carry
# the status code and the API's own detail, masked, never the request headers.
function Invoke-DevinApi {
    param([Parameter(Mandatory)] [string]$Method, [Parameter(Mandatory)] [string]$Path, [hashtable]$Query, $Body, [int]$TimeoutSec = 60)
    if ($null -eq $script:DevinCloudContext) { throw (New-DevinCloudRefusal 'refused devin-cloud: no API context; resolve the key first') }
    $uri = "$($script:DevinCloudContext.ApiBase)/organizations/$($script:DevinCloudContext.OrgId)$Path" + (ConvertTo-DevinCloudQueryString $Query)
    if ($PSVersionTable.PSEdition -ne 'Core') { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }
    $request = @{
        Method = $Method
        Uri = $uri
        Headers = @{ Authorization = 'Bearer ' + $script:DevinCloudContext.Key; Accept = 'application/json' }
        TimeoutSec = $TimeoutSec
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 30 -Compress))
    }
    try {
        return (Invoke-RestMethod @request)
    } catch {
        $status = $null
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch { } }
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { [string]$_.ErrorDetails.Message } else { [string]$_.Exception.Message }
        if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }
        $label = if ($status) { "HTTP $status" } else { 'no HTTP response' }
        throw (New-DevinCloudRefusal (Protect-DevinCloudText "devin-cloud API $Method $Path failed: $label. $detail") 1)
    }
}

function Assert-DevinCloudSessionId {
    param([string]$SessionId)
    if ($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$') { throw (New-DevinCloudRefusal 'refused devin-cloud: -SessionId is missing or malformed') }
}

function Get-DevinCloudSessions {
    param([string[]]$Tags, [int]$MaxPages = 10)
    $items = [Collections.Generic.List[object]]::new()
    $after = $null
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ first = 200 }
        if ($Tags) { $query.tags = @($Tags) }
        if ($after) { $query.after = $after }
        $response = Invoke-DevinApi -Method GET -Path '/sessions' -Query $query
        foreach ($item in @($response.items)) { if ($null -ne $item) { $items.Add($item) } }
        if (-not $response.has_next_page -or [string]::IsNullOrWhiteSpace([string]$response.end_cursor)) { break }
        $after = [string]$response.end_cursor
    }
    return $items.ToArray()
}

function ConvertTo-DevinCloudRepoName {
    param([string]$RemoteUrl)
    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return $null }
    $m = [regex]::Match($RemoteUrl.Trim(), '^(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$')
    if (-not $m.Success) { return $null }
    return "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
}

function Get-DevinCloudRepoFromCwd {
    param([string]$Cwd)
    if ([string]::IsNullOrWhiteSpace($Cwd) -or -not (Test-Path -LiteralPath $Cwd -PathType Container)) { return $null }
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { return $null }
    $url = & $git.Source -C $Cwd remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (ConvertTo-DevinCloudRepoName ([string]$url))
}

function Get-DevinCloudSessionReport {
    param($Session)
    return [ordered]@{
        session_id = [string]$Session.session_id
        url = [string]$Session.url
        status = [string]$Session.status
        status_detail = $Session.status_detail
        title = $Session.title
        tags = @($Session.tags)
        acus_consumed = $Session.acus_consumed
        pull_requests = @($Session.pull_requests)
        structured_output = $Session.structured_output
    }
}

function New-DevinCloudSession {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Title,
        [string]$RunId,
        [string[]]$Tags,
        [string[]]$Repos,
        [int]$MaxAcu = 0,
        [string]$SchemaFile
    )
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw (New-DevinCloudRefusal 'refused devin-cloud: the prompt is empty') }
    if ($PSBoundParameters.ContainsKey('MaxAcu') -and $MaxAcu -lt 1) { throw (New-DevinCloudRefusal 'refused devin-cloud: -MaxAcu must be a positive integer') }
    $limit = if ($PSBoundParameters.ContainsKey('MaxAcu')) { $MaxAcu } else { [int]$Config.DefaultMaxAcu }
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('n').Substring(0, 8) }
    if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$') { throw (New-DevinCloudRefusal 'refused devin-cloud: -RunId may use letters, digits, dot, underscore, colon and hyphen only') }
    $runTag = "run:$RunId"
    $allTags = [Collections.Generic.List[string]]::new()
    foreach ($tag in @('agenthub', $runTag) + @($Tags)) {
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        if (-not $allTags.Contains([string]$tag)) { $allTags.Add([string]$tag) }
    }

    # v3 has no idempotency key: a session already carrying this run tag is the answer.
    $existing = @(Get-DevinCloudSessions -Tags @($runTag) | Where-Object { @($_.tags) -contains $runTag } | Sort-Object { [long]$_.created_at } -Descending)
    if ($existing.Count -gt 0) {
        $report = Get-DevinCloudSessionReport $existing[0]
        return [pscustomobject][ordered]@{ session_id = $report.session_id; url = $report.url; status = $report.status; max_acu_limit = $null
            tags = $report.tags; run_id = $RunId; deduplicated = $true }
    }

    $active = @(Get-DevinCloudSessions -Tags @('agenthub') | Where-Object { @($_.tags) -contains 'agenthub' -and [string]$_.status -in $script:DevinCloudActiveStatuses })
    if ($active.Count -ge [int]$Config.MaxConcurrent) {
        $ids = (@($active | ForEach-Object { [string]$_.session_id }) -join ', ')
        throw (New-DevinCloudRefusal "refused devin-cloud: $($active.Count) agenthub-tagged sessions are active ($ids) and the cap is $($Config.MaxConcurrent) (cloudBudgetAuthorization.maxConcurrentSessions). Wait for one to finish or stop one.")
    }

    $body = [ordered]@{
        prompt = $Prompt
        title = $(if ([string]::IsNullOrWhiteSpace($Title)) { "AgentHub $RunId" } else { $Title })
        tags = $allTags.ToArray()
        max_acu_limit = $limit
    }
    $repoList = @($Repos | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($repoList.Count -gt 0) { $body.repos = $repoList }
    if (-not [string]::IsNullOrWhiteSpace($SchemaFile)) {
        if (-not (Test-Path -LiteralPath $SchemaFile -PathType Leaf)) { throw (New-DevinCloudRefusal "refused devin-cloud: schema file not found: $SchemaFile") }
        $schemaText = [IO.File]::ReadAllText($SchemaFile)
        if ([Text.Encoding]::UTF8.GetByteCount($schemaText) -gt 65536) { throw (New-DevinCloudRefusal 'refused devin-cloud: structured_output_schema is over the 64 KB API limit') }
        try { $body.structured_output_schema = $schemaText | ConvertFrom-Json } catch { throw (New-DevinCloudRefusal 'refused devin-cloud: the schema file is not valid JSON') }
    }
    $created = Invoke-DevinApi -Method POST -Path '/sessions' -Body $body
    return [pscustomobject][ordered]@{ session_id = [string]$created.session_id; url = [string]$created.url; status = [string]$created.status
        max_acu_limit = $limit; tags = @($created.tags); run_id = $RunId; deduplicated = $false }
}

function Get-DevinCloudSession {
    param([string]$SessionId)
    Assert-DevinCloudSessionId $SessionId
    return (Invoke-DevinApi -Method GET -Path "/sessions/$SessionId")
}

function Start-DevinCloudSleep {
    param([int]$Seconds)
    Start-Sleep -Seconds $Seconds
}

# Polls with backoff until the session finishes, ends, or waits on a person.
function Wait-DevinCloudSession {
    param([string]$SessionId, [int]$TimeoutSec = 3600, [int]$PollSec = 15)
    Assert-DevinCloudSessionId $SessionId
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSec))
    $delay = [Math]::Max(1, $PollSec)
    while ($true) {
        $session = Get-DevinCloudSession -SessionId $SessionId
        $report = Get-DevinCloudSessionReport $session
        $outcome = $null
        if ([string]$session.status_detail -eq 'finished') { $outcome = 'finished' }
        elseif ([string]$session.status -in $script:DevinCloudEndStatuses) { $outcome = [string]$session.status }
        elseif ([string]$session.status_detail -in $script:DevinCloudWaitingDetails) { $outcome = [string]$session.status_detail }
        if ($outcome) { $report.outcome = $outcome; return [pscustomobject]$report }
        $remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
        if ($remaining -le 0) { $report.outcome = 'timeout'; return [pscustomobject]$report }
        Start-DevinCloudSleep -Seconds ([int][Math]::Min($delay, [Math]::Ceiling($remaining)))
        $delay = [int][Math]::Min(120, [Math]::Ceiling($delay * 1.5))
    }
}

function Get-DevinCloudMessages {
    param([string]$SessionId, [int]$MaxPages = 10)
    Assert-DevinCloudSessionId $SessionId
    $items = [Collections.Generic.List[object]]::new()
    $after = $null
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ first = 200 }
        if ($after) { $query.after = $after }
        $response = Invoke-DevinApi -Method GET -Path "/sessions/$SessionId/messages" -Query $query
        foreach ($item in @($response.items)) { if ($null -ne $item) { $items.Add($item) } }
        if (-not $response.has_next_page -or [string]::IsNullOrWhiteSpace([string]$response.end_cursor)) { break }
        $after = [string]$response.end_cursor
    }
    return $items.ToArray()
}

function Send-DevinCloudMessage {
    param([string]$SessionId, [string]$Message)
    Assert-DevinCloudSessionId $SessionId
    if ([string]::IsNullOrWhiteSpace($Message)) { throw (New-DevinCloudRefusal 'refused devin-cloud: the message is empty') }
    $null = Invoke-DevinApi -Method POST -Path "/sessions/$SessionId/messages" -Body ([ordered]@{ message = $Message })
    return [pscustomobject][ordered]@{ session_id = $SessionId; sent = $true }
}

function Stop-DevinCloudSession {
    param([string]$SessionId)
    Assert-DevinCloudSessionId $SessionId
    $response = Invoke-DevinApi -Method DELETE -Path "/sessions/$SessionId"
    $status = if ($response -and $response.PSObject.Properties['status']) { [string]$response.status } else { $null }
    return [pscustomobject][ordered]@{ session_id = $SessionId; stopped = $true; status = $status }
}

function Write-DevinCloudJson {
    param($Value)
    [Console]::Out.WriteLine((Protect-DevinCloudText ($Value | ConvertTo-Json -Depth 20 -Compress)))
}

# Entry point shared by Invoke-DevinCloud.ps1. Returns the process exit code:
# 0 success, 1 API or transport failure, 3 refusal, 4 wait timeout.
function Invoke-DevinCloudMain {
    param(
        [Parameter(Mandatory)] [ValidateSet('create', 'status', 'messages', 'message', 'stop', 'wait', 'list')] [string]$Action,
        [string]$Prompt,
        [string]$PromptFile,
        [string]$Title,
        [string]$RunId,
        [string[]]$Tag,
        [string[]]$Repo,
        [int]$MaxAcu,
        [string]$SchemaFile,
        [string]$Cwd,
        [string]$SessionId,
        [string]$Message,
        [string]$MessageFile,
        [int]$TimeoutSec = 3600,
        [int]$PollSec = 15
    )
    try {
        $config = Get-DevinCloudConfig -Fleet (Get-DevinCloudFleet)
        if ($Action -eq 'create') {
            if (-not [string]::IsNullOrWhiteSpace($Prompt) -and -not [string]::IsNullOrWhiteSpace($PromptFile)) { throw (New-DevinCloudRefusal 'refused devin-cloud: pass -Prompt or -PromptFile, not both') }
            if (-not [string]::IsNullOrWhiteSpace($PromptFile)) {
                if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) { throw (New-DevinCloudRefusal "refused devin-cloud: prompt file not found: $PromptFile") }
                $Prompt = [IO.File]::ReadAllText($PromptFile)
            }
            if ([string]::IsNullOrWhiteSpace($Prompt)) { throw (New-DevinCloudRefusal 'refused devin-cloud: pass -Prompt or -PromptFile') }
        }
        if ($Action -eq 'message' -and -not [string]::IsNullOrWhiteSpace($MessageFile)) {
            if (-not (Test-Path -LiteralPath $MessageFile -PathType Leaf)) { throw (New-DevinCloudRefusal "refused devin-cloud: message file not found: $MessageFile") }
            $Message = [IO.File]::ReadAllText($MessageFile)
        }
        if ($Action -in @('status', 'messages', 'message', 'stop', 'wait')) { Assert-DevinCloudSessionId $SessionId }
        $key = Resolve-DevinCloudKey -Config $config
        Set-DevinCloudContext -Config $config -Key $key
        switch ($Action) {
            'create' {
                $repos = @($Repo | Where-Object { $_ })
                if ($repos.Count -eq 0) {
                    $derived = Get-DevinCloudRepoFromCwd -Cwd $(if ($Cwd) { $Cwd } else { (Get-Location).Path })
                    if ($derived) { $repos = @($derived) }
                }
                $create = @{ Config = $config; Prompt = $Prompt; Title = $Title; RunId = $RunId; Tags = $Tag; Repos = $repos; SchemaFile = $SchemaFile }
                if ($PSBoundParameters.ContainsKey('MaxAcu')) { $create.MaxAcu = $MaxAcu }
                Write-DevinCloudJson (New-DevinCloudSession @create)
                return 0
            }
            'status' { Write-DevinCloudJson ([pscustomobject](Get-DevinCloudSessionReport (Get-DevinCloudSession -SessionId $SessionId))); return 0 }
            'messages' { Write-DevinCloudJson ([pscustomobject]@{ session_id = $SessionId; messages = @(Get-DevinCloudMessages -SessionId $SessionId) }); return 0 }
            'message' { Write-DevinCloudJson (Send-DevinCloudMessage -SessionId $SessionId -Message $Message); return 0 }
            'stop' { Write-DevinCloudJson (Stop-DevinCloudSession -SessionId $SessionId); return 0 }
            'wait' {
                $report = Wait-DevinCloudSession -SessionId $SessionId -TimeoutSec $TimeoutSec -PollSec $PollSec
                Write-DevinCloudJson $report
                if ($report.outcome -eq 'timeout') { return 4 }
                if ($report.outcome -eq 'error') { return 1 }
                return 0
            }
            'list' {
                $tags = @('agenthub')
                if ($RunId) { $tags = @("run:$RunId") }
                $sessions = @(Get-DevinCloudSessions -Tags $tags | Where-Object { @($_.tags) -contains $tags[0] } | ForEach-Object { [pscustomobject](Get-DevinCloudSessionReport $_) })
                $activeCount = @($sessions | Where-Object { $_.status -in $script:DevinCloudActiveStatuses }).Count
                Write-DevinCloudJson ([pscustomobject][ordered]@{ active = $activeCount; max_concurrent = $config.MaxConcurrent; sessions = $sessions })
                return 0
            }
        }
    } catch {
        $code = $_.Exception.Data['ExitCode']
        if ($null -eq $code) { $code = 1 }
        [Console]::Error.WriteLine((Protect-DevinCloudText ([string]$_.Exception.Message)))
        return [int]$code
    }
}
