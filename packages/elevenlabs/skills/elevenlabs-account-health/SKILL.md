---
name: elevenlabs-account-health
description: Use when checking ElevenLabs authentication, subscription credits, live models, clone readiness or native connector access.
---

# ElevenLabs account checks

Use the already-connected host-native ElevenLabs surface for its workspace
inventory. Resolve link/workspace explicitly when more than one connection is
offered. Never assume two labels represent different accounts or the same account.

For REST metadata use `packages/elevenlabs/scripts/elevenlabs_cli.py`:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli health
python $Cli account
python $Cli models
python $Cli voice-status --voice-id <existing-id>
```

`health` reports booleans; `account` allowlists plan, quota, reset and clone-slot
metadata. Remaining credits are limit minus usage, clamped to zero; unknown fields
stay null. `voice-status` reports model-specific tuning states and verification
flags without downloading source recordings. A historical verification flag alone
does not establish that a usable clone is broken. `voices` reports only the voices
returned by that response, not a paginated account-wide total.

Record timestamp and inspected surface privately. Refresh before a new spending
batch. Never put account balances, clone IDs, raw user/billing responses, request
headers or credentials into public guidance. Check `ELEVENLABS_API_KEY` only as
set/unset; never dump the environment. These metadata commands consume no render
credits and do not change the account.

Distinguish HTTP authentication, API-key scope, subscription entitlement, native
OAuth sign-in, region and model readiness. An image/video REST 401 does not prove
the OAuth connector cannot generate. An exposed node schema is discovery evidence;
only a completed run verifies generation. Do not spend simply to test availability.
Use the current official hosted MCP setup at https://elevenlabs.io/mcp; preserve
working regional endpoints and use host-native management for troubleshooting.
No automatic permission expansion, billing change, clone replacement or retraining.
