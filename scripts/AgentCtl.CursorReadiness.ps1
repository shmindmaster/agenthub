#Requires -Version 5.1

function Get-CursorReadinessFailure([string]$Kind, [string]$Uri, $ErrorRecord) {
  if ($ErrorRecord.Exception.Response) {
    return "$Kind $Uri -> $([int]$ErrorRecord.Exception.Response.StatusCode)"
  }
  return "$Kind $Uri -> $($ErrorRecord.Exception.GetType().Name)"
}

function Test-StrictBooleanTrue($Value) {
  return ($Value -is [bool] -and $Value)
}

function Test-CursorDispatchEnabled($FleetProfile) {
  if ($null -eq $FleetProfile) { return $false }
  $cursor = $FleetProfile.dispatchPolicy.cursor
  $cursorAgent = $FleetProfile.dispatchPolicy.'cursor-agent'
  $hold = $FleetProfile.providerHolds.cursor
  return (
    $null -ne $cursor -and
    $null -ne $cursorAgent -and
    $null -ne $hold -and
    (Test-StrictBooleanTrue $cursor.enabled) -and
    (Test-StrictBooleanTrue $cursorAgent.enabled) -and
    $hold.active -is [bool] -and
    -not $hold.active
  )
}

function Get-CursorDispatchHoldReason($FleetProfile) {
  if ($null -ne $FleetProfile -and $null -ne $FleetProfile.providerHolds.cursor -and $FleetProfile.providerHolds.cursor.reason) {
    return [string]$FleetProfile.providerHolds.cursor.reason
  }
  return 'Cursor dispatch requires two explicit Boolean enable flags and an explicitly inactive provider hold'
}

function Get-CursorBlockedLauncherContent([ValidateSet('cmd', 'posix')][string]$Shell) {
  if ($Shell -eq 'cmd') {
    return '@echo off' + "`r`n" + 'echo Cursor dispatch is disabled by owner policy. Re-enable it in agenthub before use. 1>&2' + "`r`n" + 'exit /b 2'
  }
  return '#!/usr/bin/env bash' + "`n" + 'echo "Cursor dispatch is disabled by owner policy. Re-enable it in agenthub before use." >&2' + "`n" + 'exit 2'
}

function Get-CursorProviderHoldRuleContent {
  return @'
---
description: Owner provider hold for all Cursor IDE, Agent CLI, Cloud, Background Agent, SDK, and API activity
alwaysApply: true
---

# Cursor provider hold

Cursor is disabled because quota and spend headroom are exhausted.

- Do not invoke Cursor IDE agents, Cursor Agent CLI, Cloud or Background Agents, the Cursor SDK, or Cursor APIs.
- Do not read, use, forward, or recreate `CURSOR_API_KEY` or `CURSOR_ADMIN_API_KEY`.
- Existing Cursor configuration, skills, sessions, and recovery assets are preserved as dormant state only.
- Use the current host's native subagents or another explicitly authorized non-Cursor backend.
- Reauthorization requires explicit owner approval and one reviewed `agenthub` change that enables both strict Boolean dispatch flags, clears the separate provider hold, regenerates and synchronizes instructions, removes this rule, and passes validation without a paid probe.
'@
}

