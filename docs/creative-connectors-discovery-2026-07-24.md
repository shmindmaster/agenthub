# Creative connectors discovery — Adobe, Canva, Descript, OpenAI media APIs

**Date:** 2026-07-24
**Scope:** Full media production path for website, marketing, demos, and social — after product
and presentation fixes. Fleet registration for Grok, Qwen, and active hosts.

## Sources

- Adobe: https://github.com/adobe/skills/tree/main/plugins/creative-cloud/adobe-for-creativity · https://developer.adobe.com/adobe-for-creativity/ · MCP `https://adobe-creativity.adobe.io/mcp`
- Canva: https://www.canva.dev/docs/mcp/ · https://www.canva.com/help/mcp-agent-setup/ · MCP `https://mcp.canva.com/mcp`
- Descript: https://help.descript.com/hc/en-us/articles/46056322186509 · custom MCP https://help.descript.com/hc/en-us/articles/46351582343309 · Claude https://help.descript.com/hc/en-us/articles/45008080343053 · ChatGPT https://help.descript.com/hc/en-us/articles/46215649218445 · MCP `https://api.descript.com/v2/mcp`
- OpenAI Images: https://developers.openai.com/api/docs/guides/image-generation · prompting cookbook https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide
- OpenAI TTS: https://developers.openai.com/api/docs/guides/text-to-speech · models `tts-1` / `tts-1-hd` (legacy)

## Verdict

| Connector / API | Useful? | Primary role |
| --- | --- | --- |
| **Adobe for creativity** | **Yes — post-production** | Grade, crop, retouch, social variants, sizzle of **real** captures; Express collateral |
| **Canva MCP** | **Yes — secondary** | Brand-templated marketing collateral and exports |
| **Descript MCP** | **Yes — optional finish** | After evidence-approved masters: Underlord edits, highlight reels, share links |
| **OpenAI Images (`gpt-image-2`)** | **Yes — non-product imagery** | Job-4 context / brand art only; **never product UI** |
| **OpenAI TTS (`gpt-4o-mini-tts`)** | **Yes — narration option** | Demo/marketing VO alongside ElevenLabs; always disclose synthetic voice |

None of these replace real product capture or fix fake homepage media by themselves.

## What Adobe actually is

- Remote MCP with ~50+ tools across Photoshop, Lightroom, Illustrator, Firefly, Premiere, Express,
  InDesign, Stock (Adobe marketing claim; tool availability depends on plan + auth).
- Official skills are multi-step recipes (`adobe-batch-edit-photos`, `adobe-design-from-template`,
  `adobe-edit-quick-cut`, `adobe-create-social-variations`, `adobe-resize-photos-and-videos`,
  `adobe-retouch-portraits`, plus PDF skill variants).
- First-class setup is **Claude** (connector directory + plugin). Other agents can use the same
  remote MCP URL if they support OAuth streamable HTTP.
- Guest mode ≈ reduced free tools; Adobe sign-in unlocks CC storage, higher limits, more tools.
- Many skills assume Claude UI widgets (`asset_add_file` picker, `AskUserQuestion`). Grok/Qwen may
  need direct tool calls + URL assets when widgets are missing.

## What Canva actually is

- Remote MCP for design generate/edit, folder/asset ops, comments, export (PNG/JPG/PDF/PPTX/MP4…),
  resize (Pro+), brand kits/templates (Pro/Enterprise).
- Already present in `~/.grok/config.toml` before this work, but **not** in the fleet
  `registry/mcps.json` — so Qwen and Sync did not manage it canonically.
- Risk: `generate-design` can produce generic SaaS art that worsens taste problems if used for
  product heroes.

## Fit against Visual Asset Guide / homepage audit

