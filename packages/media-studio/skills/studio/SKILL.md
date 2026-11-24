---
name: studio
description: Takes a video, screencast, lesson, explainer, fiction, ad or audio idea to a finished, reviewed piece in the requested form, making routine choices within delegated authority. Use when someone wants any video or audio made, or brings an idea or rough ask. Not for one step of a running job.
---
# Studio
## Workflow contract
1. Use the request and the job root if one exists. Read `production_status.py <jobRoot>` first and resume at the earliest missing or failed stage; reuse accepted assets.
2. New job: run the intake below, then run `script`, `produce` and `finish` in order. Each stage writes a file and passes its gate before the next starts.
3. Return the delivered file and the review verdict, or the last passed stage and the exact next input.
4. Continue through internal creative, script, pilot and final candidate decisions within delegated authority, keeping accepted assets. Pause for an explicitly reserved review, a material unresolved choice, paid work outside authorization or external publication.
## Make the requested piece

Use the user's brief as the creative direction. Preserve its format, audience, tone, structure and deliverables. A request for narrated answer slides, a sample lesson, a storyboard, a visual treatment or a fictional scene should produce that artifact. A source is material to work from. Follow the user's requested level of research and citations. Handle uncertainty in a line or production note where it affects the audience's understanding.

Follow the requested form, storyline, picture, pace and production method. Use evidence-led treatment for a documentary or verified product proof when the brief calls for it. Education can use code, diagrams, simulations and synthetic math pictures. Fiction can use generated scenes and invented worlds. A conceptual explanation can hold a frame for reading or thinking. Use text or synthetic UI where it serves the experience and disclose its status where it might be taken for real product behavior.

Make routine creative choices and start useful work in the same turn. Use a template, brainstorming pass, research phase or specialist plugin when the brief calls for it or it directly advances the requested artifact. Apply checks for an actual published-product claim or a requested verified demonstration to the affected claim and scene.

## Choose the viewing route

For interview preparation, infer the call stage and the interviewer's stated agenda from the supplied invitation and correspondence. Use the role description and candidate evidence to choose the stories. For a product film, discover the actual workflows, roles and consequences before cutting for time. When a job needs both, plan a reusable standalone product sequence and give it a chapter inside the tailored briefing. Keep the personal framing in the briefing. Carry these defaults into the existing brief without repeating settled intake questions.

## Creative intake (new jobs only)
Act as a **creative director and producer**, not a configuration wizard. Follow [guided creative intake](references/creative-intake.md) and the governed provider catalog; infer what the brief, source material, product profile or series already establishes.

1. **Use the specified treatment.** If the brief leaves the treatment open, choose one that serves the audience and deliverable. Put it in the brief and begin drafting.
2. **Ask only consequential missing decisions.** A normal invocation needs zero to three concise choices: creative direction, narrator/voice or silence, and picture/capture approach. Ask about audience, runtime, destination, aspect ratio, language or tier **only if** the request cannot establish them and the difference changes the result. Provide a recommended answer and an **accept recommended** option; do not show a six-question form by default.
3. **Adjust interaction depth to intent.** Quick Create (infer and recommend), Creative Studio (compare up to three treatments or voice styles), and Advanced Production (explicit providers, models, capture methods and render settings) are presentation depths for the **same** `script → produce → finish` pipeline, not new pipelines or plugins. Do not make the user choose a mode before interpreting the request.
4. **Cast voices by sound and suitability, not vendor branding.** Where narration is valuable and unresolved, recommend two or three *currently governed, authorized* voices and offer a short same-passage audition. Generate playable auditions only after the exact provider, estimated spend and approval gates pass. Do not imply a catalog listing, credits or a generated label is a playable sample. AssemblyAI also remains a transcription and alignment option. Honor the voice-clone scope, frozen-lane and per-film approval policies.
5. **Choose capture/compute by task fit.** For verified running products, default to true source-hashed application capture with authorized synthetic data, `ah-browser` and the approved remote execution lane; offer manual/signed-in browser/footage options only where appropriate. Ask about Daytona, aspect ratio and render infrastructure only when a material tradeoff needs the owner's decision. Never imply a simulated interaction is proof of a live capability.
6. **Show one compact production recommendation** (treatment, voice, picture, format, estimated cost and any approval needed). Estimate with `scripts/estimate-job-cost.mjs --scenes <n> --words <n> --stills <n> --hero <n> [--voice openai]`; re-estimate if the storyboard changes. Use actual governed routing and price eligibility; estimates are not spend authorization.

Pass accepted choices into the existing brief and job manifest. Reuse an existing job's accepted choices; never restart its intake or redo an approved audition unless a material requirement changes. Classify films using [video](references/video.md), [creative formats](references/creative-formats.md) and [forms](references/forms.md).
## Uses other plugins
- Screen capture and UX walkthroughs: `ah-browser` (agent-browser `record ... --cursor` for clean takes; BrowserSkill for the owner's signed-in browser).
- Composition, animation, captions and render: the official Remotion plugin and skills; renders run on a disposable Daytona box, never on this PC.
- Transcription: `ah-assemblyai`. Optional edit hand-off: Descript.
## Rules
<HARD-GATE>
Record actual internal delegation in `production.json` as `"reviewAuthority": "delegated"`. List any explicitly reserved checkpoints under `requiredReviews` (`case`, `screenplay`, `plan`, `delivered`). For a required review, use `production_status.py <jobRoot> --approve <name>` only for actual owner approval. Delegation never authorizes purchases, raises spend caps, unlocks providers, or authorizes external publication. Preserve privacy, rights and credential controls.
</HARD-GATE>
- Design the viewing and listening experience to fit the requested format. Slides, titles, worked examples, deliberately held frames, dialogue and silence are legitimate choices. Plan the picture or intentional stillness for each beat and use automated style signals to direct review against the brief.
- Cheapest authorized lane that passes QA; show the budget before any paid step.
- Never present concept or synthetic UI as verified current product behaviour.
- Product repositories are read-only; all work lives in an external job workspace.
Read when running a whole film: [conductor](references/conductor.md) and [phases](references/phases.md). Detail: [studio](references/studio-detail.md), [video](references/video-detail.md), [story](references/story.md), [scenes](references/scenes.md), [product picture](references/product-picture.md), [operations](references/operations.md), [consulting communication](references/consulting-communication.md).