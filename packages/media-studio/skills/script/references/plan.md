# Plan

## Workflow contract

1. Use the approved brief and locked story, or the approved brief for a job without a separate screenplay.
2. Map each line to a picture, price eligible lanes, run picture gates and record approval before spending.
3. Hand `capture`, `visuals` and `generate` the approved storyboard, picture plan, breakdown and work list.
4. If a required asset depends on a frozen lane or the plan fails, resolve the blocker before releasing tasks.

An approved brief becomes a storyboard with a useful picture or
intentional visual/sound moment per beat, then a short list of production
tasks. For `creativeMode` fiction, vision, concept, hybrid, documentary,
educational or abstract, use the flexible storyboard schema at
`schemas/creative-storyboard.schema.json` and preserve full creative
freedom for synthetic people, scenarios, imaginary interfaces and
non-linear stories. A verified product demo continues to use the
capture/result storyboard and real-product evidence. Voice-only or
silent visual scenes need not invent narration to fill fields.

<HARD-GATE>
Before production, record the picture plan and run its checks. Keep the owner approval and spend controls. Use strict diagnostics when the approved treatment requires the briefing picture mix. For slide-led lessons, interviews, stills, silent beats and other deliberate forms, run both checks with `--advisory` and evaluate their notes against the brief.
</HARD-GATE>

## Step 2: picture plan, breakdown and gates before spend

Write the table as `story/picture-plan.json`: one scene per screenplay scene, each with a `visual` from the kit (`../visuals/references/kit-visuals.md`). Pin a reveal to a spoken word with an anchor in any `at` field: `"at": "@Penske"`, `"@trucks#1"` (second occurrence), `"@November+0.3"`. No hand-written script is needed: `build-picture.mjs` resolves the anchors from the voice clock after the takes exist.

Use the [narration-led explainer workflow](../../produce/references/explainer-shots.md) when animation advances the requested format. A narrated slide, direct demonstration, still or cut can be the right choice for a specific beat. Record `sourceAssetId` on the visual when several crops share an original, and `reuseReason` on an intentional return to footage. The variety check reports any repeated source without a reason.

Then, with no voice or image spend yet:

```text
py -3 scripts/check_script_terms.py story/locked-script.txt                                   # names and acronyms pinned
py -3 scripts/check_picture_relevance.py story/picture-plan.json story/screenplay.json --out qa/picture-relevance.json
py -3 scripts/check_visual_variety.py story/picture-plan.json --out qa/visual-variety.json    # add --advisory for an intentionally different visual treatment
py -3 scripts/screenplay_breakdown.py <jobRoot>                                               # cast, assets, budget, schedule
```

`screenplay_breakdown.py` writes `plan/breakdown.json`: the cast, the assets that must exist, the priced budget (speech from the documented Azure rates, stills counted and unpriced until quoted) and the build order. It fails on a scene with no picture or a picture that needs a frozen lane. Show the owner the picture table and the budget; on a yes, `production_status.py <jobRoot> --approve plan`.

Fix findings that conflict with the approved brief. Treat deliberate choices as part of the visual treatment.

## Deliver

`compose` delivers. A film that has not been viewed as frames is not filed as final.

Read when executing this skill for its detailed commands and gates. [Workflow detail](plan-detail.md)

For consulting profiles, load [consulting communication](../../studio/references/consulting-communication.md). Carry the decision brief, actionTitle, claim scope and proofRefs through the picture plan. Pink reviews titles alone and the claim-to-scene map; calculate scene totals against the approved ceiling before voice generation.
