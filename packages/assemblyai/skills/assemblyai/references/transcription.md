# Transcription and analysis

Checked against the vendor pages on 2026-11-24. Confirm each field for both the mode (recorded or streaming) and the model before using it.

## Models

| Work | Field and value |
|---|---|
| Recorded audio | `speech_models: ["assemblyai-stt-3-7"]` (plural list). Set it: the default depends on when the account was created |
| Voice agent, live | `speech_model=assemblyai-stt-3-7-realtime-agent` (singular) |
| Notetaker, captions, live speakers | `speech_model=assemblyai-stt-3-7-realtime` |

- Values are raw strings. SDK names such as `SpeechModel.universal_3_pro` do not exist.
- A listed `assemblyai-stt-3-7` wins for every language it supports, wherever it sits in the list. It keeps filler words by default; send `disfluencies: false` to drop them.

## Fields by need

| Need | Field |
|---|---|
| Who spoke | `speaker_labels: true`. Names or roles: add the Speaker Identification task, recorded audio only |
| Names and product terms | `keyterms_prompt` (up to 1,000 terms recorded, 100 streaming) |
| Medical speech | `domain: "medical-v1"`, not `medical_mode` |
| Remove personal data | `redact_pii`, `redact_pii_policies`, and `redact_pii_audio` for the sound |
| Language | Recorded: `language_code` or `language_detection`. Streaming: `language_codes` steers it |
| No polling | `webhook_url`: answer 2xx within 10 seconds, then fetch the transcript |
| Live translation | `llm_gateway` on the streaming connection |

Health audio needs the customer's authorization and a signed agreement before it is sent. Medical mode supplies neither.

## Limits

- Upload is raw bytes, up to 2.2 GB. A transcript takes up to 5 GB or 10 hours.
- Poll every few seconds, at most 60 a minute per transcript. Respect `Retry-After`.
- Streaming chunks are 20 to 1,000 ms of PCM16 mono, no faster than real time. Send phone audio as 8 kHz mu-law.
- Browsers get a short-lived token from the server: `POST https://token.assemblyai.com/v1/token` with `product: "streaming"`.
- The default streaming host routes to the nearest region. Use `streaming.us.assemblyai.com` or `streaming.eu.assemblyai.com` when data must stay put.

## Summaries and chapters

Transcribe, then send the text to `https://llm-gateway.assemblyai.com/v1/chat/completions`. Model names are exact and versioned: read the [current list](https://www.assemblyai.com/docs/llm-gateway/quickstart.md). With the MCP server, pass Speech Understanding options to `submit_transcript` when the need is known, or use `understand_transcript` afterwards.
