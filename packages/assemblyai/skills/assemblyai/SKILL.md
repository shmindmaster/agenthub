---
name: assemblyai
description: "Builds AssemblyAI calls and code for speech-to-text and audio analysis. Use when a task calls AssemblyAI directly: transcription, streaming, speaker labels, PII redaction, transcript analysis, or its API or MCP servers."
---

# AssemblyAI

## Workflow contract

1. Identify the exact audio source, consent to process it, and whether speaker labels, redaction or streaming are required.
2. Resolve the supported API fields, submit the authorized asset once, then poll the same transcript ID to a terminal status.
3. Return the transcript ID, selected speaker labels and timestamps, and any unprocessed span.
4. If the asset is ambiguous, private without consent, or the status is unknown, stop before resubmitting. Terminate streaming sessions you opened.

Thin routing skill. The vendor docs are the source of truth.

## Before writing code

The API changes. Fetch both, and do not rely on memorized parameter names:

- https://www.assemblyai.com/docs/agent-instructions.md
- https://www.assemblyai.com/docs/llms.txt

Optional deep reference: `npx skills add AssemblyAI/assemblyai-skill`. That repository has no licence, so never copy its text.

## MCP servers

| Server | URL | Use it to |
|---|---|---|
| `assemblyai-docs` | `https://assemblyai.com/docs/mcp` | Look up API details while coding. Free, no sign-in. |
| `assemblyai` | `https://mcp.assemblyai.com/mcp` | Transcribe and analyze audio at a public URL or an `upload_url`. OAuth sign-in. Usage is billed. |

## Gotchas

- The REST `Authorization` header takes the raw key, with no `Bearer`. The hosted MCP is the opposite: OAuth or `Bearer`.
- Always send `Terminate` when a streaming session ends. An abandoned session bills up to the 3-hour cap.
- LeMUR is sunset. Use the LLM Gateway.
- `redact_pii` needs `format_text: true`.
- `delete_transcript` is irreversible. Call it only on an explicit user request.

## Keys

Read `ASSEMBLYAI_API_KEY` from the server environment. Never put a key in client code, a file or a commit.

## Routing

Video, audio and narration work goes through `media-studio`, which picks the provider. Azure is its default; AssemblyAI runs there only when a job names it.
