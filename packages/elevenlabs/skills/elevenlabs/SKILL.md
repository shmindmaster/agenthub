---
name: elevenlabs
description: Use when ElevenLabs speech or TTS, voice clone readiness, credits or account health, live models, transcription eligibility, or image, video, music, sound effect, dubbing, Studio, Flows or agent routing needs native connector routing and live entitlement checks.
---

# ElevenLabs

One skill, five references. This file routes; load only the reference the task needs.

| Task | Reference |
| --- | --- |
| Speech, TTS, voice settings, the governed `tts` command | `references/tts.md` |
| Credits, subscription, live models, clone readiness, connector access | `references/account-health.md` |
| Transcription eligibility (paid STT is disabled, fails closed) | `references/stt.md` |
| Which surface serves images, video, music, SFX, dubbing, Studio, Flows, agents | `references/capabilities.md` |
| Route choice, spend, batch and cache, exact-asset reuse and recovery | `references/cost-controls.md` |

# ElevenLabs routing

**Governed paid route:** every paid content operation must use the shared CLI
ledger. Only REST single-voice TTS (`tts`), sound effects (`sfx`) and
instrumental music (`music`) are currently metered; other paid modalities
fail closed. Native connectors, Flows and SDK snippets must not bypass it. Read
`packages/media-studio/skills/media-studio/references/content-controls.md`.
An unset shared ceiling disables purchases. Never configure or raise it without
an owner-approved aggregate amount. This overrides the discovery order below
for paid operations; metadata discovery remains read-only.

Choose the least costly route that meets the task's quality, privacy and latency
needs. Reuse accepted assets first; use adequate Local-AI or authorized provider
APIs where suitable. Reserve ElevenLabs credits for a justified quality, capability
or delivery-speed benefit. Load `references/cost-controls.md` before paid planning,
then the relevant reference above and `references/capabilities.md` for the modality.

1. Resolve the actual host surface against `registry/fleet-profile.json`.
   For read-only discovery, use its already-connected ElevenLabs plugin/MCP if enabled. Discover its live tools,
   workspace, models and node schemas; tool presence is availability evidence,
   not proof a paid generation succeeded. Preserve explicit workspace/link IDs.
2. For connector discovery only, the official hosted
   OAuth MCP is documented at https://elevenlabs.io/mcp. Confirm the host's native
   management surface before changing configuration. Owner sign-in may be needed;
   never copy API keys into OAuth headers or install a duplicate local server.
   The upstream local `elevenlabs-mcp` is deprecated in favor of the hosted MCP:
   https://github.com/elevenlabs/elevenlabs-mcp.
3. For repository integrations or an operation unavailable through native tools,
   the shared CLI owns API authentication and its supported provider requests.
   Use official ElevenLabs skills already present for SDK/Agents/specialist work
   (https://github.com/elevenlabs/skills). Do not vendor or reinstall that catalog
   to imitate another host. Query current official docs for unsupported endpoints.

## Shared adapter and preflight

The CLI is at `packages/elevenlabs/scripts/elevenlabs_cli.py`, not beside a
loose-installed skill. Resolve `$env:AGENTHUB_ROOT` or the canonical checkout:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli account
python $Cli models
python $Cli voice-status --voice-id <existing-id>
```

The CLI's subcommands are `health`, `account`, `voice-status`, `voices`, `models`,
`tts`, `sfx`, `music`, `transcribe` (refused, see `references/stt.md`) and
`reconcile` (read-only history recovery; it never resubmits).

These are read-only. Keep account/clone details in private task receipts, never
public package content. Never print keys, headers, raw account responses or error
bodies. `ELEVENLABS_API_KEY` is an environment reference, never a copied value.

Before spending: establish remaining credits, selected workspace, exact model,
clone readiness, duration/resolution/output limits and estimated cost. An API
permission failure, subscription restriction, OAuth sign-in and regional model
availability are separate conditions. A REST failure does not establish a native
connector or UI restriction. Do not upgrade billing, enable overages, upload
private recordings, replace a clone or start owner verification without authority.

## Efficiency and evidence

- Start with one small representative preview; approve identity/content locally
  before a long batch. Cache by the complete request: text, model, voice, settings,
  dictionaries, references, neighboring context and output format. Reuse accepted
  takes; regenerate only failing segments.
- Fetch schemas once per workspace/session and reuse them until a relevant error
  requires refresh. Poll the returned run ID; never resubmit a chargeable request
  after a timeout without checking whether it completed. Back off on rate limits.
- Use explicit model IDs from the selected surface. REST and Flows model IDs may
  differ. Newest model availability does not establish compatibility with a clone.
- Record provider, workspace/run/request ID, model, parameters, input hash, cost
  estimate and output hash in the external job workspace. Report generated,
  validated, delivered and owner-approved separately.
- Sarosh voice loads `sarosh-audio-voice`; private audio/transcription loads the
  applicable privacy route. Local-AI is an eligible primary route, including for
  adequate low-cost work, and the private/offline route. Keep
  speaker identity, pronunciation, ASR and final artifact gates across providers.
