# Codex Desktop root-temp blocker evidence — 2026-07-30

## Decision

Codex Desktop remains a verified root-temp recurrence risk. AgentHub's
controllable environment and deployment paths are correct, but the current
Codex Desktop sandbox can still create `C:\tmp\sessions`. The empty observed
tree was moved recoverably into AgentHub quarantine and `C:\tmp` was absent in
the final live scan. AgentHub must not hide the proven recurrence risk with a
junction, ACL change, scanner exclusion, undocumented configuration, or by
disabling the sandbox.

## Current evidence

- Codex Desktop package at the latest recurrence:
  `OpenAI.Codex_26.721.11231.0_x64__2p2nqsd0c76g0`; the issue was first
  confirmed on `26.721.4979`.
- Codex CLI: `codex-cli 0.144.4`.
- Host-owned runtime:
  `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\f8d2abcb7481383b\bin\node_repl.exe`.
- Ten observed `node_repl.exe` wrappers were direct children of Codex
  `app-server` PID 10632. Its parent was `ChatGPT.exe` PID 2628, whose parent
  was `explorer.exe`.
- `C:\tmp` and `C:\tmp\sessions` were created at
  `2026-07-30T01:01:35Z`. The sessions directory was written as late as
  `2026-07-30T08:05:14Z` during this Codex Desktop run.
- After the restart and upgrade, the current Codex Desktop session recreated
  an empty `C:\tmp\sessions\<session-id>` tree at
  `2026-07-30T21:00:51Z`. It was moved recoverably to AgentHub quarantine;
  an upstream Chrome DevTools MCP smoke and the final live audit did not
  recreate it.
- Process and user `TMPDIR` both resolve below
  `%LOCALAPPDATA%\AgentHub`; process `TEMP` and `TMP` use the normal user
  temporary directory. The root path therefore is not caused by an
  uncontrolled AgentHub environment variable.
- `codex app-server --help` exposes general configuration, feature, transport,
  and analytics controls but no temp-root setting. The CLI exposes sandbox
  selection and a dangerous complete sandbox bypass, not a supported
  relocation control for Desktop's `node_repl` writable workspace.

These observations establish process ownership and the absence of a supported
AgentHub-side path correction. Windows did not retain a file-creation kernel
event tying an individual session directory to one PID, so that final
file-creation step remains a process-tree-and-timestamp attribution rather
than an ETW creator event.

## Required external fix

Codex Desktop must provide and honor a supported writable-workspace or sandbox
temp-root setting on Windows. After that control exists, AgentHub can pin it
below `%LOCALAPPDATA%\AgentHub`, remove `C:\tmp` after a reference/content
check, start a fresh Codex session, and verify that repeated tool calls do not
recreate the root path.

