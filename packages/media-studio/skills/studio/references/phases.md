# Phases

Read this when deciding how much of each phase a piece needs. The phases follow how films are made: development, pre-production, production, post-production, distribution. Every phase always runs; for a short piece it is light, never skipped, because the file it produces is what the next phase reads.

## 1 Develop (idea to script)

Concept refinement, the screenplay, and the package that lets it move forward.

- **Concept:** is the idea clear, does the audience want it, is there a hook? Written as the case (`case/case.md`): audience, promise, logline, stakes, tone, facts, names, constraints, success check.
- **Story:** the treatment and beat sheet decide what happens and in what order, with the picture for each beat.
- **Screenplay:** the locked lines, one scene per beat or turn, written for the ear (`skills/video/references/story.md`).
- **Package:** the case and beat sheet are what the owner approves, the way a pitch package is.

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

Captions as a sidecar, the library copy in the right folder, and the owner's recorded yes.

## By kind

| Kind | Develop | Picture | Voice | Notes |
| --- | --- | --- | --- | --- |
| explainer, briefing, training | case, 3 to 8 beats | drawn: svg, chart, flow, layers, lottie | one narrator | the default studio path |
| documentary, series episode | longer treatment, act structure | mix of drawn, stills, captures | narrator plus interview-style voices | more beats, a hero moment |
| simulated call, dialogue | scene per turn, speaker in the kicker | the discussed thing, not the speakers | one voice per character | `scenes.md` dialogue section |
| product screencast | readiness check first | captured and finished with Recast | narrator | `product-picture.md`; never a drawn stand-in for the product |
| animation, teaser | short, punchy beats | motion, lottie, hero generative shots only if approved | optional | frozen video lanes need owner approval |
| audio only | same case and screenplay | none | the whole thing | skip the picture gates |
