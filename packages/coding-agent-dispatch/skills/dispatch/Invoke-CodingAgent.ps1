#Requires -Version 5.1
<#
.SYNOPSIS
  Run one coding-agent host from another, windowless.

.DESCRIPTION
  Claude and Codex are the primary orchestrators. Any host that can run this
  script can call a host whose headless command was verified on this machine
  on 2026-10-14. Hosts without that evidence are refused. Cursor routes to
  cursor-agent and Windsurf routes to the local Devin CLI. GUI hosts are refused.

  Remote cloud agents are refused. A local headless contract does not
  authorize a hosted computer, background agent, or paid-credit run.

  Argument-style hosts take the prompt on the command line. A prompt that is
  long, multi-line, quoted, or given with -PromptFile is written to a file
  under %LOCALAPPDATA%\AgentHub\runtime\coding-agent-dispatch and the host
  receives a one-line pointer to that file. Every host therefore accepts
  -PromptFile.

  Account-authenticated hosts do not inherit their API key environment
  variables. Explicit API-key runs use their own configuration. The only
  dispatcher API-key route is -HostId claude -AnthropicApiKey, per call.

  Paths come from registry/agents.json. Flags that a ~/bin shim already
  applies are not repeated. This script does not invent a flag, open a
  window, or register a scheduled task.

.PARAMETER List
  Print each host as id, state, detail. States are callable, routed, refused.

.PARAMETER ShowCommand
  Print the file and arguments that would run, then exit. No process starts.

.PARAMETER HostId
  agents.json id. cursor is accepted and runs cursor-agent.

.PARAMETER Prompt
  Task text. Use -PromptFile when the text is long or has quotes or newlines.

.PARAMETER PromptFile
  UTF-8 file whose contents are the task.

.PARAMETER Cwd
  Working directory for the child. Defaults to the current directory.

.PARAMETER TimeoutSec
  Kill the child and its process tree after this many seconds. Default 1800.

.PARAMETER AnthropicApiKey
  Per-call opt-in for -HostId claude only: keep ANTHROPIC_API_KEY in the child
  so this one run bills the shared Anthropic API key instead of the account
  login. Requires dispatchPolicy.claude.apiKeyOptIn and refuses after its
  expiresUtc. Never applied without this switch.

.PARAMETER Model
  Model for an -AnthropicApiKey run. Defaults to apiKeyOptIn.model.
  For -HostId opencode, a model listed in dispatchPolicy.opencode.allowedModels;
  anything else is refused. Defaults to dispatchPolicy.opencode.model.
  For -HostId cline, provider:model listed in dispatchPolicy.cline.allowedModels
  (for example cline:poolside/laguna-s-2.1:free); anything else is refused, so a
  run cannot select a usage-billed model. Defaults to hostSettings.cline.
  For -HostId warp, a model listed in dispatchPolicy.warp.allowedModels (every
  Warp-hosted model spends Warp credits); anything else is refused. Defaults to
  dispatchPolicy.warp.model.
  For -HostId factory, a model listed in dispatchPolicy.factory.allowedModels;
  anything else is refused. Defaults to dispatchPolicy.factory.model.

.PARAMETER Title
  Session title for -HostId opencode, so the run is findable in the shared
  service from the TUI and Desktop. Refused for other hosts.

.PARAMETER SessionId
  Continue an existing Cline session through ACP. Policy gates still apply.

#>
[CmdletBinding()]
param(
    [string]$HostId,
    [string]$Prompt,
    [string]$PromptFile,
    [string]$Cwd,
    [int]$TimeoutSec = 1800,
    [switch]$AnthropicApiKey,
    [string]$Model,
    [string]$Title,
    [string]$SessionId,
    [switch]$List,
    [switch]$ShowCommand
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Find-AgentHubRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTHUB_ROOT)) {
        $candidate = $env:AGENTHUB_ROOT
        if (Test-Path -LiteralPath (Join-Path $candidate 'registry\agents.json')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $dir = $PSScriptRoot
    for ($i = 0; $i -lt 8 -and $dir; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir 'registry\agents.json')) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    $fallback = 'C:\Repos\shmindmaster\agenthub'
    if (Test-Path -LiteralPath (Join-Path $fallback 'registry\agents.json')) { return $fallback }
    throw 'AgentHub registry was not found. Set AGENTHUB_ROOT to the agenthub checkout.'
}

function Write-Refusal {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine($Message)
    exit $Code
}

function Format-WindowsArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    # CommandLineToArgvW quoting: double only backslashes before quotes and
    # the closing quote, never ordinary path separators.
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Join-WindowsArguments {
    param([string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object { Format-WindowsArgument $_ }) -join ' ')
}

