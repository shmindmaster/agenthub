# Text to speech

Checked against the vendor pages on 2026-11-24. Confirm a field on its page before relying on it.

## Pick the interface

| Text arrives as | Use | Limit |
|---|---|---|
| A whole text, for a file | `POST https://tts.us.assemblyai.com/v1/speech` | 5,000 characters a request |
| A whole text, with word times | `POST https://tts.us.assemblyai.com/v1/speech/events` | 5,000 characters a request, raw audio only |
| Text as a model writes it, with barge-in | `wss://tts.us.assemblyai.com/v1/ws` | 2,000 characters a `Generate`, 8,000 not yet spoken |
| OpenAI SDK code | `https://tts.us.assemblyai.com/v1/openai` | A clone goes in as `voice={"id": "<voice_id>"}`; a plain slug is refused |

A clone works only on the host of its own zone, and ours are in the US. On the EU host the answer is `voice_not_found`.

## Speak with a clone

Films and narration use `media-studio`, never this raw call. Elsewhere the call bills per character, so it needs approval of the spend.

Send `voice_id` and leave out `language` and `model_id`: the clone speaks the language it was recorded in. `voice` is retired on the native routes and refused.

```bash
curl -sS --fail-with-body -D headers.txt https://tts.us.assemblyai.com/v1/speech \
  -H "Authorization: $ASSEMBLYAI_API_KEY" \
  -d '{"text": "Hello.", "voice_id": "sarosh-hussain", "container": "wav", "stream": false}' \
  -o out.wav
```

`stream: false` gives a WAV with exact sizes. Keep `x-request-id`, `x-tts-voice-id`, `x-tts-billed-characters` and `x-tts-voice-expires-at` from the headers, and check that `x-tts-voice-id` is the voice you asked for. Billing is per character sent, so reuse an accepted take instead of making it again.

Python: `aai.TTSConfig(voice_id="sarosh-hussain")` with `aai.TextToSpeech(config=...).synthesize(text)` or `aai.TTSSession(config)`. JavaScript: `client.tts.synthesize({ text, voice_id })` or `client.tts.session({ voiceId })`.

Errors: `voice_not_found` (wrong slug, zone or account), `voice_expired` (record and clone again), `voice_blocked` (vendor support), `not_owner` (consent renewal on another account's voice). Retry `429` and `503` after `Retry-After`.

## Write text to be spoken

- Use full sentences with punctuation. `!` adds emphasis, `?!` surprise, a comma or `...` a short pause, `--` at the end a cut-off. CAPITALS stress one word.
- Write numbers, money, dates, phone numbers and addresses normally. `4-3-2-1` reads digit by digit, `4,321` as a number, `4321-5678` in groups. Spell an uncommon acronym `E-T-O`.
- No stage directions or markup: `[pause]` and `[laughs]` are read aloud, and emoji and Markdown are dropped.
- Each line break ends a spoken piece and can be heard as a pause, so join wrapped lines.
- For an approved script, change only punctuation for delivery. Fillers, stutters and false starts suit live agents and never change approved wording. Correct pronunciation in the job's pronunciation step, not by respelling the script.

## Agents that talk

Send `Generate` with the model's spaces kept, `Flush` at each sentence end, and always at the end of the reply. Use `Cancel` for barge-in and `Terminate` to finish. Open one session per conversation. In a browser or app use a short-lived token minted on the server with `product=tts`, never the key.

## Word timings

- On by default on the WebSocket. The SDKs turn them off: pass `word_boundaries=True` (Python) or `wordBoundaries: true` (JavaScript).
- At most one `WordBoundaries` per request, after its `FlushDone`. Match by `flush_id`, not by arrival order.
- `start` and `end` are milliseconds on the whole session's audio. Subtract `audio_start_ms` for a position inside one request. Never add it.
- Skip entries whose `start` equals `end`.
- Best effort: a request can finish with no timings. On `/v1/speech/events` read `Termination.word_boundaries_status`. On the WebSocket check that `Begin.configuration.word_boundaries` is true. When a film needs a word clock and none came, transcribe the delivered audio.

## Pages

[Cloned voices](https://www.assemblyai.com/docs/tts/cloned-voices.md), [voices](https://www.assemblyai.com/docs/tts/voices.md), [prompting](https://www.assemblyai.com/docs/tts/prompting-guide.md), [word boundaries](https://www.assemblyai.com/docs/tts/word-boundaries.md), [HTTP API](https://www.assemblyai.com/docs/tts/api-reference/http-api/overview.md), [WebSocket](https://www.assemblyai.com/docs/tts/connect-parameters.md), [limits](https://www.assemblyai.com/docs/tts/limits.md).
