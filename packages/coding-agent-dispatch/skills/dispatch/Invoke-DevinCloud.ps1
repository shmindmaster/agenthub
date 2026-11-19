#Requires -Version 5.1
<#
.SYNOPSIS
  Create and steer Devin Cloud sessions through the v3 API (Linear SH-4969).

.DESCRIPTION
  One JSON object on stdout per call; refusals and failures go to stderr.
  Exit codes: 0 success; 1 API or transport failure; 3 refusal (policy
  disabled, missing or persisted key, concurrency cap, a count that cannot
  complete, the create lock not acquired, bad input); 4 from wait when the
  session did not finish normally (timeout, suspended, error, or exit with any
  detail other than finished or user_request).

  Policy and every value come from registry/fleet-profile.json
  dispatchPolicy.devin-cloud.cloudBudgetAuthorization: apiBase, orgId, the
  default max_acu_limit (10), the concurrency cap (3 agenthub-tagged sessions
  in new, claimed, running or resuming) and the 1Password reference for the
  key. The key is read with `op read` through the 1Password service account
  (OP_SERVICE_ACCOUNT_TOKEN), held in memory only, and masked to its last four
  characters anywhere it could be printed; HTTP calls run with debug and
  verbose output silenced. DEVIN_CLOUD_API_KEY is honoured only as an
  in-process override, removed from the environment before any child starts;
  a value persisted in the User or Machine environment is refused.

  The dedupe lookup, the concurrency count and the POST run under the
  machine-wide mutex Global\AgentHub-DevinCloud-Create. These caps bind only
  this adapter: sessions created through the Devin MCP server are not counted
  or capped here.

  Invoke-CodingAgent.ps1 -HostId devin-cloud calls the create action.

.PARAMETER Action
  create   POST /organizations/{org}/sessions after run-tag dedupe and the
           concurrency check. Prints session_id, url, status, max_acu_limit,
           tags, run_id and deduplicated (a deduplicated result has no
           max_acu_limit: the v3 session response does not carry it).
  status   GET one session: status, status_detail, acus_consumed,
           pull_requests, structured_output.
  wait     Poll status with backoff until status_detail is finished, status is
           exit, error or suspended, or Devin waits on a person
           (waiting_for_user, waiting_for_approval). Retries 429, 5xx and
           timeouts with bounded backoff. Prints the report with an outcome
           field; see the exit codes above.
  messages List the session's messages.
  message  POST {message} to the session. Prints cutoff and cutoff_event_id
           (the newest message) for a following wait -After.
  stop     DELETE the session (terminate).
  list     agenthub-tagged sessions (or one -RunId) with the active count.

.PARAMETER MaxAcu
  Per-session max_acu_limit for create, as a positive whole number (2.5, 1e3
  and abc refuse with exit 3). Defaults to
  cloudBudgetAuthorization.defaultMaxAcuLimit; a task passes a higher explicit
  value only when it needs one.

.PARAMETER RunId
  Tags the session run:<RunId>. A create whose run tag already exists returns
  that session instead of a duplicate. When omitted it is auto-<hash> of the
  prompt, the sorted repos and the title, so an identical retry dedupes; only
  an explicit -RunId starts a new run for the same task.

.PARAMETER After
  For wait: the cutoff printed by message (a created_at value or an event id).
  A waiting state already showing counts only once Devin posts after the
  cutoff or the status changes.

.PARAMETER Repo
  owner/name repositories for the session. Derived from the -Cwd git remote
  (origin on github.com) when omitted.
#>
[CmdletBinding()]
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
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'DevinCloudLib.ps1')
exit (Invoke-DevinCloudMain @PSBoundParameters)
