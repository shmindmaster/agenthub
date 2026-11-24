# Brief

## Workflow contract

1. Use the requested audience, intended outcome and available source material.
2. Resolve the picture approach and eligible lanes, and record the internal review authority.
3. Hand `develop` the internally accepted case or brief, after any reserved review.
4. Pause downstream work for an outstanding required review. Carry a complete delegated brief directly into development.

Turn a rough ask into a short written brief. Reuse a complete brief and use the requested form to plan what the film shows and sounds like.

<HARD-GATE>
Record the brief before scripting. Honor delegated authority and any review reserved for this film. Before paid generation, verify the provider lane, cost and separate spend authorization. Before external publication, obtain separate approval for the candidate and destination.
</HARD-GATE>

## Next

In a whole-film job the brief is `case/case.md` (the `studio` skill scaffolds it with `studio_init.py`); write it there and record an explicitly required owner's yes with `production_status.py <jobRoot> --approve case`. Then `develop` for the story and screenplay, and `plan`.

Read when executing this skill for its detailed commands and gates. [Workflow detail](brief-detail.md)

For consulting communication, load [consulting communication](../../studio/references/consulting-communication.md). Extend the existing brief with the decision, primary takeaway, problem status and sources, next step (unagreed date null), duration ceiling, caption policy and audio direction before any reserved review.

## Requirements

Write `story/requirements.json` from the brief before the screenplay (`studio_init.py --requirements` scaffolds it; schema `schemas/requirements.schema.json`). One line per item, each mapped to the scene ids that deliver it:

| Item | Field |
| --- | --- |
| every feature or state the brief asked to see or hear | `requirements[]` with `scenes`, `match` terms and `evidence` (narration, picture or both) |
| spoken and on-screen language, independent of each other | `narrationLanguage`, `uiLanguage` (BCP-47 or `none`) |
| call to action | `cta` with `required`, `text`, `scene` |
| length | `durationSeconds` min and max |
| framing | `aspect` (`16x9`, `9x16`, `4x5`, `1x1`) |
| how long the last picture holds | `finalHoldSeconds` |

A requirement that no script can check (a purely visual state) is left without `match`. Watch the finished file, then record `qa/requirements-review.json`: `{"schema": "media-studio/requirements-review/1", "candidateSha256", "reviewer", "items": [{"id", "verdict": "pass" or "fail", "at": "mm:ss", "note"}]}`. With `--candidate`, each requirement without `match` needs a passing item for that exact sha256, with `at` inside the film. A fail is an error, a missing item stays `unverified`, and a review of another file is rejected as stale. The same item mechanism clears a claim nothing else measures: `narrationLanguage` or `uiLanguage` that no job, screenplay or capture-plan field declares, and a required `cta` that names a scene but no text (item ids `narrationLanguage`, `uiLanguage`, `cta`).

Matching is NFC and case-insensitive on whole words. `evidence` picture reads only text-bearing plan fields (title, kicker, caption, label, text, action and similar), never ids, kinds or paths. Run `check_requirements.py <jobRoot>` once the screenplay is written: until the picture plan exists, picture evidence is `unverified`, not an error. Run it again after the picture plan, because preproduction needs a check that includes the current plan; finally run it with `--candidate out/<file>` on the finished file. Anything it cannot measure is listed as `unverified`, never as a pass.
