#Requires -Version 5.1
<#
.SYNOPSIS
  Run one coding-agent host from another, windowless.

.DESCRIPTION
  Claude and Codex are the primary orchestrators. Any host that can run this
  script can call a host whose headless command was verified on this machine
  on 2026-10-14. Hosts without that evidence are refused. Cursor routes to
  cursor-agent and Windsurf routes to the local Devin CLI. GUI hosts are refused.

  Remote cloud agents are refused, with one exception: -HostId devin-cloud
  (SH-4969, owner direction 2026-11-19) creates one Devin Cloud session through
  Invoke-DevinCloud.ps1 when dispatchPolicy.devin-cloud is enabled and carries
  its cloudBudgetAuthorization (default max_acu_limit 10, at most 3 concurrent
  agenthub sessions). A local headless contract does not authorize a hosted
  computer, background agent, or paid-credit run.

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
  With -ReadOnly, print only the callable and routed hosts that have an
  enforced read-only mode (same three columns).

.PARAMETER ShowCommand
  Print the file and arguments that would run, then exit. No process starts.

.PARAMETER Auth
    Print sign-in or provider setup commands for the selected surface.

.PARAMETER ZCodeBrowser
  Enable ZCode native headless Browser Use in a fresh browser profile.

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
  For codex, grok, opencode, cline, warp, factory, devin, kilo, mimo-code and qwen, the model the host should run this task on. Any model the host can
  reach is accepted and passed through (owner direction 2026-11-10: a model or
  coding plan is allowed wherever it can be integrated and supported).
  dispatchPolicy.<host>.allowedModels records the smoke-verified models; it
  does not restrict the choice. A model outside it adds one stderr note and
  the run continues. The host and its plan decide what the model costs.
  Only the shape is checked, to protect the command line: no whitespace or
  shell metacharacters, provider/model for opencode, kilo and mimo-code (a
  bare id is refused), and provider:model for cline (for example
  cline:poolside/laguna-s-2.1:free). A malformed id is refused.
  Without -Model the host runs on its recorded default (dispatchPolicy.<host>.model,
  hostSettings.cline for cline, the host's own default for codex and grok).
  Two refusals remain, both about money (owner direction 2026-11-10:
  subscriptions only, never a pay-as-you-go wallet). OpenCode refuses provider
  opencode/, the Zen wallet; use opencode-go/<model>, the Go subscription. A
  MiMo-routed model on any host must run on the Xiaomi Token Plan: provider
  xiaomi/ is refused, MIMO_BASE_URL, when set, must name a
  token-plan-<region>.xiaomimimo.com host, and MIMO_API_KEY, when set, must
  start with tp- or ttp-. The values are never printed.

.PARAMETER Title
  Session title for -HostId opencode, so the run is findable in the shared
  service from the TUI and Desktop, or for -HostId devin-cloud. Refused for
  other hosts.

.PARAMETER RunId
  -HostId devin-cloud only. Tags the session run:<RunId>; a second create with
  the same run id returns the existing session instead of a duplicate. When
  omitted, the adapter derives it from the prompt, repos and title, so an
  identical retry dedupes.

.PARAMETER MaxAcu
  -HostId devin-cloud only. Per-session max_acu_limit as a positive whole
  number (2.5, 1e3 and abc refuse with exit 3); the default is
  cloudBudgetAuthorization.defaultMaxAcuLimit (10). Pass a higher value only
  when the task authorizes it. DEVIN_CLOUD_API_KEY, when set in this process,
  is removed before any child starts and handed only to the adapter.

.PARAMETER Repo
  -HostId devin-cloud only. owner/name repositories for the session; derived
  from the -Cwd git remote when omitted.

.PARAMETER SchemaFile
  -HostId devin-cloud only. JSON Schema file sent as structured_output_schema.

.PARAMETER SessionId
  Continue an existing Cline session through ACP. Policy gates still apply.

.PARAMETER Role
  OpenCode: peer (default), engineer, reviewer, tester or researcher. peer
  runs the guarded dispatchPolicy.opencode.agent profile. Every other role
  runs the V2 agent named by dispatchPolicy.opencode.roles.<role> and is
  refused when that agent file is missing from ~/.config/opencode/agents.
  -ReadOnly additionally uses dispatchPolicy.opencode.roles.readonly, the
  enforced read-only agent (no shell, no edit); it is not selectable through
  -Role. The legacy zai-coding-plan launcher route (OpenCode 1.x) has no V2
  agents and refuses every role but peer.
  Any other host refuses a role other than peer.

.PARAMETER ReadOnly
  Run the host in a read-only mode the host itself enforces; prompt wording
  is never the mechanism. A host qualifies only when this script has a
  verified read-only command for it and dispatchPolicy.<host>.readOnly
  records the flags. Every other host is refused with exit 3; there is no
  fallback to a writable run. OpenCode runs the readonly agent (read and
  search only) and is refused unless the installed readonly profile's own
  ordered frontmatter permissions effectively deny the edit, shell and
  subagent actions; -ReadOnly with a writing role is refused. -ReadOnly cannot
  resume a Cline session.

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
    [string]$Role,
    [switch]$ReadOnly,
    [switch]$ZCodeBrowser,
    [string]$RunId,
    [string]$MaxAcu,
    [string[]]$Repo,
    [string]$SchemaFile,
    [switch]$List,
    [switch]$ShowCommand,
    [switch]$Forge,
    [switch]$Auth
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

# SH-4969: an in-process Devin Cloud key override must reach no child this
# script starts (host CLIs, ssh, gh, node). It is taken out of the environment
# here and handed back only to the in-process devin-cloud adapter, which
# consumes it before starting any child of its own.
$script:DevinCloudKeyOverride = [Environment]::GetEnvironmentVariable('DEVIN_CLOUD_API_KEY', 'Process')
[Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $null, 'Process')

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

if ($Forge) {
    $forgeCatalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'forge-hosts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ($Auth) {
    if ($Prompt -or $PromptFile -or $Cwd -or $List -or $ShowCommand -or $ReadOnly -or
        $Role -or $Title -or $SessionId -or $Model -or $AnthropicApiKey -or
        $RunId -or $Repo -or $SchemaFile -or $PSBoundParameters.ContainsKey('MaxAcu') -or
        $PSBoundParameters.ContainsKey('TimeoutSec')) {
        Write-Refusal 3 'Use -Auth with only optional -Forge and -HostId.'
    }
    $authCommands = if ($Forge) {
        [ordered]@{
            grok = '/srv/work/agenthub-runner/.grok/bin/grok login --device-auth'
            codex = 'Use a codex-qwen, codex-zai, codex-mimo or codex-go launcher; no personal OpenAI login on Forge.'
            claude = 'Use a claude-qwen, claude-zai, claude-mimo or claude-go launcher; no personal Anthropic login on Forge.'
            qwen = '/srv/work/agenthub-runner/.local/bin/qwen; run /auth and choose QwenCloud Token Plan'
            cline = '/srv/work/agenthub-runner/.local/bin/cline auth'
            opencode = '/srv/work/agenthub-runner/.local/bin/opencode; run /connect and choose the intended provider'
            github = 'gh auth status; gh auth login --hostname github.com --git-protocol https --web; gh auth setup-git'
            linear = '/srv/work/agenthub-runner/.local/bin/codex mcp login linear'
            'opencode-qwen' = '/srv/work/agenthub-runner/.local/bin/opencode-qwen; uses the Forge Qwen runtime credential'
            'opencode-zai' = '/srv/work/agenthub-runner/.local/bin/opencode-zai; uses the Forge Z.ai Coding Plan runtime credential'
        }
    } else {
        [ordered]@{
            grok = 'grok login'
            codex = 'codex login; check with codex login status'
            claude = 'claude auth login; check with claude auth status'
            qwen = 'qwen; run /auth and choose QwenCloud Token Plan'
            mimo = 'mimo providers; select the MiMo Token Plan'
            cline = 'cline auth'
            opencode = 'opencode; run /connect and choose the intended provider'
            'opencode-zai' = 'Use -HostId opencode -Model zai-coding-plan/glm-5.3; the Windows launcher reads ZAI_CODING_PLAN_API_KEY.'
            github = 'gh auth status; gh auth login if needed'
            'codex-qwen' = 'codex --profile qwen; uses QWEN_TOKEN_PLAN_API_KEY'
        }
    }
    if ($Forge) {
        foreach ($entry in $forgeCatalog.PSObject.Properties) {
            if ($entry.Value.plan) {
                $authCommands[$entry.Name] = "/srv/work/agenthub-runner/$($entry.Value.argv[0]); uses the Forge $($entry.Value.plan) runtime credential."
            }
        }
    }
    if ($HostId -and -not $authCommands.Contains($HostId)) {
        Write-Refusal 3 'No sign-in command recorded for this host. Run -Auth to list supported entries.'
    }
    if ($Forge) {
        Write-Output 'Run these on Forge as agenthub-runner with HOME=/srv/work/agenthub-runner.'
    }
    foreach ($entry in $authCommands.GetEnumerator()) {
        if (-not $HostId -or $entry.Key -eq $HostId) {
            Write-Output "$($entry.Key)`t$($entry.Value)"
        }
    }
    exit 0
}

if ($Forge) {
    # This route opens an operator session. Prompt-based jobs and reviewer
    # roles require a separate Linux worker contract and provider acceptance.
    if ($Prompt -or $PromptFile -or $ReadOnly -or $Role -or $Title -or $SessionId -or
        $Model -or $AnthropicApiKey -or $RunId -or $Repo -or $SchemaFile -or
        $PSBoundParameters.ContainsKey('MaxAcu') -or $PSBoundParameters.ContainsKey('TimeoutSec')) {
        Write-Refusal 3 'Forge supports interactive sessions only. Select the provider and model inside the agent.'
    }
    $forgeHosts = [ordered]@{}
    foreach ($entry in $forgeCatalog.PSObject.Properties) {
        $forgeHosts[$entry.Name] = $entry.Value.argv -join ' '
    }
    $forgeHome = '/srv/work/agenthub-runner'
    $runner = "runuser -u agenthub-runner -- env -i HOME=$forgeHome TERM=xterm-256color PATH=$forgeHome/.local/bin:/usr/bin:/bin"
    if ($List) {
        if ($HostId -or $Cwd -or $ShowCommand) { Write-Refusal 3 'Use -Forge -List without a host, directory, or preview flag.' }
        $commands = foreach ($entry in $forgeHosts.GetEnumerator()) {
            $binary = ($entry.Value -split ' ')[0]
            "if test -x $forgeHome/$binary; then printf '%s\tinteractive\t%s\n' '$($entry.Key)' 'installed; auth unverified'; else printf '%s\trefused\t%s\n' '$($entry.Key)' 'executable absent'; fi"
        }
        $inventory = [Diagnostics.ProcessStartInfo]::new()
        $inventory.FileName = (Get-Command ssh -CommandType Application).Source
        $inventory.UseShellExecute = $false
        $inventory.CreateNoWindow = $true
        $inventory.RedirectStandardOutput = $true
        $inventory.RedirectStandardError = $true
        $inventoryArgs = @('-nT', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'forge', ($commands -join '; '))
        if ($env:OS -eq 'Windows_NT') {
            $inventory.Arguments = Join-WindowsArguments $inventoryArgs
        } else {
            foreach ($argument in $inventoryArgs) { $inventory.ArgumentList.Add($argument) }
        }
        $process = [Diagnostics.Process]::Start($inventory)
        try {
            $output = $process.StandardOutput.ReadToEndAsync()
            $errors = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(15000)) {
                $process.Kill()
                Write-Refusal 4 'Forge inventory timed out.'
            }
            [Console]::Error.Write($errors.GetAwaiter().GetResult())
            Write-Output ($output.GetAwaiter().GetResult().TrimEnd())
            exit $process.ExitCode
        } finally {
            $process.Dispose()
        }
    }
    if (-not $HostId -or -not $forgeHosts.Contains($HostId)) {
        if ($HostId -in @('codex', 'claude')) {
            Write-Refusal 3 "Select a Forge provider explicitly, for example '$HostId-zai'. Run -Forge -List."
        }
        Write-Refusal 3 'Use -Forge -List to see supported Forge hosts.'
    }
    if ($Cwd -cnotmatch '^/srv/work/agenthub-runner/worktrees/[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\z') {
        Write-Refusal 3 'Pass a Forge worktree path under /srv/work/agenthub-runner/worktrees using letters, digits, underscores or hyphens.'
    }
    $command = "$runner bash --noprofile --norc -c 'cd -- $Cwd && test `"`$(pwd -P)`" = $Cwd && exec $forgeHome/$($forgeHosts[$HostId])'"
    if ($ShowCommand) {
        Write-Output "ssh -t -o BatchMode=yes -o ConnectTimeout=10 forge $command"
        exit 0
    }
    & ssh -t -o BatchMode=yes -o ConnectTimeout=10 forge $command
    exit $LASTEXITCODE
}

