# Exact encoded-file hosted forced alignment

`qa/hosted-encoded-alignment.json` explicitly selects the hosted route in
`validate-word-sync.mjs`. It never relabels provider evidence as Local-AI.
The supported provider contract is ElevenLabs `/v1/forced-alignment`.

The manifest schema is `media-studio/hosted-forced-alignment/1`, with
`provider: elevenlabs`, `endpoint: /v1/forced-alignment`, `units: seconds`,
`gridSeconds: null`, `uncertaintySeconds: null`, and `durationSeconds` equal
to the uploaded decoded PCM sample duration. Required immutable references
(`path`, `sha256`) are `candidate`, `script`, `raw`, and `uploadedAudio`.
Candidate also records `bytes`; uploadedAudio records `format: pcm_s16le`,
`sampleRate: 24000`, `channels: 1`. Request provenance records `state:
completed`, `id` and `requestKey`; retain durable submission fences and raw
provider receipts independently. This validator makes no provider calls.

The uploaded WAV must actually be mono 24 kHz PCM16, and its entire decoded
PCM must exactly equal the entire final candidate decoded to that format.
Every raw character and word interval/loss is validated. Whitespace word
entries are checked and omitted from the lexical cue clock. The complete
ordered locked script must match both raw characters and lexical words.
The final viewer gate revalidates current immutable inputs and exact PCM.

The method is `hosted-forced-alignment-on-encoded`. Grid and uncertainty
remain null: the provider has not established an acoustic accuracy bound.
Raw per-word and aggregate losses remain in the report. The existing 40 ms
offset and drift floors remain unchanged; they measure cue correspondence,
not absolute acoustic accuracy. Full final-file acoustic review is still
required, and this path does not certify rendered caption pixels or picture.
