# Marketing readiness

The bar: would this win the viewer in a feed next to the references? Below the floor is a fail, and no score rescues it.

Applies when `job.json` has `marketing: true`, `kind: teaser`, or `programForm` `campaign-flagship`, `campaign-comparison`, `campaign-short`, `campaign-outreach`, `marketing-cutdown`, `social-clip` or `hero`.

1. Watch the exact candidate. Write `qa/marketing-readiness.json`; an mvg job writes `qa/<ratio>/marketing-readiness.json`.
2. Run `node <tools>/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>`. It writes `qa/marketing-readiness-check.json`. The release gate refuses looser threshold flags.
3. On a fail, recut the named scenes and rerun every gate.

## Floor

Every `verdict` is `pass`. `schema` is `media-studio/marketing-readiness/1`. Brackets are minimum characters.

| Check | Fields | Floor |
| --- | --- | --- |
| candidate-binding | `reviewer`, `candidate.sha256`, `candidate.bytes` | Exact file |
| hook-2s | `hook.atSeconds`, `what` [10], `verdict` | JSON number, 0 to 2 |
| one-promise | `promise.text`, `count`, `evidence` [10], `verdict` | `count` 1 |
| designed-motion | `motion.evidence` [20], `verdict` | Timestamped |
| sound-design | `sound.bed`, `designCues`, `evidence` [10], `verdict` | `bed` true, 1 cue |
| brand-end-card | `brand.kit`, `cta` [3], `endCardAtSeconds`, `verdict` | In the last 8 s |
| cuts-on-beat | `cutsOnBeat.bpm`, `offsetSeconds`, `subdivision`, `verdict` | BPM 40 to 220; subdivision 1, 2 or 4; grid over 160 ms; 90% of cuts within 80 ms |
| references | `references[]`: `title`, `source`, `whyItWins` [10] | Exactly 3 |
| feed-test | `attentionCompetition.winsAgainstReferences`, `evidence` [20] | True |
| no-fluff | `qa/narration-check.json` | `ok` true |

Cut times come from `plan/cue-sheet.json` `edl`, else `--compose-map`.

## Speech-only

Default `sound.mode` is `music`. Speech-only needs `job.soundMode` and `sound.mode` both `speech-only`, `job.producer`, `sound.bed: false`, `sound.designCues: 0`. Check `speech-edit-rhythm` replaces sound-design and cuts-on-beat. `sound` holds three `{path, sha256}` files, per `scripts/speech-only-readiness.mjs`:

- `authorization`: `media-studio/speech-only-authorization/1`, `soundMode`, `authorizedBy`, `reason` [20], `creativeSource`.
- `clock`: `media-studio/speech-edit-clock/1`, `candidateSha256`, `method`, `uncertaintyMs`, `script`, `source`, `phrases[]` covering the script.
- `review`: `media-studio/speech-only-review/1`, `candidate`, `reviewer` (not the producer), `independentOf`, `wholeFileSoundReviewed`, `wholeFileEditRhythmReviewed`, `coverage`, `uncertainties`, `clarity`, `pauses`, `pacing`, `transitions`, `authorization`, `clock`, `edl`, `cuts[]` for every cut (`atSeconds`, `verdict`, `reason`, `observedEffect`, `relationship`, `phraseIndices`).
