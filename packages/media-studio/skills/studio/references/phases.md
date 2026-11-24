# Phases

Read this when deciding how much of each phase a piece needs. The phases follow how films are made: development, pre-production, production, post-production, distribution. Every phase always runs; for a short piece it is light, never skipped, because the file it produces is what the next phase reads.

## 1 Develop (idea to script)

Concept refinement, the screenplay, and the package that lets it move forward.

- **Concept:** is the idea clear, does the audience want it, does its opening suit the form? Written as the case (`case/case.md`): audience, promise, logline, stakes, tone, facts, names, constraints, success check.
- **Story:** the treatment and beat sheet decide what happens and in what order, with the picture for each beat.
- **Screenplay:** the locked lines, one scene per beat or turn, written for the ear (`skills/studio/references/story.md`).
- **Package:** record the case and beat sheet and resolve any reserved review.

Light for a 60-second explainer: the case is half a page, the treatment 100 words, three to five beats.

## 2 Pre-production (plan and design)

Script breakdown, budget, schedule, casting, visual planning, locations and permits.

- **Breakdown:** every scene's speaker, words, seconds, picture kind and lane (`screenplay_breakdown.py`).
- **Budget and schedule:** priced speech, counted stills, a build order with the parallel steps and their limit.
- **Casting:** one distinct voice per speaker; names pinned before synthesis (`check_script_terms.py`, `pronunciation_lexicon.json`).
- **Visual planning:** the picture plan, storyboard, visual bible and shot list. Each scene says what is on screen and which words trigger each part (`at` anchors).
- **Locations:** the look. A colour and type system, the motif, the diagram language; for a product film, the synthetic workspace and a clean profile.
- **Permits and rights:** sources, licences, likeness, the Remotion licence for the organisation, and the data class. No real customer data.

## 3 Production (make the parts)

The camera rolls: here, voice takes, drawn and generated assets, and captures. Take only what the plan lists; an extra asset is a plan change.

## 4 Post (assemble and check)

Picture edit, sound mix, visual effects, review. Render, mux, finish loudness, run the gates on the exact file, and look at the frames. The review verdict decides whether it ships.

## 5 Delivery

Write the caption sidecar and place the candidate in the authorized internal library after QA. Complete reserved delivery review when applicable. Get separate external publication approval.

## By kind

| Kind | Develop | Picture | Voice | Notes |
| --- | --- | --- | --- | --- |
| explainer, briefing, training | case, 3 to 8 beats | drawn: svg, chart, flow, layers, lottie | one narrator | the default studio path |
| documentary, series episode | longer treatment, act structure | mix of drawn, stills, captures | narrator plus interview-style voices | more beats, a hero moment |
| simulated call, dialogue | scene per turn, speaker in the kicker | the discussed thing, not the speakers | one voice per character | `scenes.md` dialogue section |
| product screencast | readiness check first | captured and finished with Recast | narrator | `product-picture.md`; never a drawn stand-in for the product |
| animation, teaser | short, punchy beats | motion, Lottie, generated or source footage as appropriate | optional | frozen video lanes need owner approval |
| audio only | same case and screenplay | none | the whole thing | skip the picture gates |

## By deliverable

`job.json` may declare `deliverable`. Undeclared: `audio` for kind audio-only, otherwise `narrated-video`. A form requires only what it produces; a phase with nothing applicable is `NOT_REQUIRED` and counts as complete. `production_status.py --json` reports `deliverable` and each phase's `notRequired` list. An unknown value, or audio-only with a picture form, fails develop.

| Deliverable | Required | Not required |
| --- | --- | --- |
| `narrated-video` | everything above | none |
| `silent-video` | picture plan, relevance and variety reports, picture video, finished `.mp4`, frame integrity; scenes with an `action` or `picture` and no narration | narration text, narration check, voice takes, cue sheet, word sync, captions sidecar |
| `audio` | narration, narration check, voice takes, finished `.wav`, `.mp3` or `.m4a` | picture plan, relevance, variety, picture video, cue sheet, word sync, frame integrity, captions sidecar |
| `stills` | picture plan and its gates, finished `.png`, `.jpg`, `.pdf` or `.pptx` | narration, voice takes, video, word sync, frame integrity, story experience review (a viewer-facing still has no film to watch or hear; it is listed in post's `notRequired`), captions sidecar; the production phase |
| `storyboard` | develop and pre-production, including `story/storyboard.json` | production, post and delivery phases |

`validate-narration.mjs` stops with "no narration lines" on a screenplay with none, so the narration check is not required for `silent-video`, `stills` and `storyboard`. `screenplay_breakdown.py` runs on scenes without narration (zero seconds), so `plan/breakdown.json` stays required for every form.

A `NOT_REQUIRED` phase still fails when an owner review named in `requiredReviews` (case, screenplay, plan, delivered) is not recorded. Without `reviewAuthority: "delegated"` the `delivered` approval is asked for even where delivery has nothing to produce, so a storyboard completes without it only under delegated authority and no reservation.

`production.json` may set `finishedFile` (a path inside `out/`) to pin which file is the finished one; otherwise the newest file of the form's type is used, and a path outside `out/` fails post.

With `story/requirements.json` (written from the brief, see the script skill's brief) the check runs in this order:

1. **Develop:** needs a passing `qa/requirements-check.json` whose recorded input hashes (requirements, job, screenplay, capture plan) still match. The picture plan is not part of this freshness. While `story/picture-plan.json` is missing or still a placeholder, requirements with `evidence` picture or both are listed as `unverified`, not errors. Deleting `requirements.json` after a check was written fails develop.
2. **Preproduction:** needs that check re-run so its recorded inputs include the current picture plan, and the picture evidence is then really matched.
3. **Post:** needs the check run with `--candidate` on the current finished file, and, except for `stills`, a passing `qa/finished-film.json` for that sha256 whose `deliverable` is this job's form and whose `requirementsSha256` is the current `requirements.json`. `stills` need only the candidate run (png or jpg aspect is measured; a pdf or pptx aspect needs a passing `framing` item in `qa/requirements-review.json`).
