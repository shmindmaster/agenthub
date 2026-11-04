---
name: video
description: Produces a finished film, screencast, explainer, ad or voiceover from a concept or outline. Use when someone wants any video or audio, a demo film, script, storyboard or series episode. Not for one step of a running job; use generate, capture, compose or review.
argument-hint: "<concept, outline or bullets>"
---

# Video

A short ask is enough. Infer kind, `programForm`, audience, voice and delivery, and do not ask the user to name skills or steps. Ask at most one question, and only when there is no source at all or the destination is unknown and the product is not in `registry/product-video-delivery.json`.

| Need | Default |
| --- | --- |
| Kind | A running product is `product-screencast`, whatever the ask called it. Otherwise `references/forms.md` |
| Intent | `intent: viewer-facing`, `craftScoreMin` 85. `intent: draft` only for scratch or proxy cuts |
| Voice | A distinct, expressive Azure voice per character (`generate`) |
| Workspace | `%LOCALAPPDATA%/AgentHub/media-studio/<job-id>`; artifacts under `MEDIA_STUDIO_ROOT` (default `D:/Media-Studio`) |
| Picture | A viewer-facing kind marked R in `references/forms.md` requires Remotion. If it is missing, stop; static slides are not a fallback. `intent: draft` is exempt |
| Style | Cinematic storytelling: hook, stakes, characters, tension, payoff |

## Rules

**Hard repository boundary.** Treat every product repository as read-only. Before the first write, record `repositoryWritePolicy: read-only` and an absolute external `workspace` in `job.json`. Never create or change video code, Playwright specs, Remotion compositions, dependencies, configuration, seed fixtures, assets, evidence, generated media or Git state there, not even "one small helper". A needed product change goes back as readiness feedback. If no external workspace is possible, stop with `PIPELINE_BLOCKED`.

- Real user data on a live product: stop with `PIPELINE_BLOCKED`.
- Azure first, cheapest option that passes QA. Local AI is off: never start local models, TTS, STT or embedders.
- No Sarosh voice clone. Speaker similarity is advisory; never fail or re-voice on it.
- Reuse accepted assets. Order of repair: recut, recapture, rewrite. Re-render only the failing scene from `reviseSceneIds`, and remux unchanged audio.
- Screencasts are real captured WebM plus Recast. Never Ken Burns, auto-cards or animated screenshots, even when a clip is missing.
- Captions are a sidecar `.srt` only, never embedded or burned in.
- Never invent metrics, customers or product behaviour. Never ship an addendum clip; re-record the section and re-cut the master.
- Higgsfield and Runway credits are frozen until the owner approves a spend. ElevenLabs speech is owner-authorized per job through `generate`; ElevenLabs sound effects and music stay disabled. Generative video is for approved hero shots only.

## Pipeline

Copy this checklist into the job notes. Run the cheapest gate at each step and continue only when it passes; a finished render proves nothing.

```text
- [ ] 1. Brief and thesis: job.json, one promise (story.md)
- [ ] 2. Script: screenplay, locked facts, validate-narration.mjs passes (story.md)
- [ ] 3. Beat sheet: one line per beat, then storyboard, visual bible, direction (scenes.md)
- [ ] 4. Voice lock: takes pass the ASR round trip (generate)
- [ ] 5. Word clock: accepted takes aligned (review)
- [ ] 6. Capture or plates: WebM takes, accepted stills (capture, generate)
- [ ] 7. Cue sheet: build-cue-sheet.mjs from the word clock (compose)
- [ ] 8. Compose the candidate (compose)
- [ ] 9. Loudness master: two-pass, ducked from stems (compose)
- [ ] 10. Review the encoded file (review); loop on failures
- [ ] 11. Deliver (compose)
```

The loop: `review` names `reviseSceneIds` and an owner. Rerun that step on those scenes, re-encode, and review again. Continue to delivery only when review passes.

A running product needs a readiness check first. The valid outcomes are a strong film, or product feedback and no film (`references/product-picture.md`). A product change told as a story is `programForm: technical-story`.

Short 15 to 30 second ads use `kit/marketing/README.md`. Run `mvg.mjs` with separate `--stage compose`, `--stage qa` and `--stage deliver` calls, each with `--candidate-id`, and pass `--no-line-chips --no-captions`.

Native plugins run `scripts/` from the installed package. Loose-skill hosts use `%LOCALAPPDATA%/AgentHub/media-studio/_shared/tools`. A missing tool blocks the job until `Sync-MediaStudioKit.ps1` repairs it.

## References

| File | Read when |
| --- | --- |
| `references/story.md` | Writing the brief, thesis or script, or diagnosing a weak cut |
| `references/forms.md` | Choosing kind, `programForm`, delivery profile, a series or a campaign |
| `references/scenes.md` | Beat sheet, storyboard, visual bible, direction, picking a renderer, hero shots |
| `references/product-picture.md` | The subject is a running product |
