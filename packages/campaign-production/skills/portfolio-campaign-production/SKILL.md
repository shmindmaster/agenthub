---
name: portfolio-campaign-production
description: Use when a portfolio product needs a coordinated launch, social, sales, presentation, event, brand, customer-story, demo, or other multi-asset campaign.
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
| **Automated Media QA** | quality validation / asset verification | before delivery, always |

Do not run two adapters in the same lane for one deliverable. Prefer the adapter that owns the lane over any general-purpose alternative.

**Retired lanes.** Adobe and Canva were removed from the fleet on 2026-08-03; no host registers either MCP. Image compositing, MOGRT, professional mastering, Brand Kit assembly, and multi-format social layout therefore have **no owning adapter**. Do not substitute a general-purpose tool and present the result as the same lane — say the lane is unowned and hand the work to a human, or use the Adobe REST API (Firefly / Audio-Video) under an explicit per-run authorization. Restoring either lane means re-registering the MCP in `registry/mcps.json` first.

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

- **Adobe and Canva are retired fleet-wide.** No coding agent has either MCP. Use the Adobe REST API (Firefly / Audio-Video) or an explicit Claude Chat/Cowork handoff only when the run authorizes it; otherwise report the lane as unowned.
- Use `portfolio-prompt-os` for router/dependency resolution; this skill only orchestrates production once a workflow is selected.
