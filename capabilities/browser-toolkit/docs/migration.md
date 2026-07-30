# Installation, migration, update, and rollback

1. Install Node 22+, current Chrome, and each intended agent. Hermes follows the
   official WSL2 path on a clean Windows installation.
2. Back up agent configs. AgentHub's fleet synchronizer creates its managed
   backups; the package-local `configure-agents.ps1 -Apply` also writes backups
   under `%LOCALAPPDATA%\browser-toolkit\backups\<timestamp>` when using an
   advanced four-host routing mode.
3. Rotate any exposed token, then store it canonically as `QWEN_API_KEY`.
   Claude Code additionally requires the compatibility alias
   `ANTHROPIC_AUTH_TOKEN`; synchronize that alias from the same value without
   printing it.
4. Run `npm ci` in the toolkit. `npm audit --audit-level=moderate` must pass.
5. Deploy the upstream README configuration to every registered host with
   `Sync-AgentHub.ps1 -Apply -Validate -IncludeInactiveAgents -ScopeProfile
   global-default`, then run `Apply-FullAccessAgentProfile.ps1`. Use
   `configure-agents.ps1 -Apply -BrowserMode Shared` or `Isolated` only for the
   optional four-host controlled-browser routing.
6. Restart agent processes. Reconcile Cursor through AgentHub's full-profile
   deployment so native plugins and global skills have a single owner.
7. Launch the applicable QA profile and run `validate.ps1 -RunBrowserSmoke`.
8. Run one interactive model response per enabled agent only with a valid,
   unexposed token. Verify the configured model name in the response metadata.
9. For updates, re-check official client documentation and package releases,
   change every pin/fragment/version record together, regenerate the lockfile,
   rerun plugin tests, static checks, audit, shared smoke, and concurrency smoke.

Rollback a configuration batch with:

```powershell
.\scripts\configure-agents.ps1 -RollbackFrom "<backup-directory>"
```

Loose product-skill backups live under
`%LOCALAPPDATA%\AgentHub\handoff-skill-backups`. Claude plugin updates
use its native versioned cache and require restart. Secrets are never backed up;
restore or rotate them separately.
