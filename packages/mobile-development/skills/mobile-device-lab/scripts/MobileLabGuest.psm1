<#
.SYNOPSIS
    Shared guest-address resolution for the mobile device lab.

.DESCRIPTION
    Every remote operation in this lab is `ssh -o HostName=<address>`, so the
    address is the single point all iOS work passes through. It used to come
    from exactly one source -- `vmrun getGuestIPAddress`, polled blindly until
    it timed out -- with no fallback and no second opinion.

    That source is not trustworthy on its own. Measured 2026-08-17: the guest
    had been up 4h13m, SSH and Appium were both serving normally, and
    `getGuestIPAddress` failed from every shell while `vmrun list` reported
    "Total running VMs: 0". The host-to-guest VMX channel had degraded while
    the network stayed perfectly healthy. Nothing could recover, because the
    only question being asked was of the one component that was broken, and a
    wrong answer from it looked exactly like a guest that was not running.

    The fix is not a better single source. It is to separate *proposing* an
    address from *believing* one:

      propose   the on-disk cache, then the VMware DHCP lease file, then the
                ssh_config HostName, then vmrun -- any of them may be stale,
                wrong, or unavailable

      believe   only an SSH connection that actually completes

    So a proposal is a hypothesis and the SSH probe is the experiment. On the
    day above, the DHCP lease file held the correct address the whole time;
    one probe against it would have turned a lost hour into a lost second.

    A guest that is genuinely still booting looks identical to one that is
    unreachable, so the whole candidate list is retried until -TimeoutSeconds
    elapses rather than failing on the first sweep.

.NOTES
    The cache is a performance and recovery aid, never an authority: a cached
    address is probed exactly like every other candidate, and is written only
    after a probe succeeds. It can therefore go stale safely -- the worst a
    wrong entry costs is one failed probe.
#>

Set-StrictMode -Version Latest

$script:LeaseFile = 'C:\ProgramData\VMware\vmnetdhcp.leases'
$script:CacheFile = Join-Path $env:LOCALAPPDATA 'AgentHub\mobile-device-lab\guest-address.json'

function Get-MobileLabAddressCachePath {
    [CmdletBinding()]
    param()
    return $script:CacheFile
}

function Test-MobileLabGuestSsh {
    <#
    .SYNOPSIS
        The only thing in this module that decides an address is real.
    .DESCRIPTION
        `HostKeyAlias` keeps the known_hosts entry pinned to the logical host
        while HostName moves with DHCP, so a new lease is not reported as a
        host-key change. BatchMode makes a missing key fail fast instead of
        prompting into a script that has no console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Address,
        [string] $SshHost = 'macvm',
        [int] $ConnectTimeoutSeconds = 5
    )

    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & ssh -o "HostName=$Address" -o "HostKeyAlias=$SshHost" -o 'LogLevel=ERROR' -o 'BatchMode=yes' -o "ConnectTimeout=$ConnectTimeoutSeconds" $SshHost 'true' 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $previousEap
    }
}

function Get-MobileLabLeaseAddresses {
    <#
    .SYNOPSIS
        Addresses VMware's own DHCP server has handed out, newest lease first.
    .DESCRIPTION
        This file is the reason the lab can recover from a dead VMX channel:
        it is written by vmnetdhcp on the host, so it stays readable and
        current even when nothing can talk to the guest tools.

        dhcpd appends rather than rewrites, so one address can appear several
        times and the last block for it is the live one. Times are UTC, as the
        file's own header insists at some length.
    #>
    [CmdletBinding()]
    param([string] $Path = $script:LeaseFile)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }

    $now = [DateTime]::UtcNow
    $records = [System.Collections.Generic.List[object]]::new()

    $blocks = [regex]::Matches($text, '(?ms)^lease\s+(?<ip>\d+\.\d+\.\d+\.\d+)\s*\{(?<body>.*?)^\}')
    foreach ($block in $blocks) {
        $body = $block.Groups['body'].Value

        $ends = $null
        $endsMatch = [regex]::Match($body, 'ends\s+\d+\s+(?<stamp>[\d/]+\s+[\d:]+)\s*;')
        if ($endsMatch.Success) {
            $parsed = [DateTime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if ([DateTime]::TryParse($endsMatch.Groups['stamp'].Value, [cultureinfo]::InvariantCulture, $styles, [ref]$parsed)) {
                $ends = $parsed
            }
        }

        $records.Add([pscustomobject]@{
            Address = $block.Groups['ip'].Value
            Ends    = $ends
            Order   = $records.Count
            Expired = ($null -ne $ends -and $ends -lt $now)
        })
    }

    # Unexpired before expired, then latest-appended first. An expired lease is
    # still worth probing: VMware routinely re-issues the same address, and a
    # probe is cheap. It is simply ranked below anything still current.
    return @(
        $records |
            Sort-Object -Property @{ Expression = { $_.Expired }; Ascending = $true }, @{ Expression = { $_.Order }; Descending = $true } |
            Select-Object -ExpandProperty Address -Unique
    )
}

