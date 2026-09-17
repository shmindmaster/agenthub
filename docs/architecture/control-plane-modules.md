# Control-plane modules

The sync scripts are orchestrators. Path materialization, host loading, and
capability visibility each have one module under `scripts/lib/`. A script
must not invent a second rebase.

## Layering

1. **Portable registry data.** Tracked host destinations are templates,
   never a machine username. Package `canonicalSource` values stay
   repository-relative. Templates use `/` and these tokens:

   | Token | Alias | Windows | macOS | Linux |
   | --- | --- | --- | --- | --- |
   | `{userHome}` | `{userProfile}` | `%USERPROFILE%` | `$HOME` | `$HOME` |
   | `{localData}` | `{localAppData}` | `%LOCALAPPDATA%` | `~/Library/Application Support` | `$XDG_DATA_HOME` or `~/.local/share` |
   | `{roamingConfig}` |  | `%APPDATA%` | `~/Library/Application Support` | `$XDG_CONFIG_HOME` or `~/.config` |

   A vendor path that is `~/.foo` on every OS stays `{userHome}/.foo`.
   Use `{roamingConfig}` or `{localData}` only where the product actually
   uses the OS config or data root (Cursor and VS Code user settings,
   Devin's `%APPDATA%` / `~/.config` split, this control plane's own
   runtime). An `AppData` segment left in a template is a Windows install
   pin (Programs, WinGet, a `.exe` under AppData). It expands on Windows
   and is left unbound on macOS and Linux — it is not rewritten into a
   fake `Application Support/Programs` path.
2. **Binding at the edge.** `scripts/lib/PathBinding.ps1` is the only
   expander and the only absolute-path rebase. Callers pass a binding
   context (target profile, recorded registry profile, invoking profile).
3. **Host catalog.** `scripts/lib/HostCatalog.ps1` loads `agents.json` and
   binds every path-shaped field before a writer reads it.
4. **Capability graph.** `scripts/lib/CapabilityGraph.ps1` loads
   `capabilities.json` and merges `overlays/personal/capabilities.json` when
   the personal overlay is present. Private packages resolve under
   `overlays/personal/packages/<id>/`. Public packages (including RepoWise)
   stay under `packages/<id>/`. Core never imports a personal package id that
   the overlay has not enabled.
5. **Sync orchestration.** `scripts/lib/SyncOrchestrator.ps1` names the
   validate-then-sync step list. `scripts/AgentHub.ps1` delegates; it does
   not reimplement writers.
6. **Policy split.** `policy-core.md` is the portable policy. The personal
   overlay contributes `overlays/personal/policy-fragment.md`. This
   checkout's compiled deployment document remains
   `global-agent-policy.md` and is not part of a public export.

## Dependency direction

```text
PathBinding  <—  HostCatalog  <—  Sync-* scripts
CapabilityGraph  <—  Sync-* scripts
overlays/personal  —depends on—>  core registry
core  —must not import—>  overlays/personal or packages/sarosh-*
private packages live only under overlays/personal/packages/
```

## PathBinding contract

- Tokens expand against the binding context, then `/` becomes the host
  separator. `{userProfile}` and `{localAppData}` remain aliases.
- Supported platforms are `windows`, `darwin`, and `linux`. Those three
  cover the coding-agent market. PowerShell 7+ is the runtime on macOS
  and Linux; Windows PowerShell 5.1 remains supported on Windows. There
  is no iOS or Android host layout.
- An absolute path under the recorded registry profile (or, if that field
  is absent, the invoking profile) rebases onto the target home. A POSIX
  absolute (`/home/...`) rebases the same way; it is not refused.
- A UNC path or a drive-letter path that uses forward slashes is refused.
  Those shapes previously skipped rebase and wrote the live destination.
- Binding is idempotent: a path already under the target profile is left
  alone. `{{globalPolicy}}` is not a path token and is not rewritten.
- A Windows-only install pin is not materialized on darwin or linux.

## Overlay

`overlays/personal/overlay.json` lists private capability ids this machine
loads. `overlays/personal.example/` is the template for a fresh checkout.
`AGENTHUB_OVERLAY=off` resolves the public graph only. Absence of the
overlay directory is the same as off.

A gitignored `agenthub.profile.json` (see `agenthub.profile.example.json`)
may pin local roots. It is never required for a checkout that can use
`$env:USERPROFILE` (Windows) or `$env:HOME` (macOS and Linux). An optional
`platform` field forces `windows`, `darwin`, or `linux` for a dry run.