# Argument prompts cannot carry quotes, newlines, or a long command line.
# Stdin and prompt-file hosts can. 6000 leaves room for the flags under the
# Windows 8191-character command-line limit.
$script:ArgumentPromptLimit = 6000

function Test-ArgumentPrompt {
    param([string]$Text)
    if ($Text.Length -gt $script:ArgumentPromptLimit) { return $false }
    # Batch shims must never receive shell syntax or variable expansion.
    if ($Text -match '[\r\n"&|<>^%!()]') { return $false }
    if ($Text.StartsWith('-')) { return $false }
    return $true
}

function Get-DispatchTable {
    # mode: stdin | argument | file
    # A ~/bin or npm .cmd is started through a hidden cmd.exe. Fleet flags
    # already baked into that shim are not added again.
    return @{
        'claude' = @{
            Mode = 'stdin'
            Build = {
                param($PromptText, $Work, $File)
                $args = @('--print', '--permission-mode', 'bypassPermissions')
                if ($script:ClaudeApiKeyModel) { $args += @('--model', $script:ClaudeApiKeyModel) }
                @{ Args = $args; Stdin = $PromptText; PromptFile = $null }
            }
        }
        'codex' = @{
            Mode = 'stdin'
            Build = {
                param($PromptText, $Work, $File)
                # The shim selects a profile; cwd may legitimately be a
                # scratch directory. Do not initialize a repository there.
                $args = @('exec', '--skip-git-repo-check', '-')
                @{ Args = $args; Stdin = $PromptText; PromptFile = $null }
            }
        }
        'cursor-agent' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                @{ Args = @('--print', '--output-format', 'text', '--mode', 'ask', '--trust', '--workspace', $Work, $PromptText); Stdin = $null; PromptFile = $null }
            }
        }
        'gemini' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # The registered shim applies its yolo default only when this
                # explicit approval-mode flag is absent.
                $args = @('--approval-mode', 'yolo', '--prompt', $PromptText)
                # Gemini restricts read_file to workspace roots. A pointer
                # prompt must explicitly admit its runtime prompt directory.
                if ($File) { $args += @('--include-directories', (Split-Path -Parent $File)) }
                @{ Args = $args; Stdin = $null; PromptFile = $null }
            }
        }
        'grok' = @{
            Mode = 'file'
            Build = {
                param($PromptText, $Work, $File)
                # Local user guide 14-headless-mode.md: --prompt-file triggers headless.
                # Do not also pass -p; that puts the prompt on the command line.
                @{ Args = @('--prompt-file', $File, '--yolo', '--cwd', $Work); Stdin = $null; PromptFile = $File }
            }
        }
        'opencode' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # OpenCode 2 uses the child process working directory; --dir
                # belonged to v1 and is rejected by the shared-service CLI.
                # Native JSON events give callers reliable text/tool/usage
                # boundaries without parsing terminal-rendered output.
                $args = @('run', '--auto', '--format', 'json')
                $openCodeModel = if ($script:OpenCodeModel) { $script:OpenCodeModel } else { [string]$fleet.dispatchPolicy.opencode.model }
                if ($openCodeModel) { $args += @('--model', $openCodeModel) }
                # --auto approves every action a rule leaves at ask, so unattended
                # runs use the policy-named agent whose rules deny outward actions.
                if ($fleet.dispatchPolicy.opencode.agent) { $args += @('--agent', [string]$fleet.dispatchPolicy.opencode.agent) }
                if (-not [string]::IsNullOrWhiteSpace($Title)) { $args += @('--title', $Title.Trim()) }
                $args += $PromptText
                @{ Args = $args; Stdin = $null; PromptFile = $null }
            }
        }
        'antigravity' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # 2026-10-14 live run: agy ignores a prompt left as a separate
                # argument after --print and asks for --print='prompt'. Attach
                # the prompt to the flag and keep the permission flag before it.
                @{ Args = @('--dangerously-skip-permissions', ('--print=' + $PromptText)); Stdin = $null; PromptFile = $null }
            }
        }
        'factory' = @{
            Mode = 'file'
            Build = {
                param($PromptText, $Work, $File)
                # Governed dispatch: autonomy is capped at medium (`high` permits
                # git push and --skip-permissions-unsafe is never emitted), JSON
                # output yields a session id and credit usage, and the repo-owned
                # rules file is the permission policy verified with `droid rules check`.
                $factoryPolicy = $fleet.dispatchPolicy.factory
                $autonomy = [string]$factoryPolicy.autonomy
                if ($autonomy -notin @('low', 'medium')) {
                    Write-Refusal 3 "refused factory: dispatchPolicy.factory.autonomy '$autonomy' is not permitted for dispatch; only low or medium"
                }
                $runtimeSettings = Join-Path $root ([string]$factoryPolicy.runtimeSettings)
                if (-not (Test-Path -LiteralPath $runtimeSettings -PathType Leaf)) {
                    Write-Refusal 3 "refused factory: dispatchPolicy.factory.runtimeSettings not found: $runtimeSettings"
                }
                $args = @('exec', '--cwd', $Work, '--auto', $autonomy, '-o', 'json', '--settings', $runtimeSettings)
                $factoryModel = if ($script:FactoryModel) { $script:FactoryModel } else { [string]$factoryPolicy.model }
                if ($factoryModel) { $args += @('-m', $factoryModel) }
                $args += @('-f', $File)
                @{ Args = $args; Stdin = $null; PromptFile = $File }
            }
        }
        'cline' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # CLI 3.0.73: --yolo selects the restricted benchmark toolset.
                # Normal JSON execution retains plugins, MCP and native skills.
                $args = @('--json', '--cwd', $Work, '--timeout', [string]$TimeoutSec,
                    '--auto-approve', 'true', '--thinking', 'low', '--compaction', 'agentic')
                $clineProvider = if ($script:ClineProvider) { $script:ClineProvider } else { [string]$fleet.hostSettings.cline.provider }
                $clineModel = if ($script:ClineModel) { $script:ClineModel } else { [string]$fleet.hostSettings.cline.model }
                if ($clineProvider) { $args += @('--provider', $clineProvider) }
                if ($clineModel) { $args += @('--model', $clineModel) }
                $args += $PromptText
                # --auto-approve approves every tool call. The peer-guard plugin
                # (~/.cline/plugins/peer-guard.js) denies outward and destructive
                # actions, but only in-process: in hub mode it never sees the flag.
                @{ Args = $args; Stdin = $null; PromptFile = $null; Env = $script:ClineGuardEnv }
            }
        }
        'copilot' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                @{ Args = @('-p', $PromptText, '-C', $Work); Stdin = $null; PromptFile = $null }
            }
        }
        'amp' = @{
            Mode = 'stdin'
            Build = {
                param($PromptText, $Work, $File)
                # amp --help 2026-10-14: -x/--execute reads the prompt from stdin
                # and prints the last assistant message. --dangerously-allow-all
                # disables command confirmation (amp.dangerouslyAllowAll).
                $settingsFile = Join-Path $runDir ("settings-amp-{0}.json" -f [guid]::NewGuid().ToString('n'))
                @{ Args = @('-x', '--dangerously-allow-all', '--no-notifications', '--no-ide', '--settings-file', $settingsFile); Stdin = $PromptText; PromptFile = $null; SettingsFile = $settingsFile }
            }
        }
        'devin' = @{
            Mode = 'file'
            Build = {
                param($PromptText, $Work, $File)
                # devin --help 2026-10-14: -p is non-interactive, --prompt-file loads
                # the prompt. Flags are launchDefaults.devin; the registry points at
                # the WinGet devin.exe, not the ~/bin shim that already adds them.
                $args = @('--permission-mode', 'dangerous', '--respect-workspace-trust', 'false', '-p', '--prompt-file', $File)
                $devinModel = if ($script:DevinModel) { $script:DevinModel } else { [string]$fleet.dispatchPolicy.devin.model }
                if ($devinModel) { $args += @('--model', $devinModel) }
                @{ Args = $args; Stdin = $null; PromptFile = $File }
            }
        }
        'warp' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # warp.exe with WARP_CLI_MODE=1 is the oz CLI (oz.cmd sets the same
                # variable). `agent run --prompt` runs one local task, -C sets the cwd;
                # run-cloud is never built. --no-snapshot keeps the workspace off
                # Warp's servers, and ndjson carries the run and conversation ids.
                $args = @('agent', 'run', '--prompt', $PromptText, '-C', $Work, '--no-snapshot', '--output-format', 'ndjson')
                $warpModel = if ($script:WarpModel) { $script:WarpModel } else { [string]$fleet.dispatchPolicy.warp.model }
                if ($warpModel) { $args += @('--model', $warpModel) }
                # settings.toml agents.mcp_servers.file_based_mcp_enabled = false keeps
                # Warp from loading ~/.warp/.mcp.json on its own, so a recorded
                # dispatchPolicy.warp.mcpConfig is passed per run through the
                # documented repeatable --mcp flag with a bounded startup timeout.
                # The template resolves through the same PathBinding that resolves
                # executable paths. The file may hold auth headers, so it is never
                # read or printed here; a missing file skips both flags with one
                # stderr warning and the run continues without MCP.
                $warpMcpConfig = [string]$fleet.dispatchPolicy.warp.mcpConfig
                if (-not [string]::IsNullOrWhiteSpace($warpMcpConfig)) {
                    $warpMcpPath = Resolve-AgentHubBoundPath -Declared $warpMcpConfig.Trim() -Context $binding
                    if (Test-Path -LiteralPath $warpMcpPath -PathType Leaf) {
                        $args += @('--mcp', $warpMcpPath, '--mcp-startup-timeout', '30s')
                    } else {
                        [Console]::Error.WriteLine("warp dispatch: mcpConfig file not found, continuing without --mcp: $warpMcpPath")
                    }
                }
                # Warp syncs ExecutionProfiles from the cloud and its CLI profile cannot
                # be edited, so a command denylist does not hold. The guard lives in the
                # child environment: every push URL is rewritten to a scheme git has no
                # helper for, and gh reads an empty config directory, so pushes and
                # gh pr/release/api calls fail closed while fetch and local git work.
                $ghDir = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub\runtime\coding-agent-dispatch\warp-peer-gh'
                New-Item -ItemType Directory -Force -Path $ghDir | Out-Null
                $guard = @{ WARP_CLI_MODE = '1'; GH_CONFIG_DIR = $ghDir; GIT_CONFIG_COUNT = '3' }
                $schemes = @('https://', 'git@', 'ssh://')
                for ($i = 0; $i -lt $schemes.Count; $i++) {
                    $guard["GIT_CONFIG_KEY_$i"] = 'url.agenthub-peer-no-push://blocked/.pushInsteadOf'
                    $guard["GIT_CONFIG_VALUE_$i"] = $schemes[$i]
                }
                @{ Args = $args; Stdin = $null; PromptFile = $null; Env = $guard }
            }
        }
    }
}

