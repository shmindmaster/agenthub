---
name: studio
description: Produces a whole film or audio piece from an idea, through development, pre-production, production, post and delivery, with a deliverable and gate at each phase. Use when someone brings an idea, topic or rough ask and wants the finished piece. Not for one step of a running job.
---

# Studio

## Workflow contract

1. Use the media request and the job root if one exists.
2. Read the job status first, reuse passed artifacts, and resume at the earliest missing or invalid stage.
3. Return the final candidate and review verdict, or the last completed stage and exact next input.
4. If approval or a dependency is missing, preserve accepted assets and stop at that stage.

One idea in, one finished film out. This skill is the conductor: it runs the filmmaking phases in order, makes each produce a file, checks the file, and stops at the owner's approvals. It calls the other skills for the craft.

## Rules

<HARD-GATE>
No phase starts until the one before it shows PASS in `production_status.py`. An approval is recorded with `production_status.py <jobRoot> --approve <name>` only after the owner has said yes to that thing in this conversation. A yes to a different film or an earlier draft does not count.
</HARD-GATE>

- **Decide, do not menu.** The owner gave an idea, not a questionnaire. Infer kind, form, voices and picture; ask one question only for what a file cannot answer, and prefer a choice with a recommendation.
- **Picture first.** Every scene has what the viewer sees before it has a voice. Words in boxes fail `check_visual_variety.py`.
- **Cheapest lane that passes.** Use `route_media.py` and the voice recipes in `generate/references/voice-recipes.md`. Pick the cheapest authorized lane that passes QA. Choose DragonHD Emma2 or Andrew2 for a new walkthrough and Ava as fallback. Use Deepgram Haley batch synthesis for prepared support prompts. Show the budget in `breakdown.json` before any paid step.
- **Know every capability.** Run `route_media.py --catalog` before planning pictures: it lists every lane, scripted or by hand, with its mode (script, api, connector, browser), cost and how to run it. A browser lane (IrukaDark clips, Manus) is as legitimate as a scripted one: drive the owner's signed-in Chrome, never enter credentials or card details, ask before each download, judge the file before accepting it.
- **Gates before spend, frames before claims.** Run the free offline gates before voice or image spend; look at the frames before anything is called good.
- **Subagents with a ledger.** Independent parts (voice takes, assets) run in parallel, up to five at once; each task names its model; a fresh reviewer checks each deliverable; `plan/ledger.md` records task, agent, model, result and evidence.
- **Resumable.** Everything lives in the workspace. A new session reads `production_status.py`, not the conversation.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
