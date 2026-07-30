# Codex Desktop root-temp blocker evidence — 2026-07-30

## Decision

`C:\tmp` remains a verified Codex Desktop platform blocker. AgentHub's
controllable environment and deployment paths are correct, but the current
Codex Desktop sandbox still creates `C:\tmp\sessions`. AgentHub must not hide
this result with a junction, ACL change, scanner exclusion, undocumented
configuration, or by disabling the sandbox.

## Current evidence

- Codex Desktop package:
  `OpenAI.Codex_26.721.4979.0_x64__2p2nqsd0c76g0`.
- Codex CLI: `codex-cli 0.144.4`.
- Host-owned runtime:
  `%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\f8d2abcb7481383b\bin\node_repl.exe`.
- Ten observed `node_repl.exe` wrappers were direct children of Codex
  `app-server` PID 10632. Its parent was `ChatGPT.exe` PID 2628, whose parent
  was `explorer.exe`.
- `C:\tmp` and `C:\tmp\sessions` were created at
  `2026-07-30T01:01:35Z`. The sessions directory was written as late as
  `2026-07-30T08:05:14Z` during this Codex Desktop run.
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