function Get-AgentRecord {
    param($Agents, [string]$Id)
    return $Agents | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1
}

$root = Find-AgentHubRoot
. (Join-Path $root 'scripts\lib\PathBinding.ps1')
$binding = New-AgentHubPathBindingContext -TargetUserProfile (Get-AgentHubDefaultHome)
$isWindowsHost = $binding.Platform -eq 'windows'
$agentsDoc = Get-Content -LiteralPath (Join-Path $root 'registry\agents.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Use-AgentHubPlatformPaths -AgentsDocument $agentsDoc -Platform $binding.Platform | Out-Null
$agents = @($agentsDoc.activeAgents)
$fleet = Get-Content -LiteralPath (Join-Path $root 'registry\fleet-profile.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$interactive = @{}
foreach ($profile in @($fleet.autonomyProfiles.profiles)) {
    if ([string]$profile.defaultProfile -eq 'interactive') { $interactive[[string]$profile.hostId] = $true }
}
$table = Get-DispatchTable
$routes = @{ 'cursor' = 'cursor-agent'; 'windsurf' = 'devin' }
$dispatchPolicy = $fleet.dispatchPolicy
$script:ClaudeApiKeyOptIn = $false
$script:ClaudeApiKeyModel = $null

function Test-PolicyDisabled {
    param([string]$Id)
    if ($Id -eq 'claude' -and $script:ClaudeApiKeyOptIn) { return $false }
    if ($null -eq $dispatchPolicy) { return $false }
    $entry = $dispatchPolicy.PSObject.Properties[$Id]
    if ($null -eq $entry) { return $false }
    return ($entry.Value.enabled -eq $false)
}

function Get-PolicyRefusal {
    param([string]$Id)
    if (-not (Test-PolicyDisabled $Id)) { return $null }
    $policy = $dispatchPolicy.PSObject.Properties[$Id].Value
    return ((@('dispatchPolicy disables this host', [string]$policy.reason, [string]$policy.ownerAction) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('.') }) -join '. ')
}

function Resolve-DeclaredExecutable {
    param([string]$Declared)
    if ([string]::IsNullOrWhiteSpace($Declared)) { return $null }
    $text = $Declared
    if (-not $isWindowsHost) {
        # A Windows launcher path names a CLI that installs onto PATH elsewhere.
        $portable = Get-AgentHubPortableCommandName $text
        if ($portable) { $text = $portable }
    }
    if ($text -match '[\\/]' -or (Test-AgentHubPathTemplate $text)) {
        if (Test-AgentHubPathTemplate $text) {
            $text = Resolve-AgentHubBoundPath -Declared $text -Context $binding
        }
        if (Test-Path -LiteralPath $text -PathType Leaf) { return $text }
        return $null
    }
    $command = Get-Command -Name $text -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return [string]$command.Source }
    return $null
}

