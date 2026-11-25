# Screen-stage fixture

A synthetic product and a proof-job generator for the full-bleed "screen stage" film. No real data, no customer names, no network.

- `ledger/index.html` is "Tally", a one-file household expense ledger laid out for 1280x720. Flow: click the Amount header
  (`col-amount`), open `menu-format`, open `item-number`, click `sub-currency`. A `toast` confirms and `body[data-format]` becomes `currency`.
  `window.__ledger = { revision, persona }` is the identity probe. Other test ids: `note-field` (text cursor), `status-selection`.
- `serve.mjs [port]` serves `ledger/` on 127.0.0.1 (default 4811); `startServer(port)` returns `{ url, close }`.
- `make-proof-job.mjs <outDir> [--viewer-facing] [--touch] [--phone-in-frame]` writes a job workspace with one screen beat, S01. Default (a): 16:9 desktop,
  clicks, a typing burst (played at 2x), one declared highlight ("Open format"), 12.6 s. `--touch` (b): the phone layout (the page is responsive
  below 640 px), taps, 9:16 (record with `--ratio 9:16`). `--phone-in-frame` (c): the same phone capture inside a 16:9 frame over a generated gradient.
- `proof-box.sh` is the whole proof on one Daytona box (capture, compose, gates, negative controls, click sounds, mixing test). Env: `PROOF_JOB_FLAGS`,
  `PROOF_RECORD_FLAGS`, `PROOF_BASE`. Negative controls: the core-v1 renderer (files sent with `--put` under `/work/v1`), a fade-in film and a 30 fps re-encode must all FAIL the gate.
- `pad.mjs` writes the synthesised music pad for the mixing test (`--bright` is a bed that must fail it); `motion-energy.mjs` prints per-0.1 s motion energy for the reference comparison.
- The job is `intent: "draft"` by default because the ledger has no sign-in, so no scenario proof can be written.
- Capture and render run on a Daytona box, not on the PC. The clip `capture/clips/S01.mp4` is written by the stage recorder.

Check: `node make-proof-job.mjs <dir>`, then `validate-capture-preflight.mjs <dir>` and `build-cue-sheet.mjs <dir>` from `packages/media-studio/scripts`.
