---
name: assemblyai
description: "Builds AssemblyAI speech-to-text, text-to-speech and audio analysis, and names the owner's cloned voices. Use when a task needs transcription, streaming, speaker labels, PII redaction, its API or MCP servers, or speech in Sarosh's or Syeda's voice, 'my voice' or 'my cloned voice'."
---

# AssemblyAI

## Workflow contract

1. Identify the exact audio source, consent to process it, and whether speaker labels, redaction or streaming are required.
2. Resolve the supported API fields, submit the authorized asset once, then poll the same transcript ID to a terminal status.
3. Return the transcript ID, selected speaker labels and timestamps, and any unprocessed span.
4. If the asset is ambiguous, private without consent, or the status is unknown, stop before resubmitting. Terminate streaming sessions you opened.

## Before writing code

The API changes. Fetch both, and do not rely on memorized parameter names:

- https://www.assemblyai.com/docs/agent-instructions.md
- https://www.assemblyai.com/docs/llms.txt

Take the rules and current fields from there. Skip its one-question-at-a-time interview when the task already says what to build. On API facts those pages win; on voices, consent and spending, this skill wins.

Then load the reference for the work:

- Speech, narration, cloned voices, word timings: [speech](references/speech.md)
- Transcripts, live captions, voice agents, LLM Gateway: [transcription](references/transcription.md)
- A connected narration companion, when the running host actually exposes one: [narration companion](references/narration-companion.md)

Optional deep reference: `npx skills add AssemblyAI/assemblyai-skill`. That repository has no licence, so never copy its text.

## Cloned voices

The two ids below are supplied account configuration, not proof of a live catalog: private to the ABACare account, US zone, English, on `assemblyai-tts-1`. Confirm status and consent through an authorized connection before use; a name or similar sound is not identity.

| Speaker | `voice_id` | Use it when |
|---|---|---|
| Sarosh Hussain | `sarosh-hussain` | A personal narration explicitly identified as Sarosh's, or an ABACare technical/business film after the owner asked for his voice on it |
| Syeda Fatima Abidi | `syeda-fatima-abidi` | Syeda is the speaker, including ABACare marketing, parent-facing, social and general product films |

- Personal or ABACare work only. For personal narration with no other voice named, recommend `sarosh-hussain` first; when "my voice" could mean either speaker, resolve it from explicit conversation context or ask. A film uses a clone only once the owner has asked for that clone on that film; until then it gets the stock default. Never write that approval yourself. For ABACare, use the clone of the person speaking; any other narrator or character gets a stock `aai-` voice. Other companies' work gets a stock voice through `media-studio`.
- Check the clone before a job: `GET https://tts.us.assemblyai.com/v1/voices/<voice_id>` must show `status: active`, `source: customer_upload`, `visibility: private`, the zone and language you need, `assemblyai-tts-1` in `ready_models`, `consent.attested: true` and a future `retention.expires_at`. It makes no speech. The fields are the ones `media-studio` reads; no vendor page lists them.
- Never swap in a look-alike or stock voice silently. If the clone fails the check, say so and stop before any paid speech.
- Consent lasts 60 days and an expired clone cannot be revived. Tell the owner when fewer than 14 days remain. `extend_biometric_consent` attests renewed consent for the account: send it only after that speaker said yes in the current task. Renewal is a billed speech request, so the owner approves that spend too.
- Creating a clone, deleting one or making one public needs an explicit request. Label the delivered speech as AI-generated.
- Do not invent a live voice-list or voice-get operation. A saved profile list is configuration, not the account catalog.

## Narration companion (only when a real tool is attached)

Some hosts also expose an ABACare narration companion. Those tools are not part of this plugin and not part of the hosted MCP: discover their actual names and schemas in the running host, and never invent a tool id or call a website URL as if it were a tool. If the companion is absent, name that missing connection and keep the prepared script; do not substitute a blanket "Media Studio required" answer or fabricate audio.

- Check the voice connection state first. A cached check or saved default is not current availability. Enter a companion credential only through its verified owner form, never in chat; it is not an AssemblyAI REST key and must not be moved to another service.
- A live check that opens a TTS WebSocket, reads `Begin` and sends no `Generate` proves acceptance of the configured voice only. It does not prove private visibility, upload source, consent attestation or speaker identity; those stay separate evidence.
- Reuse binds the caller, the exact approved script, the saved voice and any take label. Do not change punctuation, title or label to force a fresh paid take. Only an explicit request for another take authorizes a new label and its spend.
- On timeout, an unknown status or a lost response, recover the original job id instead of creating a new one: the provider may already have finished and billed it. On a real failure, report the returned error; never auto-retry into a stock voice, a new clone or a consent renewal.
- Take captions and word timings from the same accepted WAV, by alignment or transcription if the generator returned none. Never resynthesize the script to obtain captions.
- For operator tutorials, align the accepted WAV to the actual visible screen labels and actions, using timings from that same audio. If speech misnames a control or arrives before its visible state, repair the script, approved take or edit and recheck; captions must reflect what is actually spoken and remain clear of the UI in the intended player.
- A completed WAV is not a finished reel. Keep the approved source media, inspect pronunciation, pacing and synchronization, review the encoded video, and report actual artifacts and status.

## Host app boundaries

The hosted AssemblyAI app exposes transcript submission, status, summarize, understand, upload URL and explicit deletion. It does not expose TTS, voice listing, clone checks, consent renewal or live streaming. Use actual tool schemas, pass attachments through a supported file field when available, and never make private audio public to fill a URL field. Clinical audio needs verified agreements, authorized data flows and account controls; use synthetic or de-identified fixtures otherwise.

## MCP servers

| Server | URL | Use it to |
|---|---|---|
| `assemblyai-docs` | `https://www.assemblyai.com/docs/mcp` | Look up API details while coding. Free, no sign-in. |
| `assemblyai` | `https://mcp.assemblyai.com/mcp` | Transcribe and analyze audio at a public URL or an `upload_url`. OAuth sign-in. Usage is billed. It has no text-to-speech tool: speech uses the API. |

## Gotchas

- The REST `Authorization` header takes the raw key, with no `Bearer`. The hosted MCP is the opposite: OAuth or `Bearer`. The speech HTTP API accepts both.
- Always send `Terminate` when a streaming session ends. An abandoned session bills up to the 3-hour cap.
- LeMUR is sunset. `auto_chapters`, `summarization`, `summary_model` and `summary_type` are deprecated. Use the LLM Gateway.
- `redact_pii` needs `format_text: true`.
- `delete_transcript` is irreversible. Call it only on an explicit user request.

## Keys

Read `ASSEMBLYAI_API_KEY` from the server environment for direct API code. The hosted MCP or companion credential is a separate connection and is not usable for arbitrary REST calls. Never request a key in chat or put one in client code, a file, logs or a commit.

## Routing

Films, narration and voice-over go through `media-studio`, which checks funding and the job's voice approval, then calls AssemblyAI through its governed script. Give it the `voice_id` above. Its stock default outside ABACare is Deepgram, then Azure. Speech inside product code, such as a voice agent, uses the API directly.