function Get-CursorLauncherContent(
  $FleetProfile,
  [ValidateSet('ide', 'agent')][string]$Surface,
  [ValidateSet('cmd', 'posix')][string]$Shell
) {
  if (-not (Test-CursorDispatchEnabled $FleetProfile)) {
    return Get-CursorBlockedLauncherContent -Shell $Shell
  }
  if ($Surface -eq 'ide' -and $Shell -eq 'cmd') {
    return '@echo off' + "`r`n" + '"%LOCALAPPDATA%\Programs\cursor\resources\app\bin\cursor.cmd" %*'
  }
  if ($Surface -eq 'ide') {
    return '#!/usr/bin/env bash' + "`n" + 'exec "$HOME/AppData/Local/Programs/cursor/resources/app/bin/cursor.cmd" "$@"'
  }
  if ($Shell -eq 'cmd') {
    return '@echo off' + "`r`n" + '"%LOCALAPPDATA%\cursor-agent\cursor-agent.cmd" --yolo --sandbox disabled --approve-mcps %*'
  }
  return '#!/usr/bin/env bash' + "`n" + 'set -euo pipefail' + "`n" + 'CA_DIR="${CURSOR_AGENT_HOME:-$HOME/AppData/Local/cursor-agent}"' + "`n" + 'if [ -x "$CA_DIR/node.exe" ] && [ -f "$CA_DIR/index.js" ]; then' + "`n" + '  exec "$CA_DIR/node.exe" "$CA_DIR/index.js" --yolo --sandbox disabled --approve-mcps "$@"' + "`n" + 'fi' + "`n" + 'VDIR=$(ls -1 "$CA_DIR/versions" 2>/dev/null | sort -V | tail -n1)' + "`n" + 'if [ -z "$VDIR" ]; then echo "cursor-agent: runtime not found" >&2; exit 1; fi' + "`n" + 'exec "$CA_DIR/versions/$VDIR/node.exe" "$CA_DIR/versions/$VDIR/index.js" --yolo --sandbox disabled --approve-mcps "$@"'
}

function Invoke-CursorCloudReadiness($FleetProfile) {
  if (-not (Test-CursorDispatchEnabled $FleetProfile)) {
    return [ordered]@{
      policyDisabled = $true
      policyReason = Get-CursorDispatchHoldReason $FleetProfile
    }
  }

  $key = $env:CURSOR_ADMIN_API_KEY
  $keySource = 'CURSOR_ADMIN_API_KEY'
  if ([string]::IsNullOrWhiteSpace($key)) {
    $key = $env:CURSOR_API_KEY
    $keySource = 'CURSOR_API_KEY'
  }
  if ([string]::IsNullOrWhiteSpace($key)) {
    return [ordered]@{
      policyDisabled = $false
      keySource = 'missing'
      authEndpoint = $null
      auth = $false
      models = @{ reachable = $false; endpoint = $null; sampleCount = 0 }
      setupValidated = $false
      setupReason = 'Machine-level validation does not cover environment setup/run-state confirmation'
      errors = @('missing Cursor API key env var')
    }
  }

  $headers = @{ Authorization = "Bearer $key"; 'User-Agent' = 'agenthub-agentctl/1.0' }
  $meUris = @('https://api.cursor.com/v1/me', 'https://api.cursor.com/v0/me')
  $modelsUris = @('https://api.cursor.com/v1/models', 'https://api.cursor.com/v0/models')
  $result = [ordered]@{
    policyDisabled = $false
    keySource = $keySource
    authEndpoint = $null
    auth = $false
    models = @{ reachable = $false; endpoint = $null; sampleCount = 0 }
    setupValidated = $false
    setupReason = 'Machine-level validation does not cover environment setup/run-state confirmation'
    errors = @()
  }

  foreach ($uri in $meUris) {
    try {
      $null = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 12 -ErrorAction Stop
      $result.auth = $true
      $result.authEndpoint = $uri
      break
    } catch {
      $result.errors += Get-CursorReadinessFailure -Kind 'AUTH' -Uri $uri -ErrorRecord $_
    }
  }
  if (-not $result.auth) { return $result }

  foreach ($uri in $modelsUris) {
    try {
      $payload = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 12 -ErrorAction Stop
      $models = if ($null -ne $payload.items) {
        @($payload.items)
      } elseif ($null -ne $payload.models) {
        @($payload.models)
      } else {
        @()
      }
      if ($models.Count -gt 0) {
        $result.models = @{ reachable = $true; endpoint = $uri; sampleCount = $models.Count }
        break
      }
      $result.errors += "MODELS $uri -> empty or unrecognized payload"
    } catch {
      $result.errors += Get-CursorReadinessFailure -Kind 'MODELS' -Uri $uri -ErrorRecord $_
    }
  }

  return $result
}
