# Mobile development

Generated current-contract view for the canonical local mobile capability.
The machine-readable source is
[`registry/mobile-development.json`](../../registry/mobile-development.json).

## Public entrypoint

```powershell
pwsh -NoProfile -File C:\Repos\shmindmaster\agenthub\packages\mobile-development\mobile.ps1 catalog
pwsh -NoProfile -File C:\Repos\shmindmaster\agenthub\packages\mobile-development\mobile.ps1 scope <productId>
pwsh -NoProfile -File C:\Repos\shmindmaster\agenthub\packages\mobile-development\mobile.ps1 check files both
pwsh -NoProfile -File C:\Repos\shmindmaster\agenthub\packages\mobile-development\mobile.ps1 check runtime both
```

The paths above are the canonical source contract for repository development.
Fleet-loaded loose skills use the checkout-independent mirror managed by
`scripts/Sync-Capabilities.ps1` at
`$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1`.
The sync ledger enforces whole-package source/deployed parity; do not point a
deployed skill at a repository checkout or maintain a second manual copy. The
same guarded sync mirrors AgentHub's registry authority under
`$env:LOCALAPPDATA\AgentHub\registry`, preserving the package's relative
registry lookup without tying it to an unmerged checkout.

Use `mobile.ps1` for catalog, scope, read-only checks, Appium activation,
lab lifecycle, deep validation, guest sync, Metro, and mobile-web routes.
The command catalog and lifecycle metadata come from
`registry/mobile-development.json`.

## Authorities and exposure

- Product eligibility and identity come only from
  [`registry/mobile-scope.json`](../../registry/mobile-scope.json). Only an
  exact `include` record authorizes product-targeted work.
- The Appium MCP package pin and its allowed hosts come only from
  [`registry/mcps.json`](../../registry/mcps.json). Appium is absent from
  persistent host configuration and is activated only for Claude or Codex.
- Every active coding host receives the loose `mobile-platform-standard` and
  `mobile-device-lab` skills plus catalog discovery. Enabling or disabling the
  Appium plugin requires a new task before the MCP tool set changes. Claude
  installs the canonical plugin when absent and leaves it installed-disabled
  after use; Codex retains add/remove lifecycle semantics.
- Guest expectations come from `registry/mobile-development.json`; live VM
  hardware comes from the VMX authority named there and is not copied here.

The dated measurements and rejected alternatives are retained in
[`architecture-decisions.md`](./skills/mobile-device-lab/references/architecture-decisions.md).
Nothing in this contract proves physical-device, credential, signing, cloud,
or store readiness.
