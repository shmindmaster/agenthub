---
name: brief
description: Turns a rough ask for video, audio, an explainer or a graphic into an approved written brief, with what the viewer will see, before any script or spend. Use when someone wants media and the ask is short or loose. Not once a brief is approved; use plan.
---

# Brief

## Workflow contract

1. Use the requested audience, intended outcome and available source material.
2. Resolve the planned screen and eligible lanes, then seek approval on the exact brief before downstream work.
3. Hand `develop` the approved case or brief and its recorded approval.
4. If approval is absent, leave the brief in draft and pause downstream work.

A rough ask is the normal case. Your job is to turn it into a short written brief the owner has agreed to, and to know what the film will SHOW, before a word is scripted or a cent is spent.

<HARD-GATE>
Do not write narration, call a voice or image provider, capture, or render until `brief.md` exists in the job folder and the owner has said yes to it in this task. A previous approval for another film does not carry over. The only exception is a scratch draft the owner asked for by name, and it still gets a brief of three lines.
</HARD-GATE>

## Next

In a whole-film job the brief is `case/case.md` (the `studio` skill scaffolds it with `studio_init.py`); write it there and record the owner's yes with `production_status.py <jobRoot> --approve case`. Then `develop` for the story and screenplay, and `plan`.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
