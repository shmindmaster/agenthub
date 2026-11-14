# Video

## Workflow contract

1. Use the brief or existing job, intended viewer and delivery target.
2. Choose the production form, route to the appropriate stage, and carry evidence from capture or generation through review.
3. Return the encoded deliverable and verified disposition, or a stage-specific blocker.
4. If the source or destination cannot be established, resolve it before production or publishing.

A whole film from an idea starts with `studio` (it runs every phase and keeps the state); a rough ask starts with `brief` (approved written brief, picture plan, priced lanes) and `plan` (storyboard with a picture for every line) before anything below. From a short ask, infer kind, `programForm`, audience, voice and delivery; never make the user name skills or steps. Ask one question at most: only with no source, or an unknown destination for a product absent from `registry/product-video-delivery.json`.

- **Kind and reality:** classify the *requested film*, not only the existence of a product. Use `references/creative-formats.md` for verified demos, fictional stories, future visions, day-in-the-life films, documentaries, education, animation and hybrids. Choose `product-screencast` with real captured UI when the movie promises to prove current functionality. Imagined or future-state UI is allowed in a clearly identified concept/vision film and is not forced through the current-product proof gate. A verified product change told as a story may be `programForm: technical-story`; otherwise use `references/forms.md`.
- **Intent:** `intent: viewer-facing`, `craftScoreMin` 85. `intent: draft` only for scratch or proxy cuts.
- **Voice:** Follow `generate/references/voice-recipes.md`. Choose governed DragonHD Emma2 or Andrew2 for new conversational walkthroughs, with Ava as fallback. Keep the selected voice and accepted takes for existing films. OpenAI Marin (`openai-speech`) is the option for directed narration. Direct ElevenLabs is excluded from new recipes. If the governed route cannot run, the cut stays silent and the lines go on screen.
- **Picture:** a viewer-facing R kind (`references/forms.md`) requires Remotion; without it, stop; static slides are no fallback. `intent: draft` is exempt from the render only, never from the picture work: show the topics, figures, dates and documents the lines name, run `scripts/check_picture_relevance.py` before rendering, and look at the contact sheet before calling a picture good or filing it. A film about someone's own call or meeting is judged on exactly this.
- **Style:** cinematic storytelling: hook, stakes, characters, tension, payoff.

## Rules

**Hard repository boundary.** Treat every product repository as read-only. Before the first write, record `repositoryWritePolicy: read-only` and an absolute external workspace in `job.json`. Never create or change video code, Playwright specs, Remotion compositions, dependencies, configuration, fixtures, assets, evidence, media or Git state there, not even "one small helper". Product changes return as readiness feedback. No external workspace possible: stop with `PIPELINE_BLOCKED`.

- Real user data on a live product: stop with `PIPELINE_BLOCKED`.
- Governed film speech uses GA Azure DragonHD. Deepgram Flux batch synthesis serves prepared support prompts. Desktop speech, HeyGen stock avatar voices and Local AI are forbidden for delivery, rehearsal and drafts.
- No Sarosh voice clone. Speaker similarity is advisory; never fail or re-voice on it.
- Reuse accepted assets. Repair order: recut, recapture, rewrite.
- **Verified current-product screencasts** use real captured WebM plus Recast for factual functionality. **Vision, fictional and concept films** may render wholly synthetic UI, realistic human characters and animated scenes via their supported image/video/Remotion workflow. Do not mislabel concept UI as verified current behavior.
- Captions are a sidecar `.srt` only, never embedded or burned in.
- Never invent factual metrics or present fictional customers or proposed behavior as verified current facts. Intentionally invent characters, scenes, interfaces and speculative technologies when the approved film calls for them; identify the representation appropriately. Recut the master instead of shipping an addendum.
- Higgsfield and Runway credits stay frozen until the owner approves spend. The direct ElevenLabs account is excluded. Generative video: approved hero shots only.

## References

- `references/story.md`: Read when writing the brief or script, or diagnosing a weak cut.
- `references/creative-formats.md`: Read before classifying any film. It separates creative freedom from present-day functionality claims and permits realistic synthetic people, patients, children, fictional interfaces and entirely invented worlds.
- `references/forms.md`: Read when choosing kind, `programForm`, delivery profile, series or campaign.
- `references/scenes.md`: Read when storyboarding, directing, picking a renderer or hero shots.
- `references/product-picture.md`: Read when the subject is a running product.
- `references/operations.md`: Read when needing workspace or tool paths, paid spend, review repairs or a short ad.

Read when executing this skill for its detailed commands and gates. [Workflow detail](video-detail.md)

For consulting product proof, technical walkthroughs or release highlights, load [consulting communication](consulting-communication.md). Select the communicationProfile in the existing brief and pass it through development, capture and review; reuse accepted proof for audience variants while retaining limitations.