function Get-HostRow {
    param($Agent)
    $id = [string]$Agent.id
    $refusal = Get-PolicyRefusal $id
    if ($refusal) {
        return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = $refusal }
    }
    if ($interactive.ContainsKey($id)) {
        return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'interactive autonomy profile; establish an unattended contract and update autonomyProfiles before dispatch' }
    }
    if ($routes.ContainsKey($id)) {
        $target = $routes[$id]
        $targetAgent = Get-AgentRecord -Agents $agents -Id $target
        if (-not $targetAgent) { return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = "route target $target is not registered" } }
        $targetRow = Get-HostRow $targetAgent
        if ($targetRow.State -eq 'refused') {
            return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = "routes to ${target}: $($targetRow.Detail)" }
        }
        $exe = Resolve-DeclaredExecutable -Declared ([string]$targetAgent.executable)
        if (-not $exe) {
            return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = "routes to $target but that executable is absent" }
        }
        return [pscustomobject]@{ Id = $id; State = 'routed'; Detail = $target }
    }
    if ($table.ContainsKey($id)) {
        $exe = Resolve-DeclaredExecutable -Declared ([string]$Agent.executable)
        if (-not $exe) {
            return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'executable is absent' }
        }
        return [pscustomobject]@{ Id = $id; State = 'callable'; Detail = [string]$table[$id].Mode }
    }
    $surface = [string]$Agent.surfaceType
    if ($surface -eq 'companion-desktop' -or $surface -eq 'companion-ide') {
        return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'GUI host is not dispatched' }
    }
    if ($id -eq 'vscode-insiders' -or $id -eq 'warp') {
        return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'GUI host is not dispatched' }
    }
    return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'no verified headless contract' }
}

