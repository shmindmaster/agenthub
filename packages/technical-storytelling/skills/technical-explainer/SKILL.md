---
name: technical-explainer
description: Use when turning a technical failure, design choice, or system behavior into a structured explanation a viewer can reuse.
---

# Technical explainer

Convert a technical question or incident into this **comprehension** structure:

```text
CORE IDEA          one sentence
PLAIN EXPLANATION  2–4 sentences
ANALOGY            memorable comparison
REAL EXAMPLE       what actually happened (FACT-tagged)
MISCONCEPTION      what people commonly get wrong
VISUAL PLAN        diagram / screen / animation intent
TAKEAWAY           what the viewer should remember
```

For a **viewer-facing film**, wrap that block in Media Studio `story-craft.md`:

```text
Question → Stakes → Wrong intuition → Complication → Reveal → Demonstration → Implication → Takeaway
```

Do not ship the comprehension block as sequential slides. The film still needs tension and a reveal.

## Rules

1. Name the concept in one sentence the viewer can reuse at work.
2. Prefer show-then-tell: point to a visual plan before dense prose.
3. Define jargon once; then use it consistently.
4. Separate FACT (observed) from DRAMATIZED / COMPOSITE (storytelling).
5. Do not invent product behavior; if evidence is missing, say so.

## Outputs

- Explanation block (markdown)
- Optional `visual_plan` notes for `technical-visualizer`
- Optional companion bullets for docs / learning cards

After the visual plan exists, compose the film through `media-studio` (kind
`explainer`, viewer-facing engagement). Do not load retired `product-demo*` skills.

## Non-goals

- Not series continuity, privacy fictionalization, or Remotion implementation.
- Request capability `video.programmatic-composition` when animation is needed;
  resolve Remotion through thirdPartyExtensions, do not vendor it here.
