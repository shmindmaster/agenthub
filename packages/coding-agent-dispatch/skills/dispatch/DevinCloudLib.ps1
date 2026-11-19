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
    # https only; plain http is accepted for a loopback host, which is how the
    # tests reach a local fixture endpoint. The registry rule still requires https.
    if ([string]$auth.apiBase -notmatch '^https://[^/\s]+(/\S*)?$' -and [string]$auth.apiBase -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?(/\S*)?$') { throw (New-DevinCloudRefusal 'refused devin-cloud: cloudBudgetAuthorization.apiBase is not an https URL') }
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
    [void]$psi.EnvironmentVariables.Remove('DEVIN_CLOUD_API_KEY')
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

# Which persistent scopes (User, Machine) hold the variable. Windows only; other
# platforms have no persistent environment scope here.
function Get-DevinCloudPersistedKeyScopes {
    param([string]$Name)
    if ($env:OS -ne 'Windows_NT') { return @() }
    return @(@('User', 'Machine') | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($Name, $_)) })
}

function Resolve-DevinCloudKey {
    param([Parameter(Mandatory)] $Config)
    # The key is runtime-only. A value persisted in the User or Machine
    # environment reaches every process on the machine, so it is refused.
    $persisted = @(Get-DevinCloudPersistedKeyScopes -Name $Config.KeyEnv)
    if ($persisted.Count -gt 0) {
        throw (New-DevinCloudRefusal "refused devin-cloud: $($Config.KeyEnv) is persisted in the $($persisted -join ' and ') environment. The key is runtime-only: remove it from that scope and let the adapter read it with op read through the 1Password service account.")
    }
    $override = [Environment]::GetEnvironmentVariable($Config.KeyEnv, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        # Consume the in-process override so no later child (git, op) inherits it.
        [Environment]::SetEnvironmentVariable($Config.KeyEnv, $null, 'Process')
    }
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
# Invoke-RestMethod prints request headers, the bearer included, to the debug
# stream on pwsh 7.4+, and it inherits a caller's -Debug/-Verbose; both are
# silenced for this scope and on the call itself.
function Invoke-DevinApi {
    param([Parameter(Mandatory)] [string]$Method, [Parameter(Mandatory)] [string]$Path, [hashtable]$Query, $Body, [int]$TimeoutSec = 60)
    $DebugPreference = 'SilentlyContinue'
    $VerbosePreference = 'SilentlyContinue'
    $InformationPreference = 'SilentlyContinue'
    if ($null -eq $script:DevinCloudContext) { throw (New-DevinCloudRefusal 'refused devin-cloud: no API context; resolve the key first') }
    $uri = "$($script:DevinCloudContext.ApiBase)/organizations/$($script:DevinCloudContext.OrgId)$Path" + (ConvertTo-DevinCloudQueryString $Query)
    if ($PSVersionTable.PSEdition -ne 'Core') { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 }
    $request = @{
        Method = $Method
        Uri = $uri
        Headers = @{ Authorization = 'Bearer ' + $script:DevinCloudContext.Key; Accept = 'application/json' }
        TimeoutSec = $TimeoutSec
        ErrorAction = 'Stop'
        Debug = $false
        Verbose = $false
        InformationAction = 'SilentlyContinue'
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
        $failure = New-DevinCloudRefusal (Protect-DevinCloudText "devin-cloud API $Method $Path failed: $label. $detail") 1
        # 429, 5xx and transport failures (timeouts, refused connections) are
        # worth a bounded retry by a poller; anything else is not.
        $failure.Data['HttpStatus'] = $status
        $failure.Data['Transient'] = ($null -eq $status -or $status -eq 429 -or $status -ge 500)
        throw $failure
    }
}

function Assert-DevinCloudSessionId {
    param([string]$SessionId)
    if ($SessionId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$') { throw (New-DevinCloudRefusal 'refused devin-cloud: -SessionId is missing or malformed') }
}

# Pages until has_next_page is false. A listing that cannot complete (a page
# promising more with no cursor, or the safety bound) is a refusal, never a
# silently short answer: dedupe and the concurrency cap both depend on it. The
# v3 SessionsQueryParams have no status filter, so the tag is the only
# server-side narrowing and status is filtered here.
function Get-DevinCloudSessions {
    param([string[]]$Tags, [int]$MaxPages = 1000)
    $items = [Collections.Generic.List[object]]::new()
    $after = $null
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ first = 200 }
        if ($Tags) { $query.tags = @($Tags) }
        if ($after) { $query.after = $after }
        $response = Invoke-DevinApi -Method GET -Path '/sessions' -Query $query
        foreach ($item in @($response.items)) { if ($null -ne $item) { $items.Add($item) } }
        if (-not $response.has_next_page) { return $items.ToArray() }
        if ([string]::IsNullOrWhiteSpace([string]$response.end_cursor)) {
            throw (New-DevinCloudRefusal 'refused devin-cloud: the session listing reported more pages but returned no cursor, so it cannot be completed')
        }
        $after = [string]$response.end_cursor
    }
    throw (New-DevinCloudRefusal "refused devin-cloud: the session listing did not finish within $MaxPages pages")
}

