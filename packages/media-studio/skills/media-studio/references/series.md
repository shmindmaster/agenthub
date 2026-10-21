# Series (multi-episode technical story methodology)

Read this for kind `series-episode` and for any multi-episode technical story series. AgentHub owns **methodology**. The separate series repository owns **story**: no private names, customers, show bible content or media in AgentHub. The picture is made in this studio (`SKILL.md` crew), never in a second engine.

## 1. Load order

1. Confirm the series repository / working tree (outside AgentHub) for the private bible, casts and media.
2. Real incident → `writer.md` §5 (Dramatize a real incident, with the comedy escalation craft).
3. Tech teaching moments → also `story-craft.md` → "Explainer path" and `direction.md` §6 (which visual).
4. Fictionalize before any external share: the `sarosh-writing` fictionalization reference. Record mappings only in the private series repository, never in AgentHub.
5. Continuity → §4 below.
6. Assembly → §5 below.
7. Direction of technical scenes → `direction.md` §7 (series technical beats).

## 2. Truth tags (required)

Every beat is tagged:

- `FACT` — observed / receipt-backed
- `DRAMATIZED` — real cause, heightened telling
- `COMPOSITE` — merged events; disclose in the ledger

## 3. Episode structure

1. Cold open with a concrete problem.
2. Status quo + character objective.
3. Complication (technical + human).
4. Midpoint reversal.
5. Climax tied to a receipt/truth.
6. Takeaway the viewer can steal.

Non-series viewer-facing films reuse the same tension craft (`goal → obstacle → escalation → complication → reversal → payoff`) via `story-craft.md`. Do not force those jobs to become series episodes.

Workplace drama: conflict should come from incentives and system design, not personal attacks. Fictionalize employers, customers, and coworkers. Keep the engineering causal chain intact.

## 4. Continuity

Validate against `../../../schemas/series/continuity.schema.json` and the prior episode ledgers in the series repository. Flag contradictions in character knowledge, system state, and timeline.

## 5. Assembly

Assemble the episode package against the schemas in `../../../schemas/series/`:

- `episode.schema.json` — id, title, logline, truth summary, technical takeaway, scenes
- `scene-plan.schema.json` — scene id, goal, visual mode, truth tag
- `receipt-ledger.schema.json` — per-claim `FACT` / `DRAMATIZED` / `COMPOSITE` with a source
- `continuity.schema.json` — series facts and open threads

Enforce truth tags and receipt links on every beat. No private media in AgentHub.

### Picture path

Non-screencast picture is made here (`kind: series-episode`). After the episode, scene plan and ledger are locked, run the crew in `SKILL.md`: `writer.md` → `storyboard.md` → `visuals.md` → `direction.md` → `media-studio-generate` → `media-studio-compose` → story-experience review → `media-studio-qa`. Remotion via capability `video.programmatic-composition` (tracked third-party), not vendored.

Do not compose slides from the scene plan alone. Do not skip the storyboard. Live-product beats stay on the capture engine invoked from this studio (`product-picture.md`: WebM + Recast); a series episode is not assembled from PNG plates and Remotion cards and called a product film. Do not convert the screencast engine into a series engine.

### Final check

- [ ] Every beat has a truth tag and a receipt link
- [ ] Viewer-facing film went through `storyboard.md`
- [ ] Private bible/media stayed outside AgentHub
- [ ] Fictionalized before any external share
