# Guided creative intake — one producer, a few meaningful decisions

This reference expands the `studio` entry point. It **does not** add a workflow, approval gate, provider adapter, profile schema or new plugin. The source of truth for actual provider state is `policy/provider-routing.json`, `route_media.py --catalog`, the current governed adapters and private owner policy.

## Priorities

1. **User's outcome:** identify the viewer, requested deliverable and delivery channel from the task and project.
2. **Creative treatment:** carry forward the requested direction. When the brief delegates treatment, choose one suited to the viewer and form, then begin the work.
3. **Picture:** choose the media the brief calls for. Use the running application and approved fixtures for scenes demonstrating current behavior. Use designed or invented scenes when suited to the requested treatment.
4. **Voice:** infer narration/no narration and cast for the audience; do not choose a vendor just because it has credits.
5. **Technical production:** choose supported browser, capture, aspect and remote render lanes automatically unless a visible tradeoff remains.
6. **Budget and approvals:** present the priced, executable choice before spending. No extra gates or silent approvals.

## Decision depth — adaptive, not three separate pipelines

| Intent | Interaction | When to ask |
| --- | --- | --- |
| Quick Create | One recommended treatment, using context and existing series defaults. | Only to resolve a consequential missing input or obtain a required approval. |
| Creative Studio | Optionally contrast up to three *meaningfully different* director treatments or narrator styles. | When the user asks for choices or multiple defensible directions exist. |
| Advanced Production | Show eligible provider/model, voice, capture, viewport, aspect, cost and remote-execution options. | When the user requests technical control or a genuine tradeoff blocks production. |

An existing job always begins with `production_status.py <jobRoot>`; resume at the earliest missing/failed stage and preserve accepted assets. Do not ask previously answered questions. Carry explicit creative delegation through screenplay, picture, pilot and internal delivery. Keep any reserved reviews and independent spend and publication authorization.

## What to recommend (the director's brief)

Use a compact, user-facing recommendation, typically one paragraph plus only the necessary choice:

- **Viewer promise:** one sentence describing what the viewer should understand or do afterward.
- **Treatment:** e.g. authentic product-led walkthrough, premium commercial, documentary, guided tutorial, technical story, creative concept or an appropriate hybrid.
- **Screenplay:** the sequence best suited to this piece. For example, work through each question in order when the brief asks for annotated answer slides.
- **Picture:** what the viewer sees. For verified demonstrations, specify the application state and interaction to capture.
- **Sound:** no narration / one narrator / cast dialogue; desired delivery qualities.
- **Production:** suitable run length, destination/ratio and quality tier inferred from the request.
- **Quote:** estimated authorized spend, assumptions and required approvals. Recalculate after the storyboard and asset counts are known.

Use the existing `script` stage to write the formal treatment, screenplay, beat sheet, storyboard, picture plan and fact lock. An intake selection is *not* a substitute for the writing stage.

## Casting and auditable voice auditions

Cast by **delivery quality** (clear instructional, warm conversational, confident authoritative, expressive cinematic, character dialogue), then choose eligible providers from the actual catalog:

- **Deepgram:** the default for stock (non-cloned) voices: Flux TTS batch through the governed adapter (Flux Sienna and Haley; Aura-2 is not governed yet). ABACare films use AssemblyAI stock voices instead.
- **Azure Speech DragonHD:** the next route after Deepgram. Approved voices such as Emma2/Andrew2 for conversational walkthroughs; Ava/Andrew where suitable.
- **Azure OpenAI / OpenAI speech:** directed narration including Marin/Cedar **only when the specific governed route is enabled for this task**.
- **ElevenLabs:** premium speech, dialogue and effects are candidates **only under the applicable authorization and frozen-lane policy**, including the Deloitte pursuit films (Revolva, Empowera, CoLedger), and only with a written reason in the job.
- **AssemblyAI:** TTS for ABACare films and the only clone route (personal and ABACare films), callable only once `assemblyai-tts` is not frozen in `policy/provider-routing.json` and a governed adapter runs it; until then deliver the ABACare cut with the next eligible stock route and note the gap, plus transcription, timing, alignment and independent quality checks. Clones use a consented reference recording with 60 day validity, renewable.
- Other providers: candidates only after checking `route_media.py --catalog`, actual model/voice compatibility, authorization, and pricing.

Do not promise that any named voice is currently callable merely because its documentation exists. Never generate fake audio previews or describe an unplayed sample as heard.

When a real audition is useful and authorized:

1. Use the *same* short representative passage (typically 8–15 seconds) and comparable target loudness.
2. Offer at most **two or three** eligible contrasting voices, including the recommended default.
3. Quote the actual estimated audition spend and obtain any required approval **before** paid synthesis.
4. Generate through the governed adapters; save the exact voice/provider/settings, passage, costs and audio artifacts in the external job workspace.
5. Present actual playable previews with meaningful names; if audio cannot be played or audition approval is unavailable, present an explicit limitation, not a fabricated opinion of the voices.
6. Save the approved choice for the current film/series and regenerate only changed or rejected segments.

A requested cloned voice does not bypass existing private consent, account, spend or scope rules. Clones are for personal or ABACare films only, through AssemblyAI. Before any generation, name the owning entity and read its live balance; use the provider with the most usable credit for that entity. Do not automatically audition a full provider roster on every film.

## Picture and capture choice

- **Verified running product:** default to `ah-browser` using the existing real-interaction capture contract, exact revision, synthetic test data, role and responsive viewport. Source-hashed Playwright/WebM + Recast evidence, pointer path, action result and timing gates apply.
- **Existing footage:** inspect rights, provenance, recency and compatibility before reusing; retain approved source takes.
- **Concept/brand/documentary:** use the existing supported animation, Remotion, still, human-world and licensed-media routes appropriate to the creative treatment. Mark proposed capabilities as proposed.
- **Signed-in/manual capture:** only when approved access or unique workflow makes automation insufficient; preserve privacy and do not impersonate unavailable roles.

Infer the appropriate remote worker from current private compute guidance: Daytona, established CI, or another approved lane. Do not surface cloud-provider names as ordinary creative choices. Never run heavy capture/render locally when private rules prohibit it. Record the chosen lane and actual source revision in the capture receipt.

## Quality tiers

- **Draft:** quick story/pacing/voice exploration; never silently publish a draft-only asset.
- **Professional (default):** authentic legible picture, reliable product action, clear narration, consistent design, accessible captions sidecar and strong review.
- **Premium:** richer treatment, acting, sound design, generated context or additional directed takes only where the viewer outcome and authorized spend justify them.

The tiers set creative expectations; they do not authorize unavailable providers or bypass screenplay, cost, truth, picture, accessibility, or final review gates.

## Examples of minimal responses

**Clear request:** “Create a 45-second vertical demo of our new scheduling workflow.” Recommend one product-led treatment, actual role interaction and one approved voice style; ask only for missing authorization or a consequential preference.

**Ambiguous request:** “Make something impressive about the platform.” Infer the product identity if available, offer two genuinely different concepts and a recommended viewer promise; ask *one* question about the audience or business objective if it materially changes the film.

**Explicit audition:** “Compare OpenAI and ElevenLabs voices.” First check governed routes and budget; offer executable auditions only from authorized voices. Explain frozen/unavailable candidates without charging or silently swapping.

**Existing film:** “Finish yesterday's cut.” Inspect `production_status.py` and continue from the earliest unmet gate; do not restart intake, change a locked voice or recut accepted scenes without evidence.
