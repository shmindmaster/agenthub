#Requires -Version 7
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mcps = Get-Content (Join-Path $root 'registry/mcps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$caps = Get-Content (Join-Path $root 'registry/capabilities.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($id in 'firecrawl','supabase') {
    if ($id -notin $mcps.retiredMcpIds) { throw "Missing retirement target $id" }
    if ($id -in $mcps.mcpServers.id -or $id -in $caps.capabilities.id) { throw "Retired provider is still active $id" }
    foreach ($hostEntry in $mcps.activationPolicy.pluginOnly.hosts.PSObject.Properties) {
        if ($hostEntry.Value.PSObject.Properties[$id]) { throw "Retired provider is allowlisted on $($hostEntry.Name)" }
    }
}
foreach ($relative in '.agents/plugins/marketplace.json','.claude-plugin/marketplace.json') {
    $catalog = Get-Content (Join-Path $root $relative) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($catalog.plugins | Where-Object name -Match '^(ah-)?(firecrawl|supabase)$').Count) { throw 'Retired plugin remains published' }
}
Write-Host 'RESULT: 4 passed, 0 failed'
