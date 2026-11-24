# Consulting communication

Load for `consulting-demo`, `technical-walkthrough` or `product-update`. For `pitch`,
`proposal`, `status-update`, `kickoff`, `final-readout` or `value-review`, also load
[engagement formats](engagement-formats.md).
These profiles reuse the film types and existing gates. They do not authorize
spend, product changes, capture, or delivery. Private recipients, discovery
sources and media stay in the external job workspace; public examples are fictional.

## Brief and argument

Extend the existing approved brief with `communicationProfile`, `primaryAudience`,
`viewerDecision`, `primaryTakeaway`, `audienceContext { problemStatus, sourceRefs }`,
`nextStep { action, owner, agreedDate, sourceRefs }`, `maxDurationSeconds`,
`captionPolicy { mode, deliverySurface }`, `limitations` and `audioDirection`.
Use `confirmed-discovery`, `hypothesis` or `fictional-scenario` for problemStatus.
Confirmed discovery needs attributable sources. An unagreed date is null;
never invent discovery, ROI, buying intent, a meeting or a paid diagnostic.
This extends the existing exact-brief approval, with no second approval process.

| Profile | Existing type | Argument |
| --- | --- | --- |
| consulting-demo | feature-demo | Answer first; compact situation/complication/question/answer; three complementary proof moments in one workflow; demonstrated scope and limitations; one next step. Use Tell–Show–Tell and feature/advantage/benefit without claiming unmeasured customer benefit. Roughly two minutes is a recommendation; the approved ceiling governs. |
| technical-walkthrough | tutorial | Follow one real record/business event: source → intake → transformation → rules/AI → human decision → output → acknowledgment or exception. Start with system context; add container/component views only for the viewer's question. Explain the relevant decision and tradeoff. Keep this a separate technical cut. |
| product-update | internal-update | What changed → interaction → result → where to use it. Usually 20–45 seconds or an approved shorter silent capture. No three-moment requirement or commercial ask. |
| pitch | founder-pitch | Recommendation first, then why change, cost of inaction, the new way, why us, one ask. |
| proposal | explainer | Recommendation, their problem played back, approach, team, timeline, investment with assumptions and exclusions, one next step. |
| status-update | internal-update | Status chip and ask first; done, next, risks, decisions, plan against actual. A steering cut keeps four sections. |
| kickoff | explainer | Objectives, scope, governance, team, timeline, risks, the first 30 days. |
| final-readout | explainer | Recommendation first, findings, roadmap, business case, one next step. |
| value-review | explainer | Baseline, realized result and evidence, measured against the business case; one next step. |

The six engagement profiles declare each beat's `section` and need no product UI proof
(`proofMoments` is 0). Sections, ceilings, fixtures and checks are in [engagement formats](engagement-formats.md).

For a technical cut declare `scenarioRecord`, `integrationStatus` (`file-import`,
`demonstrated-adapter`, `proposed`) and `integrationFlow` with the seven machine
values in the screenplay schema. A CSV upload is never evidence of live sync.
Follow one case across explicit role handoffs; do not collapse distinct authorities.

Optional `walkthroughType` guidance for a technical cut. It is a planning note in the brief, not a schema field, and nothing checks it.
- `solution`: current state, future state, transition. Walk one real scenario through both.
- `architecture`: one C4 level per scene (context, then containers, then components). Zoom in only after the level above has landed. Add a decision card per key choice: options considered, the one chosen, the reason.
- `requirements-playback`: read each requirement back and ask for sign-off. Keep it short.
- `handover`: I do, we do, you do, one task per video. Link the runbook beside it. Name who owns what at the end.

Write scene conclusions before narration. Every substantive scene has an
`actionTitle` (a full sentence), `supportingArgument`, `proofRefs` and `evidenceClaims`.
Run `check-story.mjs` on the brief; its `titlesOnly` output is the ghost storyboard.
Use `node scripts/check-story.mjs story/brief.json --titles` to display just the
scene conclusions without narration (the process still exits nonzero on failure).
Display those titles alone at Pink. The mechanical check establishes presence and
fit; a separate reviewer must judge that they form a coherent, relevant argument.
Navigation labels and repeated control slogans do not pass that editorial review.
Keep the five-second hook; speak the answer within 15 seconds. Check scene totals
before generating voice; revise a long plan rather than accelerating the narrator.

