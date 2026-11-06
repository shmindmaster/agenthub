# Plugin deployment

Every AgentHub plugin is named `ah-<package folder>` (for example `ah-product`, `ah-brave-search`, `ah-browser`) so the plugins group together in each host's list and are unmistakable when called (`ah-product:audit`). Hosts that show a display name show `AH-Product`, `AH-Brave-Search` and so on. The name is lowercase kebab-case because Grok, Antigravity, Cursor, Devin and Gemini reject mixed case and Windows folders ignore case.

Plugins come from one marketplace, `agenthub` (`C:/Repos/shmindmaster/agenthub`), plus the private `sarosh-private` marketplace for `ah-sarosh`. Validation requires a marketplace entry named `ah-<folder>` that points at `./packages/<folder>`.

Claude installs `ah-browser` so Code, Desktop, and Cowork can browse, capture, and test on a third-party gateway, where the plan browser is absent. Other native-browser hosts do not get it. It serves the hosts listed as "Use the client" in `packages/browser/skills/automate/references/hosts.md`. `ah-mobile-development` is installed disabled or on demand, because the Appium server runs only for mobile work. Claude and Codex use the vendor RepoWise plugins, so they do not install `ah-repowise`.

## Native first, no direct MCP

Every coding host gets a capability from the first of these that exists: its own official marketplace, its official community marketplace, the vendor's plugin in a catalog the host can load, then an `ah-*` plugin. `ah-descript`, `ah-exa`, `ah-notion`, `ah-firecrawl` and `ah-aws` are thin wrappers for that last step: one skill, one server, no hooks. Railway was removed on 2026-11-06: do not install `ah-railway` or any official Railway plugin.

`activationPolicy.pluginOnly` in `registry/mcps.json` lists each plugin-only host and the only direct entries allowed there, each with a reason. The sync writes nothing else to those hosts and removes any registry server already there. `pluginOwnersByHost` on each server records which plugin carries it. To add a server, give it an owner on every host, or a reason in `pluginOnly` for the hosts that cannot have one. `tests/Test-PluginOnlyMcp.ps1` fails on any other direct entry, and on anything in the shared `~/.agents/skills` folder.

Two hosts keep remote entries on purpose. Cline CLI can load `ah-*` servers, but the VS Code extension reads only `cline_mcp_settings.json`, so its official MCP Marketplace entries stay. OpenCode has no plugin catalog for those servers, and a remote entry is its documented route.

Do not install `aws-core` or `aws-data-analytics` (they run the proxy with `--skip-auth` and no profile).

## Per host

Run after a package or marketplace change. Version bumps matter only for hosts that copy.

