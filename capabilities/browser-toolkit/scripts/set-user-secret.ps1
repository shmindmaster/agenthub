[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('QWEN_API_KEY', 'ANTHROPIC_AUTH_TOKEN')]
    [string]$Name,

    [Parameter(Mandatory)]
    [Security.SecureString]$Secret
)

$ErrorActionPreference = 'Stop'
$credential = [pscredential]::new('token', $Secret)
$plain = $credential.GetNetworkCredential().Password
try {
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw 'Refusing to store an empty secret.'
    }
    [Environment]::SetEnvironmentVariable($Name, $plain, 'User')
    Write-Host "Stored $Name in the current user's environment. The value was not printed."
}
finally {
    $plain = $null
    $credential = $null
}
