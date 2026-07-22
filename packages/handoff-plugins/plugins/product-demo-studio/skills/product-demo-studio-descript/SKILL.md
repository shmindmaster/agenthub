---
name: product-demo-studio-descript
description: >
  When and how to use Descript for editorial finishing of a video — after it has already passed
  the evidence-redaction gate, never before. Use when the user asks to "clean up the audio",
  "remove filler words", "add captions with Descript", "make a shorter social cut", or "publish
  this for review". This is the optional "finish" stage of product-demo-studio, after
  demo-worthiness, craft/correctness QA, evidence approval, and product-demo-studio-render. Covers
  Descript's real MCP capability surface and its limits so you don't attempt edits it can't perform
  or use editorial finishing to conceal a product-fix-required defect.
---

## Descript is an editorial finishing lane (not capture/render core)

Descript is a convenience layer, not a required stage. The capture → narrate → sync → caption →
render pipeline can be produced end-to-end in-house with no Descript dependency:

- **Capture** — the actual screen recording (e.g. Playwright `recordVideo`, or Remotion for
  synthetic scenes). Descript cannot produce this.
- **Narration** — generated yourself (ElevenLabs TTS or equivalent).
- **Sync + final MP4** — your own ffmpeg mux places each narration clip at its measured offset.
- **Captions** — when you already have the ground-truth narration text (you generated the TTS
  from it) plus each clip's duration and on-screen offset, **generate the captions yourself** and
  burn them in — either as an SRT + an ffmpeg subtitle filter, or as a lower-third overlay drawn
  during the recording itself. This is **strictly better than Descript's ASR captioning**: zero
  transcription errors, perfect sync, no AI credits, no round-trip. (Note some bundled ffmpeg
  builds ship `--disable-filters` with no `subtitles`/`drawtext` — in that case draw the caption
  as a DOM/overlay element during capture, which is burned in natively.)

Use Descript when the user explicitly asks for its strengths (transcription cleanup, speaker
isolation, filler-word removal, style-driven trims, and quick alternate social cuts). For the
core capture-to-render pipeline, keep the existing in-house flow and avoid unnecessary round-trips.

- **Sharing is not a reason.** A shareable link is trivial without Descript — OneDrive/Drive, a
  YouTube upload, or a direct file link all do it. Do not import to Descript "just to get a link."
- **Captions** — done better in-house from ground-truth narration text (zero ASR error).
- **Audio cleanup (Studio Sound)** — marginal on already-clean TTS.
- **Filler-word / silence removal** — N/A for TTS, and destructive to narration↔video sync.

The finishing niche is when a **human wants Descript's interactive editor** to hand-tweak wording,
timing, and style by feel, or when quick post-render editorial changes are needed without
re-rendering a full composition.

## Gate check first

Do not import anything into Descript that hasn't passed `product-demo-studio-render`'s evidence
gate (`classification: approved`). Descript is an editorial-finishing tool, not a review tool —
by the time footage reaches it, redaction and claim review are already done. This matches the
portfolio's own standard: "Use Descript only for editorial finishing after technical media
review."

## Which Descript tools are available

Descript connects as an MCP server (`https://api.descript.com/v2/mcp`, OAuth, scoped to one
Descript Drive per connection). Depending on how this plugin is being run, the actual tool names
you see may be prefixed differently:

- If a Descript connector is **already connected at the session level** (e.g. via claude.ai
  Connectors), use those tools directly — do not also try to connect this plugin's bundled
  `.mcp.json` server, which would attempt a second, redundant OAuth connection.
- If this plugin's bundled `.mcp.json` `descript` server is the one enabled, its tools appear
  with that server's prefix instead.

Either way, the tool set is the same: `import_media`, `prompt_project_agent`, `publish_project`,
`wait_for_job`, `list_jobs`, `cancel_job`, `list_projects`, `get_project`.

## Resolve the project/composition first

Because the MCP connection is scoped to a single Drive, always call `list_projects`/`get_project`
before editing to confirm you're targeting the right project and composition — there is no way
to switch Drives mid-session, and editing a project on the wrong Drive errors out. `get_project`
also returns any existing publish share URLs, so check it before re-publishing if you just need
the existing link.

## `prompt_project_agent` (Underlord) is the only edit primitive

There is no fine-grained "cut here" / "move this paragraph" API — every edit goes through
natural-language instructions to Underlord via `prompt_project_agent`. Be specific: name the
project, the composition, and the exact outcome ("remove filler words and long silences from the
raw capture in composition X", "add burned-in captions", "run Studio Sound to clean up the
voiceover track"). Vague prompts waste AI credits on the wrong result.

One concrete use pattern for this portfolio:

1. **Repurpose a finished Remotion master into a shorter social cut** — import the approved
   render, ask Underlord for a highlight reel or trimmed cut, instead of hand-authoring a second
   Remotion composition for every social variant.

Never send raw capture or pre-gate plates to Descript. If capture cleanup is needed before
composition, use deterministic local editing in the capture/render pipeline, then pass the result
through the normal evidence and approval gates.

## Export is a signed web link, not a local file

There is no API/MCP endpoint for local MP4 export. `publish_project` + `wait_for_job` returns a
signed, shareable Descript web-link URL — that is the only scripted "export" path. If a true
local MP4 file is needed, that step must be done manually inside the Descript app; do not tell
the user a local file exists when only a web link does.

## Known limits to plan around

- **Single-Drive scope** — the whole session is pinned to one Drive; switching requires the user
  to log out/reconnect Descript on the web.
- **30-day job history** — don't rely on `list_jobs` to find anything older than a month.
- **HTTP 402** — media-minutes or AI-credit exhaustion. If a call fails with 402, tell the user
  plainly rather than retrying blindly; retrying doesn't fix an exhausted quota.
- **No YouTube import** — Descript's import does not accept YouTube URLs as a source.
- Prefer **Chat mode** over autonomous/agent modes when driving Descript conversationally — it's
  the mode Descript's own docs confirm works best with this MCP.

## After publishing

The signed share URL from `publish_project` is what goes into a Slack message, sales email, or
review request — not a raw file path. Record it in the render's evidence manifest
(`product-demo-studio-render`) so there's a durable link between the approved render and its
published, reviewable form.
