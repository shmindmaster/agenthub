---
name: video
description: Produces a finished film, screencast, explainer, ad or voiceover from a concept or outline. Use when someone wants any video or audio, a demo film, script, storyboard or series episode. Not for one step of a running job; use generate, capture, compose or review.
---

# Video

A whole film from an idea starts with `studio` (it runs every phase and keeps the state); a rough ask starts with `brief` (approved written brief, picture plan, priced lanes) and `plan` (storyboard with a picture for every line) before anything below. From a short ask, infer kind, `programForm`, audience, voice and delivery; never make the user name skills or steps. Ask one question at most: only with no source, or an unknown destination for a product absent from `registry/product-video-delivery.json`.

- **Kind:** a running product is `product-screencast`, whatever the ask said, after a readiness check (`references/product-picture.md`). A product change told as a story is `programForm: technical-story`. Otherwise `references/forms.md`.
- **Intent:** `intent: viewer-facing`, `craftScoreMin` 85. `intent: draft` only for scratch or proxy cuts.
- **Voice:** Follow `generate/references/voice-recipes.md`. Choose governed DragonHD Emma2 or Andrew2 for new conversational walkthroughs, with Ava as fallback. Keep the selected voice and accepted takes for existing films. Marin on Azure OpenAI `gpt-4o-mini-tts` is gated for directed narration. Direct ElevenLabs is excluded from new recipes. If the governed route cannot run, the cut stays silent and the lines go on screen.
- **Picture:** a viewer-facing R kind (`references/forms.md`) requires Remotion; without it, stop; static slides are no fallback. `intent: draft` is exempt from the render only, never from the picture work: show the topics, figures, dates and documents the lines name, run `scripts/check_picture_relevance.py` before rendering, and look at the contact sheet before calling a picture good or filing it. A film about someone's own call or meeting is judged on exactly this.
- **Style:** cinematic storytelling: hook, stakes, characters, tension, payoff.

## Rules

**Hard repository boundary.** Treat every product repository as read-only. Before the first write, record `repositoryWritePolicy: read-only` and an absolute external workspace in `job.json`. Never create or change video code, Playwright specs, Remotion compositions, dependencies, configuration, fixtures, assets, evidence, media or Git state there, not even "one small helper". Product changes return as readiness feedback. No external workspace possible: stop with `PIPELINE_BLOCKED`.

- Real user data on a live product: stop with `PIPELINE_BLOCKED`.
- Governed film speech uses GA Azure DragonHD. Deepgram Flux batch synthesis serves prepared support prompts. Desktop speech, HeyGen stock avatar voices and Local AI are forbidden for delivery, rehearsal and drafts.
- No Sarosh voice clone. Speaker similarity is advisory; never fail or re-voice on it.
- Reuse accepted assets. Repair order: recut, recapture, rewrite.
- Screencasts are real captured WebM plus Recast. Never Ken Burns, auto-cards or animated screenshots, even when a clip is missing.
- Captions are a sidecar `.srt` only, never embedded or burned in.
- Never invent metrics, customers or product behaviour. Never ship an addendum clip; re-record the section and re-cut the master.
- Higgsfield and Runway credits stay frozen until the owner approves spend. The direct ElevenLabs account is excluded. Generative video: approved hero shots only.

## Pipeline

Copy into job notes; pass each gate before the next. A finished render proves nothing.

```text
1. Brief: `brief` skill, approved brief.md; then job.json, thesis, one promise (story.md)
2. Script: locked facts; validate-narration.mjs passes (story.md)
3. Beat sheet, then storyboard with a picture per line (`plan`, `visuals`), visual bible, direction (scenes.md); gates: check_picture_relevance and check_visual_variety pass
4. Voice lock: ASR round trip passes (generate)
5. Word clock (review)
6. Capture or plates (capture, generate)
7. Cue sheet from the word clock (compose)
8. Compose the candidate (compose)
9. Two-pass loudness master, ducked from stems (compose)
10. Review the encoded file (review); loop on failures
11. Deliver (compose)
```

## References

- `references/story.md`: Read when writing the brief or script, or diagnosing a weak cut.
- `references/forms.md`: Read when choosing kind, `programForm`, delivery profile, series or campaign.
- `references/scenes.md`: Read when storyboarding, directing, picking a renderer or hero shots.
- `references/product-picture.md`: Read when the subject is a running product.
- `references/operations.md`: Read when needing workspace or tool paths, paid spend, review repairs or a short ad.
