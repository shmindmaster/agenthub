---
name: plan
description: Turns an approved brief into a beat-by-beat storyboard with a picture for every line, then runs production with gates first and a fresh reviewer. Use when a brief is approved and before narration or render. Not for a one-step fix; use compose.
---

# Plan

## Workflow contract

1. Use the approved brief and locked story, or the approved brief for a job without a separate screenplay.
2. Map each line to a picture, price eligible lanes, run picture gates and record approval before spending.
3. Hand `capture`, `visuals` and `generate` the approved storyboard, picture plan, breakdown and work list.
4. If a required asset depends on a frozen lane or the plan fails, resolve the blocker before releasing tasks.

An approved brief becomes a storyboard where every beat has a line AND a picture, then a short list of tasks that fresh agents can build and check one at a time.

<HARD-GATE>
No voice generation, image generation, capture or render until the storyboard passes `check_picture_relevance.py` and `check_visual_variety.py` and the owner has seen the picture table. Paying for audio or images against a picture that is words in boxes wastes money twice.
</HARD-GATE>

## Step 2: picture plan, breakdown and gates before spend

Write the table as `story/picture-plan.json`: one scene per screenplay scene, each with a `visual` from the kit (`../visuals/references/kit-visuals.md`). Pin a reveal to a spoken word with an anchor in any `at` field: `"at": "@Penske"`, `"@trucks#1"` (second occurrence), `"@November+0.3"`. No hand-written script is needed: `build-picture.mjs` resolves the anchors from the voice clock after the takes exist.

Then, with no voice or image spend yet:

```text
py -3 scripts/check_script_terms.py story/locked-script.txt                                   # names and acronyms pinned
py -3 scripts/check_picture_relevance.py story/picture-plan.json story/screenplay.json --out qa/picture-relevance.json
py -3 scripts/check_visual_variety.py story/picture-plan.json --out qa/visual-variety.json    # not words in boxes
py -3 scripts/screenplay_breakdown.py <jobRoot>                                               # cast, assets, budget, schedule
```

`screenplay_breakdown.py` writes `plan/breakdown.json`: the cast, the assets that must exist, the priced budget (speech from the documented Azure rates, stills counted and unpriced until quoted) and the build order. It fails on a scene with no picture or a picture that needs a frozen lane. Show the owner the picture table and the budget; on a yes, `production_status.py <jobRoot> --approve plan`.

A failing gate goes back to the table, never to the threshold.

## Deliver

`compose` delivers. A film that has not been viewed as frames is not filed as final.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
