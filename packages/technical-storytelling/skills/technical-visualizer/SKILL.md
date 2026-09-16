---
name: technical-visualizer
description: Use when choosing how to show a technical idea — real screen, terminal, diagram, animation, or narration-only.
---

# Technical visualizer

Decide the **simplest truthful visual that maintains attention**. A cheaper still that holds across two ideas is unfinished, not simpler.

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
5. If the output is a film, a visual that never changes across a scene is unfinished, not cheaper. Builds, cuts, and motion that teach are not decoration; film craft lives in `media-studio` `references/engagement.md`.
6. Route composition through `media-studio-compose`. Remotion is capability
   `video.programmatic-composition` (official `remotion-dev/skills`), never vendored
   here. Mermaid/D2 for static diagrams. Product-UI truth still captures through
   `media-studio-capture` (Playwright WebM + Recast in `packages/media-studio`).
   Do not load retired `product-demo*` skills.

## Output

```yaml
visual:
  mode: screen|terminal|diagram|animation|narration
  why: <one sentence>
  provider_hint: capture|mermaid|d2|remotion|none
  truth: FACT|DRAMATIZED|COMPOSITE
```