# A model id only has to be safe on the command line and in the shape the host
# parses. Which models a task may name is not restricted here (owner direction
# 2026-11-10); dispatchPolicy.<host>.allowedModels records what was smoke-verified.
function Get-DispatchModelShape {
    param([string]$Id)
    if ($Id -in @('opencode', 'kilo', 'mimo-code')) {
        return @{ Pattern = '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$'; Label = 'a provider/model id' }
    }
    if ($Id -eq 'cline') {
        return @{ Pattern = '^[A-Za-z0-9][A-Za-z0-9_.-]*:[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$'; Label = 'a provider:model id' }
    }
    return @{ Pattern = '^[A-Za-z0-9][A-Za-z0-9_.:/@+-]*$'; Label = 'a model id without whitespace or shell metacharacters' }
}

function Assert-DispatchModelId {
    param([string]$Id, [string]$ModelId, [string]$Source = '-Model')
    $shape = Get-DispatchModelShape $Id
    if ($ModelId -notmatch $shape.Pattern) {
        Write-Refusal 3 "refused ${Id}: $Source '$ModelId' is malformed; it must be $($shape.Label)"
    }
}

$script:UnlistedModelNoted = @{}
function Write-UnlistedModelNote {
    param([string]$Id, [string]$ModelId)
    $listed = @()
    $policy = $script:dispatchPolicy
    if ($policy -and $policy.PSObject.Properties[$Id] -and $policy.$Id -isnot [string] -and $policy.$Id.PSObject.Properties['allowedModels']) {
        $listed = @($policy.$Id.allowedModels | ForEach-Object { [string]$_ })
    }
    if ($ModelId -in $listed) { return }
    $key = "$Id|$ModelId"
    if ($script:UnlistedModelNoted.ContainsKey($key)) { return }
    $script:UnlistedModelNoted[$key] = $true
    [Console]::Error.WriteLine("note: $Id model '$ModelId' is not in the smoke-verified list; passing it through (owner direction 2026-11-10)")
}

# OWNER DIRECTION 2026-11-10: subscriptions only, never a pay-as-you-go wallet.
# These are the only model refusals besides a malformed id.
function Get-DispatchModelProvider {
    param([string]$Id, [string]$ModelId)
    $separator = if ($Id -eq 'cline') { ':' } else { '/' }
    $index = $ModelId.IndexOf($separator)
    if ($index -gt 0) { return $ModelId.Substring(0, $index) }
    return ''
}

function Assert-SubscriptionRoute {
    param([string]$Id, [string]$ModelId)
    if ([string]::IsNullOrWhiteSpace($ModelId)) { return }
    $provider = Get-DispatchModelProvider -Id $Id -ModelId $ModelId
    if ($Id -eq 'opencode' -and $provider -eq 'opencode') {
        Write-Refusal 3 "refused opencode: model '$ModelId' uses provider opencode/, the pay-as-you-go Zen wallet; use opencode-go/<model>, the Go subscription (subscriptions only, owner direction 2026-11-10)"
    }
    # A MiMo route is named by its provider segment, or by the whole id on a
    # host whose model ids carry no provider (Codex, Factory).
    $route = if ($provider) { $provider } else { $ModelId }
    if ($route -notmatch '(?i)mimo|xiaomi') { return }
    # MiMo Code lists provider xiaomi beside xiaomi-token-plan-<region>; the
    # plain one is the pay-as-you-go API.
    if ($provider -eq 'xiaomi') {
        Write-Refusal 3 "refused ${Id}: model '$ModelId' uses provider xiaomi/, the pay-as-you-go MiMo API; use the Token Plan provider (subscriptions only, owner direction 2026-11-10)"
    }
    Assert-MimoPlanEnvironment -Id $Id
}

