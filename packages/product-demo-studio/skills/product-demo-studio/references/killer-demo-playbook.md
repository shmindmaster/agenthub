# Killer demo playbook

Use this compact adapter alongside the complete
[Killer Demo Production Guide](killer-demo-production-guide.md) when selecting, planning,
producing, or reviewing an episode. The complete guide is the persuasive/craft source of truth;
this file maps it onto the plugin's normalized validators. Preserve a target repo's existing
catalog and manifest shapes; when they differ, export equivalent normalized JSON rather than
forcing a migration.

For orchestration, `policy/product-video-policy.json` is authoritative: the guide's historical
human script/final-watch checkpoints are replaced by automated validation, independent review,
iterative remediation, and terminal verification. The first human touchpoint is final presentation.

Before production, configure the output root, in-repo working directory, seed/reset environment,
brand tokens, approved voice profile, and optional issue tracker. Pick the demo type
(`sizzle-hook`, `guided-discovery-support`, `onboarding-enablement`, or `internal-handoff`) and
record whether the audience needs compliance-heavy trust framing or operational speed/ROI framing.

## Two valid outcomes

Every candidate episode ends in exactly one of these outcomes:

1. **Killer video** — a `PASS` or `CONDITIONAL` episode clears product truth, craft, technical,
   accessibility, provenance, and independent-review checks. Deliver the accepted master and requested
   derivatives.
2. **Product-readiness feedback** — a `FAIL` episode has one or more product-fix-required defects.
   Do not produce or deliver a mediocre master. Write a reproducible, buildable report instead.

A technically accurate but boring, cluttered, slow, or confusing video is not a third outcome.
Quality beats quota; zero videos plus precise feedback is a successful run.

## The classification boundary

- **Capture-fixable** — the pipeline can fully resolve the issue without changing the product:
  zooming small but readable UI, cutting idle time, speed-ramping a bounded wait, spotlighting a
  busy screen, reframing a vertical cut, or synthesizing deliberate cursor motion. These do not
  block an episode. Record the required treatment and verify it during QA.
- **Product-fix-required** — editing cannot hide the issue because it belongs to the product UX:
  no crisp outcome, excessive mandatory setup, broken/unfinished states, layout instability,
  unreadable density, an unbounded wait without feedback, a hidden primary action, a flaky flow,
  no visible trust/human-control guardrail, or no real hero moment. These block the episode.

When classification is uncertain, capture a short diagnostic sample, inspect the rendered frame
and timing evidence, and classify from what a viewer would actually experience.

## Demo-worthiness rubric

Assess the real workflow before committing to master production. Record evidence for all eleven
criteria in the configured working directory's `feedback/` folder and validate the normalized readiness sheet with
`validate-demo-readiness.mjs`.

1. **Single clear outcome** — one visible, valuable result fits within three minutes.
2. **Fast to value** — minimal mandatory navigation and setup before value appears.
3. **Clean believable states** — seeded empty/loading/success/error states are presentable; no
   placeholder, lorem, broken, or impossible state appears on the path.
4. **Visual stability** — no layout shift, overflow, clipping, or broken responsive state.
5. **Legibility** — key UI remains readable at delivery size or with a reasonable capture zoom.
6. **Bounded, feedback-rich waits** — waits are fast, cuttable, or visibly explain progress.
7. **Discoverable primary action** — the main action is clear without tribal knowledge or dead ends.
8. **Deterministic and resettable** — the synthetic flow reseeds and reproduces identically.
9. **Visible guardrail** — a trust, safety, verification, or human-decision moment can be shown.
10. **Hero moment exists** — one real in-product reveal is worth protecting and building around.
11. **Polish baseline** — consistent theming and no visibly unfinished happy-path surface.

Verdicts:

- `PASS` — all criteria pass; no capture or product fixes are needed.
- `CONDITIONAL` — failures are capture-fixable only; record exact treatments and proceed.
- `FAIL` — at least one product-fix-required defect; stop master production and route to feedback.

## Persuasion contract

Normalize every episode and segment into a storyboard that can be checked with
`validate-storyboard.mjs`.

Episode fields:

- one audience, humanized persona, problem, visible outcome, and guardrail;
- one emotional target at the payoff: relief, confidence, delight, vindication, or another named
  feeling appropriate to the vertical;
- exactly one protected hero moment: the reveal everything before sets up and everything after
  resolves;
- one shown before-state beat lasting about three to five seconds;
- one cold-open segment whose first frame carries pain, tension, or a one-to-two-second trailer
  glimpse of the result — never login, dashboard tour, logo preamble, or "in this video";
- for problem-solving or AI episodes, a brief taste of the hard case before the clean result;
- a short denouement and one designed end card with outcome, next step, brand, and approved link/QR.

Segment fields:

- unique ordered ID, on-screen action, expected state, spoken text, timing, emphasis, pauses, and
  one eye-direction cue;
- a one-line WIIFM (why the viewer cares); cut or re-anchor any segment without one;
- a primary WIIFM ladder rung: `feature`, `outcome`, or `identity`; the payoff must reach `outcome`
  or `identity`. Existing richer storyboards may use `functional-benefit`, `practical-outcome`,
  `emotional-outcome`, or `identity-outcome`; the validator accepts those as refined aliases, but
  `functional-benefit` still cannot satisfy the payoff gate;
