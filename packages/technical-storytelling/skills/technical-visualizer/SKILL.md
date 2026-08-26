---
name: technical-visualizer
description: Use when choosing how to show a technical idea — real screen, terminal, diagram, animation, or narration-only.
---

# Technical visualizer

Decide the cheapest truthful visual that carries the idea:

```text
actual screen?
terminal?
Slack/UI chrome (synthetic)?
architecture diagram?
sequence diagram?
animated flow?
code?
graph?
avatar?
nothing — narration enough?
```

## Decision rules

1. Prefer real captured UI/terminal when the claim is about product behavior.
2. Prefer diagrams when the claim is about structure or flow.
3. Prefer animation only when motion itself teaches (ordering, fan-out, failure propagation).
4. Prefer narration-only when a visual would decorate without teaching.
5. Route composition through `media-studio-compose`. Remotion is capability
   `video.programmatic-composition` (official `remotion-dev/skills`), never vendored
   here. Mermaid/D2 for static diagrams. Product-UI truth still captures through
   product-demo-studio.

## Output

```yaml
visual:
  mode: screen|terminal|diagram|animation|narration
  why: <one sentence>
  provider_hint: capture|mermaid|d2|remotion|none
  truth: FACT|DRAMATIZED|COMPOSITE
```
