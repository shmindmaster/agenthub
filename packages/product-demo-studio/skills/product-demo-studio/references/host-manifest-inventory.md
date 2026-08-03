# Host manifest inventory

Records which coding-agent hosts this capability ships a manifest for, which auto-detect the Claude layout, and where each behaviour was read from. `policy/host-manifests.json` is the machine-readable version; `scripts/validate-host-manifests.mjs` enforces it.

## Why this exists

`policy/host-parity.json` lists eighteen `mappedHosts`. `validate-host-parity.mjs` compares that list against the external registry's `hostMappings` and never looks at the plugin directory, so a host could be mapped, pass parity, and have no loadable entry point.

The new validator closes that: **every mapped host either ships a manifest, auto-detects the Claude layout, or carries a documented reason it does neither.** Silence is no longer a passing state.

It does not extend what static validation proves. `host-parity.json#validationScope` already says static validation does not establish deployed bytes, host-native read-only enforcement, or runtime behaviour.

## Four hosts auto-detect; no manifest shipped

Each translation rule below comes from that host's own current documentation.

**Factory (droid)** — translates `.claude-plugin/` to `.factory-plugin/`, `agents/` to `droids/`, and `.mcp.json` to `mcp.json` when it copies the plugin into its cache. The source repository is not mutated. Clean, unconditional, no caveat.

**VS Code** — resolves `plugin.json` in order: `.plugin/plugin.json`, `plugin.json`, `.github/plugin/plugin.json`, `.claude-plugin/plugin.json`. The Claude manifest is the documented fourth fallback.

**GitHub Copilot** — VS Code's documentation states the plugin format is shared between VS Code, Copilot CLI, and Claude Code, and that a single repository works across all three. Copilot CLI's own reading of `.claude-plugin/` was not verified against GitHub's documentation directly.

**Qwen Code** — converts Claude plugins on install: `claude-plugin.json` to `qwen-extension.json`, agent configurations to Qwen subagents, skill configurations to Qwen skills, with tool mappings handled automatically. **Conversion is documented under marketplace installation.** Whether it applies to `qwen extensions install /path/to/plugin` was not established. If a local-path install does not convert, ship `qwen-extension.json` for that route.

## One manifest is not redundant

**Antigravity** — `plugin.json` at the plugin root is a **required marker file**. No Claude-layout fallback is documented for Antigravity. Dropping this file means Antigravity does not recognise the directory as a plugin at all.

Fields per its documentation: `$schema`, `name` (optional, defaults to the directory name), `description`. `version` is carried beyond the documented example so the validator can catch drift against `capabilityVersion`. Components load from `skills/`, `agents/`, `rules/`.

The IDE loads from `~/.gemini/config/plugins/`; the CLI from `~/.gemini/antigravity-cli/plugins/`.

**One open item.** This file sits at the same path VS Code checks second, so it now takes precedence over `.claude-plugin/` there. It declares the same `name` and `version`, and VS Code documents the format as shared across the three tools — but the combination has not been load-tested on either host. If VS Code rejects `$schema`, or Antigravity rejects anything, move the VS Code copy to `.plugin/plugin.json` and leave the root file to Antigravity alone.

## The trade being made

Auto-detection depends on a compatibility shim this capability does not own. **If a host changes or drops its Claude translation, the capability stops loading there with no local signal** — no file is missing, no validator fails, and the first indication is a user reporting it.

That is an accepted trade for not maintaining five parallel manifests that would drift against each other. The mitigation is narrow and worth stating: the validator fails if `.claude-plugin/plugin.json` disappears while any host is marked `auto-detected`, so the shared anchor cannot be removed silently. Re-read each translation rule when a host's plugin documentation changes.

## OpenCode is not applicable

OpenCode plugins are JavaScript or TypeScript modules exporting hook functions for events such as `tool.execute.before` and `session.idle`, loaded from `.opencode/plugins/` or declared as npm packages in `opencode.json`. **There is no plugin manifest and no packaging format for skills, agents, and commands.**

An `.opencode-plugin/plugin.json` would conform to no schema and would pass any presence-only check. The inventory records `not-applicable` with the reason instead.

OpenCode does have Agent Skills, agents, and commands as separate configuration surfaces. Establishing how this capability should reach them is an open question, not a manifest.

## Unresolved hosts

Seven mapped hosts — `amp`, `cline`, `gemini`, `grok`, `hermes`, `warp`, `windsurf` — carry `documentation-not-read`. No manifest shipped, no auto-detection claimed, nothing guessed.

`gemini` is closest to resolvable: Gemini CLI extensions use `gemini-extension.json`, and Qwen Code documents converting from it. The format was not read directly, so nothing was written.

Four pre-existing manifests — `codex`, `cursor`, `devin`, `qoder` — are carried forward unchanged and marked `format-unverified`. They predate this pass and their formats were not checked against host documentation. They may be correct. Nothing here establishes that they are, and each may also turn out to be redundant with Claude auto-detection.

## What the validator checks

- Inventory and `mappedHosts` cover each other exactly, in both directions.
- `capabilityVersion` agrees between `host-parity.json` and `host-manifests.json`.
- Every manifest declared present exists, parses, and declares the capability id as `name` in lowercase kebab-case.
- Every manifest `version`, where set, matches `capabilityVersion`.
- Every `skills`, `agents`, `commands`, and path-form `mcpServers` reference resolves to a real directory or file.
- Every `auto-detected` host names a source URL and finds `.claude-plugin/plugin.json` present.
- A host with neither a manifest nor auto-detection carries an `openQuestion` or `notes`.

Warnings, not errors: `format-unverified` manifests, `documentation-not-read` hosts, auto-detection caveats, and shared manifest paths. These are states to resolve, not defects to block on, and they print on every run so they stay visible.

## Adding a host

**Check for auto-detection first.** If the host reads the Claude layout, record `auto-detected` with the translation rule and its source URL, and ship nothing. A manifest that duplicates what a host already translates is a file that will drift.

Only when no fallback is documented: read the host's own documentation, write the manifest to the path it specifies, record the URL in `source`, and mark `format-verified`. Add the host to `mappedHosts`. Run the validator.

**Never copy another host's manifest format.** The formats read this pass differ in path, field set, and component layout, and three of them translate from Claude in incompatible ways. Similarity between two hosts is not evidence about a third.
