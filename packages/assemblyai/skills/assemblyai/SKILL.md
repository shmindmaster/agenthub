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

Optional deep reference: `npx skills add AssemblyAI/assemblyai-skill`. That repository has no licence, so never copy its text.

## Cloned voices

Both are private to the ABACare account, in the US zone, English, on `assemblyai-tts-1`.

| Speaker | `voice_id` | Use it when |
|---|---|---|
| Sarosh Hussain | `sarosh-hussain` | The request says "my voice" or "my cloned voice", or Sarosh is the speaker |
| Syeda Fatima Abidi | `syeda-fatima-abidi` | Syeda is the speaker |

- Personal or ABACare work only. For personal narration with no other voice named, use `sarosh-hussain`. For ABACare, use the clone of the person speaking; any other narrator or character gets a stock `aai-` voice. Other companies' work gets a stock voice through `media-studio`.
- Check the clone before a job: `GET https://tts.us.assemblyai.com/v1/voices/<voice_id>` must show `status: active`, `assemblyai-tts-1` in `ready_models`, `consent.attested: true` and a future `retention.expires_at`. The check is free.
- Never swap in a look-alike or stock voice silently. If the clone fails the check, say so and stop before any paid speech.
- Consent lasts 60 days and an expired clone cannot be revived. Tell the owner when fewer than 14 days remain. `extend_biometric_consent` attests consent on the speaker's behalf, so send it only after that speaker said yes in the current task.
- Creating a clone, deleting one or making one public needs an explicit request. Label the delivered speech as AI-generated.

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

Read `ASSEMBLYAI_API_KEY` from the server environment. Never put a key in client code, a file or a commit.

## Routing

Films, narration and voice-over go through `media-studio`, which checks funding and the job's voice approval, then calls AssemblyAI through its governed script. Give it the `voice_id` above. Its stock default outside ABACare is Deepgram, then Azure. Speech inside product code, such as a voice agent, uses the API directly.