| Homepage need | Adobe | Canva | Prefer instead |
| --- | --- | --- | --- |
| Kill AI glassmorphism hero loop | N/A (stop generating) | N/A | Real CareOperations visual / capture |
| Color-match real product stills to brand | Strong | Weak | Adobe batch edit |
| Social/LinkedIn crops of real stills | Strong | Strong | Either; Adobe if CC-owned |
| Trust / continuity diagrams | Weak (Express templates) | Medium | Tokenized SVG/HTML in product |
| Fake multi-role dashboards | **Do not** | **Do not** | Real product captures |
| Owner demo poster frame | Extract from real video | Template only | Studio poster from capture |

## Fleet registration (done)

- `registry/mcps.json`: `adobe-for-creativity`, `canva` (global-default, http, oauth)
- `registry/mcp-registrations.json`: both, hosts `registered-oauth-pending`
- Skill policy: `product-demo-studio-visual-assets` updated with connector routing
- Host apply: `Sync-AgentCapabilities.ps1 -Apply` for Grok + Qwen (and other active hosts)

## Human gates remaining

1. **Adobe OAuth** in each host (Grok, Qwen, Claude) with the Creative Cloud account that owns the
   suite.
2. **Canva OAuth** where not already completed (Grok had URL only; tools may not load until auth).
3. Optional Claude: install Adobe connector + plugin from Claude directory for full skill UX.
4. Optional: clone Adobe skills into Claude skills when plugins unavailable
   (`npx skills add adobe/skills` or GitHub skill upload).

## Non-goals

- Do not replace product-demo-studio capture/Remotion with Firefly or Canva generative video.
- Do not store Adobe/Canva secrets in agenthub.
- Do not treat connector output as DEMO-READY product proof without the existing truth gates.

## What Descript actually is

- Remote MCP: `https://api.descript.com/v2/mcp` (OAuth, single Drive per connection).
- Capabilities: import media (URL or local), auto-transcribe, Underlord edits (captions, filler
  removal, Studio Sound, highlight reels, scene gen), project/folder management, publish share
  links, job tracking.
- Limitations: **no local MP4 export via MCP** (manual in app); no YouTube URL import; 30-day job
  history; consumes media minutes + AI credits.
- Official connectors: Claude directory + ChatGPT app directory; any assistant via custom MCP URL.
- Portfolio skill: `product-demo-studio-descript` — optional finish **after** evidence gate only.
- Grok already had Descript URL in config; fleet registry now owns it for Sync → Qwen and others.

## What OpenAI media APIs are (not MCP)

- **Images:** Image API + Responses image tool. Current model **`gpt-image-2`**. Org verification
  may be required. Use for non-product visual assets per Visual Asset Guide §0–2.
- **TTS:** Prefer **`gpt-4o-mini-tts`** with `instructions` (accent, tone, pace). Voices include
  marin/cedar for quality. **`tts-1` / `tts-1-hd`** remain available but are legacy (no
  instructions, smaller roster, character billing). Do not pin retired snapshots without live check.
- Delivery: env-backed scripts in product-demo-studio-narration (`--provider openai|elevenlabs`)
  and visual-assets generation — **not** a remote MCP entry in `registry/mcps.json`.
- Always disclose synthetic voice and AI photoreal people on public surfaces.

## Full production path (after website asset fixes)

1. Product/workflow truth → product-experience + prepare-product-for-demo
2. Real captures → product-demo-studio-capture
3. Optional non-product art → OpenAI gpt-image-2 or Adobe/Canva templates
4. Still polish → Adobe MCP
5. Narration → ElevenLabs or OpenAI gpt-4o-mini-tts
6. Master → Remotion / product-demo-studio-render
7. Optional finish → Descript MCP
8. Channel packs → Canva / Adobe social variations

## Fleet registration (done)

- `registry/mcps.json`: `adobe-for-creativity`, `canva`, `descript`
- `registry/mcp-registrations.json`: same, hosts oauth-pending
- OpenAI: no MCP row; skills + `OPENAI_API_KEY` + Visual Asset Guide model currency
- Skill policy: `product-demo-studio-visual-assets` full stack map
