---
name: plan
description: Turns an approved brief into a beat-by-beat storyboard with a picture for every line, then runs production with gates first and a fresh reviewer. Use when a brief is approved and before narration or render. Not for a one-step fix; use compose.
---

# Plan

An approved brief becomes a storyboard where every beat has a line AND a picture, then a short list of tasks that fresh agents can build and check one at a time.

<HARD-GATE>
No voice generation, image generation, capture or render until the storyboard passes `check_picture_relevance.py` and `check_visual_variety.py` and the owner has seen the picture table. Paying for audio or images against a picture that is words in boxes wastes money twice.
</HARD-GATE>

## Step 1: storyboard table

One row per beat, written into `plan/storyboard.md`:

| Beat | Line (locked words) | On screen | Visual kind | Source | Reveal timing | Cost |
| --- | --- | --- | --- | --- | --- | --- |
| s4 | Penske declined four 26-foot trucks. | Truck box, crossed out arrow, four trucks | `svg` | hand-drawn | each part on its word | none |

Rules for the table:

- **On screen** is nouns and shapes, not the sentence again. If the cell could be the line, the beat has no picture.
- **Visual kind** comes from the ladder in `../visuals/references/ladder.md`. Prefer a picture kind: chart, svg, lottie, flow, layers, sequence, timeline, beforeafter, map, still, broll, screen-in-context, code. A text card needs a reason (opening, close, a quoted line).
- **Source** is the lane from `scripts/route_media.py`: kit, lottie, hand-drawn svg, captured screen, Azure image. Anything paid is priced here.
- **Reveal timing** pins each part to the spoken word that names it (`at`, seconds from scene start, taken from the word boundaries).
- The visual changes with every sentence; no scene holds one picture for more than about eight seconds.

## Step 2: gates before spend

Build `briefing-props.json` from the table and run, in order:

```text
py -3 scripts/check_script_terms.py <script>                      # names and acronyms pinned
py -3 scripts/check_picture_relevance.py <props> <cue-sheet>      # picture comes from the line
py -3 scripts/check_visual_variety.py <props>                     # not words in boxes
```

A failing gate goes back to the table, never to the threshold.

## Step 3: task list

Write the plan as tasks, each small enough that a fresh agent can do it from the text alone:

```text
- [ ] T1 pronunciation lexicon decisions
- [ ] T2 voice lines and receipts
- [ ] T3 assets (per source: svg, lottie, stills, capture)
- [ ] T4 props and render
- [ ] T5 finish media and gates on the exact file
- [ ] T6 review
```

Each task states: files it touches, the command that proves it, the model to use, and what done means. Keep a ledger in `plan/ledger.md`: task, agent, model, result, evidence.

## Step 4: run it

- A fresh agent per task, naming its model: a cheaper model for scripts and evidence gathering, the strongest for verdicts and the full watch. Never run two writers on the same files.
- After each task a reviewer reads the evidence and gives two verdicts in order: **picture** (is it about the line, does it show something) then **craft** (spacing, legibility, motion). A failing task is fixed and rechecked, up to five rounds, then escalated to the owner.
- Last, one reviewer watches the whole encoded file against the brief, using `review`.

## Step 5: evidence before claims

Nothing is "done", "ready" or "fixed" until the command ran in this task and its output is in the ledger. Look at frames: build the contact sheet and view it. Name every check not performed.

## Deliver

`compose` delivers. A film that has not been viewed as frames is not filed as final.

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll fix the picture after the voice is done." | The voice is timed to the picture plan. Fix it first. |
| "The gate threshold is too strict." | It is catching the exact failure the gate exists for. Change the storyboard. |
| "The render succeeded." | A render proves nothing. Look at the frames. |
| "I'll check it myself, no reviewer needed." | The author is the worst reviewer. Use a fresh one. |
