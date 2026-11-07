[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../registry/claude-gateway-models.json') -Raw | ConvertFrom-Json
$path = 'HKCU:\Software\Policies\Claude'
$models = @($policy.models | ForEach-Object { @{ name = "claude-compatible/$($_.alias)"; labelOverride = $_.label } })
$desired = @{ inferenceModels = ($models | ConvertTo-Json -Compress); toolSearchEnabled = 'true' }
if (-not $Apply) {
    [pscustomobject]@{ Apply = $false; Default = $policy.default; Models = $models; ToolSearchEnabled = $true } | ConvertTo-Json -Depth 5
    return
}
# Windows policy may be administrator-owned. Do not modify its ACL or export credentials.
$key = Get-Item -LiteralPath $path
$prior = @{}
foreach ($name in $desired.Keys) {
    $exists = $key.GetValueNames() -contains $name
    $prior[$name] = @{ exists = $exists; value = $(if ($exists) { $key.GetValue($name) } else { $null }); kind = $(if ($exists) { $key.GetValueKind($name).ToString() } else { 'String' }) }
}
$backupDir = Join-Path $HOME 'AI/claude-runware/backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir ("native-models-" + [guid]::NewGuid().ToString('N') + '.json')
$prior | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backup -Encoding utf8
$changed = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($name in $desired.Keys) {
        if ($prior[$name].exists -and $prior[$name].value -ceq $desired[$name]) { continue }
        New-ItemProperty -LiteralPath $path -Name $name -Value $desired[$name] -PropertyType String -Force | Out-Null
        $changed.Add($name)
        if ((Get-ItemPropertyValue -LiteralPath $path -Name $name) -cne $desired[$name]) { throw "Readback failed: $name" }
    }
} catch {
    foreach ($name in $changed) {
        if ($prior[$name].exists) {
            New-ItemProperty -LiteralPath $path -Name $name -Value $prior[$name].value -PropertyType $prior[$name].kind -Force | Out-Null
        } else { Remove-ItemProperty -LiteralPath $path -Name $name }
    }
    throw "Native policy update failed; prior selected values recorded at $backup. Run from an administrator PowerShell for the same Windows user. $($_.Exception.Message)"
}
[pscustomobject]@{ Verified = $true; Changed = $changed.Count; Backup = $backup; Default = $policy.default } | ConvertTo-Json