# OpenCode V2 agent permissions are an ordered list in the Markdown frontmatter
# and the last matching rule wins. A substring search over the raw file is not
# evidence: the deny text could sit in a comment or body, and a later allow rule
# could re-open the action. This parses the frontmatter rules and returns $true
# only when the last blanket rule (resource "*") covering $Action denies it and
# no later rule re-allows the action for any resource. Conservative by design:
# a narrower allow after the blanket deny is refused too, because proving glob
# coverage is out of scope for the gate.
function Test-OpenCodeProfileDenies {
    param([string]$Text, [string]$Action)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---') { return $false }
    $frontMatter = $Matches[1]
    $rules = @()
    foreach ($line in ($frontMatter -split '\r?\n')) {
        if ($line -match '^\s*-\s*\{\s*action:\s*"?([^",}]+?)"?\s*,\s*resource:\s*"([^"]*)"\s*,\s*effect:\s*(allow|deny)\s*\}\s*$') {
            $rules += , [pscustomobject]@{ Action = $Matches[1].Trim(); Resource = $Matches[2].Trim(); Effect = $Matches[3] }
        }
    }
    if ($rules.Count -eq 0) { return $false }
    $lastBlanket = -1
    for ($i = 0; $i -lt $rules.Count; $i++) {
        $r = $rules[$i]
        if ($r.Resource -eq '*' -and ($r.Action -ceq $Action -or $r.Action -eq '*')) { $lastBlanket = $i }
    }
    if ($lastBlanket -lt 0 -or $rules[$lastBlanket].Effect -ne 'deny') { return $false }
    for ($i = $lastBlanket + 1; $i -lt $rules.Count; $i++) {
        $r = $rules[$i]
        if ($r.Effect -eq 'allow' -and ($r.Action -ceq $Action -or $r.Action -eq '*')) { return $false }
    }
    return $true
}

# Restricted OpenCode runs use a real allow-list, not a list of known denies:
# new plugin/MCP/host actions must remain denied without dispatcher updates.
# Read/glob are the only permitted actions, and secret/auth read exceptions
# must follow the broad read allow so last-match semantics preserve them.
function Test-OpenCodeProfileIsReadOnly {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---') { return $false }
    $frontMatter = $Matches[1]
    $rules = @()
    foreach ($line in ($frontMatter -split '\r?\n')) {
        if ($line -notmatch '^\s*-\s') { continue }
        # Restricted profiles use one explicit flow-rule per list item. Reject
        # unknown effects (including `ask`) and alternate/multiline YAML forms;
        # silently skipping one would let `--auto` approve it at runtime.
        if ($line -notmatch '^\s*-\s*\{\s*action:\s*"?([^",}]+?)"?\s*,\s*resource:\s*"([^"]*)"\s*,\s*effect:\s*(allow|deny)\s*\}\s*$') { return $false }
        $rules += , [pscustomobject]@{ Action = $Matches[1].Trim(); Resource = $Matches[2].Trim(); Effect = $Matches[3]; Index = $rules.Count }
    }
    $denyIndex = -1
    for ($i = 0; $i -lt $rules.Count; $i++) {
        if ($rules[$i].Action -eq '*' -and $rules[$i].Resource -eq '*' -and $rules[$i].Effect -eq 'deny') { $denyIndex = $i; break }
    }
    if ($denyIndex -lt 0) { return $false }
    $allowsRead = $false; $allowsGlob = $false; $readAllowIndex = -1
    for ($i = $denyIndex + 1; $i -lt $rules.Count; $i++) {
        $r = $rules[$i]
        if ($r.Effect -ne 'allow') { continue }
        if ($r.Action -notin @('read', 'glob')) { return $false }
        if ($r.Resource -ne '*' -and -not ($r.Action -eq 'read' -and $r.Resource -eq '*.env.example')) { return $false }
        if ($r.Action -eq 'read') { $allowsRead = $true; if ($r.Resource -eq '*') { $readAllowIndex = $i } }
        if ($r.Action -eq 'glob') { $allowsGlob = $true }
    }
    if (-not ($allowsRead -and $allowsGlob)) { return $false }
    if ($readAllowIndex -lt 0) { return $false }
    foreach ($protected in @(
        @{ Action = 'read'; Resource = '*.env'; Effect = 'deny' },
        @{ Action = 'read'; Resource = '*.env.*'; Effect = 'deny' },
        @{ Action = 'read'; Resource = '*.env.example'; Effect = 'allow' },
        @{ Action = 'read'; Resource = '*/opencode/auth.json'; Effect = 'deny' },
        @{ Action = 'read'; Resource = '*/opencode/mcp-auth.json'; Effect = 'deny' }
    )) {
        $matches = @($rules | Where-Object { $_.Action -eq $protected.Action -and $_.Resource -eq $protected.Resource })
        if (-not $matches.Count -or $matches[-1].Effect -ne $protected.Effect) { return $false }
        if ($protected.Resource -eq '*.env.example') {
            if ($matches[-1].Index -le $readAllowIndex) { return $false }
            $envDeny = @($rules | Where-Object { $_.Action -eq 'read' -and $_.Resource -eq '*.env.*' -and $_.Effect -eq 'deny' })
            if (-not $envDeny.Count -or $matches[-1].Index -le $envDeny[-1].Index) { return $false }
        } elseif ($matches[-1].Effect -eq 'deny' -and $matches[-1].Index -le $readAllowIndex) {
            return $false
        }
    }
    foreach ($r in $rules) {
        if ($r.Action -eq 'read' -and $r.Resource -eq '*' -and $r.Effect -eq 'allow' -and $r.Index -gt $readAllowIndex) { return $false }
    }
    return $true
}