# -MaxAcu arrives as text: [int] conversion would round 2.5 and read 1e3 as 1000.
function ConvertTo-DevinCloudAcuLimit {
    param([AllowNull()][string]$Value)
    if ([string]$Value -notmatch '^[1-9][0-9]{0,5}$') { throw (New-DevinCloudRefusal "refused devin-cloud: -MaxAcu must be a positive whole number (got '$Value')") }
    return [int]$Value
}

# A run id derived from what was asked, so a retry of the same dispatch dedupes.
function Get-DevinCloudDerivedRunId {
    param([string]$Prompt, [string[]]$Repos, [string]$Title)
    $basis = $Prompt + "`n" + ((@($Repos | Where-Object { $_ }) | Sort-Object) -join ',') + "`n" + [string]$Title
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($basis))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    return 'auto-' + $hash.Substring(0, 16)
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
    # A windowless child with the Devin key variable removed from its environment.
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = [string]$git.Source
    $psi.Arguments = '-C "' + $Cwd.TrimEnd('\').Replace('"', '') + '" remote get-url origin'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    [void]$psi.EnvironmentVariables.Remove('DEVIN_CLOUD_API_KEY')
    $process = [Diagnostics.Process]::Start($psi)
    try {
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync(); $null = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { try { $process.Kill() } catch { }; return $null }
        if ($process.ExitCode -ne 0) { return $null }
        return (ConvertTo-DevinCloudRepoName (([string]$stdout.GetAwaiter().GetResult()).Trim()))
    } finally { $process.Dispose() }
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

# Serializes the create path (dedupe lookup, concurrency count, POST) across
# every process on the machine, so two dispatches cannot both pass the checks.
$script:DevinCloudCreateMutexName = 'Global\AgentHub-DevinCloud-Create'

function New-DevinCloudSession {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Title,
        [string]$RunId,
        [string[]]$Tags,
        [string[]]$Repos,
        [string]$MaxAcu,
        [string]$SchemaFile,
        [int]$LockTimeoutSec = 120
    )
    $inner = @{} + $PSBoundParameters
    [void]$inner.Remove('LockTimeoutSec')
    $mutex = [Threading.Mutex]::new($false, $script:DevinCloudCreateMutexName)
    $held = $false
    try {
        try { $held = $mutex.WaitOne([TimeSpan]::FromSeconds([Math]::Max(1, $LockTimeoutSec))) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw (New-DevinCloudRefusal "refused devin-cloud: another create held the machine-wide lock ($($script:DevinCloudCreateMutexName)) for more than $LockTimeoutSec s") }
        return (New-DevinCloudSessionLocked @inner)
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function New-DevinCloudSessionLocked {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Title,
        [string]$RunId,
        [string[]]$Tags,
        [string[]]$Repos,
        [string]$MaxAcu,
        [string]$SchemaFile
    )
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw (New-DevinCloudRefusal 'refused devin-cloud: the prompt is empty') }
    $limit = if ($PSBoundParameters.ContainsKey('MaxAcu')) { ConvertTo-DevinCloudAcuLimit $MaxAcu } else { [int]$Config.DefaultMaxAcu }
    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-DevinCloudDerivedRunId -Prompt $Prompt -Repos $Repos -Title $Title }
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
        # The v3 session response carries no max_acu_limit, so the field is
        # omitted rather than printed as null.
        $report = Get-DevinCloudSessionReport $existing[0]
        return [pscustomobject][ordered]@{ session_id = $report.session_id; url = $report.url; status = $report.status
            tags = $report.tags; run_id = $RunId; deduplicated = $true }
    }

    # Fail closed: a count that cannot complete refuses the create.
    try {
        $active = @(Get-DevinCloudSessions -Tags @('agenthub') | Where-Object { @($_.tags) -contains 'agenthub' -and [string]$_.status -in $script:DevinCloudActiveStatuses })
    } catch {
        throw (New-DevinCloudRefusal "refused devin-cloud: the active-session count could not be completed, so the concurrency cap cannot be checked (fail closed). $($_.Exception.Message)")
    }
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

