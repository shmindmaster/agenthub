# Treatments

A treatment is a way to open, picture and close a film of a given format. These are choices, never gates. The user's brief wins, and a film may use none of them. They exist because a survey of delivered films found two screencast looks across most product clips, one portrait template across six walkthroughs, one dark concept card across 24 lessons, and localized films that were the English film with a swapped header. Pick on purpose; do not default.

Constant in every treatment: real UI only where the claim is verified (`product-picture.md`), one narrator, one brand-mark placement, captions as a sidecar `.srt`. Names are real kit names: archetypes in `kit/scene-archetypes.json`, visual kinds in `kit/src/Visuals.tsx`, screencast tools in `kit/screencast/`. Timings and easing: `../../produce/references/motion-recipes.md`.

## Treatments by format

Opening is the first 3 s. Close is the final state and hold: the brief's `finalHoldSeconds`, else at least 2 s, nothing moving and not fading.

| Id | Format | Use when | Opening | Picture grammar | Close | Unlike its siblings |
| --- | --- | --- | --- | --- | --- | --- |
| RT1 | Role task | One person, one job | Cost line as `kinetic-statement`, then the role's real screen | Live capture; `render-overlay` dim-cutout on the one control; `screen-in-context` | `kinetic-number` of time or steps saved | Starts from the cost, not the screen |
| RT2 | Role task | The task is a hand-off | Real UI already mid-action, no title | Capture with a `sourceRegion` push on each hand-off; `lower-third` names the role once | `checklist-build` of what the person now skips | No intro card at all |
| WW1 | Workflow | Five or more steps | `timeline` rail, all steps dim, first lit | Capture per step; rail stays as a one-line header; `chapter-card` only past 3 min | Rail fully lit plus outcome card | The rail is the spine |
| WW2 | Workflow | Steps differ in kind (human, AI, system) | `process-flow` of who acts, drawn in 2 s | Capture alternates with `diagram-build` of what the system did; `sequence` for hand-offs | `before-after` of the record, then outcome card | Shows the invisible step |
| WW3 | Workflow | Viewer must repeat it | Finished result first (2 s), then the method | Capture with a `code` or `table` card for exact values | `checklist-build` of the steps | Result before method |
| LW1 | Localized | Same product, new language | Title written fresh in the target language | Capture in that language's UI where it exists; overlays re-laid for text length | Outcome card in the target phrasing | Re-timed to the translated narration |
| LW2 | Localized | Market has its own norms (dates, units, forms) | Market-specific example record on screen | Recapture with local sample data | Local call to action | Different data, not just words |
| EL1 | Engineering lesson | One mechanism | The failure as `quote-problem` | `diagram-build` (flow, layers) landing on spoken words; one lit node | `kinetic-statement` of the rule | Starts from the break |
| EL2 | Engineering lesson | Trade-offs | `comparison` of two designs, winner unlabelled | `data-chart` of the measured cost; `evidence-proof` code | `hero-reveal` of the chosen design | A decision, not a description |
| EL3 | Engineering lesson | A trace or incident | `timeline` with the first event | `drawn-mechanism` tracing the path; `code` for the key line | `checklist-build` of the guard added | Chronology is the structure |
| AL1 | Assessment lesson | Check understanding | The question on screen, narrator silent 2 s | `quote-problem` question, then the answer built by `diagram-build` | Rubric as `checklist-build` | Question before teaching |
| AL2 | Assessment lesson | A common mistake | A wrong answer shown as if right | `before-after`, wrong against right | `kinetic-statement` of the test to apply | Teaches by the error |
| MB1 | Briefing | Know the other party | `lower-third` with one fact about them | `table` of positions, `timeline` of dates, `proof` of the document | `checklist-build` of asks | Person first |
| MB2 | Rehearsal | Practise a hard exchange | Their hardest question as `quote-problem` with `speaker` | One scene per turn; body shows the thing discussed (`scenes.md`, Dialogue) | Their best answer as `hero-reveal` | Turn-taking, accent per speaker |
| PO1 | Product overview | Many workflows | `chapter-card` ladder of the jobs | One capture per job, equal weight | `cta-end-frame` | Tour by job |
| PO2 | Product overview | One standout workflow | Hero capture; narrator names the promise | Capture; `evidence-proof` for one number | `kinetic-number` outcome | One workflow, not a tour |
| PP1 | Portfolio proof | Show it was built | Result running, no title for 3 s | Real capture; `code` card with provenance; `lower-third` role | One metric as `kinetic-number` | Evidence only, no pitch |
| PP2 | Portfolio proof | Show how it was thought | `diagram-build` of the design | `drawn-mechanism`, then capture of the result | End frame with the name | Design before demo |
| SI1 | Service intro | Buyer unsure what you do | The buyer's problem as `quote-problem` | `before-after`, then one `evidence-proof` of a delivered result | `cta-end-frame`, one next step | Opens in their words |
| SI2 | Service intro | Buyer compares vendors | `comparison` of two ways to get the job done | `process-flow` of the method; `evidence-proof` | `checklist-build` of what they receive | Method, not claims |
| VH1 | Vertical highlight | One moment, muted feed | The result frame in the first 1.5 s | One recomposed panel; the `title` as large type | Outcome line, hold | Result first |
| VH2 | Vertical highlight | Needs the how | Cropped control, one overlay | Two panels in sequence, never stacked | Outcome line | Two beats, one panel each |
| VH3 | Teaser, 15-30 s | Drive to the full film | A question line, 1.5 s | Three captured moments, 4-6 s each | `cta-end-frame` naming the full film | A teaser, not a highlight |

