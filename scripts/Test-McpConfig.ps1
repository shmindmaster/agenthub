param(
    [string[]]$ConfigPaths = @(
        "C:\Users\SaroshHussain\AppData\Roaming\Code - Insiders\User\mcp.json"
    ),
    [switch]$IncludeRepoConfigs,
    [switch]$StrictHttp,
    [int]$HttpTimeoutSec = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-ServerConfig {
    param(
        [string]$FilePath,
        [string]$Name,
        [object]$Config,
        [switch]$StrictHttp,
        [int]$HttpTimeoutSec
    )

    $issues = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]

    if (-not $Config.type) {
        $issues.Add("missing type")
    }

    if ($Config.type -eq "stdio") {
        if (-not $Config.command) {
            $issues.Add("missing command")
        }

        if ($null -eq $Config.args) {
            $notes.Add("args omitted (allowed)")
        }
        elseif ($Config.args -is [System.Array]) {
            $notes.Add("args array")
        }
        else {
            $issues.Add("args must be array")
        }

        if ($Config.command) {
            try {
                $null = Get-Command $Config.command -ErrorAction Stop
                $notes.Add("command found")
            }
            catch {
                $issues.Add("command not found: $($Config.command)")
            }
        }

        if (($Config.command -eq "python" -or $Config.command -eq "python3") -and ($Config.args -is [System.Array]) -and $Config.args.Count -gt 0) {
            $firstArg = [string]$Config.args[0]
            if ($firstArg -match "\\.py$") {
                if (Test-Path $firstArg) {
                    $notes.Add("python script exists")
                }
                else {
                    $issues.Add("python script missing: $firstArg")
                }
            }
        }
    }
    elseif ($Config.type -eq "http") {
        if (-not $Config.url) {
            $issues.Add("missing url")
        }
        else {
            try {
                $method = if ($StrictHttp) { "HEAD" } else { "GET" }
                $null = Invoke-WebRequest -Uri $Config.url -Method $method -UseBasicParsing -TimeoutSec $HttpTimeoutSec -MaximumRedirection 2 -ErrorAction Stop
                $notes.Add("url reachable ($method)")
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -match "401|403|404|405|Unauthorized|Forbidden|Method Not Allowed") {
                    $notes.Add("url reachable but auth/method restricted")
                }
                else {
                    $issues.Add("url check failed: $msg")
                }
            }
        }
    }
    elseif ($Config.type) {
        $issues.Add("unknown type: $($Config.type)")
    }

    return [PSCustomObject]@{
        file = $FilePath
        server = $Name
        type = [string]$Config.type
        status = if ($issues.Count -eq 0) { "PASS" } else { "FAIL" }
        issues = if ($issues.Count) { $issues -join " | " } else { "" }
        notes = if ($notes.Count) { $notes -join " | " } else { "" }
    }
}

$allPaths = New-Object System.Collections.Generic.List[string]
foreach ($p in $ConfigPaths) {
    if (-not [string]::IsNullOrWhiteSpace($p)) {
        $allPaths.Add($p)
    }
}

if ($IncludeRepoConfigs) {
    $repoRoot = "C:\Repos\shmindmaster\agenthub"
    if (Test-Path $repoRoot) {
        Get-ChildItem $repoRoot -Recurse -File -Include "*.mcp.json" |
            ForEach-Object { $allPaths.Add($_.FullName) }
    }
}

$uniquePaths = $allPaths | Select-Object -Unique
$results = @()

foreach ($path in $uniquePaths) {
    if (-not (Test-Path $path)) {
        $results += [PSCustomObject]@{
            file = $path
            server = "(file)"
            type = "n/a"
            status = "FAIL"
            issues = "file missing"
            notes = ""
        }
        continue
    }

    try {
        $json = Get-Content $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $results += [PSCustomObject]@{
            file = $path
            server = "(file)"
            type = "n/a"
            status = "FAIL"
            issues = "invalid json"
            notes = $_.Exception.Message
        }
        continue
    }

    if ($json.PSObject.Properties.Match("servers").Count -eq 0) {
        $results += [PSCustomObject]@{
            file = $path
            server = "(none)"
            type = "n/a"
            status = "PASS"
            issues = ""
            notes = "no servers object"
        }
        continue
    }

    foreach ($prop in $json.servers.PSObject.Properties) {
        $results += Test-ServerConfig -FilePath $path -Name $prop.Name -Config $prop.Value -StrictHttp:$StrictHttp -HttpTimeoutSec $HttpTimeoutSec
    }
}

$results | Sort-Object file, server | Format-Table -AutoSize

$total = @($results).Count
$pass = @($results | Where-Object { $_.status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.status -eq "FAIL" }).Count

Write-Output ""
Write-Output "Summary: total=$total pass=$pass fail=$fail"

if ($fail -gt 0) {
    exit 1
}

exit 0