# Xiaomi: the Token Plan serves from token-plan-<region>.xiaomimimo.com with
# tp-/ttp- keys; pay-as-you-go uses api.xiaomimimo.com with sk- keys. Only the
# variable name is ever reported. -Required is for a host whose whole route is
# this environment (qwen): the variables must then be present, not only shaped.
function Assert-MimoPlanEnvironment {
    param([string]$Id, [switch]$Required)
    $baseUrl = [Environment]::GetEnvironmentVariable('MIMO_BASE_URL')
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        if ($Required) {
            Write-Refusal 3 "refused ${Id}: MIMO_BASE_URL is not set; this host reaches the Xiaomi Token Plan only through the child environment"
        }
    } else {
        $parsed = $null
        $isTokenPlanHost = [Uri]::TryCreate($baseUrl.Trim(), [UriKind]::Absolute, [ref]$parsed) -and
            $parsed.Scheme -ceq 'https' -and
            $parsed.Host.ToLowerInvariant() -match '^token-plan-[a-z0-9-]+\.xiaomimimo\.com$'
        if (-not $isTokenPlanHost) {
            Write-Refusal 3 "refused ${Id}: MIMO_BASE_URL does not name a Xiaomi Token Plan host (token-plan-<region>.xiaomimimo.com); a MiMo model runs on the Token Plan only, never the pay-as-you-go API"
        }
    }
    $planKey = [Environment]::GetEnvironmentVariable('MIMO_API_KEY')
    if ([string]::IsNullOrWhiteSpace($planKey)) {
        if ($Required) {
            Write-Refusal 3 "refused ${Id}: MIMO_API_KEY is not set; this host reaches the Xiaomi Token Plan only through the child environment"
        }
    } elseif (-not ($planKey.StartsWith('tp-', [StringComparison]::Ordinal) -or $planKey.StartsWith('ttp-', [StringComparison]::Ordinal))) {
        Write-Refusal 3 "refused ${Id}: MIMO_API_KEY is not a Xiaomi Token Plan key (tp- or ttp- prefix); a MiMo model runs on the Token Plan only, never a pay-as-you-go key"
    }
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
        'zcode' = @{
            Mode = 'direct-argument'
            Build = {
                param($PromptText, $Work, $File)
                $launch = Resolve-ZCodeLaunch $targetAgent
                $arguments = @()
                $childEnv = @{
                    ZCODE_BUILTIN_PROVIDER_CONFIG_FILE = $launch.Builtin
                    ZCODE_PERSONAL_PROVIDER_CONFIG_FILE = $launch.Personal
                }
                if ($ZCodeBrowser) {
                    $package = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'zcode/package.json') | ConvertFrom-Json
                    $version = $package.dependencies.'playwright-core'
                    $runtime = Join-Path (Get-AgentHubDefaultLocalData) "AgentHub/runtime/coding-agent-dispatch/zcode/playwright-$version"
                    if (-not (Test-Path -LiteralPath (Join-Path $runtime 'node_modules/playwright-core/index.mjs') -PathType Leaf)) {
                        Write-Refusal 3 'refused zcode: run zcode/Install-ZCodeBrowserRuntime.ps1 to install the pinned browser dependency'
                    }
                    $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
                    if (-not (Test-Path -LiteralPath $edge -PathType Leaf)) {
                        Write-Refusal 3 'refused zcode: Microsoft Edge is absent from its Windows installation path'
                    }
                    $loader = Join-Path $PSScriptRoot 'zcode/playwright-loader.mjs'
                    $arguments = @('--import', ([uri]::new($loader)).AbsoluteUri)
                    $childEnv.AGENTHUB_ZCODE_PLAYWRIGHT_ROOT = $runtime
                }
                $arguments += @($launch.Runtime, '--cwd', $Work, '--no-color', '--mode', 'guarded')
                if ($ZCodeBrowser) {
                    $arguments += @('--surface', 'desktop', '--browser-use', 'headless', '--browser-executable', $edge, '--no-browser-state')
                }
                @{ Args = $arguments + @('--prompt', $PromptText); Env = $childEnv }
            }
        }
        'claude' = @{
            Mode = 'stdin'
            ReadOnly = $true
            Build = {
                param($PromptText, $Work, $File)
                # claude --help 2026-11-11: --permission-mode lists plan, and
                # --permission-prompts none denies anything that would prompt
                # under --print. -ReadOnly swaps the bypass mode for both.
                $args = if ($ReadOnly) { @('--print', '--permission-mode', 'plan', '--permission-prompts', 'none') }
                    else { @('--print', '--permission-mode', 'bypassPermissions') }
                if ($script:ClaudeApiKeyModel) { $args += @('--model', $script:ClaudeApiKeyModel) }
                @{ Args = $args; Stdin = $PromptText; PromptFile = $null }
            }
        }
        'codex' = @{
            Mode = 'stdin'
            ReadOnly = $true
            Build = {
                param($PromptText, $Work, $File)
                # The shim selects a profile; cwd may legitimately be a
                # scratch directory. Do not initialize a repository there.
                # codex exec --help: -m, --model <MODEL>. Passed only when a
                # task names one; otherwise the shim's profile picks the model.
                $args = @('exec')
                if ($script:CodexModel) { $args += @('-m', $script:CodexModel) }
                # codex exec --help 2026-11-11: -s, --sandbox <SANDBOX_MODE>,
                # possible values read-only, workspace-write, danger-full-access.
                if ($ReadOnly) { $args += @('--sandbox', 'read-only') }
                $args += @('--skip-git-repo-check', '-')
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
        'grok' = @{
            Mode = 'file'
            Build = {
                param($PromptText, $Work, $File)
                # Local user guide 14-headless-mode.md: --prompt-file triggers headless.
                # Do not also pass -p; that puts the prompt on the command line.
                # grok --help: -m, --model <MODEL>. Passed only when a task names one.
                $args = @('--prompt-file', $File, '--yolo', '--cwd', $Work)
                if ($script:GrokModel) { $args += @('--model', $script:GrokModel) }
                @{ Args = $args; Stdin = $null; PromptFile = $File }
            }
        }
        'opencode' = @{
            Mode = 'argument'
            ReadOnly = $true
            Build = {
                param($PromptText, $Work, $File)
                # OpenCode 2 uses the child process working directory; --dir
                # belonged to v1 and is rejected by the shared-service CLI.
                # Native JSON events give callers reliable text/tool/usage
                # boundaries without parsing terminal-rendered output.
                $args = @('run', '--auto', '--format', 'json')
                $openCodeModel = if ($script:OpenCodeModel) { $script:OpenCodeModel } else { [string]$fleet.dispatchPolicy.opencode.model }
                Assert-SubscriptionRoute -Id 'opencode' -ModelId $openCodeModel
                if ($openCodeModel -like 'zai-coding-plan/*') {
                    # The installed Z.ai profile uses OpenCode 1.x. Keep its
                    # subscription and MCP settings separate from OpenCode Go.
                    $args = @('run', '--format', 'json')
                }
                if ($openCodeModel) { $args += @('--model', $openCodeModel) }
                # --auto approves every action a rule leaves at ask, so unattended
                # runs use the policy-named agent whose rules deny outward actions.
                # A -Role or -ReadOnly run swaps that agent for the mapped V2
                # profile (SH-4674); -ReadOnly always runs the readonly profile,
                # whose own permissions deny edit and shell for every resource
                # (the reviewer role keeps a shell and is NOT a read-only run).
                if (-not $zaiLauncher) {
                    $openCodeAgent = [string]$fleet.dispatchPolicy.opencode.agent
                    $openCodeRoleName = ''
                    if ($ReadOnly) { $openCodeRoleName = 'readonly' }
                    elseif ($script:DispatchRole -ne 'peer') { $openCodeRoleName = $script:DispatchRole }
                    if ($openCodeRoleName) {
                        $openCodePolicy = $fleet.dispatchPolicy.opencode
                        $roleAgent = ''
                        if ($openCodePolicy -and $openCodePolicy.PSObject.Properties['roles'] -and $openCodePolicy.roles -and $openCodePolicy.roles.PSObject.Properties[$openCodeRoleName]) {
                            $roleAgent = [string]$openCodePolicy.roles.$openCodeRoleName
                        }
                        if ($roleAgent -notmatch '^[A-Za-z0-9_-]+$') {
                            Write-Refusal 3 "refused opencode: dispatchPolicy.opencode.roles.$openCodeRoleName must name the agent profile for role '$openCodeRoleName'"
                        }
                        $openCodeAgentsDir = Join-Path (Join-Path (Join-Path (Get-AgentHubDefaultHome) '.config') 'opencode') 'agents'
                        $roleProfile = Join-Path $openCodeAgentsDir "$roleAgent.md"
                        if (-not (Test-Path -LiteralPath $roleProfile -PathType Leaf)) {
                            Write-Refusal 3 "refused opencode: role '$openCodeRoleName' needs the agent profile $roleAgent.md, which is missing from $openCodeAgentsDir; install it from packages/coding-agent-dispatch/opencode with Install-OpenCodeProfiles.ps1"
                        }
                        if ($ReadOnly -or $script:DispatchRole -eq 'reviewer') {
                            # The installed file is what OpenCode enforces, so it
                            # is the one checked: a restricted review run is
                            # refused unless the profile's ordered frontmatter
                            # permissions effectively deny edit, shell and
                            # subagent for every resource. Text outside the
                            # frontmatter or a later allow rule never satisfies
                            # this gate, and prompt wording is never the
                            # mechanism. The gate is the V2-permission check (no shell,
                            # no writable child, no write-through-command).
                            $profileText = $null
                            try { $profileText = Get-Content -LiteralPath $roleProfile -Raw -Encoding UTF8 } catch { $profileText = $null }
                            if (-not (Test-OpenCodeProfileDenies -Text $profileText -Action 'edit')) {
                                Write-Refusal 3 "refused opencode: the installed profile $roleAgent.md does not effectively deny the edit action for every resource, so a read-only run cannot be established"
                            }
                            if (-not (Test-OpenCodeProfileDenies -Text $profileText -Action 'shell')) {
                                Write-Refusal 3 "refused opencode: the installed profile $roleAgent.md does not effectively deny the shell action, so this restricted run could still change files through commands"
                            }
                            if (-not (Test-OpenCodeProfileDenies -Text $profileText -Action 'subagent')) {
                                Write-Refusal 3 "refused opencode: the installed profile $roleAgent.md does not effectively deny the subagent action, so this restricted run could delegate to a writable agent"
                            }
                            if (-not (Test-OpenCodeProfileDenies -Text $profileText -Action 'browser')) {
                                Write-Refusal 3 "refused opencode: the installed profile $roleAgent.md does not effectively deny the browser action, so a review could perform external actions"
                            }
                            if (-not (Test-OpenCodeProfileIsReadOnly -Text $profileText)) {
                                Write-Refusal 3 "refused opencode: the installed profile $roleAgent.md must deny every action by default and allow only read and glob, with secret and auth reads denied"
                            }
                        }
                        $openCodeAgent = $roleAgent
                    }
                    if ($openCodeAgent) { $args += @('--agent', $openCodeAgent) }
                } elseif ($script:DispatchRole -ne 'peer' -or $ReadOnly) {
                    Write-Refusal 3 'refused opencode: the legacy zai-coding-plan launcher runs OpenCode 1.x with an isolated config that has no V2 agent profiles; use a native OpenCode 2 route for -Role or -ReadOnly'
                }
                if (-not [string]::IsNullOrWhiteSpace($Title)) { $args += @('--title', $Title.Trim()) }
                if ($zaiLauncher -and $File) {
                    $args += @('--file', $File, '--')
                    $PromptText = 'Carry out the task in the attached prompt file.'
                } elseif ($File) {
                    # Attach dispatcher pointer prompts in the CLI layer. This
                    # avoids granting an external_directory permission to the
                    # restricted agent merely to read its runtime task file.
                    $args += @('--file', $File)
                    $PromptText = 'Carry out the task in the attached prompt file.'
                }
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
        'kilo' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # OpenCode fork, but unlike OpenCode 2 its run honours --dir.
                # Auth is the MiMo provider through MIMO_API_KEY, the separately
                # authorized Token Plan key -- not an account login -- so the
                # child environment keeps it.
                $args = @('run', '--auto', '--format', 'json', '--dir', $Work)
                $kiloPolicy = $fleet.dispatchPolicy.kilo
                $kiloModel = if ($script:KiloModel) { $script:KiloModel } else { [string]$kiloPolicy.model }
                # The default is checked like an explicit -Model: shape only.
                Assert-DispatchModelId -Id 'kilo' -ModelId $kiloModel -Source 'model'
                Assert-SubscriptionRoute -Id 'kilo' -ModelId $kiloModel
                Write-UnlistedModelNote -Id 'kilo' -ModelId $kiloModel
                $args += @('--model', $kiloModel)
                # --auto approves every action no rule denies, so an unattended run
                # is refused unless policy names the agent whose rules deny
                # outward and destructive actions.
                $kiloAgent = [string]$kiloPolicy.agent
                if ($kiloAgent -notmatch '^[A-Za-z0-9_-]+$') {
                    Write-Refusal 3 "refused kilo: dispatchPolicy.kilo.agent must name the guarded agent for unattended runs"
                }
                $args += @('--agent', $kiloAgent)
                $args += $PromptText
                @{ Args = $args; Stdin = $null; PromptFile = $null }
            }
        }
        'mimo-code' = @{
            Mode = 'argument'
            Build = {
                param($PromptText, $Work, $File)
                # OpenCode fork; its auto-approve flag is --yolo, not --auto.
                # Auth is the stored Xiaomi Token Plan credential, so provider
                # key environment variables are stripped like any account host.
                $args = @('run', '--yolo', '--format', 'json', '--dir', $Work)
                $mimoPolicy = $fleet.dispatchPolicy.'mimo-code'
                $mimoModel = if ($script:MimoCodeModel) { $script:MimoCodeModel } else { [string]$mimoPolicy.model }
                # The default is checked like an explicit -Model: shape only.
                Assert-DispatchModelId -Id 'mimo-code' -ModelId $mimoModel -Source 'model'
                Assert-SubscriptionRoute -Id 'mimo-code' -ModelId $mimoModel
                Write-UnlistedModelNote -Id 'mimo-code' -ModelId $mimoModel
                $args += @('--model', $mimoModel)
                # --yolo approves every action no rule denies, so an unattended run
                # is refused unless policy names the agent whose rules deny
                # outward and destructive actions.
                $mimoAgent = [string]$mimoPolicy.agent
                if ($mimoAgent -notmatch '^[A-Za-z0-9_-]+$') {
                    Write-Refusal 3 "refused mimo-code: dispatchPolicy.mimo-code.agent must name the guarded agent for unattended runs"
                }
                $args += @('--agent', $mimoAgent)
                $args += $PromptText
                @{ Args = $args; Stdin = $null; PromptFile = $null }
            }
        }
        'qwen' = @{
            # The prompt goes on stdin. With an argument prompt, a long or
            # multi-line task becomes a pointer to a file under the dispatcher
            # runtime folder, and in plan (read-only) mode qwen refuses to read
            # outside the task directory (observed 2026-11-11: "Blocked: cannot
            # read the task file"). qwen reads a one-shot prompt from stdin, so
            # no file is needed in either mode.
            Mode = 'stdin'
            ReadOnly = $true
            Build = {
                param($PromptText, $Work, $File)
                # qwen --help 0.27.1 (2026-11-11): a positional query is already a
                # one-shot headless run (-p/--prompt is deprecated), --approval-mode
                # yolo automatically approves all tools, and plan "does not modify
                # files or execute commands" (the enforced read-only mode). There
                # is no directory flag: the child process working directory is the
                # task directory. The vendor Token Plan page configures an
                # OpenAI-compatible provider whose key is referenced by env name;
                # --auth-type openai plus the OPENAI_* variables below select that
                # route per run, so the stored settings (selectedType nvidia) are
                # not used and no ~/.qwen file is written.
                $qwenPolicy = $fleet.dispatchPolicy.qwen
                $qwenModel = if ($script:QwenModel) { $script:QwenModel } else { [string]$qwenPolicy.model }
                Assert-DispatchModelId -Id 'qwen' -ModelId $qwenModel -Source 'model'
                Assert-SubscriptionRoute -Id 'qwen' -ModelId $qwenModel
                # The plan credential is the whole route on this host -- nothing is
                # stored -- so both variables must be present, not only shaped.
                Assert-MimoPlanEnvironment -Id 'qwen' -Required
                Write-UnlistedModelNote -Id 'qwen' -ModelId $qwenModel
                # --approval-mode yolo approves every tool call and this host has
                # no agent-profile denylist, so the warp guard repeats here:
                # pushes fail on an unhandled scheme and gh reads an empty config
                # directory while fetch and local git keep working.
                $ghDir = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub\runtime\coding-agent-dispatch\qwen-peer-gh'
                New-Item -ItemType Directory -Force -Path $ghDir | Out-Null
                $qwenEnv = @{
                    OPENAI_API_KEY   = [Environment]::GetEnvironmentVariable('MIMO_API_KEY')
                    OPENAI_BASE_URL  = [Environment]::GetEnvironmentVariable('MIMO_BASE_URL')
                    OPENAI_MODEL     = $qwenModel
                    GH_CONFIG_DIR    = $ghDir
                    GIT_CONFIG_COUNT = '3'
                }
                $schemes = @('https://', 'git@', 'ssh://')
                for ($i = 0; $i -lt $schemes.Count; $i++) {
                    $qwenEnv["GIT_CONFIG_KEY_$i"] = 'url.agenthub-peer-no-push://blocked/.pushInsteadOf'
                    $qwenEnv["GIT_CONFIG_VALUE_$i"] = $schemes[$i]
                }
                $qwenApproval = if ($ReadOnly) { 'plan' } else { 'yolo' }
                @{ Args = @('--auth-type', 'openai', '-m', $qwenModel, '--approval-mode', $qwenApproval, '-o', 'json')
                    Stdin = $PromptText; PromptFile = $null; Env = $qwenEnv }
            }
        }
        'factory' = @{
            Mode = 'file'
            ReadOnly = $true
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
                # droid exec --help 2026-11-11: with no --auto flag exec runs in
                # read-only mode ("No modifications to files or system"), so
                # -ReadOnly leaves --auto out instead of adding a flag.
                $args = @('exec', '--cwd', $Work)
                if (-not $ReadOnly) { $args += @('--auto', $autonomy) }
                $args += @('-o', 'json', '--settings', $runtimeSettings)
                $factoryModel = if ($script:FactoryModel) { $script:FactoryModel } else { [string]$factoryPolicy.model }
                Assert-SubscriptionRoute -Id 'factory' -ModelId $factoryModel
                if ($factoryModel) { $args += @('-m', $factoryModel) }
                # Role dispatch (SH-4676): a role runs as a native custom droid
                # through the Task tool. The parent is a strict relay for exactly
                # one delegation; the droid's own frontmatter is the tool
                # boundary. --only-tools is not usable for this: session-level
                # tool restrictions propagate into subagents (observed
                # 2026-11-14: an engineer droid inherited "Available tools:
                # Task" and could not edit). The relay prompt must also forbid a
                # complexity parameter and extra subagents: the built-in
                # explorer/worker route through subagentModelSettings tiers, and
                # an explorer spawned beside a BYOK run billed Factory credits
                # at the hosted light model (observed 2026-11-14: 325 credits).
                # The repo-owned runtimeSettings pins every tier to inherit so a
                # relayed run stays on the parent's subscription route.
                $taskText = $null
                if ($script:DispatchRole -ne 'peer') {
                    if (-not ($factoryPolicy.PSObject.Properties['roles'])) {
                        Write-Refusal 3 "refused factory: -Role $($script:DispatchRole) needs dispatchPolicy.factory.roles; it is not recorded"
                    }
                    $factoryRoles = $factoryPolicy.roles
                    if (-not ($factoryRoles.PSObject.Properties[$script:DispatchRole])) {
                        Write-Refusal 3 "refused factory: dispatchPolicy.factory.roles does not map role '$($script:DispatchRole)'; mapped roles: $((@($factoryRoles.PSObject.Properties | ForEach-Object Name)) -join ', ')"
                    }
                    $droid = [string]$factoryRoles.($script:DispatchRole)
                    if ($droid -cnotmatch '^[a-z0-9-_]+$') {
                        Write-Refusal 3 "refused factory: dispatchPolicy.factory.roles.$($script:DispatchRole) ('$droid') is not a valid droid name (lowercase letters, digits, hyphens, underscores)"
                    }
                    # Factory can resolve repo-local droids from --cwd ahead of the personal
                    # droid checked below. Refuse a same-name shadow so a checkout cannot replace
                    # the validated role boundary.
                    $projectDroidsDir = Join-Path (Join-Path $Work '.factory') 'droids'
                    $projectDroidFile = Join-Path $projectDroidsDir "$droid.md"
                    if (Test-Path -LiteralPath $projectDroidFile) {
                        Write-Refusal 3 "refused factory: project droid $projectDroidFile could shadow the validated personal droid; remove it or use a checkout without that droid"
                    }
                    $factoryDroidsDir = Join-Path (Join-Path (Get-AgentHubDefaultHome) '.factory') 'droids'
                    $droidFile = Join-Path $factoryDroidsDir "$droid.md"
                    if (-not (Test-Path -LiteralPath $droidFile -PathType Leaf)) {
                        Write-Refusal 3 "refused factory: role '$($script:DispatchRole)' needs the droid $droid.md, which is missing from $factoryDroidsDir; install it from packages/coding-agent-dispatch/factory/droids"
                    }
                    if ($ReadOnly) {
                        # Allow-list, not deny-list: an omitted tools field or any
                        # file-editing or unknown tool makes the droid writable,
                        # and a read-only run never delegates to a writable droid.
                        $droidRaw = Get-Content -LiteralPath $droidFile -Raw -Encoding UTF8
                        $toolsValue = $null
                        if ($droidRaw -match '(?s)^---\r?\n(.*?)\r?\n---' -and $Matches[1] -match '(?m)^tools:[ \t]*(.+?)[ \t]*$') {
                            # Trim: in a CRLF droid file (?m)$ sits before \n, so
                            # the capture keeps a trailing \r that would fail the
                            # array/category checks below (Sentry 20251924/0).
                            $toolsValue = $Matches[1].Trim()
                        }
                        $readOnlyToolAllow = @('Read', 'LS', 'Grep', 'Glob', 'Execute', 'WebSearch', 'FetchUrl')
                        $whyNotReadOnly = $null
                        if (-not $toolsValue) {
                            $whyNotReadOnly = 'it omits tools:, which grants every tool'
                        } elseif ($toolsValue -ceq 'read-only') {
                            # the read-only category is the enforced boundary
                        } elseif ($toolsValue.StartsWith('[') -and $toolsValue.EndsWith(']')) {
                            $droidTools = @($toolsValue.Substring(1, $toolsValue.Length - 2) -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
                            $writeTools = @($droidTools | Where-Object { $_ -cnotin $readOnlyToolAllow })
                            if ($writeTools.Count -gt 0) { $whyNotReadOnly = "its tools list grants $($writeTools -join ', ')" }
                        } else {
                            $whyNotReadOnly = "its tools value '$toolsValue' is neither the read-only category nor an array"
                        }
                        if ($whyNotReadOnly) {
                            Write-Refusal 3 "refused factory: the droid $droid.md is not read-only ($whyNotReadOnly); -ReadOnly never delegates to a writable droid"
                        }
                    }
                    # droid 1.10.0 blocks the Task tool in exec sessions by
                    # default (--list-tools: "Task - status: blocked" at every
                    # autonomy, and --add-tools Task does not unblock it); an
                    # explicit --only-tools list names it back. The session
                    # allow-list is the ceiling and each droid's frontmatter
                    # narrows inside it (verified 2026-11-14: the engineer droid
                    # created its fixture through exactly one Task call at
                    # factory_credits 0, and the reviewer droid answered
                    # WRITE-DENIED with no file created under the same list).
                    # MCP tools are deliberately outside the list.
                    $args += @('--only-tools', 'Task,Read,LS,Grep,Glob,Create,Edit,ApplyPatch,Execute,WebSearch,FetchUrl,TodoWrite,Skill')
                    $taskText = "You are a delegation relay for an orchestrator; no human answers during the run. Call the Task tool exactly once with subagent_type '$droid', description 'dispatch $($script:DispatchRole) run', and prompt set to the TASK text below verbatim. Do not pass a complexity parameter. Do not call any other tool, do not spawn any other subagent, and do not perform, verify or amend the task yourself. When the subagent finishes, reply with its final message verbatim.`n`nTASK:`n$PromptText"
                }
                $args += @('-f', $File)
                @{ Args = $args; Stdin = $null; PromptFile = $File; TaskText = $taskText }
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
                Assert-SubscriptionRoute -Id 'cline' -ModelId ("{0}:{1}" -f $clineProvider, $clineModel)
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
                # the prompt. The permission flags are read from launchDefaults.devin
                # (autonomyProfiles.flagsOwnedByLaunchDefaults: the one place they are
                # recorded); the registry points at the WinGet devin.exe, not the ~/bin
                # shim that already adds them. A missing record refuses rather than
                # guessing a permission mode.
                $launchFlags = @()
                if ($fleet.PSObject.Properties['launchDefaults'] -and $fleet.launchDefaults.PSObject.Properties['devin']) {
                    $launchFlags = @($fleet.launchDefaults.devin | ForEach-Object { [string]$_ })
                }
                if ($launchFlags.Count -eq 0) {
                    Write-Refusal 3 'refused devin: registry/fleet-profile.json launchDefaults.devin is missing or empty; the local Devin permission flags are recorded only there'
                }
                $args = $launchFlags + @('-p', '--prompt-file', $File)
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

function Resolve-ZCodeLaunch {
    param($Agent)
    if (-not $isWindowsHost -or -not $Agent.nativePaths.bundledRuntime) { return $null }
    $runtime = Resolve-DeclaredExecutable -Declared ([string]$Agent.nativePaths.bundledRuntime)
    $node = Resolve-DeclaredExecutable -Declared 'node.exe'
    if (-not $runtime -or -not $node) { return $null }
    $resources = Split-Path -Parent (Split-Path -Parent $runtime)
    $builtin = Join-Path $resources 'config/provider/zcode-builtin.json'
    $personal = Join-Path (Get-AgentHubDefaultHome) '.zcode/v2/provider_config.json'
    if (-not (Test-Path -LiteralPath $builtin -PathType Leaf) -or -not (Test-Path -LiteralPath $personal -PathType Leaf)) { return $null }
    return @{ Node = $node; Runtime = $runtime; Builtin = $builtin; Personal = $personal }
}

# -Role names a per-host profile. Only the hosts listed here have any.
$script:DispatchRoles = @('peer', 'engineer', 'reviewer', 'tester', 'researcher')
$script:RoleHosts = @('opencode', 'factory')
$script:DispatchRole = 'peer'

# dispatchPolicy.<host>.readOnly: an object with a flags list when the host has
# an enforced read-only mode, false when it was checked and has none, null or
# absent when that is not established.
function Get-ReadOnlyRecord {
    param([string]$Id)
    if ($null -eq $dispatchPolicy) { return $null }
    $entry = $dispatchPolicy.PSObject.Properties[$Id]
    if ($null -eq $entry -or $null -eq $entry.Value -or $entry.Value -is [string]) { return $null }
    $record = $entry.Value.PSObject.Properties['readOnly']
    if ($null -eq $record) { return $null }
    return $record.Value
}

# Both must hold: this script has a verified read-only command for the host,
# and the registry records it. Anything else is a refusal, never a writable run.
function Get-ReadOnlyRefusal {
    param([string]$Id)
    $record = Get-ReadOnlyRecord $Id
    $recorded = $record -is [pscustomobject] -and $null -ne $record.PSObject.Properties['flags']
    if ($recorded -and $table.ContainsKey($Id) -and $table[$Id].ReadOnly) { return $null }
    $why = if ($record -is [bool] -and -not $record) { "dispatchPolicy.$Id.readOnly is false: checked, none" }
        elseif ($recorded) { 'the dispatcher has no verified read-only command for it' }
        else { "dispatchPolicy.$Id.readOnly is not established" }
    return "host $Id has no enforced read-only mode ($why); -ReadOnly never falls back to a writable run"
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
    if ($id -eq 'zcode' -and -not (Resolve-ZCodeLaunch $Agent)) {
        return [pscustomobject]@{ Id = $id; State = 'refused'; Detail = 'requires Windows, Node, and the installed ZCode bundle and provider files' }
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

# devin-cloud must be explicitly enabled and carry its budget record; a missing
# policy is a refusal here, unlike a local host whose absent record means enabled.
function Get-DevinCloudPolicyRefusal {
    $entry = if ($dispatchPolicy) { $dispatchPolicy.PSObject.Properties['devin-cloud'] } else { $null }
    if ($null -eq $entry) { return 'dispatchPolicy.devin-cloud is not enabled (no policy record)' }
    if ($entry.Value.enabled -ne $true) {
        return ((@('dispatchPolicy.devin-cloud is not enabled', [string]$entry.Value.reason, [string]$entry.Value.ownerAction) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('.') }) -join '. ')
    }
    if ($null -eq $entry.Value.cloudBudgetAuthorization) { return 'dispatchPolicy.devin-cloud records no cloudBudgetAuthorization' }
    return $null
}

# -List reports devin-cloud callable only when a create could resolve a key:
# the in-process override, or op on PATH with OP_SERVICE_ACCOUNT_TOKEN set. It
# checks presence only; it never runs op read or prints a value.
function Get-DevinCloudKeySourceRefusal {
    if (-not [string]::IsNullOrWhiteSpace($script:DevinCloudKeyOverride)) { return $null }
    if (-not (Get-Command op -CommandType Application -ErrorAction SilentlyContinue)) {
        return 'no Devin Cloud key source (the 1Password CLI op is not on PATH and no in-process DEVIN_CLOUD_API_KEY override); a create would refuse with exit 3'
    }
    if ([string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)) {
        return 'no Devin Cloud key source (OP_SERVICE_ACCOUNT_TOKEN is not set and no in-process DEVIN_CLOUD_API_KEY override); a create would refuse with exit 3'
    }
    return $null
}

if ($List) {
    foreach ($agent in ($agents | Sort-Object { [string]$_.id })) {
        $row = Get-HostRow -Agent $agent
        if ($ReadOnly) {
            if ($row.State -eq 'refused') { continue }
            $readOnlyTarget = if ($row.State -eq 'routed') { [string]$row.Detail } else { [string]$row.Id }
            if (Get-ReadOnlyRefusal $readOnlyTarget) { continue }
        }
        Write-Output ("{0}`t{1}`t{2}" -f $row.Id, $row.State, $row.Detail)
    }
    # devin-cloud is a surface of the devin host, not an agents.json record, and
    # has no read-only mode, so it is listed only without -ReadOnly.
    if (-not $ReadOnly) {
        $cloudRefusal = Get-DevinCloudPolicyRefusal
        if (-not $cloudRefusal) { $cloudRefusal = Get-DevinCloudKeySourceRefusal }
        if ($cloudRefusal) { Write-Output ("devin-cloud`trefused`t{0}" -f $cloudRefusal) }
        else { Write-Output "devin-cloud`tcallable`tcloud-adapter" }
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($HostId)) {
    Write-Refusal 3 'Pass -HostId, or -List to see which hosts are callable.'
}
$requested = $HostId.Trim()
if ($ZCodeBrowser -and $requested -ne 'zcode') { Write-Refusal 3 '-ZCodeBrowser applies only to -HostId zcode.' }
if ($requested -in @('jules', 'cursor-cloud', 'copilot-agent')) {
    Write-Refusal 3 "refused ${requested}: hosted cloud execution is disabled; owner must authorize this specific task, model, cadence, stop condition and cost budget before enabling a verified cloud adapter"
}
$cloudOnlyOptions = @('RunId', 'MaxAcu', 'Repo', 'SchemaFile') | Where-Object { $PSBoundParameters.ContainsKey($_) }
if ($requested -ne 'devin-cloud' -and @($cloudOnlyOptions).Count -gt 0) {
    Write-Refusal 3 "refused ${requested}: -$(@($cloudOnlyOptions) -join ', -') apply only to -HostId devin-cloud"
}
if ($requested -eq 'devin-cloud') {
    # SH-4969 (owner direction 2026-11-19): one Devin Cloud session per call through
    # the v3 adapter, which enforces the ACU default, the concurrency cap, run-tag
    # dedupe and the 1Password service-account key path. Nothing runs locally and
    # the adapter writes no log, so this route never touches the runtime folder.
    $cloudRefusal = Get-DevinCloudPolicyRefusal
    if ($cloudRefusal) { Write-Refusal 3 "refused devin-cloud: $cloudRefusal" }
    if ($ReadOnly) { Write-Refusal 3 'refused devin-cloud: dispatchPolicy.devin-cloud.readOnly is false: checked, none; -ReadOnly never falls back to a writable run' }
    if ($Model -or $AnthropicApiKey -or $SessionId -or ($Role -and $Role.Trim().ToLowerInvariant() -ne 'peer')) {
        Write-Refusal 3 'refused devin-cloud: -Model, -AnthropicApiKey, -SessionId and -Role do not apply; steer an existing session with Invoke-DevinCloud.ps1 -Action message'
    }
    if (-not [string]::IsNullOrWhiteSpace($Prompt) -and -not [string]::IsNullOrWhiteSpace($PromptFile)) { Write-Refusal 3 'Pass -Prompt or -PromptFile, not both.' }
    if ([string]::IsNullOrWhiteSpace($Prompt) -and [string]::IsNullOrWhiteSpace($PromptFile)) { Write-Refusal 3 'Pass -Prompt or -PromptFile.' }
    # Text, not [int]: PowerShell would round 2.5 and read 1e3 as 1000.
    if ($PSBoundParameters.ContainsKey('MaxAcu') -and $MaxAcu -notmatch '^[1-9][0-9]{0,5}$') {
        Write-Refusal 3 "refused devin-cloud: -MaxAcu must be a positive whole number (got '$MaxAcu')"
    }
    $adapter = Join-Path $PSScriptRoot 'Invoke-DevinCloud.ps1'
    $cloudArgs = [ordered]@{ Action = 'create' }
    if ($PromptFile) { $cloudArgs.PromptFile = $PromptFile } else { $cloudArgs.Prompt = $Prompt }
    $cloudArgs.Cwd = $(if ($Cwd) { $Cwd } else { (Get-Location).Path })
    if ($Title) { $cloudArgs.Title = $Title }
    if ($RunId) { $cloudArgs.RunId = $RunId }
    if ($PSBoundParameters.ContainsKey('MaxAcu')) { $cloudArgs.MaxAcu = $MaxAcu }
    if ($Repo) { $cloudArgs.Repo = $Repo }
    if ($SchemaFile) { $cloudArgs.SchemaFile = $SchemaFile }
    if ($ShowCommand) {
        Write-Output ("file={0}" -f $adapter)
        $shown = foreach ($pair in $cloudArgs.GetEnumerator()) {
            if ($pair.Key -eq 'Prompt') { '-Prompt <task text>' } else { '-{0} {1}' -f $pair.Key, (@($pair.Value) -join ',') }
        }
        Write-Output ("args={0}" -f ($shown -join ' '))
        exit 0
    }
    if (-not [string]::IsNullOrWhiteSpace($script:DevinCloudKeyOverride)) {
        [Environment]::SetEnvironmentVariable('DEVIN_CLOUD_API_KEY', $script:DevinCloudKeyOverride, 'Process')
    }
    & $adapter @cloudArgs
    exit $LASTEXITCODE
}
$agent = Get-AgentRecord -Agents $agents -Id $requested
if (-not $agent) { Write-Refusal 3 "refused ${requested}: unknown host" }
if (-not [string]::IsNullOrWhiteSpace($Role)) {
    $script:DispatchRole = $Role.Trim().ToLowerInvariant()
    if ($script:DispatchRole -notin $script:DispatchRoles) {
        Write-Refusal 3 "refused ${requested}: -Role '$($Role.Trim())' is not a role; use one of: $($script:DispatchRoles -join ', ')"
    }
    if ($script:DispatchRole -ne 'peer' -and $requested -notin $script:RoleHosts) {
        Write-Refusal 3 "refused ${requested}: -Role $($script:DispatchRole) is not supported on this host; roles are supported only on: $($script:RoleHosts -join ', ')"
    }
}

$script:ClineGuardEnv = @{ AGENTHUB_PEER_GUARD = '1'; CLINE_SESSION_BACKEND_MODE = 'local' }
if (-not $AnthropicApiKey -and -not [string]::IsNullOrWhiteSpace($Model)) {
    # OWNER DIRECTION 2026-11-10: a model or coding plan is allowed wherever it
    # can be integrated and supported. -Model is passed through to every host
    # whose CLI takes a model flag; allowedModels records the smoke-verified
    # models and no longer restricts the choice. Only the shape is enforced.
    if ($requested -notin @('codex', 'grok', 'opencode', 'cline', 'warp', 'factory', 'devin', 'kilo', 'mimo-code', 'qwen')) {
        Write-Refusal 3 '-Model applies only to an -AnthropicApiKey run or to Codex, Grok, OpenCode, Cline, Warp, Factory, Devin, Kilo, MiMo or Qwen.'
    }
    $choice = $Model.Trim()
    Assert-DispatchModelId -Id $requested -ModelId $choice
    Assert-SubscriptionRoute -Id $requested -ModelId $choice
    Write-UnlistedModelNote -Id $requested -ModelId $choice
    switch ($requested) {
        'codex'     { $script:CodexModel = $choice }
        'grok'      { $script:GrokModel = $choice }
        'opencode'  { $script:OpenCodeModel = $choice }
        'warp'      { $script:WarpModel = $choice }
        'factory'   { $script:FactoryModel = $choice }
        'devin'     { $script:DevinModel = $choice }
        'kilo'      { $script:KiloModel = $choice }
        'mimo-code' { $script:MimoCodeModel = $choice }
        'qwen'      { $script:QwenModel = $choice }
        'cline'     {
            $split = $choice.IndexOf(':')
            $script:ClineProvider = $choice.Substring(0, $split)
            $script:ClineModel = $choice.Substring($split + 1)
        }
    }
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
if ($ReadOnly) {
    # A read-only run is a mechanism the host enforces or it does not happen.
    $readOnlyRefusal = Get-ReadOnlyRefusal $targetId
    if ($readOnlyRefusal) { Write-Refusal 3 "refused ${requested}: $readOnlyRefusal" }
    if ($PSBoundParameters.ContainsKey('SessionId')) {
        Write-Refusal 3 "refused ${requested}: -ReadOnly cannot resume a session; the ACP resume path has no enforced read-only mode"
    }
    if ($targetId -eq 'opencode' -and $script:DispatchRole -notin @('peer', 'reviewer')) {
        Write-Refusal 3 "refused opencode: -ReadOnly cannot be combined with -Role $($script:DispatchRole), a writing role; a read-only OpenCode run uses the readonly agent profile"
    }
    if ($targetId -eq 'factory' -and $script:DispatchRole -notin @('peer', 'reviewer')) {
        Write-Refusal 3 "refused factory: -ReadOnly cannot be combined with -Role $($script:DispatchRole), a writing role; a read-only Factory run uses the reviewer droid"
    }
}
$targetAgent = Get-AgentRecord -Agents $agents -Id $targetId
$executable = if ($targetId -eq 'zcode') { (Resolve-ZCodeLaunch $targetAgent).Node }
    else { Resolve-DeclaredExecutable -Declared ([string]$targetAgent.executable) }
if (-not $executable) { Write-Refusal 2 "refused ${targetId}: executable is absent" }
if ($targetId -eq 'opencode' -and $script:OpenCodeModel -like 'zai-coding-plan/*') {
    $zaiLauncher = Join-Path (Get-AgentHubDefaultLocalData) 'AgentHub\zai\opencode-zai.ps1'
    if (-not (Test-Path -LiteralPath $zaiLauncher -PathType Leaf)) {
        Write-Refusal 3 'refused opencode: the Windows Z.ai Coding Plan launcher is absent'
    }
    $executable = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $executable) { Write-Refusal 3 'refused opencode: the Windows Z.ai launcher requires pwsh' }
}

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
if ($zaiLauncher) {
    $built.Args = @('-NoProfile', '-File', $zaiLauncher) + $built.Args
    # The v2 peer profile is not a v1 permission contract. Isolate this
    # route from ambient/project config and use native v1 tool rules.
    $built.Env = @{
        XDG_CONFIG_HOME = Join-Path (Split-Path -Parent $zaiLauncher) 'config'
        OPENCODE_DISABLE_PROJECT_CONFIG = 'true'
        OPENCODE_CONFIG_CONTENT = (@{
            permission = [ordered]@{
                '*' = 'deny'
                read = [ordered]@{ '*' = 'allow'; '*.env*' = 'deny' }
                glob = 'allow'
                grep = 'allow'
                edit = [ordered]@{ '*' = 'allow'; '*.env*' = 'deny' }
                'zai-*' = 'allow'
            }
        } | ConvertTo-Json -Depth 5 -Compress)
    }
}
if ($targetId -eq 'opencode' -and ($ReadOnly -or $script:DispatchRole -eq 'reviewer')) {
    if (-not $built.Env) { $built.Env = @{} }
    # Do not load repository-provided agents/config/instructions or external
    # plugins into a restricted review process; profile checks alone cannot
    # constrain code loaded after the global profile.
    $built.Env['OPENCODE_DISABLE_PROJECT_CONFIG'] = 'true'
    $built.Env['OPENCODE_PURE'] = 'true'
}
# Write the task only after Build has accepted the policy: a refusing Build
# must not leave a prompt file behind, and the run's finally block below does
# not exist yet at that point. Pointer hosts write the task text captured
# before the pointer substitution above replaced $Prompt.
if (-not $ShowCommand -and $promptFile -and ($contract.Mode -eq 'file' -or $pointer)) {
    # A Build may substitute the file text (factory role dispatch relays the
    # task through a Task-tool delegation wrapper); the raw prompt stays in
    # $taskText for every other host.
    $fileText = if ($built.TaskText) { [string]$built.TaskText } else { $taskText }
    [IO.File]::WriteAllText($promptFile, $fileText, [Text.UTF8Encoding]::new($false))
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
    if ($built.Env -and @($built.Env.Keys).Count -gt 0) {
        # Names only: values can hold credentials (qwen's OPENAI_API_KEY, for one).
        Write-Output ("env={0}" -f ((@($built.Env.Keys) | Sort-Object) -join ' '))
    }
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
# OpenCode 2 uses native Console account OAuth; its Go subscription is the opencode-go provider.
# Remove both provider overrides so they cannot replace the stored account.
# Exception (owner direction 2026-10-24): an explicit -AnthropicApiKey claude run keeps
# ANTHROPIC_API_KEY; ANTHROPIC_API_KEY_BACKUP is still removed.
$accountScrub = @{
    'claude'       = @('ANTHROPIC_API_KEY', 'ANTHROPIC_API_KEY_BACKUP')
    'codex'        = @('OPENAI_API_KEY')
    'cline'        = @('CLINE_API_KEY', 'OPENROUTER_API_KEY', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'DEEPSEEK_API_KEY')
    'devin'        = @('DEVIN_API_KEY', 'DEVIN_API_TOKEN', 'DEVIN_SERVICE_USER_TOKEN', 'DEVIN_ORG_ID')
    'antigravity'  = @('GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_GENERATIVE_AI_API_KEY')
    'warp'         = @('WARP_API_KEY', 'GH_TOKEN', 'GITHUB_TOKEN')
    'grok'         = @('XAI_API_KEY')
    'zcode'        = @('ZAI_API_KEY', 'Z_AI_API_KEY', 'BIGMODEL_API_KEY', 'GLM_API_KEY', 'ZCODE_HOME', 'ZCODE_PROVIDER_OPTIONS', 'ZCODE_BUILTIN_PROVIDER_BUNDLED_CONFIG_FILE', 'NODE_OPTIONS')
    'factory'      = @('FACTORY_API_KEY')
    'cursor-agent' = @('CURSOR_API_KEY')
    'amp'          = @('AMP_API_KEY')
    'copilot'      = @('GH_TOKEN', 'GITHUB_TOKEN')
    'opencode'     = @('OPENCODE_GO_API_KEY', 'OPENCODE_API_KEY', 'ZAI_API_KEY', 'Z_AI_API_KEY')
    # mimo-code runs on its stored Xiaomi Token Plan credential; a stray plan
    # key in the environment must not override it. kilo is the opposite case:
    # its credential IS MIMO_API_KEY, so it is deliberately absent here.
    'mimo-code'    = @('MIMO_API_KEY')
    # qwen's plan credential reaches the child as OPENAI_* set from MIMO_* after
    # this scrub. Every other provider key or base URL that could retarget auth
    # or billing away from the Token Plan is removed, along with the GitHub
    # tokens behind its GIT_CONFIG_*/GH_CONFIG_DIR push guard. MIMO_* stay:
    # they are the plan's own variables and nothing else consumes them.
    'qwen'         = @('OPENAI_API_KEY', 'OPENAI_BASE_URL', 'OPENAI_MODEL', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL', 'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_GENERATIVE_AI_API_KEY', 'DASHSCOPE_API_KEY', 'MODELSCOPE_API_KEY', 'QWEN_API_KEY', 'OPENROUTER_API_KEY', 'NVIDIA_API_KEY', 'AZURE_OPENAI_API_KEY', 'AZURE_OPENAI_ENDPOINT', 'DEEPSEEK_API_KEY', 'XAI_API_KEY', 'OPENAI_ORG_ID', 'OPENAI_PROJECT', 'GH_TOKEN', 'GITHUB_TOKEN')
}
# Every host, not just devin: the Devin Cloud key is never a child's credential.
[void]$psi.EnvironmentVariables.Remove('DEVIN_CLOUD_API_KEY')
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