## Engagement films

One suggestion each. Form and checks: `engagement-formats.md`.

- pitch: `kinetic-statement` recommendation; `kinetic-number` cost of waiting; close on `comparison` of options, then `cta-end-frame`.
- proposal: `quote-problem` of their words; `process-flow` phases; `timeline` with gates; `comparison` with assumptions shown.
- status-update: status word as a chip in `kinetic-statement`, never colour alone; real tracker in `screen-in-context`; `data-chart` plan against actual.
- kickoff: `kinetic-statement` objective; `timeline` with gates; `lower-third` per owner; close `checklist-build` of the first 30 days.
- final-readout: `hero-reveal` recommendation; `evidence-proof` per finding; `timeline` roadmap with owners.
- value-review: open on `before-after` of baseline and realized; `kinetic-number` per measure with its source.

## Pacing and sound

| Format group | Pacing | Sound |
| --- | --- | --- |
| Role, workflow, overview | One beat per 3-6 s; hold each result 1.5 s | Voice anchor, bed ducked; silence on the result |
| Lessons | A visible change every 4-8 s; 2 s pause before the answer | Voice only; a soft tick on the lit node |
| Briefing, rehearsal | One turn per scene, 5-12 s | Voice per speaker, no bed |
| Portfolio, service | 2-4 s beats; hold the metric 2 s | Light bed, ducked under every word |
| Vertical, teaser | A cut every 3-5 s; first change by 1.5 s | Built to read muted first; sound adds, never carries |

Muted play means the shot `title` and the outcome line carry the meaning on screen; captions stay a sidecar.

## Vertical and localization

**Vertical.** Recompose from native captures: choose a `sourceRegion` around one panel, show one panel at a time, keep text at 22 px or larger at 1080x1920 equivalent, keep graphics inside the safe area and out of `captionRegion` (`campaign-contract.mjs`). Never a blurred fill, never the 16:9 frame shrunk into the middle.

**Localization.** Write the title and outcome in the target language first, then fit the picture to it. Recapture in that language's UI where it exists, re-time to the translated narration, use local sample data where the market differs, and check that long words fit before render. A header swap is not a localized film.

## Rotation for a series

1. Keep constant: brand mark, narrator, UI honesty, outcome-card wording pattern.
2. List the last two episodes' treatment ids. Pick one whose opening archetype and closing archetype both differ from the previous episode's.
3. Within an episode, adjacent shots do not share a family unless `repeatIsPoint`.
4. Record the chosen id in the job plan so the next episode can read it.

Example: episode 1 RT1 (statement open, number close), episode 2 RT2 (live-UI open, checklist close), episode 3 WW1 (rail open, rail-plus-outcome close).

## Outcome card wording

Name a concrete, sourced result, never a feeling: "<result> in <time or steps>, <what changed for whom>". Use `kinetic-number` for a measured figure and `cta-end-frame` when the result is the next step. A number needs a source; do not invent one.
