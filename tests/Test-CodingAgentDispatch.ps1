#Requires -Version 5.1
<# Synthetic executables only. No installed agent, login, API or paid run.
   -DispatcherPath supports a regression run against an older dispatcher. #>
[CmdletBinding()]
param([string]$DispatcherPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $DispatcherPath) { $DispatcherPath = Join-Path $repoRoot 'packages\coding-agent-dispatch\skills\dispatch\Invoke-CodingAgent.ps1' }
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
function PassNote([string]$HostName, [string]$ModelId) {
    return ('note: {0} model ''{1}'' is not in the smoke-verified list; passing it through' -f [regex]::Escape($HostName), [regex]::Escape($ModelId))
}
$oldRoot = $env:AGENTHUB_ROOT; $oldLocal = $env:LOCALAPPDATA
$oldWindowsHome = $env:USERPROFILE; $oldPosixHome = $env:HOME
$oldApiKeyVars = @{}
foreach ($name in @('ANTHROPIC_API_KEY','ANTHROPIC_API_KEY_BACKUP','ANTHROPIC_BASE_URL','DEVIN_API_KEY','DEVIN_CLOUD_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','GOOGLE_GENERATIVE_AI_API_KEY','DASHSCOPE_API_KEY','MODELSCOPE_API_KEY','QWEN_API_KEY','OPENAI_API_KEY','OPENAI_BASE_URL','OPENAI_MODEL','OPENCODE_GO_API_KEY','OPENCODE_API_KEY','WARP_API_KEY','MIMO_API_KEY','GH_TOKEN','GITHUB_TOKEN')) {
    $oldApiKeyVars[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, 'synthetic-dispatch-fixture', 'Process')
}
# MiMo routes run only on the Xiaomi Token Plan: a tp-/ttp- key and a
# token-plan-<region> host. Fake values, set for this process only.
$oldMimoBaseUrl = [Environment]::GetEnvironmentVariable('MIMO_BASE_URL', 'Process')
$env:MIMO_API_KEY = 'tp-synthetic-dispatch-fixture'
$env:MIMO_BASE_URL = 'https://token-plan-sgp.xiaomimimo.com/v1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cad fixture ' + [guid]::NewGuid().ToString('n'))
try {
    $forgeWorktree = '/srv/work/agenthub-runner/worktrees/SH-4409'
    $r = Run @('-Forge','-HostId','opencode','-Cwd',$forgeWorktree,'-ShowCommand')
    Check 'Forge preview uses fixed SSH target and unprivileged identity' ($r.Exit -eq 0 -and $r.Out -match 'forge runuser -u agenthub-runner -- env -i' -and $r.Out -match '/\.local/bin/opencode') $r.Err
    $r = Run @('-Forge','-HostId','opencode','-Cwd',"$forgeWorktree/../outside",'-ShowCommand')
    Check 'Forge refuses paths outside the worktree root' ($r.Exit -eq 3 -and $r.Err -match 'Forge worktree path')
    $r = Run @('-Forge','-HostId','opencode','-Cwd',"$forgeWorktree`n",'-ShowCommand')
    Check 'Forge refuses shell control characters in the worktree path' ($r.Exit -eq 3)
    $r = Run @('-Forge','-HostId','opencode','-Cwd',$forgeWorktree,'-Prompt','ok')
    Check 'Forge refuses unattended prompts' ($r.Exit -eq 3 -and $r.Err -match 'interactive sessions only')
    $r = Run @('-Forge','-HostId','grok-browser','-Cwd',$forgeWorktree,'-ShowCommand')
    Check 'Forge browser route uses the isolated browser launcher' ($r.Exit -eq 0 -and $r.Out -match '/\.local/bin/grok-browser')
    $r = Run @('-Forge','-HostId','opencode-zai','-Cwd',$forgeWorktree,'-ShowCommand')
    Check 'Forge Z.ai uses the isolated launcher' ($r.Exit -eq 0 -and $r.Out -match '/\.local/bin/opencode-zai\b')
    $r = Run @('-Forge','-HostId','opencode-go','-Cwd',$forgeWorktree,'-ShowCommand')
    Check 'Forge OpenCode Go uses the subscription launcher' ($r.Exit -eq 0 -and $r.Out -match '/\.local/bin/opencode-go\b')
    foreach ($client in @('claude', 'codex')) {
        foreach ($plan in @('qwen', 'zai', 'mimo', 'go')) {
            $route = "$client-$plan"
            $r = Run @('-Forge','-HostId',$route,'-Cwd',$forgeWorktree,'-ShowCommand')
            Check "Forge $route selects an explicit provider launcher" ($r.Exit -eq 0 -and $r.Out -match "/\.local/bin/$route\b") $r.Err
            $r = Run @('-Forge','-Auth','-HostId',$route)
            Check "Forge $route identifies its runtime credential" ($r.Exit -eq 0 -and $r.Out -match 'runtime credential' -and $r.Out -notmatch 'device-auth') $r.Err
        }
        $r = Run @('-Forge','-HostId',$client,'-Cwd',$forgeWorktree,'-ShowCommand')
        Check "Forge refuses an unqualified $client route" ($r.Exit -eq 3 -and $r.Err -match 'Select a Forge provider explicitly') $r.Err
    }
    $r = Run @('-Forge','-Auth','-HostId','grok')
    Check 'Forge auth shows the browser device login command' ($r.Exit -eq 0 -and $r.Out -match 'grok login --device-auth' -and $r.Out -notmatch 'codex login')
    $r = Run @('-Auth','-HostId','codex')
    Check 'Local auth shows a status command' ($r.Exit -eq 0 -and $r.Out -match 'codex login status')
    $r = Run @('-Auth','-Prompt','ok')
    Check 'Auth guidance refuses a coding prompt' ($r.Exit -eq 3)
    foreach ($dir in @('registry','scripts\lib','scratch','logs')) { $null = New-Item -ItemType Directory -Path (Join-Path $fixture $dir) -Force }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\lib\PathBinding.ps1') -Destination (Join-Path $fixture 'scripts\lib\PathBinding.ps1')
    $fixtureFactorySettings = Join-Path $fixture 'packages\coding-agent-dispatch\skills\dispatch\factory'
    $null = New-Item -ItemType Directory -Path $fixtureFactorySettings -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'packages\coding-agent-dispatch\skills\dispatch\factory\runtime-settings.json') -Destination $fixtureFactorySettings
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
console.log(JSON.stringify({Arguments: args, Cwd: process.cwd(), Input: fs.readFileSync(0, 'utf8'), WarpMode: process.env.WARP_CLI_MODE, PeerGuard: process.env.AGENTHUB_PEER_GUARD ?? null, ClineBackend: process.env.CLINE_SESSION_BACKEND_MODE ?? null, PromptContents: contents, AmpSettingsLoaded: ampSettings !== null, AmpMcpServerCount: Object.keys(ampSettings?.['amp.mcpServers'] ?? {}).length, WarpGuard: {gitCount: process.env.GIT_CONFIG_COUNT ?? null, pushRewrite: process.env.GIT_CONFIG_KEY_0 ?? null, ghConfigDir: process.env.GH_CONFIG_DIR ?? null, ghToken: Object.hasOwn(process.env, 'GH_TOKEN') || Object.hasOwn(process.env, 'GITHUB_TOKEN')}, ApiKeyVars: Object.fromEntries(['ANTHROPIC_API_KEY','ANTHROPIC_API_KEY_BACKUP','ANTHROPIC_BASE_URL','DEVIN_API_KEY','DEVIN_CLOUD_API_KEY','GOOGLE_API_KEY','GEMINI_API_KEY','GOOGLE_GENERATIVE_AI_API_KEY','DASHSCOPE_API_KEY','MODELSCOPE_API_KEY','QWEN_API_KEY','OPENAI_API_KEY','OPENAI_BASE_URL','OPENAI_MODEL','OPENCODE_GO_API_KEY','OPENCODE_API_KEY','WARP_API_KEY','MIMO_API_KEY','GH_TOKEN','GITHUB_TOKEN'].map(name => [name, Object.hasOwn(process.env, name)])), QwenRoute: { openAiKeyPresent: Object.hasOwn(process.env, 'OPENAI_API_KEY'), openAiKeyIsMimo: process.env.OPENAI_API_KEY !== undefined && process.env.OPENAI_API_KEY === process.env.MIMO_API_KEY, openAiBaseUrl: process.env.OPENAI_BASE_URL ?? null, openAiModel: process.env.OPENAI_MODEL ?? null, ghTokenPresent: Object.hasOwn(process.env, 'GH_TOKEN') || Object.hasOwn(process.env, 'GITHUB_TOKEN'), gitPushRewrite: process.env.GIT_CONFIG_KEY_0 ?? null, ghConfigDir: process.env.GH_CONFIG_DIR ?? null }}));
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
    $ids = @('claude','codex','cursor','cursor-agent','grok','opencode','antigravity','factory','cline','copilot','amp','devin','windsurf','antigravity-desktop','kilo','mimo-code','qwen')
    $agents = @{ activeAgents = @($ids | ForEach-Object { @{ id = $_; executable = $stub; surfaceType = $(if ($_ -eq 'antigravity-desktop') { 'companion-desktop' } else { 'cli' }) } }) }
    $fleet = @{ launchDefaults = @{ devin = @('--permission-mode', 'dangerous', '--respect-workspace-trust', 'false') }; hostSettings = @{ cline = @{ provider = 'openai-compatible'; model = 'qwen3.8-max-0902' } }; autonomyProfiles = @{ profiles = @($ids | ForEach-Object { @{ hostId = $_; defaultProfile = 'repo-autonomous' } }) }; dispatchPolicy = @{ devin = @{ model = 'swe-2-medium'; allowedModels = @('swe-2-medium', 'swe-2-high', 'adaptive') }; opencode = @{ model = 'opencode-go/glm-5.3-flash' }; kilo = @{ enabled = $true; agent = 'peer'; model = 'mimo/mimo-v2.6-pro'; allowedModels = @('mimo/mimo-v2.6-pro', 'mimo/mimo-v2.5', 'mimo/x&echo') }; 'mimo-code' = @{ enabled = $true; agent = 'peer'; model = 'xiaomi-token-plan-sgp/mimo-v2.6-pro'; allowedModels = @('xiaomi-token-plan-sgp/mimo-v2.6-pro') }; qwen = @{ enabled = $true; model = 'mimo-v2.6-pro'; allowedModels = @('mimo-v2.6-pro') }; factory = @{ model = 'gpt-6-luna'; allowedModels = @('gpt-6-luna', 'glm-5.3-flash', 'gpt-6-sol'); autonomy = 'medium'; runtimeSettings = 'packages/coding-agent-dispatch/skills/dispatch/factory/runtime-settings.json' } } }
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
    foreach ($id in @('claude','codex','amp','devin','qwen')) { Check "$id headless contract" ($r.Out -match "(?m)^$id\tcallable\t") }
    foreach ($id in @('cursor','windsurf')) { Check "$id routes to CLI" ($r.Out -match "(?m)^$id\trouted\t") }
    foreach ($id in @('antigravity-desktop')) { Check "$id refuses" ($r.Out -match "(?m)^$id\trefused\t") }
    $r = Run @('-HostId','unknown','-Prompt','ok'); Check 'unknown host refuses' ($r.Exit -eq 3 -and $r.Err -match 'unknown host')
    foreach ($id in @('jules','cursor-cloud','copilot-agent')) {
        $r = Run @('-HostId',$id,'-Prompt','ok'); Check "$id cloud refuses" ($r.Exit -eq 3 -and $r.Err -match 'hosted cloud execution')
    }
    # SH-4969: devin-cloud runs only under an explicitly enabled policy; no record refuses.
    $r = Run @('-HostId','devin-cloud','-Prompt','ok')
    Check 'devin-cloud refuses without an enabled dispatchPolicy record' ($r.Exit -eq 3 -and $r.Err -match 'devin-cloud' -and $r.Err -match 'not enabled') $r.Err
    $r = Run @('-List')
    Check 'list reports devin-cloud refused without its policy' ($r.Out -match "(?m)^devin-cloud\trefused\t") $r.Out
    foreach ($id in @('claude','codex','cursor-agent','grok','opencode','antigravity','factory','cline','copilot','amp','devin','kilo','mimo-code','qwen')) {
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
        if ($id -eq 'copilot' -and $r.Exit -eq 3 -and $r.Err -match 'gh has no token for account sh-pendoah') {
            # Copilot dispatch reads the owner's sh-pendoah gh login; without it the
            # dispatcher must refuse before launching anything.
            Check 'copilot refuses without the owner gh account' $true
            continue
        }
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        Check "$id launches synthetic child" ($r.Exit -eq 0 -and $null -ne $d) $r.Err
        # SH-4969 fix round: the Devin Cloud key reaches no child the dispatcher starts.
        Check "$id child does not inherit DEVIN_CLOUD_API_KEY" ($null -ne $d -and $d.ApiKeyVars.DEVIN_CLOUD_API_KEY -eq $false) $r.Err
        if ($id -eq 'codex') {
            Check 'codex accepts non-repo cwd via explicit skip flag' ($d.Arguments -contains '--skip-git-repo-check' -and $d.Arguments -contains '-' -and $d.Input -eq 'ok')
            Check 'codex did not initialize git' (-not (Test-Path (Join-Path $scratch '.git')))
        }
        if ($id -eq 'antigravity') { Check 'agy attaches print value after permissions' ($d.Arguments -contains '--print=ok' -and $d.Arguments[0] -eq '--dangerously-skip-permissions') }
        if ($id -eq 'factory') {
            $settingsIndex = [Array]::IndexOf($d.Arguments, '--settings')
            $factoryOrder = @('exec', '--cwd', $scratch, '--auto', 'medium', '-o', 'json', '--settings')
            $factoryArgsMatch = $d.Arguments.Count -eq 13
            for ($i = 0; $i -lt $factoryOrder.Count; $i++) {
                if ($d.Arguments[$i] -ne $factoryOrder[$i]) { $factoryArgsMatch = $false }
            }
            Check 'Factory runs exec with medium autonomy, JSON output and rule settings' ($factoryArgsMatch -and $settingsIndex -ge 0 -and $d.Arguments[$settingsIndex + 1] -like '*runtime-settings.json' -and $d.Arguments -contains '-m' -and $d.Arguments -contains 'gpt-6-luna' -and $d.Arguments[-2] -eq '-f' -and $d.PromptContents -contains 'ok')
            Check 'Factory never requests unsafe permissions' ($d.Arguments -notcontains 'high' -and $d.Arguments -notcontains '--skip-permissions-unsafe')
        }
        if ($id -eq 'cursor-agent') {
            Check 'Cursor uses print text mode, read-only Q&A and trusted workspace' ($d.Arguments -contains '--print' -and $d.Arguments -contains '--output-format' -and $d.Arguments -contains 'text' -and $d.Arguments -contains '--mode' -and $d.Arguments -contains 'ask' -and $d.Arguments -contains '--trust' -and $d.Arguments -contains '--workspace' -and $d.Arguments -contains $scratch)
        }
        if ($id -eq 'devin') { Check 'Devin receives prompt file and policy model' ($d.PromptContents -contains 'ok' -and $d.Arguments -contains '--prompt-file' -and $d.Arguments -contains 'swe-2-medium') }
        if ($id -eq 'devin') { Check 'Devin uses account auth without its API key' (-not $d.ApiKeyVars.DEVIN_API_KEY) }
        if ($id -eq 'claude') { Check 'Claude uses account auth without its API key' (-not $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.ANTHROPIC_API_KEY_BACKUP -and $d.Arguments -notcontains '--model') }
        if ($id -eq 'codex') { Check 'Codex uses account auth without its API key' (-not $d.ApiKeyVars.OPENAI_API_KEY) }
        if ($id -eq 'cline') {
            Check 'Cline excludes unrelated provider key overrides' (-not $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.OPENAI_API_KEY)
            Check 'Cline keeps its full toolset and explicit provider' ($d.Arguments -contains '--json' -and $d.Arguments -notcontains '--yolo' -and $d.Arguments -contains 'openai-compatible' -and $d.Arguments -contains 'qwen3.8-max-0902')
            $timeoutIndex = [Array]::IndexOf($d.Arguments, '--timeout')
            Check 'Cline receives bounded cwd and reasoning' ($d.Arguments -contains $scratch -and $d.Arguments -contains 'low' -and $timeoutIndex -ge 0 -and $d.Arguments[$timeoutIndex + 1] -eq '5')
            Check 'Cline runs the peer guard in-process' ($d.PeerGuard -eq '1' -and $d.ClineBackend -eq 'local' -and $d.Arguments -contains '--compaction')
        }
        if ($id -eq 'opencode') {
            $formatIndex = [Array]::IndexOf($d.Arguments, '--format')
            Check 'OpenCode uses native JSON events while keeping unattended run and prompt' ($d.Arguments[0] -eq 'run' -and $d.Arguments -contains '--auto' -and $formatIndex -ge 0 -and $d.Arguments[$formatIndex + 1] -eq 'json' -and $d.Arguments[-1] -eq 'ok')
            Check 'OpenCode receives the Go subscription model' ($d.Arguments -contains '--model' -and $d.Arguments -contains 'opencode-go/glm-5.3-flash')
            Check 'OpenCode Go account uses no API key override' (-not $d.ApiKeyVars.OPENCODE_GO_API_KEY -and -not $d.ApiKeyVars.OPENCODE_API_KEY)
            Check 'OpenCode 2 uses native process cwd without obsolete flag' ($d.Cwd -in @($scratch, $scratchReal) -and $d.Arguments -notcontains '--dir')
        }
        if ($id -eq 'kilo') {
            Check 'Kilo runs with auto approval, JSON events and explicit dir' ($d.Arguments[0] -eq 'run' -and $d.Arguments -contains '--auto' -and $d.Arguments -contains '--format' -and $d.Arguments -contains '--dir' -and $d.Arguments -contains $scratch -and $d.Arguments[-1] -eq 'ok')
            Check 'Kilo receives the full provider/model policy id' ($d.Arguments -contains '--model' -and $d.Arguments -contains 'mimo/mimo-v2.6-pro')
            Check 'Kilo keeps its separately authorized plan key' ($d.ApiKeyVars.MIMO_API_KEY)
            $agentIndex = [Array]::IndexOf($d.Arguments, '--agent')
            Check 'Kilo runs unattended only under the policy-named guarded agent' ($agentIndex -ge 0 -and $d.Arguments[$agentIndex + 1] -eq 'peer')
        }
        if ($id -eq 'mimo-code') {
            Check 'MiMo runs with yolo approval, JSON events and explicit dir' ($d.Arguments[0] -eq 'run' -and $d.Arguments -contains '--yolo' -and $d.Arguments -contains '--format' -and $d.Arguments -contains '--dir' -and $d.Arguments -contains $scratch -and $d.Arguments[-1] -eq 'ok')
            Check 'MiMo receives the full provider/model policy id' ($d.Arguments -contains '--model' -and $d.Arguments -contains 'xiaomi-token-plan-sgp/mimo-v2.6-pro')
            Check 'MiMo runs on its stored plan credential without the env key' (-not $d.ApiKeyVars.MIMO_API_KEY)
            $agentIndex = [Array]::IndexOf($d.Arguments, '--agent')
            Check 'MiMo runs unattended only under the policy-named guarded agent' ($agentIndex -ge 0 -and $d.Arguments[$agentIndex + 1] -eq 'peer')
        }
        if ($id -eq 'qwen') {
            Check 'Qwen runs the one-shot openai-auth command on the plan model' ($d.Arguments -contains '--auth-type' -and $d.Arguments -contains 'openai' -and $d.Arguments -contains '-m' -and $d.Arguments -contains 'mimo-v2.6-pro' -and $d.Arguments -contains '--approval-mode' -and $d.Arguments -contains 'yolo' -and $d.Arguments -contains '-o' -and $d.Arguments -contains 'json' -and $d.Arguments[-1] -eq 'json' -and $d.Arguments -notcontains 'ok' -and $d.Cwd -in @($scratch, $scratchReal))
            Check 'Qwen child carries the Token Plan as OPENAI_* names mapped from MIMO_*' ($d.QwenRoute.openAiKeyPresent -and $d.QwenRoute.openAiKeyIsMimo -and $d.QwenRoute.openAiBaseUrl -eq 'https://token-plan-sgp.xiaomimimo.com/v1' -and $d.QwenRoute.openAiModel -eq 'mimo-v2.6-pro')
            Check 'Qwen child cannot push or call gh under the peer guard env' ($d.QwenRoute.gitPushRewrite -match 'pushInsteadOf$' -and $d.QwenRoute.ghConfigDir -match 'qwen-peer-gh$' -and -not $d.QwenRoute.ghTokenPresent)
            Check 'Qwen child drops other provider keys that could retarget billing' (-not $d.ApiKeyVars.DASHSCOPE_API_KEY -and -not $d.ApiKeyVars.GEMINI_API_KEY -and -not $d.ApiKeyVars.GOOGLE_API_KEY -and -not $d.ApiKeyVars.GOOGLE_GENERATIVE_AI_API_KEY -and -not $d.ApiKeyVars.ANTHROPIC_API_KEY -and -not $d.ApiKeyVars.ANTHROPIC_BASE_URL -and -not $d.ApiKeyVars.QWEN_API_KEY -and -not $d.ApiKeyVars.MODELSCOPE_API_KEY)
        }
        if ($id -eq 'amp') {
            $settingsIndex = [Array]::IndexOf($d.Arguments, '--settings-file')
            $settingsPath = if ($settingsIndex -ge 0) { $d.Arguments[$settingsIndex + 1] } else { $null }
            Check 'Amp receives unattended stdin with MCP servers disabled' ($d.Input -eq 'ok' -and $d.Arguments -contains '-x' -and $d.Arguments -contains '--no-notifications' -and $d.Arguments -contains '--no-ide' -and $d.AmpSettingsLoaded -and $d.AmpMcpServerCount -eq 0)
            Check 'Amp dispatch-only settings file is removed' ($settingsPath -and -not (Test-Path -LiteralPath $settingsPath))
        }
    }
    # Owner direction 2026-11-10: allowedModels records smoke-verified models and
    # does not limit -Model. An unlisted model is passed through with one stderr
    # note; only a malformed id is refused. Kilo and MiMo still take
    # provider/model ids only, for the recorded default and an explicit -Model.
    foreach ($guarded in @('kilo', 'mimo-code')) {
        $fleet.dispatchPolicy.$guarded.Remove('agent'); Save-Fixture
        $r = Run @('-HostId',$guarded,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
        Check "$guarded refuses an unattended run when policy names no guarded agent" ($r.Exit -eq 3 -and $r.Err -match 'guarded agent') $r.Err
        $fleet.dispatchPolicy.$guarded.agent = 'peer;echo'; Save-Fixture
        $r = Run @('-HostId',$guarded,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
        Check "$guarded refuses a shell-unsafe agent name" ($r.Exit -eq 3 -and $r.Err -match 'guarded agent') $r.Err
        $fleet.dispatchPolicy.$guarded.agent = 'peer'; Save-Fixture
    }
    # ---------- SH-4418: roles and the enforced read-only mode ----------
    # -ShowCommand prints the command and starts nothing.
    function ShowArgs($Result) { return [string](@(($Result.Out -split '\r?\n') -match '^args=')[0]) }
    function Arg([string]$Value) { if ($Value -match '[\s"]') { return (Quote $Value) } return $Value }
    # OpenCode V2 role agents (SH-4674): the dispatcher reads the installed
    # profile under the invoking user's home, pointed at the fixture here.
    $openCodeAgentsDir = Join-Path (Join-Path (Join-Path $fixture '.config') 'opencode') 'agents'
    $null = New-Item -ItemType Directory -Path $openCodeAgentsDir -Force
    foreach ($ocAgent in Get-ChildItem (Join-Path $repoRoot 'packages\coding-agent-dispatch\opencode\agents') -Filter *.md) {
        Copy-Item -LiteralPath $ocAgent.FullName -Destination $openCodeAgentsDir
    }
    if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE = $fixture } else { $env:HOME = $fixture }
    $fleet.dispatchPolicy.opencode['roles'] = @{ engineer = 'engineer'; reviewer = 'reviewer'; tester = 'tester'; researcher = 'researcher'; readonly = 'readonly' }
    # The real registry records the guarded peer agent; this block asserts the
    # same shape, and the cleanup below restores the keyless base fixture.
    $fleet.dispatchPolicy.opencode['agent'] = 'peer'
    $readOnlyFixture = @{
        claude  = @{ flags = @('--permission-mode', 'plan', '--permission-prompts', 'none'); omits = @('bypassPermissions') }
        codex   = @{ flags = @('--sandbox', 'read-only'); omits = @() }
        factory = @{ flags = @(); omits = @('--auto') }
        opencode = @{ flags = @('--agent', 'readonly'); omits = @('peer') }
        qwen    = @{ flags = @('--approval-mode', 'plan'); omits = @('yolo') }
    }
    $allDispatchHosts = @('claude','codex','cursor-agent','grok','opencode','antigravity','factory','cline','copilot','amp','devin','kilo','mimo-code','qwen')
    $createdPolicy = @()
    foreach ($id in $allDispatchHosts) {
        if (-not $fleet.dispatchPolicy.ContainsKey($id)) { $fleet.dispatchPolicy[$id] = @{}; $createdPolicy += $id }
    }
    foreach ($id in $readOnlyFixture.Keys) { $fleet.dispatchPolicy[$id]['readOnly'] = $readOnlyFixture[$id] }
    $fleet.dispatchPolicy['amp']['readOnly'] = $false
    $fleet.dispatchPolicy['grok']['readOnly'] = $null
    Save-Fixture

    $r = Run @('-HostId','kiro','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
    Check 'kiro is retired and refused as an unknown host' ($r.Exit -eq 3 -and $r.Err -match 'unknown host' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','boss')
    Check 'OpenCode refuses an unknown role' ($r.Exit -eq 3 -and $r.Err -match 'is not a role' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','architect')
    Check 'a role that only Kiro had is no longer a role' ($r.Exit -eq 3 -and $r.Err -match 'is not a role' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    foreach ($id in @('codex', 'claude', 'cursor', 'qwen')) {
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','engineer')
        Check "$id refuses -Role engineer and names the hosts that support roles" ($r.Exit -eq 3 -and $r.Err -match 'roles are supported only on: opencode, factory' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    }
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','peer')
    Check 'the default role is accepted on a host without roles' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=exec --skip-git-repo-check -') ($r.Out + $r.Err)

    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'Claude -ReadOnly runs plan mode with prompts denied, never the bypass mode' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=--print --permission-mode plan --permission-prompts none' -and $r.Out -match '(?m)^stdin=yes') ($r.Out + $r.Err)
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
    Check 'Claude without -ReadOnly keeps the existing command' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=--print --permission-mode bypassPermissions') ($r.Out + $r.Err)
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'Codex -ReadOnly selects the read-only sandbox' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=exec --sandbox read-only --skip-git-repo-check -' -and $r.Out -match '(?m)^stdin=yes') ($r.Out + $r.Err)
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly','-Model','gpt-6.1-sol')
    Check 'Codex -ReadOnly keeps an explicit model' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=exec -m gpt-6.1-sol --sandbox read-only --skip-git-repo-check -') ($r.Out + $r.Err)
    $factorySettings = Join-Path (Resolve-Path -LiteralPath $fixture).Path 'packages/coding-agent-dispatch/skills/dispatch/factory/runtime-settings.json'
    $showPrompt = Join-Path (Join-Path $env:LOCALAPPDATA 'AgentHub\runtime\coding-agent-dispatch') 'prompt-show.txt'
    $scratchShown = (Resolve-Path -LiteralPath $scratch).Path
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    $factoryExpected = 'args=' + ((@('exec', '--cwd', $scratchShown, '-o', 'json', '--settings', $factorySettings, '-m', 'gpt-6-luna', '-f', $showPrompt) | ForEach-Object { Arg $_ }) -join ' ')
    Check 'Factory -ReadOnly leaves --auto out, which is its read-only default' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq $factoryExpected -and (ShowArgs $r) -notmatch '--auto') ((ShowArgs $r) + ' expected ' + $factoryExpected + $r.Err)
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
    $factoryWritable = 'args=' + ((@('exec', '--cwd', $scratchShown, '--auto', 'medium', '-o', 'json', '--settings', $factorySettings, '-m', 'gpt-6-luna', '-f', $showPrompt) | ForEach-Object { Arg $_ }) -join ' ')
    Check 'Factory without -ReadOnly keeps the existing command' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq $factoryWritable) ((ShowArgs $r) + $r.Err)

    # ---------- SH-4676: Factory roles run as native droids through one Task delegation ----------
    # Exec sessions block Task by default, so a role run carries an explicit
    # --only-tools union; the relay wrapper replaces the prompt file text.
    $factoryDroidsDir = Join-Path (Join-Path $fixture '.factory') 'droids'
    $null = New-Item -ItemType Directory -Path $factoryDroidsDir -Force
    foreach ($droidName in @('ah-engineer', 'ah-reviewer', 'ah-browser-tester')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot "packages\coding-agent-dispatch\factory\droids\$droidName.md") -Destination $factoryDroidsDir
    }
    $browserTesterDroid = [IO.File]::ReadAllText((Join-Path $factoryDroidsDir 'ah-browser-tester.md'))
    Check 'Factory browser tester allows the Skill tool required by its droid-control workflow' ($browserTesterDroid -match '(?m)^tools:.*\bSkill\b' -and $browserTesterDroid -match '(?m)^1\. Load the `droid-control` skill') $browserTesterDroid
    $fleet.dispatchPolicy.factory['roles'] = @{ engineer = 'ah-engineer'; reviewer = 'ah-reviewer'; tester = 'ah-browser-tester' }
    Save-Fixture
    $projectDroidsDir = Join-Path (Join-Path $scratch '.factory') 'droids'
    $null = New-Item -ItemType Directory -Path $projectDroidsDir -Force
    [IO.File]::WriteAllText((Join-Path $projectDroidsDir 'ah-reviewer.md'), "---`nname: shadow-reviewer`nmode: all`ntools: [Read, Edit]`n---`n", [Text.UTF8Encoding]::new($false))
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer','-ReadOnly')
    Check 'Factory refuses a project droid that could shadow the validated personal reviewer' ($r.Exit -eq 3 -and $r.Err -match 'project droid' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    Remove-Item -LiteralPath $projectDroidsDir -Recurse -Force
    $r = Run @('-HostId','factory','-Prompt','do the thing','-Cwd',$scratch,'-TimeoutSec','5','-Role','engineer')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $onlyToolsIndex = if ($null -ne $d) { [Array]::IndexOf($d.Arguments, '--only-tools') } else { -1 }
    $relayPrompt = if ($null -ne $d) { [string](@($d.PromptContents)[0]) } else { '' }
    Check 'Factory -Role engineer unlocks Task through an explicit --only-tools union' ($null -ne $d -and $onlyToolsIndex -ge 0 -and $d.Arguments[$onlyToolsIndex + 1] -cmatch '(^|,)Task(,|$)') $r.Err
    Check 'Factory -Role engineer relays exactly one Task delegation with the task verbatim' ($relayPrompt -match "subagent_type 'ah-engineer'" -and $relayPrompt -match 'exactly once' -and $relayPrompt -match 'Do not pass a complexity parameter' -and $relayPrompt -match '(?m)^TASK:\r?\ndo the thing$') $relayPrompt
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','engineer','-ReadOnly')
    Check 'Factory refuses -ReadOnly with -Role engineer, a writing role' ($r.Exit -eq 3 -and $r.Err -match 'writing role' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer','-ReadOnly')
    Check 'Factory -ReadOnly -Role reviewer omits --auto and delegates to the read-only droid' ($r.Exit -eq 0 -and (ShowArgs $r) -notmatch '--auto' -and (ShowArgs $r) -match '--only-tools') ((ShowArgs $r) + $r.Err)
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','researcher')
    Check 'Factory refuses a role its policy does not map' ($r.Exit -eq 3 -and $r.Err -match 'does not map role' -and $r.Err -match 'researcher' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $fleet.dispatchPolicy.factory.roles.Remove('tester'); Save-Fixture
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','tester')
    Check 'Factory refuses an unmapped role naming the mapped ones' ($r.Exit -eq 3 -and $r.Err -match 'does not map role' -and $r.Err -match 'engineer' -and $r.Err -match 'reviewer' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $fleet.dispatchPolicy.factory.roles['tester'] = 'ah-browser-tester'; Save-Fixture
    Remove-Item -LiteralPath (Join-Path $factoryDroidsDir 'ah-browser-tester.md') -Force
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','tester')
    Check 'Factory refuses a role whose droid file is missing' ($r.Exit -eq 3 -and $r.Err -match 'ah-browser-tester\.md' -and $r.Err -match 'missing' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    Copy-Item -LiteralPath (Join-Path $repoRoot 'packages\coding-agent-dispatch\factory\droids\ah-browser-tester.md') -Destination $factoryDroidsDir
    $reviewerDroid = Join-Path $factoryDroidsDir 'ah-reviewer.md'
    $reviewerDroidText = [IO.File]::ReadAllText($reviewerDroid)
    [IO.File]::WriteAllText($reviewerDroid, $reviewerDroidText.Replace('"Glob",', '"Glob", "Edit",'))
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer','-ReadOnly')
    Check 'Factory refuses -ReadOnly when the reviewer droid grants a write tool' ($r.Exit -eq 3 -and $r.Err -match 'grants Edit' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($reviewerDroid, ($reviewerDroidText -replace '(?m)^tools:.*$', ''))
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer','-ReadOnly')
    Check 'Factory refuses -ReadOnly when the reviewer droid omits its tools boundary' ($r.Exit -eq 3 -and $r.Err -match 'omits tools:' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    # A CRLF checkout must not smuggle a trailing \r into the tools value and
    # fail the array check (Sentry 20251924/0, SH-4676 review).
    [IO.File]::WriteAllText($reviewerDroid, (($reviewerDroidText -replace "`r`n", "`n").Replace("`n", "`r`n")))
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer','-ReadOnly')
    Check 'Factory -ReadOnly validates a CRLF droid file without a carriage-return refusal' ($r.Exit -eq 0 -and (ShowArgs $r) -match '--only-tools' -and $r.Err -notmatch 'neither the read-only category') ((ShowArgs $r) + $r.Err)
    [IO.File]::WriteAllText($reviewerDroid, $reviewerDroidText)

    # ---------- SH-4674: OpenCode V2 roles and the enforced read-only agent ----------
    foreach ($roleName in @('engineer', 'reviewer', 'tester', 'researcher')) {
        $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role',$roleName)
        Check "OpenCode -Role $roleName runs the mapped V2 agent" ($r.Exit -eq 0 -and (ShowArgs $r) -ceq "args=run --auto --format json --model opencode-go/glm-5.3-flash --agent $roleName ok") ($r.Out + $r.Err)
    }
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
    Check 'OpenCode without -Role keeps the guarded peer agent' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=run --auto --format json --model opencode-go/glm-5.3-flash --agent peer ok') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','boss')
    Check 'OpenCode refuses an unknown role' ($r.Exit -eq 3 -and $r.Err -match 'is not a role' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $fleet.dispatchPolicy.opencode.roles.Remove('tester'); Save-Fixture
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','tester')
    Check 'OpenCode refuses a role that policy does not record' ($r.Exit -eq 3 -and $r.Err -match 'roles\.tester' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $fleet.dispatchPolicy.opencode.roles['tester'] = 'tester'; Save-Fixture
    Remove-Item -LiteralPath (Join-Path $openCodeAgentsDir 'tester.md') -Force
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','tester')
    Check 'OpenCode refuses a role whose agent file is missing' ($r.Exit -eq 3 -and $r.Err -match 'tester\.md' -and $r.Err -match 'missing' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    Copy-Item -LiteralPath (Join-Path $repoRoot 'packages\coding-agent-dispatch\opencode\agents\tester.md') -Destination $openCodeAgentsDir

    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode -ReadOnly runs the readonly agent, never peer or reviewer' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=run --auto --format json --model opencode-go/glm-5.3-flash --agent readonly ok') ($r.Out + $r.Err)
    foreach ($roleArgs in @(@(), @('-Role', 'reviewer'), @('-Role', 'peer'))) {
        $r = Run (@('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly') + $roleArgs)
        Check "OpenCode -ReadOnly $($roleArgs -join ' ') runs the readonly agent" ($r.Exit -eq 0 -and (ShowArgs $r) -match '--agent readonly') ($r.Out + $r.Err)
    }
    foreach ($writingRole in @('engineer', 'tester', 'researcher')) {
        $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly','-Role',$writingRole)
        Check "OpenCode refuses -ReadOnly with -Role $writingRole" ($r.Exit -eq 3 -and $r.Err -match 'writing role' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    }
    # The gate parses the installed profile's ordered frontmatter permissions
    # (last match wins); text elsewhere in the file is never the mechanism.
    $ocReadonlyProfile = Join-Path $openCodeAgentsDir 'readonly.md'
    $ocReadonlyText = [IO.File]::ReadAllText($ocReadonlyProfile)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('{ action: edit, resource: "*", effect: deny }', '{ action: edit, resource: "*", effect: allow }'))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when the installed readonly profile grants edit' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the edit action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('{ action: shell, resource: "*", effect: deny }', '{ action: shell, resource: "*", effect: allow }'))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when the installed readonly profile grants shell' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the shell action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('{ action: subagent, resource: "*", effect: deny }', '{ action: subagent, resource: "*", effect: allow }'))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when the installed readonly profile grants subagent' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the subagent action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('{ action: browser, resource: "*", effect: deny }', '{ action: browser, resource: "*", effect: allow }'))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when the installed readonly profile grants browser' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the browser action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('  - { action: edit, resource: "*", effect: deny }', "  - { action: edit, resource: ""*"", effect: deny }`n  - { action: edit, resource: ""*"", effect: allow }"))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when a later allow rule re-opens edit (last match wins)' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the edit action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $ocBodyDeny = ($ocReadonlyText -replace '(?m)^\s*- \{ action: edit, resource: "\*", effect: deny \}\r?\n', '') + "`nThe profile denies { action: edit, resource: ""*"", effect: deny } in prose, which must not count."
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocBodyDeny)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode body text cannot override deny-by-default permissions' ($r.Exit -eq 0 -and (ShowArgs $r) -match '--agent readonly') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('  - { action: "*", resource: "*", effect: deny }', '  - { action: "*", resource: "*", effect: deny }' + "`n  - { action: context7_search, resource: `"*`", effect: allow }"))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses a read-only profile that grants a new plugin action' ($r.Exit -eq 3 -and $r.Err -match 'allow only read and glob' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('  - { action: read, resource: "*.env.*", effect: deny }', '  - { action: read, resource: "*.env.*", effect: deny }' + "`n  - { action: read, resource: `"*.env.*`", effect: allow }"))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses a later allow that reopens secret environment reads' ($r.Exit -eq 3 -and $r.Err -match 'allow only read and glob' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('  - { action: read, resource: "*.env", effect: deny }', '  - { action: read, resource: "*.env", effect: deny }' + "`n  - { action: read, resource: `"*`", effect: allow }"))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses a broad read allow after secret denies' ($r.Exit -eq 3 -and $r.Err -match 'allow only read and glob' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText.Replace('{ action: shell, resource: "*", effect: deny }', '{ action: shell, resource: "*", effect: ask }'))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses ask rules that --auto could approve' ($r.Exit -eq 3 -and $r.Err -match 'allow only read and glob' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode restricted preview isolates project config and plugins' ($r.Exit -eq 0 -and $r.Out -match 'OPENCODE_DISABLE_PROJECT_CONFIG' -and $r.Out -match 'OPENCODE_PURE') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt',"first line`nsecond line",'-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode restricted pointer prompt is attached by CLI without external read permission' ($r.Exit -eq 0 -and (ShowArgs $r) -match '--file .*prompt-show\.txt' -and $r.Out -match 'OPENCODE_PURE') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer')
    Check 'OpenCode reviewer preview isolates project config and plugins' ($r.Exit -eq 0 -and $r.Out -match 'OPENCODE_DISABLE_PROJECT_CONFIG' -and $r.Out -match 'OPENCODE_PURE') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','tester')
    Check 'OpenCode non-review role does not enable restricted-run switches' ($r.Exit -eq 0 -and $r.Out -notmatch 'OPENCODE_DISABLE_PROJECT_CONFIG|OPENCODE_PURE') ($r.Out + $r.Err)
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer')
    Check 'OpenCode reviewer role runs only with its installed restricted profile' ($r.Exit -eq 0 -and (ShowArgs $r) -match '--agent reviewer') ($r.Out + $r.Err)
    $ocReviewerProfile = Join-Path $openCodeAgentsDir 'reviewer.md'
    $ocReviewerText = [IO.File]::ReadAllText($ocReviewerProfile)
    foreach ($action in @('edit', 'shell', 'subagent', 'browser')) {
        $originalRule = "{ action: $action, resource: `"*`", effect: deny }"
        $allowedRule = "{ action: $action, resource: `"*`", effect: allow }"
        [IO.File]::WriteAllText($ocReviewerProfile, $ocReviewerText.Replace($originalRule, $allowedRule))
        $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer')
        Check "OpenCode reviewer refuses a profile that grants $action" ($r.Exit -eq 3 -and $r.Err -match "does not effectively deny the $action action" -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    }
    [IO.File]::WriteAllText($ocReviewerProfile, $ocReviewerText)
    [IO.File]::WriteAllText($ocReviewerProfile, $ocReviewerText.Replace('  - { action: shell, resource: "*", effect: deny }', '  - { action: shell, resource: "*", effect: deny }' + "`n  - { action: shell, resource: `"*`", effect: allow }"))
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-Role','reviewer')
    Check 'OpenCode reviewer refuses a later shell allow rule (last match wins)' ($r.Exit -eq 3 -and $r.Err -match 'does not effectively deny the shell action' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReviewerProfile, $ocReviewerText)
    Remove-Item -LiteralPath $ocReadonlyProfile -Force
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'OpenCode refuses -ReadOnly when the readonly agent is not installed' ($r.Exit -eq 3 -and $r.Err -match 'readonly\.md' -and $r.Err -match 'missing') ($r.Out + $r.Err)
    [IO.File]::WriteAllText($ocReadonlyProfile, $ocReadonlyText)

    foreach ($id in @('cursor-agent','grok','antigravity','cline','copilot','amp','devin','kilo','mimo-code','cursor','windsurf')) {
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
        Check "$id refuses -ReadOnly: no enforced read-only mode, no command" ($r.Exit -eq 3 -and $r.Err -match 'has no enforced read-only mode' -and $r.Err -match 'never falls back to a writable run' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-ReadOnly')
        Check "$id starts no child under -ReadOnly" ($r.Exit -eq 3 -and $r.Out -notmatch '"Arguments"') ($r.Out + $r.Err)
    }
    $r = Run @('-HostId','amp','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'a recorded false is reported as checked, none' ($r.Exit -eq 3 -and $r.Err -match 'readOnly is false: checked, none') $r.Err
    $r = Run @('-HostId','grok','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'a recorded null is reported as not established' ($r.Exit -eq 3 -and $r.Err -match 'readOnly is not established') $r.Err
    # Both gates can fail: a registry record without a verified command, and a
    # verified command without a registry record.
    $fleet.dispatchPolicy['grok']['readOnly'] = @{ flags = @('--permission-mode', 'plan'); omits = @() }; Save-Fixture
    $r = Run @('-HostId','grok','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'a registry record alone does not make a host read-only' ($r.Exit -eq 3 -and $r.Err -match 'no verified read-only command' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    $fleet.dispatchPolicy['grok']['readOnly'] = $null
    foreach ($unrecorded in @($false, $null, 'absent')) {
        if ($unrecorded -is [string]) { $fleet.dispatchPolicy['codex'].Remove('readOnly') } else { $fleet.dispatchPolicy['codex']['readOnly'] = $unrecorded }
        Save-Fixture
        $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
        Check "Codex refuses -ReadOnly when its registry record is $(if ($null -eq $unrecorded) { 'null' } else { $unrecorded })" ($r.Exit -eq 3 -and $r.Err -match 'has no enforced read-only mode' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    }
    $fleet.dispatchPolicy['codex']['readOnly'] = $readOnlyFixture['codex']; Save-Fixture
    $r = Run @('-HostId','cline','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly','-SessionId','abc')
    Check 'a Cline session resume is refused under -ReadOnly' ($r.Exit -eq 3 -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)

    # A real launch of the synthetic child: the flags reach the process.
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-ReadOnly')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Codex -ReadOnly child receives the read-only sandbox and the task on stdin' ($null -ne $d -and (@($d.Arguments) -join ' ') -ceq 'exec --sandbox read-only --skip-git-repo-check -' -and $d.Input -eq 'ok') $r.Err
    $r = Run @('-HostId','claude','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-ReadOnly')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Claude -ReadOnly child never receives the bypass mode' ($null -ne $d -and (@($d.Arguments) -join ' ') -ceq '--print --permission-mode plan --permission-prompts none' -and $d.Input -eq 'ok') $r.Err
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
    Check 'Qwen -ReadOnly swaps the yolo approval mode for plan' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=--auth-type openai -m mimo-v2.6-pro --approval-mode plan -o json' -and $r.Out -match '(?m)^stdin=yes') ($r.Out + $r.Err)
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-ReadOnly')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Qwen -ReadOnly child receives plan and never yolo' ($null -ne $d -and (@($d.Arguments) -join ' ') -ceq '--auth-type openai -m mimo-v2.6-pro --approval-mode plan -o json' -and $d.QwenRoute.openAiKeyIsMimo) $r.Err

    # -List stays as it was; -List -ReadOnly narrows it to read-only hosts.
    $r = Run @('-List')
    $listRows = @(($r.Out -split '\r?\n') | Where-Object { $_ })
    # Plus one devin-cloud row (SH-4969): a surface of the devin host, not an agents.json record.
    Check '-List still prints one three-column row per registered host' ($r.Exit -eq 0 -and $listRows.Count -eq ($ids.Count + 1) -and $r.Out -match "(?m)^devin-cloud\t" -and @($listRows | Where-Object { @($_ -split "`t").Count -ne 3 }).Count -eq 0 -and $r.Out -match "(?m)^grok\tcallable\tfile") $r.Out
    $r = Run @('-List','-ReadOnly')
    $readOnlyRows = @(($r.Out -split '\r?\n') | Where-Object { $_ } | ForEach-Object { ($_ -split "`t")[0] })
    Check '-List -ReadOnly prints exactly the read-only hosts' ($r.Exit -eq 0 -and (($readOnlyRows | Sort-Object) -join ',') -ceq 'claude,codex,factory,opencode,qwen') ($r.Out + $r.Err)
    $fleet.dispatchPolicy['codex']['enabled'] = $false; Save-Fixture
    $r = Run @('-List','-ReadOnly')
    Check '-List -ReadOnly leaves out a read-only host that policy disables' ($r.Exit -eq 0 -and $r.Out -notmatch '(?m)^codex\t' -and $r.Out -match '(?m)^claude\t') $r.Out
    $fleet.dispatchPolicy['codex'].Remove('enabled'); Save-Fixture

    # The checked-in registry and the dispatcher agree: every dispatchable host
    # records readOnly, a recorded mode yields its flags, anything else refuses.
    $realPolicy = (Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json).dispatchPolicy
    foreach ($id in $allDispatchHosts) {
        $realEntry = $realPolicy.PSObject.Properties[$id]
        $hasRecord = $null -ne $realEntry -and $null -ne $realEntry.Value.PSObject.Properties['readOnly']
        Check "registry records readOnly and a dated note for $id" ($hasRecord -and [string]$realEntry.Value.readOnlyNote -match '^\d{4}-\d{2}-\d{2} ') "dispatchPolicy.$id"
        if (-not $hasRecord) { continue }
        $realRecord = $realEntry.Value.readOnly
        $fixtureBefore = $fleet.dispatchPolicy[$id]['readOnly']
        $supported = $realRecord -is [pscustomobject]
        $fleet.dispatchPolicy[$id]['readOnly'] = if ($supported) { @{ flags = @($realRecord.flags); omits = @($realRecord.omits) } } else { $realRecord }
        Save-Fixture
        $r = Run @('-HostId',$id,'-Prompt','ok','-Cwd',$scratch,'-ShowCommand','-ReadOnly')
        if ($supported) {
            $shown = ' ' + (ShowArgs $r).Substring([Math]::Min(5, (ShowArgs $r).Length)) + ' '
            $missingFlags = @(@($realRecord.flags) | Where-Object { -not $shown.Contains(" $_ ") })
            $presentOmits = @(@($realRecord.omits) | Where-Object { $shown.Contains(" $_ ") })
            Check "registry read-only flags for $id are the flags the dispatcher runs" ($r.Exit -eq 0 -and $missingFlags.Count -eq 0 -and $presentOmits.Count -eq 0) ("missing=$($missingFlags -join ',') present=$($presentOmits -join ',') $($r.Out) $($r.Err)")
        } else {
            Check "registry records no read-only mode for $id and the dispatcher refuses it" ($r.Exit -eq 3 -and $r.Err -match 'has no enforced read-only mode') ($r.Out + $r.Err)
        }
        $fleet.dispatchPolicy[$id]['readOnly'] = $fixtureBefore
    }
    $realOcRoles = $realPolicy.opencode.roles
    $ocRoleNames = @('engineer', 'reviewer', 'tester', 'researcher', 'readonly')
    Check 'registry records the OpenCode role agents next to the guarded agent' ([string]$realPolicy.opencode.agent -ceq 'peer' -and @($ocRoleNames | Where-Object { [string]$realOcRoles.$_ -cne $_ }).Count -eq 0 -and @($ocRoleNames | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot "packages\coding-agent-dispatch\opencode\agents\$_.md")) }).Count -eq 0) ($realOcRoles | Out-String)

    # Back to the state the rest of this file expects.
    foreach ($id in $allDispatchHosts) { if ($fleet.dispatchPolicy.ContainsKey($id)) { $fleet.dispatchPolicy[$id].Remove('readOnly') } }
    foreach ($id in $createdPolicy) { $fleet.dispatchPolicy.Remove($id) }
    $fleet.dispatchPolicy.opencode.Remove('roles')
    $fleet.dispatchPolicy.opencode.Remove('agent'); Save-Fixture
    if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE = $oldWindowsHome } else { $env:HOME = $oldPosixHome }

    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','mimo/mimo-v2.5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Kilo routes a listed explicit provider/model' ($null -ne $d -and $d.Arguments -contains 'mimo/mimo-v2.5' -and $d.Arguments -notcontains 'mimo/mimo-v2.6-pro' -and $r.Err -notmatch 'note:') $r.Err
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','mimo/other-model')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Kilo passes an unlisted provider/model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'mimo/other-model' -and $r.Err -match (PassNote 'kilo' 'mimo/other-model')) $r.Err
    Check 'An unlisted model is noted exactly once' (@(($r.Err -split '\r?\n') -match '^note:').Count -eq 1) $r.Err
    Check 'Kilo keeps its guarded agent and plan key on an unlisted model' ($null -ne $d -and $d.Arguments -contains '--agent' -and $d.Arguments -contains 'peer' -and $d.ApiKeyVars.MIMO_API_KEY) $r.Err
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-Model','mimo-v2.6-pro')
    Check 'Kilo refuses a bare model id' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-Model','mimo/x&echo')
    Check 'Kilo refuses a shell-unsafe model even when listed' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $fleet.dispatchPolicy.kilo.model = 'mimo/x&echo'; Save-Fixture
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Kilo refuses a shell-unsafe default even when listed' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $fleet.dispatchPolicy.kilo.model = 'mimo/mimo-v2.6-pro'; Save-Fixture
    $fleet.dispatchPolicy.kilo.model = 'mimo-v2.6-pro'; Save-Fixture
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Kilo refuses a bare default model' ($r.Exit -eq 3 -and $r.Err -match 'provider/model') $r.Err
    $fleet.dispatchPolicy.kilo.model = 'mimo/mimo-v2.6-flash'; Save-Fixture
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Kilo runs an unlisted default with a note' ($null -ne $d -and $d.Arguments -contains 'mimo/mimo-v2.6-flash' -and $r.Err -match (PassNote 'kilo' 'mimo/mimo-v2.6-flash')) $r.Err
    $fleet.dispatchPolicy.kilo.model = 'mimo/mimo-v2.6-pro'; Save-Fixture
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','xiaomi-token-plan-sgp/mimo-v2.6-pro')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'MiMo honours the listed explicit provider/model' ($null -ne $d -and $d.Arguments -contains 'xiaomi-token-plan-sgp/mimo-v2.6-pro' -and $r.Err -notmatch 'note:') $r.Err
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','xiaomi-token-plan-sgp/other')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'MiMo passes an unlisted provider/model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'xiaomi-token-plan-sgp/other' -and $r.Err -match (PassNote 'mimo-code' 'xiaomi-token-plan-sgp/other')) $r.Err
    Check 'MiMo still strips the env plan key and keeps its guarded agent on an unlisted model' ($null -ne $d -and -not $d.ApiKeyVars.MIMO_API_KEY -and $d.Arguments -contains '--agent' -and $d.Arguments -contains 'peer') $r.Err
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-Model','mimo-v2.6-pro')
    Check 'MiMo refuses a bare model id' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $fleet.dispatchPolicy.'mimo-code'.allowedModels += 'xiaomi-token-plan-sgp/x&echo'
    $fleet.dispatchPolicy.'mimo-code'.model = 'xiaomi-token-plan-sgp/x&echo'; Save-Fixture
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'MiMo refuses a shell-unsafe default even when listed' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $fleet.dispatchPolicy.'mimo-code'.allowedModels = @('xiaomi-token-plan-sgp/mimo-v2.6-pro')
    $fleet.dispatchPolicy.'mimo-code'.model = 'xiaomi-token-plan-sgp/mimo-v2.6-pro'; Save-Fixture
    $fleet.dispatchPolicy.'mimo-code'.model = 'xiaomi-token-plan-sgp/other'; Save-Fixture
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'MiMo runs an unlisted default with a note' ($null -ne $d -and $d.Arguments -contains 'xiaomi-token-plan-sgp/other' -and $r.Err -match (PassNote 'mimo-code' 'xiaomi-token-plan-sgp/other')) $r.Err
    $fleet.dispatchPolicy.'mimo-code'.model = 'xiaomi-token-plan-sgp/mimo-v2.6-pro'; Save-Fixture
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','gpt-6-sol')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Factory honours a listed explicit model' ($null -ne $d -and $d.Arguments -contains 'gpt-6-sol' -and $d.Arguments -notcontains 'gpt-6-luna' -and $r.Err -notmatch 'note:') $r.Err
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','gpt-6.1-sol')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '-m') } else { -1 }
    Check 'Factory passes an unlisted model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'gpt-6.1-sol' -and $d.Arguments -contains 'medium' -and $r.Err -match (PassNote 'factory' 'gpt-6.1-sol')) $r.Err
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','gpt 6&echo')
    Check 'Factory refuses a malformed model id' ($r.Exit -eq 3 -and $r.Err -match 'malformed')
    $fleet.dispatchPolicy.factory.autonomy = 'high'; Save-Fixture
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Factory refuses high autonomy' ($r.Exit -eq 3 -and $r.Err -match 'only low or medium')
    $fleet.dispatchPolicy.factory.autonomy = 'medium'
    $fleet.dispatchPolicy.factory.enabled = $false; $fleet.dispatchPolicy.factory.reason = 'synthetic factory block'; Save-Fixture
    $r = Run @('-HostId','factory','-Prompt','ok','-Cwd',$scratch)
    Check 'disabled Factory policy still refuses a dispatch' ($r.Exit -eq 3 -and $r.Err -match 'synthetic factory block')
    $fleet.dispatchPolicy.factory.Remove('enabled'); $fleet.dispatchPolicy.factory.Remove('reason'); Save-Fixture
    $r = Run @('-HostId','devin','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','adaptive')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Devin routes a listed model per task' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'adaptive' -and $d.Arguments -notcontains 'swe-2-medium' -and $r.Err -notmatch 'note:') $r.Err
    $r = Run @('-HostId','devin','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','swe-2-medium-lightning')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Devin passes an unlisted model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'swe-2-medium-lightning' -and -not $d.ApiKeyVars.DEVIN_API_KEY -and $r.Err -match (PassNote 'devin' 'swe-2-medium-lightning')) $r.Err
    $r = Run @('-HostId','devin','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','--cloud')
    Check 'Devin refuses a model id shaped like a flag' ($r.Exit -eq 3 -and $r.Err -match 'malformed')
    # SH-4969: the local Devin flags come from launchDefaults.devin, not a copy in the dispatcher.
    $fleet.launchDefaults.devin = @('--permission-mode', 'smart', '--respect-workspace-trust', 'false'); Save-Fixture
    $r = Run @('-HostId','devin','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modeIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--permission-mode') } else { -1 }
    Check 'Devin takes its permission flags from launchDefaults.devin' ($modeIndex -eq 0 -and $d.Arguments[1] -eq 'smart' -and $d.Arguments -notcontains 'dangerous' -and $d.Arguments -contains '-p' -and $d.Arguments -contains '--prompt-file') $r.Err
    $fleet.launchDefaults.Remove('devin'); Save-Fixture
    $r = Run @('-HostId','devin','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Devin refuses when launchDefaults.devin is missing' ($r.Exit -eq 3 -and $r.Err -match 'launchDefaults\.devin') $r.Err
    $fleet.launchDefaults.devin = @('--permission-mode', 'dangerous', '--respect-workspace-trust', 'false'); Save-Fixture
    # SH-4969: -HostId devin-cloud hands the task to the Devin Cloud adapter's create action.
    $liveCloud = (Get-Content -LiteralPath (Join-Path $repoRoot 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json).dispatchPolicy.'devin-cloud'
    $fleet.dispatchPolicy['devin-cloud'] = @{ enabled = $false; reason = 'synthetic cloud block'; ownerAction = 'owner records a budget' }; Save-Fixture
    $r = Run @('-HostId','devin-cloud','-Prompt','ok')
    Check 'a disabled devin-cloud policy refuses with its reason' ($r.Exit -eq 3 -and $r.Err -match 'synthetic cloud block') $r.Err
    $fleet.dispatchPolicy['devin-cloud'] = ($liveCloud | ConvertTo-Json -Depth 10 | ConvertFrom-Json); Save-Fixture
    $r = Run @('-HostId','devin-cloud','-PromptFile',(Join-Path $repoRoot 'AGENTS.md'),'-Cwd',$scratch,'-RunId','sh4969-show','-MaxAcu','25','-Repo','shmindmaster/agenthub','-Title','t','-ShowCommand')
    Check 'devin-cloud show command names the adapter create action and its options' ($r.Exit -eq 0 -and $r.Out -match 'Invoke-DevinCloud\.ps1' -and $r.Out -match '-Action create' -and $r.Out -match '-MaxAcu 25' -and $r.Out -match '-RunId sh4969-show' -and $r.Out -match '-Repo shmindmaster/agenthub') "$($r.Out) $($r.Err)"
    foreach ($bad in @(@('-ReadOnly'), @('-Model','swe-2-high'), @('-Role','reviewer'))) {
        $r = Run (@('-HostId','devin-cloud','-Prompt','ok') + $bad)
        Check "devin-cloud refuses $($bad[0])" ($r.Exit -eq 3) "exit=$($r.Exit) $($r.Err)"
    }
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-MaxAcu','5')
    Check '-MaxAcu is refused for a host other than devin-cloud' ($r.Exit -eq 3 -and $r.Err -match 'devin-cloud') $r.Err
    foreach ($bad in @('2.5', '1e3', 'abc')) {
        $r = Run @('-HostId','devin-cloud','-Prompt','ok','-Cwd',$scratch,'-MaxAcu',$bad,'-ShowCommand')
        Check "devin-cloud refuses -MaxAcu $bad with exit 3" ($r.Exit -eq 3 -and $r.Err -match 'MaxAcu') "exit=$($r.Exit) $($r.Out) $($r.Err)"
    }
    $oldOpToken = [Environment]::GetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', 'Process')
    $oldCloudKey = [Environment]::GetEnvironmentVariable('DEVIN_CLOUD_API_KEY', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', $null, 'Process')
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $null, 'Process')
        $r = Run @('-List')
        Check 'list reports devin-cloud refused when no key source is reachable' ($r.Out -match "(?m)^devin-cloud\trefused\tno Devin Cloud key source" -and $r.Out -notmatch "(?m)^devin-cloud\tcallable") $r.Out
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', 'cog_SYNTHETIClistKEY0123456789abcdQRST', 'Process')
        $r = Run @('-List')
        Check 'list reports devin-cloud callable through its adapter with a key source' ($r.Out -match "(?m)^devin-cloud\tcallable\tcloud-adapter" -and $r.Out -notmatch 'SYNTHETIClistKEY') $r.Out
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $null, 'Process')
        $r = Run @('-HostId','devin-cloud','-Prompt','ok','-Cwd',$scratch,'-RunId','sh4969-nokey')
        Check 'devin-cloud without a key refuses with exit 3 naming the 1Password item' ($r.Exit -eq 3 -and $r.Err -match 'Business & Apps' -and $r.Err -match 'OP_SERVICE_ACCOUNT_TOKEN' -and [string]::IsNullOrWhiteSpace($r.Out)) "exit=$($r.Exit) $($r.Err)"
        # The dispatcher withholds the in-process override from its children but still
        # hands it to the adapter: with no service-account token, only the override can
        # get the run as far as the (refused) loopback connection.
        $cloudKey = 'cog_SYNTHETICdispatchKEY0123456789abQRST'
        $fleet.dispatchPolicy['devin-cloud'].cloudBudgetAuthorization.apiBase = 'https://127.0.0.1:9/v3'; Save-Fixture
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $cloudKey, 'Process')
        $r = Run @('-HostId','devin-cloud','-Prompt','ok','-Cwd',$scratch,'-RunId','sh4969-override','-Repo','o/r')
        Check 'devin-cloud hands an in-process key override to the adapter' ($r.Exit -eq 1 -and $r.Err -match 'no HTTP response') "exit=$($r.Exit) $($r.Err)"
        Check 'the handed-over key is never printed' (($r.Out + $r.Err) -notmatch [regex]::Escape($cloudKey))
    } finally {
        [Environment]::SetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', $oldOpToken, 'Process')
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $oldCloudKey, 'Process')
    }
    $fleet.dispatchPolicy.Remove('devin-cloud'); Save-Fixture
    $text = "quoted `"text`" café`n& echo %PATH% !name! " + ('x' * 9000)
    $taskFile = Join-Path $fixture 'task.txt'; [IO.File]::WriteAllText($taskFile, $text)
    foreach ($id in @('antigravity')) {
        $r = Run @('-HostId',$id,'-PromptFile',$taskFile,'-Cwd',$scratch,'-TimeoutSec','5')
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        $detail = "exit=$($r.Exit) lengths=$(@($d.PromptContents | ForEach-Object { $_.Length }) -join ',') expected=$($text.Length) args=$($d.Arguments -join ' ') $($r.Err)"
        Check "$id preserves long quoted multiline prompt" ($r.Exit -eq 0 -and $d.PromptContents -contains $text) $detail
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
    $r = Run @('-HostId','amp','-Prompt','ok','-Cwd',$scratch,'-Model','x')
    Check 'a host without a model contract still refuses -Model' ($r.Exit -eq 3 -and $r.Err -match '-Model applies only')
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','gpt-6.1-sol')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '-m') } else { -1 }
    Check 'Codex passes an explicit model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'gpt-6.1-sol' -and $d.Arguments[0] -eq 'exec' -and $d.Arguments[-1] -eq '-' -and $d.Input -eq 'ok' -and -not $d.ApiKeyVars.OPENAI_API_KEY -and $r.Err -match (PassNote 'codex' 'gpt-6.1-sol')) $r.Err
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-Model','gpt 6|more')
    Check 'Codex refuses a malformed model id' ($r.Exit -eq 3 -and $r.Err -match 'malformed')
    $r = Run @('-HostId','grok','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','grok-4.7-code')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Grok passes an explicit model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'grok-4.7-code' -and $d.Arguments -contains '--prompt-file' -and $d.PromptContents -contains 'ok' -and $r.Err -match (PassNote 'grok' 'grok-4.7-code')) $r.Err
    $r = Run @('-HostId','grok','-Prompt','ok','-Cwd',$scratch,'-Model','grok;echo')
    Check 'Grok refuses a malformed model id' ($r.Exit -eq 3 -and $r.Err -match 'malformed')
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','opencode-go/kimi-k3')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'OpenCode passes an unlisted provider/model through with a note' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'opencode-go/kimi-k3' -and -not $d.ApiKeyVars.OPENCODE_GO_API_KEY -and $r.Err -match (PassNote 'opencode' 'opencode-go/kimi-k3')) $r.Err
    $zaiArgs = @('-HostId','opencode','-Model','zai-coding-plan/glm-5.3','-ShowCommand','-Cwd',$scratch)
    $r = Run $zaiArgs
    Check 'Windows Z.ai refuses a missing launcher rather than falling back to Go' ($r.Exit -eq 3 -and $r.Err -match 'launcher is absent')
    $zaiFixture = Join-Path $env:LOCALAPPDATA 'AgentHub\zai'
    $null = New-Item -ItemType Directory -Path $zaiFixture -Force
    Set-Content -LiteralPath (Join-Path $zaiFixture 'opencode-zai.ps1') -Value 'exit 7'
    $r = Run $zaiArgs
    Check 'Windows Z.ai uses the isolated launcher without the Go peer auto-approval' ($r.Exit -eq 0 -and $r.Out -match 'opencode-zai\.ps1' -and $r.Out -match '--model zai-coding-plan/glm-5\.3' -and $r.Out -match 'OPENCODE_CONFIG_CONTENT' -and $r.Out -notmatch '--auto')
    $r = Run @('-HostId','opencode','-Model','zai-coding-plan/glm-5.3','-Cwd',$scratch,'-Prompt','ok','-TimeoutSec','5')
    Check 'Windows Z.ai propagates its launcher exit status' ($r.Exit -eq 7)
    # Subscriptions only: the opencode/ provider is the pay-as-you-go Zen wallet.
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','opencode/kimi-k3')
    Check 'OpenCode refuses the pay-as-you-go opencode/ provider and names the Go route' ($r.Exit -eq 3 -and $r.Err -match 'Zen wallet' -and $r.Err -match 'opencode-go/<model>') $r.Err
    $fleet.dispatchPolicy.opencode.model = 'opencode/glm-5.3-flash'; Save-Fixture
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'OpenCode refuses a recorded default on the opencode/ provider' ($r.Exit -eq 3 -and $r.Err -match 'Zen wallet') $r.Err
    $fleet.dispatchPolicy.opencode.model = 'opencode-go/glm-5.3-flash'; Save-Fixture
    # MiMo routes on every host must be the Xiaomi Token Plan.
    $mimoRoutes = @(
        @('kilo', 'mimo/mimo-v2.6-pro'),
        @('mimo-code', 'xiaomi-token-plan-sgp/mimo-v2.6-pro'),
        @('opencode', 'mimo-token-plan/mimo-v2.6-pro'),
        @('cline', 'mimo-token-plan:mimo-v2.6-pro'),
        @('factory', 'custom-mimo-v2.6-pro'),
        @('qwen', 'mimo-v2.6-pro')
    )
    foreach ($route in $mimoRoutes) {
        $routeHost = $route[0]; $routeModel = $route[1]
        $r = Run @('-HostId',$routeHost,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model',$routeModel)
        $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
        Check "$routeHost runs a MiMo model with a tp- key and a token-plan host" ($null -ne $d -and $r.Err -notmatch 'refused') $r.Err
        $env:MIMO_API_KEY = 'sk-synthetic-payg-fixture'
        $r = Run @('-HostId',$routeHost,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model',$routeModel)
        Check "$routeHost refuses a MiMo model on a pay-as-you-go sk- key without printing it" ($r.Exit -eq 3 -and $r.Err -match 'MIMO_API_KEY' -and $r.Err -notmatch 'synthetic-payg' -and $r.Out -notmatch 'synthetic-payg') $r.Err
        $env:MIMO_API_KEY = 'ttp-synthetic-dispatch-fixture'; $env:MIMO_BASE_URL = 'https://api.xiaomimimo.com/v1'
        $r = Run @('-HostId',$routeHost,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model',$routeModel)
        Check "$routeHost refuses a MiMo model on the pay-as-you-go base URL without printing it" ($r.Exit -eq 3 -and $r.Err -match 'MIMO_BASE_URL' -and $r.Err -notmatch 'api\.xiaomimimo') $r.Err
        $env:MIMO_BASE_URL = 'https://token-plan-sgp.xiaomimimo.com/v1'
        $r = Run @('-HostId',$routeHost,'-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model',$routeModel)
        Check "$routeHost accepts a ttp- key on a token-plan host" ($r.Exit -eq 0) $r.Err
        $env:MIMO_API_KEY = 'tp-synthetic-dispatch-fixture'
    }
    $env:MIMO_API_KEY = $null; $env:MIMO_BASE_URL = $null
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'MiMo runs on its stored plan credential when neither variable is set' ($r.Exit -eq 0) $r.Err
    $env:MIMO_BASE_URL = 'https://token-plan-sgp.xiaomimimo.com.example.net/v1'
    $r = Run @('-HostId','kilo','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Kilo refuses a look-alike token-plan host on its default model' ($r.Exit -eq 3 -and $r.Err -match 'MIMO_BASE_URL') $r.Err
    $env:MIMO_API_KEY = 'tp-synthetic-dispatch-fixture'; $env:MIMO_BASE_URL = 'https://token-plan-sgp.xiaomimimo.com/v1'
    $r = Run @('-HostId','mimo-code','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','xiaomi/mimo-v2.6-pro')
    Check 'MiMo refuses the pay-as-you-go xiaomi/ provider' ($r.Exit -eq 3 -and $r.Err -match 'pay-as-you-go MiMo API') $r.Err
    $env:MIMO_API_KEY = 'sk-synthetic-payg-fixture'
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','opencode-go/mimo-v2.6-pro')
    Check 'A MiMo model on the OpenCode Go subscription is not a MiMo API route' ($r.Exit -eq 0) $r.Err
    $env:MIMO_API_KEY = 'tp-synthetic-dispatch-fixture'

    # ---------- SH-4421: Qwen Code on the Xiaomi MiMo Token Plan ----------
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
    Check 'Qwen -ShowCommand prints the exact command and child env names, never the key' ($r.Exit -eq 0 -and (ShowArgs $r) -ceq 'args=--auth-type openai -m mimo-v2.6-pro --approval-mode yolo -o json' -and $r.Out -match '(?m)^stdin=yes' -and $r.Out -match '(?m)^env=' -and $r.Out -match 'OPENAI_API_KEY' -and $r.Out -match 'OPENAI_BASE_URL' -and $r.Out -match 'OPENAI_MODEL' -and $r.Out -notmatch 'tp-synthetic-dispatch-fixture' -and $r.Err -notmatch 'tp-synthetic-dispatch-fixture') ($r.Out + $r.Err)
    $savedMimoUrl = $env:MIMO_BASE_URL
    try {
        $env:MIMO_BASE_URL = 'http://token-plan-sgp.xiaomimimo.com/v1'
        $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-ShowCommand')
        Check 'Qwen refuses a Token Plan host over plain http' ($r.Exit -eq 3 -and $r.Err -match 'MIMO_BASE_URL' -and $r.Out -notmatch 'args=') ($r.Out + $r.Err)
    } finally { $env:MIMO_BASE_URL = $savedMimoUrl }
    # The plan credential is this route's whole auth, so absent variables are a
    # refusal, not a pass-through like mimo-code's stored credential.
    $env:MIMO_API_KEY = $null; $env:MIMO_BASE_URL = $null
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Qwen refuses when the plan variables are absent and starts no child' ($r.Exit -eq 3 -and $r.Err -match 'MIMO_BASE_URL is not set' -and $r.Out -notmatch '"Arguments"') ($r.Out + $r.Err)
    $env:MIMO_BASE_URL = 'https://token-plan-sgp.xiaomimimo.com/v1'
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5')
    Check 'Qwen refuses when only the plan key is absent' ($r.Exit -eq 3 -and $r.Err -match 'MIMO_API_KEY is not set') ($r.Out + $r.Err)
    $env:MIMO_API_KEY = 'tp-synthetic-dispatch-fixture'
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','mimo-v2.6-pro')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Qwen routes a listed explicit model without a note' ($null -ne $d -and $d.Arguments -contains 'mimo-v2.6-pro' -and $r.Err -notmatch 'note:') $r.Err
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-TimeoutSec','5','-Model','mimo-v2.6-flash')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    Check 'Qwen passes an unlisted plan model through with a note and remaps it' ($null -ne $d -and $d.Arguments -contains 'mimo-v2.6-flash' -and $d.QwenRoute.openAiModel -eq 'mimo-v2.6-flash' -and $r.Err -match (PassNote 'qwen' 'mimo-v2.6-flash')) $r.Err
    $r = Run @('-HostId','qwen','-Prompt','ok','-Cwd',$scratch,'-Model','mimo v2&echo')
    Check 'Qwen refuses a malformed model id' ($r.Exit -eq 3 -and $r.Err -match 'malformed')
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-Model','kimi-k3')
    Check 'OpenCode refuses a bare model id' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-Model','opencode-go/x&echo')
    Check 'OpenCode refuses a shell-unsafe model id' ($r.Exit -eq 3 -and $r.Err -match 'provider/model')
    $fleet.dispatchPolicy.opencode['allowedModels'] = @('opencode-go/glm-5.3-flash', 'opencode-go/glm-5.3'); $fleet.dispatchPolicy.opencode['agent'] = 'peer'; Save-Fixture
    $r = Run @('-HostId','opencode','-Prompt','ok','-Cwd',$scratch,'-Model','opencode-go/glm-5.3','-Title','T1 task','-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    $titleIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--title') } else { -1 }
    Check 'OpenCode routes a listed Go model and session title per task' ($modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'opencode-go/glm-5.3' -and $r.Err -notmatch 'note:' -and $titleIndex -ge 0 -and $d.Arguments[$titleIndex + 1] -eq 'T1 task' -and $d.Arguments[-1] -eq 'ok') $r.Err
    $agentIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--agent') } else { -1 }
    Check 'OpenCode unattended runs use the policy-named agent' ($agentIndex -ge 0 -and $d.Arguments[$agentIndex + 1] -eq 'peer') $r.Err
    $fleet.dispatchPolicy.opencode.Remove('allowedModels'); $fleet.dispatchPolicy.opencode.Remove('agent'); Save-Fixture
    $fleet.dispatchPolicy['cline'] = @{ allowedModels = @('openai-compatible:qwen3.8-max-0902', 'cline:poolside/laguna-s-2.1:free') }; Save-Fixture
    $r = Run @('-HostId','cline','-Prompt','ok','-Cwd',$scratch,'-Model','cline:anthropic/claude-sonnet-5.5','-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $providerIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--provider') } else { -1 }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Cline passes an unlisted provider:model through with a note' ($providerIndex -ge 0 -and $d.Arguments[$providerIndex + 1] -eq 'cline' -and $modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'anthropic/claude-sonnet-5.5' -and $d.PeerGuard -eq '1' -and -not $d.ApiKeyVars.ANTHROPIC_API_KEY -and $r.Err -match (PassNote 'cline' 'cline:anthropic/claude-sonnet-5.5')) $r.Err
    $r = Run @('-HostId','cline','-Prompt','ok','-Cwd',$scratch,'-Model','claude-sonnet-5.5','-TimeoutSec','5')
    Check 'Cline refuses a model id without a provider' ($r.Exit -eq 3 -and $r.Err -match 'provider:model')
    $r = Run @('-HostId','cline','-Prompt','ok','-Cwd',$scratch,'-Model','cline:poolside/laguna-s-2.1:free','-TimeoutSec','5')
    $d = if ($r.Exit -eq 0) { $r.Out | ConvertFrom-Json } else { $null }
    $providerIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--provider') } else { -1 }
    $modelIndex = if ($d) { [Array]::IndexOf($d.Arguments, '--model') } else { -1 }
    Check 'Cline routes a listed provider:model per task' ($r.Err -notmatch 'note:' -and $providerIndex -ge 0 -and $d.Arguments[$providerIndex + 1] -eq 'cline' -and $modelIndex -ge 0 -and $d.Arguments[$modelIndex + 1] -eq 'poolside/laguna-s-2.1:free' -and $d.PeerGuard -eq '1') $r.Err
    $fleet.dispatchPolicy.Remove('cline'); Save-Fixture
    if ($env:OS -eq 'Windows_NT') { $env:USERPROFILE = $oldWindowsHome } else { $env:HOME = $oldPosixHome }
    $r = Run @('-HostId','codex','-Prompt','ok','-Cwd',$scratch,'-Title','x')
    Check 'session title is refused for other hosts' ($r.Exit -eq 3 -and $r.Err -match '-Title applies only')
    $r = Run @('-List')
    Check 'list keeps disabled Claude refused despite the opt-in record' ($r.Out -match "(?m)^claude\trefused\t")
    $fleet.dispatchPolicy.Remove('claude'); Save-Fixture
    $r = Run @('-HostId','windsurf','-Prompt','ok','-Cwd',$scratch)
    Check 'Windsurf executes the Devin file contract' ($r.Exit -eq 0 -and $r.Out -match 'routed: windsurf -> devin' -and $r.Out -match 'swe-2-medium') $r.Err
    $r = Run @('-HostId','antigravity','-Prompt','--dash & echo %PATH%','-ShowCommand')
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
    ($agents.activeAgents | Where-Object id -eq 'antigravity').executable = Join-Path $fixture 'missing-agent-binary'; Save-Fixture
    $r = Run @('-HostId','antigravity','-Prompt','ok'); Check 'missing binary refuses' ($r.Exit -eq 3 -and $r.Err -match 'executable is absent')
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
    $env:USERPROFILE = $oldWindowsHome; $env:HOME = $oldPosixHome
    foreach ($name in $oldApiKeyVars.Keys) { [Environment]::SetEnvironmentVariable($name, $oldApiKeyVars[$name], 'Process') }
    [Environment]::SetEnvironmentVariable('MIMO_BASE_URL', $oldMimoBaseUrl, 'Process')
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith([IO.Path]::GetFullPath(([IO.Path]::GetTempPath())).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ("RESULT: {0} passed, {1} failed" -f ($checked - $failed), $failed)
if ($failed) { exit 1 }
exit 0
