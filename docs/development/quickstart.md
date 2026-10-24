# Quickstart (public core)

Get from clone to a useful drift audit in a few minutes. PowerShell 7+
(`pwsh`) is required on Windows, macOS, and Linux, and `validate` needs
[ripgrep](https://github.com/BurntSushi/ripgrep#installation) (`rg`) on PATH.

## 1. Install the CLI wrapper (optional)

From the repository root:

```bash
npm install -g .
# or, without a global install:
node ./scripts/agenthub-cli.mjs --help
```

The commands below use the repository's npm scripts, which run this clone's
wrapper. The published npm package (`npx @shmindmaster/agenthub`) carries only
`doctor`, not the sync engine.

## 2. Initialize a local overlay

```bash
npm run init
# equivalent:
pwsh -NoProfile -File ./scripts/AgentHub.ps1 init
```

This copies:

- `overlays/personal.example/` → `overlays/personal/` (if missing)
- `agenthub.profile.example.json` → `agenthub.profile.json` (if missing)

Leave `enabledCapabilityIds` empty unless you add private packages yourself.
Public capabilities load without an overlay.

## 3. Validate, then audit

```bash
npm run validate
npm run sync
```

`sync` without `--apply` is read-only drift. When the audit looks right:

```bash
npm run sync -- --apply
```

## 4. Private vs public

| Surface | Where it lives |
| --- | --- |
| Portable policy | `policy-core.md` |
| Personal rules | `overlays/personal/policy-fragment.md` |
| Private capability ids | `overlays/personal/overlay.json` |
| Machine roots | `agenthub.profile.json` (gitignored) |

Turn the overlay off for a public-only graph:

```bash
# PowerShell
$env:AGENTHUB_OVERLAY = 'off'
npm run validate
```

## Starter path

After init, prefer enabling only what you need. Good first public
capabilities (already in the registry when present): `security`,
`browser-toolkit`, `open-connector`, `slack` (fixture mode). Heavy studio
packs can wait.

See [setup.md](./setup.md) for machine requirements and
[control-plane-modules.md](../architecture/control-plane-modules.md) for
path binding and overlay rules.