function Get-MobileLabSshConfigAddress {
    [CmdletBinding()]
    param([string] $SshHost = 'macvm')

    $configPath = Join-Path $env:USERPROFILE '.ssh\config'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }

    $inBlock = $false
    foreach ($line in (Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*Host\s+(.+?)\s*$') {
            $inBlock = (($matches[1] -split '\s+') -contains $SshHost)
            continue
        }
        if ($inBlock -and $line -match '^\s*HostName\s+(\S+)') { return $matches[1] }
    }
    return $null
}

function Get-MobileLabCachedAddress {
    [CmdletBinding()]
    param([string] $Vmx)

    if (-not (Test-Path -LiteralPath $script:CacheFile)) { return $null }
    try {
        $cache = Get-Content -LiteralPath $script:CacheFile -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
    if (-not $cache) { return $null }
    $names = @($cache.PSObject.Properties.Name)
    if ($names -notcontains 'address') { return $null }
    # Keyed by VMX so two guests never hand each other an address.
    if ($Vmx -and ($names -contains 'vmx') -and $cache.vmx -and $cache.vmx -ne $Vmx) { return $null }
    return $cache.address
}

function Set-MobileLabCachedAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Address,
        [string] $Vmx,
        [string] $Source
    )

    try {
        $dir = Split-Path -Parent $script:CacheFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [pscustomobject]@{
            address    = $Address
            vmx        = $Vmx
            source     = $Source
            verifiedAt = [DateTime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $script:CacheFile -Encoding UTF8
    } catch {
        # The cache is an optimization. Losing it must never fail a lab run.
        Write-Verbose "Could not write guest address cache: $_"
    }
}

function Get-MobileLabVmrunAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Vmx,
        [Parameter(Mandatory)][string] $VmrunPath,
        [int] $TimeoutSeconds = 20
    )

    # `getGuestIPAddress` can block for a long time, and it is the source with
    # a measured history of hanging when the VMX channel degrades, so it runs
    # out-of-process under a hard timeout. A stuck proposer must not be able to
    # stall the resolver that exists to route around it.
    try {
        $job = Start-Job -ScriptBlock {
            param($exe, $vmx)
            & $exe getGuestIPAddress $vmx 2>&1 | Select-Object -First 1
        } -ArgumentList $VmrunPath, $Vmx

        if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
            $result = (Receive-Job -Job $job -ErrorAction SilentlyContinue | Select-Object -First 1)
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            if ("$result" -match '^\s*(\d+\.\d+\.\d+\.\d+)\s*$') { return $matches[1] }
            return $null
        }

        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $null
    } catch {
        return $null
    }
}

