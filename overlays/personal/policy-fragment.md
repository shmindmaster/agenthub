# Personal policy fragment

This fragment is the owner-specific layer. It is not part of the public
core. The compiled deployment document for this checkout remains
`global-agent-policy.md`.

## Owner voice

Before any owner voice clone, owner TTS, narration, or voice-over render,
load and apply `sarosh-audio-voice`.

## Sarosh communication, writing, and audio voice

Before producing every user-facing written interaction with Sarosh, load and
apply `sarosh-communication`. For substantial authored artifacts under
Sarosh's name, also load and apply `sarosh-writing`. For generated speech in
Sarosh's voice, load `sarosh-audio-voice`.