# True when Devin posted a message after the cutoff: a created_at value, or an
# event_id whose later siblings in the thread count as new.
# True when Devin posted after the cutoff that -Action message printed. Order is
# the thread's own event order, never whole-second created_at alone, so a
# reply in the same second as the cutoff still counts:
# - an event_id cutoff: any Devin message positioned after that event;
# - a created_at cutoff (0 for an empty thread): any Devin message positioned
#   after the first user message at or after the cutoff, which is the message
#   that was just sent.
function Test-DevinCloudNewDevinMessage {
    param([string]$SessionId, [string]$After)
    $thread = @(Get-DevinCloudMessages -SessionId $SessionId)
    $anchor = -1
    if ($After -match '^\d+(\.\d+)?$') {
        $cut = [double]$After
        for ($i = 0; $i -lt $thread.Count; $i++) {
            if ([string]$thread[$i].source -eq 'user' -and [double]$thread[$i].created_at -ge $cut) { $anchor = $i; break }
        }
    } else {
        for ($i = 0; $i -lt $thread.Count; $i++) { if ([string]$thread[$i].event_id -eq $After) { $anchor = $i } }
    }
    if ($anchor -lt 0) { return $false }
    return (@($thread | Select-Object -Skip ($anchor + 1) | Where-Object { [string]$_.source -eq 'devin' }).Count -gt 0)
}

# Polls with backoff until the session finishes, ends, or waits on a person.
# With -After (a message created_at or event_id, as printed by -Action message),
# a waiting_for_user/approval state counts only once Devin has posted after the
# cutoff or the status has changed since the wait began, so a wait right after a
# reply does not return on the stale state.
function Wait-DevinCloudSession {
    param([string]$SessionId, [int]$TimeoutSec = 3600, [int]$PollSec = 15, [string]$After)
    Assert-DevinCloudSessionId $SessionId
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSec))
    $delay = [Math]::Max(1, $PollSec)
    $transientFailures = 0
    $staleWaiting = -not [string]::IsNullOrWhiteSpace($After)
    while ($true) {
        try {
            $session = Get-DevinCloudSession -SessionId $SessionId
            # The message read shares the status read's retry: both sit in this try.
            $newDevinMessage = $false
            if ($staleWaiting -and [string]$session.status_detail -in $script:DevinCloudWaitingDetails) {
                $newDevinMessage = Test-DevinCloudNewDevinMessage -SessionId $SessionId -After $After
            }
            $transientFailures = 0
        } catch {
            # A 429, 5xx or transport failure is retried with backoff, bounded by
            # six in a row and by the deadline; anything else ends the wait.
            $transientFailures++
            $remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
            if ($_.Exception.Data['Transient'] -ne $true -or $transientFailures -gt 6 -or $remaining -le 0) { throw }
            Start-DevinCloudSleep -Seconds ([int][Math]::Max(1, [Math]::Min($delay, [Math]::Ceiling($remaining))))
            $delay = [int][Math]::Min(120, [Math]::Ceiling($delay * 1.5))
            continue
        }
        $report = Get-DevinCloudSessionReport $session
        $outcome = $null
        if ([string]$session.status_detail -eq 'finished') { $outcome = 'finished' }
        elseif ([string]$session.status -in $script:DevinCloudEndStatuses) { $outcome = [string]$session.status }
        elseif ([string]$session.status_detail -in $script:DevinCloudWaitingDetails) {
            if ($staleWaiting -and $newDevinMessage) { $staleWaiting = $false }
            if (-not $staleWaiting) { $outcome = [string]$session.status_detail }
        } else {
            # Any other state means the session moved on since the cutoff.
            $staleWaiting = $false
        }
        if ($outcome) { $report.outcome = $outcome; return [pscustomobject]$report }
        $remaining = ($deadline - [DateTime]::UtcNow).TotalSeconds
        if ($remaining -le 0) { $report.outcome = 'timeout'; return [pscustomobject]$report }
        Start-DevinCloudSleep -Seconds ([int][Math]::Min($delay, [Math]::Ceiling($remaining)))
        $delay = [int][Math]::Min(120, [Math]::Ceiling($delay * 1.5))
    }
}

