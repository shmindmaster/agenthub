#Requires -Version 5.1

function Get-CursorReadinessFailure([string]$Kind, [string]$Uri, $ErrorRecord) {
  if ($ErrorRecord.Exception.Response) {
    return "$Kind $Uri -> $([int]$ErrorRecord.Exception.Response.StatusCode)"
  }
  return "$Kind $Uri -> $($ErrorRecord.Exception.GetType().Name)"
}

function Invoke-CursorCloudReadiness {
  $key = $env:CURSOR_ADMIN_API_KEY
  $keySource = 'CURSOR_ADMIN_API_KEY'
  if ([string]::IsNullOrWhiteSpace($key)) {
    $key = $env:CURSOR_API_KEY
    $keySource = 'CURSOR_API_KEY'
  }
  if ([string]::IsNullOrWhiteSpace($key)) {
    return [ordered]@{
      keySource = 'missing'
      authEndpoint = $null
      auth = $false
      models = @{ reachable = $false; endpoint = $null; sampleCount = 0 }
      setupValidated = $false
      setupReason = 'Machine-level validation does not cover environment setup/run-state confirmation'
      errors = @('missing Cursor API key env var')
    }
  }

  $headers = @{ Authorization = "Bearer $key"; 'User-Agent' = 'agent-capabilities-agentctl/1.0' }
  $meUris = @('https://api.cursor.com/v1/me', 'https://api.cursor.com/v0/me')
  $modelsUris = @('https://api.cursor.com/v1/models', 'https://api.cursor.com/v0/models')
  $result = [ordered]@{
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
