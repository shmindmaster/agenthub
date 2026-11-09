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
