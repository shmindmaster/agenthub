---
name: desktop-evidence
description: Use when a native Windows window or the whole desktop needs a screenshot or recording written to the AgentHub evidence root — not for web pages, and not for polished demo video.
---

# Desktop evidence

<!-- skill-kind: provider-reference -->
<!-- provider-channel: cli -->

**Do not start here.** Enter through `browser-evidence` when the target is not a
browser. Sibling catalogs (`use-playwright-mcp`, `use-playwright-cli`,
`use-playwright-test`) capture web pages. Polished delivery video is
`media-studio`.

This lane is **not** an MCP server. It does not appear in `registry/mcps.json`.
The helper is the provider:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Capture = Join-Path $Hub 'packages\browser-toolkit\scripts\Capture-Screen.ps1'
```

Evidence root (owned by that helper; do not invent a second path):

```text
%LOCALAPPDATA%\AgentHub\evidence\<task-slug>\
```

Never commit capture blobs to a repository. Never attach to the owner's
personal browser profile. Do not use Snagit, Snipping Tool, ZoomIt, or OBS as
the autonomous path. Do not call retired Chrome DevTools MCP screencast tools.

`computer.gui` on a surface (only `claude-cli` is recorded `true` today) may
drive the app being captured. It does not replace this helper for writing the
PNG or MP4.

## Commands

```powershell
pwsh -NoProfile -File $Capture -Action resolve-dir -Task <task-slug>
pwsh -NoProfile -File $Capture -Action screenshot -Task <task-slug>
pwsh -NoProfile -File $Capture -Action screenshot -Task <task-slug> -Title "Window Title"
pwsh -NoProfile -File $Capture -Action record -Task <task-slug> -Duration 20
pwsh -NoProfile -File $Capture -Action windows
```

Stdout is one JSON object with `output` / `directory`. Pass `-PlanOnly` to print
the plan without capturing.

## Procedure

1. Classify the target. A URL or web app belongs back in `browser-evidence`.
2. Pick a lowercase task slug. Resolve the evidence directory.
3. If a specific window is required, list titles (`-Action windows`) and pass
   `-Title` exactly. Otherwise capture the desktop.
4. Screenshot stills of each material state. Record only when motion is the
   claim. Maximum duration is 120 seconds.
5. Redact secrets, customer data, and unrelated desktop contents before sharing.
6. Report the file paths and what they show, separately from inference.