if ($List) {
    foreach ($agent in ($agents | Sort-Object { [string]$_.id })) {
        $row = Get-HostRow -Agent $agent
        Write-Output ("{0}`t{1}`t{2}" -f $row.Id, $row.State, $row.Detail)
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($HostId)) {
    Write-Refusal 3 'Pass -HostId, or -List to see which hosts are callable.'
}
$requested = $HostId.Trim()
if ($requested -in @('devin-cloud', 'jules', 'cursor-cloud', 'copilot-agent')) {
    Write-Refusal 3 "refused ${requested}: hosted cloud execution is disabled; owner must authorize this specific task, model, cadence, stop condition and cost budget before enabling a verified cloud adapter"
}
$agent = Get-AgentRecord -Agents $agents -Id $requested
if (-not $agent) { Write-Refusal 3 "refused ${requested}: unknown host" }

$script:ClineGuardEnv = @{ AGENTHUB_PEER_GUARD = '1'; CLINE_SESSION_BACKEND_MODE = 'local' }
if (-not $AnthropicApiKey -and -not [string]::IsNullOrWhiteSpace($Model) -and $requested -eq 'warp') {
    # Every Warp-hosted model spends Warp credits, so only the recorded
    # economical allowlist may be selected per task.
    $allowedModels = @()
    if ($dispatchPolicy -and $dispatchPolicy.PSObject.Properties['warp'] -and $dispatchPolicy.warp.PSObject.Properties['allowedModels']) {
        $allowedModels = @($dispatchPolicy.warp.allowedModels | ForEach-Object { [string]$_ })
    }
    if ($Model.Trim() -notin $allowedModels) { Write-Refusal 3 "refused warp: $($Model.Trim()) is not in dispatchPolicy.warp.allowedModels" }
    $script:WarpModel = $Model.Trim()
} elseif (-not $AnthropicApiKey -and -not [string]::IsNullOrWhiteSpace($Model) -and $requested -eq 'cline') {
    # Provider id plus model: on provider cline only ':free' ids are recorded,
    # because every other model there bills usage credit.
    $allowedModels = @()
    if ($dispatchPolicy -and $dispatchPolicy.PSObject.Properties['cline'] -and $dispatchPolicy.cline.PSObject.Properties['allowedModels']) {
        $allowedModels = @($dispatchPolicy.cline.allowedModels | ForEach-Object { [string]$_ })
    }
    $choice = $Model.Trim()
    if ($choice -notin $allowedModels) { Write-Refusal 3 "refused cline: $choice is not in dispatchPolicy.cline.allowedModels (use provider:model)" }
    $split = $choice.IndexOf(':')
    $script:ClineProvider = $choice.Substring(0, $split)
    $script:ClineModel = $choice.Substring($split + 1)
} elseif (-not $AnthropicApiKey -and -not [string]::IsNullOrWhiteSpace($Model)) {
    if ($requested -notin @('opencode', 'factory', 'devin')) { Write-Refusal 3 '-Model applies only to an -AnthropicApiKey run or an allowed OpenCode, Cline, Warp, Factory or Devin model.' }
    # Governed routing is per task, but only within the owner's recorded
    # allowlist: a model outside it could bill beyond the recorded allowance.
    $allowedModels = @()
    if ($dispatchPolicy -and $dispatchPolicy.PSObject.Properties[$requested] -and $dispatchPolicy.$requested.PSObject.Properties['allowedModels']) {
        $allowedModels = @($dispatchPolicy.$requested.allowedModels | ForEach-Object { [string]$_ })
    }
    if ($Model.Trim() -notin $allowedModels) { Write-Refusal 3 "refused ${requested}: $($Model.Trim()) is not in dispatchPolicy.${requested}.allowedModels" }
    if ($requested -eq 'opencode') { $script:OpenCodeModel = $Model.Trim() }
    if ($requested -eq 'factory') { $script:FactoryModel = $Model.Trim() }
    if ($requested -eq 'devin') { $script:DevinModel = $Model.Trim() }
}
if (-not [string]::IsNullOrWhiteSpace($Title) -and $requested -ne 'opencode') {
    Write-Refusal 3 '-Title applies only to -HostId opencode.'
}
if ($AnthropicApiKey) {
    # OWNER DIRECTION 2026-10-24: the Anthropic key is shared promotional credit.
    # It is used only when a caller passes this switch for this one run.
    if ($requested -ne 'claude') { Write-Refusal 3 "refused ${requested}: -AnthropicApiKey applies only to -HostId claude" }
    $optIn = $null
    if ($dispatchPolicy -and $dispatchPolicy.PSObject.Properties['claude']) { $optIn = $dispatchPolicy.claude.apiKeyOptIn }
    if (-not $optIn) { Write-Refusal 3 'refused claude: dispatchPolicy.claude.apiKeyOptIn is not recorded; the API-key route is not authorized' }
    $expires = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$optIn.expiresUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$expires)) {
        Write-Refusal 3 'refused claude: apiKeyOptIn.expiresUtc is missing or invalid'
    }
    if ([DateTimeOffset]::UtcNow -ge $expires) {
        Write-Refusal 3 "refused claude: the API-key opt-in expired at $($expires.ToString('u')); the owner must re-authorize it"
    }
    if ([string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) { Write-Refusal 3 'refused claude: ANTHROPIC_API_KEY is not set in this environment' }
    $script:ClaudeApiKeyModel = if (-not [string]::IsNullOrWhiteSpace($Model)) { $Model.Trim() } else { [string]$optIn.model }
    if ([string]::IsNullOrWhiteSpace($script:ClaudeApiKeyModel)) { Write-Refusal 3 'refused claude: no model; pass -Model or record apiKeyOptIn.model' }
    $script:ClaudeApiKeyOptIn = $true
}

