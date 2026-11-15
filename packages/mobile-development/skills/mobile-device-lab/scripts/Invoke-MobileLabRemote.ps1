<#
.SYNOPSIS
    Drive the remote Linux Android worker: build, install, run a Maestro flow,
    bring back evidence, and open a view of the emulator.

.DESCRIPTION
    The worker is one Linux host with KVM, reached by the SSH alias recorded in
    registry/mobile-development.json -> remoteAndroid. It holds no app
    knowledge. Each run sends a `git archive` of the chosen commit and the
    app's lab profile from the registry, so adding an app is a registry entry.

    Nothing heavy runs on this PC: no Docker, no WSL, no local emulator, no
    Gradle. The only local processes are git, ssh, scp and, for `view`, adb and
    scrcpy.

    Turn-taking is a lock on the worker, not the local mutex, because callers
    may be on different machines. A run that finds the lock held stops and
    names the holder.

.EXAMPLE
    mobile.ps1 remote run abacare -Json
    mobile.ps1 remote run rexa -Profile smoke -WorkingTree
    mobile.ps1 remote view
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('status', 'provision', 'start', 'stop', 'run', 'sync', 'view', 'clean')]
    [string]$Action,
    [Parameter(Position = 1)][string]$ProductId,
    [string]$Profile,
    [string]$RepoPath,
    [string]$Ref = 'HEAD',
    # Send tracked, uncommitted changes too (git stash create; nothing is stashed).
    [switch]$WorkingTree,
    # provision only: the worker's address, used once to write the SSH alias.
    [string]$HostName,
    [string]$IdentityFile,
    # view only: prove the stream without opening a window.
    [switch]$Check,
    [int]$LeaseWaitSeconds = 0,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\..\MobileDevelopment.psm1') -Force
$contract = Get-MobileDevelopmentContract
$remote = $contract.remoteAndroid
if (-not $remote) { throw 'registry/mobile-development.json has no remoteAndroid section.' }
$alias = [string]$remote.sshHostAlias
$sshOptions = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15')
$localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }

function Write-Result([object]$Value) {
    if ($Json) { Write-Output ($Value | ConvertTo-Json -Depth 12 -Compress) }
    else { $Value | Format-List | Out-Host }
}

function Invoke-Worker([string]$Command, [string]$InputText) {
    $output = if ($PSBoundParameters.ContainsKey('InputText')) { $InputText | & ssh @sshOptions $alias $Command }
              else { & ssh @sshOptions $alias $Command }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Get-LabApp([string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Id)) { throw "A productId is required for '$Action'." }
    $product = Get-MobileScopeProduct -ProductId $Id -RequireInclude
    $app = @($remote.apps | Where-Object { [string]$_.productId -eq $Id })
    if ($app.Count -ne 1) { throw "Product '$Id' is eligible but has no entry in remoteAndroid.apps. Register it in registry/mobile-development.json." }
    $profileName = if ($Profile) { $Profile } else { [string]$app[0].defaultProfile }
    $selected = $app[0].profiles.PSObject.Properties[$profileName]
    if (-not $selected) { throw "Product '$Id' has no lab profile '$profileName'. Known: $(@($app[0].profiles.PSObject.Properties.Name) -join ', ')" }
    $settings = $selected.Value
    $appPath = if ($product.mobileIdentity.appPath) { [string]$product.mobileIdentity.appPath } else { '.' }
    if ($appPath -notmatch '^(\.|[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*)$') { throw "Unsupported appPath '$appPath'." }

    if ([bool]$product.healthSensitive) {
        # A health-sensitive app may only be built against nothing or a
        # synthetic endpoint on the worker itself. 10.0.2.2 is the emulator's
        # alias for the worker's loopback.
        foreach ($entry in @($settings.env.PSObject.Properties)) {
            $value = [string]$entry.Value
            if ($value -match '^[a-z]+://' -and $value -notmatch '^https?://(10\.0\.2\.2|127\.0\.0\.1|localhost)(:\d+)?(/|$)') {
                throw "Profile '$profileName' sets $($entry.Name) to a non-local address. '$Id' is health-sensitive: lab builds use synthetic data on the worker only."
            }
        }
        if ($settings.launchUrl) {
            Test-MobileLabLaunchUrl -LaunchUrl ([string]$settings.launchUrl) -HealthSensitive:$true
        }
        if ($settings.flowRewrite) {
            # Host-side flow scripts run on the worker; the same fence as the
            # profile env applies to the addresses a rewrite points them at.
            foreach ($entry in @($settings.flowRewrite.PSObject.Properties)) {
                $value = [string]$entry.Value
                if ($value -match '^https?://' -and $value -notmatch '^https?://(10\.0\.2\.2|127\.0\.0\.1|localhost)(:\d+)?(/|$)') {
                    throw "Profile '$profileName' flowRewrite '$($entry.Name)' points at a non-local address. '$Id' is health-sensitive: lab builds use synthetic data on the worker only."
                }
            }
        }
    }
    [pscustomobject]@{ Product = $product; App = $app[0]; ProfileName = $profileName; Settings = $settings; AppPath = $appPath }
}

