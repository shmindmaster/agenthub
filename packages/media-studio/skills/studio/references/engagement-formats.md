# Engagement formats

Load for `pitch`, `proposal`, `status-update`, `kickoff`, `final-readout` or `value-review`.
They extend [consulting communication](consulting-communication.md): same brief, same claim
scopes, same Go/No-Go, Pink, Red and Gold stages. There is no new job system, renderer or gate.
Examples are fictional. Private recipients and real figures stay in the job workspace.

## Pick the profile

| Profile | Film type | Ceiling | Sections, in order (`?` is optional) | Use when |
| --- | --- | --- | --- | --- |
| pitch | founder-pitch | 180 s | recommendation > why-change > cost-of-inaction > new-way > why-us > options? > ask | "Pitch video", win the room, open an account |
| proposal | explainer | 300 s | recommendation > understanding > approach > team > timeline > options? > investment > next-step | "Proposal video", sits beside a written proposal |
| status-update | internal-update | 120 s | status > done > next > risks > decisions > plan-vs-actual | "Status update", weekly report, client progress |
| kickoff | explainer | 240 s | objectives > scope > governance > team > timeline > risks > first-30-days | "Kickoff video", start an engagement |
| final-readout | explainer | 480 s | recommendation > findings > roadmap > business-case > next-step | "Final readout", close an engagement, approve a roadmap |
| value-review | explainer | 180 s | baseline > realized > evidence > next-step | "Value review", benefits against the business case |

A "steering committee update" is `status-update` with `cadence: "steering"`. It needs only
plan-vs-actual > risks > decisions > next. The weekly cut (`cadence: "weekly"`) keeps the full list and a 90 s ceiling.
Complete fictional briefs that pass the gate, one per profile (check yours with `node scripts/check-story.mjs <brief.json>`):
`tests/fixtures/engagement/pitch.json`, `tests/fixtures/engagement/proposal.json`,
`tests/fixtures/engagement/status-update.json` (weekly, 90 s), `tests/fixtures/engagement/status-update-steering.json`,
`tests/fixtures/engagement/kickoff.json`, `tests/fixtures/engagement/final-readout.json`,
`tests/fixtures/engagement/value-review.json`.

## Declaring sections

Each beat names its section in the optional field `section`. Beats keep their `storyRole` too,
because the film type's own slots still apply. Use these roles so the type's slots are met:

| Profile | storyRole by section |
| --- | --- |
| pitch | recommendation hook; why-change and cost-of-inaction problem; new-way solution (name the product here); why-us proof; options explanation; ask cta |
| proposal | recommendation to timeline and options explanation; investment takeaway; next-step next-step |
| status-update | status context; done demonstration; next next-step; risks and decisions explanation; plan-vs-actual proof |
| status-update, steering cut | plan-vs-actual context; risks demonstration; decisions explanation; next next-step (internal-update needs a context beat, then a demonstration, then a next-step) |
| kickoff | objectives to risks explanation; first-30-days takeaway |
| final-readout | recommendation, findings, roadmap explanation; business-case payoff; next-step next-step |
| value-review | baseline explanation; realized payoff; evidence proof; next-step next-step |

The gate checks in code, not in the schema: the opening beat declares the first section,
every required section appears, sections keep the profile order, and a section may span
consecutive beats but not come back. An unknown section is reported with the allowed values.
The opening beat must declare the first section. A later beat with no `section` is tolerated. The three older profiles ignore the field.

## What each format needs

- **Every format.** Answer first. One action title per scene. Every claim has a source. Write the titles first (Pink).
- **Ceilings are advice.** The brief's `maxDurationSeconds` governs. The gate does not flag a brief above the ceiling.
  Shorten before you lengthen. The reviewer may note it at Pink.
- **One ask.** Pitch, proposal, final readout and value review allow one beat with the `cta` or `next-step` role.
  Two asks means two videos. The ask carries the existing `nextStep` owner and date.
- **Numbers.** The baseline and realized scenes (value review) each carry a `measured-benefit` claim, and so does the
  cost-of-inaction scene (pitch) when it states a number, in digits or in words. It needs a source and a baseline, comparison, population, method and time window.
  Synthetic data never proves a customer number. If you have no measurement, state the cost in plain words without a number.
  "States a number" is a word-list heuristic: any digit, or words such as zero, two to twelve, thirteen to ninety, twice, doubled,
  dozens, half of, a quarter of, percent. A claim in these scenes is checked for source, measurement and real data on any beat,
  even a hook, an ask or a next step.
- **Options (pitch, proposal).** When present: `options: [{ label, recommended }]` with two or three entries and exactly one recommended.
- **Investment (proposal).** The scene lists `assumptions` and `exclusions`, each a list of short statements.
- **Status.** Brief fields: `rag` (red, amber, green), `ragSince`, `statusDate`, `risks` and `decisions`.
  Each risk has description, owner, impact and mitigation. Each decision has the decision, an owner and a
  `dueDate`. Use null only when no date is agreed. An agreed date needs YYYY-MM-DD and `sourceRefs`.
  Green with an unowned risk or an overdue decision is a finding. Show amber as soon as it is true.
  Record an empty list when there are no risks or decisions. Link the risk log and decision log beside the video.
  Status narration may say what changed or previously (the same narrow exemption as product-update); "since last time" stays refused.

## Habits that apply inside one profile

- **pitch:** lead with their problem, then earn the ask. Credentials appear only as proof (why-us).
  Cut variants for the economic buyer, the technical evaluator and the champion as extra `cuts`.
- **proposal:** pick three or four win themes, state each once, prove each in its scene. Show named people.
  Check what the RFP allows before attaching a film. Offer a small paid first step only if the brief states one; never invent a price.
- **status-update:** keep the order the same every week. Keep information and asks in different scenes. Show the real tracker, not slides.
- **kickoff:** name an owner for each deliverable. End by recording the baseline the value review will use.
- **final-readout:** recommendation first, then the findings that support it. Do not hold the answer back.
- **value-review:** show before and after against that baseline. Cut a short result clip for the next pitch.
- RAID or RACI, Shipley themes and sales asks belong only to the profile that names them. Do not add them elsewhere.

Production policy is unchanged: captions are chosen per export (sidecar `.srt` in the delivered library),
voice and video providers follow the governed routing, and local AI stays off.
