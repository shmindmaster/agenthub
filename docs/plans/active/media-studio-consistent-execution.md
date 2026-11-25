# Media Studio: consistent execution

Linear: CORE-82 (this plan), with CORE-33, CORE-84, CORE-10 and CORE-16 as neighbours. Written 2026-11-24 against `cdaeda0a`.

An outside architecture review proposed a larger refactor. Each claim was checked against source, a fresh-session measurement, vendor pages, and a visual survey of 25 delivered films (12 frames each; audio not listened to). This page records what survived, what changed, and what was dropped.

## What the check found

| Claim in the review | Verdict | Consequence |
|---|---|---|
| Preferred voice providers are not connected to the `mvg` driver | True. The schema accepts `elevenlabs`, `openai`, `local`. | One `import` adapter for audio any governed script produced |
| A skipped required shot completes the film | Overstated. The assets stage records done, then compose throws with a misleading hint. | Fail at lint, before paid stages |
| Provider spend is accounted correctly | Missed by the review. Every provider except ElevenLabs is charged against the OpenAI cap. | Provider table in the ledger; fixed first |
| Routes point at retired skills | True. About 20 agent-facing references in Media Studio, plus global policy and registries. | Fixed, with a link guard test |
| Skill descriptions are suppressed | Measured. At 0.005, `script` and `finish` list by name only; at 0.01 all four keep descriptions. About 6K tokens per session. | Vendor default restored |
| Validators assume narrated video | True for `production_status.py`; CORE-91 and CORE-92 had already fixed several others. | One optional `deliverable` field |
| Nothing maps requirements to scenes | True | `story/requirements.json` and a gate |
| A CTA end card is forced | True in schema, compose and the composition | Optional; a closing card instead |
| Clerk installer targets retired hosts | True (`warp`, `mimo-code`) | Reads the registry |
| Build new on OpenAI Flex | Review is right to avoid it: the beta is winding down. Azure Flex still lists the models policy uses, as a preview. | No change here |

## What the films showed

The review did not look at output. Ranked by how many of 25 films showed it:

| Defect | Films | Where it is now caught |
|---|---:|---|
| Ends on an undesigned page, no outcome | 14 | Finished-film gate (hold, trailing silence); closing card; treatments |
| Black, blank or static first three seconds | 13 | Finished-film gate; frame-0 rule in the composition |
| UI or terminal text clipped at an edge | 10 | Human review checklist (not measured) |
| UI too small at delivered size | 6 | Human review checklist (not measured) |
| Loading or blank page left in | 4 | Finished-film gate: blank is an error, possible loading an advisory |
| Audio silent 3-16 s mid-film | several | Finished-film gate, with a reviewed-silence list |
| Vertical cut is a blurred or cropped 16:9 | 1 of 1 | Advisory plus the vertical rule in treatments |

Two screencast treatments cover most product clips, so variety is a treatment-selection problem before it is a renderer problem.

## Decisions

- Keep Remotion and the existing driver. No new job system and no module split: the contracts below give the same guarantees with less movement.
- Adapt timing ideas from Video Shotcraft (Apache-2.0) in our own words. No code or media copied.
- Explainroo (MIT) is a candidate for a bounded trial only. It accepts recorded narration, but its default voice and timing are local models, so a trial runs remotely with imported audio after this work lands.
- OpenMontage (AGPL-3.0) and Anything2Explainer (PolyForm Noncommercial) are not adopted.
- Native AssemblyAI synthesis is not called from a stage: its quote and authorization step is a human gate, and `import` keeps it.
- Generated video shots stay out. Compose takes still images for b-roll, and no governed video wrapper exists (CORE-10).
- `packages/product` is owned by another session on this date and is untouched.

## Contracts added

1. **Ledger:** one unit and cap per provider; unknown provider refuses; uncapped new providers refuse spend.
2. **`voice.provider: import` and `broll.provider: import`:** hash-bound files with the receipt of whichever governed script made them.
3. **`deliverable`** in `job.json`: `narrated-video`, `silent-video`, `audio`, `stills`, `storyboard`. An undeclared job is `narrated-video` with the checks it had before, except `kind: audio-only`, which is now judged as `audio`: it could never pass checks that demand a picture and an MP4.
4. **`story/requirements.json`:** features, language states, CTA, duration, framing and final hold, each mapped to scenes. Unmeasured items are `unverified`, never a pass. Opt-in by file presence.
5. **`qa/finished-film.json`:** opening, ending, silence and blank checks on the exact encoded file.

## Not yet proven

A real production through the new contracts, with the encoded file watched and heard. That is CORE-33's pilot. Text clipping and text size stay human checks.
