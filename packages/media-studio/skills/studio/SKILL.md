---
name: studio
description: Produces a whole film or audio piece from an idea, through development, pre-production, production, post and delivery, with a deliverable and gate at each phase. Use when someone brings an idea, topic or rough ask and wants the finished piece. Not for one step of a running job.
---

# Studio

One idea in, one finished film out. This skill is the conductor: it runs the filmmaking phases in order, makes each produce a file, checks the file, and stops at the owner's approvals. It calls the other skills for the craft.

## Start

```text
py -3 scripts/studio_init.py "<working title>" --kind <briefing|explainer|training|documentary|animation|teaser|...> --identity <mahumtech|abacare>
py -3 scripts/production_status.py <jobRoot>        # where it stands and what to do next, at any time
```

`production_status.py` is the memory of the job. Run it first in every session that touches a production, and after every step. It names the phase, the failing check and the next skill. Never claim a phase is done that it does not show as PASS.

## The phases

| Phase | Deliverables | Skill | Owner approves |
| --- | --- | --- | --- |
| 1 Develop: idea to script | `case/case.md`, `story/treatment.md`, `story/beat-sheet.json`, `story/screenplay.json`, narration check | `brief`, `develop` | the case, then the screenplay |
| 2 Pre-production: plan and design | `story/picture-plan.json`, `story/storyboard.json`, `story/visual-bible.json`, `plan/breakdown.json` (cast, assets, budget, schedule), relevance and variety gates | `plan`, `visuals` | the plan: picture table and cost |
| 3 Production: make the parts | voice takes, assets (drawn, generated, captured), cue sheet, built props, rendered picture | `generate`, `visuals`, `capture`, `compose` | none, unless spend rises |
| 4 Post: assemble and check | finished file, loudness, word sync, frame integrity, the review verdict | `compose`, `review` | none |
| 5 Delivery | captions sidecar, library copy, delivered record | `compose` | delivery |

Read `references/phases.md` for what each phase means for each kind of piece, and how light a phase can be.

## Rules

<HARD-GATE>
No phase starts until the one before it shows PASS in `production_status.py`. An approval is recorded with `production_status.py <jobRoot> --approve <name>` only after the owner has said yes to that thing in this conversation. A yes to a different film or an earlier draft does not count.
</HARD-GATE>

- **Decide, do not menu.** The owner gave an idea, not a questionnaire. Infer kind, form, voices and picture; ask one question only for what a file cannot answer, and prefer a choice with a recommendation.
- **Picture first.** Every scene has what the viewer sees before it has a voice. Words in boxes fail `check_visual_variety.py`.
- **Cheapest lane that passes.** `route_media.py` names the funded lane per need; free lanes first for pictures; voice has no free lane and a desktop voice is never a substitute; frozen lanes stay frozen; the budget in `breakdown.json` is shown before any paid step.
- **Know every capability.** Run `route_media.py --catalog` before planning pictures: it lists every lane, scripted or by hand, with its mode (script, api, connector, browser), cost and how to run it. A browser lane (IrukaDark clips, Manus) is as legitimate as a scripted one: drive the owner's signed-in Chrome, never enter credentials or card details, ask before each download, judge the file before accepting it.
- **Gates before spend, frames before claims.** Run the free offline gates before voice or image spend; look at the frames before anything is called good.
- **Subagents with a ledger.** Independent parts (voice takes, assets) run in parallel, up to five at once; each task names its model; a fresh reviewer checks each deliverable; `plan/ledger.md` records task, agent, model, result and evidence.
- **Resumable.** Everything lives in the workspace. A new session reads `production_status.py`, not the conversation.

## Pace

Do the free phases fast and in one go: develop and pre-production need no spend. Pause for the two approvals (screenplay, plan), then run production and post without stopping unless a gate fails or spend would exceed the plan. Report at the end with the file, the gates that ran, the gates that did not, and the cost against the estimate.

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll write the script and fix the picture later." | The picture shapes the script. Beat sheet first, with a picture per beat. |
| "The status tool is bureaucracy." | It is the only thing that tells the next session what is true. |
| "They said 'sounds good' earlier, I'll approve." | Approval is for the exact thing, in this conversation, recorded by the command. |
| "A text card is quicker." | Quick and empty is the failure this studio exists to prevent. |
