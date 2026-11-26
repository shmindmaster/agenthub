# Narration companion contract

This reference describes an **optional host-provided** narration companion, not a tool that this plugin ships or that the hosted AssemblyAI MCP provides. Load it only when the running host actually exposes such tools. Discover their names and schemas in that host; a published website or a remembered tool name is not a callable connection.

## Operations to expect

| Operation | Purpose | What it proves |
|---|---|---|
| Connection state | Show saved connection/setup state and recent jobs | Configuration and pending work; no provider call |
| Saved voice profiles | Show saved aliases and preference | Configuration only, never a live account voice list |
| Voice acceptance check | Open a TTS WebSocket, read `Begin`, send no `Generate` | The configured voice is accepted now; not private visibility, source, consent attestation or identity |
| Narration generation | Send the exact approved script for an authorized speaker | A billed job or a reused accepted take |
| Job result | Return the saved state, metadata and private artifact links for a job id | Actual job state; no new synthesis |
| Audio | Return the completed WAV | The audio that must be reviewed |
| Captions | Return word timings and SRT when present | Timing for that same delivered WAV; may be absent |

## Secure setup

- Check connection state first. Distinguish a missing owner credential from incomplete server setup; they are different blockers.
- The owner enters a companion credential through the verified origin's secure form and attests authorized use there. Never ask for it in chat, copy it into a file, or reuse it as an `ASSEMBLYAI_API_KEY`.
- Keep the approved script and source media ready before setup. After setup, resume the same pending job instead of asking the speaker to choose a voice again.
- If the tools are not attached, say exactly which connection is missing. A verified site may still support the flow through its UI; a desktop installation is not implied.

## Take identity and reuse

Idempotency binds caller, exact approved text, saved voice and take label. The same inputs reuse the original job. Changing only a title or caption option does not create a new take. Do not change punctuation or labels merely to bypass reuse.

Only an explicit owner request for another paid take justifies a new short take label and the authorization flag that reflects that request. Billing is per character sent; prefer the accepted take.

## Result handling

- `processing`: retrieve the same job id later.
- `unknown`, timeout or lost response: recover the original saved job. The provider may have completed and billed it; never create a new identity and resubmit.
- `failed`: report the returned error and fix the actual issue. No automatic retry, stock substitution, re-clone or consent extension.
- `completed`: play the actual WAV and retrieve its captions. Report the real job id and whether the take was reused.
- Missing timings: align or transcribe the **same accepted WAV** through STT with word timing. A private artifact URL may not be readable by the provider; never publish it to work around that.

## Evidence boundaries

Keep these separate: owner attestation, live voice acceptance, completed speech, accepted narration, and a reviewed finished reel. Identify generated speech as AI-generated in delivery metadata. Preserve the approved visual treatment; do not add an unwanted narration label over the video. Audio completion alone never authorizes publication.
