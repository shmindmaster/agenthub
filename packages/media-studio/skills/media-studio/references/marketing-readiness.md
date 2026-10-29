# Marketing readiness (customer-facing cuts)

A customer-facing video does not play in a review room. It plays in a feed, next to many other videos, and the
viewer decides in the first few seconds whether to keep watching. The bar for a marketing cut is therefore not
"accurate and complete". It is: **would this win the viewer in a feed next to the references?** A film that is
true, well synced and complete but loses that contest is not marketing ready. It is recut.

This rubric applies to every marketing cut: `programForm` `campaign-flagship`, `campaign-comparison`,
`campaign-short`, `campaign-outreach`, `marketing-cutdown`, `social-clip`, `hero`; `kind: teaser`; or
`marketing: true` in `job.json`. Explainers, training and technical stories keep `story-review-rubric.md`;
they inherit the no-fluff rule (`validate-narration.mjs`) and the cursor rule (`validate-pointer-path.mjs`)
but are not judged against reference ads.

The story-experience review (`media-studio-qa`) records the verdicts; `scripts/validate-marketing-readiness.mjs` holds
them to the floor on the exact encoded file and `validate-viewer-release.mjs` refuses a marketing cut without
a passing check. Below the floor is a fail. There is no score to average it away.

## The floor

| Criterion | Pass | Measured by |
| --- | --- | --- |
| hook-2s | The pain or the payoff is on screen inside **two seconds**. Not a logo, not a title, not a nav tour. | `hook.atSeconds` ≤ 2.0 on the encoded file |
| one-promise | The film makes one promise and keeps it. A second promise splits the cut. | `promise.count` = 1 with scene-cited evidence |
| designed-motion | Type and picture are designed to move: builds, wipes, cuts, a punch-in. No static hold a thumb would scroll past. | timestamped evidence |
| sound-design | Default music mode: a music bed under the voice and at least one designed cue (riser into the reveal, hit on a cut, sting under the end card). The bed carries the pace. | `sound.bed` true, `designCues` ≥ 1; explicit speech-only alternative below |
| brand-end-card | End card from the brand kit with one CTA, inside the last eight seconds. | `brand.endCardAtSeconds` inside the last 8 s of the file |
| cuts-on-beat | Default music mode: cuts land on the bed's grid: ≥ 90 % within 80 ms of the beat. | edit decision list vs `cutsOnBeat.bpm` / `offsetSeconds`; explicit speech-only cut adjudication below |
| references | Three reference ads this cut competes against, each with title, source and one sentence on why it wins attention. | exactly 3 entries |
| feed-test | The reviewer's answer to "would this win the viewer in a feed next to those three?" is **yes**, with evidence from the first five seconds. | `attentionCompetition.winsAgainstReferences` true |
| no-fluff | The narration check passed on this script (`qa/narration-check.json` ok). Fluff is a feed loss. | `validate-narration.mjs` |

## What the reviewer writes

`qa/marketing-readiness.json`, bound to the exact candidate:

```json
{
  "schema": "media-studio/marketing-readiness/1",
  "reviewer": "<who judged>",
  "candidate": { "path": "output/<base>.mp4", "sha256": "<sha256>", "bytes": 12345678 },
  "hook": { "atSeconds": 0.8, "what": "the held-claim count fills the frame before any logo", "verdict": "pass" },
  "promise": { "text": "See why a claim is held before the payer does.", "count": 1, "verdict": "pass", "evidence": "M01 names it, M06 shows it, M08 repeats it" },
  "motion": { "verdict": "pass", "evidence": "type builds at 0:00.4 and 0:03.1; rows wipe in at 0:05; no hold over 2 s" },
  "sound": { "bed": true, "designCues": 3, "verdict": "pass", "evidence": "riser into 0:04, hit on the 0:06 cut, sting under the end card" },
  "brand": { "kit": "<brand kit id>", "endCardAtSeconds": 46.5, "cta": "Book a 20-minute walkthrough", "verdict": "pass" },
  "cutsOnBeat": { "bpm": 120, "offsetSeconds": 0.12, "toleranceMs": 80, "verdict": "pass", "evidence": "cuts at 2.0, 4.0, 6.5" },
  "references": [
    { "title": "<ad>", "source": "<where it runs>", "whyItWins": "<one sentence>" },
    { "title": "<ad>", "source": "<where>", "whyItWins": "<one sentence>" },
    { "title": "<ad>", "source": "<where>", "whyItWins": "<one sentence>" }
  ],
  "attentionCompetition": { "winsAgainstReferences": true, "evidence": "the number lands at 0.8 s; the references take 1.5–3 s to state a pain" }
}
```

