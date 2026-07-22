param(
  [switch]$PersistUser
)

$ErrorActionPreference = "Stop"
$token = $env:DIGITALOCEAN_API_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:DO_API_TOKEN }
if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:DIGITALOCEAN_ACCESS_TOKEN }

$checks = [ordered]@{
  DIGITALOCEAN_API_TOKEN = -not [string]::IsNullOrWhiteSpace($token)
  doctl = [bool](Get-Command doctl -ErrorAction SilentlyContinue)
  AWS_ACCESS_KEY_ID = -not [string]::IsNullOrWhiteSpace($env:AWS_ACCESS_KEY_ID)
  AWS_SECRET_ACCESS_KEY = -not [string]::IsNullOrWhiteSpace($env:AWS_SECRET_ACCESS_KEY)
  AWS_ENDPOINT_URL_S3 = -not [string]::IsNullOrWhiteSpace($env:AWS_ENDPOINT_URL_S3)
  AWS_REGION = -not [string]::IsNullOrWhiteSpace($env:AWS_REGION)
  DO_SPACES_BUCKET = -not [string]::IsNullOrWhiteSpace($env:DO_SPACES_BUCKET)
  DO_INFERENCE_API_KEY = -not [string]::IsNullOrWhiteSpace($env:DO_INFERENCE_API_KEY)
}

if ($PersistUser -and -not [string]::IsNullOrWhiteSpace($token)) {
  [Environment]::SetEnvironmentVariable("DIGITALOCEAN_API_TOKEN", $token, "User")
  [Environment]::SetEnvironmentVariable("DIGITALOCEAN_ACCESS_TOKEN", $token, "User")
  $env:DIGITALOCEAN_API_TOKEN = $token
  $env:DIGITALOCEAN_ACCESS_TOKEN = $token
}

[pscustomobject]@{
  ok = -not ($checks.Values -contains $false)
  persisted_user_token_aliases = [bool]($PersistUser -and -not [string]::IsNullOrWhiteSpace($token))
  checks = $checks
} | ConvertTo-Json -Depth 4