$row = Get-HostRow -Agent $agent
if ($row.State -eq 'refused') { Write-Refusal 3 "refused ${requested}: $($row.Detail)" }
if ($PSBoundParameters.ContainsKey('SessionId') -and ($requested -ne 'cline' -or [string]::IsNullOrWhiteSpace($SessionId))) {
    Write-Refusal 3 '-SessionId requires -HostId cline and a non-empty session id.'
}

$targetId = if ($row.State -eq 'routed') { $row.Detail } else { $requested }
$targetAgent = Get-AgentRecord -Agents $agents -Id $targetId
$executable = Resolve-DeclaredExecutable -Declared ([string]$targetAgent.executable)
if (-not $executable) { Write-Refusal 2 "refused ${targetId}: executable is absent" }

if ($ShowCommand -and [string]::IsNullOrWhiteSpace($Prompt) -and [string]::IsNullOrWhiteSpace($PromptFile)) {
    $Prompt = 'ping'
}
if (-not [string]::IsNullOrWhiteSpace($Prompt) -and -not [string]::IsNullOrWhiteSpace($PromptFile)) {
    Write-Refusal 3 'Pass -Prompt or -PromptFile, not both.'
}
if (-not [string]::IsNullOrWhiteSpace($PromptFile)) {
    if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
        Write-Refusal 3 "prompt file not found: $PromptFile"
    }
    $Prompt = [IO.File]::ReadAllText($PromptFile)
}
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    Write-Refusal 3 'Pass -Prompt or -PromptFile.'
}
if ([string]::IsNullOrWhiteSpace($Cwd)) { $Cwd = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Cwd -PathType Container)) {
    Write-Refusal 3 "working directory not found: $Cwd"
}
$Cwd = (Resolve-Path -LiteralPath $Cwd).Path
if ($TimeoutSec -lt 1) { Write-Refusal 3 '-TimeoutSec must be at least 1.' }

