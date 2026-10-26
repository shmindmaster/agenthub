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
$oldApiKeyVars = @{}
foreach ($name in @('ANTHROPIC_API_KEY','ANTHROPIC_API_KEY_BACKUP','DEVIN_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','OPENAI_API_KEY','OPENCODE_GO_API_KEY','OPENCODE_API_KEY','WARP_API_KEY')) {
    $oldApiKeyVars[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, 'synthetic-dispatch-fixture', 'Process')
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cad fixture ' + [guid]::NewGuid().ToString('n'))
try {
    foreach ($dir in @('registry','scripts\lib','scratch','logs')) { $null = New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\lib\PathBinding.ps1') -Destination (Join-Path $fixture 'scripts\lib\PathBinding.ps1')
    $recorder = Join-Path $fixture 'record.cjs'
    @'
const fs = require('node:fs');
if (process.env.CAD_FIXTURE_SLEEP) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 8000);
const args = process.argv.slice(2);
const contents = [];
let ampSettings = null;
for (const arg of args) {
  const match = arg.match(/Read the task from this UTF-8 file and carry it out: (.+)$/);
  const file = match ? match[1] : arg;
  if ((match || /prompt-.*\.txt$/.test(arg)) && fs.existsSync(file)) contents.push(fs.readFileSync(file, 'utf8'));
}
const settingsIndex = args.indexOf('--settings-file');
if (settingsIndex >= 0 && fs.existsSync(args[settingsIndex + 1])) ampSettings = JSON.parse(fs.readFileSync(args[settingsIndex + 1], 'utf8'));
console.log(JSON.stringify({Arguments: args, Cwd: process.cwd(), Input: fs.readFileSync(0, 'utf8'), WarpMode: process.env.WARP_CLI_MODE, PromptContents: contents, AmpSettingsLoaded: ampSettings !== null, AmpMcpServerCount: Object.keys(ampSettings?.['amp.mcpServers'] ?? {}).length, ApiKeyVars: Object.fromEntries(['ANTHROPIC_API_KEY','ANTHROPIC_API_KEY_BACKUP','DEVIN_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','OPENAI_API_KEY','OPENCODE_GO_API_KEY','OPENCODE_API_KEY','WARP_API_KEY'].map(name => [name, Object.hasOwn(process.env, name)]))}));
if (process.env.CAD_FIXTURE_EXIT) process.exit(7);
'@ | Set-Content -LiteralPath $recorder -Encoding UTF8
    $node = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    if ($env:OS -eq 'Windows_NT') {
        $stub = Join-Path $fixture 'fake agent.cmd'
        [IO.File]::WriteAllText($stub, "@echo off`r`n`"$node`" `"$recorder`" %*`r`n")
    } else {
        # An executable script stands in for the agent CLI; the space in its
        # name keeps the argument-quoting coverage the .cmd stub has.
        $stub = Join-Path $fixture 'fake agent'
        [IO.File]::WriteAllText($stub, "#!/bin/sh`nexec '$node' '$recorder' `"`$@`"`n")
        [IO.File]::SetUnixFileMode($stub, [IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
    }
    $ids = @('claude','codex','cursor','cursor-agent','gemini','grok','opencode','antigravity','factory','cline','copilot','amp','devin','warp','windsurf','antigravity-desktop')
    $agents = @{ activeAgents = @($ids | ForEach-Object { @{ id = $_; executable = $stub; surfaceType = $(if ($_ -eq 'antigravity-desktop') { 'companion-desktop' } else { 'cli' }) } }) }
    $fleet = @{ hostSettings = @{ cline = @{ provider = 'openai-compatible'; model = 'qwen3.8-max' } }; autonomyProfiles = @{ profiles = @($ids | ForEach-Object { @{ hostId = $_; defaultProfile = 'repo-autonomous' } }) }; dispatchPolicy = @{ devin = @{ model = 'swe-2-medium-lightning' }; opencode = @{ model = 'opencode/glm-5.3-flash' } } }
    function Save-Fixture {
        $agents | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $fixture 'registry\agents.json') -Encoding UTF8
        $fleet | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $fixture 'registry\fleet-profile.json') -Encoding UTF8
    }
    Save-Fixture
    $env:AGENTHUB_ROOT = $fixture; $env:LOCALAPPDATA = Join-Path $fixture 'logs'
    $scratch = Join-Path $fixture 'scratch'
    # A child reports its cwd with symlinks resolved (macOS temp lives under /var -> /private/var).
    $scratchReal = (& $node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' $scratch)
    $r = Run @('-List')
    Check 'list succeeds' ($r.Exit -eq 0) $r.Err
    $fleet.dispatchPolicy['codex'] = @{ enabled = $false; reason = 'response capture is not verified'; ownerAction = 'run a bounded smoke after the output fix' }; Save-Fixture
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch)
    Check 'disabled Codex policy refuses a dispatch' ($r.Exit -eq 3 -and $r.Err -match 'response capture is not verified' -and $r.Err -match 'bounded smoke')
    $fleet.dispatchPolicy.Remove('codex'); Save-Fixture
    $r = Run @('-List')
    foreach ($id in @('claude','codex','amp','devin','warp')) { Check "$id headless contract" ($r.Out -match "(?m)^$id\tcallable\t") }
    foreach ($id in @('cursor','windsurf')) { Check "$id routes to CLI" ($r.Out -match "(?m)^$id\trouted\t") }
    foreach ($id in @('antigravity-desktop')) { Check "$id refuses" ($r.Out -match "(?m)^$id\trefused\t") }
    $r = Run @('-HostId','unknown','-Prompt','ok'); Check 'unknown host refuses' ($r.Exit -eq 3 -and $r.Err -match 'unknown host')
    foreach ($id in @('devin-cloud','jules','cursor-cloud','copilot-agent')) {
        $r = Run @('-HostId',$id,'-Prompt','ok'); Check "$id cloud refuses" ($r.Exit -eq 3 -and $r.Err -match 'hosted cloud execution')
    }
    foreach ($id in @('claude','codex','cursor-agent','gemini','grok','opencode','antigravity','factory','cline','copilot','amp','devin','warp')) {
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
        if ($id -eq 'copilot' -and $r.Exit -eq 3 -and $r.Err -match 'gh has no token for account sh-pendoah') {
            # Copilot dispatch reads the owner's sh-pendoah gh login; without it the
            # dispatcher must refuse before launching anything.
            Check 'copilot refuses without the owner gh account' $true
            continue
        }
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        Check "$id launches synthetic child" ($r.Exit -eq 0 -and $null -ne $d) $r.Err
        if ($id -eq 'codex') {
            Check 'codex accepts non-repo cwd via explicit skip flag' ($d.Arguments -contains '--skip-git-repo-check' -and $d.Arguments -contains '-' -and $d.Input -eq 'ok')
            Check 'codex did not initialize git' (-not (Test-Path (Join-Path $scratch '.git')))
        }
        if ($id -eq 'antigravity') { Check 'agy attaches print value after permissions' ($d.Arguments -contains '--print=ok' -and $d.Arguments[0] -eq '--dangerously-skip-permissions') }
        if ($id -eq 'factory') {
            $factoryOrder = @('--cwd', $scratch, 'exec', '--auto', 'high', '-f')
            $factoryArgsMatch = $d.Arguments.Count -eq 7
            for ($i = 0; $i -lt $factoryOrder.Count; $i++) {
                if ($d.Arguments[$i] -ne $factoryOrder[$i]) { $factoryArgsMatch = $false }
            }
            Check 'Factory places global auto mode after exec' ($factoryArgsMatch -and $d.PromptContents -contains 'ok')
        }
        if ($id -eq 'gemini') {
            $promptIndex = [Array]::IndexOf($d.Arguments, '--prompt')
            $approvalIndex = [Array]::IndexOf($d.Arguments, '--approval-mode')
            Check 'Gemini uses headless prompt with yolo approval mode' ($promptIndex -ge 0 -and $d.Arguments[$promptIndex + 1] -eq 'ok' -and $approvalIndex -ge 0 -and $d.Arguments[$approvalIndex + 1] -eq 'yolo' -and $d.Arguments -notcontains '--yolo')
        }
        if ($id -eq 'cursor-agent') {
            Check 'Cursor uses print text mode, read-only Q&A and trusted workspace' ($d.Arguments -contains '--print' -and $d.Arguments -contains '--output-format' -and $d.Arguments -contains 'text' -and $d.Arguments -contains '--mode' -and $d.Arguments -contains 'ask' -and $d.Arguments -contains '--trust' -and $d.Arguments -contains '--workspace' -and $d.Arguments -contains $scratch)
        }
        if ($id -eq 'warp') { Check 'warp receives CLI environment' ($d.WarpMode -eq '1' -and $d.Arguments[0] -eq 'agent' -and $d.Arguments[1] -eq 'run') }
        if ($id -eq 'devin') { Check 'Devin receives prompt file and paid model' ($d.PromptContents -contains 'ok' -and $d.Arguments -contains '--prompt-file' -and $d.Arguments -contains 'swe-2-medium-lightning') }
        if ($id -eq 'devin') { Check 'Devin uses account auth without its API key' (-not $d.ApiKeyVars.DEVIN_API_KEY) }
        if ($id -eq 'claude') { Check 'Claude uses account auth without its API key' (-not $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.ANTHROPIC_API_KEY_BACKUP -and $d.Arguments -notcontains '--model') }
        if ($id -eq 'codex') { Check 'Codex uses account auth without its API key' (-not $d.ApiKeyVars.OPENAI_API_KEY) }
        if ($id -eq 'cline') {
            Check 'Cline excludes unrelated provider key overrides' (-not $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.OPENAI_API_KEY)
            Check 'Cline keeps its full toolset and explicit provider' ($d.Arguments -contains '--json' -and $d.Arguments -notcontains '--yolo' -and $d.Arguments -contains 'openai-compatible' -and $d.Arguments -contains 'qwen3.8-max')
            $timeoutIndex = [Array]::IndexOf($d.Arguments, '--timeout')
            Check 'Cline receives bounded cwd and reasoning' ($d.Arguments -contains $scratch -and $d.Arguments -contains 'low' -and $timeoutIndex -ge 0 -and $d.Arguments[$timeoutIndex + 1] -eq '5')
        }
        if ($id -eq 'gemini') { Check 'Gemini uses OAuth without API-key variables' (-not $d.ApiKeyVars.GOOGLE_API_KEY -and -not $d.ApiKeyVars.GEMINI_API_KEY) }
        if ($id -eq 'opencode') {
            $formatIndex = [Array]::IndexOf($d.Arguments, '--format')
            Check 'OpenCode uses native JSON events while keeping unattended run and prompt' ($d.Arguments[0] -eq 'run' -and $d.Arguments -contains '--auto' -and $formatIndex -ge 0 -and $d.Arguments[$formatIndex + 1] -eq 'json' -and $d.Arguments[-1] -eq 'ok')
            Check 'OpenCode receives paid plan model' ($d.Arguments -contains '--model' -and $d.Arguments -contains 'opencode/glm-5.3-flash')
            Check 'OpenCode Go account uses no API key override' (-not $d.ApiKeyVars.OPENCODE_GO_API_KEY -and -not $d.ApiKeyVars.OPENCODE_API_KEY)
            Check 'OpenCode 2 uses native process cwd without obsolete flag' ($d.Cwd -in @($scratch, $scratchReal) -and $d.Arguments -notcontains '--dir')
        }
        if ($id -eq 'warp') { Check 'Warp account auth uses no API key override' (-not $d.ApiKeyVars.WARP_API_KEY) }
        if ($id -eq 'amp') {
            $settingsIndex = [Array]::IndexOf($d.Arguments, '--settings-file')
            $settingsPath = if ($settingsIndex -ge 0) { $d.Arguments[$settingsIndex + 1] } else { $null }
            Check 'Amp receives unattended stdin with MCP servers disabled' ($d.Input -eq 'ok' -and $d.Arguments -contains '-x' -and $d.Arguments -contains '--no-notifications' -and $d.Arguments -contains '--no-ide' -and $d.AmpSettingsLoaded -and $d.AmpMcpServerCount -eq 0)
            Check 'Amp dispatch-only settings file is removed' ($settingsPath -and -not (Test-Path -LiteralPath $settingsPath))
        }
    }
    $text = "quoted `"text`" café`n& echo %PATH% !name! " + ('x' * 9000)
    $taskFile = Join-Path $fixture 'task.txt'; [IO.File]::WriteAllText($taskFile, $text)
    foreach ($id in @('gemini','antigravity')) {
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
    $fleet.dispatchPolicy['claude'] = @{ enabled = $false; reason = 'weekly account limit' }; Save-Fixture
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch)
    Check 'disabled Claude still refuses without the per-call opt-in' ($r.Exit -eq 3 -and $r.Err -match 'weekly account limit')
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-AnthropicApiKey')
    Check 'Claude API-key opt-in refuses without a recorded authorization' ($r.Exit -eq 3 -and $r.Err -match 'apiKeyOptIn is not recorded')
    $fleet.dispatchPolicy.claude['apiKeyOptIn'] = @{ model = 'claude-sonnet-5-5'; expiresUtc = '2020-01-01T00:00:00Z' }; Save-Fixture
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-AnthropicApiKey')
    Check 'expired Claude API-key opt-in refuses' ($r.Exit -eq 3 -and $r.Err -match 'expired')
    $fleet.dispatchPolicy.claude.apiKeyOptIn.expiresUtc = '2999-01-01T00:00:00Z'; Save-Fixture
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-AnthropicApiKey')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Claude API-key opt-in keeps only the primary key and passes the recorded model' ($null -ne $d -and $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.ANTHROPIC_API_KEY_BACKUP -and $d.Arguments -contains '--model' -and $d.Arguments -contains 'claude-sonnet-5-5') $r.Err
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-AnthropicApiKey','-Model','claude-haiku-5-5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Claude API-key opt-in honours an explicit model' ($null -ne $d -and $d.Arguments -contains 'claude-haiku-5-5' -and $d.Arguments -notcontains 'claude-sonnet-5-5') $r.Err
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch)
    Check 'recorded opt-in is not applied without the switch' ($r.Exit -eq 3 -and $r.Err -match 'weekly account limit')
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-AnthropicApiKey')
    Check 'Anthropic API-key opt-in is refused for other hosts' ($r.Exit -eq 3 -and $r.Err -match 'applies only to -HostId claude')
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-Model','x')
    Check 'model override requires the API-key opt-in' ($r.Exit -eq 3 -and $r.Err -match '-Model applies only')
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-Model','opencode/kimi-k3')
    Check 'OpenCode refuses a model outside the allowlist' ($r.Exit -eq 3 -and $r.Err -match 'not in dispatchPolicy.opencode.allowedModels')
    $fleet.dispatchPolicy.opencode['allowedModels'] = @('opencode/glm-5.3-flash', 'opencode/glm-5.3'); $fleet.dispatchPolicy.opencode['agent'] = 'peer'; Save-Fixture
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-Model','opencode/glm-5.3','-Title','T1 task','-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    $titleIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--title') } else { -1 }
    Check 'OpenCode routes an allowed model and session title per task' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'opencode/glm-5.3' -and $titleIndex -ge 0 -and $d.Arguments[$titleIndex + 1] -eq 'T1 task' -and $d.Arguments[-1] -eq 'ok') $r.Err
    $agentIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--agent') } else { -1 }
    Check 'OpenCode unattended runs use the policy-named agent' ($agentIndex -ge 0 -and $d.Arguments[$agentIndex + 1] -eq 'peer') $r.Err
    $fleet.dispatchPolicy.opencode.Remove('allowedModels'); $fleet.dispatchPolicy.opencode.Remove('agent'); Save-Fixture
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-Title','x')
    Check 'session title is refused for other hosts' ($r.Exit -eq 3 -and $r.Err -match '-Title applies only')
    $r = Run @('-List')
    Check 'list keeps disabled Claude refused despite the opt-in record' ($r.Out -match "(?m)^claude\trefused\t")
    $fleet.dispatchPolicy.Remove('claude'); Save-Fixture
    $r = Run @('-HostId','windsurf','-Prompt','ok','-Cwd',$scratch)
    Check 'Windsurf executes the Devin file contract' ($r.Exit -eq 0 -and $r.Out -match 'routed: windsurf -> devin' -and $r.Out -match 'swe-2-medium-lightning') $r.Err
    $r = Run @('-HostId','gemini','-Prompt','--dash & echo %PATH%','-ShowCommand')
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
    ($agents.activeAgents | Where-Object id -eq 'gemini').executable = Join-Path $fixture 'missing-agent-binary'; Save-Fixture
    $r = Run @('-HostId','gemini','-Prompt','ok'); Check 'missing binary refuses' ($r.Exit -eq 3 -and $r.Err -match 'executable is absent')
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
    foreach ($name in $oldApiKeyVars.Keys) { [Environment]::SetEnvironmentVariable($name, $oldApiKeyVars[$name], 'Process') }
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetFullPath(([IO.Path]::GetTempPath())).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
