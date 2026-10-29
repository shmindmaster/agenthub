# Identity PCM derived clock

`qa/derived-audio-clock.json` explicitly selects the
`media-studio/derived-audio-clock/1` route in word-sync and full sync QA.
It is an ASR-anchored clock, never a forced-alignment claim. The job must set
`clockPolicy.allowAsrAnchored: true`. All other release gates remain required.

The manifest has `transform: "identity-decoded-pcm"` and immutable `{path, sha256}`
references named `candidate`, `script`, `sourceAudio`, `sourceAlignment`, and `raw`.
The source alignment is a successful canonical Nova3 script alignment from
`kit/cloud/cloud-ai.mjs`. The retained Nova3 response must contain its actual
request ID, model information and provider-reported SHA-256 of the uploaded WAV.
The validator regenerates clock words and coverage from that retained response.
It never substitutes an encoded-file hash into the source alignment.

The manifest must declare `pcm: {sampleRate: 16000, channels: 1,
sampleFormat: "s16le"}` (24 kHz and 48 kHz are also supported). The retained
upload must already be mono PCM16 WAV at that declared rate. Both files are
decoded completely to that canonical ASR representation with ffmpeg. Every byte,
including silence and the final sample, must match. There is no tolerance,
time shift, padding, truncation, speed change, edit graph or sampled comparison.
All immutable references are rechecked after decoding. The original 80 ms clock
grid, coverage limits and precision-limited words remain in force; word-sync
offset and drift limits remain 40 ms. PCM equality cannot improve ASR acoustic
accuracy or substitute for independent final-file content review. Mono sample-rate
normalization verifies the ASR representation, not multichannel or full-band
audio fidelity; independent audio review remains mandatory.

This strict route is useful when a WAV submitted for transcription was extracted
by decoding the exact encoded candidate into the declared ASR format. A WAV made before a lossy re-encode
usually cannot use this route. Obtain an actual alignment for the final audio
instead of relaxing equality or rewriting provenance.

Focused remote test: `node --test tests/derived-audio-clock.test.mjs`.