$contract = $table[$targetId]
if (-not $contract) { Write-Refusal 3 "refused ${targetId}: no verified headless contract" }
$pointer = -not $SessionId -and $contract.Mode -eq 'argument' -and ($PromptFile -or -not (Test-ArgumentPrompt $Prompt))

$runDir = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub\runtime\coding-agent-dispatch'
$promptFile = $null
if ($contract.Mode -eq 'file' -or $pointer) {
    if (-not $ShowCommand) {
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $promptFile = Join-Path $runDir ("prompt-{0}-{1}.txt" -f $targetId, ([guid]::NewGuid().ToString('n')))
    } else {
        $promptFile = Join-Path $runDir 'prompt-show.txt'
    }
}
$taskText = $Prompt
if ($pointer) { $Prompt = "Read the task from this UTF-8 file and carry it out: $promptFile" }

$built = & $contract.Build $Prompt $Cwd $promptFile
# Write the task only after Build has accepted the policy: a refusing Build
# must not leave a prompt file behind, and the run's finally block below does
# not exist yet at that point. Pointer hosts write the task text captured
# before the pointer substitution above replaced $Prompt.
if (-not $ShowCommand -and $promptFile -and ($contract.Mode -eq 'file' -or $pointer)) {
    [IO.File]::WriteAllText($promptFile, $taskText, [Text.UTF8Encoding]::new($false))
}
if ($SessionId) {
    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { Write-Refusal 2 'Cline ACP resume requires Node.js.' }
    $built = @{
        Args = @((Join-Path $PSScriptRoot 'cline\acp-dispatch.mjs'))
        Stdin = (@{ executable = $executable; sessionId = $SessionId; cwd = $Cwd; prompt = $Prompt; timeoutMs = ($TimeoutSec * 1000)
            provider = $(if ($script:ClineProvider) { $script:ClineProvider } else { [string]$fleet.hostSettings.cline.provider })
            model = $(if ($script:ClineModel) { $script:ClineModel } else { [string]$fleet.hostSettings.cline.model }) } | ConvertTo-Json -Compress)
        PromptFile = $null
        Env = $script:ClineGuardEnv
    }
    $executable = [string]$node.Source
}
if ($row.State -eq 'routed') { Write-Output ("routed: {0} -> {1}" -f $requested, $targetId) }
if ($ShowCommand) {
    Write-Output ("file={0}" -f $executable)
    Write-Output ("args={0}" -f (Join-WindowsArguments $built.Args))
    Write-Output ("stdin={0}" -f ($(if ($built.Stdin) { 'yes' } else { 'no' })))
    exit 0
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('n').Substring(0, 8)
$stdoutPath = Join-Path $runDir "$stamp-$targetId.out"
$stderrPath = Join-Path $runDir "$stamp-$targetId.err"
$settingsFile = $built.SettingsFile
$isBatch = $isWindowsHost -and $executable -match '\.(cmd|bat)$'
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = $Cwd
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $true
$psi.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
$psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
# OWNER RULE 2026-10-22: every agent runs on its account/plan login, never a provider API key.
# Strip provider keys from the child environment so a key in the User environment cannot
# override the account login (Devin used DEVIN_API_KEY; Codex's wrapper used OPENAI_API_KEY).
# OpenCode 2 uses native Console account OAuth and a Go-only provider endpoint.
# Remove both provider overrides so they cannot replace the stored account.
# Exception (owner direction 2026-10-24): an explicit -AnthropicApiKey claude run keeps
# ANTHROPIC_API_KEY; ANTHROPIC_API_KEY_BACKUP is still removed.
$accountScrub = @{
    'claude'       = @('ANTHROPIC_API_KEY', 'ANTHROPIC_API_KEY_BACKUP')
    'codex'        = @('OPENAI_API_KEY')
    'cline'        = @('CLINE_API_KEY', 'OPENROUTER_API_KEY', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'DEEPSEEK_API_KEY')
    'devin'        = @('DEVIN_API_KEY', 'DEVIN_API_TOKEN', 'DEVIN_SERVICE_USER_TOKEN', 'DEVIN_ORG_ID')
    'gemini'       = @('GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_GENERATIVE_AI_API_KEY')
    'antigravity'  = @('GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_GENERATIVE_AI_API_KEY')
    'warp'         = @('WARP_API_KEY', 'GH_TOKEN', 'GITHUB_TOKEN')
    'grok'         = @('XAI_API_KEY')
    'factory'      = @('FACTORY_API_KEY')
    'cursor-agent' = @('CURSOR_API_KEY')
    'amp'          = @('AMP_API_KEY')
    'copilot'      = @('GH_TOKEN', 'GITHUB_TOKEN')
    'opencode'     = @('OPENCODE_GO_API_KEY', 'OPENCODE_API_KEY')
}
if ($accountScrub.ContainsKey($targetId)) {
    foreach ($name in $accountScrub[$targetId]) {
        if ($script:ClaudeApiKeyOptIn -and $targetId -eq 'claude' -and $name -eq 'ANTHROPIC_API_KEY') { continue }
        [void]$psi.EnvironmentVariables.Remove($name)
    }
}
# Copilot runs on the sh-pendoah GitHub account (owner direction 2026-10-22). The token is read
# from gh's keyring at launch, placed only in the child environment, and never printed.
if ($targetId -eq 'copilot') {
    $pendoahToken = if (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue) { (& gh auth token --user sh-pendoah 2>$null) } else { $null }
    if ($pendoahToken) { $psi.EnvironmentVariables['COPILOT_GITHUB_TOKEN'] = ([string]$pendoahToken).Trim() }
    else { Write-Refusal 3 'copilot: gh has no token for account sh-pendoah; run gh auth login for it.' }
}
if ($built.Env) {
    foreach ($name in $built.Env.Keys) { $psi.EnvironmentVariables[$name] = [string]$built.Env[$name] }
}
if ($isBatch) {
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $inner = (Format-WindowsArgument $executable) + ' ' + (Join-WindowsArguments $built.Args)
    $psi.Arguments = '/d /s /c "' + $inner + '"'
} elseif ($isWindowsHost) {
    $psi.FileName = $executable
    $psi.Arguments = Join-WindowsArguments $built.Args
} else {
    # macOS/Linux take an argv vector directly; no command-line quoting applies.
    $psi.FileName = $executable
    foreach ($argument in @($built.Args)) { $psi.ArgumentList.Add([string]$argument) }
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $psi
try {
    if ($settingsFile) {
        [IO.File]::WriteAllText($settingsFile, '{"amp.mcpServers":{}}', [Text.UTF8Encoding]::new($false))
    }
    if (-not $process.Start()) { Write-Refusal 2 "refused ${targetId}: process did not start" }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $inputTask = if ($built.Stdin) { $process.StandardInput.WriteAsync([string]$built.Stdin) } else { $null }
    # Bounded stdin prevents a non-reading child from defeating TimeoutSec.
    $inputFinished = -not $inputTask -or $inputTask.Wait($TimeoutSec * 1000)
    if ($inputFinished) { $process.StandardInput.Close() }
    $remaining = [Math]::Max(0, $TimeoutSec * 1000 - [int]$timer.ElapsedMilliseconds)
    $finished = $process.WaitForExit($remaining)
    if (-not $finished) {
        if ($isWindowsHost) {
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            $killInfo = [Diagnostics.ProcessStartInfo]::new()
            $killInfo.FileName = $taskkill
            $killInfo.Arguments = "/PID $($process.Id) /T /F"
            $killInfo.UseShellExecute = $false
            $killInfo.CreateNoWindow = $true
            $killInfo.RedirectStandardOutput = $true
            $killInfo.RedirectStandardError = $true
            $killer = [Diagnostics.Process]::Start($killInfo)
            $null = $killer.WaitForExit(5000)
            $killer.Dispose()
        } else {
            try { $process.Kill($true) } catch [InvalidOperationException] { }
        }
        $null = $process.WaitForExit(5000)
        [Console]::Error.WriteLine("timeout ${targetId} after ${TimeoutSec}s; process tree killed")
        $exitCode = 4
    } else {
        $exitCode = $process.ExitCode
        if ($exitCode -in 2, 3, 4) { $exitCode = 1 }
    }
    try { $null = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000) } catch {}
    $stdoutText = if ($stdoutTask.Status -eq 'RanToCompletion') { $stdoutTask.Result } else { '' }
    $stderrText = if ($stderrTask.Status -eq 'RanToCompletion') { $stderrTask.Result } else { '' }
    [IO.File]::WriteAllText($stdoutPath, $stdoutText, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderrText, [Text.UTF8Encoding]::new($false))
    if ($stdoutText) { [Console]::Out.Write($stdoutText) }
    if ($stderrText) { [Console]::Error.Write($stderrText) }
    exit $exitCode
} finally {
    if ($promptFile -and (Test-Path -LiteralPath $promptFile)) {
        Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
    }
    if ($settingsFile -and (Test-Path -LiteralPath $settingsFile)) {
        Remove-Item -LiteralPath $settingsFile -Force -ErrorAction SilentlyContinue
    }
    $process.Dispose()
}