- zero to two progressive annotations for the beat, removed as soon as their job is done;
- no more than one idea and one primary visual target;
- an explicit attention reset when needed so no unchanged stretch exceeds about 15 seconds.

## Story and screen craft

- Start in medias res. Make the cost of the old way felt before the payoff.
- Show contrast rather than merely claiming it: old way to new way, input effort to output result.
- Use one or two open loops at most; pay each off.
- Prefer the hard, still-clean case over a trivial toy input. Show a brief taste of complexity, then
  the result. For AI, show enough reasoning to earn trust and keep human control adjacent.
- Stage the hero moment with a beat of near-silence, a restrained push-in, at most one sound cue,
  and a readable hold. Do not give the episode a second competing reveal.
- Let the cursor act intentionally: gesture, hesitate, trace, click, then park away from content.
- Default deliberate pointer moves to 400–600ms with deceleration into the target. Settle at least
  250ms before a click and hold at least 500ms after it. Use a 300–400ms restrained radial pulse
  for clicks, a held state/trail for drags, native product feedback for hovers, and a reproducible
  keystroke overlay for shortcut-driven changes. Scale the pointer 1.5–2× for mobile/embedded cuts;
  never use a persistent follow-the-pointer spotlight.
- Build dense screens progressively and preserve spatial continuity.
- Snap to an active region over 300–500ms, hold through the action, and pull back only when context
  is useful. Allow at most one zoom change per beat and no continuous drift over UI.
- Use speed ramps as punctuation: real time for meaningful interaction, 4–8× or a truthful cut for
  bounded waits, 3–4× or chunked entry for text, and real time again for payoff. Never edit away a
  latency, feedback, or product defect that the viewer needs to understand.
- Use kinetic type for at most the one number that expresses the transformation.
- Seed a coherent synthetic mini-story with specific, believable values. Label synthetic claims
  and verify every visible value against the truth sheet.

## Narration craft

- Put pain or payoff in the first sentence. Center "you" and the viewer's units — time, money,
  headcount, risk, or effort — instead of vendor language and vague efficiency claims.
- Write one idea per short sentence. Use concrete specifics, contrast, the occasional rule of
  three, and rhetorical questions only when they create a loop the video pays off.
- Choreograph pace, pitch, emphasis, and pauses. Lead the eye just before an action; name a result
  just after it appears so the viewer discovers it first.
- Round for the ear while keeping exact values on screen. Leave the hero moment partly scriptless
  when silence is stronger than explanation.
- Keep narration, captions, and visual callouts distinct. Never narrate every click or repeat a
  headline word-for-word.
- Cut the first draft aggressively; every second must earn the next one.

## Craft gate

Fail closed after full-playback and representative-frame review unless all are true:

- the cold open establishes pain, tension, or desired outcome within five to eight seconds;
- exactly one hero moment exists and is staged, held, and protected;
- the before-state is shown, and the payoff reaches the outcome or identity WIIFM rung;
- every segment has one WIIFM and one idea;
- no uncut dead time remains, and attention changes at least about every 10–15 seconds;
- text annotations remain visible for at least `word count / 2.5 + 0.5 seconds`;
- results land in deliberate near-silence;
- voice is conversational, varied, correctly pronounced, and not wall-to-wall;
- final frames are stable, legible at delivery size, and free of occlusion;
- the declared emotional target is actually supported by pace, music, silence, and wording;
- the close gives exactly one takeaway or next step and ends on a designed frame.

If re-editing cannot clear the gate, decide whether the remaining cause is capture-fixable or a
late-discovered product-fix-required defect. Pull and report the latter; never ship it to meet a
quota.

## Feedback contract

Write one fix-oriented entry per product-fix-required defect:

- stable ID and affected episode/flow;
- violated craft principle;
- exact observed behavior with frame, console, trace, and/or timing evidence;
- concrete viewer impact explaining why it blocks a killer demo;
- classification and severity (`blocks`, `degrades`, or `minor`; legacy `*-video` aliases work);
- concrete, buildable product change;
- shortest minimal set of fixes that moves each failed episode to pass.

Store the report under the configured in-repo working directory's `feedback/` folder. Create tracker tickets only when the current
request authorizes tracker writes; otherwise prepare ticket-ready entries and report that they were
not filed.

## Output family

Capture once and derive only the variants the user or repo requires: a roughly 90-second sales
master, 30-second social cut, 10–15-second teaser, silent GIF/loop, vertical 9:16 reframe with
captions, and a deliberate thumbnail/first frame. Recompose rather than crop. Do not multiply
deliverables by default when the episode or request needs only one format.

## Timed script and provider preflight

The structured timed script is the source of truth for capture, narration, annotations, captions,
and render timing. Validate it automatically before final capture, then run the independent review,
remediation, and terminal verification loop before final presentation. Before any billed narration run, resolve the current speech and transcription
models against provider model/deprecation information, verify credentials without generating,
recheck price and quota, verify the approved voice still exists, estimate cost from measured
duration, and record provider/model/voice/instructions/speed/formats in the episode manifest. Never
hardcode the dated provider snapshot in the complete guide as if it were current.

Deliver final masters flat under `<OUTPUT_ROOT>/<PRODUCT>/`, requested cut-downs under `cuts/`, and
keep scripts, truth sheets, captions, claims, manifests, checksums, and QA evidence only in the
configured in-repo work directory. Feed completion rate, watch percentage, drop-off timestamps,
CTA/reply rate, and the demo type's downstream outcome back into the next script revision.
