# Quickstart (public core)

Get from clone to a useful drift audit in a few minutes. PowerShell 7+
(`pwsh`) is required on Windows, macOS, and Linux.

## 1. Install the CLI wrapper (optional)

From the repository root:

```bash
npm install -g .
# or, without a global install:
node ./scripts/agenthub-cli.mjs --help
```

## 2. Initialize a local overlay

```bash
npx agenthub init
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
npx agenthub validate
npx agenthub sync
```

`sync` without `--apply` is read-only drift. When the audit looks right:

```bash
npx agenthub sync --apply
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
npx agenthub validate
```

## Starter path

After init, prefer enabling only what you need. Good first public
capabilities (already in the registry when present): `security`,
`browser-toolkit`, `open-connector`, `slack` (fixture mode). Heavy studio
packs can wait.

See [setup.md](./setup.md) for machine requirements and
[control-plane-modules.md](../architecture/control-plane-modules.md) for
path binding and overlay rules.
