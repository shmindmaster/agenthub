---
name: technical-explainer
description: Use when turning a technical failure, design choice, or system behavior into a structured explanation a viewer can reuse.
---

# Technical explainer

Convert a technical question or incident into this structure:

```text
CORE IDEA          one sentence
PLAIN EXPLANATION  2–4 sentences
ANALOGY            memorable comparison
REAL EXAMPLE       what actually happened (FACT-tagged)
MISCONCEPTION      what people commonly get wrong
VISUAL PLAN        diagram / screen / animation intent
TAKEAWAY           what the viewer should remember
```

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

## Non-goals

- Not series continuity, privacy fictionalization, or Remotion implementation.
- Request capability `video.programmatic-composition` when animation is needed;
  resolve Remotion through thirdPartyExtensions, do not vendor it here.
