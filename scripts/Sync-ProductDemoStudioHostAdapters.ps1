#Requires -Version 5.1
<#
.SYNOPSIS
  Generates Product Demo Studio subagents in each host's documented native format.

.DESCRIPTION
  AgentHub's Product Demo Studio agents are the only prompt source. This script
  translates their frontmatter and bodies into runtime adapters; it never makes
  an agent-home copy an independent policy authority. Reviewer, arbiter, and
  final-verifier roles receive host-native read-only restrictions.
#>
[CmdletBinding()]
param(
  [string]$RegistryRoot = 'C:\Repos\shmindmaster\agenthub',
  [string]$UserProfile = $env:USERPROFILE
)

$ErrorActionPreference = 'Stop'
$RegistryRoot = [IO.Path]::GetFullPath($RegistryRoot).TrimEnd('\')
$UserProfile = [IO.Path]::GetFullPath($UserProfile).TrimEnd('\')
$pluginRoot = Join-Path $RegistryRoot 'packages\handoff-plugins\plugins\product-demo-studio'
$agentsRoot = Join-Path $pluginRoot 'agents'
$manifestPath = Join-Path $pluginRoot '.codex-plugin\plugin.json'
if (!(Test-Path -LiteralPath $agentsRoot -PathType Container)) {
  throw "Product Demo Studio agents are missing: $agentsRoot"
}
if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Product Demo Studio manifest is missing: $manifestPath"
}
$pluginVersion = [string](Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $parent = Split-Path -Parent $Path
  if (!(Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Read-CanonicalAgent {
  param([string]$Path)
  $content = [IO.File]::ReadAllText($Path)
  $match = [regex]::Match(
    $content,
    '\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n(?<body>[\s\S]*)\z',
    [Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (!$match.Success) { throw "Invalid Product Demo Studio agent frontmatter: $Path" }
  $frontmatter = $match.Groups['frontmatter'].Value
  $name = [regex]::Match($frontmatter, '(?m)^name:\s*(?<value>.+?)\s*$').Groups['value'].Value
  $description = [regex]::Match($frontmatter, '(?m)^description:\s*(?<value>.+?)\s*$').Groups['value'].Value
  $tools = [regex]::Match($frontmatter, '(?m)^tools:\s*(?<value>.+?)\s*$').Groups['value'].Value -split '\s*,\s*'
  $readOnly = [regex]::IsMatch($frontmatter, '(?m)^readonly:\s*true\s*$')
  if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
    throw "Product Demo Studio agent lacks name or description: $Path"
  }
  [pscustomobject]@{
    name = $name
    description = $description
    tools = @($tools | Where-Object { $_ })
    readOnly = $readOnly
    body = $match.Groups['body'].Value.Trim()
  }
}

function ConvertTo-TomlString {
  param([string]$Value)
  return ($Value | ConvertTo-Json -Compress)
}

function Get-GeminiTools {
  param([string[]]$Tools)
  $map = @{
    Read = 'read_file'
    Grep = 'grep_search'
    Glob = 'glob'
    Bash = 'run_shell_command'
    Edit = 'replace'
    Write = 'write_file'
  }
  @($Tools | ForEach-Object { $map[$_] } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-AntigravityTools {
  param([string[]]$Tools)
  $map = @{
    Read = 'view_file'
    Grep = 'grep_search'
    Glob = 'find_by_name'
    Bash = 'run_command'
    Edit = 'replace_file_content'
    Write = 'write_to_file'
  }
  @($Tools | ForEach-Object { $map[$_] } | Where-Object { $_ } | Sort-Object -Unique)
}

$agents = @(
  Get-ChildItem -LiteralPath $agentsRoot -Filter '*.md' -File |
    Sort-Object Name |
    ForEach-Object { Read-CanonicalAgent -Path $_.FullName }
)
if ($agents.Count -ne 13) {
  throw "Expected 13 canonical Product Demo Studio agents; found $($agents.Count)."
}
$readOnlyCount = @($agents | Where-Object readOnly).Count
if ($readOnlyCount -ne 6) {
  throw "Expected six mechanically read-only Product Demo Studio roles; found $readOnlyCount."
}

$codexAgentsRoot = Join-Path $UserProfile '.codex\agents'
$openCodeAgentsRoot = Join-Path $UserProfile '.config\opencode\agents'
$geminiExtensionRoot = Join-Path $UserProfile '.gemini\extensions\agenthub-product-demo-studio'
$geminiAgentsRoot = Join-Path $geminiExtensionRoot 'agents'
$antigravityPluginRoot = Join-Path $UserProfile '.gemini\antigravity-cli\plugins\product-demo-studio'
$antigravityAgentsRoot = Join-Path $antigravityPluginRoot 'agents'

$geminiManifest = [ordered]@{
  name = 'agenthub-product-demo-studio'
  version = $pluginVersion
  description = 'AgentHub-managed Product Demo Studio subagents; skills and MCP remain centrally distributed.'
}
Write-Utf8NoBom -Path (Join-Path $geminiExtensionRoot 'gemini-extension.json') `
  -Content ($geminiManifest | ConvertTo-Json -Depth 5)

$antigravityManifest = [ordered]@{
  '$schema' = 'https://antigravity.google/schemas/v1/plugin.json'
  name = 'product-demo-studio'
  description = 'AgentHub-managed Product Demo Studio subagents; skills and MCP remain centrally distributed.'
}
Write-Utf8NoBom -Path (Join-Path $antigravityPluginRoot 'plugin.json') `
  -Content ($antigravityManifest | ConvertTo-Json -Depth 5)

foreach ($agent in $agents) {
  $runtimeName = "product-demo-studio-$($agent.name)"

  $codexLines = @(
    "name = $(ConvertTo-TomlString $runtimeName)",
    "description = $(ConvertTo-TomlString $agent.description)"
  )
  if ($agent.readOnly) { $codexLines += 'sandbox_mode = "read-only"' }
  $codexLines += @(
    'developer_instructions = """',
    $agent.body,
    '"""'
  )
  Write-Utf8NoBom -Path (Join-Path $codexAgentsRoot "$runtimeName.toml") `
    -Content (($codexLines -join "`n") + "`n")

  $openCodeFrontmatter = @(
    '---',
    "description: $($agent.description)",
    'mode: subagent'
  )
  if ($agent.readOnly) {
    $openCodeFrontmatter += @(
      'permission:',
      '  edit: deny',
      '  bash: deny',
      '  task: deny'
    )
  }
  $openCodeFrontmatter += '---'
  Write-Utf8NoBom -Path (Join-Path $openCodeAgentsRoot "$runtimeName.md") `
    -Content (($openCodeFrontmatter + '', $agent.body) -join "`n")

  $geminiTools = Get-GeminiTools -Tools $agent.tools
  $geminiFrontmatter = @(
    '---',
    "name: $runtimeName",
    "description: $($agent.description)",
    'kind: local',
    'tools:'
  ) + @($geminiTools | ForEach-Object { "  - $_" }) + @(
    'model: inherit',
    'max_turns: 30',
    '---'
  )
  Write-Utf8NoBom -Path (Join-Path $geminiAgentsRoot "$runtimeName.md") `
    -Content (($geminiFrontmatter + '', $agent.body) -join "`n")

  $antigravityTools = Get-AntigravityTools -Tools $agent.tools
  $antigravityFrontmatter = @(
    '---',
    "name: $runtimeName",
    "description: $($agent.description)",
    'tools:'
  ) + @($antigravityTools | ForEach-Object { "  - $_" }) + @(
    'subagent: true',
    'mainAgent: false',
    'model: inherit',
    "commandExecutionPolicy: $(if ($agent.readOnly) { 'off' } else { 'sandbox' })",
    '---'
  )
  Write-Utf8NoBom -Path (Join-Path $antigravityAgentsRoot "$runtimeName.md") `
    -Content (($antigravityFrontmatter + '', $agent.body) -join "`n")
}

Write-Host "Product Demo Studio adapters synchronized: 13 roles, $readOnlyCount read-only roles, version $pluginVersion."
