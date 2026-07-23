#Requires -Version 5.1

Describe 'Cursor cloud read-only readiness' {
  BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\AgentCtl.CursorReadiness.ps1')
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

  It 'reports missing credentials without making a network request' {
    Mock Invoke-RestMethod { throw 'network should not be called' }

    $result = Invoke-CursorCloudReadiness

    $result.keySource | Should Be 'missing'
    $result.auth | Should Be $false
    $result.models.reachable | Should Be $false
    Assert-MockCalled Invoke-RestMethod -Times 0
  }

  It 'fails closed without an explicit enabled dispatch policy' {
    Mock Invoke-RestMethod { throw 'network should not be called' }

    $missingPolicy = Invoke-CursorCloudReadinessForPolicy -DispatchPolicy $null
    $disabledPolicy = Invoke-CursorCloudReadinessForPolicy -DispatchPolicy ([pscustomobject]@{ enabled = $false; reason = 'synthetic hold' })
    $stringPolicy = Invoke-CursorCloudReadinessForPolicy -DispatchPolicy ([pscustomobject]@{ enabled = 'true' })
    $numericPolicy = Invoke-CursorCloudReadinessForPolicy -DispatchPolicy ([pscustomobject]@{ enabled = 1 })

    $missingPolicy.policyDisabled | Should Be $true
    $disabledPolicy.policyDisabled | Should Be $true
    $stringPolicy.policyDisabled | Should Be $true
    $numericPolicy.policyDisabled | Should Be $true
    $disabledPolicy.policyReason | Should Be 'synthetic hold'
    Assert-MockCalled Invoke-RestMethod -Times 0
  }

  It 'uses the API key fallback when the admin key is whitespace' {
    $env:CURSOR_ADMIN_API_KEY = '   '
    $env:CURSOR_API_KEY = 'synthetic-fallback-key'
    Mock Invoke-RestMethod {
      param($Method, $Uri, $Headers, $TimeoutSec, $ErrorAction)
      if ($Uri -match '/me$') { return @{ userId = 'synthetic' } }
      return @{ items = @(@{ id = 'synthetic-model' }) }
    }

    $result = Invoke-CursorCloudReadiness

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

    $result = Invoke-CursorCloudReadiness
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

    $result = Invoke-CursorCloudReadiness

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
