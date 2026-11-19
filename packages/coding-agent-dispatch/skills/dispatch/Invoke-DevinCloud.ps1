#Requires -Version 5.1
<#
.SYNOPSIS
  Create and steer Devin Cloud sessions through the v3 API (Linear SH-4969).

.DESCRIPTION
  One JSON object on stdout per call; refusals and failures go to stderr.
  Exit codes: 0 success, 1 API or transport failure, 3 policy refusal (policy
  disabled, missing key, concurrency cap, bad input), 4 wait timeout.

  Policy and every value come from registry/fleet-profile.json
  dispatchPolicy.devin-cloud.cloudBudgetAuthorization: apiBase, orgId, the
  default max_acu_limit (10), the concurrency cap (3 agenthub-tagged sessions
  in new, claimed, running or resuming) and the 1Password reference for the
  key. The key is read with `op read` through the 1Password service account
  (OP_SERVICE_ACCOUNT_TOKEN), held in memory only, and masked to its last four
  characters anywhere it could be printed. DEVIN_CLOUD_API_KEY is honoured only
  as an in-process override; never persist it.

  Invoke-CodingAgent.ps1 -HostId devin-cloud calls the create action.

.PARAMETER Action
  create   POST /organizations/{org}/sessions after run-tag dedupe and the
           concurrency check. Prints session_id, url, status, max_acu_limit,
           tags, run_id and deduplicated.
  status   GET one session: status, status_detail, acus_consumed,
           pull_requests, structured_output.
  wait     Poll status with backoff until status_detail is finished, status is
           exit, error or suspended, or Devin waits on a person
           (waiting_for_user, waiting_for_approval). Prints the report with an
           outcome field.
  messages List the session's messages.
  message  POST {message} to the session.
  stop     DELETE the session (terminate).
  list     agenthub-tagged sessions (or one -RunId) with the active count.

.PARAMETER MaxAcu
  Per-session max_acu_limit for create. Defaults to
  cloudBudgetAuthorization.defaultMaxAcuLimit; a task passes a higher explicit
  value only when it needs one.

.PARAMETER RunId
  Tags the session run:<RunId>. A create whose run tag already exists returns
  that session instead of a duplicate. Generated when omitted.

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
    [int]$MaxAcu,
    [string]$SchemaFile,
    [string]$Cwd,
    [string]$SessionId,
    [string]$Message,
    [string]$MessageFile,
    [int]$TimeoutSec = 3600,
    [int]$PollSec = 15
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'DevinCloudLib.ps1')
exit (Invoke-DevinCloudMain @PSBoundParameters)
