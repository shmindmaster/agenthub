#Requires -Version 5.1
<# Synthetic executables only. No installed agent, login, API or paid run.
   -DispatcherPath supports a regression run against an older dispatcher. #>
[CmdletBinding()]
param([string]$DispatcherPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DispatcherPath) { $DispatcherPath = Join-Path $repoRoot 'packages\coding-agent-dispatch\skills\use-coding-agent\Invoke-CodingAgent.ps1' }
$failed = 0; $checked = 0
function Check([string]$Name, [bool]$Passed, [string]$Detail = '') {
    $script:checked++
    if ($Passed) { Write-Host "PASS: $Name" } else { $script:failed++; Write-Host "FAIL: $Name -- $Detail" }
}
function Quote([string]$Value) {
    $v = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    return '"' + ([regex]::Replace($v, '(\\+)$', '$1$1')) + '"'
}
function Run([string[]]$Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $psi.Arguments = ((@('-NoProfile', '-File', $DispatcherPath) + $Arguments | ForEach-Object { Quote $_ }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false); $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(20000)) { $p.Kill(); throw 'Synthetic test exceeded 20 seconds' }
    $result = [pscustomobject]@{ Exit = $p.ExitCode; Out = $o.GetAwaiter().GetResult(); Err = $e.GetAwaiter().GetResult() }
    $p.Dispose(); return $result
}
$oldRoot = $env:AGENTHUB_ROOT; $oldLocal = $env:LOCALAPPDATA
$fixture = Join-Path $env:TEMP ('cad fixture ' + [guid]::NewGuid().ToString('n'))
try {
    foreach ($dir in @('registry','scripts\lib','scratch','logs')) { $null = New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\lib\PathBinding.ps1') -Destination (Join-Path $fixture 'scripts\lib\PathBinding.ps1')
    $recorder = Join-Path $fixture 'record.cjs'
    @'
const fs = require('node:fs');
if (process.env.CAD_FIXTURE_SLEEP) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 8000);
const args = process.argv.slice(2);
const contents = [];
for (const arg of args) {
  const match = arg.match(/Read the task from this UTF-8 file and carry it out: (.+)$/);
  const file = match ? match[1] : arg;
  if ((match || /prompt-.*\.txt$/.test(arg)) && fs.existsSync(file)) contents.push(fs.readFileSync(file, 'utf8'));
}
console.log(JSON.stringify({Arguments: args, Input: fs.readFileSync(0, 'utf8'), WarpMode: process.env.WARP_CLI_MODE, PromptContents: contents}));
if (process.env.CAD_FIXTURE_EXIT) process.exit(7);
'@ | Set-Content -LiteralPath $recorder -Encoding UTF8
    $stub = Join-Path $fixture 'fake agent.cmd'
    $node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    [IO.File]::WriteAllText($stub, "@echo off`r`n`"$node`" `"$recorder`" %*`r`n")
    $ids = @('claude','codex','cursor','cursor-agent','qwen-code','gemini','grok','opencode','antigravity','factory','cline','copilot','amp','devin','qoder','warp','windsurf','hermes','antigravity-desktop')
    $agents = @{ activeAgents = @($ids | ForEach-Object { @{ id = $_; executable = $stub; surfaceType = $(if ($_ -eq 'antigravity-desktop') { 'companion-desktop' } else { 'cli' }) } }) }
    $fleet = @{ autonomyProfiles = @{ profiles = @($ids | ForEach-Object { @{ hostId = $_; defaultProfile = 'repo-autonomous' } }) }; dispatchPolicy = @{ devin = @{ model = 'swe-2-medium' }; opencode = @{ model = 'opencode/big-pickle' } } }
    function Save-Fixture {
        $agents | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $fixture 'registry\agents.json') -Encoding UTF8
        $fleet | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    }
    Save-Fixture
    $env:AGENTHUB_ROOT = $fixture; $env:LOCALAPPDATA = Join-Path $fixture 'logs'
    $scratch = Join-Path $fixture 'scratch'
    $r = Run @('-List')
    Check 'list succeeds' ($r.Exit -eq 0) $r.Err
    foreach ($id in @('claude','codex','amp','devin','qoder','warp')) { Check "$id headless contract" ($r.Out -match "(?m)^$id\tcallable\t") }
    foreach ($id in @('cursor','windsurf')) { Check "$id routes to CLI" ($r.Out -match "(?m)^$id\trouted\t") }
    foreach ($id in @('hermes','antigravity-desktop')) { Check "$id refuses" ($r.Out -match "(?m)^$id\trefused\t") }
    $r = Run @('-HostId','unknown','-Prompt','ok'); Check 'unknown host refuses' ($r.Exit -eq 3 -and $r.Err -match 'unknown host')
    foreach ($id in @('devin-cloud','jules','cursor-cloud','copilot-agent')) {
        $r = Run @('-HostId',$id,'-Prompt','ok'); Check "$id cloud refuses" ($r.Exit -eq 3 -and $r.Err -match 'hosted cloud execution')
    }
    foreach ($id in @('claude','codex','cursor-agent','qwen-code','gemini','grok','opencode','antigravity','factory','cline','copilot','amp','devin','qoder','warp')) {
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        Check "$id launches synthetic child" ($r.Exit -eq 0 -and $null -ne $d) $r.Err
        if ($id -eq 'codex') {
            Check 'codex accepts non-repo cwd via explicit skip flag' ($d.Arguments -contains '--skip-git-repo-check' -and $d.Arguments -contains '-' -and $d.Input -eq 'ok')
            Check 'codex did not initialize git' (-not (Test-Path (Join-Path $scratch '.git')))
        }
        if ($id -eq 'antigravity') { Check 'agy attaches print value after permissions' ($d.Arguments -contains '--print=ok' -and $d.Arguments[0] -eq '--dangerously-skip-permissions') }
        if ($id -eq 'warp') { Check 'warp receives CLI environment' ($d.WarpMode -eq '1' -and $d.Arguments[0] -eq 'agent' -and $d.Arguments[1] -eq 'run') }
        if ($id -eq 'devin') { Check 'Devin receives prompt file and pinned free model' ($d.PromptContents -contains 'ok' -and $d.Arguments -contains '--prompt-file' -and $d.Arguments -contains 'swe-2-medium') }
        if ($id -eq 'opencode') { Check 'OpenCode receives pinned free model' ($d.Arguments -contains '--model' -and $d.Arguments -contains 'opencode/big-pickle') }
        if ($id -eq 'amp') { Check 'Amp receives unattended stdin contract' ($d.Input -eq 'ok' -and $d.Arguments -contains '-x' -and $d.Arguments -contains '--no-notifications' -and $d.Arguments -contains '--no-ide') }
        if ($id -eq 'qoder') { Check 'Qoder receives print workspace and text options' ($d.Arguments -contains '-p' -and $d.Arguments -contains '-w' -and $d.Arguments -contains $scratch -and $d.Arguments -contains 'text') }
    }
    $text = "quoted `"text`" café`n& echo %PATH% !name! " + ('x' * 9000)
    $taskFile = Join-Path $fixture 'task.txt'; [IO.File]::WriteAllText($taskFile, $text)
    foreach ($id in @('qwen-code','gemini','antigravity','qoder')) {
        $r = Run @('-HostId',$id,'-PromptFile',$taskFile,'-Cwd',$scratch,'-TimeoutSec','5')
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        $detail = "exit=$($r.Exit) lengths=$(@($d.PromptContents | ForEach-Object { $_.Length }) -join ',') expected=$($text.Length) args=$($d.Arguments -join ' ') $($r.Err)"
        Check "$id preserves long quoted multiline prompt" ($r.Exit -eq 0 -and $d.PromptContents -contains $text) $detail
        if ($id -eq 'gemini') { Check 'Gemini admits runtime prompt directory' ($d.Arguments -contains '--include-directories') }
    }
    foreach ($id in @('codex','amp','devin')) {
        $r = Run @('-HostId',$id,'-PromptFile',$taskFile,'-Cwd',$scratch,'-TimeoutSec','5')
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        Check "$id preserves UTF-8 task through stdin or file" ($r.Exit -eq 0 -and ($d.Input -eq $text -or $d.PromptContents -contains $text)) $r.Err
    }
    $r = Run @('-HostId','windsurf','-Prompt','ok','-Cwd',$scratch)
    Check 'Windsurf executes the Devin file contract' ($r.Exit -eq 0 -and $r.Out -match 'routed: windsurf -> devin' -and $r.Out -match 'swe-2-medium') $r.Err
    $r = Run @('-HostId','qoder','-Prompt','--dash & echo %PATH%','-ShowCommand')
    Check 'show command uses safe pointer' ($r.Exit -eq 0 -and $r.Out -match 'prompt-show.txt' -and $r.Out -notmatch '%PATH%')
    $fleet.dispatchPolicy['devin'] = @{ enabled = $false; reason = 'synthetic auth block'; ownerAction = 'owner runs devin auth login' }; Save-Fixture
    $r = Run @('-HostId','windsurf','-Prompt','ok')
    Check 'alias enforces target policy and owner action' ($r.Exit -eq 3 -and $r.Err -match 'synthetic auth block' -and $r.Err -match 'devin auth login')
    $fleet.dispatchPolicy.Remove('devin'); $fleet.dispatchPolicy['windsurf'] = @{ enabled = $false; reason = 'alias disabled' }; Save-Fixture
    $r = Run @('-HostId','windsurf','-Prompt','ok'); Check 'alias own policy enforced' ($r.Exit -eq 3 -and $r.Err -match 'alias disabled')
    $fleet.dispatchPolicy.Remove('windsurf'); ($fleet.autonomyProfiles.profiles | Where-Object hostId -eq 'amp').defaultProfile = 'interactive'; Save-Fixture
    $r = Run @('-HostId','amp','-Prompt','ok'); Check 'table cannot bypass interactive profile' ($r.Exit -eq 3 -and $r.Err -match 'interactive')
    ($fleet.autonomyProfiles.profiles | Where-Object hostId -eq 'windsurf').defaultProfile = 'interactive'; Save-Fixture
    $r = Run @('-HostId','windsurf','-Prompt','ok'); Check 'alias cannot bypass its interactive profile' ($r.Exit -eq 3 -and $r.Err -match 'interactive')
    ($agents.activeAgents | Where-Object id -eq 'qoder').executable = Join-Path $fixture 'missing.exe'; Save-Fixture
    $r = Run @('-HostId','qoder','-Prompt','ok'); Check 'missing binary refuses' ($r.Exit -eq 3 -and $r.Err -match 'executable is absent')
    $env:CAD_FIXTURE_EXIT = '1'
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch); Check 'child exit code retained' ($r.Exit -eq 7)
    $env:CAD_FIXTURE_EXIT = $null; $env:CAD_FIXTURE_SLEEP = '1'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','1')
    Check 'timeout kills hidden process tree promptly' ($r.Exit -eq 4 -and $timer.Elapsed.TotalSeconds -lt 10 -and $r.Err -match 'process tree killed') $r.Err
    $env:CAD_FIXTURE_SLEEP = $null
    $left = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\coding-agent-dispatch') -Filter 'prompt-*.txt' -ErrorAction SilentlyContinue)
    Check 'temporary prompt files cleaned' ($left.Count -eq 0)
} finally {
    $env:AGENTHUB_ROOT = $oldRoot; $env:LOCALAPPDATA = $oldLocal; $env:CAD_FIXTURE_EXIT = $null; $env:CAD_FIXTURE_SLEEP = $null
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
