---
name: brief
description: Turns a rough ask for video, audio, an explainer or a graphic into an approved written brief, with what the viewer will see, before any script or spend. Use when someone wants media and the ask is short or loose. Not once a brief is approved; use plan.
---

# Brief

A rough ask is the normal case. Your job is to turn it into a short written brief the owner has agreed to, and to know what the film will SHOW, before a word is scripted or a cent is spent.

<HARD-GATE>
Do not write narration, call a voice or image provider, capture, or render until `brief.md` exists in the job folder and the owner has said yes to it in this task. A previous approval for another film does not carry over. The only exception is a scratch draft the owner asked for by name, and it still gets a brief of three lines.
</HARD-GATE>

## Why this exists

Films shipped as words presented well: clean cards, correct facts, nothing to look at. The cause was that the first question was "what will it say" and nobody asked "what will the viewer see". Every step below puts the picture next to the line.

## Workflow

```text
- [ ] 1. Triage: what is it, who watches, where does it go, how long
- [ ] 2. Look before asking: sources, past jobs, library, registry/product-video-delivery.json
- [ ] 3. Echo the ask back in about 200 words, including what the viewer will see
- [ ] 4. Ask one question at a time, only what you cannot find out
- [ ] 5. Offer two or three approaches with a recommendation (form, picture style, cost)
- [ ] 6. Write brief.md, get a yes
- [ ] 7. Hand to plan
```

**1. Triage.** Infer kind, `programForm`, audience, voice and destination from the ask (`../video/references/forms.md`). A running product is `product-screencast`. Say what you inferred in one line; do not make the owner name skills or steps.

**2. Look before asking.** Read the source material, the job folder, the library index, and the delivery registry first. Retrieve from documents with `ah-sarosh:search-docs` when the ask refers to past work. Never ask a question a file can answer.

**3. Echo.** Restate the ask as: who it is for, the one promise, the shape (length, voices, form), and what is on screen for the main beats. If the echo is wrong, the owner corrects it in one line.

**4. One question at a time.** Prefer a choice over an open question. Ask only what changes the work: unknown destination for a product absent from the registry, missing source, a name you cannot pronounce. Never ask about tooling.

**5. Approaches.** Give two or three real options and say which you recommend and why. Always include the picture decision, for example:

- Recommended: drawn explainer. Hand-drawn SVG and charts in the Remotion kit, one picture per sentence. No paid media.
- Richer: add generated stills for two or three scenes through Azure images. Small spend, shown before the run.
- Heavy: add generative video hero shots. Frozen until you approve spend.

Run `py -3 scripts/route_media.py <need> --identity <mahumtech|abacare>` for each need so the options match what is funded and allowed today. A frozen lane is not offered as an option; name it and say what unfreezes it.

**6. Write `brief.md`.** Short, and checkable:

```markdown
# Brief: <working title>
Audience / where it plays:
One promise:
Form, length, voices:
Facts locked (source for each):
Names to pronounce (go to pronunciation_lexicon.json):
Picture plan, one line per beat or section: what is ON SCREEN, not what is said
Lanes and cost: from route_media.py, with price basis
Out of scope:
Success check: what the owner will see in the first five seconds and at the end
```

Self-review before showing it: no placeholder, no beat with only a title for a picture, no unpriced paid step, every name listed. Fix inline, then ask for the yes.

## Red flags

| Thought | Reality |
| --- | --- |
| "The ask is clear enough, I'll script it." | Clear words are not a clear picture. Write the picture plan first. |
| "A title card is fine for this beat." | A title is a label. Say what the viewer sees that the line is about. |
| "I'll ask the owner about the tools." | Tool choice is yours. Ask only about the film. |
| "They approved a similar film." | Approval is per film. |
| "Draft means skip the picture work." | A draft skips the render only. |

## Next

In a whole-film job the brief is `case/case.md` (the `studio` skill scaffolds it with `studio_init.py`); write it there and record the owner's yes with `production_status.py <jobRoot> --approve case`. Then `develop` for the story and screenplay, and `plan`.
