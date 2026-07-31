---
name: product-demo-studio-visual-assets
description: Use when auditing text-heavy marketing or journey surfaces, planning or generating truthful visual assets, selecting narration and media models, or producing non-product-UI imagery that supports a product demo or launch surface.
---

# Product Visual Assets

Read the complete
[Visual Communication & Asset Generation Guide](../product-demo-studio/references/Visual-Asset-Guide.md)
before planning or generating assets. It is the authoritative model, voice, disclosure, and visual
asset contract for Product Demo Studio.

## Ownership boundary

- Product Experience Engineering owns whether the real product workflow is useful and
  `DEMO-READY`.
- Product Demo Studio owns truthful product-demo media after that gate.
- This skill owns the visual communication survey and non-product-UI image/voice assets used by
  marketing and journey surfaces or demo composition.
- The Browser Quality Toolkit owns live browser diagnostics and evidence capture.

Do not generate product screenshots, product UI, tables, metrics, workflows, or product results.
Those must be captured from the real product using synthetic data. Generated imagery may support
concept, context, brand, atmosphere, or illustration only when it cannot be mistaken for product
evidence.

## Workflow

1. Confirm the product audit/remediation gate has run for any surface whose claims depend on the
   product.
2. Survey the complete page or journey. Identify text that should remain text, visual hierarchy
   defects, and gaps where an image can orient, explain, prove, or create recognition.
3. Give every proposed asset one job, placement, aspect ratio, art direction, source/provenance,
   alt-text purpose, and acceptance test. Cut decorative assets that do no work.
4. Reuse real product captures for product truth. Use generated or licensed assets only for
   non-product visual communication.
5. Before any billed generation, verify current model availability, deprecations, pricing, output
   limits, license/usage terms, and provider credentials against current official sources. Never
   silently substitute a provider or model.
6. For narration, audition with synthetic text, record the exact provider/model/voice/instructions,
   and include the required clear synthetic-voice disclosure in every public/customer-facing
   master and derivative.
7. Record prompts, seeds where supported, source files, transforms, licenses, disclosures,
   checksums, and the automated acceptance decision.
8. Validate the asset in its real page/video context at representative responsive sizes,
   light/dark mode, zoom, reduced motion, and with assistive text alternatives.

Fail closed when provenance, license, disclosure, product truth, accessibility, or current model
status is unresolved.

## Creative-suite connectors (Adobe / Canva)

These are **post-production and collateral** tools. They do not replace real product capture,
product-demo-studio, or the Visual Asset Guide integrity rules.

### When to use which

| Job | Tool | Notes |
| --- | --- | --- |
| Show the **real product** | Product capture / studio stills / Remotion from real UI | Never generate or "design" product UI in Adobe Express or Canva |
| Color-grade / cohesive look on **real** stills | Adobe for creativity (`adobe-for-creativity` MCP) | `adobe-batch-edit-photos`, Lightroom-style adjustments |
| Exact resize / social crops of **real** assets | Adobe resize / social-variation skills | Prefer subject-aware crop over generative expand for product truth |
| Highlight / sizzle from a **real** screencast | Adobe Quick Cut / Premiere path | Source must be real capture; do not invent product motion |
| Brand-templated social, OG, flyer, pitch slide | Canva MCP **or** Adobe Express templates | Lock brand kit / tokens; no fake product screenshots inside |
| Invented product dashboards, metrics, AI glassmorphism heroes | **Forbidden** | Same integrity bar as Guide 3 §2.3 |

### MCP registration (fleet)

Canonical registry entries (agenthub):

- `adobe-for-creativity` → `https://adobe-creativity.adobe.io/mcp` (OAuth, host-managed)
- `canva` → `https://mcp.canva.com/mcp` (OAuth, host-managed)

Sync with `Sync-AgentHub.ps1 -Apply` so Grok, Qwen, Claude, and other active hosts receive
the remote MCP definitions. Credentials stay in host OAuth stores — never in the registry.

### Host notes

