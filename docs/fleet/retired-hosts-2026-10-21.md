# Retired coding hosts — 2026-10-21

Owner direction on 2026-10-21: retire Qoder, Qwen Code, and Hermes from the
AgentHub fleet. Their host records, capability mappings, integrations,
dispatcher contracts, and host-specific maintenance code were removed from
the active repository configuration. Git history is unchanged.

## Local installation disposition

The checked locations did not contain an install to uninstall. No uninstall
command was run, no preserved evidence was deleted, and no files under the
preservation folder were inspected or changed.

| Host | Read-only result | Action |
| --- | --- | --- |
| Qwen Code | `qwen` was absent from `PATH`; `npm list --global --depth=0 qwen-code` listed no package. | Already absent; no uninstall run. |
| Hermes | `%LOCALAPPDATA%\hermes` was absent. The earlier worker had already moved the installation to a preserved folder, which remains untouched. | Already moved to preservation; no removal or preservation-folder cleanup run. |
| Qoder | `qodercli` was absent from `PATH`. | Already absent from the checked command path; no uninstall run. |

Read-only checks used:

```powershell
Get-Command qwen -ErrorAction SilentlyContinue
npm list --global --depth=0 qwen-code
Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'hermes')
Get-Command qodercli -ErrorAction SilentlyContinue
```

The disposition is limited to those checked command and package locations; it
does not claim a whole-machine search. No uninstall command was run because no
in-scope install was found at those locations.

## 2026-10-30 Update — Qoder un-retired

Owner direction on 2026-10-30 restored Qoder (`qoder`) to the active AgentHub fleet after verifying Qoder CLI 1.1.81 at `~/.qoder/bin/qodercli/qodercli.exe` (shimmed at `~/bin/qodercli.cmd`) and Qoder Desktop IDE 1.24.2 at `%LOCALAPPDATA%\Programs\Qoder\Qoder.exe`. Qwen Code and Hermes remain retired.

## 2026-11-09 Update — Qoder retired again

Owner direction on 2026-11-09 retired Qoder (`qoder`) from the AgentHub fleet again, and asked for it to be removed and uninstalled. No install was present to uninstall. Read-only checks on that date found `~/.qoder/bin/qodercli/qodercli.exe` and `%LOCALAPPDATA%\Programs\Qoder\Qoder.exe` absent (`Test-Path`), no Qoder entry in the Windows uninstall registry (HKLM and HKCU), and no `qodercli` or Qoder directory on `PATH`. The registry still listed Qoder as an active host, so the sync had created a stray `~/.qoder/settings.json` (17 bytes); that file and its empty folder were deleted.

Removed: the `qoder` agent record, its capability mappings, native-connector and gateway rows, plugin-format row, per-host MCP and plugin-owner entries, the dispatcher contract and its tests, the Sync-AgentHub and Sync-Plugins host code, and the Clerk fleet installer entry. `registry/mcps.json` `hostInventory.notInstalled` now records `qoder` beside `windsurf`. Qwen Code and Hermes remain retired. The 2026-10-30 section above is kept as the historical record.

## 2026-11-10 Update — Gemini CLI retired

Owner direction on 2026-11-10 retired Gemini CLI (`gemini`) from the AgentHub fleet and asked for it to be uninstalled (SH-4331). Evidence from the same day, on this machine: Gemini CLI 0.67.0 with the stored Google sign-in answered "You do not have a valid license of this product" when `GOOGLE_CLOUD_PROJECT` was set, and "This client is no longer supported for Gemini Code Assist for individuals. To continue using Gemini, please migrate to the Antigravity suite of products" when it was unset. Antigravity CLI (`agy` 1.5.3) returned READY headless the same day and is the Google route.

Removed: the `gemini` agent record, its `managedHosts`, launch-default, autonomy, host-setting, dispatch-policy and host-surface rows, its capability mappings, native-connector and gateway rows, plugin-format and subagent-format rows, per-server MCP host entries, the dispatcher contract and key-scrub entry and their tests, the Sync-AgentHub, Sync-Plugins, Sync-Subagents, Remove-StaleAgentSessions and doctor host code, and the Clerk fleet installer entry. The `gemini-extension.json` manifests were deleted from seven packages (assemblyai, aws, context7, descript, exa, linear, notion) because only Gemini CLI read them; those packages, `browser` and `coding-agent-dispatch` were version-bumped.

Kept: every Antigravity path under `~/.gemini/` and every `antigravity*` host row. `~/.gemini/GEMINI.md` is an Antigravity global rule, so the `antigravity` entry now owns that instruction file and the desktop and IDE entries name it as owner; the file header text is unchanged, so the deployed file does not change. Gemini model ids and Gemini API code are not the CLI host and were not touched.

Local installation: uninstalled on 2026-11-10 after the retirement was written. `npm uninstall -g --prefix %APPDATA%\npm @google/gemini-cli` removed the package and its three npm launchers; `~/bin/gemini.cmd`, `~/bin/gemini-acp.cmd` and a stale mise shim were deleted. Read back the same day: the package folder is absent (`Test-Path`), `Get-Command gemini` finds nothing, and `agy` still returned READY headless. `~/.gemini` was kept whole because Antigravity stores its configuration there; that leaves Gemini CLI's own sign-in file, settings and chat history in place. `registry/mcps.json` `hostInventory.notInstalled` now lists `gemini`.

## 2026-11-17 Update — Kiro retired

Owner direction on 2026-11-17 retired Kiro (`kiro`, the CLI and IDE) and KiroCrew (`kirocrew`) from the AgentHub fleet (SH-4838 follow-up), saying Kiro is gone.

Removed: the `kiro` and `kirocrew` agent records, the `kiro` entries in `managedHosts`, autonomy, host-setting and dispatch-policy rows, the `kiro` host mappings in six capability rows, the plugin-format row, the MCP `hostInventory` and `sessionStart` entries, the context-limits note, the dispatcher contract, roles and `kiro/` profile directory, `Install-KiroProfiles.ps1`, `New-KiroCloudPowers.ps1`, the Kiro tests, and the two Kiro runbooks. Git history is unchanged.

Local installation: read-only checks on 2026-11-17 found `kiro-cli` and `kiro` absent from `PATH`, no `~/bin/kiro*.cmd`, no `%LOCALAPPDATA%ProgramsKiro` and no `%LOCALAPPDATA%ProgramsKiroCrew`, and no running Kiro process. Leftovers remain: `%LOCALAPPDATA%Kiro-Cli` holds `bun.exe`, `data.sqlite3` and run receipts but no `kiro-cli.exe`, and `~/.kiro` still holds `agents`, `powers`, `skills`, `steering`, `settings`, `sessions`, `crew` and a `secrets.json`. No uninstall command was run and nothing was deleted, because those folders may hold the only copy of owner-authored agents, steering and credentials; the owner decides whether to remove them. The check covered those paths only and does not claim a whole-machine search.

## 2026-11-19 Update — Warp, MiMo Code and Qwen Code retired

Owner direction. MiMo Code and Qwen Code were uninstalled and moved to
`inactiveAgents` in `registry/agents.json` (#164), and the `pending-retirement`
fleet role was renamed `supported`. Warp was uninstalled (app, config and skill
links) and moved to `inactiveAgents` the same day (#165). The sync no longer
targets any of the three; `doctor` still detects them from the inactive rows.