# Exit code for a wait report: 0 when the session finished, is waiting on a
# person, or exited because a user asked; 4 when it did not finish normally
# (timeout, suspended, error, or exit with any other detail). Read `outcome`.
function Get-DevinCloudWaitExitCode {
    param($Report)
    switch ([string]$Report.outcome) {
        'finished' { return 0 }
        'waiting_for_user' { return 0 }
        'waiting_for_approval' { return 0 }
        'exit' { if ([string]$Report.status_detail -in @('finished', 'user_request')) { return 0 } else { return 4 } }
        default { return 4 }
    }
}

# Pages until has_next_page is false and fails closed (exit 3) when the thread
# cannot be read completely, as Get-DevinCloudSessions does.
function Get-DevinCloudMessages {
    param([string]$SessionId, [int]$MaxPages = 1000)
    Assert-DevinCloudSessionId $SessionId
    $items = [Collections.Generic.List[object]]::new()
    $after = $null
    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ first = 200 }
        if ($after) { $query.after = $after }
        $response = Invoke-DevinApi -Method GET -Path "/sessions/$SessionId/messages" -Query $query
        foreach ($item in @($response.items)) { if ($null -ne $item) { $items.Add($item) } }
        if (-not $response.has_next_page) { return $items.ToArray() }
        if ([string]::IsNullOrWhiteSpace([string]$response.end_cursor)) {
            throw (New-DevinCloudRefusal 'refused devin-cloud: the message listing reported more pages but returned no cursor, so it cannot be completed')
        }
        $after = [string]$response.end_cursor
    }
    throw (New-DevinCloudRefusal "refused devin-cloud: the message listing did not finish within $MaxPages pages")
}

function Send-DevinCloudMessage {
    param([string]$SessionId, [string]$Message)
    Assert-DevinCloudSessionId $SessionId
    if ([string]::IsNullOrWhiteSpace($Message)) { throw (New-DevinCloudRefusal 'refused devin-cloud: the message is empty') }
    # The cutoff for a following `wait -After` is the newest message that exists
    # BEFORE this one is posted (0 and no event id for an empty thread). Taken
    # after the POST it could already be Devin's reply, and the wait would then
    # never see a newer one. A thread that cannot be read stops the send.
    $existing = @(Get-DevinCloudMessages -SessionId $SessionId)
    $cutoff = 0; $cutoffEvent = $null
    if ($existing.Count -gt 0) { $cutoff = $existing[-1].created_at; $cutoffEvent = [string]$existing[-1].event_id }
    $null = Invoke-DevinApi -Method POST -Path "/sessions/$SessionId/messages" -Body ([ordered]@{ message = $Message })
    return [pscustomobject][ordered]@{ session_id = $SessionId; sent = $true; cutoff = $cutoff; cutoff_event_id = $cutoffEvent }
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
# 0 success, 1 API or transport failure, 3 refusal, 4 from wait on a timeout or
# an abnormal outcome (suspended, error, or exit other than finished or
# user_request); see Get-DevinCloudWaitExitCode.
function Invoke-DevinCloudMain {
    param(
        [Parameter(Mandatory)] [ValidateSet('create', 'status', 'messages', 'message', 'stop', 'wait', 'list')] [string]$Action,
        [string]$Prompt,
        [string]$PromptFile,
        [string]$Title,
        [string]$RunId,
        [string[]]$Tag,
        [string[]]$Repo,
        [string]$MaxAcu,
        [string]$SchemaFile,
        [string]$Cwd,
        [string]$SessionId,
        [string]$Message,
        [string]$MessageFile,
        [int]$TimeoutSec = 3600,
        [int]$PollSec = 15,
        [string]$After
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
                $report = Wait-DevinCloudSession -SessionId $SessionId -TimeoutSec $TimeoutSec -PollSec $PollSec -After $After
                Write-DevinCloudJson $report
                return (Get-DevinCloudWaitExitCode $report)
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
