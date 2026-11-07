# Workflow detail


## Workflow

`<kit>` is `%LOCALAPPDATA%/AgentHub/media-studio/briefing-kit`. `<tools>` is `%LOCALAPPDATA%/AgentHub/media-studio/_shared/tools`.

```text
- [ ] Verify deployed commit, role, seed or reset, and a clean browser profile; read the product note
- [ ] Lock narration, then write capture/scenes.mjs and story/capture-plan.json
- [ ] node <kit>/screencast/record-job.mjs <jobRoot> [S05 ...]
- [ ] Validate, fix, repeat until all pass
- [ ] Build plan/cue-sheet.json with build-cue-sheet.mjs
```

**Scenes.** `capture/scenes.mjs` exports `options`, `order` and one `async S05(h, ctx)` per screen beat. Drive the product only through the `h.*` helpers. End every interaction beat with `h.expect(locator, 'label')`. Pacing is built into the helpers, so never add `page.waitForTimeout`; re-pace or split the beat.

Start the product with `node <tools>/demo-stack.mjs up --repo <product>`; a shipped `demo/harness.json` prefills `scaffold-video-workspace.mjs`.

**Record.** `record-job.mjs` runs `validate-capture-preflight.mjs` and refuses on failure. It writes one take per beat: `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json` and hash-bound `capture/receipt.json`. Do not use `--skip-preflight` for a real take; no gate accepts it. Re-record a SHORT or INVALID take, never pad it. Keep config and runtime in one session (`carryState`).

**Validate loop.** Run from `<tools>`; re-record only failing beats until all pass:

```powershell
node validate-capture-manifest.mjs <manifest>
node validate-product-picture.mjs <jobRoot>
node validate-pointer-path.mjs <jobRoot>
```

**Voice first.** Align picture to voice, never stretch voice. `node <kit>/cloud/cloud-ai.mjs align --take <take.wav> --script <locked-line.txt> --out voice/align/<id>.json`. A transcript is a text check, never the clock.

Screencast quality is the product-picture contract plus the story-experience review in `review`, not a second overlay stack. Annotation markup is the compositor's layer, applied after Recast.

Capture each delivered ratio at its own viewport. Never derive a vertical or square cut from a desktop capture, even by a small crop.