## Proof scope

Each claim carries `text`, `scope`, `sourceRefs` and independent dimensions:
`implementationState` (implemented/proposed), `dataType` (synthetic/customer/public),
`aiExecutionMode` (live/recorded/stubbed/none), and `businessValidation`
(unvalidated/measured/discovery-confirmed). Copy these fields through to the final
scene plan; changing creative mode never bypasses evidence checks.

| Scope | Evidence |
| --- | --- |
| product-behavior | Accepted build, captured action and observed result; `uiProof` identifies actor, object, action, systemResponse, result and significance. |
| measured-benefit | Source plus measurement baseline, comparison, population, method and timeWindow; synthetic data cannot establish customer benefit. |
| proposed-interface | Proposed contract/diagram with visibleLabel; distinguish it from a demonstrated adapter. |
| customer-priority | Attributable confirmed discovery, never a generated scenario. |
| illustrative-scenario | Source/scenario reference and visibleLabel; no implication of adoption or financial results. |

References are planning evidence pointers, not proof that their contents are true.
The reviewer must open them and match every claim to the accepted build or source.
Source, selected action, decision and held result must remain understandable.
Use actual screen capture for interaction, side-by-side passages for conflict,
progressive flow diagrams for system boundaries, and sourced charts for measurements.
Retain sourceRefs and limitations when deriving executive or update cuts. Reuse
accepted footage and recapture only missing proof. Each ratio/export receives its
own framing, readability and final-file review.

## One review result

Use stage names in the existing production status and review result; no parallel
scorecard. Go/No-Go = approved audience/decision and reuse/recut/remake choice.
Pink = titles-only argument and claim-to-scene map. Red = rough-cut comprehension.
Gold = exact exported file and intended player/delivery surface. Keep the checks
lightweight for updates. Record each defect's stage, scene, timestamp, owner and
repair in the existing findings list. Misleading claims or unreadable key results
block regardless of average score. A recut invalidates candidate-bound reviews.

At delivered viewing size, read the source passage, response, assessment and
authorization status in a training workflow; follow origin, conflict, resolution
and handoff state in a case workflow. Narration cannot substitute for missing proof.
Review the first-15-second answer against the actual export; words/wpm is only a
planning estimate. Listen for meaningful conclusion versus repetition, not lexical
novelty alone. Procedure revision is a domain term; video revision is production talk.

`audioDirection` records narratorIdentity, pronunciationRefs, delivery, emphasis,
pauses and musicTreatment. Preserve one approved narrator. Listen across joins for
timbre, energy, pace and natural emphasis. ASR and loudness cannot establish
persuasiveness. When music is uncertain, compare the same short passage with a
restrained bed and no music; silence is valid. Existing governed provider/spend
policy applies. Do not restart local TTS or desktop voices.

Choose captions per export: selectable captions enabled in the player, approved
open captions, or a sidecar supported by the delivery surface. Gold checks the
actual player/file combination, spelling, timing, readability and key UI occlusion.
Do not override existing film-specific delivery instructions implicitly.

Do not apply Shipley, RAID/RACI, ADKAR or sales CTAs to every film. Each belongs only to
the profile that names it (see [engagement formats](engagement-formats.md)).

For selectable/open caption delivery, record `captions` in the existing
`qa/story-experience-review.json`: mode, deliverySurface, verdict PASS,
artifactPath relative to the job, and sha256 of that exact export. The check
must inspect the intended player as well as the file. Re-encoding invalidates it.

Pink uses the existing form-aware `write-story-review.py` route for these profiles,
without labelling a factual demo as fiction. Copy the approved decision fields and
profile-specific `narrative` into the screenplay/job. Its seven reviewer judgments
are audience, form-fit, visual-story, representation, ghost-storyboard, proof-scope
and answer-first, each with scene-cited evidence and pass/fail (not n/a). Bind
`qa/story-judgments.json` inputs.screenplay.sha256 and inputs.storyboard.sha256 to
the current files. The reviewer reruns the same story gate and requires the current
hash-bound narration report. No fixed dramatic hero or three-scene anticipation
is imposed on an update. Final encoded-file review remains a separate existing gate.
