# Workflow detail

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll fix the picture after the voice is done." | The voice is timed to the picture plan. Fix it first. |
| "The picture check flagged this sequence." | Compare the observation with the brief. Revise a picture that misses the brief or is unreadable; keep intentional slides, stills and silence. |
| "The render succeeded." | A render proves nothing. Look at the frames. |
| "I'll check it myself, no reviewer needed." | The author is the worst reviewer. Use a fresh one. |

## Step 3: task list

Write the plan as tasks, each small enough that a fresh agent can do it from the text alone:

```text
- [ ] T1 pronunciation lexicon decisions
- [ ] T2 voice lines and receipts
- [ ] T3 assets (per source: svg, lottie, stills, capture)
- [ ] T4 `build-picture.mjs <jobRoot>` then render
- [ ] T5 finish media and gates on the exact file
- [ ] T6 review
```

Each task states: files it touches, the command that proves it, the model to use, and what done means. Keep a ledger in `plan/ledger.md`: task, agent, model, result, evidence.

## Step 4: run it

- A fresh agent per task, naming its model: a cheaper model for scripts and evidence gathering, the strongest for verdicts and the full watch. Never run two writers on the same files.
- After each task a reviewer reads the evidence and gives two verdicts in order: **picture** (is it about the line, does it show something) then **craft** (spacing, legibility, motion). A failing task is fixed and rechecked, up to five rounds, then escalated to the owner.
- Last, one reviewer watches the whole encoded file against the brief, using `review`.

## Step 5: check the output

Nothing is "done", "ready" or "fixed" until the command ran in this task and its output is in the ledger. Look at frames: build the contact sheet and view it. Name every check not performed.


## Step 1: storyboard table

One row per beat, written into `plan/storyboard.md`:

| Beat | Line (locked words) | On screen | Visual kind | Source | Reveal timing | Cost |
| --- | --- | --- | --- | --- | --- | --- |
| s4 | Penske declined four 26-foot trucks. | Truck box, crossed out arrow, four trucks | `svg` | hand-drawn | each part on its word | none |

Rules for the table:

- **On screen** describes what appears, including any words the viewer should read. Avoid restating the spoken sentence unless the format calls for reading along.
- **Visual kind** comes from the ladder in `../../produce/references/ladder.md`. Prefer a picture kind: chart, svg, lottie, flow, layers, sequence, timeline, beforeafter, map, still, broll, screen-in-context, code. Use text cards for lessons, exercises, titles, quotes and other moments that call for reading.
- **Source** is the lane from `scripts/route_media.py`: kit, lottie, hand-drawn svg, captured screen, Azure image. Anything paid is priced here.
- **Reveal timing** pins each part to the spoken word that names it (`at`, seconds from scene start, taken from the word boundaries).
- Time picture changes and holds to the delivery. Give the viewer enough time to read, think or solve the exercise.
