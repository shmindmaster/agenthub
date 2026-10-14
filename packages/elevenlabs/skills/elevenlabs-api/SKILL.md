---
name: elevenlabs-api
description: Use when a repository needs direct ElevenLabs API access or provider-level voice and media operations beyond the focused STT and TTS skills, including model choice, dialogue, music, sound effects, voice design, pronunciation dictionaries, request stitching, and Agents.
---

# ElevenLabs API

Use `ELEVENLABS_API_KEY` from the user environment. Never print, copy, write to
a file, or ask the user to paste its value. Diagnostics report only whether it
is set. Prefer the bundled CLI for health, voice discovery, model listing, TTS,
and transcription.

Keep integrations provider-neutral: callers may be creative, product, voice,
video, telephony, or agent projects. Do not hard-code a repository name, voice
ID, model, or output directory when an environment override or explicit prompt
provides one.

## 1. Locate the bundled CLI

The CLI lives at the package root, `packages/elevenlabs/scripts/elevenlabs_cli.py`,
not inside any skill folder. Loose-skill deployments (`~/.claude/skills`,
`~/.agents/skills`) copy only `SKILL.md`, so a bare `scripts/elevenlabs_cli.py`
does not resolve there. Resolve it like this:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli models
```

When the package is installed as a Claude Code plugin, the same file is
`${CLAUDE_PLUGIN_ROOT}/scripts/elevenlabs_cli.py`. Do not use the Codex cache
copy under `~/.codex/plugins/cache/personal/elevenlabs-media/0.1.0+codex.*`;
it predates 1.1.0 and defaults to an old model.

## 2. Verify the live model list first

Model availability changes faster than this file. Before choosing a model for a
render, run `python $Cli models` (read-only `GET /v1/models`, no credits) and
use only ids it returns. Never invent or carry forward a model id from memory.

Live list on the fleet account (verified 2026-10-13 against `GET /v1/models`
and live calls), best first:

| Model | Chars/request | Languages | Use |
| --- | --- | --- | --- |
| `eleven_v4` | 10,000 | 94 | Default for produced audio: narration, role voices, dialogue. Honours inline audio tags. |
| `eleven_v4_turbo` | 10,000 | 94 | Agents and anything latency-bound (about 100 ms median). |
| `eleven_v3` | 5,000 | 74 | Compatibility only, for reproducing an older render. No request stitching. |
| `eleven_v3_conversational` | 5,000 | 74 | Compatibility only (previous real-time model). |
| `eleven_flash_v2_5`, `eleven_turbo_v2_5`, `eleven_multilingual_v2` | 10,000 to 40,000 | 29 to 32 | Legacy. Only when a caller pins them. |

Always pass `model_id` explicitly. Endpoint defaults are old: TTS
`eleven_multilingual_v2`, Text to Dialogue `eleven_v3`, Music `music_v1`. The
CLI defaults to `eleven_v4` from 1.1.0 (override with `--model-id` or
`ELEVENLABS_MODEL_TTS_DEFAULT`).

Sources: https://elevenlabs.io/docs/overview/models,
https://elevenlabs.io/docs/changelog/2026/9/28 (v4 and v4 Turbo launch),
https://elevenlabs.io/docs/changelog/2026/10/5 (v4 in conversational TTS).

## 3. Endpoint quick reference

Read `references/capabilities.md` before calling an endpoint the CLI does not
cover. It records the endpoint, the model to pass, limits, and whether each row
was exercised on the fleet account or is docs-only.

- **Text to Speech**: `POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_192`
  with `text`, `model_id`, `voice_settings` `{stability, similarity_boost,
  style, use_speaker_boost}`, optional `language_code`, `seed`,
  `pronunciation_dictionary_locators`, and stitching fields (section 4).
  `/with-timestamps` adds character alignment. `mp3_44100_192` needs Creator
  tier or above; PCM/WAV 44.1 kHz needs Pro.
- **Text to Dialogue**: `POST /v1/text-to-dialogue`
  `{"model_id":"eleven_v4","inputs":[{"text":"...","voice_id":"..."}, ...]}`
  returns one mixed MP3 with natural turn-taking. At most 10 unique voices.
  Keep each request at or below about 2,000 characters across all inputs, and
  chain longer scenes with `previous_request_ids`.
  https://elevenlabs.io/docs/api-reference/text-to-dialogue/convert
- **Sound effects**: `POST /v1/sound-generation`
  `{"text","duration_seconds","prompt_influence"}`; duration 0.5 to 30 s,
  `prompt_influence` 0 to 1 (default 0.3), `loop` on `eleven_text_to_sound_v2`.
  https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
- **Music**: `POST /v1/music` `{"prompt","music_length_ms"}` works on the
  Creator tier (verified 2026-10-13). Length 3,000 to 600,000 ms. Pass
  `"model_id":"music_v2_5"` (accepted since the 2026-09-14 changelog);
  `force_instrumental` for beds; `composition_plan` instead of `prompt` to lock
  section lengths. https://elevenlabs.io/docs/api-reference/music/compose
- **Voice design**: `POST /v1/text-to-voice/design` `{"voice_description",
  "text" (100 to 1,000 chars) or "auto_generate_text", "model_id"}` returns
  previews with `generated_voice_id`; then `POST /v1/text-to-voice`
  `{"voice_name","voice_description","generated_voice_id"}` saves the chosen
  one. Model ids: `eleven_multilingual_ttv_v2` (default) or `eleven_ttv_v3`
  (supports `reference_audio_base64`). A second design call while a preview is
  generating returns 409; retry.
  https://elevenlabs.io/docs/api-reference/text-to-voice/design
- **Pronunciation dictionaries**: create with
  `POST /v1/pronunciation-dictionaries/add-from-rules` (alias rules
  `{"type":"alias","string_to_replace","alias"}` or IPA phoneme rules) or
  `add-from-file` (PLS). Pass up to 3 locators per request as
  `pronunciation_dictionary_locators: [{"pronunciation_dictionary_id","version_id"}]`,
  applied in order. CLI: `--pronunciation-dictionary ID[:VERSION]`.
  Pronunciation is a dictionary layer; do not respell input text.
  https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/pronunciation-dictionaries
- **Speech to Text**: `POST /v1/speech-to-text` with `model_id=scribe_v2`
  (fallback `scribe_v1`, deprecated). See `elevenlabs-stt`.

## 4. Request stitching

To keep prosody continuous across separately rendered lines, send the
`request-id` response header of neighbouring renders:

- `previous_request_ids` (up to 3, the last is closest) and `next_request_ids`
  (up to 3, the first is closest). Ids older than about two hours are unusable.
  The CLI prints `request_id` for every render; store it per line.
- Never send `previous_request_ids` and `previous_text` in one body (or the
  `next_*` pair). The live API rejected that combination on 2026-10-13, even
  though some reference pages say the ids override the text. The CLI refuses it
  before spending credits.
- Not available on `eleven_v3`. Use the same model on both sides of a seam.

https://elevenlabs.io/docs/eleven-api/guides/how-to/text-to-speech/request-stitching

## 5. Credit efficiency (mandatory for batch renders)

- Cache every render under `sha256(model_id + voice_id + voice_settings +
  text with tags + dictionary versions + effects + output_format)`. A cache hit
  is never re-rendered.
- Never re-render a line that already passed its gate. Regenerate only the
  failing line, stitched to its neighbours.
- A/B a new voice, model, or tag style on 2 to 3 representative lines before
  committing a full script.
- Health, voice, and model listings are free; every render consumes quota and
  runs only when the user asked for audio.
- Concurrency on this plan is 5 speech requests (header
  `maximum-concurrent-requests`). Batch with at most 4 speech or dialogue
  workers and 2 music workers. On HTTP 429 or `too_many_concurrent_requests`,
  back off and retry the same request; do not widen the pool.
- Use a timeout of about 300 s for renders (the CLI does this for `tts`).

## 6. Agents platform

Product SDK and agent-building work belongs to the official skills
(`npx skills add elevenlabs/skills`). What the platform offers today (agents
update API, verified against the reference downloaded 2026-10-13):

- TTS `model_id` defaults to `eleven_v4_turbo`; `eleven_v4` and
  `eleven_v3_conversational` are also allowed.
- ASR `provider` defaults to `scribe_realtime` (`scribe_v2_turbo` allowed).
- LLM choice includes Claude and GPT models, with `backup_llm_config` cascading
  and `cascade_timeout_seconds` (2 to 15, default 4).
- Knowledge base documents plus `rag` configuration.
- Testing: simulate-conversation (`new_turns_limit` max 100) and the tests API
  (create, run on agent, invocations report `credits_used`).

https://elevenlabs.io/docs/eleven-agents/api-reference/agents/update,
https://elevenlabs.io/docs/eleven-agents/customization/agent-testing

## 7. Account limits and connectors

- The Image & Video, Flows, and Studio APIs are gated on this account: the key
  lacks `image_video_generation`, Image & Video API needs Pro or above, and the
  Studio API needs sales whitelisting. Use the ElevenCreative UI for those.
- The hosted MCP (`https://api.us.elevenlabs.io/v1/mcp`) authenticates with
  OAuth only. Do not configure it with an `xi-api-key` header or with the
  `api.elevenlabs.io` host. Troubleshooting: the `elevenlabs-full` entry in
  `~/.claude.json` was repointed to the `api.us` host on 2026-10-13 (the old
  host caused the connection failure) and needs the owner's OAuth sign-in via
  `/mcp`. See `elevenlabs-account-health`.
- The local `uvx elevenlabs-mcp` server defaults to `eleven_turbo_v2` and
  `music_v2`; override the model on every call.
