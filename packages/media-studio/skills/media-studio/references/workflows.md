# Workflow notes (load after the router picks a kind)

Viewer-facing jobs also load `engagement.md`. Kind rows there are the plate/rhythm defaults; this file is sequencing.

## briefing

Designed viewer experiences on the Remotion **archetype** kit, not a stack of dark-field slides. Default profile `briefing-board` 1600×1000. Not a product screencast.

Evidence-led private briefings (a ledger plus captured/annotated screens): curate plates first (markup over raw), write a dramatic spine, storyboard scenes, then compose. Do not narrate the ledger in order. Open items stay open. Do not recapture live production.

1. Writer (`writer.md`) locks `story/screenplay.json` (`story-craft.md`: sceneRole, WIIFM, hook, one hero).
2. Storyboard (`storyboard.md`) locks `story/storyboard.json` (shot plan, archetype, sound, 2–3 scored hooks — pick internally).
3. Visuals (`visuals.md`) locks `visual-bible.json`. Direction (`direction.md`) maps archetypes and registers.
4. Generate narration through `media-studio-generate` (Azure cast voice per role, no Sarosh voice clone in films; identity is advisory only, never gate on it), supply the bed from an accepted asset unless `intent: draft`. Render composition `Briefing` from the house kit (do not `create-video` a new app). Sync kit source from `packages/media-studio/kit` first.
5. `Finish-Media.ps1 -Speech -Music`. Craft critic (score ≥ 85) then QA. Exact logos, numbers, and legal text are compositor-set type, never diffusion.

Remotion is required unless `intent: draft` or the user asked for a basic/proxy cut.

## training

Same crew, shorter scenes, one learning outcome per clip. Pattern interrupt between cards. Optional Remotion. `learning-studio` owns the question loop; this studio owns the film around it.

## explainer

Comprehension (`story-craft.md` → "Explainer path") comes first. Wrap it in the spine in `story-craft.md` (Question → Stakes → Wrong intuition → Reveal → Demonstration → Implication → Takeaway). `direction.md` §6 picks the simplest truthful visual that maintains attention. Real UI claims still capture through Playwright. A diagram that never builds is unfinished. Remotion required unless draft.

## talking-head

Voice first, then the Azure TTS avatar batch API (prebuilt avatar, `subtitleType: none`) renders a lip-synced presenter. Lipsync of real footage and still-to-motion portraits have no active route (Local AI is off). Viewer-facing: bed + register change on the payoff line.

## animation

Accepted or Azure-generated still → Remotion motion (image-to-video has no active route while Local AI is off). Programmatic UI motion → Remotion. Exact diagrams → SVG/Mermaid, never diffusion.

## audio-only

Voice and/or an accepted, licensed bed (cloud music disabled pending a metered adapter). Mix a bed under speech with `Finish-Media.ps1 -Speech -Music` (sidechain duck), then the same two-pass loudness finish. Silence on the key line.

## product-screencast

Do not load retired `product-demo*` skills. Stay in media-studio: `product-picture.md` (prove config → action → response → result), capture via `record-job.mjs`, local voice of the locked script, `validate-product-picture.mjs`, `media-studio-qa`. Job config is `job.json` in the external workspace; a legacy `product-demo-studio.config.yaml` in a product repo is read-only input and must not be created or updated there. All capture and composition code stays external. Engagement is product-picture plus encoded-file review, not a pre-capture text score.

## series-episode

`series.md` owns methodology and continuity. Tension/escalation/reveal craft is `story-craft.md`. Compose non-screencast picture here. Mix bed and holds in this studio. Remotion required unless draft.

## webcast / webinar

Broadcast or taught-session feel on the archetype kit (`speaker-slide`, `lower-third`, `chapter-card`). Infer `programForm` (`webinar-deep-dive` vs launch/town-hall). Lower-thirds need headroom. Chapters are real beats, not a contents slide. Remotion required unless draft.

## keynote

Speaker coverage plus slides. Change angle or punch-in; a single locked webcam is unfinished. Lower-third on first identification.

## documentary

Picture-led. Slower register, silence for image, B-roll from the visual bible. Do not narrate what the frame already shows.

## teaser

One promise, 15–45s. Recut from a locked master via `sourceJobId` when possible. No logo intro.