function Resolve-LabRepo([object]$Lab) {
    $path = if ($RepoPath) { $RepoPath } else { Join-Path 'C:\Repos' (([string]$Lab.Product.repository) -replace '/', '\') }
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) { throw "No git checkout at '$path'. Pass -RepoPath." }
    (Resolve-Path -LiteralPath $path).Path
}

# Windows OpenSSH resets a single large stream mid-transfer on some hosts
# (measured on sh-forge), so archives go to the worker in chunks, each over
# its own connection: upload-chunk per piece, then the receive command that
# assembles them. cmd owns every binary redirection: PowerShell would
# re-encode the stream.
function Send-LabArchive([string]$ArchiveCommand, [string]$Key, [string]$FinishCommand) {
    $tmp = Join-Path $localData "AgentHub\tmp\mobile-lab-send-$PID"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $tarPath = Join-Path $tmp 'archive.tar'
        & cmd.exe /d /c "$ArchiveCommand > `"$tarPath`""
        if ($LASTEXITCODE -ne 0) { throw "Creating the archive failed (exit $LASTEXITCODE)." }
        $chunks = @(Split-MobileLabArchive -Path $tarPath -Destination $tmp)
        & ssh @sshOptions $alias "mobile-lab clear-chunks $Key"
        if ($LASTEXITCODE -ne 0) { throw "The worker could not clear old chunks for '$Key' (exit $LASTEXITCODE)." }
        foreach ($chunk in $chunks) {
            $index = [IO.Path]::GetFileNameWithoutExtension($chunk) -replace '^chunk-', ''
            # Some hosts reset a bulk SSH stream mid-transfer even at chunk
            # size; the upload is idempotent, so retry the same piece.
            $sent = $false
            foreach ($attempt in 1..4) {
                & cmd.exe /d /c "ssh -o BatchMode=yes $alias `"mobile-lab upload-chunk $Key $index`" < `"$chunk`""
                if ($LASTEXITCODE -eq 0) { $sent = $true; break }
                Start-Sleep -Seconds $attempt
            }
            if (-not $sent) { throw "Sending chunk $index to the worker failed after 4 attempts." }
            Remove-Item -LiteralPath $chunk -Force
        }
        & ssh @sshOptions $alias $FinishCommand
        if ($LASTEXITCODE -ne 0) { throw "The worker could not assemble the archive (exit $LASTEXITCODE)." }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Send-LabSource([object]$Lab, [string]$Repo) {
    $commit = (& git -C $Repo rev-parse --verify "$Ref^{commit}").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve '$Ref' in $Repo." }
    $label = $commit
    if ($WorkingTree) {
        $snapshot = (& git -C $Repo stash create 2>$null | Out-String).Trim()
        if ($snapshot) { $commit = $snapshot; $label = "$snapshot (working tree on $label)" }
    }
    if ($commit -notmatch '^[0-9a-f]{40,64}$') { throw "Unexpected commit id '$commit'." }
    # cmd owns the archive redirection: PowerShell would re-encode the binary tar stream.
    $extras = @($Lab.App.extraPaths | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim('/') })
    foreach ($extra in $extras) { if ($extra -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$') { throw "Unsupported extra path '$extra'." } }
    Send-LabArchive "git -C `"$Repo`" archive --format=tar $commit" ([string]$Lab.Product.productId) "mobile-lab receive $($Lab.Product.productId) $($Lab.AppPath) $($extras -join ' ')"
    if ($extras.Count -gt 0) {
        # Gitignored inputs the bundle needs. Stamp on names, sizes and write
        # times so an unchanged folder is not sent again.
        $listing = foreach ($extra in $extras) {
            $root = Join-Path $Repo ($extra -replace '/', '\')
            if (-not (Test-Path -LiteralPath $root)) { throw "Extra path '$extra' is missing in $Repo. Restore it before a lab run." }
            Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName | ForEach-Object { "$($_.FullName.Substring($Repo.Length))|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        $stamp = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($listing -join "`n"))) | ForEach-Object { $_.ToString('x2') })
        $sha.Dispose()
        $current = ((& ssh @sshOptions $alias "mobile-lab extra-stamp $($Lab.Product.productId)") | Out-String).Trim()
        if ($current -ne $stamp) {
            $bsdtar = Join-Path $env:SystemRoot 'System32\tar.exe'
            Send-LabArchive "`"$bsdtar`" -cf - -C `"$Repo`" $($extras -join ' ')" "$($Lab.Product.productId)-extra" "mobile-lab receive-extra $($Lab.Product.productId) $stamp"
        }
    }
    $label
}

