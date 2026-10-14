# ElevenLabs capability map (checked 2026-10-13)

`ACCOUNT` = exercised on the fleet account (Creator tier) on 2026-10-13.
`docs-only` = stated in elevenlabs.io/docs, not exercised. Re-check docs-only
rows before relying on them. Full research note:
`D:\Local-AI\data\artifacts\media-studio\_shared\elevenlabs-v4-research\2026-10-14-ElevenLabs-Capabilities-Learnings.md`.

## Pass the model on every call

Endpoint defaults are old: TTS `eleven_multilingual_v2`, dialogue `eleven_v3`,
music `music_v1`, the local `elevenlabs-mcp` server `eleven_turbo_v2` / `music_v2`.

| Need | Endpoint | Model | Status |
| --- | --- | --- | --- |
| Produced speech | `POST /v1/text-to-speech/{voice_id}[/stream][/with-timestamps]` | `eleven_v4` (1 credit/char, 10k chars/request) | ACCOUNT |
| Real-time speech | same + WebSocket / multi-context WebSocket | `eleven_v4_turbo` (0.5 credit/char) | ACCOUNT (listed) |
| Multi-speaker scene | `POST /v1/text-to-dialogue[/stream][/with-timestamps]` | `eleven_v4`; ≤10 voices; keep ≤2,000 chars/request, chain with `previous_request_ids` | ACCOUNT |
| Music | `POST /v1/music[/stream]`, `/v1/music/detailed` (lyrics timestamps), `/v1/music/plan` | `music_v2_5`; 3 s–600 s; `force_instrumental`; `composition_plan.chunks[]`; `store_for_inpainting` returns a `song-id` header | ACCOUNT (prompt mode) |
| Music from picture | `POST /v1/music/video-to-music` (≤10 files, ≤200 MB, ≤600 s) | `music_v2_5` | docs-only |
| Stems | `POST /v1/music/stem-separation` | — | docs-only |
| Music finetune | `/v1/music/finetunes` | `finetune_id` on compose | ACCOUNT (list) |
| Sound effects | `POST /v1/sound-generation` (`duration_seconds` 0.5–30, `loop`, `prompt_influence`) | `eleven_text_to_sound_v2` | ACCOUNT (loop) |
| Audio effects on speech | `audio_effects` on TTS and dialogue; catalog `GET /v1/audio-effects/catalog` | filters `phone`, `low_quality_phone`, `bright_phone`, `old_radio`, `robot`, `cheap_microphone`; rooms `small_room`, `big_room`, `hall`, `tunnel`, `street`, `valley`, `forest`; beds `call_center`, `cafe`, `city`, `keyboard`; `distance`, `send_level`, `pan`. No extra cost. Reverb/pan → stereo, rejected for `pcm_*`/`ulaw`/`alaw`. | ACCOUNT |
| Voice design | `POST /v1/text-to-voice/design` → `POST /v1/text-to-voice` | `eleven_ttv_v3` | docs-only |
| Voice remix | `POST /v1/text-to-voice/{voice_id}/remix` | — | docs-only |
| Clone | IVC `POST /v1/voices/add`; PVC `/v1/voices/pvc/*`, v4 fine-tune `POST /v1/voices/pvc/{id}/train {"model_id":"eleven_v4"}` | — | docs-only |
| Voice changer | `POST /v1/speech-to-speech/{voice_id}` | `eleven_multilingual_sts_v2` (no v4 STS) | docs-only |
| Voice isolator | `POST /v1/audio-isolation` | — | docs-only |
| Transcription | `POST /v1/speech-to-text` | `scribe_v2`, `scribe_v2_realtime`, `scribe_v2_medical` | ACCOUNT |
| Forced alignment | `POST /v1/forced-alignment` (`file`, `text`) | — | docs-only |
| Pronunciation dictionary | `POST /v1/pronunciation-dictionaries/add-from-rules` / `add-from-file`; up to 3 `pronunciation_dictionary_locators` per request | — | ACCOUNT (list) |
| Dubbing | `POST /v1/dubbing` (`model_id` `dubbing_v2` default or `dubbing_v1`, `keyterms`, `target_language`, webhooks) | v2 ≈ 7× v1 cost | ACCOUNT (list) |
| Studio / audiobooks / GenFM podcast API | `/v1/studio/*` | — | ACCOUNT: 403, needs sales whitelisting |
| Image, video, flows, templates, assets | `/v1/flows/{image,video,text-to-speech}`, `/v1/flows/templates/{id}/runs`, `/v1/assets` | — | ACCOUNT: 401, key lacks `image_video_generation`; docs: API needs Pro+ |
| Avatars | UI only | — | docs-only (no API yet) |

## Output formats

Speech on Creator: `mp3_44100_192` is the best format; PCM/WAV 44.1 kHz needs Pro+. Music:
`mp3_48000_192`–`mp3_48000_320`. Opus 48 k and 8 kHz µ-law/A-law exist for telephony.

## Limits

Creator concurrency: TTS 5 (header `maximum-concurrent-requests`, ACCOUNT),
Flash 10, STT 20, music 2, dubbing 3 jobs, dialogue WebSocket sessions 35
(docs). HTTP requests count while generating; a TTS WebSocket counts only while
audio is being generated.

## Connectors

- Hosted MCP: `https://api.us.elevenlabs.io/v1/mcp`, **OAuth only**. The API key
  header is rejected. Scopes: `convai_read convai_write text_to_speech
  speech_history_read flows image_video_generation voice_generation`. Configure
  the `api.us` host; the `api.elevenlabs.io` URL from the docs page fails Claude
  Code's protected-resource check because the server advertises `api.us`.
- Local MCP: `uvx elevenlabs-mcp` (API key). Override its stale model defaults.
- Official CLI: `npm i -g @elevenlabs/cli` (`elevenlabs music compose --model-id music_v2_5 …`, agents-as-code).
- Official skills: `npx skills add elevenlabs/skills`. Official Claude Code
  plugin (agents + Architect skills): `/plugin marketplace add elevenlabs/plugin`.

## ElevenCreative-only features (UI)

Recast (video character swap template; unrelated to media-studio's Recast
finishing tool), Brand Kit, Avatars, Flows and the Flows agent, Templates,
Audiobooks multi-cast with auto character casting and auto pronunciation
dictionary, and Studio 4.0 video projects.
