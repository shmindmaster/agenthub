# Screen-stage fixture

A synthetic product and a proof-job generator for the full-bleed "screen stage" film. No real data, no customer names, no network.

- `ledger/index.html` is "Tally", a one-file household expense ledger laid out for 1280x720. Flow: click the Amount header
  (`col-amount`), open `menu-format`, open `item-number`, click `sub-currency`. A `toast` confirms and `body[data-format]` becomes `currency`.
  `window.__ledger = { revision, persona }` is the identity probe. Other test ids: `note-field` (text cursor), `status-selection`.
- `serve.mjs [port]` serves `ledger/` on 127.0.0.1 (default 4811); `startServer(port)` returns `{ url, close }`.
- `make-proof-job.mjs <outDir> [--viewer-facing]` writes a job workspace with one screen beat, S01 (6.0 s, 16 hand-timed words,
  clicks at about 1.0, 2.0, 3.1, 4.2 s, result at 4.6 s, 1.4 s end hold). It has `screenStage: {}` for the stage to fill.
- The job is `intent: "draft"` by default because the ledger has no sign-in, so no scenario proof can be written.
- Capture and render run on a Daytona box, not on the PC. The clip `capture/clips/S01.mp4` is written by the stage recorder.

Check: `node make-proof-job.mjs <dir>`, then `validate-capture-preflight.mjs <dir>` and `build-cue-sheet.mjs <dir>` from `packages/media-studio/scripts`.