Every verdict carries a timestamp or a scene id. A criterion without evidence is a fail, not a pass. An honest
`winsAgainstReferences: false` is the most useful line in the file: it sends the cut back to the writer (`writer.md`) /
storyboard (`storyboard.md`) with the reference that beat it.

## Then

```text
node <tools>/validate-marketing-readiness.mjs <jobRoot> <candidate.mp4>
```

writes `qa/marketing-readiness-check.json` with per-criterion pass/fail and the measured cut grid. The
viewer-release gate requires it to be a PASS bound to the exact candidate for every marketing cut. On a fail,
recut the scenes the finding names, re-encode, rerun every gate.

The rhythm receipt may declare `cutsOnBeat.subdivision` as the integer `1`, `2` or `4` for quarter, eighth or sixteenth notes; omission retains quarter-note behavior. Keep the actual bed BPM (40–220), declare the audible grid honestly, and retain the 80 ms / 90% floor. The validator records BPM, subdivision and grid period separately; a subdivision is not evidence that the mixed cue is audible.

Declare the subdivision from the actual audible score and retain its provenance, never choose one merely to fit the edit. The grid period must exceed twice the fixed 80 ms tolerance, so the rhythm test can reject off-grid cuts; overly dense grids fail even when the supplied cuts lie on them.
## Explicit speech-only creative mode

The default remains `music`: omission never waives a bed or the audible beat-grid floor. Unknown modes fail.
An intentional speech-only film may opt in with BOTH `job.soundMode: "speech-only"` and
`readiness.sound.mode: "speech-only"`. `job.producer` names its actual editor/producer. Keep
`sound.bed:false` and `sound.designCues:0` truthful; do not invent music, cues or BPM.

The sound object references three job-relative evidence files as `{path, sha256}`:

- `authorization`: schema `media-studio/speech-only-authorization/1`, `soundMode:"speech-only"`,
  actual `authorizedBy`, concrete `reason`, and hash-bound `creativeSource:{path,sha256}` pointing
  to the original creative direction. A reviewer cannot infer authorization from missing music.
- `clock`: schema `media-studio/speech-edit-clock/1`, exact `candidateSha256`, actual `method`,
  `uncertaintyMs` (nonnegative measured precision, or null when unknown), hash-bound UTF-8 locked
  `script`, hash-bound original timing evidence `source:{path,sha256}`, and ordered `phrases:[{startSeconds,endSeconds,text}]`. All script text is preserved;
  zero-duration raw function words may remain. Never fabricate clocks or precision.
- `review`: schema `media-studio/speech-only-review/1`, exact `candidate:{sha256,bytes}`, independent
  `reviewer` distinct from `job.producer`, `independentOf` naming that producer,
  `wholeFileSoundReviewed:true`, `wholeFileEditRhythmReviewed:true`, full contiguous
  `coverage:[{startSeconds:0,endSeconds:<exact duration>}]`, explicit `uncertainties:[]`, and
  `clarity`, `pauses`, `pacing`, `transitions` each with `verdict:"pass"` and concrete timestamped
  `evidence`. Unknown clock precision must appear in uncertainties. Preserve actual limitations.

Review also binds the same `authorization` and `clock` file references and their exact hashes.
Review `edl:{path,sha256}` binds the actual cue-sheet/compose-map used by the gate. Its `cuts`
array enumerates EVERY actual EDL start after frame zero, in order, exactly once:
`{atSeconds,verdict,reason,observedEffect,relationship,phraseIndices}`. Times must equal actual
EDL starts. Reasons and effects cite what the reviewer observed at that cut. Relationships are
`phrase-boundary`, `continuous-speech`, `pause`, or `visual-transition`. Zero-based phrase indices
refer to the bound measured clock; they are required when speech timing is relevant (the first
three relationships), optional for an independent visual transition. The gate checks provenance,
ordered/in-range clocks, script coverage, exact-file review coverage and exhaustive cut enumeration.
It does NOT decide artistic timing or manufacture a universal speech beat threshold. A cut during
continuous speech can pass when an independent reviewer judges its actual effect intentionally good.

The report writes `speechOnly` evidence and `speech-edit-rhythm` checks; `cutsOnBeat` stays null.
This branch replaces ONLY music-bed/cue and musical-grid criteria. Hook, promise, designed motion,
CTA, references, feed competition, narration and all separate release gates remain unchanged.
A complete provenance record is not proof that the reviewer actually watched/listened: the review
must truthfully record that act, not extrapolate it from a render or sampled stills.