| Host | Source | Refresh |
|---|---|---|
| Claude | marketplace `agenthub`, `sarosh-private` | `claude plugin marketplace update agenthub`, then `claude plugin install ah-<name>@agenthub --scope user`. The marketplace `renames` map migrates old settings keys. |
| Codex | marketplace `agenthub`, `sarosh-private` | `codex plugin remove <old>@agenthub`, then `codex plugin add ah-<name>@agenthub`. Codex copies into `~/.codex/plugins/cache`. Verified 2026-11-05: `codex plugin add` on an already-installed plugin refreshes it in place and leaves only the new version folder, so the remove is only needed to drop a plugin. `codex plugin marketplace upgrade agenthub` fails with "not configured as a Git marketplace" because this marketplace is a directory source read live, and it is not part of the refresh. |
| Copilot CLI | live local marketplace | `copilot plugin install ah-<name>@agenthub`. Loaded live from the repository; nothing is copied. |
| Factory Droid | marketplace `agenthub`, `personal` | `droid plugin marketplace update agenthub`, then `droid plugin update ah-<name>@agenthub`. Copies the working tree and labels it with the HEAD commit. Verified 2026-11-05: `droid plugin install ah-<name>@agenthub --scope user` now refuses an existing install with "already installed at user scope. Uninstall it first to change scope", so `update` is the refresh and `install` is the first-install form. |
| Qoder | marketplace `agenthub`, `sarosh-private` | `qodercli plugins marketplace update agenthub`, then `qodercli plugins update ah-<name>@agenthub`; `qodercli plugins install` is the first-install form. The marketplace step is not optional: without it `plugins update` reports success and reinstalls the version it already had cached. Verified 2026-11-05. The CLI prints unrelated provider-config warnings first. The cache at `~/.qoder/plugins/cache/agenthub/<name>` keeps every prior version folder and the newest is the copy the host resolves, so a stale sibling folder beside a current one is history, not drift. |
| Grok | local path | `grok plugin uninstall <old>`, then `grok plugin install C:/Repos/shmindmaster/agenthub/packages/<folder> --trust`. Use forward slashes. `plugin update` does nothing for a local install. Uninstall takes the name the manifest declares (`ah-product`), not the `<folder>-<hash>` id that `grok plugin list` prints first; passing that id fails with "not found". Grok renames each installed folder that way, so a scan matching `ah-*` folder names sees none of them. |
| Devin (formerly Windsurf) | local path, plus `CognitionAI/devin-marketplace` | `devin plugins update <name>` re-fetches and reinstalls at the latest HEAD and is the refresh; `devin plugins remove <old>` then `devin plugins install <path> --yes --local` is the first-install form. Desktop and the CLI it bundles share `%APPDATA%\devin\cli\plugins` and `%APPDATA%\devin\mcp_config.json`. `~/.config/devin` and `~/.codeium` are not read on Windows. Plugin manifests are read in the order `.devin-plugin`, `.claude-plugin`, root `plugin.json`. Do not run `devin mcp remove` on a signed-in server: it deletes the stored OAuth token. RepoWise here is `ah-repowise`. |
| Antigravity | local path | `agy plugin uninstall <old>`, then `agy plugin install <path>`. Copies the folder. |
| Cursor IDE, Cursor Agent | real folders in `~/.cursor/plugins/local` | Run `pwsh -NoProfile -File scripts/Install-CursorLocalPlugins.ps1`, and again after a package changes. The script is `#Requires -Version 7`, so launching it from the default `powershell.exe` aborts with `ScriptRequiresUnmatchedPSVersion`. Do not link: both surfaces share a loader that rejects a link whose target is outside that folder, and a Windows junction counts as a link. Cursor Agent also imports the plugins enabled in `~/.claude`. |
| Cline | junctions in `~/.agents/plugins` | Junction `ah-<name>` to the package folder. Check with `loadAgentPluginPackages` from `@cline/core`, which reports each plugin, its servers and any rejected field. The loader needs root `mcp.json` with a `type` on every server, and it rejects Claude-only skill fields such as `argument-hint`. `cline plugin install` is a different format and needs a code entry file. |
| VS Code Insiders | `chat.pluginLocations`, plus the Copilot catalog | Add the package path to `chat.pluginLocations` in `settings.json`. Native plugins come from `copilot plugin install`, which VS Code reads from `~/.copilot/installed-plugins`. |
| OpenCode | npm or git plugins | `opencode plugin add <spec>` for vendor plugins. `ah-*` packages have no manifest format here, so OpenCode has no `ah-*` plugins. |
| Amp | real folders in `~/.config/amp/plugins` | Run `scripts/Install-AmpPlugins.py`, and again after a package changes. It builds `<name>/index.ts` and puts each server in a `mcp.json` beside the plugin's skill. Amp has no catalog, rejects links out of the folder, expands `${VAR}` and sends `${env:VAR}` literally. A plugin's tools stay hidden until its skill loads, but third-party docs say the server still starts, so the installer leaves local servers out. |
| Warp | skill junctions and remote servers | Warp has no plugin format. Run `scripts/Install-WarpSkills.ps1` for the skills, and keep only the remote servers in `activationPolicy.pluginOnly` in `~/.warp/.mcp.json`. |
| Gemini CLI | none | The CLI is unlicensed on this account, so its extensions cannot be managed. |

## Session start

A plugin is packaging, not on-demand. Grok, Claude and Codex start every enabled plugin's servers with a session, and hooks arrive inside plugins too. Plugin servers therefore stay off by default, with RepoWise kept on for Claude and Codex. `activationPolicy.sessionStart` in `registry/mcps.json` lists each host's off switch, including the hosts where none was applied.

Grok also loads plugins installed for Claude. Turn those off with the `disabled` list under `[plugins]` in `~/.grok/config.toml`, because `grok plugin disable` cannot see them. `grok inspect` still lists a disabled plugin's hooks, so restart Grok to confirm. Hooks written for bash fail under PowerShell on Windows.

Vendor RepoWise carries hooks and runs a server per session, so Devin, Factory, Qoder and Grok use `ah-repowise`, which has no hooks.

A host that copies a plugin ignores a content change at the same version: `claude plugin update` says "already at the latest version" and leaves the cached copy stale. Bump the plugin version, or uninstall and install it again (Claude, Codex, Factory, Qoder, Grok, Devin and Antigravity all work that way). `ah-media-studio` keeps its version until a release changes it, because its kit and policy hard-code the number, so refresh it by reinstalling.

## Keeping hosts lean

`removedPlugins` in `registry/context-limits.json` lists vendor plugins taken off every host on 2026-11-04, with the reason. `scripts/Set-ContextLimits.py` reports any that return on Claude, Codex, Factory or Qoder. Reinstall one from the host's catalog when a task needs it. Every `ah-*` plugin stayed.

Daytona reaches every host. Claude and Factory use `daytona-skills` from their catalog, Devin installs `daytona/skills` with `devin plugins install daytona/skills --yes --local`, and Grok imports Claude's copy. The other hosts use `ah-daytona`, which has one skill, no server and no hook. `packages/daytona/NOTICE` names the upstream commit.

