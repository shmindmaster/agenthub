---
name: elevenlabs-tts
description: Use when approved text needs ElevenLabs speech generation, voice selection, audio-tag direction, pronunciation control, request stitching, or segment-level regeneration with an STT gate.
---

# ElevenLabs TTS

Product SDK, agents, music, dubbing, and voice-isolation work belongs to the
official ElevenLabs skills, not this overlay:

```bash
npx skills add elevenlabs/skills
```

Upstream: https://github.com/elevenlabs/skills. This skill is the fleet
routing layer: owner-voice stays local, and non-owner TTS uses the bundled
CLI. Endpoint, model, and stitching details live in `elevenlabs-api`; read it
when a call goes beyond single-voice TTS.

## 1. Check first: is this the owner's own voice?

If the requested narration is Sarosh's voice, **stop and use the local route
instead**. That voice is a local capability with an enrolled speaker profile and
an identity gate; ElevenLabs cannot produce it and will return a different
speaker that merely sounds professional.

```powershell
& '<LOCAL_AI_ROOT>\ai.ps1' voice qwen-clone --voice sarosh --text "..." --out <out.wav>
```

Sarosh moods use the `styles-20260815` style-bank WAVs (not ElevenLabs and not
free-text mood prompts). See the `local-ai-stack` skill for the full Qwen-only
playbook (0.6B Fast default, `--premium` for 1.7B, celebrity-style narrator ids,
mandatory identity gate, call-operator invocation) and `sarosh-audio-voice` for
the policy. This mirrors the boundary `elevenlabs-stt` already enforces for
privileged media: some audio belongs on this machine and nowhere else.

The owner has said his own voice is not required for rehearsal films. Use a
library or designed ElevenLabs voice there rather than any hosted copy of his
voice. The policy against cloning or hosting his voice is unchanged.

ElevenLabs remains correct for non-owner voices, for stock/character narration,
and for an explicitly requested benchmark comparison against the local engine.
A benchmark run sends the benchmark text to an external provider, so it needs
the same explicit approval any other outbound transmission does.

## 2. Choose the model from the live list

Run `python $Cli models` first (free; see `elevenlabs-api` section 1 for `$Cli`)
and pick from what it returns. As verified 2026-10-13 against `GET /v1/models`
and live calls:

- `eleven_v4`: produced audio. 94 languages, 10,000 chars per request,
  honours inline audio tags. The default.
- `eleven_v4_turbo`: agents and latency-bound use.
- `eleven_v3` / `eleven_v3_conversational`: compatibility only, when matching
  an older render. No request stitching on `eleven_v3`.

The CLI defaults to `eleven_v4` from package 1.1.0. The raw API still defaults
to `eleven_multilingual_v2`, so always send `model_id` when calling it directly.

## 3. Generating

The CLI lives at `packages/elevenlabs/scripts/elevenlabs_cli.py` in the
AgentHub checkout (or `${CLAUDE_PLUGIN_ROOT}/scripts/` when installed as a
plugin), not beside this file:

```powershell
$Hub = if ($env:AGENTHUB_ROOT) { $env:AGENTHUB_ROOT } else { 'C:\Repos\shmindmaster\agenthub' }
$Cli = Join-Path $Hub 'packages\elevenlabs\scripts\elevenlabs_cli.py'
python $Cli tts --voice-id <id> --text "[warmly] Welcome back." --output <out.mp3>
```

The command requires a voice ID from `ELEVENLABS_VOICE_ID` or `--voice-id`,
uses `output_format=mp3_44100_192` unless `--output-format` or
`ELEVENLABS_OUTPUT_FORMAT` says otherwise, and prints the `request_id` needed
for stitching.

Product-video callers may also supply the reviewed prerecorded-narration controls:
`--stability`, `--similarity-boost`, `--style`, `--speed`,
`--use-speaker-boost`/`--no-use-speaker-boost`, `--text-normalization`,
`--previous-text`/`--next-text`, `--previous-request-id`/`--next-request-id`,
`--pronunciation-dictionary ID[:VERSION]`, `--language-code`, and `--seed`. The
shared CLI owns the provider request and authentication; downstream capabilities
own only their segment, timing, checksum, and composition orchestration.

## 4. Directing Eleven v4

- Settings: steer v4 with `--stability` and `--similarity-boost`. A live A/B on
  2026-10-13 (`eleven_v4`, same voice, text, and seed, with and without
  `style` 0.3 + `use_speaker_boost`) returned HTTP 200 both times: the API
  accepts those fields silently. The two takes had identical duration (4.72 s)
  and size, and loudness within 0.1 LU (-21.2 vs -21.1 LUFS). The bytes
  differed, but seeds are not guaranteed deterministic, so that is not evidence
  of an effect. Treat `style`, `use_speaker_boost`, and `speed` as no-ops on v4
  until a listening A/B shows otherwise. No SSML, so `<break time>` is ignored;
  direct pace with tags, punctuation (ellipses, capitals), and sentence length.
- Audio tags work inline: `[warmly]`, `[short pause]`, `[confident]`,
  `[laughs softly]`, `[frustrated]`, `[whispers]`, `[sighs]`. Write the line as
  prose first, then add tags only where the text alone does not imply the
  delivery. Describe the voice quality (`[low, gravelly voice]`) so a tag is not
  read as a sound cue.
  https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices
- Pronunciation: v4 reads IPA wrapped in slashes, for example `/ˈzɛndɛsk/`. For
  a reusable lexicon, use a pronunciation dictionary (up to 3 locators per
  request), which matches the fleet rule that pronunciation is a dictionary
  layer. Do not respell words.
- Continuity: regenerate one segment with `--previous-request-id` /
  `--next-request-id` (the neighbours' `request_id`), or with
  `--previous-text` / `--next-text`. Never both forms on the same side: the
  live API rejects it and the CLI refuses it.
- `/with-timestamps` returns per-character alignment for captions and beat
  sync. `audio_effects` (phone, radio, room, background bed, pan) costs nothing
  extra. See `../elevenlabs-api/references/capabilities.md`.
- Multi-speaker scenes belong on Text to Dialogue (`POST /v1/text-to-dialogue`
  with `"model_id": "eleven_v4"`), which returns one mixed MP3 with natural
  turn-taking. At most 10 voices and about 2,000 chars per request; chain longer
  scenes with `previous_request_ids`. The CLI does not wrap it yet.
- The `SH (PVC)` voice on the account is **not** fine-tuned on `eleven_v4`
  (checked 2026-10-13). This does not change the owner-voice rule above: hosted
  SH output is never the narration route.

## 5. Gate every line, spend credits once

1. A/B the voice and tag style on 2 to 3 representative lines before a full
   script.
2. Cache each line by `sha256(model_id + voice_id + settings + text with tags +
   dictionary versions + effects + output_format)`. Skip any cache hit.
3. Transcribe each new render with `scribe_v2` (see `elevenlabs-stt`) and pass
   it only when normalised WER is at or below 0.15 **and** every key term
   (names, product terms, numbers) is present. Normalise both sides: lowercase,
   strip punctuation and bracketed audio tags, collapse whitespace.
4. Never re-render a PASS line. Re-render only failures, stitched to their
   neighbours by request id.
5. Run at most 4 speech workers in parallel (plan concurrency is 5). On HTTP
   429, back off and retry the same request.

The WER gate checks words, not speaker identity. Owner-voice identity gating is
separate and local.

Confirm the requested output path and format before generating media. Health,
voice, and model listings are read-only; TTS consumes account quota and should
only run when the user asks for audio.
