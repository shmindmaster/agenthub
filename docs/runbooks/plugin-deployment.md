# Plugin deployment

Every AgentHub plugin is named `ah-<package folder>` (for example `ah-product`, `ah-brave-search`, `ah-browser`) so the plugins group together in each host's list and are unmistakable when called (`ah-product:audit`). Hosts that show a display name show `AH-Product`, `AH-Brave-Search` and so on. The name is lowercase kebab-case because Grok, Antigravity, Cursor and Devin reject mixed case and Windows folders ignore case.

Keep the portable `plugin.json` within the [Agent Plugins manifest schema](https://agent-plugins.org/plugin-authors/manifest). Bundle square artwork under `assets/`. Use the supported icon fields in each host projection. Codex uses `interface.composerIcon` and `interface.logo`. Cursor, Antigravity and Devin use `logo` on their native manifests. Claude's `icon` is directory listing metadata. VS Code and Cline use their built-in presentation. The marketplace display labels and host projections must agree.

Plugins come from one marketplace, `agenthub` (`C:/Repos/shmindmaster/agenthub`), plus the private `sarosh-private` marketplace for `ah-sarosh`. Validation requires a marketplace entry named `ah-<folder>` that points at `./packages/<folder>`.

`ah-browser` gives local agents a shared routing skill. It can select the intended existing Chrome or Edge profile through a native tool or Tencent BrowserSkill and use agent-browser for isolated work. BrowserSkill needs a local `bsk` CLI and the user-enabled extension in each intended profile. See [browser routing and verification](../../packages/browser/skills/automate/references/hosts.md). `ah-mobile-development` is installed disabled or on demand, because the Appium server runs only for mobile work.

## Native marketplace and hosted MCP ownership

Every coding host gets a capability from the first of these that exists: its own official marketplace, its official community marketplace, the vendor's plugin in a catalog the host can load, then an `ah-*` plugin. AgentHub ships an `ah-*` plugin only when no vendor plugin exists for a retained host (owner direction 2026-11-13, SH-4636). `ah-assemblyai` is the remaining thin wrapper; Context7, Linear, Notion, Exa, Daytona, AWS and Descript come from their vendors, and Brave Search is no longer used. Railway was removed on 2026-11-06: do not install `ah-railway` or any official Railway plugin.

`activationPolicy.pluginOnly` in `registry/mcps.json` lists each plugin-only host and the only direct entries allowed there, each with a reason. The sync writes nothing else to those hosts and removes any registry server already there. `pluginOwnersByHost` on each server records which plugin carries it. To add a server, give it an owner on every host, or a reason in `pluginOnly` for the hosts that cannot have one. `tests/Test-PluginOnlyMcp.ps1` fails on any other direct entry, and on anything in the shared `~/.agents/skills` folder.

Cline CLI can load `ah-*` servers, but the VS Code extension reads only `cline_mcp_settings.json`, so its official MCP Marketplace entries stay. OpenCode uses native remote configuration for services without a supported vendor plugin.

AWS supports a direct hosted OAuth MCP connection at `https://aws-mcp.us-east-1.api.aws/mcp`. Use the vendor's documented `?oauth=initialize` suffix for clients that need explicit OAuth discovery. Keep the vendor AWS skills installed and give the connection one owner. Claude can suppress `plugin:aws-core:aws-mcp` through `deniedMcpServers`. Codex can disable the bundled server through `[plugins."<plugin>@<marketplace>".mcp_servers.aws-mcp] enabled = false`. Both can then use a native remote `aws-mcp` entry. OpenCode uses `mcp.servers.aws-mcp` with `type: "remote"`, and Cursor and Kiro use their native remote MCP configuration. Grok's existing disabled state stays until its effective remote override is verified. These owner-configured exceptions are listed in `activationPolicy.pluginOnly`. They remain outside generated `mcpServers` rows.

Complete native OAuth separately in each host and verify the intended AWS identity before invoking account operations. Existing IAM permissions govern access. OAuth uses one identity per connection, so workflows that switch profiles need separate connections or an explicitly selected SigV4 fallback. Preserve a running proxy until its hosted replacement connects. Configuration and plugin installation establish the next session's setup, while a runtime connection check establishes readiness. AWS documents the endpoint, client configuration, identity limitations, and consent requirements in its [OAuth guide](https://docs.aws.amazon.com/agent-toolkit/latest/userguide/oauth-authentication.html).

Minimize authentication prompts by retaining each host's native credential store and automatic refresh. Reuse an active browser sign-in for the selected account; do not log out, clear credentials, recreate an unchanged connection, or reset consent during plugin updates. Keep one active connection per service and identity in each host, suppress duplicate plugin proxies, and authorize optional integrations when their workflows need them. AWS access tokens last one hour and native refresh tokens last up to twelve hours; an expired refresh session can still require sign-in. A manually pasted one-hour bearer token does not provide this refresh behavior. Account authentication is separate from coding-tool approval settings.

For unattended AWS work, an existing automatically renewable profile can use AWS's [non-interactive token grant](https://docs.aws.amazon.com/signin/latest/userguide/aws-mcp-server.html#non-interactive-authorization) through a host's native dynamic header hook. `scripts/aws-mcp-headers.py --profile <explicit-profile> --aws-cli <absolute-cli-path>` emits only the required JSON headers to the host, with no token file or resident server. Give the Python executable and script absolute paths in the hook command. Claude's [`headersHelper`](https://code.claude.com/docs/en/mcp#use-dynamic-headers-for-custom-authentication) and Codex's [`http_headers_helper`](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) refresh after an authentication rejection. Use the base AWS MCP URL for this grant; `?oauth=initialize` is for interactive OAuth discovery. Codex stored OAuth credentials take precedence over helper headers, so check the selected credential source rather than assuming a configured helper is active. Other hosts keep their native OAuth flow unless they document an equivalent hook. The profile must already renew without a human; this helper does not remove an identity provider's sign-in requirements.

A remote URL saves local server resources only when execution moves off the machine. Browser Use offers a hosted browser MCP with separate cloud credentials. Remote Desktop Commander continues to require a local device agent. Local filesystem, signed-in browser, device, and 1Password integrations retain their local dependencies. Use each host's built-in tools where they provide the required workflow and keep remaining local integrations task-scoped. Vendor plugin caches can contain unused servers and previous versions, so an audit must distinguish enabled installations, cached definitions, runtime connections, and authenticated tool calls.

## Per host

Run after a package or marketplace change. Version bumps matter only for hosts that copy.

| Host | Source | Refresh |
|---|---|---|
| Claude | marketplace `agenthub`, `sarosh-private` | `claude plugin marketplace update agenthub`, then `claude plugin install ah-<name>@agenthub --scope user`. The marketplace `renames` map migrates old settings keys. |
| Codex | marketplace `agenthub`, `sarosh-private` | `codex plugin remove <old>@agenthub`, then `codex plugin add ah-<name>@agenthub`. Codex copies into `~/.codex/plugins/cache`. Verified 2026-11-05: `codex plugin add` on an already-installed plugin refreshes it in place and leaves only the new version folder, so the remove is only needed to drop a plugin. `codex plugin marketplace upgrade agenthub` fails with "not configured as a Git marketplace" because this marketplace is a directory source read live, and it is not part of the refresh. |
| Copilot CLI | live local marketplace | `copilot plugin install ah-<name>@agenthub`. Loaded live from the repository; nothing is copied. |
| Factory Droid | marketplace `agenthub`, `personal` | `droid plugin marketplace update agenthub`, then `droid plugin update ah-<name>@agenthub`. Copies the working tree and labels it with the HEAD commit. Verified 2026-11-05: `droid plugin install ah-<name>@agenthub --scope user` now refuses an existing install with "already installed at user scope. Uninstall it first to change scope", so `update` is the refresh and `install` is the first-install form. Since Droid 1.6.0 (measured 2026-11-09) the install renames `.mcp.json` to `mcp.json` with compact JSON and `agents/` to `droids/`; the audit compares those renamed files by content. |
| Grok | local path | `grok plugin uninstall <old>`, then `grok plugin install C:/Repos/shmindmaster/agenthub/packages/<folder> --trust`. Use forward slashes. `plugin update` does nothing for a local install. Uninstall takes the name the manifest declares (`ah-product`), not the `<folder>-<hash>` id that `grok plugin list` prints first; passing that id fails with "not found". Grok renames each installed folder that way, so a scan matching `ah-*` folder names sees none of them. |
| Devin (formerly Windsurf) | local path, plus `CognitionAI/devin-marketplace` | `devin plugins update <name>` re-fetches and reinstalls at the latest HEAD and is the refresh; `devin plugins remove <old>` then `devin plugins install <path> --yes --local` is the first-install form. Desktop and the CLI it bundles share `%APPDATA%\devin\cli\plugins` and `%APPDATA%\devin\mcp_config.json`. `~/.config/devin` and `~/.codeium` are not read on Windows. Plugin manifests are read in the order `.devin-plugin`, `.claude-plugin`, root `plugin.json`. Do not run `devin mcp remove` on a signed-in server: it deletes the stored OAuth token. |
| Antigravity | local path | `agy plugin uninstall <old>`, then `agy plugin install <path>` from a temporary projection of the tracked package. `agy` 1.5.3 strict validation rejects the root `plugin.json`, `mcp.json` and `.mcp.json` that other hosts read, so the projection omits them and Antigravity loads servers from `mcp_config.json`. For AH-Product run `scripts/Install-AntigravityProductPlugin.ps1`. Its validated copy carries the skills and resources and excludes the shared reviewer that Antigravity cannot load. |
| Cursor IDE, Cursor Agent | real folders in `~/.cursor/plugins/local` | Run `pwsh -NoProfile -File scripts/Install-CursorLocalPlugins.ps1`, and again after a package changes. The script is `#Requires -Version 7`, so launching it from the default `powershell.exe` aborts with `ScriptRequiresUnmatchedPSVersion`. Do not link: both surfaces share a loader that rejects a link whose target is outside that folder, and a Windows junction counts as a link. Cursor Agent also imports the plugins enabled in `~/.claude`. |
| Cline | junctions in `~/.agents/plugins` | Junction `ah-<name>` to the package folder. Check with `loadAgentPluginPackages` from `@cline/core`, which reports each plugin, its servers and any rejected field. The loader needs root `mcp.json` with a `type` on every server, and it rejects Claude-only skill fields such as `argument-hint`. `cline plugin install` is a different format and needs a code entry file. |
| VS Code Insiders | `chat.pluginLocations`, plus the Copilot catalog | Add the package path to `chat.pluginLocations` in `settings.json`. Native plugins come from `copilot plugin install`, which VS Code reads from `~/.copilot/installed-plugins`. A mapping may instead declare `nativeOwnerHost: "copilot"` (as `ah-coding-agent-dispatch` does): the row then reports under `vscode-insiders` but observes and installs through Copilot alone, never twice. |
| Cursor Agent | shares the Cursor local plugin | `cursor-agent` rows declare `nativeOwnerHost: "cursor"`: one `~/.cursor/plugins/local` install satisfies the IDE and the agent surface. The owner must be an active host with a self-owned mapping for the same capability; chained or cyclic owners are refused before any mutation. |
| OpenCode | npm or git plugins | `opencode plugin add <spec>` for vendor plugins. `ah-*` packages have no manifest format here, so OpenCode has no `ah-*` plugins. |
| Amp | real folders in `~/.config/amp/plugins` | Run `scripts/Install-AmpPlugins.py`, and again after a package changes. It builds `<name>/index.ts` and puts each server in a `mcp.json` beside the plugin's skill. Amp has no catalog, rejects links out of the folder, expands `${VAR}` and sends `${env:VAR}` literally. A plugin's tools stay hidden until its skill loads, but third-party docs say the server still starts, so the installer leaves local servers out. |
| Warp | skill junctions and remote servers | Warp has no plugin format. Run `scripts/Install-WarpSkills.ps1` for the skills, and keep only the remote servers in `activationPolicy.pluginOnly` in `~/.warp/.mcp.json`. |
| Kilo, MiMo Code | host-local skill junctions | Neither has an `ah-*` plugin format. `Sync-Plugins` links `skills/*` of a mapped package through `Install-WarpSkills.ps1 -WarpHome ~/.kilocode` or `~/.mimocode` (native skill projection; Kilo's root is documented in its vendor migration doc, MiMo's in the mimo-code README). `ah-coding-agent-dispatch`, `ah-funding` and `ah-media-studio` are mapped this way, because none needs an MCP server (Media Studio's tools are read from `%LOCALAPPDATA%\AgentHub\media-studio\_shared\tools`, which `Sync-MediaStudioKit.ps1` fills for every host); a package with a server stays unmapped until a direct MCP exception is approved for these hosts. |

## OpenCode Go on Forge

On Forge, OpenCode 2.2.7 successfully ran `opencode-go/deepseek-v4.1-flash` with `OPENCODE_API_KEY` supplied at runtime. For a provider-only smoke test, use a synthetic prompt with tools and MCP servers disabled. Keep the key out of configuration files and logs.

If you test OpenCode 1.19.5 alongside 2.x, use separate XDG data, state, and cache directories. The two versions use incompatible session databases.

## Session start

A plugin is packaging, not on-demand. Grok, Claude and Codex start every enabled plugin's servers with a session, and hooks arrive inside plugins too. Plugin servers therefore stay off by default. `activationPolicy.sessionStart` in `registry/mcps.json` lists each host's off switch, including the hosts where none was applied.

Grok also loads plugins installed for Claude. Turn those off with the `disabled` list under `[plugins]` in `~/.grok/config.toml`, because `grok plugin disable` cannot see them. `grok inspect` still lists a disabled plugin's hooks, so restart Grok to confirm. Hooks written for bash fail under PowerShell on Windows.


A host that copies a plugin ignores a content change at the same version: `claude plugin update` says "already at the latest version" and leaves the cached copy stale. Bump the plugin version, or uninstall and install it again (Claude, Codex, Factory, Grok, Devin and Antigravity all work that way). `ah-media-studio` keeps its version until a release changes it, because its kit and policy hard-code the number, so refresh it by reinstalling.

## Keeping hosts lean

`removedPlugins` in `registry/context-limits.json` lists vendor plugins taken off every host on 2026-11-04, with the reason. `scripts/Set-ContextLimits.py` reports any that return on Claude, Codex or Factory. Reinstall one from the host's catalog when a task needs it. Every `ah-*` plugin stayed.

Daytona reaches every host. Claude and Factory use `daytona-skills` from their catalog, Devin installs `daytona/skills` with `devin plugins install daytona/skills --yes --local`, and Grok imports Claude's copy. Codex installs `daytona@daytona` after `codex plugin marketplace add https://github.com/daytona/skills.git`, and Antigravity runs `agy plugin install https://github.com/daytona/skills.git`. AgentHub no longer ships `ah-daytona`.

Clerk also reaches every host, but only ever from its own upstream: there is no `ah-clerk` package and there must not be one. Run `python scripts/Install-ClerkFleet.py` for a read-only plan, add `--apply` to install, or pass `--host <id>` to repair one host. `--audit` reads back the official skill texts against the upstream checkout and checks that each host's entry names `https://mcp.clerk.com/mcp` exactly. Claude, Codex, Copilot, Factory and Devin install the vendor's own plugin through the host's plugin command; Grok and Antigravity install the upstream checkout; Cursor, Cline, Amp, VS Code Insiders, OpenCode and Warp get host-local adapters. Kilo and MiMo Code get the official skills only, with no Clerk server. Desktop and CLI aliases share their primary host's configuration, and nothing is written into `~/.agents/skills`. [clerk-auth.md](clerk-auth.md) carries the rollout detail and the acceptance contract.

OpenCode has no plugin format here and `~/.agents/skills` holds no skills, so run `scripts/Install-WarpSkills.ps1 -WarpHome "$HOME\.config\opencode"` to link its skills.

Codex uses the owner's own `~/.codex/AGENTS.md`, not the compiled policy, and Cursor has no global file route, so a repository `AGENTS.md` carries instructions there. `~/.cursor/rules/agenthub-global-policy.mdc` is not synced: refresh it by hand if anything is found to read it.

## Context limits

`registry/context-limits.json` holds the context settings for every host, or the reason a host has none. `tests/Test-ContextLimits.ps1` fails if a plugin-only host is missing. Audit with `python scripts/Set-ContextLimits.py` and write with `--apply`. It keeps no backup copy and prints each changed file with its before and after hash, and running sessions keep their old values until they restart.

Host updates can rewrite these files, so run the audit after one. Cline's `disabled` key is written over every server in `cline_mcp_settings.json`, so turn a server on in Cline's MCP panel when a task needs it.

Grok ships its user guide inside `grok.exe`. Read it there before guessing a key: `compat.claude.agents` gates `~/.claude/CLAUDE.md` and `compat.claude.rules` only gates rules directories. `grok inspect --json` then reports `compatibilityStatus: disabled` on the file. The file stays in the list, so read the status and not the count.

After any change, run `scripts/Validate-AgentHub.ps1`, `tests/Test-PortablePluginSchemas.ps1`, `tests/Test-PluginManifests.ps1`, and `tests/Test-InstalledPluginFreshness.ps1`. The freshness check also fails if an un-prefixed registration is left on Claude or Codex.

A green freshness run proves the installed **cache** matches source. It does not
prove a host session loaded it. Claude says so out loud when refreshed:
it reports `Restart to apply changes`. Until that restart happens the running session is still using the
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

Keeping every host on the latest version is enforced by that test rather than by a schedule, because no AgentHub script may register a recurring job. It reads Claude's `installed_plugins.json` plus every cache a host copies into: Codex by version folder, Cursor, Antigravity and Cline as flat folders, and Factory by nested manifest. Private overlay packages resolve under `overlays/personal/packages`, so `ah-sarosh` and `ah-linkedin` are covered rather than silently skipped.

It compares content and not only version, because a host that copies ignores a content change at an unchanged version. Measured 2026-11-05: `ah-sarosh` carried a stale `write/SKILL.md` on Antigravity and Factory while every copy reported 1.1.2, which no version comparison could have caught. A failure names the host and the exact command that fixes it. Copilot loads this repository live and Amp is rebuilt from source by `scripts/Install-AmpPlugins.py`, so neither carries a version to compare; `tests/Test-AmpPlugins.ps1` covers Amp's shape instead.

The test reads the live profile, so `tests/ci-skip.json` skips it on CI runners that have no hosts installed. A plain local `tests/Run-AllTests.ps1` run executes it.

`Sync-AgentHub.ps1` does not copy the registry to the runtime folder. After changing `registry/mcps.json`, run `scripts/Sync-Capabilities.ps1 -CapabilityId mobile-development -Apply`, or `tests/Test-MobileDevelopment.ps1` fails on `authorityParity=False`.

## Instructions

`scripts/Sync-Instructions.ps1` compiles the host instruction files from the overlay policy. Audit does not restage, so diff a real render before applying: run `-Apply -UserProfile <empty temp dir>` and compare its output with the deployed file.

## Fleet plugin command

Run a read-only plan with optional filters.

~~~powershell
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -Json
pwsh -NoProfile -File scripts/AgentHub.ps1 plugins -HostId cursor -PluginId ah-browser -Json
~~~

Add `-Apply` to repair managed drift. Apply requires the clean primary `main` checkout, matching published `origin/main`, successful CI on that exact commit, and registry validation. Alternate user profiles are audit-only. The planner distinguishes source/cache parity from session load. Native activation, account entitlement and provider acceptance remain separate checks.

The command records version and source-hash evidence under the local AgentHub runtime before invoking an installer. It holds an exclusive deployment lock and stops on failed readback. Cursor and Amp package copies restore from the prior package backup. Grok and Antigravity can reinstall the backed-up package through their native CLI. Other native registration failures retain the prior cache evidence and stop with a host-specific recovery requirement. Review the receipt before resuming that wave. A verified install deletes its rollback copy, and a run where every change verified deletes its receipt, so `runtime/plugin-deployment` only ever holds evidence for a failure.

An absent native registration stays blocked until its approved ownership and activation are established. The audit reports direct Claude MCP entries and loose shared skills as unmanaged conflicts. It preserves them. Unsupported legacy mappings stay blocked.

## Forge operator sessions

From a terminal with the existing `forge` SSH alias, run
`Invoke-CodingAgent.ps1 -Forge -List` to see the installed Forge clients.
Use `-Forge -HostId <id> -Cwd /srv/work/agenthub-runner/worktrees/<task>`
to open a client as the unprivileged runner. Provision the worktree on Forge
from a claimed Linear issue before launching. OpenClaw opens its local
terminal UI, whose workspace is controlled by its native configuration.
The SSH route does not forward workstation credentials. Complete provider
and MCP authorization in the runner's native profile before using a client.
An installed binary or registered MCP endpoint is not an authenticated smoke.

Use `-Auth` for local sign-in commands, or `-Forge -Auth` for runner
commands. Add `-HostId grok` or another listed ID to narrow the output.
The command lists each client's native sign-in command. When operating for
the user, start the login in the target client and open the provider's
authorization URL in the user's browser. Leave sign-in and consent to the
user. Keep the login process running until it confirms completion.

For GitHub, authorize the runner with `gh auth login --hostname github.com
--git-protocol https --web` and run `gh auth setup-git`. Verify repository
access under the runner account before pushing. Git and `gh` cover branch
and pull request operations for clients with a shell.

Choose `grok-browser` for Forge QA with an isolated local Chrome profile.
Prefer each plan’s native client integration when it is available. Clients
can also use the Anthropic or OpenAI compatible endpoint documented for the
plan. On Forge, use an explicit `claude-*` or `codex-*`
route: `qwen`, `zai`, `mimo`, or `go` selects the corresponding
subscription. Keep native Claude and Codex logins on Windows. Grok and Kiro
use their native account logins on both hosts. In OpenCode, use
`opencode-qwen` for Qwen or `opencode-go` for the Forge Go workspace and
DeepSeek V4.1 Flash.
Choose `opencode-zai` for the runner's Z.ai Coding Plan and its four Z.ai
MCPs. On Windows, select that plan with
`-HostId opencode -Model zai-coding-plan/glm-5.3`. This Windows route
supports workspace edits and Z.ai MCPs, with shell tools disabled.
On Windows use `codex --profile qwen` with the user environment reference.
To keep an interactive task alive across SSH disconnects, start Herdr or
tmux as `agenthub-runner` on Forge and launch the client inside its pane.
From an existing Forge terminal, run the installed dispatch skill's
`python3 forge-session.py --list` or
`python3 forge-session.py --host <id> --cwd <Forge-worktree>`.

The official [Z.ai Cursor guide](https://docs.z.ai/devpack/tool/cursor) and
[Qwen Cursor guide](https://docs.qwencloud.com/developer-guides/clients-and-developer-tools/cursor)
describe Cursor editor model settings for vendor-compatible endpoints. Forge
Cursor CLI does not consume those editor settings and instead requires Cursor
credentials through its [native CLI authentication](https://cursor.com/docs/cli/reference/authentication).

The Forge Codex sandbox uses the Ubuntu `bubblewrap` package. On Ubuntu
24.04, allow user namespaces only for the root-owned `/usr/bin/bwrap` via
AppArmor. Verify a read and a denied write with `codex sandbox -- <command>`;
leave the system-wide AppArmor restriction enabled. In the MiMo Codex
profile set `web_search = "disabled"`: its Responses gateway rejects the
built-in web search tool. This does not disable browser QA or MCPs.

OpenCode v2 stores remote MCP servers under `mcp.servers`. Forge Linear
OAuth is per client: use `opencode mcp auth linear` for OpenCode and
`codex mcp login linear` for Codex. If a Forge client uses a loopback
callback, relay it to that client's active listener over SSH or use the
client's callback input when supported. Keep the listener private; never
put the callback URL in chat, logs, or an issue. Verify the resulting
session by reading a Linear issue from the client that signed in.

Forge operator sessions are interactive. Linux tool isolation and exact-head
review acceptance are tracked under
[SH-4409](https://linear.app/shorg/issue/SH-4409).

## Forge unattended intake

`skills/dispatch/forge-intake.mjs` turns one eligible Linear issue into one
draft pull request without any workstation online. A systemd timer on Forge
(`forge-intake.timer`, 30 minutes after the previous run ends) starts
`forge-intake.service` as `agenthub-runner`. It runs from the root-owned release
catalog at `/opt/agenthub/current`, so the runner cannot edit its own
allowlist, caps or routes. `forge-intake.json` holds all of them.

A run has three headless Codex sessions on a token plan, and a wrapper that
keeps GitHub credentials away from the model:

1. **Select and claim** (read-only sandbox). Releases `agent:forge` claims that
   are stale (8 h), then takes the best unclaimed issue: team Sh-org, state
   Backlog or Todo, no assignee, labelled `type:bug`, `type:tech-debt` or
   `area:docs`, labelled with a mapped app (today only `app:agenthub`), and
   carrying none of `type:epic`, `type:research`, `attention:*`, `agent:*`,
   `risk:compliance`, `risk:security`, `stage:*`, `lane:*`, `funding:*`. It adds
   `agent:forge` and sets In Progress (SH-4063). The wrapper re-checks the
   labels the agent reports and refuses an ineligible claim, and the selector is
   told to query `list_issues` once for each mapped app label instead of
   scanning the whole backlog. When the selector has claimed an issue the rules
   exclude, the close-out restores it to its earlier state with a comment and
   the wrapper retires it after that single run instead of burning a second
   one: on 2026-11-12 an `app:empowera` bug was claimed by mistake, restored to
   Backlog and retired.
2. **Implement** (permission profile, network off, Linear read-only). The
   agent works in a fresh clone, follows the repository's AGENTS.md, and leaves
   its edits uncommitted: the wrapper commits.
3. **Verify, push, open the PR** (wrapper only). Before committing it checks
   that the agent left `.git` hooks and config untouched, and every wrapper git
   call runs with hooks, fsmonitor, external diff, textconv and global config
   disabled. It refuses an empty diff, more than 30 files or 1200 changed lines,
   binary files, symlinks, submodules, mode changes, changes under `.github/`,
   `registry/`, `.agents/`, `.claude-plugin/`, `AGENTS.md`, `CLAUDE.md`, any
   `.mcp.json` or package `hooks/`, secret-shaped paths or added lines,
   uncommitted leftovers and `git diff --check` failures. Agent-written text is
   redacted for secret-shaped content before it reaches the PR or Linear, and the
   issue id is validated (`SH-<digits>`) before it becomes a path or branch.
   It pushes `forge/<issue>-<slug>`, opens a **draft** PR, and removes the clone.
   The agent never edits `registry/capabilities.json` or any version: both are
   protected, and a hand-computed hash failed CI on #125. When the diff touches
   `packages/<name>/` the PR body ends with a note naming those packages, and
   the reviewer bumps each version (`scripts/Bump-PackageVersion.ps1`, plus
   `metadata.version` in that package's SKILL.md by hand) and recomputes the
   contentHash with `scripts/RegistryContentHash.ps1` or, where there is no
   `pwsh`, with `node scripts/registry-content-hash.mjs packages/<name>`: a
   Node port that produces the same hash and is test-enforced by
   `scripts/registry-content-hash.test.mjs`. CI fails on drift until then.
4. **Close out** (Linear write allowlist). Comments the PR link, removes
   `agent:forge`, and sets In Review, or on failure restores the earlier state
   with the reason. It never sets Done. CI on the PR is the verification.
   A person or a different host reviews and marks it ready; nothing is merged
   or deployed.

The model runs under a Codex permission profile built per run: read the machine,
write only the workspace (`.git` read-only), network off, and `deny` on every
credential-bearing entry of the runner's home (the GitHub token, the Linear
OAuth login, the plan keys, every other client's login). Measured on Forge on
2026-11-12: before the profile, a sandboxed session could read `gh/hosts.yml`,
`.codex/.credentials.json` and the plan key; with it, all three are denied, a
write outside the workspace fails, and Codex itself is unaffected (its helper
binaries under `.local/bin` and `.local/lib` stay readable). A profile cannot be
mixed with `-s`, and `-c` cannot take quoted dotted keys, so it is passed as one
inline table. The Linear OAuth session still belongs to the owner's identity, so
the select and close-out sessions can write to any issue in the workspace; their
tool lists exclude every delete.

Codex exposes only a handful of the Linear server's 78 tools to the model
unless an allowlist names them, so each phase passes
`mcp_servers.linear.enabled_tools` (select and close-out can write, implement
cannot, none can delete).

Limits: one issue per run, 6 runs a day, 2 attempts per issue (a PR or a second
failure retires it from selection), one run at a time, free memory of at least
4 GiB. Routes rotate least-recently-used over the enabled plans, and every
enabled route has a proven full cycle now: `codex-zai` (Z.ai Coding Plan)
produced SH-4512 (#125), `codex-qwen` (Qwen Token Plan) produced SH-4576
(#127) and `codex-go` (OpenCode Go) produced SH-4583 (#128); each was claimed,
implemented and opened as a draft PR unattended, and merged after review.
`codex-mimo` stays disabled: its turns end without a reply (SH-4421). A plan
that reports a usage or rate limit cools down for 3 hours and the attempt is not
charged to the issue (Z.ai's 5-hour limit was hit on 2026-11-12 during testing).
Logs and the ledger live in `~/.local/state/agenthub/forge-intake`, pruned
after 14 days.
`node forge-intake.mjs --status` prints runs today, the cap, draft PRs,
failures, retired issues, per-route use, cooling routes, Linear close-outs that
were not confirmed, and the lock: `lockHeldBy` is the PID of a live run, or
null, and `staleLock` is a dead or unreadable PID that the next run takes over.

Operate it as root over the `forge` alias:

~~~bash
systemctl status forge-intake.timer
systemctl start forge-intake.service            # one run now
touch /srv/work/agenthub-runner/.config/agenthub/forge-intake.disabled   # stop
rm /srv/work/agenthub-runner/.config/agenthub/forge-intake.disabled      # resume
~~~

Install or update (root): put the released tree at
`/opt/agenthub/catalogs/<sha>` and point `/opt/agenthub/current` at it. Then
update the clients as `agenthub-runner`, with `HOME=/srv/work/agenthub-runner`
and `~/.local/bin` on `PATH`. Removing a marketplace also uninstalls its
plugins, so the reinstall step is required. For Claude:
`claude plugin marketplace remove agenthub`,
`claude plugin marketplace add /opt/agenthub/catalogs/<sha>`, then
`claude plugin install <name>@agenthub` for each of ah-browser,
ah-coding-agent-dispatch and ah-product. For Codex:
`codex plugin marketplace remove agenthub`,
`codex plugin marketplace add /opt/agenthub/catalogs/<sha>`, then
`codex plugin add <name>@agenthub` for each of ah-product, ah-browser
and ah-coding-agent-dispatch. Copy
`forge-intake.service` and `forge-intake.timer` to `/etc/systemd/system` again
only when they changed (`cmp` them against the installed copies): a new catalog
alone needs no timer restart. After a unit change run
`systemctl daemon-reload && systemctl enable --now forge-intake.timer`. This is
a standing schedule that the owner directed on 2026-11-12 for Forge only, so
the "no scheduled jobs" rule for the workstation is unchanged. When Forge
retires after 2026-12-01, move the same script to the successor host.

## Provider removal and presentation

Owner direction on 2026-11-06 removes Firecrawl and Supabase plugins, loose skills and MCP routes. Supabase credits do not imply current activation. The rollout now contains 14 public and three private plugins.

AgentHub packages retain stable `ah-*` IDs and `AH-*` display names with distinct icons. Clerk is an official upstream plugin and retains vendor identity.