function Resolve-MobileLabGuestAddress {
    <#
    .SYNOPSIS
        Return an address that SSH has just been proven to reach, or throw.
    .OUTPUTS
        [pscustomobject] address, source, attempts, elapsedSeconds
    .EXAMPLE
        $guest = Resolve-MobileLabGuestAddress -Vmx $vmx -VmrunPath $vmrun
        ssh -o "HostName=$($guest.address)" -o HostKeyAlias=macvm macvm 'uptime'
    #>
    [CmdletBinding()]
    param(
        [string] $Vmx,
        [string] $VmrunPath,
        [string] $SshHost = 'macvm',
        [int] $TimeoutSeconds = 120,
        [int] $ProbeTimeoutSeconds = 5,

        # Skip vmrun entirely. Useful when it is known to be the broken
        # component and its per-sweep timeout is pure latency.
        [switch] $SkipVmrun
    )

    $started = [DateTime]::UtcNow
    $attempts = [System.Collections.Generic.List[object]]::new()
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $sweep = 0

    do {
        $sweep++
        $candidates = [System.Collections.Generic.List[object]]::new()

        # Cheapest and most likely correct first: an address that worked before.
        $cached = Get-MobileLabCachedAddress -Vmx $Vmx
        if ($cached) { $candidates.Add([pscustomobject]@{ Address = $cached; Source = 'cache' }) }

        foreach ($leased in (Get-MobileLabLeaseAddresses)) {
            $candidates.Add([pscustomobject]@{ Address = $leased; Source = 'vmnetdhcp-lease' })
        }

        $configured = Get-MobileLabSshConfigAddress -SshHost $SshHost
        if ($configured) { $candidates.Add([pscustomobject]@{ Address = $configured; Source = 'ssh-config' }) }

        # vmrun last, not first: it is the slowest to answer and the only
        # source with a measured history of confidently answering wrong.
        if (-not $SkipVmrun -and $Vmx -and $VmrunPath -and (Test-Path -LiteralPath $VmrunPath)) {
            $fromVmrun = Get-MobileLabVmrunAddress -Vmx $Vmx -VmrunPath $VmrunPath
            if ($fromVmrun) { $candidates.Add([pscustomobject]@{ Address = $fromVmrun; Source = 'vmrun' }) }
        }

        $seen = @{}
        foreach ($candidate in $candidates) {
            if ($seen.ContainsKey($candidate.Address)) { continue }
            $seen[$candidate.Address] = $true

            $reachable = Test-MobileLabGuestSsh -Address $candidate.Address -SshHost $SshHost -ConnectTimeoutSeconds $ProbeTimeoutSeconds
            $attempts.Add([pscustomobject]@{ address = $candidate.Address; source = $candidate.Source; sweep = $sweep; reachable = $reachable })

            if ($reachable) {
                Set-MobileLabCachedAddress -Address $candidate.Address -Vmx $Vmx -Source $candidate.Source
                return [pscustomobject]@{
                    address        = $candidate.Address
                    source         = $candidate.Source
                    attempts       = @($attempts)
                    elapsedSeconds = [math]::Round(([DateTime]::UtcNow - $started).TotalSeconds, 1)
                }
            }
        }

        if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 5 }
    } while ([DateTime]::UtcNow -lt $deadline)

    $tried = if ($attempts.Count -gt 0) {
        (@($attempts | ForEach-Object { "$($_.address) ($($_.source))" }) | Select-Object -Unique) -join ', '
    } else {
        '<no candidate address from any source>'
    }
    throw ("No SSH-reachable address for '$SshHost' after ${TimeoutSeconds}s. Probed: $tried. " +
           "Remediation, in order: confirm the guest is running; " +
           "check $script:LeaseFile for a current lease; " +
           "if the guest is up but every address fails, the VMware NAT network is down rather than the guest. " +
           "A stale cache is not a cause -- every candidate here was probed, not assumed.")
}

function Invoke-MobileLabVmrunStart {
    <#
    .SYNOPSIS
        Run `vmrun start` and return its exit code AND its output.
    .DESCRIPTION
        The output is the only diagnosis vmrun gives. Discarding it (the old
        `| Out-Null`) left "exit -1" as the whole error report. Native stderr
        is merged under 'Continue' so Windows PowerShell 5.1 does not turn the
        first stderr line into a terminating error before the code is read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $VmrunPath,
        [Parameter(Mandatory)][string] $Vmx
    )

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $VmrunPath -T ws start $Vmx nogui 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousEap
    }
    [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Get-MobileLabVmrunList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $VmrunPath)

    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { @(& $VmrunPath list 2>&1 | ForEach-Object { "$_" }) }
    catch { @("vmrun list failed: $($_.Exception.Message)") }
    finally { $ErrorActionPreference = $previousEap }
}

