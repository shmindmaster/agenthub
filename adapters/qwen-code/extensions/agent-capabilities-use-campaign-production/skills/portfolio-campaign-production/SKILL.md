---
name: portfolio-campaign-production
description: Orchestrate creative campaign production for the SH portfolio — product launches, social campaign packs, sales collateral, presentations, event kits, brand variants, and customer-story packages. Use when asked to produce marketing, branding, content, demo, or media deliverables for a portfolio app, or to assemble a multi-asset campaign. Selects a canonical creative workflow from the Notion Prompt OS and routes to the owned creative tool adapters (Canva, Adobe, Descript, Remotion, Playwright).
---

# Portfolio Campaign Production

Orchestrates end-to-end creative production by selecting one canonical **Composite Workflow** from the Notion Prompt OS and routing its steps to the correct **Tool Adapters**. This skill does not reimplement tool behavior — it composes the owned lanes.

## When to use

Product launch content, social campaign packs, sales collateral, presentation decks, event marketing kits, brand-variant production, customer-story packages, product visual-evidence capture, and product video pipelines for any app in `C:\Repos\shmindmaster`.

## Workflow

1. **Identify the app.** Determine the current repository/app and fetch its record in the Notion **Apps** database (execution + brand/creative profile). Do not proceed on brand assumptions — read the Brand Kit, color tokens, typography, approved claims, and restricted-data rules from the Apps record.
2. **Route via the Prompt OS.** Invoke the `portfolio-prompt-os` retrieval contract: fetch the **Agent Bootstrap** page and **Prompt Router**, then select exactly one primary **Composite Workflow** (e.g. *Product Launch Content System*, *Campaign Asset Production*, *Narrated Product Story*, *Homepage Product Hero*).
3. **Resolve dependencies.** From the workflow record, fetch required `Calls`, `Prerequisites`, required tools, approval gates, and resolved variables. Confirm execution-host compatibility before starting.
4. **Compose adapters.** Apply the router selection pattern:
   ```
   one primary workflow
   + one evidence or capture adapter
   + one mastering or editorial adapter
   + zero or more derivative-output adapters
   ```
5. **Produce.** Execute each workflow step through its owned adapter (below), respecting each adapter's *do-not-use-when* boundaries.
6. **Generate an asset manifest.** Record every produced asset: type, tool, source template/project ID, aspect ratios, output URL/path, and the approved-claim/brand basis.
7. **Log the run.** Record the run in the Notion **Prompt Runs / Evals** database (agent, model, result, evidence URLs, output artifact, approval obtained). Never reconstruct a canonical prompt from memory when Notion is unavailable — report the access blocker instead.

## Tool adapter routing (owned lanes)

| Adapter | Owned lane | Use when |
|---|---|---|
| **Playwright Product Evidence** | verified screenshots / video / browser flows | you need real product-state captures |
| **Remotion Programmatic Motion** | programmatic video / UI motion / frames | motion driven by data or code |
| **Descript Spoken Content** | transcript editing / narration / audio cleanup | there is a voice/narration track |
| **Adobe Professional Creative** | image editing / composites / MOGRT / mastering | final professional mastering |
| **Canva Campaign Assembly** | campaign assembly / Brand Kit / social formats | multi-format social/campaign layout |
| **Automated Media QA** | quality validation / asset verification | before delivery, always |

Do not run two adapters in the same lane for one deliverable. Prefer the adapter that owns the lane over any general-purpose alternative.

## Approval and safety gates

- Treat brand assets, live product data, and customer material as sensitive. Never fabricate metrics, testimonials, or claims — use only sources marked approved in the Apps record.
- Honor each app's `Restricted content` and `Required legal footer` fields.
- Request approval before publishing outward-facing assets or spending paid render/generation credits.
- Never copy privileged/legal/discovery media into a creative pipeline.

## Output contract

- A named campaign folder (or Notion page) with all deliverables.
- An asset manifest enumerating each asset and its provenance.
- A completed Prompt Runs / Evals record with evidence URLs.

## Handoffs

- **Adobe on Codex/Cursor:** no public Adobe MCP endpoint — use the Adobe REST API (Firefly / Audio-Video) or an explicit Claude Chat/Cowork handoff, per the Adobe tool adapter.
- Use `portfolio-prompt-os` for router/dependency resolution; this skill only orchestrates production once a workflow is selected.
