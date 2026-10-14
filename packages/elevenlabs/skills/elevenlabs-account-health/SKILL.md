---
name: elevenlabs-account-health
description: Use when ElevenLabs authentication, account availability, the live model list, or safe quota metadata must be checked without generating media.
---

# ElevenLabs Account Health

The CLI lives at `C:/Repos/shmindmaster/agenthub/packages/elevenlabs/scripts/elevenlabs_cli.py`
(or under `$env:AGENTHUB_ROOT`). Loose-skill installs do not ship `scripts/`,
so call it by that path:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli health
```

- `health` calls `/v1/user` and reports only success and non-sensitive
  subscription booleans.
- `voices` counts and lists voice IDs/names when needed; do not expose
  unrelated account data.
- `models` lists the models the account can use now (`GET /v1/models`). Run it
  before any render that names a model, and use only ids it returns.

None of these consume credits. Never print the key or request headers; report
only whether `ELEVENLABS_API_KEY` is set.

## Quota and access detail (read-only)

`health` reports booleans only. For remaining credits, read
`GET /v1/user/subscription` and print only `tier`, `status`, `character_count`,
`character_limit`, `next_character_count_reset_unix`, `voice_slots_used`,
`voice_limit`, and the professional-voice fields. `GET /v1/models`
`model_rates.character_cost_multiplier` gives the per-model credit rate
(`eleven_v4` 1.0, `eleven_v4_turbo` 0.5).

Known state on 2026-10-13: tier `creator`, credit limit 315,221, resets
2026-11-13. The `SH (PVC)` voice is not fine-tuned on `eleven_v4`. Live models
(verified 2026-10-13 against `GET /v1/models`): `eleven_v4`,
`eleven_v4_turbo` (10,000 chars, 94 languages), `eleven_v3`,
`eleven_v3_conversational` (5,000 chars, 74 languages), plus legacy v2 models.

## Concurrency

Speech concurrency on this plan is 5, reported in the
`maximum-concurrent-requests` response header. Batch at most 4 speech or
dialogue workers (leave one for interactive use) and 2 music workers. On HTTP
429 or `too_many_concurrent_requests`, back off and retry; never raise the
worker count to compensate.

## Access probes

Each is a cheap GET:

- `/v1/flows/image` returning 401 `missing the permission image_video_generation`
  means the API key needs the Image & Video permission (dashboard, Developers,
  API keys). The Image & Video API also needs Pro or above.
- `/v1/studio/projects` returning 403 `explicitly whitelisted` means the Studio
  API is gated by sales. The ElevenCreative UI still works.

## Troubleshooting the hosted MCP

`claude mcp get elevenlabs-full` should show the URL
`https://api.us.elevenlabs.io/v1/mcp`. The earlier connection failure came from
the `api.elevenlabs.io` host; the entry in `~/.claude.json` was repointed to the
`api.us` host on 2026-10-13 and now needs the owner's sign-in. `Needs
authentication` means the owner must run `/mcp` and finish the OAuth sign-in.
That server rejects API-key headers.
