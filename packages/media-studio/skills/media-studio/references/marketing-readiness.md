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
| sound-design | A music bed under the voice and at least one designed cue (riser into the reveal, hit on a cut, sting under the end card). The bed carries the pace. | `sound.bed` true, `designCues` ≥ 1 |
| brand-end-card | End card from the brand kit with one CTA, inside the last eight seconds. | `brand.endCardAtSeconds` inside the last 8 s of the file |
| cuts-on-beat | Cuts land on the bed's grid: ≥ 90 % within 80 ms of the beat. | edit decision list vs `cutsOnBeat.bpm` / `offsetSeconds` |
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
