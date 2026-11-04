# Word and picture clocks

## New film

1. Set `"clockPolicy": { "allowAsrAnchored": true }` in `job.json`.
2. Align each accepted take and the exact encoded candidate: `node <kit>/cloud/cloud-ai.mjs align --take <file> --script <script.txt> --out <report.json>`. Report schema `cloud-speech/script-alignment/1`, method `asr-anchored-alignment`, 80 ms grid. A report under the limits lands at `<report.json>.failed.json`.
3. Put take reports at `voice/align/<id>.json`, the encoded report at `qa/encoded-alignment.json`, the script at `story/locked-script.txt`.
4. After the last compose run `build-cue-sheet.mjs <jobRoot>`, `validate-word-sync.mjs <jobRoot> <candidate>` (`qa/word-sync.json`), `validate-sync.mjs <jobRoot> <candidate>` (`qa/sync.json`).

A new film without the opt-in has no accepted word clock: report word-sync as blocked, never as passed. A `validate-sync.mjs` pass without a clock is not one. Whisper checks text; its onsets never set a clock.

## Accepted clocks

Scripts are in `scripts/`. `forced` means `syncClock: "forced-aligner"`. Word-sync uses the first of rows 2 to 5 present, else `qa/encoded-alignment.json`. `validate-sync.mjs` does not read rows 4 and 5.

| Kind | Applies when | Script and file | job.json | Limits |
| --- | --- | --- | --- | --- |
| 1 ASR-anchored | Every new film | `validate-word-sync.mjs`, `qa/encoded-alignment.json` | Opt-in | At least 90% exact onsets, no precision-limited run over 6 words |
| 2 Queue Qwen | Accepted film, read-only | `queue-qwen-alignment-clock.mjs`, `qa/queue-qwen-alignment.json` | `forced` | Schema `media-studio/queue-qwen-forced-alignment/1`; `gridSeconds` 0.08 or null; identical PCM; final word overrun 0 to 10 ms |
| 3 Derived PCM | The WAV sent to ASR was decoded from the exact candidate | `derived-audio-clock.mjs`, `qa/derived-audio-clock.json` | Opt-in | Schema `media-studio/derived-audio-clock/1`, `transform: identity-decoded-pcm`, refs `candidate`, `script`, `sourceAudio`, `sourceAlignment`, `raw`, `pcm` 16, 24 or 48 kHz mono `s16le`. Source is Deepgram `nova-3` with its retained response. Every decoded sample matches |
| 4 Hosted forced | Existing manifest; ElevenLabs is blocked | `hosted-alignment-clock.mjs`, `qa/hosted-encoded-alignment.json` | `forced` | Schema `media-studio/hosted-forced-alignment/1`; upload mono 24 kHz PCM16 WAV or FLAC, identical decoded PCM; grid and uncertainty null |
| 5 Edit map | Silence cuts or declared mutes of an accepted film | `validate-edit-map.mjs <jobRoot> <candidate> plan/edit-map.json`, `edit-map-clock.mjs`, `qa/encoded-edit-map.json` | `forced` | Schema `media-studio/edit-map/1`; refs `candidate`, `source.candidate`, `source.alignment`, `source.script`; `cuts`, `mutes`; `verifyPicture: true` when picture is kept. An ASR-anchored source is refused. No cut through a word or the tail, no replaced, stretched or reordered speech. PCM correlation 0.98 |
| 6 Forced report | Accepted film, read-only | `qa/encoded-alignment.json` | `forced` | Existing reports stay valid evidence for accepted films |
| 7 Piecewise picture | Compose group has `actualCaptureWindow.piecewise_time_map` | `piecewise-capture-clock.mjs` via `build-cue-sheet.mjs` | None | Anchors `output_frame`, `source_seconds`; `source_sha256` matches file and receipt. `validate-pointer-path.mjs` refuses it, which blocks release |
| 8 Physical result | Reviewer corrects a poll time from final frames | `physical-result-observations.mjs`, `build-cue-sheet.mjs <jobRoot> --physical-results qa/physical-result-observations.json` | None | Schema `media-studio/physical-result-observations/1`; `producer`, independent `reviewer`, `candidate`, `inputs`, `frameRate`, `observations[]` with native PNG crops. Constant frame rate. Result times only. Rebuild after the final encode |

## All word clocks

Offset and drift stay within 40 ms. That measures cue match, not acoustic accuracy. Missing, stale or invalid evidence fails closed. Never rewrite a report to select a route.
