---
name: episode-editor
description: Use when assembling scene plans, narration, and receipt ledgers into a coherent episode package.
---

# Episode editor

Assemble against schemas in `schemas/`:

- episode.schema.json
- scene-plan.schema.json
- receipt-ledger.schema.json
- continuity.schema.json

Enforce truth tags and receipt links. No private media in AgentHub.

## 1. Picture path

Non-screencast picture is **Media Studio** (`kind: series-episode`). After the episode/scene-plan/ledger are locked:

`media-writer` → `media-storyboard` → `media-studio-visuals` → `media-director` → `media-studio-generate` → `media-studio-compose` → craft critic → QA.

Do not compose slides from the scene plan alone. Do not skip the storyboard.

Live-product beats stay on the PDS capture engine invoked from `media-studio` (`product-picture.md`: WebM + Recast). Do not assemble a series episode from PNG plates and Remotion cards and call it a product film.

## 2. Final check

- [ ] Every beat has a truth tag and a receipt link
- [ ] Viewer-facing film went through `media-storyboard`
- [ ] Private bible/media stayed outside AgentHub
