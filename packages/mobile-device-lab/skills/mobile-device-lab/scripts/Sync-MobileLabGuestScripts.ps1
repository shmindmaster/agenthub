#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GuestIp,
    [string]$SshHost = 'macvm',
    [switch]$StageOnly,
    [string]$StagePath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $PSScriptRoot 'guest'
$ownsStage = $false

function Write-Result {
    param([bool]$Ok, [string]$Stage, [object[]]$Files, [bool]$Changed, [bool]$Restarted, [string]$ErrorMessage)
    $result = [ordered]@{
        ok = $Ok
        stage = $Stage
        files = @($Files)
        changed = $Changed
        appiumRestarted = $Restarted
        error = $ErrorMessage
        remediation = if ($Ok) { $null } else { 'Verify guest SSH, then rerun Start-MobileLab.ps1 -Json. Do not hand-edit ~/mobile-lab copies.' }
    }
    if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 5 -Compress) }
    else { $result }
}

try {
    if ($StageOnly -and [string]::IsNullOrWhiteSpace($StagePath)) { throw '-StageOnly requires -StagePath.' }
    if (-not $StageOnly -and [string]::IsNullOrWhiteSpace($GuestIp)) { throw 'GuestIp is required unless -StageOnly is used.' }
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Guest script source missing: $sourceRoot" }

    if ($StageOnly) {
        if (Test-Path -LiteralPath $StagePath) {
            if (@(Get-ChildItem -LiteralPath $StagePath -Force).Count -gt 0) { throw "StagePath must be empty: $StagePath" }
        }
        else { New-Item -ItemType Directory -Path $StagePath -Force | Out-Null }
        $stageRoot = (Resolve-Path -LiteralPath $StagePath).Path
    }
    else {
        $stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('agenthub-mobile-guest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $ownsStage = $true
    }

    $files = [Collections.Generic.List[object]]::new()
    foreach ($source in @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.sh' -File | Sort-Object Name)) {
        if ($source.Name -notmatch '^[A-Za-z0-9._-]+$') { throw "Unsafe guest script name: $($source.Name)" }
        $normalized = [IO.File]::ReadAllText($source.FullName).Replace("`r`n", "`n").Replace("`r", "`n")
        $destination = Join-Path $stageRoot $source.Name
        [IO.File]::WriteAllText($destination, $normalized, [Text.UTF8Encoding]::new($false))
        $files.Add([pscustomobject]@{
                name = $source.Name
                sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            })
    }
    if ($files.Count -eq 0) { throw "No guest shell scripts found under $sourceRoot" }

    if ($StageOnly) {
        Write-Result -Ok $true -Stage 'staged' -Files @($files) -Changed $false -Restarted $false -ErrorMessage $null
        exit 0
    }

    $sshBase = @('-o', "HostName=$GuestIp", '-o', "HostKeyAlias=$SshHost", '-o', 'LogLevel=ERROR', '-o', 'ConnectTimeout=10', '-o', 'BatchMode=yes', $SshHost)
    & ssh @sshBase 'mkdir -p "$HOME/mobile-lab/.agenthub-sync"'
    if ($LASTEXITCODE -ne 0) { throw "Could not create guest staging directory (ssh exit $LASTEXITCODE)." }
    foreach ($file in $files) {
        $localPath = Join-Path $stageRoot $file.name
        $remotePath = "${SshHost}:~/mobile-lab/.agenthub-sync/$($file.name)"
        & scp -o "HostName=$GuestIp" -o "HostKeyAlias=$SshHost" -o "LogLevel=ERROR" -o BatchMode=yes $localPath $remotePath
        if ($LASTEXITCODE -ne 0) { throw "Could not upload $($file.name) (scp exit $LASTEXITCODE)." }
    }

    $fileNames = @($files | ForEach-Object { $_.name }) -join ' '
    $remoteInstall = @'
set -eu
changed=0
restart=0
for name in __AGENTHUB_FILE_NAMES__; do
  src="$HOME/mobile-lab/.agenthub-sync/$name"
  dst="$HOME/mobile-lab/$name"
  if ! cmp -s "$src" "$dst" 2>/dev/null; then
    changed=1
    [ "$name" = "start-appium-guest.sh" ] && restart=1
    install -m 755 "$src" "$dst"
  fi
done
rm -rf "$HOME/mobile-lab/.agenthub-sync"
if [ "$restart" -eq 1 ]; then
  bash "$HOME/mobile-lab/start-appium-guest.sh"
fi
printf 'AGENTHUB_GUEST_SYNC changed=%s restarted=%s\n' "$changed" "$restart"
'@.Replace('__AGENTHUB_FILE_NAMES__', $fileNames)
    $installOutput = @(& ssh @sshBase $remoteInstall 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Guest helper install failed: $(($installOutput | Select-Object -Last 5) -join ' ')" }
    $resultLine = [string]($installOutput | Where-Object { $_ -match '^AGENTHUB_GUEST_SYNC ' } | Select-Object -Last 1)
    if ($resultLine -notmatch 'changed=([01])\s+restarted=([01])') { throw "Guest helper install returned no result marker: $(($installOutput | Select-Object -Last 5) -join ' ')" }
    Write-Result -Ok $true -Stage 'deployed' -Files @($files) -Changed ($Matches[1] -eq '1') -Restarted ($Matches[2] -eq '1') -ErrorMessage $null
    exit 0
}
catch {
    Write-Result -Ok $false -Stage 'guest-script-sync' -Files @() -Changed $false -Restarted $false -ErrorMessage $_.Exception.Message
    exit 1
}
finally {
    if ($ownsStage -and $stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
