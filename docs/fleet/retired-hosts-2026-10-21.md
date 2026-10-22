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
