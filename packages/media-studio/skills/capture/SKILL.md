---
name: capture
description: Produces hash-bound WebM takes of a live product with Recast pointer, click and zoom finishing. Use when a film needs real product footage, a screen recording, a Playwright take or a re-record of a beat. Not for stills or slides; use generate or compose.
---

# Capture

The contract is `../video/references/product-picture.md`. Read it first. Screen beats are real WebM plus Recast. PNGs are posters only, never the picture of a `screen` beat, even when a take is late.

Work only in the external job workspace, because the product repository is read-only. Scripts, traces, recordings, manifests, auth state and reset evidence all stay there. Never add a capture test, helper or file to the product repo. A needed product or seed change is readiness feedback for a separate task.

Capture only an owner-authorized synthetic tenant or sandbox with fictional data. Never show real customer tickets, names or PII, write to customer systems, or copy cookies or signed-in browser profiles. Production capture needs an approved sign-in route and stays read-only.

## Browser

Deterministic takes are Playwright CLI or Test from the external workspace. Exploratory looks use the running surface's browser where `registry/fleet-profile.json` `hostSurfaces` records `browser.isolated: true`, and happen before the take. Never write a host-specific browser tool name into a storyboard, manifest or script.

## Workflow

`<kit>` is `%LOCALAPPDATA%/AgentHub/media-studio/briefing-kit`. `<tools>` is `%LOCALAPPDATA%/AgentHub/media-studio/_shared/tools`.

```text
- [ ] Verify deployed commit, role, seed or reset, and a clean browser profile; read the product note
- [ ] Lock narration, then write capture/scenes.mjs and story/capture-plan.json
- [ ] node <kit>/screencast/record-job.mjs <jobRoot> [S05 ...]
- [ ] Validate, fix, repeat until all pass
- [ ] Build plan/cue-sheet.json with build-cue-sheet.mjs
```

**Scenes.** `capture/scenes.mjs` exports `options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } }`, `order = [...]`, and one `async S05(h, ctx)` per screen beat. Drive the product only through `h.go`, `h.approach`, `h.click`, `h.typeText`, `h.uploadFile`, `h.fillValue`, `h.selectOption`, `h.pointAt`, `h.hoverHold`, `h.smoothScroll`, `h.expect`, `h.hold`. End every interaction beat with `h.expect(locator, 'label')`. Pacing is built into the helpers, so never add `page.waitForTimeout`; re-pace or split the beat.

If the product ships `demo/harness.json`, `scaffold-video-workspace.mjs` prefills from it. Start the product with `node <tools>/demo-stack.mjs up --repo <product>`.

**Record.** `record-job.mjs` runs `validate-capture-preflight.mjs` and refuses on failure. It writes one take per beat: `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json` and hash-bound `capture/receipt.json`. Do not use `--skip-preflight` for a real take; no gate accepts it. Re-record a SHORT or INVALID take, never pad it. Keep config and runtime in one session (`carryState`).

**Validate loop.** Run from `<tools>` and re-record only the beats that fail. Continue only when all pass:

```powershell
node validate-capture-manifest.mjs <manifest>
node validate-product-picture.mjs <jobRoot>
node validate-pointer-path.mjs <jobRoot>
```

**Voice first.** Align picture to voice, never stretch voice. `node <kit>/cloud/cloud-ai.mjs align --take <take.wav> --script <locked-line.txt> --out voice/align/<id>.json`. A transcript is a text check, never the clock.

Screencast quality is the product-picture contract plus the story-experience review in `review`, not a second overlay stack. Annotation markup is the compositor's layer, applied after Recast.

Capture each delivered ratio at its own viewport. Never derive a vertical or square cut from a desktop capture, even by a small crop.

## References

| File | Read when |
| --- | --- |
| `references/recording.md` | Multiple ratios, a native mobile app, Recast limits (`autoZoom`, `.recast-tmp`), uploads, selects or filled inputs |
| `references/abacare-local.md` | Capturing ABACare |
| `references/abacare-lexicon.json` | ABACare pronunciation |
