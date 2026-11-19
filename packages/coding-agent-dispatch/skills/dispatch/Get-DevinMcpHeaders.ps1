#Requires -Version 5.1
<#
.SYNOPSIS
  Native headers helper for the official Devin MCP server (Linear SH-4969).

.DESCRIPTION
  A host runs this at connect time (Claude Code `headersHelper`) and reads one
  JSON object from stdout: {"Authorization": "Bearer <key>", "X-Org-Id": "<org>"}.
  The key comes from `op read` through the 1Password service account
  (OP_SERVICE_ACCOUNT_TOKEN), using cloudBudgetAuthorization.keyOpRef in
  registry/fleet-profile.json, and exists only in this process's memory and
  the host's pipe. No host config file holds the key or a key-bearing
  environment variable. Refuses with exit 3 and empty stdout when
  dispatchPolicy.devin-cloud is disabled or no key resolves.

  Never run this in a terminal whose output is recorded: stdout is a credential.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'DevinCloudLib.ps1')
try {
    $config = Get-DevinCloudConfig -Fleet (Get-DevinCloudFleet)
    $key = Resolve-DevinCloudKey -Config $config
    [Console]::Out.WriteLine(([ordered]@{ Authorization = "Bearer $key"; 'X-Org-Id' = $config.OrgId } | ConvertTo-Json -Compress))
    exit 0
} catch {
    $code = $_.Exception.Data['ExitCode']
    if ($null -eq $code) { $code = 1 }
    [Console]::Error.WriteLine((Protect-DevinCloudText ([string]$_.Exception.Message)))
    exit ([int]$code)
}
