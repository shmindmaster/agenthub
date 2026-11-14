# NotebookLM (research and draft lane)

Read this when a topic needs source-grounded research, a quick overview to learn from, or a rough deck or infographic to react to. Tool: `teng-lin/notebooklm-py` (MIT, unofficial), a CLI over Google's undocumented NotebookLM interface.

## What it gives

Audio and video overviews, a slide deck (PDF or PPTX), an infographic PNG, a quiz and flashcards, a report, a data table and a mind map, all grounded in the sources you add.

## How it fits

- **Draft only.** Output is for learning the material and for reacting to a rough shape. It is never the delivered picture or voice. The finished film is built in the kit, with Azure speech and a drawn picture.
- **Useful moves:** add the source pages, ask for the report or mind map to find the real structure, read the infographic or deck to see how a topic can be drawn, then redraw it in the kit.
- **Free tier limits:** about three audio and three video overviews a day.

## Run

Use the CLI with `--json`; do not run the MCP or REST server for this. Log in once in a normal window (the owner does that); the CLI keeps its own session. Do not schedule it.

```text
py -3 -m notebooklm --help
py -3 -m notebooklm create "<job name>" --json
py -3 -m notebooklm source add <url-or-file> --json
py -3 -m notebooklm generate report --json
```

Installed 2026-11-06 as notebooklm-py 0.8.6 (`py -3 -m pip install --user notebooklm-py`). The `notebooklm` script is not on PATH, so call it through `py -3 -m notebooklm`. Not logged in yet: `notebooklm login` opens a browser for a Google sign-in, which is the owner's one step. Check `--help` for the installed version's exact commands; they change.

## Limits to keep

- It is an unofficial client of undocumented APIs, so it can break without notice. When it fails, continue without it.
- Public and personal material only. Client material, customer data and anything under an NDA stays out.
- Record the draft's path in the job ledger as `draftOnly`, so it is never mistaken for a delivered asset.
