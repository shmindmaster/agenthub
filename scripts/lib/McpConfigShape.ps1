#Requires -Version 5.1

function Test-OpenCodeNativeMcpCatalog {
    param($Servers)

    # A flat OpenCode config can name an individual server "servers".
    return ($Servers -is [System.Collections.IDictionary] -or $Servers -is [pscustomobject]) -and
        $Servers.type -isnot [string] -and $Servers.transport -isnot [string] -and
        $Servers.url -isnot [string] -and $Servers.enabled -isnot [bool] -and
        $Servers.disabled -isnot [bool] -and $Servers.command -isnot [string] -and
        $Servers.command -isnot [array]
}
