# Installation, migration, update, and rollback

1. Install Node 22+, current Chrome, and each intended agent. Hermes follows the
   official WSL2 path on a clean Windows installation.
2. Back up agent configs. `configure-agents.ps1 -Apply` does this automatically
   under `%LOCALAPPDATA%\browser-toolkit\backups\<timestamp>`.
3. Rotate any exposed token, then store it canonically as `QWEN_API_KEY`.
   Claude Code additionally requires the compatibility alias
   `ANTHROPIC_AUTH_TOKEN`; synchronize that alias from the same value without
   printing it.
4. Run `npm ci` in the toolkit. `npm audit --audit-level=moderate` must pass.
5. Run `configure-agents.ps1` dry, review the targets, then run
   `configure-agents.ps1 -Apply -BrowserMode Shared` or `Isolated`.
6. Restart agent processes. Keep Cursor staged only while its hold is active.
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