Clerk also reaches every host, but only ever from its own upstream: there is no `ah-clerk` package and there must not be one. Run `python scripts/Install-ClerkFleet.py` for a read-only plan, add `--apply` to install, or pass `--host <id>` to repair one host. `--audit` reads back the official skill texts against the upstream checkout and checks that each host's entry names `https://mcp.clerk.com/mcp` exactly. Claude, Codex, Copilot, Factory, Qoder and Devin install the vendor's own plugin through the host's plugin command; Grok and Antigravity install the upstream checkout; Cursor, Cline, Amp, VS Code Insiders, OpenCode, Warp and Gemini get host-local adapters. Desktop and CLI aliases share their primary host's configuration, and nothing is written into `~/.agents/skills`. [clerk-auth.md](clerk-auth.md) carries the rollout detail and the acceptance contract.

OpenCode has no plugin format here and `~/.agents/skills` holds no skills, so run `scripts/Install-WarpSkills.ps1 -WarpHome "$HOME\.config\opencode"` to link its skills.

Codex uses the owner's own `~/.codex/AGENTS.md`, not the compiled policy, and Cursor has no global file route, so a repository `AGENTS.md` carries instructions there. `~/.cursor/rules/agenthub-global-policy.mdc` is not synced: refresh it by hand if anything is found to read it.

## Context limits

`registry/context-limits.json` holds the context settings for every host, or the reason a host has none. `tests/Test-ContextLimits.ps1` fails if a plugin-only host is missing. Audit with `python scripts/Set-ContextLimits.py` and write with `--apply`. It backs up each changed file to `%LOCALAPPDATA%\AgentHub\backups`, and running sessions keep their old values until they restart.

Host updates can rewrite these files, so run the audit after one. Cline's `disabled` key is written over every server in `cline_mcp_settings.json`, so turn a server on in Cline's MCP panel when a task needs it.

Grok ships its user guide inside `grok.exe`. Read it there before guessing a key: `compat.claude.agents` gates `~/.claude/CLAUDE.md` and `compat.claude.rules` only gates rules directories. `grok inspect --json` then reports `compatibilityStatus: disabled` on the file. The file stays in the list, so read the status and not the count.

After any change: `pwsh -NoProfile -File scripts/Validate-AgentHub.ps1`, then `tests/Test-InstalledPluginFreshness.ps1`, which also fails if an un-prefixed registration is left on Claude or Codex.

A green freshness run proves the installed **cache** matches source. It does not
prove a host session loaded it. Several hosts say so out loud when refreshed:
Claude reports `Restart to apply changes` and Qoder reports `Run /plugins reload
to apply`. Until that restart happens the running session is still using the
previous copy, so record cache parity and loaded-session state as two rungs. The
one claim that follows from the test alone is that a fresh session will resolve
the current version.

`Sync-AgentHub.ps1 -Apply` does not deploy a capability runtime tree; it only
writes host MCP configuration. A package with a `deployedCatalog` row in
`registry/capabilities.json`, such as `mobile-development`, is refreshed solely
by `scripts/Sync-Capabilities.ps1 -Apply`. Measured 2026-11-05: `-Apply` on
`Sync-AgentHub.ps1` reported `Validation: OK` while the deployed catalog stayed
one version behind, and `Test-MobileDevelopment.ps1` correctly failed. That
deployer refuses a destination whose tree no longer matches the hash it recorded,
and the recorded hash does not survive a deployment made by another route, so a
legitimate refresh can need `-AdoptExisting`. Confirm first that the destination
holds nothing the source does not, then scope the run:
`pwsh -NoProfile -File scripts/Sync-Capabilities.ps1 -Apply -AdoptExisting -CapabilityId mobile-development`.

Keeping every host on the latest version is enforced by that test rather than by a schedule, because no AgentHub script may register a recurring job. It reads Claude's `installed_plugins.json` plus every cache a host copies into: Codex and Qoder by version folder, Cursor, Antigravity and Cline as flat folders, and Factory by nested manifest. Private overlay packages resolve under `overlays/personal/packages`, so `ah-sarosh` and `ah-linkedin` are covered rather than silently skipped.

It compares content and not only version, because a host that copies ignores a content change at an unchanged version. Measured 2026-11-05: `ah-sarosh` carried a stale `write/SKILL.md` on Antigravity and Factory while every copy reported 1.1.2, which no version comparison could have caught. A failure names the host and the exact command that fixes it. Copilot loads this repository live and Amp is rebuilt from source by `scripts/Install-AmpPlugins.py`, so neither carries a version to compare; `tests/Test-AmpPlugins.ps1` covers Amp's shape instead.

The test reads the live profile, so `tests/ci-skip.json` skips it on CI runners that have no hosts installed. A plain local `tests/Run-AllTests.ps1` run executes it.

`Sync-AgentHub.ps1` does not copy the registry to the runtime folder. After changing `registry/mcps.json`, run `scripts/Sync-Capabilities.ps1 -CapabilityId mobile-development -Apply`, or `tests/Test-MobileDevelopment.ps1` fails on `authorityParity=False`.

## Instructions

`scripts/Sync-Instructions.ps1` compiles the host instruction files from the overlay policy. Audit does not restage, so diff a real render before applying: run `-Apply -UserProfile <empty temp dir>` and compare its output with the deployed file.
