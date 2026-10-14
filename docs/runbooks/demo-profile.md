# Demo profile: audit, apply, audit without touching the fleet

`scripts/AgentHubDemoProfile.ps1` builds a throwaway profile in which
`Sync-Instructions.ps1` can be filmed reporting drift, fixing it, and
reporting clean around a one-line policy edit. Nothing in the real fleet is
read for private content or written.

## What the profile is

| Path under the root | Contents |
| --- | --- |
| `.agenthub-demo-profile.json` | Marker. `Remove` and a reset `New` delete only a root that carries it for that exact path. |
| `repo\registry\agents.json` | Snapshot of this checkout's host catalog. |
| `repo\policy-core.md` | The public portable policy. It has no owner identity, so it is safe to show. |
| `home\` | The throwaway user profile that host instruction files are written into. |

The default root is `%LOCALAPPDATA%\AgentHub\demo\agenthub-profile`. Pass
`-Root <dir>` to use another scratch directory.

Every sync runs `Sync-Instructions.ps1 -RepositoryRoot <root>\repo
-UserProfile <root>\home` with `AGENTHUB_OVERLAY=off`. Staging goes under
`<root>\home`, not the live `%LOCALAPPDATA%\AgentHub\runtime`.

The script refuses:

- a root that is, or contains, the real user profile
- a root inside a real host configuration directory (`.claude`, `.codex`,
  `.agents`, `AppData\Roaming` and the others listed in the script)
- a root inside this checkout
- a drive root
- an existing directory without its marker

It registers nothing and starts no service, and its child processes inherit
the caller's hidden console.

## Publishable output

All output, refusals included, prints the invoking user's home as `~`
(`scripts/lib/DisplayPath.ps1`, `Format-AgentHubDisplayText`). Only whole
path segments are replaced, so `C:\Users\Alex` becomes `~` but
`C:\Users\Alexis` does not. Pass `-NoCrop` to see raw paths.

## The sequence

Run from the repository root, in a hidden console:

```powershell
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action New         # one command creates (or resets)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit       # claude ... missing   (15 missing)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply       # claude ... updated   (14 updated)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit       # claude ... current   (15 current)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action EditPolicy  # + one line in the profile's policy-core.md
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Diff        # shows that one line
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit       # claude ... drift     (15 drift)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Apply       # claude ... updated   (14 updated)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Audit       # claude ... current   (15 current)
pwsh -NoProfile -File scripts\AgentHubDemoProfile.ps1 -Action Remove      # one command destroys
```

`Apply` updates 14 files while 15 hosts are in the work set, because
`opencode` and `opencode-desktop` share one destination: the second reports
`current` after the first writes it.

The counts are fixed for a given commit's `registry/agents.json`.
`EditPolicy` is idempotent and always appends the same line.

`tests/Test-AgentHubDemoProfile.ps1` pins the sequence, the cropping, the
refusals, and the real-fleet timestamps.