- **Claude**: First-class Adobe path (connector + optional `adobe-for-creativity` plugin/skills from
  [adobe/skills](https://github.com/adobe/skills/tree/main/plugins/creative-cloud/adobe-for-creativity)).
  Sign in with Adobe ID for full tools and CC storage.
- **Grok / Qwen / others**: Register the remote HTTP MCP; complete OAuth in that host when prompted.
  Adobe's interactive file-picker widgets and some skills are Claude-optimized — if a skill blocks on
  Claude-only widgets, use direct MCP tools with public/presigned asset URLs or fall back to Claude
  for that step.
- **Canva**: Works with any MCP client that supports remote OAuth; brand kits need Pro/Enterprise per
  Canva docs. Prefer templates over freeform generative designs for portfolio taste control.

### Adobe skill pack (optional, workflow recipes)

Official skills under the Adobe plugin (require the MCP connector):

- `adobe-batch-edit-photos` — cohesive photo grade across a set
- `adobe-retouch-portraits` — portrait batch retouch
- `adobe-resize-photos-and-videos` — exact dimensions
- `adobe-create-social-variations` — platform crops
- `adobe-edit-quick-cut` — sizzle from real video
- `adobe-design-from-template` — Express templates (collateral only)

Do not treat Adobe Firefly generative expand or Express template "product mock" art as product
evidence. Generative expand on product UI is a trust failure.

### Acceptance for connector-produced assets

1. Source is a real product capture, licensed photo, or non-product brand collateral.
2. Output matches brand tokens (ABACare: ultraviolet primary, intelligence cyan, calm care tone) or
   an explicit approved campaign look.
3. No invented metrics, fake UI chrome, or AI fantasy hero loops on public product pages.
4. Manifest / provenance records model or app path, disclosure if required, and automated acceptance.

## Full media stack map (website · marketing · demos · social)

Use this after product/website asset fixes. Sequence still matters: **truthful product first**, then
polish, then assembly, then optional editorial finish.

| Stage | Job | Primary tool | Fallback / notes |
| --- | --- | --- | --- |
| 0 · Product gate | Workflow DEMO-READY | product-experience / prepare-product-for-demo | Do not film broken UI |
| 1 · Real product media | Show the product | product-demo-studio-capture + real UI components | Never generate product UI |
| 2 · Non-product imagery | Context, brand, atmosphere | **OpenAI Images API `gpt-image-2`** (API, not MCP) or Adobe Express / Canva templates | Job 4 only; disclose photoreal people; no fake dashboards |
| 3 · Still polish | Grade, crop, social packs | **Adobe for creativity** MCP | Canva resize if brand-kit only |
| 4 · Narration | Voiceover for demos / explainers | product-demo-studio-narration: **ElevenLabs** (default catalog) or **OpenAI `gpt-4o-mini-tts`** | Avoid legacy `tts-1` / `tts-1-hd` for new work; disclose synthetic voice always |
| 5 · Assembly | Persuasive masters | product-demo-studio-remotion / render | Claim ledger + truth sheets |
| 6 · Editorial finish | Filler, Studio Sound, social cut, share link | **Descript** MCP (optional) | Only after evidence gate; no local MP4 export via API |
| 7 · Collateral | OG, LinkedIn, flyers, pitch | Canva brand templates or Adobe Express | Brand kit locked |

### Descript MCP (`https://api.descript.com/v2/mcp`)

- **Needed?** Yes for optional finishing of approved masters and quick social cuts — not required for
  the core capture→narrate→Remotion path.
- **Can do:** import media (URL/local), Underlord edits (captions, filler removal, Studio Sound,
  highlight reels), list/manage projects, publish to Descript web share links, track jobs.
- **Cannot do:** direct local MP4 export via MCP; YouTube URL import; multi-drive in one session.
- **Cost:** Descript media minutes + AI credits.
- **Skill owner:** `product-demo-studio-descript` (gate-aware).
- **Setup:** OAuth; Grok/Qwen use custom MCP URL; Claude may use directory connector (media gen needs
  custom MCP per Descript docs).

### OpenAI Images + Speech (API skills, not MCP)

There is no official OpenAI “Images/TTS MCP” to register like Descript/Adobe. Production use is
through env-backed scripts and skills (`OPENAI_API_KEY`), with model currency from the Visual Asset
Guide and live OpenAI docs.

| Capability | Current model | Do not use for new work |
| --- | --- | --- |
| Image generate/edit | **`gpt-image-2`** | DALL·E 2/3 (retired); migrate off `gpt-image-1*` family per Guide §0.2 |
| TTS (instructions-capable) | **`gpt-4o-mini-tts`** family; prefer current snapshot | Pinning retired snapshots; `tts-1` / `tts-1-hd` are legacy (no `instructions`, smaller voice set) |
| Voices (gpt-4o-mini-tts) | Prefer `marin` / `cedar` for quality | Silent voice switches across a catalog |

Integrity (unchanged):

- Never generate product UI or invented metrics with Images API.
- Always disclose AI-generated photoreal people and synthetic voice on public surfaces.
- Org verification may be required for GPT Image models.
- Prefight model deprecations before every billed run.

### Sequencing for ABACare-style work

1. Fix website / product presentation (homepage media audit).
2. Recapture honest product stills and demo plates.
3. Optional: OpenAI/Adobe non-product brand imagery + grade.
4. Narrate (ElevenLabs or OpenAI TTS) → Remotion master.
5. Optional: Descript social cut / share link after automated acceptance and explicit publication authority.
6. Canva/Adobe for channel collateral only.
