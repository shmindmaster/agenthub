# Operations

## Workspace and tools

- Workspace: `%LOCALAPPDATA%/AgentHub/media-studio/<job-id>`; artifacts under `MEDIA_STUDIO_ROOT` (default `D:/Media-Studio`).
- Native plugins run `scripts/` from the installed package. Loose-skill hosts use `%LOCALAPPDATA%/AgentHub/media-studio/_shared/tools`. A missing tool blocks the job until `Sync-MediaStudioKit.ps1` repairs it.

## Pipeline gates

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

## Review repair loop

`review` names `reviseSceneIds` and an owner. Rerun that step on those scenes, re-encode, and review again. Continue to delivery only when review passes.

Reuse accepted assets. Order of repair: recut, recapture, rewrite. Re-render only the failing scene from `reviseSceneIds`, and remux unchanged audio.

## Paid providers

Higgsfield and Runway credits are frozen until the owner approves a spend. ElevenLabs speech is owner-authorized per job through `generate`; ElevenLabs sound effects and music stay disabled. Generative video is for approved hero shots only.

## Short ads

Short 15 to 30 second ads use `kit/marketing/README.md`. Run `mvg.mjs` with separate `--stage compose`, `--stage qa` and `--stage deliver` calls, each with `--candidate-id`, and pass `--no-line-chips --no-captions`.
