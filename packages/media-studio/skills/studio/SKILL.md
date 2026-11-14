---
name: studio
description: Takes a video, screencast, explainer, ad or audio idea to a finished, reviewed piece, asking a few quick questions first to pick the approach. Use when someone wants any video or audio made, or brings an idea, topic or rough ask. Not for one step of a running job.
---
# Studio
## Workflow contract
1. Use the request and the job root if one exists. Read `production_status.py <jobRoot>` first and resume at the earliest missing or failed stage; reuse accepted assets.
2. New job: run the intake below, then run `write`, `produce` and `finish` in order. Each stage writes a file and passes its gate before the next starts.
3. Return the delivered file and the review verdict, or the last passed stage and the exact next input.
4. Stop at an owner approval (brief/script, spend, final cut) and keep accepted assets.
## Intake (new jobs only)
Ask up to six quick multiple-choice questions in one message, each with a recommended answer, and skip any a file or the request already answers:
1. Purpose and viewer: who watches and what they should do afterwards.
2. Kind: verified product demo, training, explainer, story or concept, ad.
3. Length and destination: YouTube, LinkedIn, website, internal or presentation.
4. Voice: none (captions), AI narrator (recommended), or the owner.
5. Picture: real product capture, concept or animated, or a mix.
6. Quality and engine: draft, standard (recommended) or premium; voice on Azure DragonHD (default) or OpenAI marin/cedar. Show each tier's price from `scripts/estimate-job-cost.mjs --scenes <n> --words <n> --stills <n> --hero <n> [--voice openai]` so the choice is made with its cost.
From the answers choose the kind, `programForm`, delivery profile, tier and lanes (OpenAI lanes in `policy/provider-routing.json`: `openai-text`, `openai-image`, `openai-speech`, `openai-transcribe`, `openai-moderation`), show the plan and the estimate, and get one yes before spend. Re-run the estimate when the storyboard changes the counts. Rules for classifying films: [video](references/video.md), [creative formats](references/creative-formats.md), [forms](references/forms.md).
## Uses other plugins
- Screen capture and UX walkthroughs: `ah-browser` (agent-browser `record ... --cursor` for clean takes; BrowserSkill for the owner's signed-in browser).
- Composition, animation, captions and render: the official Remotion plugin and skills; renders run on sh-forge in a disposable workspace, never on this PC.
- Transcription: `ah-assemblyai`. Optional edit hand-off: Descript.
## Rules
<HARD-GATE>
No stage starts until the previous one shows PASS in `production_status.py`. Record an approval with `production_status.py <jobRoot> --approve <name>` only after the owner said yes to that exact item in this conversation.
</HARD-GATE>
- Picture first: every line has something to look at; words in boxes fail the picture gates.
- Cheapest authorized lane that passes QA; show the budget before any paid step.
- Never present concept or synthetic UI as verified current product behaviour.
- Product repositories are read-only; all work lives in an external job workspace.
Read when running a whole film: [conductor](references/conductor.md) and [phases](references/phases.md). Detail: [studio](references/studio-detail.md), [video](references/video-detail.md), [story](references/story.md), [scenes](references/scenes.md), [product picture](references/product-picture.md), [operations](references/operations.md), [consulting communication](references/consulting-communication.md).