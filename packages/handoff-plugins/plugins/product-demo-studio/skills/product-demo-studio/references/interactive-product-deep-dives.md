# Interactive product deep-dives

Use this derivative only when the requested deliverable is a role-routed interactive walkthrough,
not for every product video. Product Demo Studio owns the truthful media, claim evidence, scene
contract, and immutable review package. Product Experience Engineering or the target repository's
frontend owner implements the page in that repository's native stack.

## What is worth preserving

- Route two to four meaningful personas through one operational narrative. Reuse shared scenes;
  do not produce disconnected role-specific feature tours.
- Give each scene a stable deep link, visible journey position, relevant role set, interactive
  proof asset, evidence references, and an outcome-oriented next step.
- Prefer short verified loops, evidence-backed hotspots, or a synthetic isolated sandbox. Always
  include keyboard-accessible controls, a poster/fallback, reduced-motion behavior, and lazy
  loading.
- Put the trust/control moment next to the automation it governs. For AI, show source classes,
  a user-facing confidence label when the product really emits one, limitations, and the actual
  human control. Never expose or fabricate private chain-of-thought.
- Show a quantified impact only when the claim ledger points to approved evidence. A section with
  no defensible metric stays qualitative.
- Instrument role selection, scene views, proof interaction, and CTA use so drop-off can drive the
  next revision.

## Rejected absolutes

- A static poster is not a failure when it is the accessible, reduced-motion, low-bandwidth, or
  error fallback for an interactive primary proof.
- A live iframe is not required. Use it only in an authorized synthetic environment with isolation,
  reset behavior, and no external side effects.
- Do not force ten to fifteen scenes when a shorter end-to-end workflow is stronger. The contract
  allows five to fifteen and requires every scene to move the operational story.
- Do not fabricate a metric for every section, keep a CTA over content at every viewport position,
  or label generated prose as system reasoning.

## Contract and handoff

Write `interactive-deep-dive.json` and validate it:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-interactive-deep-dive.mjs" \
  <path-to-interactive-deep-dive.json>
```

Every referenced proof asset must already be bound to the Product Demo Studio claim ledger and
evidence package. The page implementation may begin only after the contract passes. Any media,
claim, product-state, or automation-control change invalidates affected evidence and triggers the
normal candidate, review, arbiter, and final-verifier loop.
