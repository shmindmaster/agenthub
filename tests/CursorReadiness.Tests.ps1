#Requires -Version 5.1

Describe 'Cursor compound dispatch gate and readiness' {
  BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\AgentCtl.CursorReadiness.ps1')

    function New-CursorProfile($CursorEnabled = $true, $AgentEnabled = $true, $HoldActive = $false) {
      return [pscustomobject]@{
        dispatchPolicy = [pscustomobject]@{
          cursor = [pscustomobject]@{ enabled = $CursorEnabled }
          'cursor-agent' = [pscustomobject]@{ enabled = $AgentEnabled }
        }
        providerHolds = [pscustomobject]@{
          cursor = [pscustomobject]@{ active = $HoldActive; reason = 'synthetic hold' }
        }
      }
    }
  }

  BeforeEach {
    $script:previousAdminKey = $env:CURSOR_ADMIN_API_KEY
    $script:previousApiKey = $env:CURSOR_API_KEY
    $env:CURSOR_ADMIN_API_KEY = $null
    $env:CURSOR_API_KEY = $null
  }

  AfterEach {
    $env:CURSOR_ADMIN_API_KEY = $script:previousAdminKey
    $env:CURSOR_API_KEY = $script:previousApiKey
  }

  It 'fails closed for missing, inconsistent, malformed, and held profiles without network access' {
    Mock Invoke-RestMethod { throw 'network should not be called' }
    $profiles = @(
      $null,
      (New-CursorProfile $false $false $true),
      (New-CursorProfile $true $false $false),
      (New-CursorProfile $false $true $false),
      (New-CursorProfile 'true' $true $false),
      (New-CursorProfile $true 1 $false),
      (New-CursorProfile $true $true 'false'),
      (New-CursorProfile $true $true $true)
    )

    foreach ($profile in $profiles) {
      $result = Invoke-CursorCloudReadiness -FleetProfile $profile
      $result.policyDisabled | Should Be $true
      (Test-CursorDispatchEnabled $profile) | Should Be $false
      (Get-CursorLauncherContent -FleetProfile $profile -Surface ide -Shell cmd) | Should Be (Get-CursorBlockedLauncherContent -Shell cmd)
      (Get-CursorLauncherContent -FleetProfile $profile -Surface ide -Shell posix) | Should Be (Get-CursorBlockedLauncherContent -Shell posix)
      (Get-CursorLauncherContent -FleetProfile $profile -Surface agent -Shell cmd) | Should Be (Get-CursorBlockedLauncherContent -Shell cmd)
      (Get-CursorLauncherContent -FleetProfile $profile -Surface agent -Shell posix) | Should Be (Get-CursorBlockedLauncherContent -Shell posix)
    }
    Assert-MockCalled Invoke-RestMethod -Times 0
  }

  It 'requires both strict Boolean flags and an explicitly inactive provider hold' {
    $enabled = New-CursorProfile $true $true $false
    (Test-CursorDispatchEnabled $enabled) | Should Be $true
    (Get-CursorLauncherContent -FleetProfile $enabled -Surface ide -Shell cmd) | Should Match 'Programs\\cursor'
    (Get-CursorLauncherContent -FleetProfile $enabled -Surface ide -Shell posix) | Should Match 'cursor\.cmd'
    (Get-CursorLauncherContent -FleetProfile $enabled -Surface agent -Shell posix) | Should Match '--yolo'
  }

  It 'makes appended launch commands fail exact blocked-wrapper equality' {
    $expected = (Get-CursorBlockedLauncherContent -Shell cmd).Replace("`r`n", "`n").TrimEnd("`r", "`n")
    $tampered = ((Get-CursorBlockedLauncherContent -Shell cmd) + "`r`n" + 'cursor-agent.cmd %*').Replace("`r`n", "`n").TrimEnd("`r", "`n")
    ($tampered -ceq $expected) | Should Be $false
  }

  It 'ships a Cursor-native always-on rule that blocks SDK, API, CLI, and cloud dispatch' {
    $rule = Get-CursorProviderHoldRuleContent
    $rule | Should Match 'alwaysApply: true'
    $rule | Should Match 'Cursor SDK'
    $rule | Should Match 'Do not read, use, forward, or recreate'
    $rule | Should Match 'both strict Boolean dispatch flags'
  }

  It 'reports missing credentials without making a network request when fully enabled' {
    Mock Invoke-RestMethod { throw 'network should not be called' }
    $result = Invoke-CursorCloudReadiness -FleetProfile (New-CursorProfile)
    $result.policyDisabled | Should Be $false
    $result.keySource | Should Be 'missing'
    $result.auth | Should Be $false
    $result.models.reachable | Should Be $false
    Assert-MockCalled Invoke-RestMethod -Times 0
  }

  It 'uses the API key fallback when fully enabled and the admin key is whitespace' {
    $env:CURSOR_ADMIN_API_KEY = '   '
    $env:CURSOR_API_KEY = 'synthetic-fallback-key'
    Mock Invoke-RestMethod {
      param($Method, $Uri, $Headers, $TimeoutSec, $ErrorAction)
      if ($Uri -match '/me$') { return @{ userId = 'synthetic' } }
      return @{ items = @(@{ id = 'synthetic-model' }) }
    }

    $result = Invoke-CursorCloudReadiness -FleetProfile (New-CursorProfile)
    $result.keySource | Should Be 'CURSOR_API_KEY'
    $result.auth | Should Be $true
    $result.models.reachable | Should Be $true
    $result.models.sampleCount | Should Be 1
    Assert-MockCalled Invoke-RestMethod -Times 2 -ParameterFilter { $Method -eq 'Get' }
  }

  It 'falls back from v1 to v0 without exposing an exception message' {
    $env:CURSOR_API_KEY = 'synthetic-api-key'
    Mock Invoke-RestMethod {
      param($Method, $Uri, $Headers, $TimeoutSec, $ErrorAction)
      if ($Uri -match '/v1/') { throw 'synthetic-secret-value' }
      if ($Uri -match '/me$') { return @{ userId = 'synthetic' } }
      return @{ models = @(@{ id = 'synthetic-model' }) }
    }

    $result = Invoke-CursorCloudReadiness -FleetProfile (New-CursorProfile)
    $serialized = $result | ConvertTo-Json -Depth 8
    $result.authEndpoint | Should Be 'https://api.cursor.com/v0/me'
    $result.models.endpoint | Should Be 'https://api.cursor.com/v0/models'
    $serialized | Should Not Match 'synthetic-secret-value'
    $serialized | Should Not Match 'synthetic-api-key'
  }

  It 'does not mark an empty or unrecognized models payload reachable' {
    $env:CURSOR_API_KEY = 'synthetic-api-key'
    Mock Invoke-RestMethod {
      param($Method, $Uri, $Headers, $TimeoutSec, $ErrorAction)
      if ($Uri -match '/me$') { return @{ userId = 'synthetic' } }
      return @{ unexpected = @(@{ limit = 9999 }) }
    }
    $result = Invoke-CursorCloudReadiness -FleetProfile (New-CursorProfile)
    $result.auth | Should Be $true
    $result.models.reachable | Should Be $false
    $result.models.sampleCount | Should Be 0
    ($result.errors -join '|') | Should Match 'empty or unrecognized payload'
  }

  It 'records an HTTP status without retaining response content' {
    $syntheticRecord = [pscustomobject]@{
      Exception = [pscustomobject]@{
        Response = [pscustomobject]@{ StatusCode = 401 }
      }
    }
    $message = Get-CursorReadinessFailure -Kind 'AUTH' -Uri 'https://api.cursor.com/v1/me' -ErrorRecord $syntheticRecord
    $message | Should Be 'AUTH https://api.cursor.com/v1/me -> 401'
  }
}
