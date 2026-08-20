#Requires -Version 5.1

$script:PackageRoot = $PSScriptRoot
$script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $script:PackageRoot '..\..'))

function Read-AgentHubJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $script:RepoRoot ($RelativePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "AgentHub authority is missing: $path"
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-MobileDevelopmentContract {
    [CmdletBinding()]
    param()
    Read-AgentHubJson -RelativePath 'registry/mobile-development.json'
}

function Get-MobileScopeContract {
    [CmdletBinding()]
    param()
    Read-AgentHubJson -RelativePath 'registry/mobile-scope.json'
}

function Get-MobileScopeProduct {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProductId,
        [switch]$RequireInclude
    )

    $scope = Get-MobileScopeContract
    $matches = @($scope.products | Where-Object { [string]$_.productId -eq $ProductId })
    if ($matches.Count -ne 1) {
        throw "Product '$ProductId' is absent from registry/mobile-scope.json. Absence never means eligible; ask the owner to classify it."
    }
    $product = $matches[0]
    if ($RequireInclude -and [string]$product.bucket -ne 'include') {
        $detail = switch ([string]$product.bucket) {
            'evaluateLater' { 'Native value is unproven; no mobile identifier may be reserved.' }
            'excludedPendingReposition' { 'Mobile identity is frozen until the recorded owner-only exit condition is met.' }
            'noNative' { 'This product has no intended native mobile surface.' }
            default { 'The product is not in the include bucket.' }
        }
        throw "Product '$ProductId' is classified '$($product.bucket)', not 'include'. $detail"
    }
    $product
}

function Get-AppiumMcpAuthority {
    [CmdletBinding()]
    param()

    $mcps = Read-AgentHubJson -RelativePath 'registry/mcps.json'
    $matches = @($mcps.mcpServers | Where-Object { [string]$_.id -eq 'appium-mobile' })
    if ($matches.Count -ne 1) { throw "Expected exactly one registry/mcps.json server with id 'appium-mobile'; found $($matches.Count)." }
    $server = $matches[0]
    $packageArgs = @($server.args | Where-Object { [string]$_ -match '^appium-mcp@[^@]+$' })
    if ([string]$server.command -ne 'npx' -or $packageArgs.Count -ne 1) {
        throw "registry/mcps.json#appium-mobile must declare exactly one pinned appium-mcp@<version> argument invoked by npx."
    }
    [pscustomobject]@{
        Server = $server
        Package = [string]$packageArgs[0]
        Version = ([string]$packageArgs[0]).Substring('appium-mcp@'.Length)
    }
}

function Get-MobileDevelopmentRepoRoot {
    [CmdletBinding()]
    param()
    $script:RepoRoot
}

function Get-MobileDevelopmentPackageRoot {
    [CmdletBinding()]
    param()
    $script:PackageRoot
}

function Get-MobileDevelopmentExpectation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('android', 'ios', 'guestAppium', 'xcuitest')][string]$Name)
    (Get-MobileDevelopmentContract).expectations.$Name
}

function Get-MobileDevelopmentResource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $matches = @((Get-MobileDevelopmentContract).resources | Where-Object { [string]$_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Expected exactly one mobile-development resource '$Id'; found $($matches.Count)." }
    $matches[0]
}

function Get-MobileVmxFacts {
    [CmdletBinding()]
    param()

    $contract = Get-MobileDevelopmentContract
    $vmx = ([string]$contract.authorities.vmx) -replace '/', '\'
    if (-not (Test-Path -LiteralPath $vmx -PathType Leaf)) {
        return [pscustomobject]@{ path = $vmx; exists = $false; vcpu = $null; memoryMb = $null }
    }
    $text = Get-Content -LiteralPath $vmx -Raw -Encoding UTF8
    $vcpu = if ($text -match '(?m)^numvcpus\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
    $memory = if ($text -match '(?m)^memsize\s*=\s*"([0-9]+)"') { [int]$Matches[1] } else { $null }
    [pscustomobject]@{ path = $vmx; exists = $true; vcpu = $vcpu; memoryMb = $memory }
}

Export-ModuleMember -Function Read-AgentHubJson, Get-MobileDevelopmentContract, Get-MobileScopeContract, Get-MobileScopeProduct, Get-AppiumMcpAuthority, Get-MobileDevelopmentRepoRoot, Get-MobileDevelopmentPackageRoot, Get-MobileDevelopmentExpectation, Get-MobileDevelopmentResource, Get-MobileVmxFacts