# Failures reach a -Json caller as one object, like every other mobile.ps1 route.
trap {
    if ($Json) { Write-Output ([pscustomobject]@{ ok = $false; action = $Action; productId = $ProductId; error = $_.Exception.Message } | ConvertTo-Json -Compress) }
    else { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
}

switch ($Action) {
    'status' {
        $reply = Invoke-Worker 'mobile-lab status'
        if ($reply.ExitCode -ne 0) { throw "Worker '$alias' did not answer. Check the SSH alias, or run: mobile.ps1 remote provision -HostName <address>" }
        Write-Result (($reply.Output -join "`n") | ConvertFrom-Json)
    }
    'provision' {
        $sshConfig = Join-Path $HOME '.ssh\config'
        $hasAlias = (Test-Path -LiteralPath $sshConfig) -and (Select-String -LiteralPath $sshConfig -Pattern "^\s*Host\s+$([regex]::Escape($alias))\s*$" -Quiet)
        if (-not $hasAlias) {
            if (-not $HostName -or -not $IdentityFile) { throw "SSH alias '$alias' is not defined. Pass -HostName <address> -IdentityFile <private key path> once." }
            $block = "`nHost $alias`n  HostName $HostName`n  User $($remote.user)`n  IdentityFile $IdentityFile`n  IdentitiesOnly yes`n  StrictHostKeyChecking accept-new`n  ServerAliveInterval 30`n"
            Add-Content -LiteralPath $sshConfig -Value $block -Encoding ascii
        }
        $workerScripts = Join-Path $PSScriptRoot 'worker'
        $environment = "ANDROID_API=$($remote.apiLevel) AVD_NAME=$($remote.avdName) LAB_USER=$($remote.user) LAB_ROOT=$($remote.labRoot)"
        & ssh @sshOptions -l root $alias 'mkdir -p /root/mobile-lab-provision'
        if ($LASTEXITCODE -ne 0) { throw "Root SSH to '$alias' failed; provisioning needs root once." }
        & scp -q -o BatchMode=yes -o User=root (Join-Path $workerScripts 'provision-android-worker.sh') (Join-Path $workerScripts 'mobile-lab.sh') (Join-Path $workerScripts 'prepare-flow.mjs') "${alias}:/root/mobile-lab-provision/"
        if ($LASTEXITCODE -ne 0) { throw 'Copying the worker scripts failed.' }
        & ssh @sshOptions -l root $alias "cd /root/mobile-lab-provision && $environment bash provision-android-worker.sh && rm -rf /root/mobile-lab-provision" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Provisioning failed (exit $LASTEXITCODE)." }
        $reply = Invoke-Worker 'mobile-lab status'
        Write-Result (($reply.Output -join "`n") | ConvertFrom-Json)
    }
    'start' {
        & ssh @sshOptions $alias 'mobile-lab emulator start' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'The emulator did not start.' }
        Write-Result ((Invoke-Worker 'mobile-lab status').Output -join "`n" | ConvertFrom-Json)
    }
    'stop' {
        & ssh @sshOptions $alias 'mobile-lab emulator stop' | Out-Host
        Write-Result ((Invoke-Worker 'mobile-lab status').Output -join "`n" | ConvertFrom-Json)
    }
    'sync' {
        $lab = Get-LabApp $ProductId
        $source = Send-LabSource $lab (Resolve-LabRepo $lab)
        Write-Result ([pscustomobject]@{ ok = $true; productId = $ProductId; sourceRef = $source; note = 'A debug build with Metro running on the worker reloads from this source.' })
    }
    'run' {
        $lab = Get-LabApp $ProductId
        $repo = Resolve-LabRepo $lab
        $source = Send-LabSource $lab $repo
        $runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $settings = $lab.Settings
        $config = [ordered]@{
            runId = $runId
            appPath = $lab.AppPath
            androidPackage = [string]$lab.Product.mobileIdentity.androidPackage
            variant = if ($settings.variant) { [string]$settings.variant } else { 'release' }
            install = [string]$lab.App.install
            env = if ($settings.env) { $settings.env } else { @{} }
            flow = [string]$settings.flow
            preCommand = [string]$settings.preCommand
            launchUrl = [string]$settings.launchUrl
            flowRewrite = if ($settings.flowRewrite) { $settings.flowRewrite } else { @{} }
            screenshot = [bool]$settings.screenshot
            sourceRef = $source
            leaseWaitSeconds = $LeaseWaitSeconds
            requestedBy = "$env:COMPUTERNAME/$PID"
        }
        $configJson = $config | ConvertTo-Json -Depth 6 -Compress
        # Progress goes to the console; the worker's last stdout object is the result.
        $lines = @($configJson | & ssh @sshOptions $alias "mobile-lab run $ProductId")
        $workerExit = $LASTEXITCODE
        $resultText = ($lines -join "`n")
        $result = $null
        try { $result = $resultText | ConvertFrom-Json } catch { }
        $localDir = Join-Path $localData "AgentHub\mobile-lab\remote-runs\$ProductId\$runId"
        New-Item -ItemType Directory -Force -Path $localDir | Out-Null
        $remoteDir = "$($remote.labRoot)/artifacts/$ProductId/$runId"
        # The APK stays on the worker; evidence comes back.
        # Windows' own bsdtar: GNU tar from Git reads "C:" as a remote host.
        $bsdtar = Join-Path $env:SystemRoot 'System32\tar.exe'
        & cmd.exe /d /c "ssh -o BatchMode=yes $alias `"cd $remoteDir && tar -cf - --exclude=*.apk .`" | `"$bsdtar`" -xf - -C `"$localDir`""
        $evidence = @(Get-ChildItem -LiteralPath $localDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($localDir.Length + 1) })
        if (-not $result) {
            Write-Result ([pscustomobject]@{ ok = $false; productId = $ProductId; profile = $lab.ProfileName; sourceRef = $source; error = 'The run stopped before a verdict; read the logs in evidencePath.'; evidencePath = $localDir; evidence = $evidence })
            exit 1
        }
        $result | Add-Member -NotePropertyName ok -NotePropertyValue ($result.verdict -eq 'pass') -Force
        $result | Add-Member -NotePropertyName profile -NotePropertyValue $lab.ProfileName -Force
        $result | Add-Member -NotePropertyName evidencePath -NotePropertyValue $localDir -Force
        $result | Add-Member -NotePropertyName evidence -NotePropertyValue $evidence -Force
        $result | Add-Member -NotePropertyName syntheticDataOnly -NotePropertyValue ([bool]$lab.Product.healthSensitive) -Force
        Write-Result $result
        if ($workerExit -ne 0 -or $result.verdict -ne 'pass') { exit 1 }
    }
    'clean' {
        $null = Get-LabApp $ProductId
        & ssh @sshOptions $alias "mobile-lab clean $ProductId" | Out-Host
        Write-Result ([pscustomobject]@{ ok = ($LASTEXITCODE -eq 0); productId = $ProductId })
    }
    'view' {
        $scrcpy = Get-Command scrcpy -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $scrcpy) { throw 'scrcpy is not on PATH. Install it once: winget install Genymobile.scrcpy' }
        # scrcpy ships a matching adb; use it so the two never disagree on protocol.
        $bundledAdb = Join-Path (Split-Path $scrcpy.Source) 'adb.exe'
        $adb = if (Test-Path -LiteralPath $bundledAdb) { $bundledAdb } else { (Get-Command adb -CommandType Application | Select-Object -First 1).Source }
        $port = [int]$remote.viewLocalPort
        $serial = "127.0.0.1:$port"
        $tunnel = Start-Process -FilePath 'ssh' -ArgumentList @('-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-N', '-L', "${port}:127.0.0.1:5555", $alias) -WindowStyle Hidden -PassThru
        try {
            $connected = $false
            foreach ($attempt in 1..15) {
                Start-Sleep -Seconds 1
                if ($tunnel.HasExited) { throw "The SSH tunnel to '$alias' closed. Is local port $port already in use?" }
                $state = (& $adb connect $serial 2>&1 | Out-String)
                if ($state -match 'connected to') {
                    $devices = (& $adb devices | Out-String)
                    if ($devices -match "$([regex]::Escape($serial))\s+device") { $connected = $true; break }
                }
            }
            if (-not $connected) { throw "The emulator did not answer through the tunnel. Start it first: mobile.ps1 remote start" }
            $env:ADB = $adb
            if ($Check) {
                $probe = Join-Path $localData "AgentHub\tmp\mobile-lab-view-check-$PID.mkv"
                New-Item -ItemType Directory -Force -Path (Split-Path $probe) | Out-Null
                & $scrcpy.Source -s $serial --no-window --no-playback --no-audio --record $probe --time-limit 6 2>&1 | Out-Null
                $bytes = if (Test-Path -LiteralPath $probe) { (Get-Item -LiteralPath $probe).Length } else { 0 }
                Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
                Write-Result ([pscustomobject]@{ ok = ($bytes -gt 0); serial = $serial; streamBytes = $bytes; window = $false })
                if ($bytes -le 0) { exit 1 }
            } else {
                Write-Host "Opening the remote emulator. Close the window to disconnect."
                & $scrcpy.Source -s $serial --no-audio --window-title "Mobile lab: $alias" --stay-awake
            }
        }
        finally {
            & $adb disconnect $serial 2>&1 | Out-Null
            if (-not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue }
        }
    }
}
