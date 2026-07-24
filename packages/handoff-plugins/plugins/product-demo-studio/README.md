# product-demo-studio

Current package release: **0.6.1**. The plugin now requires the validated, current Product
Experience Engineering pre-video handoff and independently reruns its eleven-item capture gate.
The complete self-contained persuasion, craft, production,
automation, and measurement standard is bundled at
`skills/product-demo-studio/references/killer-demo-production-guide.md`; the adjacent compact
playbook maps it to the package's normalized JSON validators.
The synchronized Visual Communication & Asset Generation Guide is bundled beside it and is owned
by `product-demo-studio-visual-assets`; it supersedes stale narration/model tables and forbids
generated product UI or fabricated results.

A cross-agent plugin/skill suite for autonomously assessing demo-worthiness, reconciling, capturing,
composing, narrating, rendering, and QA'ing persuasive product demo / marketing videos with
[Remotion](https://remotion.dev), provider-agnostic TTS, and Descript — built to be invoked against
**any** repository, not a fixed portfolio. It never
installs itself into a target repo; it operates against a repo path (`--repo <path>`) and produces
only the video-production deliverables that repo would own anyway.

## Skills

| Skill | Purpose |
|---|---|
| `product-demo-studio` | Router. Enforces Product Experience handoff → independent demo-worthiness gate → storyboard/narrate → capture → compose → render/QA → video-or-feedback, states the evidence-redaction rule, and reports existing video infra. Start here. |
| `product-demo-studio-remotion` | Product-demo composition policy layered over the official Remotion mechanics owner when available; 43 bundled rules provide a fallback plus studio-specific overlay/evidence guidance. |
| `product-demo-studio-capture` | Deterministic browser-automation capture conventions: fixed viewports, reduced motion, discover-first auth, seeded data only, capture manifests, redaction rules. |
| `product-demo-studio-visual-assets` | Marketing/journey visual survey, non-product-UI asset generation, current model/voice verification, provenance, disclosure, and accessibility. |
| `product-demo-studio-narration` | Provider-agnostic TTS narration: generation, segment-level regeneration, timing, narration style. |
| `product-demo-studio-render` | Render orchestration, the video/scene catalog schema, the product-claim ledger, and the evidence gate that must pass before a render is "approved" for external use. |
| `product-demo-studio-qa` | The proxy-review loop: deterministic technical checks plus five portable independent critic prompts (product-truth, story, visual, audio, technical). |
| `product-demo-studio-descript` | When and how to use Descript's MCP tools for editorial finishing — after the evidence gate, never before. |

## Agents

Five read-only reviewer prompts ship for the QA proxy-review loop: `product-truth-reviewer`,
`story-reviewer`, `visual-reviewer`, `audio-reviewer`, and `technical-reviewer`. Plugin-aware hosts
may invoke them as `product-demo-studio:<name>`; skill-only hosts load the same Markdown prompts
from the canonical root and create equivalent independent reviewer/subagent passes. See
`product-demo-studio-qa`.

## Scripts

All scripts are plain Node (`.mjs`, no build step, zero npm dependencies) under `scripts/`, always
invoked from the plugin against a target repo — never copied into one:

- `video-cli.mjs` — single verb-based entry point for the whole pipeline (`inventory discover
  readiness storyboard claims reset capture voice render-proxy frames qa revise render-final
  package all`).
- `validate-demo-readiness.mjs` / `validate-storyboard.mjs` — fail-closed normalized contracts for
   video-vs-feedback classification and persuasion craft (cold open, before-state, one hero moment,
   all eleven worthiness criteria, three-rung WIIFM with compatible refined aliases, emotional
   target, annotation limits, cadence, and end card).
- `repo-registry.mjs` — reports whether a target repo (`--repo <path>`, the default/primary mode)
  or a workspace of sibling repos (`--root <path>`, optional convenience) already has video
  infrastructure, and its actual shape.
- `scaffold-video-workspace.mjs` — idempotently creates a Remotion video workspace in a target repo.
- `new-video-catalog-entry.mjs` — appends a typed, validated video/scene entry to a repo's catalog.
- `render-videos.mjs` — renders one or all compositions in a target repo's video workspace, using
  whichever package manager (`pnpm`/`yarn`/`bun`/`npm`) the target repo's lockfile indicates.
- `generate-narration.mjs` — provider-agnostic TTS (ElevenLabs / OpenAI, auto-detected from
  environment API keys), with per-segment regenerate-only-changed and checksummed sidecars.
- `compute-overlay-placement.mjs` — resolves a safe on-screen-text region from capture-manifest
  geometry (focus rect, protected regions, cursor path), so headlines/callouts never occlude the
  product.
- `technical-checks.mjs` — FFmpeg/ffprobe-backed technical QA: codec/resolution/fps/duration,
  black-frame/freeze-frame/loudness/silence detection, and scene-boundary frame extraction +
  contact sheet.
- `validate-claims.mjs` / `validate-capture-manifest.mjs` — hand-rolled schema validators for the
  product-claim ledger and capture manifests.
- `check-evidence-gate.mjs` — validates a release-evidence manifest before a render can be treated
  as approved for external use.

## Design notes

- No `commands/` or `hooks/` — this plugin ships skills, an `agents/` directory (the five QA
  reviewers), and scripts.
- Fully self-contained and repo-agnostic: the only required input to repo-operating scripts is `--repo <path>`
  (or a manifest path). No script assumes a specific multi-repo workspace, portfolio registry, or
  identity provider; `repo-registry.mjs --root` is an optional convenience only.
- Generic Remotion APIs and framework mechanics are owned by the current official
  `remotion-best-practices` capability when it is available. The bundled `rules/` are a
  self-contained fallback plus Product Demo Studio integration policy, vendored from
  [`remotion-dev/remotion`](https://github.com/remotion-dev/remotion/tree/main/packages/skills)
  (39 files) plus 4 supplementary rules (`charts.md`, `can-decode.md`, `extract-frames.md`,
  `overlay-placement.md`) — the first three from
  [`affaan-m/ECC`](https://github.com/affaan-m/ECC/tree/main/skills/remotion-video-creation),
  the last authored for this plugin's occlusion-avoidance workflow.
- `.mcp.json` optionally bundles Descript's remote MCP server
  (`https://api.descript.com/v2/mcp`) so enabling this plugin offers a one-time OAuth connection
  to your own Descript Drive, without requiring the separate claude.ai connector setup. If a
  Descript connector is already connected at the session level, use those tools instead — don't
  connect twice. Narration (ElevenLabs/OpenAI) is called directly from `generate-narration.mjs` via
  plain HTTPS, not through an MCP server — set `ELEVENLABS_API_KEY` and/or `OPENAI_API_KEY`.
- This plugin does not scaffold anything into any product repo on its own. Invoke its skills and
  scripts explicitly, per repo, when you're ready to produce that repo's videos.
- Fleet-distributed skill-only hosts resolve this directory from the `product-demo-studio`
  capability's `canonicalSource` in the Agent Capabilities registry. They do not rely on the
  Claude-only `CLAUDE_PLUGIN_ROOT` environment variable or duplicate the scripts into product repos.