function Invoke-MobileLabGuestBringUp {
    <#
    .SYNOPSIS
        Decide whether the macOS guest needs starting, and start it if so.
    .DESCRIPTION
        `vmrun list` is one witness, not the guest. Measured 2026-08-17 it
        reported zero running VMs while the guest served SSH; measured
        2026-10-13 vmrun start failed with "Unknown error" because the VMware
        host services were stopped. So the decision asks, in order:

          1. does the guest answer SSH right now?   -> never start it
          2. does vmrun list it, or is the canonical
             vmware-vmx process alive?              -> it is up or booting
          3. are the VMware host services running?  -> if not, name them and
                                                       stop, unless the caller
                                                       explicitly allowed repair
          4. vmrun start, keeping its exit code and output

        Every dependency is a script block so the decision is testable without
        a VM. Callers in Start-MobileLab.ps1 wire the live implementations.
    .OUTPUTS
        [pscustomobject] action (already-reachable | already-running | started),
        started, vmrunListed, vmxProcess, controlChannel, guestAddress,
        servicesRepaired, serviceState, evidence
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Vmx,
        [string] $VmrunPath,
        [string] $SshHost = 'macvm',
        [scriptblock] $ProbeGuest,
        [scriptblock] $ListRunning,
        [scriptblock] $TestVmxProcess = { $false },
        [scriptblock] $GetServiceState = { $null },
        [scriptblock] $StartVm,
        [scriptblock] $RepairServices,
        [switch] $RepairServicesAllowed
    )

    # One quick sweep with vmrun skipped: this only decides "do not start a
    # healthy guest". The caller's full resolver still waits for a booting one.
    $probe = if ($ProbeGuest) { & $ProbeGuest } else {
        try { Resolve-MobileLabGuestAddress -Vmx $Vmx -SshHost $SshHost -SkipVmrun -TimeoutSeconds 1 -ProbeTimeoutSeconds 3 } catch { $null }
    }
    $listLines = if ($ListRunning) { @(& $ListRunning) } elseif ($VmrunPath) { @(Get-MobileLabVmrunList -VmrunPath $VmrunPath) } else { @() }
    $normalizedVmx = $Vmx.Replace('/', '\').Trim()
    $listed = [bool](@($listLines | Where-Object { ([string]$_).Trim().Replace('/', '\') -ieq $normalizedVmx }).Count)
    $listSummary = (@($listLines | Where-Object { "$_".Trim() }) -join ' | ')

    $result = [ordered]@{
        action = $null
        started = $false
        vmrunListed = $listed
        vmxProcess = $null
        controlChannel = 'unknown'
        guestAddress = $null
        servicesRepaired = $false
        serviceState = $null
        evidence = $null
    }

    if ($probe -and $probe.address) {
        $result.action = 'already-reachable'
        $result.guestAddress = [string]$probe.address
        $result.controlChannel = if ($listed) { 'healthy' } else { 'degraded' }
        $result.evidence = if ($listed) {
            "guest answered SSH at $($probe.address) (via $($probe.source)) and vmrun lists it"
        } else {
            "guest answered SSH at $($probe.address) (via $($probe.source)) while vmrun list reported '$listSummary'; trusting SSH -- the VMX control channel is degraded, the guest is not, so it was not restarted"
        }
        return [pscustomobject]$result
    }

    $vmxProcess = [bool](& $TestVmxProcess)
    $result.vmxProcess = $vmxProcess
    if ($listed -or $vmxProcess) {
        $result.action = 'already-running'
        $result.controlChannel = if ($listed) { 'healthy' } else { 'degraded' }
        $result.evidence = "guest not yet answering SSH; vmrunListed=$listed vmxProcess=$vmxProcess -- treating it as booting and not starting a second instance"
        return [pscustomobject]$result
    }

    $state = & $GetServiceState
    $result.serviceState = $state
    # The lab requires all three declared services. Which one was causal on
    # 2026-10-13 was not isolated, so the message states the observed failure,
    # not a proven cause. A missing service blocks as well as a stopped one.
    $blocking = @()
    if ($state) { $blocking = @(@($state.notRunning) + @($state.missing)) }
    if ($blocking.Count) {
        if (-not $RepairServicesAllowed) {
            throw ("VMware host services the lab requires are not all running ($($state.summary)). With all three stopped, vmrun start failed with only 'Unknown error' (reproduced 2026-10-13), so startup stops here instead. " +
                   "Nothing was started or changed. Remediation: $($state.remediation)")
        }
        if (-not $RepairServices) { throw 'RepairServicesAllowed was set without a RepairServices implementation.' }
        & $RepairServices $state | Out-Null
        $result.servicesRepaired = $true
        $state = & $GetServiceState
        $result.serviceState = $state
        if ($state -and (@($state.notRunning).Count -or @($state.missing).Count)) {
            throw "VMware host services are still not running after repair ($($state.summary)). Remediation: $($state.remediation)"
        }
    }

    $start = if ($StartVm) { & $StartVm } else { Invoke-MobileLabVmrunStart -VmrunPath $VmrunPath -Vmx $Vmx }
    if ([int]$start.ExitCode -ne 0) {
        $said = (@($start.Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' | ')
        if (-not $said) { $said = '<no output>' }
        $serviceText = if ($state) { "VMware host services: $($state.summary)." } else { 'VMware host service state was not checked.' }
        $remedy = if ($state -and $state.remediation) { $state.remediation } else {
            "Run '& `"$VmrunPath`" -T ws start `"$Vmx`" nogui' by hand to see whether the VMware GUI reports more; check that no other process holds the VMX lock (*.lck beside the VMX); then rerun startup."
        }
        throw "vmrun start failed (exit $($start.ExitCode)): $said. $serviceText Remediation: $remedy"
    }

    $result.action = 'started'
    $result.started = $true
    $result.evidence = "vmrun start succeeded; vmrun list had reported '$listSummary'"
    [pscustomobject]$result
}

Export-ModuleMember -Function Resolve-MobileLabGuestAddress, Test-MobileLabGuestSsh, Get-MobileLabLeaseAddresses, Get-MobileLabSshConfigAddress, Get-MobileLabCachedAddress, Set-MobileLabCachedAddress, Get-MobileLabVmrunAddress, Get-MobileLabAddressCachePath, Invoke-MobileLabVmrunStart, Get-MobileLabVmrunList, Invoke-MobileLabGuestBringUp
