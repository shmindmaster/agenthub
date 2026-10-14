# Code-walkthrough stage (code + diagram shots)

Records **real source code** and **component diagrams** as screen beats for technical stories, through the same
headless Playwright WebM + Recast path as a product take (`../screencast/record-job.mjs`). No editor GUI, no visible
window, no focus change: the editor is a VS Code-faithful page (Monaco, Dark Modern palette, explorer tree with the
real path, tabs, breadcrumbs, line numbers, minimap, status bar) rendered in headless Chromium and served from disk
through `page.route` on `http://code-stage.localhost/` (no port is opened).

Truth guarantees:

- Files are read from **git objects at a resolved commit** (`git show <commit>:<path>`), never the working tree.
- `capture/code-stage/receipt.json` records the commit, each file's sha256 and blob id, a sha256 per shown line,
  per highlight band and for the context lines in view before the reveal scroll.
- In the browser, the page hashes the lines Monaco actually rendered (`crypto.subtle`) and the take records the
  expectation `rendered lines match the receipt hashes`; it fails the take when they differ.
- `verify-receipt.mjs` re-reads everything from the repository later and also checks the browser's rendered hashes.

| File | Role |
| --- | --- |
| `shotlist.mjs` | Pure shot-list parser: validation, defaults, word cues -> per-shot event timeline |
| `source.mjs` | Git reads at a commit, explorer listing, line hashes, receipt build + verify |
| `build-stage.mjs` | CLI: shot list -> `capture/code-stage/{stage.json,receipt.json,scenes.mjs}` |
| `driver.mjs` | Scene functions (record-lib helpers): load page, verify render, fire events on cue |
| `editor.html` / `diagram.html` | The editor and diagram stages |
| `verify-receipt.mjs` | Re-verify a receipt against the repository (exit 1 on any difference) |

## Shot list (`<job>/story/code-shots.json`)

```json
{
  "schemaVersion": "1.0.0",
  "repo": "C:/Repos/<org>/<repo>",            // read-only; the job workspace must be outside it
  "ref": "main",                               // resolved to a commit once; every file is read at that commit
  "viewport": { "width": 1280, "height": 800 },
  "shots": [
    { "id": "S01", "kind": "code",
      "file": "apps/api/src/gate.py",          // repo-relative, no ".."
      "startLine": 959,                        // optional: first line in view before the reveal scroll
      "lines": [1006, 1031],                   // the range the reveal centres (<= 60 lines)
      "highlight": [[1006, 1011], [1019, 1023]],
      "callout": { "line": 1023, "text": "Nothing executes without this" },   // <= 90 chars, inline below the line
      "zoom": 1.4,                             // Recast punch-in level on each click
      "pointer": [{ "line": 959, "click": true }],                           // optional pointer path
      "crossRef": { "file": "web/Review.tsx", "lines": [153, 168], "highlight": [[168, 168]],
                    "callout": { "line": 168, "text": "Approve stays disabled" }, "label": "renders" },
      "targetSeconds": 19.9, "holdSeconds": 1.0,
      "cues": [ { "event": "highlight:0", "word": "persisted", "lead": 0.1 }, { "event": "callout", "at": 17.6 } ] },
    { "id": "S03", "kind": "diagram", "kicker": "...", "title": "...", "footer": "...",
      "nodes": [ { "id": "evidence", "label": "Evidence", "sub": "persisted capture" }, ... ],   // 2-8 nodes, labels <= 3 words
      "edges": [ ["evidence", "rule"] ],      // optional; default chains the nodes in order
      "lit": "approval", "litChip": "HUMAN GATE",
      "cues": [ { "event": "node:evidence", "word": "evidence" }, { "event": "lit", "word": "approval", "occurrence": 2 } ] }
  ]
}
```

`crossRef` (alias `cross-ref`) may be an object or an array. Events: code `reveal`, `pointer:<k>`, `highlight:<i>`,
`callout`, `crossref:<i>`, `crossref:<i>:highlight`, `crossref:<i>:callout`; diagram `node:<id>`, `lit`. A cue is
`{event, at}` (seconds from the shot's `stage-t0` beat) or `{event, word, occurrence?, lead?}` resolved against
`<job>/story/code-words.json` (`{ "S01": [{ "text", "start", "end" }] }`, e.g. from ElevenLabs `with-timestamps`
alignment or STT words). Events without a cue keep a default pace. The parser refuses spans outside `lines`,
absolute or `..` paths, holds over 8 s, unknown events, missing cue words, and a cross-ref highlight before its open.

## Commands

```powershell
$Kit = '<agenthub>\packages\media-studio\kit'     # or the runtime kit after Sync-MediaStudioKit.ps1
node "$Kit\code-stage\build-stage.mjs" $Job --fps 15 [--monaco <dir with min\vs\loader.js>]
# capture\scenes.mjs: import { scenes as code, recast } from './code-stage/scenes.mjs' and spread them in
node "$Kit\screencast\record-job.mjs" $Job S01 S02 S03
node "$Kit\code-stage\verify-receipt.mjs" "$Job\capture\code-stage\receipt.json"
node --test packages\media-studio\tests\code-stage.test.mjs
```

Monaco resolves from `--monaco`, `CODE_STAGE_MONACO_DIR`, or `kit\node_modules\monaco-editor\min`; otherwise the page
loads the pinned CDN build (cdnjs `monaco-editor@0.52.2`). The clip's `stage-t0` beat (in `capture/receipt.json`) is
where cue time 0 sits in the take: trim the clip there so the cues land on their words.
