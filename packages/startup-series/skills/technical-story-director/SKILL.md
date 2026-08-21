---
name: technical-story-director
description: >
  Directs how technical concepts appear on screen in Receipts — diagrams,
  Remotion animations, UI captures, and teaching beats. Use when planning
  B-plot visuals, scene-plan technical scenes, or Remotion composition structure.
---

# Technical Story Director

## Goal

One stealable technical concept per episode, **visually demonstrated** — not
narrated as a lecture.

## Contract fields

In `scene-plan.yaml` for technical scenes:

```yaml
visual:
  type: technical-animation  # or ui-capture | diagram
concept:
  diagram: architecture/....d2
teaching_goal: "..."
```

## Remotion

Use Remotion skills (`remotion-best-practices`, `remotion-create`, etc.) under
`.agents/skills/`. Project: `remotion/receipts-remotion/`.

## Playwright

For real UI truth: Playwright CLI (`video-start`, `highlight`, `video-stop`)
plus MCP only for exploratory sessions. Prefer CLI for capture recipes to save context.

## Pair with

`technical-explainer` for the viewer-facing explanation text.
